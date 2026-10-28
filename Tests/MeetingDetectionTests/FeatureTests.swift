import XCTest
@testable import MeetingDetection

final class FeatureTests: XCTestCase {
    func testTimedBusyExpiresExactlyAtDeadlineAndAfterSleep() {
        for minutes in [15, 30, 60] {
            let start = Date(timeIntervalSince1970: 1000)
            var override = ManualOverride()
            override.select(.busy, at: start, minutes: minutes)
            XCTAssertFalse(override.expire(at: start.addingTimeInterval(Double(minutes * 60) - 1)))
            XCTAssertTrue(override.expire(at: start.addingTimeInterval(Double(minutes * 60) + 10)))
            XCTAssertEqual(override.mode, .automatic)
            XCTAssertNil(override.expiresAt)
        }
    }

    func testChangingModeCancelsTimerAndPresentingNeverAutoExpires() {
        var override = ManualOverride()
        override.select(.busy, minutes: 15)
        override.select(.presenting)
        XCTAssertNil(override.expiresAt)
        XCTAssertFalse(override.expire(at: Date.distantFuture))
        XCTAssertEqual(override.mode, .presenting)
        override.select(.busy)
        XCTAssertFalse(override.expire(at: Date.distantFuture))
        override.select(.automatic)
        XCTAssertNil(override.startedAt)
    }

    func testCompleteAbsenceClearsMeetingAndHungScanCannotKeepBusy() {
        let start = Date(timeIntervalSince1970: 1000)
        let evidence = MeetingEvidence(service: .zoom, isPresenting: false)
        var tracker = EvidenceTracker()
        tracker.accept([evidence], at: start)
        XCTAssertFalse(tracker.expire(at: start.addingTimeInterval(11)))
        XCTAssertTrue(tracker.expire(at: start.addingTimeInterval(12)))
        XCTAssertTrue(tracker.evidence.isEmpty)
        tracker.accept([evidence], at: start)
        tracker.accept([], at: start.addingTimeInterval(2))
        XCTAssertTrue(tracker.evidence.isEmpty)
        tracker.clear()
        XCTAssertNil(tracker.lastCompletedAt)
    }

    func testZoomMenuNeedsCurrentWindowAndPostMeetingDoesNotStayBusy() {
        let menu = [Control("Leave Meeting")]
        XCTAssertNil(Detection.evaluate(service: .zoom, controls: [], menuControls: menu))
        XCTAssertNil(Detection.evaluate(service: .zoom, controls: [Control("New meeting"), Control("Join a meeting")], windowTitle: "Zoom Workplace", menuControls: menu))
        let live = Detection.evaluate(service: .zoom, controls: [Control("Unmute")], windowTitle: "Zoom Meeting", menuControls: menu)
        XCTAssertEqual(live?.signal, .zoomMenu)
        XCTAssertNil(Detection.evaluate(service: .zoom, controls: [Control("Rejoin"), Control("Leave meeting")], windowTitle: "Zoom Meeting", menuControls: menu))
    }

    func testZoomSharingMenuIsCorroboratedAndMutedCallStillCounts() {
        let menus = [Control("Leave Meeting"), Control("Stop Share")]
        let call = Detection.evaluate(service: .zoom, controls: [Control("Unmute"), Control("Start video")], windowTitle: "Zoom Meeting", menuControls: menus)
        XCTAssertTrue(call!.isPresenting)
        XCTAssertNil(Detection.evaluate(service: .zoom, controls: [], windowTitle: "Zoom Workplace", menuControls: menus))
        XCTAssertNotNil(Detection.evaluate(service: .zoom, controls: [Control("Leave"), Control("Unmute"), Control("Start video")]))
    }

    func testReleaseVersionsCompareNumerically() {
        XCTAssertTrue(ReleaseVersion("v1.10.0")! > ReleaseVersion("1.9.9")!)
        XCTAssertEqual(ReleaseVersion("1.6"), ReleaseVersion("v1.6.0"))
        for invalid in ["", "1..2", "1.0-beta", "1.2.3.4", "latest", "1.-1.0"] { XCTAssertNil(ReleaseVersion(invalid)) }
    }

    func testUpdateLinksStayOnTheProjectsGitHubReleasePage() throws {
        func release(_ tag: String, _ url: String, prerelease: Bool = false) throws -> PublishedRelease {
            let data = try JSONSerialization.data(withJSONObject: ["tag_name": tag, "html_url": url, "draft": false, "prerelease": prerelease])
            return try JSONDecoder().decode(PublishedRelease.self, from: data)
        }
        let url = "https://github.com/chipset/Meeting-Busy/releases/tag/v1.7.0"
        XCTAssertNotNil(try release("v1.7.0", url).updateURL(currentVersion: "1.6.0"))
        XCTAssertNil(try release("v1.6.0", url).updateURL(currentVersion: "1.6.0"))
        XCTAssertNil(try release("v1.7.0", url, prerelease: true).updateURL(currentVersion: "1.6.0"))
        for unsafe in ["https://example.com/download", "http://github.com/chipset/Meeting-Busy/releases/tag/v2", "https://github.com/other/repo/releases/tag/v2", "https://github.com.evil.example/chipset/Meeting-Busy/releases/tag/v2", "https://github.com/chipset/Busy-Notifier/releases/tag/v2"] {
            XCTAssertNil(try release("v2.0.0", unsafe).updateURL(currentVersion: "1.6.0"))
        }
    }

    func testLogRotationExportAndClearLeaveOtherFilesAlone() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DiagnosticLogStore(directory: directory, maximumFileBytes: 1024, backups: 2)
        for index in 0..<100 {
            try store.append(DiagnosticEntry(event: .stateChanged, date: Date(timeIntervalSince1970: Double(index)), state: .meeting,
                                            evidence: [MeetingEvidence(service: .zoom, isPresenting: false)], trusted: true))
        }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 3)
        for file in files {
            XCTAssertLessThanOrEqual(try Data(contentsOf: file).count, 1024)
            let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
            XCTAssertEqual(permissions?.intValue, 0o600)
        }
        let data = try store.exportData()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try data.split(separator: 0x0A).map { try decoder.decode(DiagnosticEntry.self, from: Data($0)) }
        XCTAssertFalse(entries.isEmpty)
        XCTAssertEqual(entries.map(\.date), entries.map(\.date).sorted())
        let marker = directory.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: marker)
        try store.clear()
        XCTAssertEqual(try store.exportData().count, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
    }

    func testLogSchemaContainsOnlyStructuredDiagnostics() throws {
        let entry = DiagnosticEntry(event: .scan, state: .meeting, evidence: [MeetingEvidence(service: .teams, isPresenting: false)], scanMilliseconds: 150)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as! [String: Any]
        let allowed: Set<String> = ["date", "event", "state", "mode", "services", "signals", "trusted", "incomplete", "scanMilliseconds", "failureCodes"]
        XCTAssertTrue(Set(object.keys).isSubset(of: allowed))
        XCTAssertNil(object["message"])
        XCTAssertNil(object["title"])
        XCTAssertNil(object["url"])
    }
}
