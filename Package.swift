// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ios-sdk",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "LivoStudioAPI", targets: ["LivoStudioAPI"]),
        .library(name: "LivoStudioKit", targets: ["LivoStudioKit"]),
    ],
    dependencies: [
        // RealtimeKit Core ships as a binary XCFramework. Pin by semver so this
        // package can itself be consumed by version (SPM forbids branch pins
        // inside a versioned package).
        .package(url: "https://github.com/cloudflare/realtimekit-ios-core.git", from: "3.1.0"),
    ],
    targets: [
        .target(name: "LivoStudioAPI"),
        .target(
            name: "LivoStudioKit",
            dependencies: [
                "LivoStudioAPI",
                .product(name: "RealtimeKit", package: "realtimekit-ios-core"),
            ]
        ),
        .testTarget(name: "LivoStudioAPITests", dependencies: ["LivoStudioAPI"]),
        .testTarget(name: "LivoStudioKitTests", dependencies: ["LivoStudioKit"]),
    ]
)
