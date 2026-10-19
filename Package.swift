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
        .library(name: "EHDeviceSync", targets: ["EHDeviceSync"]),
        .library(name: "EHTranslationMac", targets: ["EHTranslationMac"]),
        .executable(name: "EhViewerPreview", targets: ["EhViewerPreview"])
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.9.6")
    ],
    targets: [
        .target(
            name: "EHDomain"
        ),
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
            resources: [.process("Resources")],
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
        .target(
            name: "EHDeviceSync",
            dependencies: ["EHDomain", "EHPersistence", "EHDownloads"],
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [
                .linkedFramework("Network"),
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "EhViewerPreview",
            dependencies: ["EHDomain", "EHNetworking", "EHPersistence", "EHDownloads", "EHDeviceSync",
                           .target(name: "EHTranslationMac", condition: .when(platforms: [.macOS]))],
            path: "Sources/EhViewer",
            exclude: ["Info.plist", "Info-macOS.plist", "EhViewer-iOS.entitlements"],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "EHTranslationMac",
            dependencies: ["EHDomain", "EHDownloads"],
            exclude: ["Resources"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "EHTranslationMacTests",
            dependencies: ["EHTranslationMac"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "EhViewerTests",
            dependencies: ["EHDomain", "EHNetworking", "EHPersistence", "EHDownloads", "EHDeviceSync", "EhViewerPreview"],
            resources: [.process("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
