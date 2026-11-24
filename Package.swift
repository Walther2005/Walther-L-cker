// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pixelwisch",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Pixelwisch",
            path: "Sources/Pixelwisch"
        )
    ]
)
