// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TeakTextView",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TeakTextView", targets: ["TeakTextView"]),
        .library(name: "TeakTextCore", targets: ["TeakTextCore"])
    ],
    targets: [
        .target(name: "TeakTextBuffer", publicHeadersPath: "include"),
        .target(name: "TeakTextCore", dependencies: ["TeakTextBuffer"],
                resources: [.process("Languages")]),
        .target(name: "TeakTextStorage", dependencies: ["TeakTextBuffer"],
                publicHeadersPath: "include"),
        .target(name: "TeakTextView", dependencies: ["TeakTextCore", "TeakTextStorage"]),
        .testTarget(name: "TeakTextCoreTests", dependencies: ["TeakTextCore"],
                    resources: [.copy("Fixtures")])
    ],
    cxxLanguageStandard: .cxx20
)
