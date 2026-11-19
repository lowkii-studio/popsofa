// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PopSofa",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PopSofa",
            path: "Sources/PopSofa"
        )
    ]
)
