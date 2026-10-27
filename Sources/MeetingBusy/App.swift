import AppKit
@preconcurrency import ApplicationServices
import MeetingDetection
import ServiceManagement

@main
enum MeetingBusyApp {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--diagnose") {
            let trusted = AXIsProcessTrusted()
            print("Meeting Busy \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")")
            print("Accessibility access: \(trusted ? "granted" : "denied")")
            guard trusted else { return }
            let targets = NSWorkspace.shared.runningApplications.compactMap { app -> ApplicationTarget? in
                guard let id = app.bundleIdentifier,
                      Detection.nativeService(bundleID: id) != nil || AccessibilityScanner.browserIDs.contains(id) else { return nil }
                return ApplicationTarget(pid: app.processIdentifier, bundleID: id)
            }
            let result = AccessibilityScanner.scan(targets)
            print(result.details.joined(separator: "\n"))
            for item in result.evidence { print("\(item.service.rawValue): \(item.isPresenting ? "presenting" : "in meeting")") }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let panel = BusyPanel()
    private let appearance = AppearanceStore()
    private let features = FeatureSettings()
    private let diagnostics = DiagnosticsController()
    private let updates = UpdateChecker()
    private let notifications = NotificationController()
    private let hotKeys = HotKeyController()
    private lazy var settingsController = SettingsController(store: appearance, features: features, diagnostics: diagnostics, updates: updates, notifications: notifications)
    private var timer: Timer?
    private var scanning = false
    private var tracker = EvidenceTracker()
    private var evidence: [MeetingEvidence] { tracker.evidence }
    private var trusted = false
    private var incomplete = false
    private var manualOverride = ManualOverride()
    private var mode: DisplayMode { manualOverride.mode }
    private var scanGeneration = 0
    private var previewUntil = Date.distantPast
    private var suspended = false
    private var lastLoggedReason: IndicatorReason?
    private var lastLoggedEvidence: [MeetingEvidence] = []
    private var lastTrusted: Bool?
    private var configuredShortcuts: Bool?
    private var notificationConfiguration = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        appearance.onChange = { [weak self] in self?.updateUI() }
        panel.onMove = { [weak self] origin, screen, displayID in
            guard let self else { return }
            self.appearance.appearance = self.appearance.appearance.repositioned(to: origin, in: screen, displayID: displayID)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "person.crop.circle.badge.clock", accessibilityDescription: "Meeting Busy")
        notifications.start()
        notifications.onAutomatic = { [weak self] in self?.changeMode(.automatic) }
        notifications.onOpenRelease = { [weak self] in self?.updates.openRelease() }
        notifications.onError = { [weak self] code in self?.diagnostics.record(DiagnosticEntry(event: .notificationFailed, failureCodes: [code])) }
        hotKeys.onAction = { [weak self] action in
            self?.changeMode(action == .automatic ? .automatic : (action == .busy ? .busy : .presenting))
        }
        features.onChange = { [weak self] in self?.configureFeatures() }
        updates.onChange = { [weak self] in self?.updateUI() }
        updates.onResult = { [weak self] event, code in self?.diagnostics.record(DiagnosticEntry(event: event, failureCodes: code.map { [$0] } ?? [])) }
        updates.onAvailable = { [weak self] version in
            guard let self, self.features.updateNotifications else { return }
            self.notifications.notifyUpdate(version: version)
        }
        trusted = AXIsProcessTrusted()
        diagnostics.record(DiagnosticEntry(event: .launched, trusted: trusted))
        configureFeatures()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        updateUI()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        if !UserDefaults.standard.bool(forKey: "didShowWelcome") {
            UserDefaults.standard.set(true, forKey: "didShowWelcome")
            showWelcome()
        }
        poll()
    }

    private func poll() {
        guard !suspended else { return }
        if manualOverride.expire() {
            changeMode(.automatic, event: .timerExpired, refresh: false)
        }
        if tracker.expire() {
            incomplete = true
            diagnostics.record(DiagnosticEntry(event: .evidenceExpired))
        }
        updates.checkIfDue(enabled: features.automaticUpdateChecks)
        trusted = AXIsProcessTrusted()
        if trusted != lastTrusted {
            lastTrusted = trusted
            diagnostics.record(DiagnosticEntry(event: .permissionChanged, trusted: trusted))
        }
        guard trusted else {
            scanGeneration += 1
            tracker.clear()
            appearance.lastCheckDescription = "Automatic detection is waiting for Accessibility permission."
            appearance.detectionDetails = "Accessibility access is denied.\nUse Grant Accessibility access from the menu.\nIf this app was rebuilt, remove its old Accessibility entry and add this copy again.\nApp: \(Bundle.main.bundlePath)"
            updateUI()
            return
        }
        updateUI()
        guard !scanning else { return }
        scanning = true
        let generation = scanGeneration
        let scanStarted = Date()
        let targets = NSWorkspace.shared.runningApplications.compactMap { app -> ApplicationTarget? in
            guard let id = app.bundleIdentifier,
                  Detection.nativeService(bundleID: id) != nil || AccessibilityScanner.browserIDs.contains(id) else { return nil }
            return ApplicationTarget(pid: app.processIdentifier, bundleID: id)
        }
        Task { [weak self] in
            let result = await AccessibilityScanner.scanConcurrently(targets)
            guard let self else { return }
            self.scanning = false
            guard self.scanGeneration == generation, !self.suspended else { return }
            if Date().timeIntervalSince(scanStarted) >= self.tracker.maximumAge {
                self.tracker.clear()
                self.incomplete = true
                self.appearance.lastCheckDescription = "The last scan took too long; stale evidence was discarded."
                self.diagnostics.record(DiagnosticEntry(event: .scanFailed, incomplete: true,
                                                         scanMilliseconds: Int(Date().timeIntervalSince(scanStarted) * 1000)))
                self.updateUI()
                return
            }
            self.tracker.accept(result.evidence.sorted { ($0.service.rawValue, $0.signal.rawValue, $0.isPresenting ? 1 : 0) < ($1.service.rawValue, $1.signal.rawValue, $1.isPresenting ? 1 : 0) })
            self.incomplete = result.incomplete
            let milliseconds = Int(Date().timeIntervalSince(scanStarted) * 1000)
            self.appearance.lastCheckDescription = "Last check: \(Date().formatted(date: .omitted, time: .standard)) · \(milliseconds) ms\(result.incomplete ? " · incomplete" : "")"
            self.diagnostics.record(DiagnosticEntry(event: result.incomplete ? .scanFailed : .scan, evidence: self.evidence,
                                                     trusted: self.trusted, incomplete: result.incomplete,
                                                     scanMilliseconds: milliseconds, failureCodes: result.failureCodes))
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
            self.appearance.detectionDetails = "Version: \(version)\nApp: \(Bundle.main.bundlePath)\nAccessibility access: granted\n" + result.details.joined(separator: "\n")
            self.updateUI()
        }
    }

    private func updateUI() {
        let previewRequested = appearance.showPreview || Date() < previewUntil
        let reason = IndicatorPolicy.reason(mode: mode, evidence: evidence, trusted: trusted, preview: previewRequested)
        if lastLoggedReason != reason || lastLoggedEvidence != evidence {
            lastLoggedReason = reason
            lastLoggedEvidence = evidence
            diagnostics.record(DiagnosticEntry(event: .stateChanged, state: reason, mode: mode, evidence: evidence, trusted: trusted))
        }
        let presenting = reason == .presenting
        let visible = !suspended && reason.showsIndicator
        panel.update(visible: visible, appearance: appearance.appearance)
        let state: String
        switch reason {
        case .presenting:
            let minutes = Int(Date().timeIntervalSince(manualOverride.startedAt ?? Date()) / 60)
            state = mode == .presenting ? "Presenting — indicator hidden (\(minutes) min)" : "Screen sharing detected — indicator hidden"
        case .forcedBusy:
            state = manualOverride.expiresAt.map { "Busy — until \($0.formatted(date: .omitted, time: .shortened))" } ?? "Busy — manual override"
        case .meeting: state = "In a meeting: " + Set(evidence.map { $0.service.rawValue }).sorted().joined(separator: ", ")
        case .preview: state = trusted ? "Preview — no meeting detected" : "Preview — Accessibility setup needed"
        case .setupNeeded: state = "Setup needed: Accessibility access"
        case .idle: state = incomplete ? "Unable to inspect some meeting windows" : "No active meeting detected"
        }
        appearance.detectionStatus = state
        statusItem.button?.toolTip = "Meeting Busy: " + state
        statusItem.button?.title = mode == .presenting ? " Presenting" : ""
        statusItem.button?.image = NSImage(systemSymbolName: presenting ? "rectangle.on.rectangle.slash" : (visible ? "video.fill" : "video"), accessibilityDescription: state)
        let menu = NSMenu()
        let status = NSMenuItem(title: state, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        let checked = NSMenuItem(title: appearance.lastCheckDescription, action: nil, keyEquivalent: "")
        checked.isEnabled = false
        menu.addItem(checked)
        menu.addItem(.separator())
        for (index, choice) in DisplayMode.allCases.enumerated() {
            let item = NSMenuItem(title: choice.rawValue, action: #selector(setMode(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = choice == mode ? .on : .off
            if features.shortcutsEnabled && features.shortcutStatus == "Global shortcuts are active." {
                item.keyEquivalent = String(index + 1)
                item.keyEquivalentModifierMask = [.control, .option, .command]
            }
            menu.addItem(item)
        }
        let timed = NSMenuItem(title: "Busy for…", action: nil, keyEquivalent: "")
        let durations = NSMenu()
        for minutes in [15, 30, 60] {
            let item = add("\(minutes) minutes", action: #selector(timedBusy(_:)), to: durations)
            item.tag = minutes
        }
        timed.submenu = durations
        menu.addItem(timed)
        menu.addItem(.separator())
        add("Settings…", action: #selector(showSettings), to: menu, key: ",")
        add("Preview Busy for 5 seconds", action: #selector(preview), to: menu)
        if previewRequested { add("Stop preview", action: #selector(stopPreview), to: menu) }
        let update = add(updates.availableVersion.map { "Update available: \($0)…" } ?? "Check for updates…", action: #selector(checkUpdates), to: menu)
        update.isEnabled = !updates.isChecking
        if !updates.isChecking {
            let updateStatus = NSMenuItem(title: updates.status, action: nil, keyEquivalent: "")
            updateStatus.isEnabled = false
            menu.addItem(updateStatus)
        }
        add("Grant Accessibility access…", action: #selector(grantAccess), to: menu)
        let login = add("Launch at login", action: #selector(toggleLogin), to: menu)
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        add("About & setup…", action: #selector(showWelcome), to: menu)
        add("Quit Meeting Busy", action: #selector(quit), to: menu, key: "q")
        statusItem.menu = menu
    }

    @discardableResult private func add(_ title: String, action: Selector, to menu: NSMenu, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func setMode(_ sender: NSMenuItem) {
        changeMode(DisplayMode.allCases[sender.tag])
    }

    @objc private func timedBusy(_ sender: NSMenuItem) { changeMode(.busy, minutes: sender.tag) }

    private func changeMode(_ newMode: DisplayMode, minutes: Int? = nil, event: DiagnosticEvent = .modeChanged, refresh: Bool = true) {
        manualOverride.select(newMode, minutes: minutes)
        notifications.schedulePresentation(startedAt: newMode == .presenting ? manualOverride.startedAt : nil,
                                             minutes: features.reminderMinutes, enabled: features.presentationReminders)
        diagnostics.record(DiagnosticEntry(event: event, mode: newMode))
        previewUntil = .distantPast
        appearance.showPreview = false
        updateUI()
        if refresh { poll() }
    }

    private func configureFeatures() {
        if configuredShortcuts != features.shortcutsEnabled {
            configuredShortcuts = features.shortcutsEnabled
            let status = hotKeys.configure(enabled: features.shortcutsEnabled)
            features.shortcutStatus = features.shortcutsEnabled ? (status == 0 ? "Global shortcuts are active." : "A shortcut could not be registered (error \(status)). Try disabling conflicting shortcuts.") : "Keyboard shortcuts are off."
            let event: DiagnosticEvent = !features.shortcutsEnabled ? .shortcutsDisabled : (status == 0 ? .shortcutsRegistered : .shortcutsFailed)
            diagnostics.record(DiagnosticEntry(event: event, failureCodes: status == 0 ? [] : [Int(status)]))
        }
        let configuration = "\(features.presentationReminders)-\(features.reminderMinutes)-\(features.updateNotifications)"
        if notificationConfiguration != configuration {
            notificationConfiguration = configuration
            if features.presentationReminders || features.updateNotifications {
                Task { [weak self] in
                    guard let self else { return }
                    let allowed = await self.notifications.requestAccess()
                    self.notifications.schedulePresentation(startedAt: self.mode == .presenting ? self.manualOverride.startedAt : nil,
                                                              minutes: self.features.reminderMinutes, enabled: allowed && self.features.presentationReminders)
                }
            } else { notifications.schedulePresentation(startedAt: nil, minutes: features.reminderMinutes, enabled: false) }
        }
        updates.checkIfDue(enabled: features.automaticUpdateChecks)
        updateUI()
    }

    @objc private func checkUpdates() {
        if updates.releaseURL != nil { updates.openRelease() }
        else { updates.check() }
    }

    @objc private func preview() {
        previewUntil = Date().addingTimeInterval(5)
        updateUI()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.updateUI() }
    }

    @objc private func showSettings() {
        settingsController.show()
    }

    @objc private func stopPreview() {
        previewUntil = .distantPast
        appearance.showPreview = false
        updateUI()
    }

    @objc private func grantAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change launch at login"
            alert.informativeText = error.localizedDescription + "\nKeep Meeting Busy.app in a permanent location before enabling this option."
            alert.runModal()
        }
        if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        updateUI()
    }

    @objc private func showWelcome() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Meeting Busy"
        alert.informativeText = "Shows a red Busy box at the upper left of your main display during Webex, Teams, Google Meet, and Zoom calls.\n\nEnable Accessibility access so Meeting Busy can read meeting buttons. No microphone, camera, or screen recording access is needed.\n\nThe indicator hides when a Stop sharing, Stop Share, or Stop presenting control is detected. Before presenting, choose ‘I’m presenting’ from the menu bar for immediate hiding; return to Automatic afterward.\n\nDetection currently uses English controls. Background browser tabs and some client versions may not expose their controls. Use Force Busy when needed."
        alert.addButton(withTitle: "Grant Accessibility access")
        alert.addButton(withTitle: "Done")
        if alert.runModal() == .alertFirstButtonReturn { grantAccess() }
    }

    @objc private func willSleep() {
        suspended = true
        scanGeneration += 1
        tracker.clear()
        diagnostics.record(DiagnosticEntry(event: .sleep))
        previewUntil = .distantPast
        panel.update(visible: false)
    }
    @objc private func didWake() { suspended = false; diagnostics.record(DiagnosticEntry(event: .wake)); poll() }
    @objc private func screenChanged() { updateUI() }
    func applicationWillTerminate(_ notification: Notification) {
        hotKeys.unregister()
        notifications.schedulePresentation(startedAt: nil, minutes: features.reminderMinutes, enabled: false)
        diagnostics.record(DiagnosticEntry(event: .terminated))
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
