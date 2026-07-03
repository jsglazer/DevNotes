// swift-tools-version: 6.0
// DevNotes — ultra-fast, offline-first Markdown editor for macOS & iOS.
// Targeted toolchain: Swift 6.3.3 / Xcode 26.6 / macOS SDK 26.5 / iOS SDK 26.5.
import PackageDescription

let package = Package(
    name: "DevNotes",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        // Platform-agnostic domain logic. The whole headless test suite runs against this.
        .library(name: "DevNotesCore", targets: ["DevNotesCore"]),
        // The OS shell (SwiftUI + TextKit 2 + CloudKit). Not part of the headless gate.
        .executable(name: "DevNotesApp", targets: ["DevNotesApp"])
    ],
    targets: [
        // MARK: - Pure core (no AppKit / UIKit / SwiftUI / CloudKit, no file/network I/O)
        .target(
            name: "DevNotesCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),

        // MARK: - OS shell
        .executableTarget(
            name: "DevNotesApp",
            dependencies: ["DevNotesCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),

        // MARK: - Deterministic headless tests (the machine-checkable gate)
        .testTarget(
            name: "DevNotesCoreTests",
            dependencies: ["DevNotesCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),

        // MARK: - Performance tests (XCTMetric). Headless proxy for the launch budget.
        // The true launch-to-interactive metric (XCTApplicationLaunchMetric) lives in the
        // Xcode UI-test target — see BUILD-MANIFEST.md — because XCUIApplication needs an
        // app bundle SwiftPM does not produce.
        .testTarget(
            name: "DevNotesPerformanceTests",
            dependencies: ["DevNotesCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
