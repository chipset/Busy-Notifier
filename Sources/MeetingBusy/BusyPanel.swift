import AppKit
import MeetingDetection

@MainActor
final class BusyPanel {
    private var indicators: [UInt32: IndicatorWindow] = [:]
    var onMove: ((CGPoint, CGRect, UInt32) -> Void)?
    var onKeyboardMove: (() -> Void)?
    /// Minutes to hide for, or nil to hide until the user returns to Automatic.
    var onHide: ((Int?) -> Void)?

    func update(visible: Bool, appearance: IndicatorAppearance = IndicatorAppearance(), accessibilityStatus: String = "Status indicator") {
        guard visible else { for indicator in indicators.values { indicator.hide() }; return }
        let screens: [NSScreen]
        if appearance.allDisplays { screens = NSScreen.screens.filter { appearance.isVisible(on: $0.displayID) } }
        else { screens = (NSScreen.screens.first(where: { $0.displayID == appearance.displayID }) ?? NSScreen.screens.first).map { [$0] } ?? [] }
        let activeIDs = Set(screens.map(\.displayID))
        for id in Array(indicators.keys) where !activeIDs.contains(id) {
            indicators[id]?.discard()
            indicators.removeValue(forKey: id)
        }
        for screen in screens {
            let indicator = indicators[screen.displayID] ?? IndicatorWindow()
            indicator.onMove = { [weak self] origin, bounds, id in self?.onMove?(origin, bounds, id) }
            indicator.onKeyboardMove = { [weak self] in self?.onKeyboardMove?() }
            indicator.onHide = { [weak self] minutes in self?.onHide?(minutes) }
            indicators[screen.displayID] = indicator
            indicator.update(appearance: appearance, screen: screen, accessibilityStatus: accessibilityStatus)
        }
    }
}

@MainActor
private final class IndicatorWindow {
    private let panel: NSPanel
    private var isDragging = false
    var onMove: ((CGPoint, CGRect, UInt32) -> Void)?
    var onKeyboardMove: (() -> Void)?
    var onHide: ((Int?) -> Void)?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 168, height: 82),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        let view = BusyView(frame: NSRect(x: 0, y: 0, width: 168, height: 82))
        view.onDragStarted = { [weak self] in self?.isDragging = true }
        view.onDragFinished = { [weak self] in self?.saveDraggedPosition() }
        view.onKeyboardMove = { [weak self] in self?.onKeyboardMove?() }
        view.onHide = { [weak self] minutes in self?.onHide?(minutes) }
        panel.contentView = view
    }

    func hide() {
        isDragging = false
        (panel.contentView as? BusyView)?.cancelMove()
        panel.orderOut(nil)
    }

    func discard() { hide(); panel.close() }

    func update(appearance: IndicatorAppearance, screen: NSScreen, accessibilityStatus: String) {
        let settings = appearance.normalized
        // Meeting polls may update the appearance while dragging; do not snap back to the saved position.
        if !isDragging { panel.setFrame(settings.frame(in: screen.visibleFrame, displayID: screen.displayID), display: true) }
        panel.alphaValue = 1 - settings.transparency
        (panel.contentView as? BusyView)?.text = settings.text
        (panel.contentView as? BusyView)?.color = settings.color
        panel.contentView?.setAccessibilityLabel(settings.text + ". " + accessibilityStatus)
        panel.contentView?.needsDisplay = true
        panel.orderFrontRegardless()
    }

    private func saveDraggedPosition() {
        isDragging = false
        let frame = panel.frame
        let screens = NSScreen.screens
        // Prefer the display containing most of the indicator, including displays left/below the main one.
        let screen = screens.max { left, right in
            let a = frame.intersection(left.frame)
            let b = frame.intersection(right.frame)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        }
        guard let screen else { return }
        onMove?(frame.origin, screen.visibleFrame, screen.displayID)
    }
}

