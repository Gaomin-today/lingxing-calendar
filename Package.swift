// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LingxingCalendar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LingxiCore", targets: ["LingxiCore"]),
        .executable(name: "LingxingCalendar", targets: ["LingxiApp"])
    ],
    targets: [
        .target(name: "LingxiCore"),
        .executableTarget(name: "LingxiApp", dependencies: ["LingxiCore"]),
        .testTarget(name: "LingxiCoreTests", dependencies: ["LingxiCore"])
    ]
)
