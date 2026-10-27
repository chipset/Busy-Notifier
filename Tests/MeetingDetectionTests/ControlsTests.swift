import XCTest
import CoreGraphics
@testable import MeetingDetection

final class ControlsTests: XCTestCase {
    func testPauseExpiresAcrossSleepAndSurvivesRelaunch() throws {
        let now = Date(timeIntervalSince1970: 1000)
        for minutes in [15, 60] {
            var pause = DetectionPause()
            pause.pause(minutes: minutes, at: now)
            let data = try JSONEncoder().encode(pause)
            pause = try JSONDecoder().decode(DetectionPause.self, from: data)
            XCTAssertTrue(pause.isPaused)
            XCTAssertFalse(pause.expire(at: now.addingTimeInterval(Double(minutes * 60 - 1))))
            XCTAssertTrue(pause.expire(at: now.addingTimeInterval(Double(minutes * 60 + 1))))
            XCTAssertFalse(pause.isPaused)
            XCTAssertNil(pause.resumeAt)
        }
    }

    func testIndefinitePauseAndResume() {
        var pause = DetectionPause()
        pause.pause()
        XCTAssertFalse(pause.expire(at: .distantFuture))
        XCTAssertTrue(pause.isPaused)
        pause.resume()
        XCTAssertFalse(pause.isPaused)
        XCTAssertNil(pause.resumeAt)
    }

    func testPauseSuppressesAutomaticDetectionButNotManualModesOrExplicitPreview() {
        let call = MeetingEvidence(service: .zoom, isPresenting: false)
        XCTAssertEqual(IndicatorPolicy.reason(mode: .automatic, evidence: [call], trusted: true, paused: true), .paused)
        XCTAssertFalse(IndicatorReason.paused.showsIndicator)
        XCTAssertEqual(IndicatorPolicy.reason(mode: .busy, evidence: [], trusted: false, paused: true), .forcedBusy)
        XCTAssertEqual(IndicatorPolicy.reason(mode: .automatic, evidence: [], trusted: false, preview: true, paused: true), .preview)
        XCTAssertEqual(IndicatorPolicy.reason(mode: .presenting, evidence: [call], trusted: true, preview: true, paused: true), .presenting)
    }

    func testAllServicesOffHasAnExplicitStateWithoutPermissionPrompt() {
        XCTAssertEqual(IndicatorPolicy.reason(mode: .automatic, evidence: [], trusted: false, servicesEnabled: false), .disabled)
        XCTAssertFalse(IndicatorReason.disabled.showsIndicator)
        XCTAssertEqual(IndicatorPolicy.reason(mode: .busy, evidence: [], trusted: false, servicesEnabled: false), .forcedBusy)
        XCTAssertEqual(IndicatorPolicy.reason(mode: .presenting, evidence: [], trusted: false, preview: true, servicesEnabled: false), .presenting)
    }

    func testDisabledBrowserServicesAreIgnoredAndChoicesPersist() throws {
        let selected: Set<MeetingService> = [.teams, .webex]
        let saved = try JSONDecoder().decode(Set<MeetingService>.self, from: JSONEncoder().encode(selected))
        XCTAssertEqual(saved, selected)
        XCTAssertNil(Detection.webService(url: "https://app.zoom.us/wc/123/join", enabledServices: saved))
        XCTAssertNil(Detection.webService(url: "https://meet.google.com/abc-defg-hij", enabledServices: saved))
        XCTAssertEqual(Detection.webService(url: "https://teams.microsoft.com/v2", enabledServices: saved), .teams)
        XCTAssertEqual(Detection.webService(url: "https://company.webex.com/meet/person", enabledServices: saved), .webex)
        XCTAssertNil(Detection.webService(url: "https://teams.microsoft.com/v2", enabledServices: []))
    }

    func testShortcutValidationFindsDuplicatesAndUnsafeUnmodifiedKeys() {
        var configuration = ShortcutConfiguration()
        XCTAssertNil(configuration.validationMessage)
        configuration.busy = configuration.automatic
        XCTAssertNotNil(configuration.validationMessage)
        configuration = ShortcutConfiguration()
        configuration.busy = ShortcutBinding(key: .b, command: false, option: false, control: false, shift: true)
        XCTAssertNotNil(configuration.validationMessage)
        configuration.busy.option = true
        XCTAssertNil(configuration.validationMessage)
    }

    func testShortcutsPersistAndEachKeyHasUniqueCode() throws {
        var configuration = ShortcutConfiguration()
        configuration.automatic = ShortcutBinding(key: .f6, command: false, option: true, control: true, shift: true)
        let copy = try JSONDecoder().decode(ShortcutConfiguration.self, from: JSONEncoder().encode(configuration))
        XCTAssertEqual(copy, configuration)
        XCTAssertEqual(copy.automatic.label, "⌃⌥⇧F6")
        XCTAssertEqual(Set(ShortcutKey.allCases.map(\.keyCode)).count, ShortcutKey.allCases.count)
    }

    func testPresetRoundTripIncludesAllAppearanceChoices() throws {
        let appearance = IndicatorAppearance(scale: 1.5, transparency: 0.3, x: 0.75, y: 0.6, displayID: 42,
                                              text: "Do not disturb", color: IndicatorColor(red: 0.1, green: 0.8, blue: 0.5), allDisplays: true)
        let preset = AppearancePreset(name: "  Focus  ", appearance: appearance)
        let decoded = try JSONDecoder().decode(AppearancePreset.self, from: JSONEncoder().encode(preset))
        XCTAssertEqual(decoded, preset)
        XCTAssertEqual(decoded.name, "Focus")
        XCTAssertEqual(decoded.appearance, appearance)
        XCTAssertEqual(AppearancePreset.defaults.map(\.name), ["Meeting", "Recording", "Do not disturb"])
    }

    func testOldAppearanceDefaultsToOneDisplayAndMovementKeepsEveryDisplayChoice() throws {
        let old = try JSONDecoder().decode(IndicatorAppearance.self, from: Data(#"{"text":"Busy","scale":1}"#.utf8))
        XCTAssertFalse(old.allDisplays)
        let all = IndicatorAppearance(allDisplays: true)
        let moved = all.repositioned(to: CGPoint(x: 100, y: 200), in: CGRect(x: 0, y: 0, width: 1440, height: 900), displayID: 42)
        XCTAssertTrue(moved.allDisplays)
        let other = CGRect(x: -1920, y: -200, width: 1920, height: 1056)
        XCTAssertTrue(other.contains(moved.frame(in: other)))
    }

    func testReportContainsSanitizedStateAndNoAppContentOrUserPathFields() {
        let report = DetectionReport(version: "0.0.1", build: "11", osVersion: "26.0", date: Date(timeIntervalSince1970: 0),
                                     mode: .automatic, reason: .meeting, trusted: true, paused: false,
                                     enabledServices: [.zoom, .teams], evidence: [MeetingEvidence(service: .zoom, isPresenting: false)],
                                     lastScanAt: Date(timeIntervalSince1970: 0), failureCodes: [-25211])
        let text = report.rendered()
        XCTAssertTrue(text.contains("Expected behavior:"))
        XCTAssertTrue(text.contains("Zoom: Active call controls"))
        XCTAssertTrue(text.contains("-25211"))
        XCTAssertTrue(text.contains("No logs are attached automatically"))
        XCTAssertFalse(text.contains("/Users/"))
        XCTAssertFalse(text.contains("http"))
        XCTAssertFalse(text.contains("appearance"))
    }
}
