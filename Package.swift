// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GhosttyKit",
    products: [
        .library(
            name: "GhosttyKit",
            targets: ["GhosttyKit"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "GhosttyKit",
            url: "https://github.com/RodrigoEspinosa/bellith/releases/download/v0.1.0/GhosttyKit.xcframework.zip",
            checksum: "1dd3dbbab0274079ea8d4f50110b6b23aa5b72ce388b964e7cc8185065d2e5c7"
        ),
    ]
)
