// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GradientKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "GradientKit", targets: ["GradientKit"]),
    ],
    targets: [
        .target(name: "GradientKit"),
        .testTarget(name: "GradientKitTests", dependencies: ["GradientKit"]),
    ]
)
