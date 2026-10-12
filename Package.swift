// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EZSnapshot",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "EZSnapshot", targets: ["EZSnapshot"])],
    targets: [.executableTarget(name: "EZSnapshot", path: "Sources/EZSnapshot")]
)
