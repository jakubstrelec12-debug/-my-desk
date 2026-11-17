// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "MyDesk", defaultLocalization: "cs", platforms: [.macOS(.v13)],
    products: [.executable(name: "MyDesk", targets: ["MyDesk"])],
    targets: [
        .executableTarget(name: "MyDesk", resources: [.process("Resources")],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("Security"), .linkedFramework("IOKit"), .linkedFramework("ServiceManagement"), .linkedFramework("AuthenticationServices")]),
        .testTarget(name: "MyDeskTests", dependencies: ["MyDesk"])
    ], swiftLanguageVersions: [.v5]
)
