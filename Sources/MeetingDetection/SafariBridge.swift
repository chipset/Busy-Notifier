import Foundation
import Network
import Security

public struct SafariBridgeConfiguration: Codable, Sendable {
    public let port: UInt16
    public let token: String
    public init(port: UInt16, token: String) { self.port = port; self.token = token }
}

public struct SafariBridgeEnvelope: Codable, Sendable {
    public let session: UUID
    public let message: BrowserBridgeMessage
    public init(session: UUID, message: BrowserBridgeMessage) { self.session = session; self.message = message }
}

public enum SafariPairingDecision: Equatable, Sendable { case pending, approved, denied }

public struct SafariPairingReply: Codable, Sendable {
    public var status: String
    public var port: UInt16?
    public var token: String?
}

/// Tracks "Allow this Safari extension?" requests so the user approves each pairing in the app.
/// Approval is consumed by the next request from the same extension origin and is never persisted.
public final class SafariPairingCoordinator: @unchecked Sendable {
    private enum State { case pending, approved, denied }
    private struct Entry { var state: State; var date: Date }
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var promptDates: [Date] = []
    public var onPrompt: (@Sendable (String) -> Void)?
    public static let pendingLifetime: TimeInterval = 60
    public static let approvalLifetime: TimeInterval = 120
    public static let maximumPromptsPerWindow = 5
    public static let promptWindow: TimeInterval = 600

    public init(onPrompt: (@Sendable (String) -> Void)? = nil) { self.onPrompt = onPrompt }

    public func request(origin: String, now: Date = Date()) -> SafariPairingDecision {
        lock.lock()
        entries = entries.filter { _, entry in
            now.timeIntervalSince(entry.date) < (entry.state == .approved ? Self.approvalLifetime : Self.pendingLifetime)
        }
        promptDates.removeAll { now.timeIntervalSince($0) >= Self.promptWindow }
        if let entry = entries[origin] {
            if entry.state == .approved { entries[origin] = nil }
            lock.unlock()
            switch entry.state { case .pending: return .pending; case .approved: return .approved; case .denied: return .denied }
        }
        // One prompt at a time and a small budget keep a misbehaving page or process from spamming the user.
        guard !entries.values.contains(where: { $0.state == .pending }), promptDates.count < Self.maximumPromptsPerWindow else {
            lock.unlock(); return .denied
        }
        entries[origin] = Entry(state: .pending, date: now)
        promptDates.append(now)
        let prompt = onPrompt
        lock.unlock()
        prompt?(origin)
        return .pending
    }

    public func resolve(origin: String, approve: Bool, now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        guard entries[origin]?.state == .pending else { return }
        entries[origin] = Entry(state: approve ? .approved : .denied, date: now)
    }
}

/// A per-install secret for Safari extension pairing. The build-time token in the app bundle
/// is identical for every download of a release, so extension requests never rely on it.
public enum SafariPairingToken {
    public static func loadOrCreate(directory: URL) -> String? {
        let url = directory.appendingPathComponent("safari-pairing-token")
        if let existing = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           isValid(existing) { return existing }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try Data(token.utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { return nil }
        return token
    }
    static func isValid(_ token: String) -> Bool { token.count == 64 && token.allSatisfy(\.isHexDigit) }
}

/// The sandboxed Safari app extension forwards native messages over loopback.
/// A per-build random token stays in the native bundles, never in webpage scripts.
public final class SafariBridgeServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "local.meetingbusy.safari-bridge")
    private let configuration: SafariBridgeConfiguration
    private let store: BrowserBridgeStore
    private let pairingToken: String?
    private let pairing: SafariPairingCoordinator?
    private let onUpdate: @Sendable () -> Void
    private var active = 0 // confined to queue

    /// `configuration.token` authenticates the native Safari handler (requests without an Origin).
    /// Extension pages (a Safari-extension Origin) must use the per-install `pairingToken`.
    public init(configuration: SafariBridgeConfiguration, pairingToken: String? = nil, pairing: SafariPairingCoordinator? = nil,
                store: BrowserBridgeStore, onStatus: @escaping @Sendable (String) -> Void = { _ in },
                onUpdate: @escaping @Sendable () -> Void = {}) throws {
        guard SafariPairingToken.isValid(configuration.token), pairingToken.map(SafariPairingToken.isValid) ?? true,
              let port = NWEndpoint.Port(rawValue: configuration.port) else { throw CocoaError(.coderInvalidValue) }
        self.configuration = configuration; self.store = store
        self.pairingToken = pairingToken; self.pairing = pairing; self.onUpdate = onUpdate
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
        listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: onStatus("Safari bridge is ready on this Mac.")
            case .failed: onStatus("Safari bridge could not start. Quit other copies of Meeting Busy, then toggle browser integration off and on.")
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, self.active < 16 else { connection.cancel(); return }
            self.active += 1
            let request = SafariBridgeConnection(connection: connection, configuration: self.configuration, pairingToken: self.pairingToken,
                                                 pairing: self.pairing, store: self.store, queue: self.queue,
                                                 onUpdate: self.onUpdate, onClose: { [weak self] in self?.active -= 1 })
            request.start()
        }
        listener.start(queue: queue)
    }
    public func stop() { listener.cancel() }
    deinit { listener.cancel() }
}

private final class SafariBridgeConnection: @unchecked Sendable {
    let connection: NWConnection
    let configuration: SafariBridgeConfiguration
    let pairingToken: String?
    let pairing: SafariPairingCoordinator?
    let store: BrowserBridgeStore
    let queue: DispatchQueue
    let onUpdate: @Sendable () -> Void
    let onClose: @Sendable () -> Void
    var data = Data()
    var closed = false
    var allowedOrigin: String?
    var deadline: DispatchWorkItem?

