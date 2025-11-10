// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "blogger2ghost",
    platforms: [.macOS(.v12)],
    products: [.executable(name: "blogger2ghost", targets: ["blogger2ghost"])],
    targets: [
        .executableTarget(
            name: "blogger2ghost",
            path: "Sources/blogger2ghost"
        )
    ]
)
