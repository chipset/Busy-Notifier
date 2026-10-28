import AppKit

@MainActor
final class KeyboardMovementController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let store: AppearanceStore
    private var ownsPreview = false

    init(store: AppearanceStore) {
        self.store = store
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 235),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Move indicator using the keyboard"
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.isReleasedWhenClosed = false
        window.delegate = self
        let root = KeyboardMovementView(frame: NSRect(x: 0, y: 0, width: 460, height: 235))
        root.onNudge = { [weak self] dx, dy in self?.store.nudge(dx: dx, dy: dy) }
        root.onFinish = { [weak self] in self?.window.close() }
        window.contentView = root
        window.initialFirstResponder = root
        window.center()
    }

    func show() {
        if !window.isVisible {
            ownsPreview = !store.showPreview
            if ownsPreview { store.showPreview = true }
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.contentView)
    }

    func windowWillClose(_ notification: Notification) {
        if ownsPreview { store.showPreview = false }
        ownsPreview = false
    }
}

private final class KeyboardMovementView: NSView {
    var onNudge: ((CGFloat, CGFloat) -> Void)?
    var onFinish: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let heading = NSTextField(labelWithString: "Use arrow keys to move the indicator")
        heading.font = .systemFont(ofSize: 16, weight: .semibold)
        let help = NSTextField(wrappingLabelWithString: "Arrow keys: 10 points · Shift + arrow: 50 points\nOption + arrow: 1 point · Return or Escape: finish\n\nPosition saves after every move. Choose another display in Settings. When showing on every display, each display keeps its own position. Presenting always keeps the indicator hidden.")
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 10
        for (index, title) in ["←", "→", "↓", "↑"].enumerated() {
            let button = NSButton(title: title, target: self, action: #selector(nudge(_:)))
            button.tag = index
            button.setAccessibilityLabel(["Move left", "Move right", "Move down", "Move up"][index])
            buttons.addArrangedSubview(button)
        }
        let done = NSButton(title: "Done", target: self, action: #selector(finish))
        done.keyEquivalent = "\r"
        buttons.addArrangedSubview(done)
        let stack = NSStackView(views: [heading, help, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
                                     stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
                                     stack.centerYAnchor.constraint(equalTo: centerYAnchor)])
        setAccessibilityRole(.group)
        setAccessibilityLabel("Keyboard movement controls")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func keyDown(with event: NSEvent) {
        if [36, 53, 76].contains(event.keyCode) { onFinish?(); return }
        let step: CGFloat = event.modifierFlags.contains(.option) ? 1 : (event.modifierFlags.contains(.shift) ? 50 : 10)
        switch event.keyCode {
        case 123: onNudge?(-step, 0)
        case 124: onNudge?(step, 0)
        case 125: onNudge?(0, -step)
        case 126: onNudge?(0, step)
        default: super.keyDown(with: event)
        }
    }
    override func cancelOperation(_ sender: Any?) { onFinish?() }
    @objc private func nudge(_ sender: NSButton) {
        let deltas: [(CGFloat, CGFloat)] = [(-10, 0), (10, 0), (0, -10), (0, 10)]
        onNudge?(deltas[sender.tag].0, deltas[sender.tag].1)
    }
    @objc private func finish() { onFinish?() }
}
