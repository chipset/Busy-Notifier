import SwiftUI
import MeetingDetection

/// Serial I/O stays on one queue so a slow or unplugged device never blocks the interface.
private final class LightWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.meetingbusy.usb-light")
    private var link: SerialLink?
    private var lastAttempt = Date.distantPast
    private var lastReport = ""

    func send(_ state: LightState, report: @escaping @Sendable (String) -> Void) {
        queue.async { [self] in
            if link == nil {
                guard Date().timeIntervalSince(lastAttempt) >= 5 else { return }
                lastAttempt = Date()
                guard let found = SerialLink.connect() else { say("No Meeting Busy light found. Plug it in; it connects automatically.", report); return }
                link = found
                say("Connected to the light on \(found.path.replacingOccurrences(of: "/dev/", with: "")).", report)
            }
            if link?.write(IndicatorLight.command(state)) != true {
                link?.close(); link = nil
                say("The light was disconnected. Looking for it again…", report)
            }
        }
    }

    func shutdown(report: @escaping @Sendable (String) -> Void) {
        queue.sync {
            _ = link?.write(IndicatorLight.command(.off))
            link?.close(); link = nil
            lastAttempt = .distantPast
        }
        say("Light is off.", report)
    }

    private func say(_ text: String, _ report: @Sendable (String) -> Void) {
        guard text != lastReport else { return }
        lastReport = text
        report(text)
    }
}

@MainActor
final class UsbLightController: ObservableObject {
    @Published private(set) var status = "USB light is off."
    private let worker = LightWorker()
    private var lastState: LightState?
    private var lastSent = Date.distantPast
    private var testing = false

    /// Called on every UI refresh; resends the state as a heartbeat so the firmware knows the app is alive.
    func update(_ state: LightState, enabled: Bool) {
        guard !testing else { return }
        guard enabled else {
            if lastState != nil { stop() }
            return
        }
        guard state != lastState || Date().timeIntervalSince(lastSent) >= IndicatorLight.heartbeat else { return }
        lastState = state
        lastSent = Date()
        send(state)
    }

    func stop() {
        lastState = nil
        worker.shutdown { _ in }
        status = "USB light is off."
    }

    func test() {
        guard !testing else { return }
        testing = true
        Task {
            for state in [LightState.busy, .presenting, .attention, .off] {
                send(state)
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
            testing = false
            lastState = nil
        }
    }

    private func send(_ state: LightState) {
        worker.send(state) { [weak self] text in Task { @MainActor in self?.status = text } }
    }
}

struct UsbLightSettings: View {
    @ObservedObject var features: FeatureSettings
    @ObservedObject var light: UsbLightController
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("USB indicator light").font(.headline)
            Toggle("Drive a Meeting Busy USB light", isOn: $features.usbLightEnabled)
            Text("Optional RP2040 board with a WS2812 strip (see Firmware/UsbLight). Red = busy, yellow = presenting, slow amber flash = setup needed or the browser extension stopped reporting. Only the state name is sent; nothing about the meeting. The light turns off by itself if this app stops.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Test light") { light.test() }.disabled(!features.usbLightEnabled)
                Text(features.usbLightEnabled ? light.status : "USB light is off.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
