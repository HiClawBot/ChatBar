// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "ChatBar",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ChatBar", targets: ["ChatBarApp"])
    ],
    targets: [
        .target(name: "ChatBarCore", path: "Sources/ChatBarCore"),
        .executableTarget(
            name: "ChatBarApp",
            dependencies: ["ChatBarCore"],
            path: "Sources/ChatBarApp",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ChatBarCoreTests",
            dependencies: ["ChatBarCore"],
            path: "Tests/ChatBarCoreTests"
        )
    ]
)
