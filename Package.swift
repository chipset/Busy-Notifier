// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeetingBusy",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MeetingBusy", targets: ["MeetingBusy"]),
               .executable(name: "MeetingBusyBrowserHost", targets: ["MeetingBusyBrowserHost"])],
    targets: [
        .target(name: "MeetingDetection"),
        .executableTarget(name: "MeetingBusy", dependencies: ["MeetingDetection"]),
        .executableTarget(name: "MeetingBusyBrowserHost", dependencies: ["MeetingDetection"]),
        .testTarget(name: "MeetingDetectionTests", dependencies: ["MeetingDetection"])
    ]
)
