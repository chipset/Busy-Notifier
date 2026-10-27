import AppKit
import SwiftUI
import MeetingDetection

enum BridgeBrowser: String, CaseIterable {
    case chrome = "Google Chrome", edge = "Microsoft Edge", brave = "Brave", chromium = "Chromium", firefox = "Firefox"
    var relativeHostsDirectory: String {
        switch self {
        case .chrome: "Google/Chrome/NativeMessagingHosts"
        case .edge: "Microsoft Edge/NativeMessagingHosts"
        case .brave: "BraveSoftware/Brave-Browser/NativeMessagingHosts"
        case .chromium: "Chromium/NativeMessagingHosts"
        case .firefox: "Mozilla/NativeMessagingHosts"
        }
    }
    var extensionFolder: String { self == .firefox ? "firefox" : "chromium" }
}

private struct ExtensionIdentity: Decodable { var chromiumID: String; var firefoxID: String }

@MainActor
final class BrowserBridgeController: ObservableObject {
    @Published var browser = BridgeBrowser.chrome
    @Published private(set) var status = "Browser integration is off."
    @Published private(set) var setupStatus = "Install a bridge entry, then load the extension into your browser."
    private(set) var connected = false
    private(set) var lastObservedAt: Date?
    private var configuration: BrowserBridgePolicy?
    private let store = BrowserBridgeStore(directory: BrowserBridgeStore.defaultDirectory)

    func configure(enabled: Bool, paused: Bool, services: Set<MeetingService>) {
        let policy = BrowserBridgePolicy(enabled: enabled, paused: paused, services: services)
        guard policy != configuration else { return }
        configuration = policy
        connected = false
        lastObservedAt = nil
        store.clearSnapshots()
        do { try store.writePolicy(policy) }
        catch { configuration = nil; status = "Local browser bridge storage is unavailable."; return }
        status = !enabled ? "Browser integration is off." : (paused ? "Browser detection is paused." : "Waiting for a browser extension connection…")
    }

    func evidence() -> [MeetingEvidence] {
        guard let policy = configuration, policy.enabled, !policy.paused, !policy.services.isEmpty else { return [] }
        let snapshots = store.freshSnapshots()
        connected = !snapshots.isEmpty
        lastObservedAt = snapshots.map(\.receivedAt).max()
        let evidence = BrowserBridgeStore.evidence(from: snapshots, policy: policy)
        status = connected ? "\(snapshots.count) browser connection(s), \(evidence.count) active meeting service(s)." : "No browser connection. Install the bridge and connect the extension."
        return evidence
    }

    private var applicationSupport: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first! }
    private var installedExtension: URL { applicationSupport.appendingPathComponent("MeetingBusy/BrowserExtension/\(browser.extensionFolder)", isDirectory: true) }
    private var hostManifest: URL { applicationSupport.appendingPathComponent(browser.relativeHostsDirectory, isDirectory: true).appendingPathComponent("local.meetingbusy.browser.json") }

    func install() {
        guard let executable = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("MeetingBusyBrowserHost"),
              FileManager.default.isExecutableFile(atPath: executable.path),
              let resources = Bundle.main.resourceURL?.appendingPathComponent("BrowserExtension"),
              let data = try? Data(contentsOf: resources.appendingPathComponent("identity.json")),
              let identity = try? JSONDecoder().decode(ExtensionIdentity.self, from: data) else {
            setupStatus = "Use the packaged Meeting Busy.app to install browser integration."
            return
        }
        do {
            let manager = FileManager.default
            try manager.createDirectory(at: installedExtension, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let source = resources.appendingPathComponent(browser.extensionFolder)
            for file in try manager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                let destination = installedExtension.appendingPathComponent(file.lastPathComponent)
                if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
                try manager.copyItem(at: file, to: destination)
            }
            var manifest: [String: Any] = ["name": "local.meetingbusy.browser", "description": "Local Meeting Busy state bridge", "path": executable.path, "type": "stdio"]
            if browser == .firefox { manifest["allowed_extensions"] = [identity.firefoxID] }
            else { manifest["allowed_origins"] = ["chrome-extension://\(identity.chromiumID)/"] }
            try manager.createDirectory(at: hostManifest.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: hostManifest, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: hostManifest.path)
            setupStatus = "Installed for \(browser.rawValue). Open the extension folder, then load it in your browser. After an update, reload the extension."
        } catch { setupStatus = "Bridge setup failed (error \((error as NSError).code)). Keep the app in Applications and try again." }
    }

    func remove() {
        do {
            if FileManager.default.fileExists(atPath: hostManifest.path) { try FileManager.default.removeItem(at: hostManifest) }
            setupStatus = "Removed the \(browser.rawValue) bridge entry. Remove the extension in the browser separately if desired."
        } catch { setupStatus = "The selected browser bridge could not be removed." }
    }

    func openExtensionFolder() {
        guard FileManager.default.fileExists(atPath: installedExtension.path) else { setupStatus = "Install the selected browser's bridge first."; return }
        NSWorkspace.shared.open(installedExtension)
    }
}

struct BrowserIntegrationSettings: View {
    @ObservedObject var features: FeatureSettings
    @ObservedObject var bridge: BrowserBridgeController
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("Browser integration").font(.headline)
            Toggle("Use browser extension meeting detection", isOn: $features.browserIntegrationEnabled)
            Text("Detects calls in inactive tabs through a local native bridge. Reports only service and call/sharing state; no URLs, titles, names, or chat. Pause and service switches also apply.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Browser", selection: $bridge.browser) {
                ForEach(BridgeBrowser.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            HStack {
                Button("Install/update bridge") { bridge.install() }
                Button("Open extension folder") { bridge.openExtensionFolder() }
            }
            Button("Remove selected bridge and turn integration off") { features.browserIntegrationEnabled = false; bridge.remove() }
            Text(bridge.setupStatus).font(.caption).foregroundStyle(.secondary)
            Text(bridge.status).font(.caption).foregroundStyle(.secondary)
            Text("Chrome/Edge/Brave/Chromium: load the folder as an unpacked extension. Firefox: temporary add-on loading requires reloading after a browser restart. Safari continues to use Accessibility detection.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
