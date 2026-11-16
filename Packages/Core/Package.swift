// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "TrunklineCore", platforms: [.macOS(.v14), .iOS(.v17)], products: [.library(name: "TrunklineCore", targets: ["TrunklineCore"])], targets: [.target(name: "TrunklineCore"), .testTarget(name: "TrunklineCoreTests", dependencies: ["TrunklineCore"])])
