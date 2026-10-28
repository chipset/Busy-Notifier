import AppKit
import SwiftUI
import ApplicationServices
import MeetingDetection

@MainActor
final class AppearanceStore: ObservableObject {
    @Published var presets: [AppearancePreset] {
        didSet {
            if let data = try? JSONEncoder().encode(presets) { UserDefaults.standard.set(data, forKey: "appearancePresets") }
            onChange?()
        }
    }
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
    @Published var lastCheckDescription = "No completed scan yet."
    @Published var showPreview = false { didSet { onChange?() } }
    var onChange: (() -> Void)?
    var onKeyboardMove: (() -> Void)?

    init() {
        if let data = UserDefaults.standard.data(forKey: "appearancePresets"),
           let saved = try? JSONDecoder().decode([AppearancePreset].self, from: data) {
            presets = saved.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { AppearancePreset(id: $0.id, name: $0.name, appearance: $0.appearance) }
        } else { presets = AppearancePreset.defaults }
        if let data = UserDefaults.standard.data(forKey: "indicatorAppearance"),
           let saved = try? JSONDecoder().decode(IndicatorAppearance.self, from: data) {
            appearance = saved.normalized
        } else { appearance = IndicatorAppearance() }
    }

    func savePreset(name: String) -> UUID? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if let index = presets.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            let id = presets[index].id
            presets[index] = AppearancePreset(id: id, name: name, appearance: appearance)
            return id
        }
        let preset = AppearancePreset(name: name, appearance: appearance)
        presets.append(preset)
        return preset.id
    }

    func applyPreset(id: UUID) {
        if let preset = presets.first(where: { $0.id == id }) { appearance = preset.appearance.normalized }
    }

    func nudge(dx: CGFloat, dy: CGFloat) {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == appearance.displayID }) ?? NSScreen.screens.first else { return }
        let origin = appearance.frame(in: screen.visibleFrame, displayID: screen.displayID).origin
        appearance = appearance.repositioned(to: CGPoint(x: origin.x + dx, y: origin.y + dy), in: screen.visibleFrame, displayID: screen.displayID)
    }
}

@MainActor
final class SettingsController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let store: AppearanceStore

    init(store: AppearanceStore, features: FeatureSettings, diagnostics: DiagnosticsController, updates: UpdateChecker, notifications: NotificationController, bridge: BrowserBridgeController, light: UsbLightController) {
        self.store = store
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 650),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Meeting Busy Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView(store: store, features: features, diagnostics: diagnostics, updates: updates, notifications: notifications, bridge: bridge, light: light))
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
    let features: FeatureSettings
    let diagnostics: DiagnosticsController
    let updates: UpdateChecker
    let notifications: NotificationController
    let bridge: BrowserBridgeController
    let light: UsbLightController
    @State private var selectedPreset: UUID?
    @State private var presetName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Setup and live test").font(.title2.bold())
                Text("1. Accessibility: \(AXIsProcessTrusted() ? "granted" : "needed for native clients and browser fallback")")
                if !AXIsProcessTrusted() { Button("Grant Accessibility access…") { features.onGrantAccess?() } }
                Text("2. Browser extension (optional): \(bridge.status)")
                Text("Install its bridge and extension in Browser integration below to detect inactive tabs.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("3. Live test")
                Text("Enabled services: \(features.enabledServices.map(\.rawValue).sorted().joined(separator: ", "))")
                Text("Current result: \(store.detectionStatus)")
                Text(store.lastCheckDescription).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Check now") { features.onCheckDetection?() }
                    Button("Preview Busy for 5 seconds") { features.onPreview?() }
                }
                HStack {
                    Button("Test Presenting") { features.onSetMode?(.presenting) }
                    Button("Return to Automatic") { features.onSetMode?(.automatic) }
                }
                Text("For a live test, join a call, select Check now, and confirm the result changes to In a meeting. Start sharing to confirm the indicator hides; stop sharing to confirm it returns.")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                Text("Busy indicator").font(.title2.bold())
                Text("Changes save automatically and apply immediately.").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Appearance preset", selection: $selectedPreset) {
                        Text("Choose a preset").tag(nil as UUID?)
                        ForEach(store.presets) { Text($0.name).tag($0.id as UUID?) }
                    }
                    HStack {
                        Button("Apply preset") { if let selectedPreset { store.applyPreset(id: selectedPreset) } }
                            .disabled(!store.presets.contains(where: { $0.id == selectedPreset }))
                        Button("Delete preset") {
                            store.presets.removeAll { $0.id == selectedPreset }
                            selectedPreset = nil
                        }.disabled(!store.presets.contains(where: { $0.id == selectedPreset }))
                    }
                    TextField("Save current appearance as", text: $presetName, prompt: Text("Preset name"))
                        .textFieldStyle(.roundedBorder)
                    Button("Save preset") {
                        selectedPreset = store.savePreset(name: presetName)
                        presetName = ""
                    }.disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text("Saving with an existing name updates that preset. Presets include placement and display settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
                    Toggle("Show on every display", isOn: $store.appearance.allDisplays)
                    Picker("Display", selection: $store.appearance.displayID) {
                        Text("Main display").tag(nil as UInt32?)
                        ForEach(NSScreen.screens, id: \.displayID) { screen in
                            Text(screen.localizedName).tag(screen.displayID as UInt32?)
                        }
                    }.disabled(store.appearance.allDisplays)
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
                    Button("Move indicator using the keyboard…") { store.onKeyboardMove?() }
                    if store.appearance.allDisplays {
                        DisclosureGroup("Per-display positions and visibility") {
                            ForEach(NSScreen.screens, id: \.displayID) { screen in
                                let placement = placementBinding(for: screen.displayID)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(screen.localizedName).font(.subheadline.bold())
                                    Toggle("Show indicator", isOn: placement.visible)
                                    Text("Horizontal: \(Int(placement.wrappedValue.x * 100))%")
                                    Slider(value: placement.x, in: 0...1, step: 0.01)
                                    Text("Vertical: \(Int(placement.wrappedValue.y * 100))%")
                                    Slider(value: placement.y, in: 0...1, step: 0.01)
                                }.padding(.vertical, 4)
                            }
                        }
                    }
                }
                Toggle("Show indicator preview", isOn: $store.showPreview)
                Text("Preview is manual and stays visible until unchecked or Settings is closed. It stays hidden while Presenting or Available is selected.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Restore default appearance") { store.appearance = IndicatorAppearance() }
                Divider()
                Text("Meeting detection").font(.headline)
                Text(store.detectionStatus).font(.callout)
                Text(store.lastCheckDescription).font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Detection details") {
                    Text(store.detectionDetails).font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("If access is denied after an update, remove Meeting Busy from Accessibility in System Settings, add this copy again, and reopen it.")
                    .font(.caption).foregroundStyle(.secondary)
                FeatureSettingsView(features: features, diagnostics: diagnostics, updates: updates, notifications: notifications)
                BrowserIntegrationSettings(features: features, bridge: bridge)
                UsbLightSettings(features: features, light: light)
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

    private func placementBinding(for id: UInt32) -> Binding<DisplayPlacement> {
        Binding(get: { store.appearance.placement(for: id) }, set: { placement in
            var value = store.appearance
            value.displayPlacements[id] = placement
            store.appearance = value
        })
    }
}

extension NSScreen {
    var displayID: UInt32 { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
}
