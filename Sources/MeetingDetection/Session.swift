import Foundation

public struct ManualOverride: Sendable {
    public private(set) var mode: DisplayMode = .automatic
    public private(set) var startedAt: Date?
    public private(set) var expiresAt: Date?

    public init() {}

    public mutating func select(_ mode: DisplayMode, at now: Date = Date(), minutes: Int? = nil) {
        self.mode = mode
        startedAt = mode == .automatic ? nil : now
        expiresAt = mode == .busy || mode == .available ? minutes.flatMap { $0 > 0 ? now.addingTimeInterval(Double($0) * 60) : nil } : nil
    }

    @discardableResult public mutating func expire(at now: Date = Date()) -> Bool {
        guard let expiresAt, now >= expiresAt else { return false }
        select(.automatic, at: now)
        return true
    }
}

/// A positive result cannot keep the indicator busy indefinitely if scans stop returning.
public struct EvidenceTracker: Sendable {
    public private(set) var evidence: [MeetingEvidence] = []
    public private(set) var lastCompletedAt: Date?
    public var maximumAge: TimeInterval = 12

    public init() {}

    public mutating func accept(_ evidence: [MeetingEvidence], at now: Date = Date()) {
        self.evidence = evidence
        lastCompletedAt = now
    }

    @discardableResult public mutating func expire(at now: Date = Date()) -> Bool {
        guard !evidence.isEmpty, let lastCompletedAt, now.timeIntervalSince(lastCompletedAt) >= maximumAge else { return false }
        evidence = []
        return true
    }

    public mutating func clear() { evidence = []; lastCompletedAt = nil }
}

/// Returns to Automatic only after sharing was observed and a live call repeatedly
/// confirms that the same service is no longer sharing.
public struct PresentationReturnTracker: Sendable {
    private var armedServices = Set<MeetingService>()
    private var stoppedChecks = 0

    public init() {}

    public mutating func reset() {
        armedServices = []
        stoppedChecks = 0
    }

    public mutating func observe(mode: DisplayMode, evidence: [MeetingEvidence], complete: Bool) -> Bool {
        guard mode == .presenting else { reset(); return false }
        guard complete else { return false }
        let sharing = Set(evidence.filter(\.isPresenting).map(\.service))
        if !sharing.isEmpty {
            armedServices.formUnion(sharing)
            stoppedChecks = 0
            return false
        }
        guard !armedServices.isEmpty else { return false }
        if evidence.contains(where: { armedServices.contains($0.service) }) {
            stoppedChecks += 1
            return stoppedChecks >= 3
        }
        stoppedChecks = 0
        return false
    }
}
