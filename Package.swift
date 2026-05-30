// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyGhost",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "KeyGhost",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "KeyGhost",
            resources: [
                .copy("Resources/bindings.example.json")
            ]
        ),
    ]
)
