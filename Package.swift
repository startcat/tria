// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "tria",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TriaCore", targets: ["TriaCore"]),
        .library(name: "TriaKit", targets: ["TriaKit"]),
        .executable(name: "tria", targets: ["tria"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/CoreOffice/CoreXLSX.git", from: "0.14.0"),
    ],
    targets: [
        .target(name: "TriaCore", dependencies: ["Yams"]),
        .target(name: "TriaKit", dependencies: ["TriaCore", "Yams", "CoreXLSX"]),
        .target(
            name: "TriaCLI",
            dependencies: ["TriaKit", .product(name: "ArgumentParser", package: "swift-argument-parser")]
        ),
        .executableTarget(name: "tria", dependencies: ["TriaCLI"]),
        .target(name: "TriaTestSupport", dependencies: ["TriaKit"], path: "Tests/TriaTestSupport"),
        .testTarget(name: "TriaKitTests", dependencies: ["TriaKit", "TriaTestSupport"]),
        .testTarget(
            name: "TriaCLITests",
            dependencies: ["TriaCLI", "TriaKit", "TriaTestSupport",
                           .product(name: "ArgumentParser", package: "swift-argument-parser")]
        ),
    ]
)
