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
            // bindings.example.json is embedded as a string literal in
            // Bindings.swift (see BindingsLoader.exampleConfigJSON) and kept in
            // the repo only as human-readable documentation, so exclude it from
            // the build rather than shipping it as a resource bundle — an SPM
            // executableTarget's Bundle.module can't be located inside a signed
            // .app, which crashed the app on launch.
            exclude: [
                "Resources/bindings.example.json"
            ]
        ),
    ]
)
