import Foundation
import Network

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

/// The sandboxed Safari app extension forwards native messages over loopback.
/// A per-build random token stays in the native bundles, never in webpage scripts.
public final class SafariBridgeServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "local.meetingbusy.safari-bridge")
    private let configuration: SafariBridgeConfiguration
    private let store: BrowserBridgeStore
    private var active = 0 // confined to queue

    public init(configuration: SafariBridgeConfiguration, store: BrowserBridgeStore,
                onStatus: @escaping @Sendable (String) -> Void = { _ in }) throws {
        guard configuration.token.count == 64, configuration.token.allSatisfy(\.isHexDigit),
              let port = NWEndpoint.Port(rawValue: configuration.port) else { throw CocoaError(.coderInvalidValue) }
        self.configuration = configuration; self.store = store
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
            let request = SafariBridgeConnection(connection: connection, configuration: self.configuration, store: self.store,
                                                 queue: self.queue, onClose: { [weak self] in self?.active -= 1 })
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
    let store: BrowserBridgeStore
    let queue: DispatchQueue
    let onClose: @Sendable () -> Void
    var data = Data()
    var closed = false
    var allowedOrigin: String?
    var deadline: DispatchWorkItem?

    init(connection: NWConnection, configuration: SafariBridgeConfiguration, store: BrowserBridgeStore,
         queue: DispatchQueue, onClose: @escaping @Sendable () -> Void) {
        self.connection = connection; self.configuration = configuration; self.store = store
        self.queue = queue; self.onClose = onClose
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
            let isPreflight = lines.first == "OPTIONS /state HTTP/1.1"
            guard isPreflight || lines.first == "POST /state HTTP/1.1" else { respond(400); return }
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
            guard fields["authorization"] == "Bearer \(configuration.token)" else { respond(403); return }
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
                store.removeSnapshot(session: envelope.session)
                respond(200, reply: BrowserBridgeReply(accepted: false, policy: policy)); return
            }
            do {
                if policy.enabled && !policy.paused {
                    try store.writeSnapshot(BrowserBridgeSnapshot(states: envelope.message.states.filter { policy.allows($0.service) }), session: envelope.session)
                } else { store.removeSnapshot(session: envelope.session) }
                respond(200, reply: BrowserBridgeReply(accepted: true, policy: policy))
            } catch { respond(503) }
        }
    }
    func respond(_ code: Int, reply: BrowserBridgeReply? = nil) {
        let body = reply.flatMap { try? JSONEncoder().encode($0) } ?? Data()
        var response = Data("HTTP/1.1 \(code) \(code == 200 ? "OK" : "Error")\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n".utf8)
        if let origin = allowedOrigin {
            response = Data("HTTP/1.1 \(code) \(code == 200 ? "OK" : "Response")\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\nAccess-Control-Allow-Origin: \(origin)\r\nAccess-Control-Allow-Methods: POST\r\nAccess-Control-Allow-Headers: Authorization, Content-Type\r\nVary: Origin\r\n\r\n".utf8)
        }
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { [self] _ in close() })
    }
}
