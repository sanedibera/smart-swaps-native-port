// swift-tools-version: 5.9
import PackageDescription

// SmartSwapsKit holds everything that is not a view: the ported engine, the models, the
// data layer and the JS-semantics compatibility shims. It is a package rather than part of
// the app target for one reason - the Phase 3 equivalence suite has to be runnable as
// `swift test` in seconds, without booting a simulator. The iOS app target depends on it.
let package = Package(
    name: "SmartSwapsKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "SmartSwapsKit", targets: ["SmartSwapsKit"]),
    ],
    targets: [
        .target(
            name: "SmartSwapsKit",
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "SmartSwapsKitTests",
            dependencies: ["SmartSwapsKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
