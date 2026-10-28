import AppKit
import SwiftUI
import MeetingDetection

enum BridgeBrowser: String, CaseIterable {
    case safari = "Safari", chrome = "Google Chrome", edge = "Microsoft Edge", brave = "Brave", chromium = "Chromium", firefox = "Firefox"
    var relativeHostsDirectory: String {
        switch self {
        case .safari: ""
        case .chrome: "Google/Chrome/NativeMessagingHosts"
        case .edge: "Microsoft Edge/NativeMessagingHosts"
        case .brave: "BraveSoftware/Brave-Browser/NativeMessagingHosts"
        case .chromium: "Chromium/NativeMessagingHosts"
        case .firefox: "Mozilla/NativeMessagingHosts"
        }
    }
    var extensionFolder: String { self == .safari ? "safari-temporary" : (self == .firefox ? "firefox" : "chromium") }
}

private struct ExtensionIdentity: Decodable { var chromiumID: String; var firefoxID: String }

@MainActor
final class BrowserBridgeController: ObservableObject {
    @Published var browser = BridgeBrowser.safari
    @Published private(set) var status = "Browser integration is off."
    @Published private(set) var setupStatus = "Choose your browser and enable its extension."
    private(set) var connected = false
    private(set) var lastObservedAt: Date?
    @Published private(set) var safariStatus = "Safari bridge is off."
    /// Called on the main actor when the Safari extension posts fresh state, so the indicator updates without waiting for the next poll.
    var onSafariUpdate: (() -> Void)?
    /// True once a browser connection was seen this session and has since gone quiet.
    private(set) var lostConnection = false
    private var everConnected = false
    private var lastPrune = Date.distantPast
    private var safariServer: SafariBridgeServer?
    private let pairing = SafariPairingCoordinator()
    private var configuration: BrowserBridgePolicy?
    private let store = BrowserBridgeStore(directory: BrowserBridgeStore.defaultDirectory)

    func configure(enabled: Bool, paused: Bool, services: Set<MeetingService>) {
        let policy = BrowserBridgePolicy(enabled: enabled, paused: paused, services: services)
        guard policy != configuration else { return }
        configuration = policy
        connected = false
        lostConnection = false
        everConnected = false
        lastObservedAt = nil
        store.clearSnapshots()
        do { try store.writePolicy(policy) }
        catch { configuration = nil; status = "Local browser bridge storage is unavailable."; return }
        if enabled, safariServer == nil {
            if let url = Bundle.main.resourceURL?.appendingPathComponent("SafariBridge.json"),
               let data = try? Data(contentsOf: url),
               let settings = try? JSONDecoder().decode(SafariBridgeConfiguration.self, from: data) {
                do {
                    pairing.onPrompt = { [weak self] origin in Task { @MainActor in self?.confirmPairing(origin: origin) } }
                    safariServer = try SafariBridgeServer(configuration: settings, pairingToken: pairingToken, pairing: pairing, store: store, onStatus: { [weak self] message in
                        Task { @MainActor in self?.safariStatus = message }
                    }, onUpdate: { [weak self] in Task { @MainActor in self?.onSafariUpdate?() } })
                } catch { safariStatus = "Could not start the Safari bridge. Quit other copies of Meeting Busy and try again." }
            } else { safariStatus = "This build does not include the Safari bridge. Use the packaged app." }
        } else if !enabled { safariServer?.stop(); safariServer = nil; safariStatus = "Safari bridge is off." }
        status = !enabled ? "Browser integration is off." : (paused ? "Browser detection is paused." : "Waiting for a browser extension connection…")
    }

    func evidence() -> [MeetingEvidence] {
        guard let policy = configuration, policy.enabled, !policy.paused, !policy.services.isEmpty else { return [] }
        if Date().timeIntervalSince(lastPrune) > 60 { lastPrune = Date(); store.pruneSnapshots() }
        let snapshots = store.freshSnapshots()
        connected = !snapshots.isEmpty
        if connected { everConnected = true }
        lostConnection = everConnected && !connected
        lastObservedAt = snapshots.map(\.receivedAt).max()
        let evidence = BrowserBridgeStore.evidence(from: snapshots, policy: policy)
        status = connected ? "\(snapshots.count) browser connection(s), \(evidence.count) active meeting service(s)."
            : (lostConnection ? "The browser extension stopped reporting. Safari removes temporary extensions on quit or after 24 hours; add it again and pair."
               : "No browser connection. Install the bridge and connect the extension.")
        return evidence
    }

