// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "TrackpadHandwriting",
    platforms: [.macOS(.v26)],
    targets: [
        .target(
            name: "CMultitouch",
            path: "Sources/CMultitouch"
        ),
        // 呼叫系統內建手寫引擎（CoreHandwriting 私有框架）的 Objective-C 橋接
        .target(
            name: "CAppleHandwriting",
            path: "Sources/CAppleHandwriting",
            linkerSettings: [.linkedFramework("Foundation"), .linkedFramework("CoreGraphics")]
        ),
        .executableTarget(
            name: "TrackpadHandwriting",
            dependencies: ["CMultitouch", "CAppleHandwriting"],
            path: "Sources/TrackpadHandwriting",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Vision"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
