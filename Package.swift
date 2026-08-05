// swift-tools-version: 6.0
// Convenience manifest for people with full Xcode installed (File → Open → Package.swift).
// The primary, Xcode-free build is ./scripts/build-app.sh (plain swiftc — works with
// just Command Line Tools).
import PackageDescription

let package = Package(
    name: "Stoguard",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Stoguard",
            path: "Sources/Stoguard",
            exclude: ["Resources"],
            swiftSettings: [
                // Xcode opens with Swift 6 toolchain; stay on Swift 5 language mode until
                // strict-concurrency cleanup is complete (matches build-app.sh behaviour).
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
