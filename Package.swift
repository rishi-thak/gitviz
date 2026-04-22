// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GitStatus",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "GitStatus",
            targets: ["GitStatus"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "GitStatus"
        ),
        .testTarget(
            name: "GitStatusTests",
            dependencies: ["GitStatus"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
