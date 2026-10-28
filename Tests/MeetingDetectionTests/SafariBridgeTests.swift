import XCTest
import Foundation
@testable import MeetingDetection

final class SafariBridgeTests: XCTestCase, @unchecked Sendable {
    func testLoopbackBridgeValidatesAuthenticationAndHonorsPolicy() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BrowserBridgeStore(directory: directory)
        try store.writePolicy(BrowserBridgePolicy(enabled: true, services: [.meet]))
        let token = String(repeating: "a", count: 64), pairingToken = String(repeating: "b", count: 64), port = UInt16.random(in: 51000...61000)
        let ready = expectation(description: "loopback listener ready")
        let server = try SafariBridgeServer(configuration: .init(port: port, token: token), pairingToken: pairingToken, store: store) { status in
            if status.contains("is ready") { ready.fulfill() }
        }
        defer { server.stop() }
        await fulfillment(of: [ready], timeout: 5)
        let session = UUID()
        let states = [BrowserTabState(id: "1:0", service: .meet, inMeeting: true, presenting: true),
                      BrowserTabState(id: "2:0", service: .zoom, inMeeting: true, presenting: false)]
        let body = try JSONEncoder().encode(SafariBridgeEnvelope(session: session, message: .init(states: states)))
        let client = URLSession(configuration: .ephemeral)
        defer { client.invalidateAndCancel() }
        func send(_ data: Data, authentication: String, origin: String? = nil) async throws -> (Data, Int, String?) {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/state")!)
            request.httpMethod = "POST"; request.httpBody = data; request.timeoutInterval = 3
            request.setValue("Bearer \(authentication)", forHTTPHeaderField: "Authorization")
            if let origin { request.setValue(origin, forHTTPHeaderField: "Origin") }
            let (data, response) = try await client.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0, (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Access-Control-Allow-Origin"))
        }
        let forbidden = try await send(body, authentication: "wrong")
        XCTAssertEqual(forbidden.1, 403); XCTAssertTrue(store.freshSnapshots().isEmpty)
        let webOrigin = try await send(body, authentication: pairingToken, origin: "https://meet.google.com")
        XCTAssertEqual(webOrigin.1, 403)
        let safariOrigin = "safari-web-extension://\(UUID().uuidString)"
        var preflight = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/state")!)
        preflight.httpMethod = "OPTIONS"
        preflight.setValue(safariOrigin, forHTTPHeaderField: "Origin")
        preflight.setValue("POST", forHTTPHeaderField: "Access-Control-Request-Method")
        preflight.setValue("authorization, content-type", forHTTPHeaderField: "Access-Control-Request-Headers")
        let (_, preflightResponse) = try await client.data(for: preflight)
        XCTAssertEqual((preflightResponse as? HTTPURLResponse)?.statusCode, 204)
        XCTAssertEqual((preflightResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "Access-Control-Allow-Origin"), safariOrigin)
        XCTAssertTrue(store.freshSnapshots().isEmpty)
        preflight.setValue("https://meet.google.com", forHTTPHeaderField: "Origin")
        let (_, deniedPreflight) = try await client.data(for: preflight)
        XCTAssertEqual((deniedPreflight as? HTTPURLResponse)?.statusCode, 403)
        let unpaired = try await send(body, authentication: "wrong", origin: safariOrigin)
        XCTAssertEqual(unpaired.1, 403)
        let invalidOrigin = try await send(body, authentication: pairingToken, origin: "safari-web-extension://not-an-extension")
        XCTAssertEqual(invalidOrigin.1, 403)
        // The build token is public inside every release, so extension origins may not use it.
        let buildTokenFromExtension = try await send(body, authentication: token, origin: safariOrigin)
        XCTAssertEqual(buildTokenFromExtension.1, 403)
        let nativeWithInstallToken = try await send(body, authentication: pairingToken)
        XCTAssertEqual(nativeWithInstallToken.1, 403)
        let paired = try await send(body, authentication: pairingToken, origin: safariOrigin)
        XCTAssertEqual(paired.1, 200); XCTAssertEqual(paired.2, safariOrigin)
        let malformed = try await send(Data("{}".utf8), authentication: token)
        XCTAssertEqual(malformed.1, 400)
        let accepted = try await send(body, authentication: token)
        XCTAssertEqual(accepted.1, 200)
        let reply = try JSONDecoder().decode(BrowserBridgeReply.self, from: accepted.0)
        XCTAssertTrue(reply.accepted)
        XCTAssertEqual(store.freshSnapshots().first?.states, [states[0]])
        let invalid = try JSONEncoder().encode(SafariBridgeEnvelope(session: session, message: .init(states: [states[0], states[0]])))
        let rejected = try await send(invalid, authentication: token)
        XCTAssertFalse(try JSONDecoder().decode(BrowserBridgeReply.self, from: rejected.0).accepted)
        XCTAssertTrue(store.freshSnapshots().isEmpty)
        _ = try await send(body, authentication: token)
        try store.writePolicy(BrowserBridgePolicy(enabled: true, paused: true, services: [.meet]))
        let paused = try await send(body, authentication: token)
        XCTAssertTrue(try JSONDecoder().decode(BrowserBridgeReply.self, from: paused.0).policy.paused)
        XCTAssertTrue(store.freshSnapshots().isEmpty)
    }

