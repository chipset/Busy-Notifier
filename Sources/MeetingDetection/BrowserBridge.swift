import Foundation

public struct BrowserBridgePolicy: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var paused: Bool
    public var services: Set<MeetingService>
    public init(enabled: Bool = false, paused: Bool = false, services: Set<MeetingService> = []) {
        self.enabled = enabled; self.paused = paused; self.services = services
    }
    public func allows(_ service: MeetingService) -> Bool { enabled && !paused && services.contains(service) }
}

public struct BrowserTabState: Codable, Equatable, Sendable {
    public var id: String
    public var service: MeetingService
    public var inMeeting: Bool
    public var presenting: Bool
    public init(id: String, service: MeetingService, inMeeting: Bool, presenting: Bool) {
        self.id = id; self.service = service; self.inMeeting = inMeeting; self.presenting = presenting
    }
    public var isValid: Bool {
        let parts = id.split(separator: ":", omittingEmptySubsequences: false)
        return id.utf8.count <= 32 && parts.count == 2 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }
            && (!presenting || inMeeting)
    }
}

public struct BrowserBridgeMessage: Codable, Sendable {
    public var protocolVersion: Int
    public var states: [BrowserTabState]
    public init(states: [BrowserTabState], protocolVersion: Int = 1) { self.states = states; self.protocolVersion = protocolVersion }
    public var isValid: Bool { protocolVersion == 1 && states.count <= 256 && states.allSatisfy(\.isValid) && Set(states.map(\.id)).count == states.count }
}

public struct BrowserBridgeReply: Codable {
    public var protocolVersion = 1
    public var accepted: Bool
    public var policy: BrowserBridgePolicy
    public init(accepted: Bool, policy: BrowserBridgePolicy) { self.accepted = accepted; self.policy = policy }
}

public struct BrowserBridgeSnapshot: Codable, Sendable {
    public var protocolVersion = 1
    public var receivedAt: Date
    public var states: [BrowserTabState]
    public init(receivedAt: Date = Date(), states: [BrowserTabState]) { self.receivedAt = receivedAt; self.states = states }
    public func isFresh(at now: Date, maximumAge: TimeInterval = 20) -> Bool {
        let age = now.timeIntervalSince(receivedAt)
        return protocolVersion == 1 && age >= -2 && age < maximumAge && BrowserBridgeMessage(states: states).isValid
    }
}

public struct BrowserBridgeStore: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MeetingBusy/BrowserBridge", isDirectory: true)
    }
    public func readPolicy() -> BrowserBridgePolicy {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("policy.json")),
              let policy = try? JSONDecoder().decode(BrowserBridgePolicy.self, from: data) else { return BrowserBridgePolicy() }
        return policy
    }
    public func writePolicy(_ policy: BrowserBridgePolicy) throws {
        try write(JSONEncoder().encode(policy), to: directory.appendingPathComponent("policy.json"))
    }
    public func writeSnapshot(_ snapshot: BrowserBridgeSnapshot, session: UUID) throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        try write(encoder.encode(snapshot), to: snapshotURL(session))
    }
    public func removeSnapshot(session: UUID) {
        try? FileManager.default.removeItem(at: snapshotURL(session))
    }
    public func clearSnapshots() {
        for url in snapshotFiles() { try? FileManager.default.removeItem(at: url) }
    }
    public func freshSnapshots(at now: Date = Date()) -> [BrowserBridgeSnapshot] {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        return Array(snapshotFiles().compactMap { url -> BrowserBridgeSnapshot? in
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= NativeMessageIO.maximumBytes,
                  let data = try? Data(contentsOf: url), let snapshot = try? decoder.decode(BrowserBridgeSnapshot.self, from: data),
                  snapshot.isFresh(at: now) else { return nil }
            return snapshot
        }.sorted { $0.receivedAt > $1.receivedAt }.prefix(32))
    }
    public static func evidence(from snapshots: [BrowserBridgeSnapshot], policy: BrowserBridgePolicy) -> [MeetingEvidence] {
        let active = snapshots.flatMap(\.states).filter { $0.isValid && $0.inMeeting && policy.allows($0.service) }
        return MeetingService.allCases.compactMap { service in
            let matching = active.filter { $0.service == service }
            return matching.isEmpty ? nil : MeetingEvidence(service: service, isPresenting: matching.contains(where: \.presenting), signal: .browserTab)
        }
    }
    private func snapshotURL(_ id: UUID) -> URL { directory.appendingPathComponent("session-\(id.uuidString).json") }
    private func snapshotFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]))?.filter {
            $0.lastPathComponent.hasPrefix("session-") && $0.pathExtension == "json"
                && UUID(uuidString: String($0.deletingPathExtension().lastPathComponent.dropFirst(8))) != nil
        } ?? []
    }
    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// Chromium and Firefox use a native-endian 32-bit length followed by UTF-8 JSON.
/// Both supported Mac architectures are little-endian. Never print text to the native stdout pipe.
public enum NativeMessageIO {
    public static let maximumBytes = 64 * 1024
    public static func read(from handle: FileHandle) throws -> Data? {
        guard let header = try exact(4, from: handle, allowEOF: true) else { return nil }
        let bytes = [UInt8](header)
        let count = Int(UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24)
        guard count > 0, count <= maximumBytes, let data = try exact(count, from: handle, allowEOF: false) else { throw CocoaError(.fileReadCorruptFile) }
        return data
    }
    public static func write(_ data: Data, to handle: FileHandle) throws {
        guard !data.isEmpty, data.count <= maximumBytes else { throw CocoaError(.fileWriteInvalidFileName) }
        var count = UInt32(data.count).littleEndian
        var framed = withUnsafeBytes(of: &count) { Data($0) }; framed.append(data)
        try handle.write(contentsOf: framed)
    }
    private static func exact(_ count: Int, from handle: FileHandle, allowEOF: Bool) throws -> Data? {
        var data = Data()
        while data.count < count {
            guard let part = try handle.read(upToCount: count - data.count), !part.isEmpty else {
                if allowEOF && data.isEmpty { return nil }
                throw CocoaError(.fileReadCorruptFile)
            }
            data.append(part)
        }
        return data
    }
}
