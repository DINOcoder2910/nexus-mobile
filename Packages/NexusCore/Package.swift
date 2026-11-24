// swift-tools-version:5.9
// The pure half of Nexus on the iPad: the data folder (groups, workstreams, tasks), the line-level YAML edits that keep the
// user's files as they wrote them, and the planning model the screens read. No UIKit or SwiftUI here, so `swift test` runs it on
// any Mac (the cloud build does, on every push).
//
// NexusRust is the shared Rust core (the laptop's new app runs the same code): Rust/NexusCoreFFI.xcframework is nexus core/ built as a
// static library (its source stays in the private nexus repo) and NexusRust/nexus_core_ffi.swift the Swift UniFFI wrote for it. Both
// come from tools/rust-core/copy.sh; Rust/COMMIT names the nexus commit.
import PackageDescription

let package = Package(
    name: "NexusCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "NexusCore", targets: ["NexusCore"])],
    dependencies: [.package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0")],
    targets: [
        // the shared Rust core for iOS, the simulator and the Mac (tools/rust-core/copy.sh)
        .binaryTarget(name: "NexusCoreFFI", path: "Rust/NexusCoreFFI.xcframework"),
        // its Swift side, generated (nexus core/ffi/bindings.sh); the library needs CoreFoundation (time zones) and nothing else
        .target(name: "NexusRust", dependencies: ["NexusCoreFFI"], linkerSettings: [.linkedFramework("CoreFoundation")]),
        // Resources/richcore.js: the laptop's rich-text converters (tools/richtext/build.mjs), run by RichWords.swift in JavaScriptCore
        .target(name: "NexusCore", dependencies: ["Yams", "NexusRust"], resources: [.copy("Resources/richcore.js")]),
        .testTarget(name: "NexusCoreTests", dependencies: ["NexusCore"], resources: [.copy("Fixtures")]),
    ]
)
