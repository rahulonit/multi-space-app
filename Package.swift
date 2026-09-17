// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PINGGO",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PINGGO", targets: ["PINGGO"])],
    targets: [.executableTarget(name: "PINGGO", path: "Sources/Multispace", resources: [.process("Resources")])]
)
