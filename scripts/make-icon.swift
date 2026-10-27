import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Vector artwork, rendered at every standard macOS icon size without GUI access.
// The white camera and the minus badge identify a meeting/busy status utility.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rounded(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func render(pixels: Int, filename: String) throws {
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)
    let plate = rounded(CGRect(x: 64, y: 64, width: 896, height: 896), radius: 202)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 22,
                      color: CGColor(red: 0.2, green: 0, blue: 0.03, alpha: 0.24))
    context.addPath(plate)
    context.setFillColor(CGColor(red: 0.92, green: 0.10, blue: 0.19, alpha: 1))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(plate)
    context.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 1, green: 0.34, blue: 0.39, alpha: 1),
        CGColor(red: 0.84, green: 0.07, blue: 0.20, alpha: 1)
    ] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 180, y: 960), end: CGPoint(x: 830, y: 64), options: [])
    context.restoreGState()
    context.addPath(plate)
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
    context.setLineWidth(3)
    context.strokePath()

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 16,
                      color: CGColor(red: 0.35, green: 0, blue: 0.03, alpha: 0.2))
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.addPath(rounded(CGRect(x: 220, y: 426, width: 364, height: 248), radius: 55))
    context.fillPath()
    context.beginPath()
    context.move(to: CGPoint(x: 618, y: 600))
    context.addLine(to: CGPoint(x: 755, y: 675))
    context.addQuadCurve(to: CGPoint(x: 780, y: 660), control: CGPoint(x: 780, y: 688))
    context.addLine(to: CGPoint(x: 780, y: 440))
    context.addQuadCurve(to: CGPoint(x: 755, y: 425), control: CGPoint(x: 780, y: 412))
    context.addLine(to: CGPoint(x: 618, y: 500))
    context.closePath()
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -8), blur: 12,
                      color: CGColor(red: 0.25, green: 0, blue: 0.04, alpha: 0.22))
    context.setFillColor(CGColor(red: 0.48, green: 0.035, blue: 0.12, alpha: 1))
    context.fillEllipse(in: CGRect(x: 588, y: 232, width: 216, height: 216))
    context.restoreGState()
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.addPath(rounded(CGRect(x: 636, y: 326, width: 120, height: 28), radius: 14))
    context.fillPath()

    let image = context.makeImage()!
    let file = output.appendingPathComponent(filename)
    let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "MeetingBusyIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to write \(filename)"])
    }
}

for size in [16, 32, 128, 256, 512] {
    try render(pixels: size, filename: "icon_\(size)x\(size).png")
    try render(pixels: size * 2, filename: "icon_\(size)x\(size)@2x.png")
}

// Store PNG representations in an ICNS family directly. This keeps packaging
// independent of iconutil's image-conversion services in restricted build sessions.
func bigEndian(_ value: Int) -> Data {
    var integer = UInt32(value).bigEndian
    return withUnsafeBytes(of: &integer) { Data($0) }
}

let representations = [
    ("icp4", "icon_16x16.png"), ("ic11", "icon_16x16@2x.png"),
    ("icp5", "icon_32x32.png"), ("ic12", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"), ("ic13", "icon_128x128@2x.png"),
    ("ic08", "icon_256x256.png"), ("ic14", "icon_256x256@2x.png"),
    ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png")
]
var body = Data()
for (type, filename) in representations {
    let png = try Data(contentsOf: output.appendingPathComponent(filename))
    body.append(Data(type.utf8))
    body.append(bigEndian(png.count + 8))
    body.append(png)
}
var family = Data("icns".utf8)
family.append(bigEndian(body.count + 8))
family.append(body)
try family.write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
