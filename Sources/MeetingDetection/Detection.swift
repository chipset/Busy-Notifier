import Foundation

public enum MeetingService: String, Sendable, CaseIterable, Codable {
    case webex = "Webex"
    case teams = "Microsoft Teams"
    case meet = "Google Meet"
    case zoom = "Zoom"
}

public struct Control: Sendable {
    public let label: String
    public let actionable: Bool
    public init(_ label: String, actionable: Bool = true) {
        self.label = label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.actionable = actionable
    }
}

public struct MeetingEvidence: Sendable, Equatable {
    public let service: MeetingService
    public let isPresenting: Bool
    public let signal: DetectionSignal
    public init(service: MeetingService, isPresenting: Bool, signal: DetectionSignal = .callControls) {
        self.service = service
        self.isPresenting = isPresenting
        self.signal = signal
    }
}

public enum DetectionSignal: String, Codable, Sendable {
    case callControls = "Active call controls"
    case sharingControl = "Your stop-sharing control"
    case zoomToolbar = "Zoom meeting window and toolbar"
    case zoomMenu = "Zoom meeting window and enabled Meeting command"
    case browserTab = "Browser extension meeting controls"
}

public enum Detection {
    // Exact actionable control labels seen in supported clients. Keep these
    // narrow: arbitrary text must never become meeting evidence.
    private static let localizedLeave = [
        "salir de la llamada", "salir de la reunión", "abandonar la reunión",
        "quitter l’appel", "quitter l'appel", "quitter la réunion",
        "anruf verlassen", "besprechung verlassen", "meeting verlassen"
    ]
    private static let localizedStopSharing = [
        "dejar de compartir", "detener la presentación", "dejar de presentar",
        "arrêter le partage", "arrêter de partager", "arrêter la présentation",
        "freigabe beenden", "bildschirmfreigabe beenden", "präsentation beenden"
    ]
    // These lists are mirrored by BrowserExtension/shared/detector.js. Keep each
    // `static let NAME = [...]` on one line: BrowserExtension/tests/parity.test.cjs
    // parses this file and fails when the two implementations drift apart.
    private static let meetEnd = ["leave call", "leave meeting", "hang up"]
    private static let teamsEnd = ["leave call", "leave meeting", "hang up", "end call", "end meeting"]
    private static let webexEnd = ["leave meeting", "end meeting", "leave call", "end call", "leave / end meeting", "leave or end meeting", "end or leave meeting"]
    private static let zoomEnd = ["leave meeting", "end meeting", "end meeting for all", "leave webinar", "end webinar"]
    private static let stopSharing = ["stop sharing", "stop presenting", "stop share", "stop screen sharing"]
    private static let teamsLeaveCompanions = ["mute", "unmute", "turn camera on", "turn camera off", "camera", "mic", "microphone"]
    private static let zoomLeaveCompanions = ["mute", "unmute", "mute audio", "unmute audio", "mute my audio", "unmute my audio", "start video", "stop video", "join audio", "audio", "video"]
    private static let endedAny = ["rejoin", "return to home", "back to home"]
    private static let endedZoom = ["join a meeting", "new meeting"]

    public static func nativeService(bundleID: String) -> MeetingService? {
        switch bundleID.lowercased() {
        case "com.microsoft.teams", "com.microsoft.teams2": .teams
        case "com.cisco.webexmeetingsapp", "com.webex.meetingmanager", "com.cisco.webexteams": .webex
        case "us.zoom.xos": .zoom
        default: nil
        }
    }

    public static func webService(url: String) -> MeetingService? {
        guard let parsed = URL(string: url), parsed.scheme == "https", let host = parsed.host?.lowercased() else { return nil }
        if host == "meet.google.com", parsed.path != "/", !parsed.path.isEmpty { return .meet }
        if host == "teams.microsoft.com" || host == "teams.live.com" || host == "teams.cloud.microsoft" { return .teams }
        if host == "webex.com" || host.hasSuffix(".webex.com") { return .webex }
        if host == "zoom.us" || host.hasSuffix(".zoom.us") || host == "zoom.com" || host.hasSuffix(".zoom.com") { return .zoom }
        return nil
    }

    public static func webService(url: String, enabledServices: Set<MeetingService>) -> MeetingService? {
        guard let service = webService(url: url), enabledServices.contains(service) else { return nil }
        return service
    }