    func testPairingRequiresUserApprovalAndReturnsInstallToken() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BrowserBridgeStore(directory: directory)
        let installToken = try XCTUnwrap(SafariPairingToken.loadOrCreate(directory: directory))
        XCTAssertEqual(SafariPairingToken.loadOrCreate(directory: directory), installToken)
        let permissions = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("safari-pairing-token").path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
        let prompted = expectation(description: "user prompted"); prompted.assertForOverFulfill = false
        let origin = "safari-web-extension://\(UUID().uuidString)"
        let coordinator = SafariPairingCoordinator { asked in XCTAssertEqual(asked, origin); prompted.fulfill() }
        let port = UInt16.random(in: 51000...61000), ready = expectation(description: "ready")
        let server = try SafariBridgeServer(configuration: .init(port: port, token: String(repeating: "a", count: 64)), pairingToken: installToken,
                                            pairing: coordinator, store: store, onStatus: { if $0.contains("is ready") { ready.fulfill() } })
        defer { server.stop() }
        await fulfillment(of: [ready], timeout: 5)
        let client = URLSession(configuration: .ephemeral)
        defer { client.invalidateAndCancel() }
        func pair(origin: String?) async throws -> (SafariPairingReply?, Int) {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/pair")!)
            request.httpMethod = "POST"; request.timeoutInterval = 3
            if let origin { request.setValue(origin, forHTTPHeaderField: "Origin") }
            let (data, response) = try await client.data(for: request)
            return (try? JSONDecoder().decode(SafariPairingReply.self, from: data), (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let noOrigin = try await pair(origin: nil)
        XCTAssertEqual(noOrigin.1, 403)
        let web = try await pair(origin: "https://evil.example")
        XCTAssertEqual(web.1, 403)
        let first = try await pair(origin: origin)
        XCTAssertEqual(first.1, 202); XCTAssertNil(first.0?.token)
        await fulfillment(of: [prompted], timeout: 5)
        let waiting = try await pair(origin: origin)
        XCTAssertEqual(waiting.1, 202); XCTAssertNil(waiting.0?.token)
        coordinator.resolve(origin: origin, approve: true)
        let approved = try await pair(origin: origin)
        XCTAssertEqual(approved.1, 200); XCTAssertEqual(approved.0?.token, installToken); XCTAssertEqual(approved.0?.port, port)
        let consumed = try await pair(origin: origin)
        XCTAssertEqual(consumed.1, 202, "approval is single-use and a new request prompts again")
    }

    func testPairingCoordinatorLimitsPromptsAndExpiresRequests() {
        let counter = PromptCounter()
        let coordinator = SafariPairingCoordinator { _ in counter.increment() }
        let start = Date()
        XCTAssertEqual(coordinator.request(origin: "a", now: start), .pending)
        XCTAssertEqual(coordinator.request(origin: "b", now: start), .denied, "only one prompt at a time")
        coordinator.resolve(origin: "a", approve: false, now: start)
        XCTAssertEqual(coordinator.request(origin: "a", now: start.addingTimeInterval(5)), .denied)
        XCTAssertEqual(coordinator.request(origin: "a", now: start.addingTimeInterval(61)), .pending, "declines expire")
        XCTAssertEqual(coordinator.request(origin: "a", now: start.addingTimeInterval(200)), .pending, "unanswered requests expire and prompt again")
        coordinator.resolve(origin: "a", approve: true, now: start.addingTimeInterval(200))
        XCTAssertEqual(coordinator.request(origin: "a", now: start.addingTimeInterval(330)), .pending, "approval expires if the extension never collects it")
        XCTAssertEqual(counter.value, 4)
        let limited = SafariPairingCoordinator()
        for index in 0..<SafariPairingCoordinator.maximumPromptsPerWindow {
            XCTAssertEqual(limited.request(origin: "o\(index)", now: start), .pending)
            limited.resolve(origin: "o\(index)", approve: false, now: start)
        }
        XCTAssertEqual(limited.request(origin: "extra", now: start.addingTimeInterval(61)), .denied, "prompt budget is exhausted")
    }

    func testStaleSnapshotsArePruned() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BrowserBridgeStore(directory: directory)
        try store.writeSnapshot(BrowserBridgeSnapshot(states: []), session: UUID())
        XCTAssertEqual(store.pruneSnapshots(olderThan: 300), 0)
        XCTAssertEqual(store.pruneSnapshots(olderThan: 300, at: Date().addingTimeInterval(301)), 1)
    }
}

private final class PromptCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
