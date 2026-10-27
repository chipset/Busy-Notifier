import XCTest
@testable import MeetingDetection

final class DetectionTests: XCTestCase {
    func testRunningClientAndPrejoinAreNotMeetings() {
        for service in MeetingService.allCases {
            XCTAssertNil(Detection.evaluate(service: service, controls: []))
            XCTAssertNil(Detection.evaluate(service: service, controls: [Control("Join now"), Control("Microphone")]))
        }
    }

    func testActiveCallsAcrossProviders() {
        XCTAssertEqual(Detection.evaluate(service: .meet, controls: [Control("Leave call (⌘ + W)")]), MeetingEvidence(service: .meet, isPresenting: false))
        XCTAssertNotNil(Detection.evaluate(service: .teams, controls: [Control("Leave"), Control("Unmute (⌘ + Shift + M)")]))
        XCTAssertNotNil(Detection.evaluate(service: .webex, controls: [Control("Leave or end meeting")]))
    }

    func testChatTextAndSimilarLabelsDoNotCount() {
        XCTAssertNil(Detection.evaluate(service: .teams, controls: [Control("Leave meeting", actionable: false)]))
        XCTAssertNil(Detection.evaluate(service: .teams, controls: [Control("Leave feedback"), Control("Leave team")]))
        XCTAssertNil(Detection.evaluate(service: .teams, controls: [Control("Leave")]))
        XCTAssertNil(Detection.evaluate(service: .meet, controls: [Control("Learn how to leave call")]))
    }

    func testSharingControlsHideIndicatorEvenWithoutCallToolbar() {
        for service in MeetingService.allCases {
            for label in ["Stop sharing", "Stop presenting", "Stop screen sharing", "Stop sharing, keyboard shortcut"] {
                let evidence = Detection.evaluate(service: service, controls: [Control(label)])
                XCTAssertEqual(evidence?.isPresenting, true)
                XCTAssertFalse(IndicatorPolicy.visible(mode: .automatic, evidence: [evidence!], trusted: true))
                XCTAssertFalse(IndicatorPolicy.visible(mode: .busy, evidence: [evidence!], trusted: true))
            }
        }
    }

    func testSharingSomeoneElsesPresentationDoesNotHideIndicator() {
        let evidence = Detection.evaluate(service: .meet, controls: [Control("Leave call"), Control("Alice is presenting", actionable: false), Control("Present now")])!
        XCTAssertFalse(evidence.isPresenting)
        XCTAssertTrue(IndicatorPolicy.visible(mode: .automatic, evidence: [evidence], trusted: true))
    }

    func testWebOriginsAreVerified() {
        XCTAssertEqual(Detection.webService(url: "https://meet.google.com/abc-defg-hij"), .meet)
        XCTAssertEqual(Detection.webService(url: "https://teams.microsoft.com/v2/"), .teams)
        XCTAssertEqual(Detection.webService(url: "https://teams.cloud.microsoft/meet/123"), .teams)
        XCTAssertEqual(Detection.webService(url: "https://company.webex.com/meet/person"), .webex)
        for url in ["https://meet.google.com/", "https://notwebex.com/meet", "https://meet.google.com.evil.example/abc", "https://example.org/?url=https://teams.microsoft.com", "file:///meet.google.com/abc"] {
            XCTAssertNil(Detection.webService(url: url), url)
        }
    }

    func testNativeApplicationsAreRecognized() {
        XCTAssertEqual(Detection.nativeService(bundleID: "com.microsoft.teams2"), .teams)
        XCTAssertEqual(Detection.nativeService(bundleID: "com.cisco.webexteams"), .webex)
        XCTAssertNil(Detection.nativeService(bundleID: "com.apple.TextEdit"))
    }

    func testOverridesAndPermissionChanges() {
        let call = MeetingEvidence(service: .teams, isPresenting: false)
        XCTAssertFalse(IndicatorPolicy.visible(mode: .automatic, evidence: [], trusted: true))
        XCTAssertFalse(IndicatorPolicy.visible(mode: .automatic, evidence: [call], trusted: false))
        XCTAssertTrue(IndicatorPolicy.visible(mode: .busy, evidence: [], trusted: false))
        XCTAssertFalse(IndicatorPolicy.visible(mode: .presenting, evidence: [call], trusted: true))
        XCTAssertFalse(IndicatorPolicy.visible(mode: .presenting, evidence: [], trusted: false))
    }

    func testAnyPresentationSuppressesSimultaneousCalls() {
        let calls = [MeetingEvidence(service: .teams, isPresenting: false), MeetingEvidence(service: .meet, isPresenting: true)]
        XCTAssertFalse(IndicatorPolicy.visible(mode: .automatic, evidence: calls, trusted: true))
    }

