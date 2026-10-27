import Foundation

public struct DetectionPause: Codable, Equatable, Sendable {
    public private(set) var isPaused = false
    public private(set) var resumeAt: Date?
    public init() {}

    public mutating func pause(minutes: Int? = nil, at now: Date = Date()) {
        isPaused = true
        resumeAt = minutes.flatMap { $0 > 0 ? now.addingTimeInterval(Double($0) * 60) : nil }
    }
    public mutating func resume() { isPaused = false; resumeAt = nil }
    @discardableResult public mutating func expire(at now: Date = Date()) -> Bool {
        guard isPaused, let resumeAt, now >= resumeAt else { return false }
        resume()
        return true
    }
}

public struct AppearancePreset: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var appearance: IndicatorAppearance

    public init(id: UUID = UUID(), name: String, appearance: IndicatorAppearance) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.appearance = appearance.normalized
    }

    public static var defaults: [Self] {
        [Self(name: "Meeting", appearance: IndicatorAppearance()),
         Self(name: "Recording", appearance: IndicatorAppearance(text: "Recording", color: IndicatorColor(red: 0.12, green: 0.35, blue: 0.8))),
         Self(name: "Do not disturb", appearance: IndicatorAppearance(text: "Do not disturb", color: IndicatorColor(red: 0.95, green: 0.55, blue: 0.08)))]
    }
}

public enum ShortcutKey: String, CaseIterable, Codable, Sendable {
    case a = "A", b = "B", c = "C", d = "D", e = "E", f = "F", g = "G", h = "H", i = "I", j = "J", k = "K", l = "L", m = "M"
    case n = "N", o = "O", p = "P", q = "Q", r = "R", s = "S", t = "T", u = "U", v = "V", w = "W", x = "X", y = "Y", z = "Z"
    case zero = "0", one = "1", two = "2", three = "3", four = "4", five = "5", six = "6", seven = "7", eight = "8", nine = "9"
    case f1 = "F1", f2 = "F2", f3 = "F3", f4 = "F4", f5 = "F5", f6 = "F6", f7 = "F7", f8 = "F8", f9 = "F9", f10 = "F10", f11 = "F11", f12 = "F12"

    /// ANSI virtual key positions used by the macOS global hotkey API.
    public var keyCode: UInt32 {
        switch self {
        case .a: 0; case .b: 11; case .c: 8; case .d: 2; case .e: 14; case .f: 3; case .g: 5; case .h: 4; case .i: 34
        case .j: 38; case .k: 40; case .l: 37; case .m: 46; case .n: 45; case .o: 31; case .p: 35; case .q: 12; case .r: 15
        case .s: 1; case .t: 17; case .u: 32; case .v: 9; case .w: 13; case .x: 7; case .y: 16; case .z: 6
        case .zero: 29; case .one: 18; case .two: 19; case .three: 20; case .four: 21; case .five: 23; case .six: 22; case .seven: 26; case .eight: 28; case .nine: 25
        case .f1: 122; case .f2: 120; case .f3: 99; case .f4: 118; case .f5: 96; case .f6: 97; case .f7: 98; case .f8: 100; case .f9: 101; case .f10: 109; case .f11: 103; case .f12: 111
        }
    }
}

public struct ShortcutBinding: Codable, Equatable, Hashable, Sendable {
    public var key: ShortcutKey
    public var command: Bool
    public var option: Bool
    public var control: Bool
    public var shift: Bool

    public init(key: ShortcutKey, command: Bool = true, option: Bool = true, control: Bool = true, shift: Bool = false) {
        self.key = key; self.command = command; self.option = option; self.control = control; self.shift = shift
    }
    public var isValid: Bool { command || option || control }
    public var label: String { (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + key.rawValue }
}

public struct ShortcutConfiguration: Codable, Equatable, Sendable {
    public var automatic = ShortcutBinding(key: .one)
    public var busy = ShortcutBinding(key: .two)
    public var presenting = ShortcutBinding(key: .three)
    public init() {}
    public var bindings: [ShortcutBinding] { [automatic, busy, presenting] }
    public var validationMessage: String? {
        guard bindings.allSatisfy(\.isValid) else { return "Each shortcut must use Command, Option, or Control." }
        guard Set(bindings).count == bindings.count else { return "Choose a different shortcut for each action." }
        return nil
    }
}

/// A report excludes window titles, paths, URLs, custom indicator text, and log contents.
public struct DetectionReport: Sendable {
    public var version: String
    public var build: String
    public var osVersion: String
    public var date: Date
    public var mode: DisplayMode
    public var reason: IndicatorReason
    public var trusted: Bool
    public var paused: Bool
    public var enabledServices: Set<MeetingService>
    public var evidence: [MeetingEvidence]
    public var lastScanAt: Date?
    public var failureCodes: [Int]

    public init(version: String, build: String, osVersion: String, date: Date = Date(), mode: DisplayMode, reason: IndicatorReason,
                trusted: Bool, paused: Bool, enabledServices: Set<MeetingService>, evidence: [MeetingEvidence], lastScanAt: Date?, failureCodes: [Int]) {
        self.version = version; self.build = build; self.osVersion = osVersion; self.date = date; self.mode = mode; self.reason = reason
        self.trusted = trusted; self.paused = paused; self.enabledServices = enabledServices; self.evidence = evidence
        self.lastScanAt = lastScanAt; self.failureCodes = failureCodes
    }

    public func rendered() -> String {
        let formatter = ISO8601DateFormatter()
        let services = enabledServices.map(\.rawValue).sorted().joined(separator: ", ")
        let signals = evidence.map { "\($0.service.rawValue): \($0.signal.rawValue)\($0.isPresenting ? " (presenting)" : "")" }.sorted().joined(separator: "\n")
        return """
        Meeting Busy detection report
        Created: \(formatter.string(from: date))
        App: \(version) (build \(build))
        macOS: \(osVersion)

        Expected behavior: [Describe what should have happened]
        Steps to reproduce: [Describe the steps without private meeting information]

        Mode: \(mode.rawValue)
        Indicator reason: \(reason.rawValue)
        Accessibility permission: \(trusted ? "granted" : "denied")
        Detection paused: \(paused ? "yes" : "no")
        Enabled services: \(services.isEmpty ? "none" : services)
        Last completed scan: \(lastScanAt.map { formatter.string(from: $0) } ?? "none")
        Error codes: \(failureCodes.isEmpty ? "none" : failureCodes.map(String.init).joined(separator: ", "))
        Detection signals:
        \(signals.isEmpty ? "none" : signals)

        Review this report before sharing. No logs are attached automatically.
        """
    }
}
