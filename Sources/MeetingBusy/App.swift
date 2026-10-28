import AppKit
@preconcurrency import ApplicationServices
import MeetingDetection
import ServiceManagement

@main
enum MeetingBusyApp {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--diagnose") {
            let trusted = AXIsProcessTrusted()
            print("Meeting Busy \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development") (build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"))")
            print("Accessibility access: \(trusted ? "granted" : "denied")")
            guard trusted else { return }
            let settings = FeatureSettings()
            var pause = settings.pause
            pause.expire()
            if pause.isPaused { print("Automatic detection is paused; no applications were inspected."); return }
            let enabled = settings.enabledServices
            guard !enabled.isEmpty else { print("All meeting services are disabled; no applications were inspected."); return }
            let targets = NSWorkspace.shared.runningApplications.compactMap { app -> ApplicationTarget? in
                guard let id = app.bundleIdentifier,
                      Detection.nativeService(bundleID: id).map({ enabled.contains($0) }) ?? AccessibilityScanner.browserIDs.contains(id) else { return nil }
                return ApplicationTarget(pid: app.processIdentifier, bundleID: id)
            }
            let result = AccessibilityScanner.scan(targets, enabledServices: enabled)
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
    private let browserBridge = BrowserBridgeController()
    private lazy var settingsController = SettingsController(store: appearance, features: features, diagnostics: diagnostics, updates: updates, notifications: notifications, bridge: browserBridge)
    private lazy var keyboardMovement = KeyboardMovementController(store: appearance)
    private let reportController = ReportController()
    private var timer: Timer?
    private var scanning = false
    private var tracker = EvidenceTracker()
    private var presentationReturn = PresentationReturnTracker()
    private var browserEvidence: [MeetingEvidence] = []
    private var evidence: [MeetingEvidence] { (trusted ? tracker.evidence : []) + browserEvidence }
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
    private var configuredShortcutBindings: ShortcutConfiguration?
    private var configuredServices: Set<MeetingService>?
    private var configuredPause: DetectionPause?
    private var configuredBrowserIntegration: Bool?
    private var lastScanFailureCodes: [Int] = []
    private var notificationConfiguration = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        appearance.onChange = { [weak self] in self?.updateUI() }
        appearance.onKeyboardMove = { [weak self] in self?.keyboardMovement.show() }
        panel.onKeyboardMove = { [weak self] in self?.keyboardMovement.show() }
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
        features.onPause = { [weak self] minutes in self?.pauseDetection(minutes: minutes) }
        features.onResume = { [weak self] in self?.resumeDetection() }
        features.onReport = { [weak self] in self?.showReport() }
        features.onSetMode = { [weak self] mode in self?.changeMode(mode) }
        features.onPreview = { [weak self] in self?.preview() }
        features.onCheckDetection = { [weak self] in self?.poll() }
        features.onGrantAccess = { [weak self] in self?.grantAccess() }
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
        var pause = features.pause
        if pause.expire() { features.pause = pause }
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
        browserBridge.configure(enabled: features.browserIntegrationEnabled, paused: features.pause.isPaused, services: features.enabledServices)
        browserEvidence = browserBridge.evidence()
        if !trusted, features.autoReturnAfterSharing,
           presentationReturn.observe(mode: mode, evidence: browserEvidence, complete: browserBridge.connected) {
            changeMode(.automatic)
            return
        }
        guard !features.pause.isPaused, !features.enabledServices.isEmpty else {
            tracker.clear()
            appearance.lastCheckDescription = features.pause.isPaused ? "Automatic scans are paused." : "Enable a meeting service in Settings to start scanning."
            updateUI()
            return
        }
        guard trusted else {
            scanGeneration += 1
            tracker.clear()
            lastScanFailureCodes = []
            appearance.lastCheckDescription = browserBridge.connected ? "Browser bridge checked \(Date().formatted(date: .omitted, time: .standard)); native Accessibility checks are off." : "Automatic native detection is waiting for Accessibility permission."
            appearance.detectionDetails = "Accessibility access is denied.\nBrowser bridge: \(browserBridge.status)\nUse Grant Accessibility access for native client detection, or connect the browser extension for browser meetings.\nApp: \(Bundle.main.bundlePath)"
            updateUI()
            return
        }
        updateUI()
        guard !scanning else { return }
        scanning = true
        let generation = scanGeneration
        let scanStarted = Date()
        let enabledServices = features.enabledServices
        let targets = NSWorkspace.shared.runningApplications.compactMap { app -> ApplicationTarget? in
            guard let id = app.bundleIdentifier,
                  Detection.nativeService(bundleID: id).map({ enabledServices.contains($0) }) ?? AccessibilityScanner.browserIDs.contains(id) else { return nil }
            return ApplicationTarget(pid: app.processIdentifier, bundleID: id)
        }
        Task { [weak self] in
            let result = await AccessibilityScanner.scanConcurrently(targets, enabledServices: enabledServices)
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
            if self.features.autoReturnAfterSharing,
               self.presentationReturn.observe(mode: self.mode, evidence: self.evidence, complete: !result.incomplete) {
                self.changeMode(.automatic)
                return
            }
            self.incomplete = result.incomplete
            self.lastScanFailureCodes = result.failureCodes
            let milliseconds = Int(Date().timeIntervalSince(scanStarted) * 1000)
            self.appearance.lastCheckDescription = "Last check: \(Date().formatted(date: .omitted, time: .standard)) · \(milliseconds) ms\(result.incomplete ? " · incomplete" : "")"
            self.diagnostics.record(DiagnosticEntry(event: result.incomplete ? .scanFailed : .scan, evidence: self.evidence,
                                                     trusted: self.trusted, incomplete: result.incomplete,
                                                     scanMilliseconds: milliseconds, failureCodes: result.failureCodes))
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
            self.appearance.detectionDetails = "Version: \(version) (build \(build))\nApp: \(Bundle.main.bundlePath)\nAccessibility access: granted\nBrowser bridge: \(self.browserBridge.status)\n" + result.details.joined(separator: "\n")
            self.updateUI()
        }
    }

    private func updateUI() {
        let previewRequested = appearance.showPreview || Date() < previewUntil
        let reason = IndicatorPolicy.reason(mode: mode, evidence: evidence, trusted: trusted, preview: previewRequested,
                                           paused: features.pause.isPaused, servicesEnabled: !features.enabledServices.isEmpty, browserConnected: browserBridge.connected)
        if lastLoggedReason != reason || lastLoggedEvidence != evidence {
            lastLoggedReason = reason
            lastLoggedEvidence = evidence
            diagnostics.record(DiagnosticEntry(event: .stateChanged, state: reason, mode: mode, evidence: evidence, trusted: trusted))
        }
        let presenting = reason == .presenting
        let visible = !suspended && reason.showsIndicator
        let accessibilityStatus = reason == .preview ? "Indicator preview" : (reason == .forcedBusy ? "Manual status" : "Meeting detected")
        panel.update(visible: visible, appearance: appearance.appearance, accessibilityStatus: accessibilityStatus)
        let state: String
        switch reason {
        case .presenting:
            let minutes = Int(Date().timeIntervalSince(manualOverride.startedAt ?? Date()) / 60)
            state = mode == .presenting ? "Presenting — indicator hidden (\(minutes) min)" : "Screen sharing detected — indicator hidden"
        case .forcedBusy:
            state = manualOverride.expiresAt.map { "Busy — until \($0.formatted(date: .omitted, time: .shortened))" } ?? "Busy — manual override"
        case .available:
            state = manualOverride.expiresAt.map { "Available — indicator hidden until \($0.formatted(date: .omitted, time: .shortened))" } ?? "Available — indicator hidden until Automatic"
        case .meeting: state = "In a meeting: " + Set(evidence.map { $0.service.rawValue }).sorted().joined(separator: ", ")
        case .preview:
            state = features.pause.isPaused ? "Preview — detection paused" : (trusted ? "Preview — no meeting detected" : "Preview — Accessibility setup needed")
        case .setupNeeded: state = features.browserIntegrationEnabled ? "Connect browser extension or grant Accessibility access" : "Setup needed: Accessibility access"
        case .idle: state = !trusted && browserBridge.connected ? "No browser meeting detected — native Accessibility is off" : (incomplete ? "Unable to inspect some meeting windows" : "No active meeting detected")
        case .paused: state = features.pause.resumeAt.map { "Detection paused until \($0.formatted(date: .omitted, time: .shortened))" } ?? "Detection paused until resumed"
        case .disabled: state = "All meeting services are disabled"
        }
        appearance.detectionStatus = state
        statusItem.button?.toolTip = "Meeting Busy: " + state
        statusItem.button?.title = mode == .available ? " Available" : (mode == .presenting ? " Presenting" : (features.pause.isPaused ? " Paused" : ""))
        let symbol = reason == .available ? "checkmark.circle" : (reason == .paused ? "pause.circle" : (reason == .disabled ? "video.slash" : (presenting ? "rectangle.on.rectangle.slash" : (visible ? "video.fill" : "video"))))
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: state)
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
            if features.shortcutsEnabled && features.shortcutStatus == "Global shortcuts are active." && index < features.shortcuts.bindings.count {
                let binding = features.shortcuts.bindings[index]
                item.keyEquivalent = binding.menuKey
                item.keyEquivalentModifierMask = binding.menuModifiers
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
        let available = NSMenuItem(title: "Available for…", action: nil, keyEquivalent: "")
        let availableDurations = NSMenu()
        for minutes in [15, 30, 60] {
            let item = add("\(minutes) minutes", action: #selector(timedAvailable(_:)), to: availableDurations)
            item.tag = minutes
        }
        available.submenu = availableDurations
        menu.addItem(available)
        if features.pause.isPaused { add("Resume detection", action: #selector(resumeDetection), to: menu) }
        let pauseItem = NSMenuItem(title: "Pause detection", action: nil, keyEquivalent: "")
        let pauseMenu = NSMenu()
        for (minutes, title) in [(15, "15 minutes"), (60, "1 hour"), (0, "Until resumed")] {
            let item = add(title, action: #selector(pauseFromMenu(_:)), to: pauseMenu)
            item.tag = minutes
        }
        pauseItem.submenu = pauseMenu
        menu.addItem(pauseItem)
        let serviceItem = NSMenuItem(title: "Meeting services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu()
        for (index, service) in MeetingService.allCases.enumerated() {
            let item = add(service.rawValue, action: #selector(toggleService(_:)), to: servicesMenu)
            item.tag = index
            item.state = features.enabledServices.contains(service) ? .on : .off
        }
        serviceItem.submenu = servicesMenu
        menu.addItem(serviceItem)
        if !appearance.presets.isEmpty {
            let presetsItem = NSMenuItem(title: "Appearance presets", action: nil, keyEquivalent: "")
            let presetsMenu = NSMenu()
            for preset in appearance.presets {
                let item = add(preset.name, action: #selector(applyPreset(_:)), to: presetsMenu)
                item.representedObject = preset.id.uuidString
            }
            presetsItem.submenu = presetsMenu
            menu.addItem(presetsItem)
        }
        menu.addItem(.separator())
        add("Settings…", action: #selector(showSettings), to: menu, key: ",")
        add("Move indicator using the keyboard…", action: #selector(showKeyboardMovement), to: menu)
        add("This detection is incorrect…", action: #selector(showReport), to: menu)
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
    @objc private func timedAvailable(_ sender: NSMenuItem) { changeMode(.available, minutes: sender.tag) }

    private func changeMode(_ newMode: DisplayMode, minutes: Int? = nil, event: DiagnosticEvent = .modeChanged, refresh: Bool = true) {
        manualOverride.select(newMode, minutes: minutes)
        presentationReturn.reset()
        notifications.schedulePresentation(startedAt: newMode == .presenting ? manualOverride.startedAt : nil,
                                             minutes: features.reminderMinutes, enabled: features.presentationReminders)
        diagnostics.record(DiagnosticEntry(event: event, mode: newMode))
        previewUntil = .distantPast
        appearance.showPreview = false
        updateUI()
        if refresh { poll() }
    }

    private func configureFeatures() {
        if !features.autoReturnAfterSharing { presentationReturn.reset() }
        if configuredBrowserIntegration != features.browserIntegrationEnabled {
            configuredBrowserIntegration = features.browserIntegrationEnabled
            browserEvidence = []
        }
        browserBridge.configure(enabled: features.browserIntegrationEnabled && !suspended, paused: features.pause.isPaused, services: features.enabledServices)
        if configuredServices != features.enabledServices || configuredPause != features.pause {
            if configuredServices != nil, configuredServices != features.enabledServices {
                diagnostics.record(DiagnosticEntry(event: .servicesChanged))
            }
            if configuredPause != features.pause, configuredPause != nil || features.pause.isPaused {
                diagnostics.record(DiagnosticEntry(event: features.pause.isPaused ? .detectionPaused : .detectionResumed))
            }
            configuredServices = features.enabledServices
            configuredPause = features.pause
            scanGeneration += 1
            tracker.clear()
            browserEvidence = []
            lastScanFailureCodes = []
            incomplete = false
            appearance.lastCheckDescription = features.pause.isPaused ? "Automatic scans are paused." : "Waiting for the next scan of enabled services."
            appearance.detectionDetails = "Enabled services: " + features.enabledServices.map(\.rawValue).sorted().joined(separator: ", ")
        }
        if configuredShortcuts != features.shortcutsEnabled || configuredShortcutBindings != features.shortcuts {
            configuredShortcuts = features.shortcutsEnabled
            configuredShortcutBindings = features.shortcuts
            let status = hotKeys.configure(enabled: features.shortcutsEnabled, configuration: features.shortcuts)
            features.shortcutStatus = features.shortcutsEnabled ? (status == 0 ? "Global shortcuts are active." : (hotKeys.failureDescription ?? "Shortcuts could not be registered (error \(status)).")) : "Keyboard shortcuts are off."
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

    private func pauseDetection(minutes: Int?) {
        var pause = features.pause
        pause.pause(minutes: minutes)
        features.pause = pause
        poll()
    }
    @objc private func pauseFromMenu(_ sender: NSMenuItem) { pauseDetection(minutes: sender.tag == 0 ? nil : sender.tag) }
    @objc private func resumeDetection() {
        var pause = features.pause
        pause.resume()
        features.pause = pause
        poll()
    }
    @objc private func toggleService(_ sender: NSMenuItem) {
        let service = MeetingService.allCases[sender.tag]
        if features.enabledServices.contains(service) { features.enabledServices.remove(service) }
        else { features.enabledServices.insert(service) }
        poll()
    }
    @objc private func applyPreset(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let id = UUID(uuidString: value) else { return }
        appearance.applyPreset(id: id)
    }
    @objc private func showKeyboardMovement() { keyboardMovement.show() }
    @objc private func showReport() {
        let reason = IndicatorPolicy.reason(mode: mode, evidence: evidence, trusted: trusted,
                                           preview: appearance.showPreview || Date() < previewUntil,
                                           paused: features.pause.isPaused, servicesEnabled: !features.enabledServices.isEmpty, browserConnected: browserBridge.connected)
        let report = DetectionReport(version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
                                     build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                                     osVersion: ProcessInfo.processInfo.operatingSystemVersionString, mode: mode, reason: reason, trusted: trusted,
                                     paused: features.pause.isPaused, enabledServices: features.enabledServices, evidence: evidence,
                                     lastScanAt: [tracker.lastCompletedAt, browserBridge.lastObservedAt].compactMap { $0 }.max(), failureCodes: lastScanFailureCodes)
        reportController.show(report)
        diagnostics.record(DiagnosticEntry(event: .reportPrepared, state: reason))
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
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        alert.informativeText = "Version \(version) (build \(build))\n\nShows a red Busy box at the upper left of your main display during Webex, Teams, Google Meet, and Zoom calls.\n\nEnable Accessibility access so Meeting Busy can read meeting buttons. No microphone, camera, or screen recording access is needed.\n\nThe indicator hides when a Stop sharing, Stop Share, or Stop presenting control is detected. Before presenting, choose ‘I’m presenting’ from the menu bar for immediate hiding; return to Automatic afterward.\n\nDetection uses English and limited Spanish, French, and German controls. For inactive browser tabs, set up the optional Safari, Chromium, or Firefox extension in Settings → Browser integration. Some client versions may still hide their controls. Use Force Busy for missed calls or Available to hide a false positive."
        alert.addButton(withTitle: "Grant Accessibility access")
        alert.addButton(withTitle: "Done")
        if alert.runModal() == .alertFirstButtonReturn { grantAccess() }
    }

    @objc private func willSleep() {
        suspended = true
        scanGeneration += 1
        tracker.clear()
        browserEvidence = []
        browserBridge.configure(enabled: false, paused: features.pause.isPaused, services: features.enabledServices)
        diagnostics.record(DiagnosticEntry(event: .sleep))
        previewUntil = .distantPast
        panel.update(visible: false)
    }
    @objc private func didWake() { suspended = false; configureFeatures(); diagnostics.record(DiagnosticEntry(event: .wake)); poll() }
    @objc private func screenChanged() { updateUI() }
    func applicationWillTerminate(_ notification: Notification) {
        browserBridge.configure(enabled: false, paused: features.pause.isPaused, services: features.enabledServices)
        hotKeys.unregister()
        notifications.schedulePresentation(startedAt: nil, minutes: features.reminderMinutes, enabled: false)
        diagnostics.record(DiagnosticEntry(event: .terminated))
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
