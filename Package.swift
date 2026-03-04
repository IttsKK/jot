// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Jot",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Jot", targets: ["Jot"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.3"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.4")
    ],
    targets: [
        .executableTarget(
            name: "Jot",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Jot",
            exclude: [
                "App/Info.plist",
                "Resources"
            ]
        ),
        .testTarget(
            name: "JotTests",
            dependencies: ["Jot"],
            path: "Tests/JotTests"
        )
    ]
)
