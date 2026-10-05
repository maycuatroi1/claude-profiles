// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ClaudeProfiles",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "ClaudeProfiles"),
        .testTarget(name: "ClaudeProfilesTests", dependencies: ["ClaudeProfiles"]),
    ]
)
