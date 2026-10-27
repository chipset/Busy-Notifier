import AppKit
import SwiftUI
import MeetingDetection

@MainActor
final class AppearanceStore: ObservableObject {
    @Published var appearance: IndicatorAppearance {
        didSet {
            if let data = try? JSONEncoder().encode(appearance.normalized) {
                UserDefaults.standard.set(data, forKey: "indicatorAppearance")
            }
            onChange?()
        }
    }
    @Published var detectionStatus = "Checking meeting applications…"
    @Published var detectionDetails = "Waiting for the first scan."
    @Published var showPreview = false { didSet { onChange?() } }
    var onChange: (() -> Void)?

    init() {
        if let data = UserDefaults.standard.data(forKey: "indicatorAppearance"),
           let saved = try? JSONDecoder().decode(IndicatorAppearance.self, from: data) {
            appearance = saved.normalized
        } else { appearance = IndicatorAppearance() }
    }
}

@MainActor
final class SettingsController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let store: AppearanceStore

    init(store: AppearanceStore) {
        self.store = store
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 650),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Meeting Busy Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView(store: store))
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { store.showPreview = false }
}

private struct SettingsView: View {
    @ObservedObject var store: AppearanceStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Busy indicator").font(.title2.bold())
                Text("Changes save automatically and apply immediately.").foregroundStyle(.secondary)
                TextField("Indicator text", text: $store.appearance.text, prompt: Text("Busy"))
                    .textFieldStyle(.roundedBorder)
                Text("Leave blank to use Busy. Longer messages automatically fit the box.")
                    .font(.caption).foregroundStyle(.secondary)
                ColorPicker("Indicator color", selection: Binding(
                    get: {
                        let color = store.appearance.color.normalized
                        return Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: 1)
                    },
                    set: { selection in
                        guard let color = NSColor(selection).usingColorSpace(.sRGB) else { return }
                        store.appearance.color = IndicatorColor(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent)
                    }), supportsOpacity: false)
                Text("Text switches between white and black for readability.")
                    .font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading) {
                    Text("Size: \(Int(store.appearance.scale * 100))%")
                    Slider(value: $store.appearance.scale, in: 0.5...2.5, step: 0.05)
                        .accessibilityLabel("Indicator size")
                    Text("Transparency: \(Int((store.appearance.transparency * 100).rounded()))%")
                    Slider(value: $store.appearance.transparency, in: 0...0.9, step: 0.05)
                        .accessibilityLabel("Indicator transparency")
                    Text("0% is solid; 90% is almost transparent.").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Location").font(.headline)
                    Text("You can also right-click the indicator, choose Move indicator, then drag it. Release to save.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Display", selection: $store.appearance.displayID) {
                        Text("Main display").tag(nil as UInt32?)
                        ForEach(NSScreen.screens, id: \.displayID) { screen in
                            Text(screen.localizedName).tag(screen.displayID as UInt32?)
                        }
                    }
                    HStack {
                        position("Top left", x: 0, y: 0)
                        position("Top right", x: 1, y: 0)
                        position("Center", x: 0.5, y: 0.5)
                    }
                    HStack {
                        position("Bottom left", x: 0, y: 1)
                        position("Bottom right", x: 1, y: 1)
                    }
                    Text("Horizontal: \(Int(store.appearance.x * 100))% from left")
                    Slider(value: $store.appearance.x, in: 0...1, step: 0.01).accessibilityLabel("Horizontal position")
                    Text("Vertical: \(Int(store.appearance.y * 100))% from top")
                    Slider(value: $store.appearance.y, in: 0...1, step: 0.01).accessibilityLabel("Vertical position")
                }
                Toggle("Show indicator preview", isOn: $store.showPreview)
                Text("Preview is manual and stays visible until unchecked or Settings is closed. It stays hidden while presenting.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Restore default appearance") { store.appearance = IndicatorAppearance() }
                Divider()
                Text("Meeting detection").font(.headline)
                Text(store.detectionStatus).font(.callout)
                DisclosureGroup("Detection details") {
                    Text(store.detectionDetails).font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("If access is denied after an update, remove Meeting Busy from Accessibility in System Settings, add this copy again, and reopen it.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(22)
        }.frame(width: 500, height: 650)
    }

    private func position(_ title: String, x: Double, y: Double) -> some View {
        Button(title) {
            var value = store.appearance
            value.x = x
            value.y = y
            store.appearance = value
        }
    }
}

extension NSScreen {
    var displayID: UInt32 { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
}
