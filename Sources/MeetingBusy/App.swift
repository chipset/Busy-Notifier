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
    private lazy var settingsController = SettingsController(store: appearance)
    private var timer: Timer?
    private var scanning = false
    private var evidence: [MeetingEvidence] = []
    private var trusted = false
    private var incomplete = false
    private var mode = DisplayMode.automatic
    private var scanGeneration = 0
    private var previewUntil = Date.distantPast
    private var suspended = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        appearance.onChange = { [weak self] in self?.updateUI() }
        panel.onMove = { [weak self] origin, screen, displayID in
            guard let self else { return }
            self.appearance.appearance = self.appearance.appearance.repositioned(to: origin, in: screen, displayID: displayID)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "person.crop.circle.badge.clock", accessibilityDescription: "Meeting Busy")
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
        trusted = AXIsProcessTrusted()
        guard trusted else {
            scanGeneration += 1
            evidence = []
            appearance.detectionDetails = "Accessibility access is denied.\nUse Grant Accessibility access from the menu.\nIf this app was rebuilt, remove its old Accessibility entry and add this copy again.\nApp: \(Bundle.main.bundlePath)"
            updateUI()
            return
        }
        updateUI()
        guard !scanning else { return }
        scanning = true
        let generation = scanGeneration
        let targets = NSWorkspace.shared.runningApplications.compactMap { app -> ApplicationTarget? in
            guard let id = app.bundleIdentifier,
                  Detection.nativeService(bundleID: id) != nil || AccessibilityScanner.browserIDs.contains(id) else { return nil }
            return ApplicationTarget(pid: app.processIdentifier, bundleID: id)
        }
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) { AccessibilityScanner.scan(targets) }.value
            guard let self else { return }
            self.scanning = false
            guard self.scanGeneration == generation, !self.suspended else { return }
            self.evidence = result.evidence
            self.incomplete = result.incomplete
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
            self.appearance.detectionDetails = "Version: \(version)\nApp: \(Bundle.main.bundlePath)\nAccessibility access: granted\n" + result.details.joined(separator: "\n")
            self.updateUI()
        }
    }

    private func updateUI() {
        let previewRequested = appearance.showPreview || Date() < previewUntil
        let reason = IndicatorPolicy.reason(mode: mode, evidence: evidence, trusted: trusted, preview: previewRequested)
        let presenting = reason == .presenting
        let visible = !suspended && reason.showsIndicator
        panel.update(visible: visible, appearance: appearance.appearance)
        let state: String
        switch reason {
        case .presenting:
            state = mode == .presenting ? "Presenting — indicator hidden" : "Screen sharing detected — indicator hidden"
        case .forcedBusy: state = "Busy — manual override"
        case .meeting: state = "In a meeting: " + Set(evidence.map { $0.service.rawValue }).sorted().joined(separator: ", ")
        case .preview: state = trusted ? "Preview — no meeting detected" : "Preview — Accessibility setup needed"
        case .setupNeeded: state = "Setup needed: Accessibility access"
        case .idle: state = incomplete ? "Unable to inspect some meeting windows" : "No active meeting detected"
        }
        appearance.detectionStatus = state
        statusItem.button?.toolTip = "Meeting Busy: " + state
        statusItem.button?.image = NSImage(systemSymbolName: presenting ? "rectangle.on.rectangle.slash" : (visible ? "video.fill" : "video"), accessibilityDescription: state)
        let menu = NSMenu()
        let status = NSMenuItem(title: state, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        for (index, choice) in DisplayMode.allCases.enumerated() {
            let item = NSMenuItem(title: choice.rawValue, action: #selector(setMode(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = choice == mode ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        add("Settings…", action: #selector(showSettings), to: menu, key: ",")
        add("Preview Busy for 5 seconds", action: #selector(preview), to: menu)
        if previewRequested { add("Stop preview", action: #selector(stopPreview), to: menu) }
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
        mode = DisplayMode.allCases[sender.tag]
        previewUntil = .distantPast
        appearance.showPreview = false
        updateUI()
        poll()
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
        evidence = []
        previewUntil = .distantPast
        panel.update(visible: false)
    }
    @objc private func didWake() { suspended = false; poll() }
    @objc private func screenChanged() { updateUI() }
    @objc private func quit() { NSApp.terminate(nil) }
}
