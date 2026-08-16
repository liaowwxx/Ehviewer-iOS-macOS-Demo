// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "EhViewer",
    defaultLocalization: "zh-Hans",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "EHDomain", targets: ["EHDomain"]),
        .library(name: "EHNetworking", targets: ["EHNetworking"]),
        .library(name: "EHPersistence", targets: ["EHPersistence"]),
        .library(name: "EHDownloads", targets: ["EHDownloads"]),
        .executable(name: "EhViewerPreview", targets: ["EhViewerPreview"])
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.9.6")
    ],
    targets: [
        .target(name: "EHDomain"),
        .target(
            name: "EHArchiveSupport",
            path: "Sources/EHArchiveSupport",
            publicHeadersPath: "include",
            linkerSettings: [.linkedLibrary("archive")]
        ),
        .target(
            name: "EHNetworking",
            dependencies: [
                "EHDomain",
                .product(name: "SwiftSoup", package: "SwiftSoup")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "EHPersistence",
            dependencies: ["EHDomain"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "EHDownloads",
            dependencies: ["EHDomain", "EHNetworking", "EHArchiveSupport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "EhViewerPreview",
            dependencies: ["EHDomain", "EHNetworking", "EHPersistence", "EHDownloads"],
            path: "Sources/EhViewer",
            exclude: ["Info.plist"],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "EhViewerTests",
            dependencies: ["EHDomain", "EHNetworking", "EHPersistence", "EHDownloads", "EhViewerPreview"],
            resources: [.process("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
