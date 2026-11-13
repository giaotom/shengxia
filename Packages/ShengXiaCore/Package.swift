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
        .target(name: "CInflate"),
        .target(
            name: "ShengXiaCore",
            dependencies: ["CInflate"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "ShengXiaCoreTests", dependencies: ["ShengXiaCore"])
    ]
)
