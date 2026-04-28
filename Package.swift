// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BackgroundComputerUse",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BackgroundComputerUseKit", targets: ["BackgroundComputerUse"]),
        .executable(name: "BackgroundComputerUse", targets: ["BackgroundComputerUseServer"]),
        .executable(name: "SpotifyWebViewApp", targets: ["SpotifyWebViewApp"]),
    ],
    dependencies: [
        .package(path: "External/CodexAppServerClient"),
    ],
    targets: [
        .target(
            name: "BackgroundComputerUse",
            path: "Sources/BackgroundComputerUse"
        ),
        .executableTarget(
            name: "BackgroundComputerUseServer",
            dependencies: ["BackgroundComputerUse"],
            path: "Sources/BackgroundComputerUseServer"
        ),
        .executableTarget(
            name: "SpotifyWebViewApp",
            dependencies: [
                "BackgroundComputerUse",
                .product(name: "CodexAppServerClient", package: "CodexAppServerClient"),
            ],
            path: "Sources/SpotifyWebViewApp"
        ),
        .testTarget(
            name: "BackgroundComputerUseTests",
            dependencies: ["BackgroundComputerUse"],
            path: "Tests/BackgroundComputerUseTests"
        ),
    ]
)
