// swift-tools-version: 6.2
import PackageDescription

let releaseSettings: [SwiftSetting] = [
    .unsafeFlags(["-Osize"], .when(configuration: .release)),
    .unsafeFlags(
        ["-Xfrontend", "-disable-reflection-metadata"],
        .when(configuration: .release),
    ),
]

let package = Package(
    name: "Cornerlight",
    platforms: [.macOS("26.6")],
    products: [
        .executable(name: "Cornerlight", targets: ["Cornerlight"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.9.6",
        ),
    ],
    targets: [
        .executableTarget(
            name: "Cornerlight",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Launcher",
            swiftSettings: releaseSettings,
        ),
        .testTarget(
            name: "CornerlightTests",
            dependencies: ["Cornerlight"],
            path: "Tests/LauncherTests",
        ),
    ],
)
