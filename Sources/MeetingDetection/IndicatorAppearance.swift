import Foundation
import CoreGraphics

public struct IndicatorAppearance: Codable, Equatable, Sendable {
    public var scale: Double
    public var transparency: Double
    /// Fractions of the available travel, measured from the upper left.
    public var x: Double
    public var y: Double
    public var displayID: UInt32?
    public var text: String
    public var color: IndicatorColor

    public init(scale: Double = 1, transparency: Double = 0, x: Double = 0, y: Double = 0, displayID: UInt32? = nil, text: String = "Busy", color: IndicatorColor = .busyRed) {
        self.scale = scale
        self.transparency = transparency
        self.x = x
        self.y = y
        self.displayID = displayID
        self.text = text
        self.color = color
    }

    private enum CodingKeys: String, CodingKey { case scale, transparency, x, y, displayID, text, color }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(scale: try values.decodeIfPresent(Double.self, forKey: .scale) ?? 1,
                  transparency: try values.decodeIfPresent(Double.self, forKey: .transparency) ?? 0,
                  x: try values.decodeIfPresent(Double.self, forKey: .x) ?? 0,
                  y: try values.decodeIfPresent(Double.self, forKey: .y) ?? 0,
                  displayID: try values.decodeIfPresent(UInt32.self, forKey: .displayID),
                  text: try values.decodeIfPresent(String.self, forKey: .text) ?? "Busy",
                  color: try values.decodeIfPresent(IndicatorColor.self, forKey: .color) ?? .busyRed)
    }

    public var normalized: Self {
        Self(scale: clamp(scale, 0.5...2.5, fallback: 1),
             transparency: clamp(transparency, 0...0.9, fallback: 0),
             x: clamp(x, 0...1, fallback: 0), y: clamp(y, 0...1, fallback: 0), displayID: displayID,
             text: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Busy" : text.trimmingCharacters(in: .whitespacesAndNewlines),
             color: color.normalized)
    }

    public func frame(in screen: CGRect) -> CGRect {
        let value = normalized
        let margin = min(12, max(0, min(screen.width, screen.height) / 4))
        let width = min(168 * value.scale, max(0, screen.width - 2 * margin))
        let height = min(82 * value.scale, max(0, screen.height - 2 * margin))
        let travelX = max(0, screen.width - 2 * margin - width)
        let travelY = max(0, screen.height - 2 * margin - height)
        return CGRect(x: screen.minX + margin + travelX * value.x,
                      y: screen.maxY - margin - height - travelY * value.y, width: width, height: height)
    }

    /// Convert a dragged window origin back to the same normalized coordinates used by Settings.
    public func repositioned(to origin: CGPoint, in screen: CGRect, displayID: UInt32) -> Self {
        var value = normalized
        let margin = min(12, max(0, min(screen.width, screen.height) / 4))
        let size = value.frame(in: screen).size
        let travelX = max(0, screen.width - 2 * margin - size.width)
        let travelY = max(0, screen.height - 2 * margin - size.height)
        value.x = travelX > 0 ? (origin.x - screen.minX - margin) / travelX : 0
        value.y = travelY > 0 ? (screen.maxY - margin - size.height - origin.y) / travelY : 0
        value.displayID = displayID
        return value.normalized
    }

    private func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}

public struct IndicatorColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public static let busyRed = IndicatorColor(red: 0.83, green: 0.06, blue: 0.12)

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var normalized: Self {
        Self(red: component(red, fallback: Self.busyRed.red),
             green: component(green, fallback: Self.busyRed.green),
             blue: component(blue, fallback: Self.busyRed.blue))
    }

    /// Choose whichever of black and white has higher contrast against the solid fill.
    public var prefersDarkText: Bool {
        let color = normalized
        let luminance = 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
        return (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05)
    }

    private func component(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : fallback
    }

    private func linear(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
}
