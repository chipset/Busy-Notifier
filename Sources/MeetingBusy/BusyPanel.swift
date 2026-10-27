import AppKit
import MeetingDetection

@MainActor
final class BusyPanel {
    private let panel: NSPanel

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 168, height: 82),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.contentView = BusyView(frame: NSRect(x: 0, y: 0, width: 168, height: 82))
    }

    func update(visible: Bool, appearance: IndicatorAppearance = IndicatorAppearance()) {
        let settings = appearance.normalized
        guard visible, let screen = NSScreen.screens.first(where: { $0.displayID == settings.displayID }) ?? NSScreen.screens.first else { panel.orderOut(nil); return }
        panel.setFrame(settings.frame(in: screen.visibleFrame), display: true)
        panel.alphaValue = 1 - settings.transparency
        (panel.contentView as? BusyView)?.text = settings.text
        (panel.contentView as? BusyView)?.color = settings.color
        panel.contentView?.needsDisplay = true
        panel.orderFrontRegardless()
    }
}

private final class BusyView: NSView {
    var color = IndicatorColor.busyRed { didSet { if color != oldValue { needsDisplay = true } } }
    var text = "Busy" {
        didSet {
            guard text != oldValue else { return }
            setAccessibilityLabel(text + ". Meeting in progress.")
            needsDisplay = true
        }
    }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityLabel("Busy. Meeting in progress.")
        setAccessibilityRole(.staticText)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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
