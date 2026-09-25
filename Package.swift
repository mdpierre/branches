// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Branches",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Branches", targets: ["BranchesApp"]),
    ],
    targets: [
        // All observation, parsing and status logic. No SwiftUI.
        .target(name: "BranchesKit", exclude: ["Providers/README.md"]),
        // The SwiftUI app shell.
        .executableTarget(name: "BranchesApp", dependencies: ["BranchesKit"]),
        .testTarget(name: "BranchesKitTests", dependencies: ["BranchesKit"]),
    ]
)
