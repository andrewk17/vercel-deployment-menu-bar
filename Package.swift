// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Deploylight",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Deploylight",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "DeploylightTests",
            dependencies: ["Deploylight"]
        ),
    ]
)