    // Only actionable controls count. Chat messages and page text cannot start a meeting.
    public static func evaluate(service: MeetingService, controls: [Control], windowTitle: String? = nil, menuControls: [Control] = []) -> MeetingEvidence? {
        let labels = controls.filter(\.actionable).map(\.label)
        let endControls: [String]
        switch service {
        case .meet: endControls = meetEnd
        case .teams: endControls = teamsEnd
        case .webex: endControls = webexEnd
        case .zoom: endControls = zoomEnd
        }
        let presenting = labels.contains { matches($0, phrases: stopSharing + localizedStopSharing) }
        // Teams also labels its call button simply “Leave”; require a companion
        // call control to avoid treating a team/channel's Leave menu as a call.
        let teamsCall = service == .teams && labels.contains(where: { matches($0, phrases: ["leave"]) })
            && labels.contains(where: { matches($0, phrases: ["mute", "unmute", "turn camera on", "turn camera off", "camera", "mic", "microphone"]) })
        // Zoom's host button is “End”, and participants may see “Leave”.
        // Require an audio/video control alongside these otherwise ambiguous labels.
        let zoomCall = service == .zoom && labels.contains(where: { matches($0, phrases: ["end", "leave"]) })
            && labels.contains(where: { matches($0, phrases: ["mute", "unmute", "mute audio", "unmute audio", "mute my audio", "unmute my audio", "start video", "stop video", "join audio", "audio", "video"]) })
        let title = windowTitle?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let zoomWindow = title == "zoom meeting" || title == "zoom webinar" || title.hasPrefix("zoom meeting - ")
        let zoomToolbarCount = ["participants", "reactions", "share screen", "share", "meeting info"].filter { phrase in
            labels.contains(where: { matches($0, phrases: [phrase]) })
        }.count
        let prejoin = labels.contains(where: { matches($0, phrases: ["join", "join meeting", "join now", "join webinar"]) })
        let zoomToolbar = service == .zoom && zoomWindow && zoomToolbarCount >= 2 && !prejoin
        // Menu commands may linger after leaving. They only corroborate an actual meeting window.
        let menuLabels = menuControls.filter(\.actionable).map(\.label)
        let zoomMenu = service == .zoom && zoomWindow && !prejoin
            && (zoomToolbarCount > 0 || labels.contains(where: { matches($0, phrases: ["mute", "unmute", "start video", "stop video", "join audio"]) }))
            && menuLabels.contains(where: { matches($0, phrases: endControls) })
        // "New meeting" and "Join a meeting" are only post-call buttons in Zoom; Teams and Meet
        // show similar buttons on screens that remain visible during a live call.
        let ended = labels.contains(where: { matches($0, phrases: endedAny + (service == .zoom ? endedZoom : [])) })
        guard !ended, presenting || teamsCall || zoomCall || zoomToolbar || zoomMenu || labels.contains(where: { matches($0, phrases: endControls + localizedLeave) }) else { return nil }
        let sharingMenu = zoomMenu && menuLabels.contains(where: { matches($0, phrases: stopSharing + localizedStopSharing) })
        let signal: DetectionSignal = presenting || sharingMenu ? .sharingControl : (zoomToolbar ? .zoomToolbar : (zoomMenu ? .zoomMenu : .callControls))
        return MeetingEvidence(service: service, isPresenting: presenting || sharingMenu, signal: signal)
    }

    private static func matches(_ label: String, phrases: [String]) -> Bool {
        phrases.contains { phrase in
            label == phrase || label.hasPrefix(phrase + ",") || label.hasPrefix(phrase + " (") || label.hasPrefix(phrase + ".")
                || label.hasPrefix(phrase + "\n") || label.hasPrefix(phrase + "\t")
        }
    }
}

public enum DisplayMode: String, CaseIterable, Sendable, Codable {
    case automatic = "Automatic"
    case busy = "Force Busy"
    case presenting = "I’m presenting — hide indicator"
    case available = "Available — hide indicator"
}

public enum IndicatorPolicy {
    public static func visible(mode: DisplayMode, evidence: [MeetingEvidence], trusted: Bool) -> Bool {
        reason(mode: mode, evidence: evidence, trusted: trusted).showsIndicator
    }

    public static func reason(mode: DisplayMode, evidence: [MeetingEvidence], trusted: Bool, preview: Bool = false, paused: Bool = false, servicesEnabled: Bool = true, browserConnected: Bool = false) -> IndicatorReason {
        if mode == .available { return .available }
        if mode == .presenting || evidence.contains(where: \.isPresenting) { return .presenting }
        if mode == .busy { return .forcedBusy }
        if paused { return preview ? .preview : .paused }
        if !servicesEnabled { return preview ? .preview : .disabled }
        if evidence.contains(where: { trusted || $0.signal == .browserTab }) { return .meeting }
        if preview { return .preview }
        return trusted || browserConnected ? .idle : .setupNeeded
    }
}

public enum IndicatorReason: String, Equatable, Sendable, Codable {
    case presenting, forcedBusy, meeting, preview, idle, setupNeeded, paused, disabled, available

    public var showsIndicator: Bool {
        switch self {
        case .forcedBusy, .meeting, .preview: true
        case .presenting, .idle, .setupNeeded, .paused, .disabled, .available: false
        }
    }
}
