import AppKit
import SwiftUI
import MeetingDetection

@MainActor
final class FeatureSettings: ObservableObject {
    @Published var shortcutsEnabled = UserDefaults.standard.bool(forKey: "shortcutsEnabled") {
        didSet { UserDefaults.standard.set(shortcutsEnabled, forKey: "shortcutsEnabled"); onChange?() }
    }
    @Published var presentationReminders = UserDefaults.standard.bool(forKey: "presentationReminders") {
        didSet { UserDefaults.standard.set(presentationReminders, forKey: "presentationReminders"); onChange?() }
    }
    @Published var reminderMinutes = UserDefaults.standard.integer(forKey: "reminderMinutes") == 0 ? 15 : UserDefaults.standard.integer(forKey: "reminderMinutes") {
        didSet { UserDefaults.standard.set(reminderMinutes, forKey: "reminderMinutes"); onChange?() }
    }
    @Published var automaticUpdateChecks = UserDefaults.standard.bool(forKey: "automaticUpdateChecks") {
        didSet { UserDefaults.standard.set(automaticUpdateChecks, forKey: "automaticUpdateChecks"); onChange?() }
    }
    @Published var updateNotifications = UserDefaults.standard.bool(forKey: "updateNotifications") {
        didSet { UserDefaults.standard.set(updateNotifications, forKey: "updateNotifications"); onChange?() }
    }
    @Published var shortcutStatus = "Keyboard shortcuts are off."
    var onChange: (() -> Void)?
}

@MainActor
final class DiagnosticsController: ObservableObject {
    @Published var mode: LoggingMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "loggingMode") }
    }
    @Published var status = "Logs stay on this Mac."
    private let store: DiagnosticLogStore

    init() {
        mode = LoggingMode(rawValue: UserDefaults.standard.string(forKey: "loggingMode") ?? "") ?? .events
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        store = DiagnosticLogStore(directory: library.appendingPathComponent("Logs/MeetingBusy", isDirectory: true))
    }

    func record(_ entry: DiagnosticEntry) {
        guard mode != .off, entry.event != .scan || mode == .verbose else { return }
        do { try store.append(entry); status = "Logs stay on this Mac (up to 2 MB)." }
        catch { status = "Could not write the diagnostic log (error \((error as NSError).code))." }
    }

    func openFolder() {
        do {
            try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            NSWorkspace.shared.open(store.directory)
        } catch { status = "Could not open the log folder." }
    }

    func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MeetingBusy-diagnostics.jsonl"
        panel.title = "Export local diagnostic logs"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.exportData().write(to: url, options: .atomic); status = "Diagnostic logs exported." }
        catch { status = "Could not export diagnostic logs." }
    }

    func clear() {
        do { try store.clear(); status = "Diagnostic logs cleared." }
        catch { status = "Could not clear diagnostic logs." }
    }
}

private struct ReleaseResponseError: Error { let status: Int }

@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var status = "Updates have not been checked."
    @Published private(set) var availableVersion: String?
    @Published private(set) var releaseURL: URL?
    @Published private(set) var isChecking = false
    var onChange: (() -> Void)?
    var onAvailable: ((String) -> Void)?
    var onResult: ((DiagnosticEvent, Int?) -> Void)?
    private var lastAttempt = UserDefaults.standard.object(forKey: "lastUpdateAttempt") as? Date

    func checkIfDue(enabled: Bool) {
        guard enabled, !isChecking, lastAttempt == nil || Date().timeIntervalSince(lastAttempt!) >= 24 * 60 * 60 else { return }
        check()
    }

    func check() {
        guard !isChecking else { return }
        isChecking = true
        lastAttempt = Date()
        UserDefaults.standard.set(lastAttempt, forKey: "lastUpdateAttempt")
        status = "Checking GitHub Releases…"
        onChange?()
        Task {
            defer { isChecking = false; onChange?() }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/chipset/Busy-Notifier/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("MeetingBusy", forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await session.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if code == 404 {
                    availableVersion = nil; releaseURL = nil
                    status = "No published GitHub release is available yet."
                    onResult?(.updateCheck, code)
                    return
                }
                guard code == 200 else { throw ReleaseResponseError(status: code) }
                let release = try JSONDecoder().decode(PublishedRelease.self, from: data)
                let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
                guard let latestVersion = ReleaseVersion(release.tagName), let currentVersion = ReleaseVersion(current), !release.draft, !release.prerelease else { throw ReleaseResponseError(status: -1) }
                if latestVersion > currentVersion {
                    guard let url = release.updateURL(currentVersion: current) else { throw ReleaseResponseError(status: -1) }
                    availableVersion = release.tagName; releaseURL = url
                    status = "Update available: \(release.tagName)."
                    onResult?(.updateAvailable, nil)
                    onAvailable?(release.tagName)
                } else {
                    availableVersion = nil; releaseURL = nil
                    status = "You are up to date (checked \(Date().formatted(date: .omitted, time: .shortened)))."
                    onResult?(.updateCheck, nil)
                }
            } catch {
                status = "Update check failed. Check your connection and try again."
                onResult?(.updateFailed, (error as? ReleaseResponseError)?.status ?? (error as NSError).code)
            }
        }
    }

    func openRelease() {
        if let releaseURL { NSWorkspace.shared.open(releaseURL) }
    }
}

struct FeatureSettingsView: View {
    @ObservedObject var features: FeatureSettings
    @ObservedObject var diagnostics: DiagnosticsController
    @ObservedObject var updates: UpdateChecker
    @ObservedObject var notifications: NotificationController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            Text("Keyboard shortcuts").font(.headline)
            Toggle("Enable global shortcuts", isOn: $features.shortcutsEnabled)
            Text("⌃⌥⌘1 Automatic · ⌃⌥⌘2 Busy · ⌃⌥⌘3 Presenting").font(.caption)
            Text(features.shortcutStatus).font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Presentation reminders").font(.headline)
            Toggle("Remind me to return to Automatic", isOn: $features.presentationReminders)
            Picker("Remind after", selection: $features.reminderMinutes) {
                ForEach([5, 10, 15, 30, 60], id: \.self) { Text("\($0) minutes").tag($0) }
            }
            Text("A reminder does not turn the indicator back on. Presenting remains visible in the menu bar until you change modes.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Diagnostic logging").font(.headline)
            Picker("Record", selection: $diagnostics.mode) {
                ForEach(LoggingMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Text("Local only. No meeting titles, names, chat, URLs, or indicator text. Old entries rotate automatically.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Open log folder") { diagnostics.openFolder() }
                Button("Export…") { diagnostics.export() }
                Button("Clear logs") { diagnostics.clear() }
            }
            Text(diagnostics.status).font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Updates").font(.headline)
            Toggle("Check GitHub for updates daily", isOn: $features.automaticUpdateChecks)
            Toggle("Notify when an update is available", isOn: $features.updateNotifications)
            Text("Checks contact GitHub's public release API. Updates open in your browser; downloads and installation are manual.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Check now") { updates.check() }.disabled(updates.isChecking)
                if updates.releaseURL != nil { Button("View release") { updates.openRelease() } }
            }
            Text(updates.status).font(.caption).foregroundStyle(.secondary)
            Text(notifications.status).font(.caption).foregroundStyle(.secondary)
        }
    }
}
