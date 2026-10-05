// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "VerbKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "VerbKit", targets: ["VerbKit"])
    ],
    targets: [
        .target(
            name: "VerbKit",
            resources: [.copy("Resources/forms.json"), .copy("Resources/dialects.json")]
        ),
        .testTarget(
            name: "VerbKitTests",
            dependencies: ["VerbKit"],
            resources: [.copy("Fixtures/verbs-fixture.json")]
        )
    ],
    swiftLanguageModes: [.v5]
)
