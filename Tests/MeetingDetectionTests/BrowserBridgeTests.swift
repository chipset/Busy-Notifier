import XCTest
@testable import MeetingDetection

final class BrowserBridgeTests: XCTestCase {
    func testAvailableHidesFalsePositiveAndPreviewsWithoutCallingItPresenting() {
        for sharing in [false, true] {
            let state = IndicatorPolicy.reason(mode: .available, evidence: [MeetingEvidence(service: .zoom, isPresenting: sharing)],
                                               trusted: true, preview: true, paused: false)
            XCTAssertEqual(state, .available)
            XCTAssertFalse(state.showsIndicator)
        }
    }
    func testAvailableTimerReturnsToAutomaticAndDoesNotChangePause() {
        let now = Date(timeIntervalSince1970: 1000)
        for minutes in [15, 30, 60] {
            var override = ManualOverride()
            override.select(.available, at: now, minutes: minutes)
            XCTAssertEqual(override.mode, .available)
            XCTAssertFalse(override.expire(at: now.addingTimeInterval(Double(minutes * 60 - 1))))
            XCTAssertTrue(override.expire(at: now.addingTimeInterval(Double(minutes * 60))))
            XCTAssertEqual(override.mode, .automatic)
        }
        var override = ManualOverride()
        override.select(.available)
        XCTAssertFalse(override.expire(at: .distantFuture))
        override.select(.automatic)
        XCTAssertNil(override.expiresAt)
    }
    func testOnlyBrowserSignalsWorkWithoutAccessibilityAndIdleBridgeIsNotSetupFailure() {
        let browser = MeetingEvidence(service: .meet, isPresenting: false, signal: .browserTab)
        XCTAssertEqual(IndicatorPolicy.reason(mode: .automatic, evidence: [browser], trusted: false, browserConnected: true), .meeting)
        XCTAssertEqual(IndicatorPolicy.reason(mode: .automatic, evidence: [], trusted: false, browserConnected: true), .idle)
        XCTAssertEqual(IndicatorPolicy.reason(mode: .automatic, evidence: [MeetingEvidence(service: .zoom, isPresenting: false)], trusted: false), .setupNeeded)
        XCTAssertEqual(IndicatorPolicy.reason(mode: .automatic, evidence: [browser], trusted: false, paused: true, browserConnected: true), .paused)
    }
    func testMultipleTabsAndProfilesAggregateWithoutCancellingEachOther() {
        let snapshots = [BrowserBridgeSnapshot(states: [BrowserTabState(id: "1:0", service: .meet, inMeeting: true, presenting: false),
                                                        BrowserTabState(id: "2:0", service: .meet, inMeeting: false, presenting: false)]),
                         BrowserBridgeSnapshot(states: [BrowserTabState(id: "1:0", service: .teams, inMeeting: true, presenting: true)])]
        let policy = BrowserBridgePolicy(enabled: true, services: [.meet, .teams])
        let result = BrowserBridgeStore.evidence(from: snapshots, policy: policy)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains { $0.service == .meet && !$0.isPresenting })
        XCTAssertTrue(result.contains { $0.service == .teams && $0.isPresenting })
        XCTAssertEqual(IndicatorPolicy.reason(mode: .automatic, evidence: result, trusted: false), .presenting)
        XCTAssertTrue(BrowserBridgeStore.evidence(from: snapshots, policy: BrowserBridgePolicy(enabled: true, paused: true, services: [.meet, .teams])).isEmpty)
        XCTAssertTrue(BrowserBridgeStore.evidence(from: snapshots, policy: BrowserBridgePolicy()).isEmpty)
        XCTAssertEqual(BrowserBridgeStore.evidence(from: snapshots, policy: BrowserBridgePolicy(enabled: true, services: [.meet])).count, 1)
    }
    func testNativeMessagesRejectPrivateIdentifiersDuplicatesAndInvalidSharingState() {
        XCTAssertTrue(BrowserBridgeMessage(states: [BrowserTabState(id: "12:0", service: .meet, inMeeting: true, presenting: false)]).isValid)
        for id in ["https://meet.google.com/private", "user@example.com", "../policy", "-1:0", "1:", "1:0:3"] {
            XCTAssertFalse(BrowserTabState(id: id, service: .meet, inMeeting: true, presenting: false).isValid)
        }
        let state = BrowserTabState(id: "1:0", service: .zoom, inMeeting: false, presenting: true)
        XCTAssertFalse(BrowserBridgeMessage(states: [state]).isValid)
        let valid = BrowserTabState(id: "1:0", service: .zoom, inMeeting: true, presenting: true)
        XCTAssertFalse(BrowserBridgeMessage(states: [valid, valid]).isValid)
        XCTAssertFalse(BrowserBridgeMessage(states: [], protocolVersion: 99).isValid)
    }
    func testCacheExpiryAndSessionRemovalPreventStuckBusy() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BrowserBridgeStore(directory: directory)
        let now = Date(timeIntervalSince1970: 1000)
        let session = UUID()
        let state = BrowserTabState(id: "1:0", service: .meet, inMeeting: true, presenting: false)
        try store.writeSnapshot(BrowserBridgeSnapshot(receivedAt: now, states: [state]), session: session)
        XCTAssertEqual(store.freshSnapshots(at: now.addingTimeInterval(19)).count, 1)
        XCTAssertTrue(store.freshSnapshots(at: now.addingTimeInterval(20)).isEmpty)
        store.removeSnapshot(session: session)
        XCTAssertTrue(store.freshSnapshots(at: now).isEmpty)
        XCTAssertFalse(BrowserBridgeSnapshot(receivedAt: now.addingTimeInterval(10), states: [state]).isFresh(at: now))
    }
    func testFreshConnectionIsNotLostAmongStaleSessionFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BrowserBridgeStore(directory: directory)
        let now = Date(timeIntervalSince1970: 1000)
        for _ in 0..<40 { try store.writeSnapshot(BrowserBridgeSnapshot(receivedAt: now.addingTimeInterval(-60), states: []), session: UUID()) }
        try store.writeSnapshot(BrowserBridgeSnapshot(receivedAt: now, states: []), session: UUID())
        XCTAssertEqual(store.freshSnapshots(at: now).count, 1)
        store.clearSnapshots()
        XCTAssertTrue(store.freshSnapshots(at: now).isEmpty)
    }
    func testPolicyAndSnapshotHavePrivateFilePermissionsAndNoContentFields() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BrowserBridgeStore(directory: directory)
        let policy = BrowserBridgePolicy(enabled: true, services: [.zoom])
        try store.writePolicy(policy)
        XCTAssertEqual(store.readPolicy(), policy)
        try store.writeSnapshot(BrowserBridgeSnapshot(states: [BrowserTabState(id: "1:0", service: .zoom, inMeeting: true, presenting: false)]), session: UUID())
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
            XCTAssertEqual(permissions?.intValue, 0o600)
            let data = try Data(contentsOf: file)
            let text = String(decoding: data, as: UTF8.self)
            XCTAssertFalse(text.contains("https://"))
            XCTAssertFalse(text.contains("title"))
            XCTAssertFalse(text.contains("url"))
        }
    }
    func testNativeFramingSupportsMultipleMessagesAndEOF() throws {
        let pipe = Pipe()
        try NativeMessageIO.write(Data("{\"one\":true}".utf8), to: pipe.fileHandleForWriting)
        try NativeMessageIO.write(Data("{}".utf8), to: pipe.fileHandleForWriting)
        try pipe.fileHandleForWriting.close()
        XCTAssertEqual(try NativeMessageIO.read(from: pipe.fileHandleForReading), Data("{\"one\":true}".utf8))
        XCTAssertEqual(try NativeMessageIO.read(from: pipe.fileHandleForReading), Data("{}".utf8))
        XCTAssertNil(try NativeMessageIO.read(from: pipe.fileHandleForReading))
        try pipe.fileHandleForReading.close()
    }
    func testNativeFramingRejectsOversizeAndTruncatedPayloads() throws {
        for bytes: [UInt8] in [[0xff, 0xff, 0xff, 0x7f], [4, 0, 0, 0, 0x7b], [2, 0]] {
            let pipe = Pipe()
            try pipe.fileHandleForWriting.write(contentsOf: Data(bytes))
            try pipe.fileHandleForWriting.close()
            XCTAssertThrowsError(try NativeMessageIO.read(from: pipe.fileHandleForReading))
            try pipe.fileHandleForReading.close()
        }
    }
}
