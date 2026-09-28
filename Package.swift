// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LingxingCalendar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LingxiCore", targets: ["LingxiCore"]),
        .library(name: "LingxiAgent", targets: ["LingxiAgent"]),
        .executable(name: "LingxingCalendar", targets: ["LingxiApp"]),
        .executable(name: "lingxi", targets: ["LingxiCLI"])
    ],
    dependencies: [.package(path: "Vendor/LunarSwiftRuntime")],
    targets: [
        .target(name: "LingxiCore", dependencies: [.product(name: "LunarSwift", package: "LunarSwiftRuntime")]),
        .target(name: "LingxiAgent", dependencies: ["LingxiCore"]),
        .executableTarget(name: "LingxiApp", dependencies: ["LingxiCore", "LingxiAgent"]),
        .executableTarget(name: "LingxiCLI", dependencies: ["LingxiCore"]),
        .testTarget(name: "LingxiCoreTests", dependencies: ["LingxiCore"]),
        .testTarget(name: "LingxiCLITests", dependencies: ["LingxiCLI", "LingxiCore"]),
        .testTarget(name: "LingxiAgentTests", dependencies: ["LingxiAgent", "LingxiCore"]),
        .testTarget(name: "LingxiAppTests", dependencies: ["LingxiApp", "LingxiAgent"])
    ]
)
