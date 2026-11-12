// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShengXiaCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v12)
    ],
    products: [
        .library(name: "ShengXiaCore", targets: ["ShengXiaCore"])
    ],
    targets: [
        .target(name: "ShengXiaCore"),
        .testTarget(name: "ShengXiaCoreTests", dependencies: ["ShengXiaCore"])
    ]
)
