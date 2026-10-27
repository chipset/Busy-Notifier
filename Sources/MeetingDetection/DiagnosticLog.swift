import Foundation

public enum LoggingMode: String, CaseIterable, Sendable {
    case off = "Off", events = "State changes", verbose = "Every scan"
}

public enum DiagnosticEvent: String, Codable, Sendable {
    case launched, terminated, stateChanged, permissionChanged, modeChanged, timerExpired, scan, scanFailed, evidenceExpired
    case sleep, wake, shortcutsRegistered, shortcutsDisabled, shortcutsFailed, updateCheck, updateAvailable, updateFailed, notificationFailed
}

/// Deliberately has no arbitrary message field: no UI labels, titles, URLs, names, or custom text.
public struct DiagnosticEntry: Codable, Sendable {
    public var date: Date
    public var event: DiagnosticEvent
    public var state: IndicatorReason?
    public var mode: DisplayMode?
    public var services: [MeetingService]
    public var signals: [DetectionSignal]
    public var trusted: Bool?
    public var incomplete: Bool?
    public var scanMilliseconds: Int?
    public var failureCodes: [Int]

    public init(event: DiagnosticEvent, date: Date = Date(), state: IndicatorReason? = nil, mode: DisplayMode? = nil,
                evidence: [MeetingEvidence] = [], trusted: Bool? = nil, incomplete: Bool? = nil,
                scanMilliseconds: Int? = nil, failureCodes: [Int] = []) {
        self.date = date
        self.event = event
        self.state = state
        self.mode = mode
        services = Array(Set(evidence.map(\.service))).sorted { $0.rawValue < $1.rawValue }
        signals = Array(Set(evidence.map(\.signal))).sorted { $0.rawValue < $1.rawValue }
        self.trusted = trusted
        self.incomplete = incomplete
        self.scanMilliseconds = scanMilliseconds
        self.failureCodes = failureCodes
    }
}

public struct DiagnosticLogStore {
    public let directory: URL
    public let maximumFileBytes: Int
    public let backups: Int

    public init(directory: URL, maximumFileBytes: Int = 512 * 1024, backups: Int = 3) {
        self.directory = directory
        self.maximumFileBytes = max(1024, maximumFileBytes)
        self.backups = min(10, max(0, backups))
    }

    public func append(_ entry: DiagnosticEntry) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(entry)
        data.append(0x0A)
        guard data.count <= maximumFileBytes else { throw CocoaError(.fileWriteOutOfSpace) }
        let file = url(0)
        let size = (try? manager.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
        if size + data.count > maximumFileBytes {
            for index in stride(from: backups, through: 0, by: -1) {
                let source = url(index)
                guard manager.fileExists(atPath: source.path) else { continue }
                if index == backups { try manager.removeItem(at: source) }
                else { try manager.moveItem(at: source, to: url(index + 1)) }
            }
        }
        if !manager.fileExists(atPath: file.path) {
            guard manager.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    public func exportData() throws -> Data {
        var data = Data()
        for index in stride(from: backups, through: 0, by: -1) {
            let file = url(index)
            if FileManager.default.fileExists(atPath: file.path) { data.append(try Data(contentsOf: file)) }
        }
        return data
    }

    public func clear() throws {
        for index in 0...backups {
            let file = url(index)
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        }
    }

    private func url(_ index: Int) -> URL {
        directory.appendingPathComponent(index == 0 ? "events.jsonl" : "events.\(index).jsonl")
    }
}
