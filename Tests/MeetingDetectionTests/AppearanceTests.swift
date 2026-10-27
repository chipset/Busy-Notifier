import XCTest
import CoreGraphics
@testable import MeetingDetection

final class AppearanceTests: XCTestCase {
    func testPositionsOnDisplayWithNegativeOrigin() {
        let display = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let topLeft = IndicatorAppearance().frame(in: display)
        XCTAssertEqual(topLeft.minX, display.minX + 12)
        XCTAssertEqual(topLeft.maxY, display.maxY - 12)
        let bottomRight = IndicatorAppearance(x: 1, y: 1).frame(in: display)
        XCTAssertEqual(bottomRight.maxX, display.maxX - 12)
        XCTAssertEqual(bottomRight.minY, display.minY + 12)
        let center = IndicatorAppearance(x: 0.5, y: 0.5).frame(in: display)
        XCTAssertEqual(center.midX, display.midX)
        XCTAssertEqual(center.midY, display.midY)
    }

    func testLargeIndicatorStaysInsideSmallDisplay() {
        let display = CGRect(x: 30, y: 40, width: 240, height: 180)
        let frame = IndicatorAppearance(scale: 2.5, x: 1, y: 1).frame(in: display)
        XCTAssertTrue(display.contains(frame))
        XCTAssertGreaterThan(frame.width, 0)
    }

    func testInvalidSavedValuesAreBounded() {
        let invalid = IndicatorAppearance(scale: .infinity, transparency: -1, x: 2, y: .nan).normalized
        XCTAssertEqual(invalid.scale, 1)
        XCTAssertEqual(invalid.transparency, 0)
        XCTAssertEqual(invalid.x, 1)
        XCTAssertEqual(invalid.y, 0)
        XCTAssertEqual(IndicatorAppearance(transparency: 1).normalized.transparency, 0.9)
    }

    func testAppearanceRoundTripsForPersistence() throws {
        let value = IndicatorAppearance(scale: 1.5, transparency: 0.35, x: 1, y: 0.25, displayID: 42, text: "In a meeting", color: IndicatorColor(red: 0.2, green: 0.4, blue: 0.8))
        XCTAssertEqual(try JSONDecoder().decode(IndicatorAppearance.self, from: JSONEncoder().encode(value)), value)
    }

    func testExistingSettingsKeepAppearanceWhenTextIsAdded() throws {
        let legacy = Data(#"{"scale":1.5,"transparency":0.35,"x":1,"y":0.25,"displayID":42}"#.utf8)
        let value = try JSONDecoder().decode(IndicatorAppearance.self, from: legacy)
        XCTAssertEqual(value, IndicatorAppearance(scale: 1.5, transparency: 0.35, x: 1, y: 0.25, displayID: 42, text: "Busy"))
    }

    func testBlankMessageUsesDefaultAndCustomMessagePreservesUnicode() {
        XCTAssertEqual(IndicatorAppearance(text: " \n\t ").normalized.text, "Busy")
        XCTAssertEqual(IndicatorAppearance(text: "  In a meeting 🎧  ").normalized.text, "In a meeting 🎧")
    }

    func testColorDefaultsWhenUpgradingAndKeepsOtherPreferences() throws {
        let legacy = Data(#"{"scale":1.5,"transparency":0.35,"x":1,"y":0.25,"text":"On a call"}"#.utf8)
        let value = try JSONDecoder().decode(IndicatorAppearance.self, from: legacy)
        XCTAssertEqual(value.color, .busyRed)
        XCTAssertEqual(value.text, "On a call")
        XCTAssertEqual(value.scale, 1.5)
        XCTAssertEqual(value.transparency, 0.35)
    }

    func testColorsAreBoundedAndTextContrastsWithFill() {
        XCTAssertEqual(IndicatorColor(red: -1, green: 2, blue: .nan).normalized,
                       IndicatorColor(red: 0, green: 1, blue: IndicatorColor.busyRed.blue))
        XCTAssertTrue(IndicatorColor(red: 1, green: 1, blue: 1).prefersDarkText)
        XCTAssertFalse(IndicatorColor(red: 0, green: 0, blue: 0).prefersDarkText)
        XCTAssertFalse(IndicatorColor.busyRed.prefersDarkText)
    }

    func testDraggedPositionRoundTripsOnSecondaryDisplay() {
        let display = CGRect(x: -1920, y: -1080, width: 1920, height: 1056)
        let original = IndicatorAppearance(scale: 1.5, transparency: 0.35, text: "On a call", color: IndicatorColor(red: 0.1, green: 0.2, blue: 0.8))
        let origin = CGPoint(x: -1440, y: -700)
        let moved = original.repositioned(to: origin, in: display, displayID: 99)
        let frame = moved.frame(in: display)
        XCTAssertEqual(frame.origin.x, origin.x, accuracy: 0.001)
        XCTAssertEqual(frame.origin.y, origin.y, accuracy: 0.001)
        XCTAssertEqual(moved.displayID, 99)
        XCTAssertEqual(moved.scale, original.scale)
        XCTAssertEqual(moved.transparency, original.transparency)
        XCTAssertEqual(moved.text, original.text)
        XCTAssertEqual(moved.color, original.color)
    }

    func testDraggedPositionIsClampedInsideDisplay() {
        let display = CGRect(x: 0, y: 25, width: 1440, height: 850)
        let moved = IndicatorAppearance().repositioned(to: CGPoint(x: 5000, y: -900), in: display, displayID: 10)
        XCTAssertEqual(moved.x, 1)
        XCTAssertEqual(moved.y, 1)
        XCTAssertTrue(display.contains(moved.frame(in: display)))
    }

    func testDraggingOnDisplayWithNoTravelAvoidsDivisionByZero() {
        let display = CGRect(x: 0, y: 0, width: 100, height: 80)
        let moved = IndicatorAppearance(scale: 2.5).repositioned(to: CGPoint(x: 40, y: 50), in: display, displayID: 11)
        XCTAssertEqual(moved.x, 0)
        XCTAssertEqual(moved.y, 0)
        XCTAssertTrue(display.contains(moved.frame(in: display)))
    }
}
