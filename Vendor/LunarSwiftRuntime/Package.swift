// swift-tools-version: 5.5
import PackageDescription

// All runtime sources are unchanged from lunar-swift 1.1.8; only this package
// manifest is reduced to the runtime product used by the containing application.
let package = Package(
    name: "LunarSwift",
    products: [.library(name: "LunarSwift", targets: ["LunarSwift"])],
    targets: [.target(name: "LunarSwift")]
)
