// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Genesis",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Genesis", targets: ["Genesis"])
    ],
    targets: [
        .executableTarget(
            name: "Genesis",
            path: "Sources/Genesis"
        ),
        .testTarget(
            name: "GenesisTests",
            dependencies: ["Genesis"],
            path: "Tests/GenesisTests"
        )
    ]
)