    func testZoomHostAndParticipantCalls() {
        XCTAssertEqual(Detection.nativeService(bundleID: "us.zoom.xos"), .zoom)
        for controls in [[Control("End"), Control("Mute, currently unmuted")],
                         [Control("Leave"), Control("Start video (⌘+Shift+V)")],
                         [Control("Leave Meeting")], [Control("End Meeting for All")],
                         [Control("Join audio"), Control("Leave")]] {
            XCTAssertEqual(Detection.evaluate(service: .zoom, controls: controls), MeetingEvidence(service: .zoom, isPresenting: false))
        }
        XCTAssertNil(Detection.evaluate(service: .zoom, controls: [Control("End")]))
        XCTAssertNil(Detection.evaluate(service: .zoom, controls: [Control("Leave")]))
        XCTAssertNil(Detection.evaluate(service: .zoom, controls: [Control("Join"), Control("Start video")]))
        XCTAssertNil(Detection.evaluate(service: .zoom, controls: [Control("Leave meeting", actionable: false)]))
    }

    func testZoomSharingAndWebClient() {
        let sharing = Detection.evaluate(service: .zoom, controls: [Control("Stop Share")])!
        XCTAssertTrue(sharing.isPresenting)
        XCTAssertFalse(IndicatorPolicy.visible(mode: .busy, evidence: [sharing], trusted: true))
        let watching = Detection.evaluate(service: .zoom, controls: [Control("Leave Meeting"), Control("Alice is screen sharing", actionable: false)])!
        XCTAssertFalse(watching.isPresenting)
        XCTAssertTrue(IndicatorPolicy.visible(mode: .automatic, evidence: [watching], trusted: true))
        XCTAssertEqual(Detection.webService(url: "https://app.zoom.us/wc/123/join"), .zoom)
        XCTAssertEqual(Detection.webService(url: "https://company.zoom.com/wc/123/start"), .zoom)
        XCTAssertNil(Detection.webService(url: "https://zoom.us.evil.example/wc/123"))
        XCTAssertNil(Detection.webService(url: "https://notzoom.us/wc/123"))
    }

    func testZoomHiddenLeaveButtonUsesMeetingToolbar() {
        let toolbar = [Control("Participants"), Control("Reactions"), Control("Share")]
        XCTAssertNotNil(Detection.evaluate(service: .zoom, controls: toolbar, windowTitle: "Zoom Meeting"))
        XCTAssertNotNil(Detection.evaluate(service: .zoom, controls: toolbar, windowTitle: "Zoom Webinar"))
        XCTAssertNil(Detection.evaluate(service: .zoom, controls: toolbar, windowTitle: "Zoom Workplace"))
        XCTAssertNil(Detection.evaluate(service: .zoom, controls: toolbar + [Control("Join meeting")], windowTitle: "Zoom Meeting"))
        XCTAssertNil(Detection.evaluate(service: .zoom, controls: [], windowTitle: "Zoom Meeting"))
    }

    func testZoomEnabledMenuCommandsAndMultilineLabels() {
        XCTAssertNotNil(Detection.evaluate(service: .zoom, controls: [Control("Leave Meeting\t⌘W")]))
        XCTAssertNil(Detection.evaluate(service: .zoom, controls: [Control("Leave Meeting", actionable: false)]))
        let sharing = Detection.evaluate(service: .zoom, controls: [Control("Stop Share\n⌘⇧S")])!
        XCTAssertTrue(sharing.isPresenting)
        XCTAssertFalse(IndicatorPolicy.visible(mode: .automatic, evidence: [sharing], trusted: true))
    }

    func testLeavingZoomClearsAutomaticIndicator() {
        let call = Detection.evaluate(service: .zoom, controls: [Control("Leave"), Control("Mute")])!
        XCTAssertEqual(IndicatorPolicy.reason(mode: .automatic, evidence: [call], trusted: true), .meeting)
        XCTAssertEqual(IndicatorPolicy.reason(mode: .automatic, evidence: [], trusted: true), .idle)
        XCTAssertFalse(IndicatorPolicy.reason(mode: .automatic, evidence: [], trusted: true).showsIndicator)
    }

    func testMissingPermissionDoesNotReportMeetingOrShowBusy() {
        let stale = MeetingEvidence(service: .zoom, isPresenting: false)
        let state = IndicatorPolicy.reason(mode: .automatic, evidence: [stale], trusted: false)
        XCTAssertEqual(state, .setupNeeded)
        XCTAssertFalse(state.showsIndicator)
    }

    func testPreviewIsDistinguishedFromMeetingAndSetupNeeded() {
        XCTAssertEqual(IndicatorPolicy.reason(mode: .automatic, evidence: [], trusted: false, preview: true), .preview)
        XCTAssertEqual(IndicatorPolicy.reason(mode: .automatic, evidence: [], trusted: true, preview: true), .preview)
        XCTAssertEqual(IndicatorPolicy.reason(mode: .automatic, evidence: [], trusted: false, preview: false), .setupNeeded)
        let sharing = MeetingEvidence(service: .zoom, isPresenting: true)
        XCTAssertEqual(IndicatorPolicy.reason(mode: .automatic, evidence: [sharing], trusted: true, preview: true), .presenting)
        XCTAssertEqual(IndicatorPolicy.reason(mode: .presenting, evidence: [], trusted: false, preview: true), .presenting)
        XCTAssertFalse(IndicatorPolicy.reason(mode: .presenting, evidence: [], trusted: false, preview: true).showsIndicator)
    }
}
