// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "penumbra",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "penumbra",
            path: "Sources",
            linkerSettings: [
                .unsafeFlags(["-F/System/Library/PrivateFrameworks", "-framework", "SkyLight"])
            ]
        )
    ]
)
