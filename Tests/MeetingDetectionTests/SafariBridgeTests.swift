import XCTest
import Foundation
@testable import MeetingDetection

final class SafariBridgeTests: XCTestCase, @unchecked Sendable {
    func testLoopbackBridgeValidatesAuthenticationAndHonorsPolicy() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BrowserBridgeStore(directory: directory)
        try store.writePolicy(BrowserBridgePolicy(enabled: true, services: [.meet]))
        let token = String(repeating: "a", count: 64), port = UInt16.random(in: 51000...61000)
        let ready = expectation(description: "loopback listener ready")
        let server = try SafariBridgeServer(configuration: .init(port: port, token: token), store: store) { status in
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
        let webOrigin = try await send(body, authentication: token, origin: "https://meet.google.com")
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
        let invalidOrigin = try await send(body, authentication: token, origin: "safari-web-extension://not-an-extension")
        XCTAssertEqual(invalidOrigin.1, 403)
        let paired = try await send(body, authentication: token, origin: safariOrigin)
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
}
