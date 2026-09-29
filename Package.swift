// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WinTab",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0"),
    ],
    targets: [
        .target(name: "SwitcherCore"),
        .executableTarget(
            name: "WinTab",
            dependencies: [
                "SwitcherCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .testTarget(name: "SwitcherCoreTests", dependencies: ["SwitcherCore"]),
    ]
)
