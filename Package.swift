// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MSL",
    products: [
        .library(name: "MSLCore", targets: ["MSLCore"]),
    ],
    targets: [
        .target(name: "MSLCore"),
        .testTarget(name: "MSLCoreTests", dependencies: ["MSLCore"]),
    ]
)
