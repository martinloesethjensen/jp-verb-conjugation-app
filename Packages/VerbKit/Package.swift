// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "VerbKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "VerbKit", targets: ["VerbKit"])
    ],
    targets: [
        .target(name: "VerbKit"),
        .testTarget(
            name: "VerbKitTests",
            dependencies: ["VerbKit"],
            resources: [.copy("Fixtures/verbs-fixture.json")]
        )
    ]
)