private final class BusyView: NSView {
    var onDragStarted: (() -> Void)?
    var onDragFinished: (() -> Void)?
    var onKeyboardMove: (() -> Void)?
    var onHide: ((Int?) -> Void)?
    private var moveEnabled = false
    private var dragStart: CGPoint?
    private var originalOrigin: CGPoint?
    var color = IndicatorColor.busyRed { didSet { if color != oldValue { needsDisplay = true } } }
    var text = "Busy" {
        didSet {
            guard text != oldValue else { return }
            needsDisplay = true
        }
    }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityLabel("Busy. Status indicator.")
        setAccessibilityRole(.staticText)
        setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "Move indicator using keyboard", target: self, selector: #selector(accessibilityKeyboardMove)),
                                       NSAccessibilityCustomAction(name: "Hide indicator until Automatic", target: self, selector: #selector(accessibilityHide))])
        toolTip = "Right-click to move or hide the indicator."
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let item = NSMenuItem(title: moveEnabled ? "Cancel move" : "Move indicator", action: #selector(toggleMove), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        let keyboard = NSMenuItem(title: "Move using keyboard…", action: #selector(moveUsingKeyboard), keyEquivalent: "")
        keyboard.target = self
        menu.addItem(keyboard)
        menu.addItem(.separator())
        for (title, minutes) in [("Hide for 15 minutes", 15), ("Hide for 1 hour", 60), ("Hide until I choose Automatic", 0)] {
            let hide = NSMenuItem(title: title, action: #selector(hideIndicator(_:)), keyEquivalent: "")
            hide.target = self
            hide.tag = minutes
            menu.addItem(hide)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func hideIndicator(_ sender: NSMenuItem) { cancelMove(); onHide?(sender.tag > 0 ? sender.tag : nil) }
    @objc private func accessibilityHide() -> Bool {
        guard onHide != nil else { return false }
        hideIndicator(NSMenuItem(title: "", action: nil, keyEquivalent: ""))
        return true
    }

    @objc private func moveUsingKeyboard() { cancelMove(); onKeyboardMove?() }
    @objc private func accessibilityKeyboardMove() -> Bool {
        guard onKeyboardMove != nil else { return false }
        moveUsingKeyboard()
        return true
    }

    @objc private func toggleMove() {
        moveEnabled.toggle()
        toolTip = moveEnabled ? "Drag the indicator, then release to save its location." : "Right-click to move or hide the indicator."
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: moveEnabled ? .openHand : .arrow)
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        guard moveEnabled, let window else { return }
        dragStart = NSEvent.mouseLocation
        originalOrigin = window.frame.origin
        onDragStarted?()
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let origin = originalOrigin else { return }
        let location = NSEvent.mouseLocation
        window?.setFrameOrigin(CGPoint(x: origin.x + location.x - start.x, y: origin.y + location.y - start.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        cancelMove()
        onDragFinished?()
    }

    func cancelMove() {
        dragStart = nil
        originalOrigin = nil
        moveEnabled = false
        toolTip = "Right-click to move or hide the indicator."
        window?.invalidateCursorRects(for: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        let fill = color.normalized
        NSColor(srgbRed: fill.red, green: fill.green, blue: fill.blue, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        let message = text as NSString
        let scale = min(bounds.width / 168, bounds.height / 82)
        let available = bounds.insetBy(dx: 12 * scale, dy: 10 * scale)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        var lower: CGFloat = 0.1
        var upper: CGFloat = 34 * scale
        // Fit both multiword messages and unbroken strings without changing the box's size.
        for _ in 0..<12 {
            let candidate = (lower + upper) / 2
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: candidate, weight: .bold), .paragraphStyle: paragraph]
            let measured = message.boundingRect(with: NSSize(width: available.width, height: .greatestFiniteMagnitude), options: options, attributes: attributes)
            if measured.width <= available.width && measured.height <= available.height { lower = candidate }
            else { upper = candidate }
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: lower, weight: .bold), .foregroundColor: fill.prefersDarkText ? NSColor.black : NSColor.white, .paragraphStyle: paragraph
        ]
        let size = message.boundingRect(with: NSSize(width: available.width, height: .greatestFiniteMagnitude), options: options, attributes: attributes).size
        message.draw(with: NSRect(x: available.minX, y: bounds.midY - size.height / 2, width: available.width, height: size.height), options: options, attributes: attributes)
    }
}
