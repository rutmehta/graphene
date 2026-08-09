// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Graphene",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Graphene",
            path: "Sources/Graphene",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
