// swift-tools-version:5.9
// The pure half of Nexus on the iPad: the data folder (groups, workstreams, tasks), the line-level YAML edits that keep the
// user's files as they wrote them, and the planning model the screens read. No UIKit or SwiftUI here, so `swift test` runs it on
// any Mac (the cloud build does, on every push).
import PackageDescription

let package = Package(
    name: "NexusCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "NexusCore", targets: ["NexusCore"])],
    dependencies: [.package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0")],
    targets: [
        .target(name: "NexusCore", dependencies: ["Yams"]),
        .testTarget(name: "NexusCoreTests", dependencies: ["NexusCore"], resources: [.copy("Fixtures")]),
    ]
)
