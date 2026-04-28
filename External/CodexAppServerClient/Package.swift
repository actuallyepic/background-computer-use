// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "codex-app-server-client",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "CodexAppServerClient",
            targets: ["CodexAppServerClient"]
        ),
        .library(
            name: "CodexAppServerProtocol",
            targets: ["CodexAppServerProtocol"]
        ),
        .executable(
            name: "CodexAppServerExample",
            targets: ["CodexAppServerExample"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "CodexAppServerProtocol"
        ),
        .target(
            name: "CodexAppServerClient",
            dependencies: ["CodexAppServerProtocol"]
        ),
        .executableTarget(
            name: "CodexAppServerExample",
            dependencies: ["CodexAppServerClient"]
        ),
        .testTarget(
            name: "CodexAppServerTests",
            dependencies: ["CodexAppServerClient"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