    init(connection: NWConnection, configuration: SafariBridgeConfiguration, pairingToken: String?, pairing: SafariPairingCoordinator?,
         store: BrowserBridgeStore, queue: DispatchQueue, onUpdate: @escaping @Sendable () -> Void, onClose: @escaping @Sendable () -> Void) {
        self.connection = connection; self.configuration = configuration; self.pairingToken = pairingToken; self.pairing = pairing
        self.store = store; self.queue = queue; self.onUpdate = onUpdate; self.onClose = onClose
    }
    static func sameSecret(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b, a.utf8.count == b.utf8.count else { return false }
        return zip(a.utf8, b.utf8).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
    func start() {
        connection.start(queue: queue)
        let timeout = DispatchWorkItem { [weak self] in self?.close() }
        deadline = timeout; queue.asyncAfter(deadline: .now() + 4, execute: timeout)
        receive()
    }
    func close() {
        guard !closed else { return }; closed = true
        deadline?.cancel(); deadline = nil; connection.cancel(); onClose()
    }
    func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [self] chunk, _, complete, error in
            guard !closed else { return }
            if let chunk { data.append(chunk) }
            guard data.count <= NativeMessageIO.maximumBytes + 8192 else { respond(413); return }
            guard let boundary = data.range(of: Data("\r\n\r\n".utf8)) else {
                if data.count > 8192 || complete || error != nil { close() } else { receive() }; return
            }
            guard boundary.lowerBound <= 8192,
                  let header = String(data: data[..<boundary.lowerBound], encoding: .utf8) else { respond(400); return }
            let lines = header.components(separatedBy: "\r\n")
            let isPreflight = lines.first == "OPTIONS /state HTTP/1.1" || lines.first == "OPTIONS /pair HTTP/1.1"
            let isPairing = lines.first == "POST /pair HTTP/1.1" || lines.first == "OPTIONS /pair HTTP/1.1"
            guard isPreflight || isPairing || lines.first == "POST /state HTTP/1.1" else { respond(400); return }
            var fields: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { respond(400); return }
                let key = line[..<colon].lowercased()
                guard fields[key] == nil else { respond(400); return }
                fields[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            guard fields["host"] == "127.0.0.1:\(configuration.port)" else { respond(403); return }
            if let origin = fields["origin"] {
                guard let url = URL(string: origin), url.scheme == "safari-web-extension", let host = url.host,
                      UUID(uuidString: host) != nil, url.user == nil, url.password == nil, url.port == nil,
                      url.path.isEmpty, url.query == nil, url.fragment == nil else { respond(403); return }
                allowedOrigin = origin
            }
            if isPreflight {
                let headers = Set((fields["access-control-request-headers"] ?? "").lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
                guard allowedOrigin != nil, fields["access-control-request-method"] == "POST",
                      headers.isSubset(of: ["authorization", "content-type"]) else { respond(403); return }
                respond(204); return
            }
            if isPairing {
                guard let origin = allowedOrigin, let pairing, let pairingToken else { respond(403); return }
                switch pairing.request(origin: origin) {
                case .pending: respond(202, body: SafariPairingReply(status: "pending"))
                case .approved: respond(200, body: SafariPairingReply(status: "approved", port: configuration.port, token: pairingToken))
                case .denied: respond(403, body: SafariPairingReply(status: "denied"))
                }
                return
            }
            // Extension origins use the per-install token; only the native handler (no Origin) may use the build token.
            let expected = allowedOrigin == nil ? configuration.token : pairingToken
            guard let authorization = fields["authorization"], authorization.hasPrefix("Bearer "),
                  Self.sameSecret(String(authorization.dropFirst(7)), expected) else { respond(403); return }
            guard fields["transfer-encoding"] == nil, let rawLength = fields["content-length"],
                  let length = Int(rawLength), length > 0, length <= NativeMessageIO.maximumBytes else { respond(400); return }
            let body = data[boundary.upperBound...]
            if body.count < length {
                if complete || error != nil { close() } else { receive() }; return
            }
            guard body.count == length,
                  let envelope = try? JSONDecoder().decode(SafariBridgeEnvelope.self, from: Data(body)) else { respond(400); return }
            let policy = store.readPolicy()
            guard envelope.message.isValid else {
                store.removeSnapshot(session: envelope.session); onUpdate()
                respond(200, body: BrowserBridgeReply(accepted: false, policy: policy)); return
            }
            do {
                if policy.enabled && !policy.paused {
                    try store.writeSnapshot(BrowserBridgeSnapshot(states: envelope.message.states.filter { policy.allows($0.service) }), session: envelope.session)
                } else { store.removeSnapshot(session: envelope.session) }
                onUpdate()
                respond(200, body: BrowserBridgeReply(accepted: true, policy: policy))
            } catch { respond(503) }
        }
    }
    func respond<Body: Encodable>(_ code: Int, body reply: Body) { respond(code, encoded: try? JSONEncoder().encode(reply)) }
    func respond(_ code: Int) { respond(code, encoded: nil) }
    func respond(_ code: Int, encoded: Data?) {
        let body = encoded ?? Data()
        var response = Data("HTTP/1.1 \(code) \(code == 200 ? "OK" : (code == 202 ? "Accepted" : "Error"))\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n".utf8)
        if let origin = allowedOrigin {
            response = Data("HTTP/1.1 \(code) \(code == 200 ? "OK" : (code == 202 ? "Accepted" : "Response"))\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\nAccess-Control-Allow-Origin: \(origin)\r\nAccess-Control-Allow-Methods: POST\r\nAccess-Control-Allow-Headers: Authorization, Content-Type\r\nVary: Origin\r\n\r\n".utf8)
        }
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { [self] _ in close() })
    }
}
