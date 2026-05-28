// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyGhost",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "KeyGhost",
            path: "KeyGhost",
            resources: [
                .copy("Resources/bindings.example.json")
            ]
        ),
    ]
)
