// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Multispace",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Multispace", targets: ["Multispace"])],
    targets: [.executableTarget(name: "Multispace", path: "Sources/Multispace")]
)
