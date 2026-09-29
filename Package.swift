// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WinTab",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SwitcherCore"),
        .executableTarget(name: "WinTab", dependencies: ["SwitcherCore"]),
        .testTarget(name: "SwitcherCoreTests", dependencies: ["SwitcherCore"]),
    ]
)