    private var pairingToken: String? { SafariPairingToken.loadOrCreate(directory: store.directory) }

    private func confirmPairing(origin: String) {
        let alert = NSAlert()
        alert.messageText = "Allow a Safari extension to connect?"
        alert.informativeText = "A Safari extension asked to send meeting and screen-sharing state to Meeting Busy. Allow it only if you just added “Meeting Busy (Temporary)” in Safari yourself.\n\nExtension ID: \(origin.replacingOccurrences(of: "safari-web-extension://", with: ""))"
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don’t Allow")
        NSApp.activate(ignoringOtherApps: true)
        let approved = alert.runModal() == .alertFirstButtonReturn
        pairing.resolve(origin: origin, approve: approved)
        safariStatus = approved ? "Safari extension approved." : "Safari extension request was declined."
    }

    private var applicationSupport: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first! }
    private var installedExtension: URL { applicationSupport.appendingPathComponent("MeetingBusy/BrowserExtension/\(browser.extensionFolder)", isDirectory: true) }
    private var hostManifest: URL { applicationSupport.appendingPathComponent(browser.relativeHostsDirectory, isDirectory: true).appendingPathComponent("local.meetingbusy.browser.json") }

    func install() {
        if browser == .safari { installSafariTemporary(); return }
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
        if browser == .safari { setupStatus = "Remove Meeting Busy (Temporary) in Safari Settings → Extensions."; return }
        do {
            if FileManager.default.fileExists(atPath: hostManifest.path) { try FileManager.default.removeItem(at: hostManifest) }
            setupStatus = "Removed the \(browser.rawValue) bridge entry. Remove the extension in the browser separately if desired."
        } catch { setupStatus = "The selected browser bridge could not be removed." }
    }

    private func installSafariTemporary() {
        guard let source = Bundle.main.resourceURL?.appendingPathComponent("BrowserExtension/safari-temporary"),
              FileManager.default.fileExists(atPath: source.appendingPathComponent("manifest.json").path) else {
            setupStatus = "Use the updated Meeting Busy.app with Safari temporary-extension support."; return
        }
        do {
            let manager = FileManager.default
            try manager.createDirectory(at: installedExtension, withIntermediateDirectories: true)
            for file in try manager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                let destination = installedExtension.appendingPathComponent(file.lastPathComponent)
                if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
                try manager.copyItem(at: file, to: destination)
            }
            setupStatus = "In Safari Settings → Developer, choose Add Temporary Extension and select this folder. Then copy a pairing code below and paste it into the extension popup. Safari removes temporary extensions on quit or after 24 hours."
            NSWorkspace.shared.open(installedExtension)
        } catch { setupStatus = "Could not prepare the Safari extension folder. Try opening the packaged app from Applications." }
    }

    func copySafariPairingCode() {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("SafariBridge.json"),
              let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(SafariBridgeConfiguration.self, from: data),
              let token = pairingToken else {
            setupStatus = "This build has no Safari pairing configuration."; return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(settings.port):\(token)", forType: .string)
        setupStatus = "Pairing code copied. Paste it only into the Meeting Busy (Temporary) extension popup and choose Pair with the Mac app. Keep browser integration on."
    }

    func openExtensionFolder() {
        if browser == .safari { installSafariTemporary(); return }
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
            if bridge.browser == .safari {
                HStack {
                    Button("Open Safari extension folder") { bridge.install() }
                    Button("Copy pairing code (manual)") { features.browserIntegrationEnabled = true; bridge.copySafariPairingCode() }
                }
                Text("Safari Settings → Developer → Add Temporary Extension: select the opened folder, allow supported sites, then choose Pair automatically in the extension popup and click Allow when Meeting Busy asks. No certificate is required. Safari removes this extension on quit or after 24 hours.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(bridge.safariStatus).font(.caption).foregroundStyle(.secondary)
            } else { HStack {
                Button("Install/update bridge") { bridge.install() }
                Button("Open extension folder") { bridge.openExtensionFolder() }
            }
            }
            Button(bridge.browser == .safari ? "Turn browser integration off" : "Remove selected bridge and turn integration off") { features.browserIntegrationEnabled = false; bridge.remove() }
            Text(bridge.setupStatus).font(.caption).foregroundStyle(.secondary)
            Text(bridge.status).font(.caption).foregroundStyle(.secondary)
            Text("Chrome/Edge/Brave/Chromium: load the folder as an unpacked extension. Firefox: temporary add-on loading requires reloading after a browser restart. Safari: load the temporary extension in Developer settings and pair with the Mac app. Accessibility remains a fallback.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
