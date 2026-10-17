/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai gallery browsing client
 * Copyright (C) 2026 EhViewer Contributors
 */

import CryptoKit
import Foundation

public enum DeviceSyncManifestError: Error, LocalizedError, Sendable, Equatable {
    case invalidGalleryKey
    case invalidPageIndex
    case invalidPageByteCount
    case duplicateGalleryKey
    case duplicatePageIndex
    case orphanPageEntries
    case tooManyGalleries
    case tooManyPages
    case metadataTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidGalleryKey:
            String(localized: "设备同步清单包含无效的画廊标识。")
        case .invalidPageIndex:
            String(localized: "设备同步清单包含无效的页面索引。")
        case .invalidPageByteCount:
            String(localized: "设备同步清单包含无效的页面大小。")
        case .duplicateGalleryKey:
            String(localized: "设备同步清单包含重复的画廊。")
        case .duplicatePageIndex:
            String(localized: "设备同步清单包含重复的页面。")
        case .orphanPageEntries:
            String(localized: "设备同步清单包含没有元数据的页面。")
        case .tooManyGalleries:
            String(localized: "设备同步清单中的画廊数量超出限制。")
        case .tooManyPages:
            String(localized: "设备同步清单中的页面数量超出限制。")
        case .metadataTooLarge:
            String(localized: "设备同步元数据超出单条消息限制。")
        }
    }
}

public struct DeviceSyncPageEntry: Codable, Hashable, Sendable, Identifiable {
    public static let maximumPageIndex = 100_000
    public static let maximumByteCount: Int64 = 256 * 1024 * 1024

    public let pageIndex: Int
    public let byteCount: Int64

    public init(pageIndex: Int, byteCount: Int64) throws {
        guard (0..<Self.maximumPageIndex).contains(pageIndex) else {
            throw DeviceSyncManifestError.invalidPageIndex
        }
        guard (1...Self.maximumByteCount).contains(byteCount) else {
            throw DeviceSyncManifestError.invalidPageByteCount
        }
        self.pageIndex = pageIndex
        self.byteCount = byteCount
    }

    public var id: Int { pageIndex }
}

public struct DeviceSyncMetadataDigest: Codable, Hashable, Sendable {
    public let stableCapturedAt: Date
    public let stableCompleteness: GalleryMetadataCompleteness
    public let stableFingerprint: Data
    public let dynamicCapturedAt: Date?
    public let dynamicCompleteness: GalleryMetadataCompleteness?
    public let dynamicFingerprint: Data?
    public let estimatedTransferBytes: Int64

    public init(
        stableCapturedAt: Date,
        stableCompleteness: GalleryMetadataCompleteness,
        stableFingerprint: Data,
        dynamicCapturedAt: Date? = nil,
        dynamicCompleteness: GalleryMetadataCompleteness? = nil,
        dynamicFingerprint: Data? = nil,
        estimatedTransferBytes: Int64
    ) throws {
        guard (0...Int64(4 * 1024 * 1024)).contains(estimatedTransferBytes) else {
            throw DeviceSyncManifestError.metadataTooLarge
        }
        self.stableCapturedAt = stableCapturedAt
        self.stableCompleteness = stableCompleteness
        self.stableFingerprint = stableFingerprint
        self.dynamicCapturedAt = dynamicCapturedAt
        self.dynamicCompleteness = dynamicCompleteness
        self.dynamicFingerprint = dynamicFingerprint
        self.estimatedTransferBytes = estimatedTransferBytes
    }

    public static func make(for record: GalleryTransferRecord) throws -> Self {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let stableData = try encoder.encode(record.stable)
        let dynamicData = try record.dynamic.map(encoder.encode)
        return try Self.make(
            stable: record.stable,
            dynamic: record.dynamic,
            stableData: stableData,
            dynamicData: dynamicData,
            estimatedTransferBytes: Int64(stableData.count + (dynamicData?.count ?? 0))
        )
    }

    public static func make(
        stable: StableGalleryMetadataSnapshot,
        dynamic: DownloadedGalleryDynamicSnapshot?
    ) throws -> Self {
        let encoder = makeEncoder()
        let stableData = try encoder.encode(stable)
        let dynamicData = try dynamic.map(encoder.encode)
        return try Self.make(
            stable: stable,
            dynamic: dynamic,
            stableData: stableData,
            dynamicData: dynamicData,
            estimatedTransferBytes: Int64(stableData.count + (dynamicData?.count ?? 0))
        )
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func make(
        stable: StableGalleryMetadataSnapshot,
        dynamic: DownloadedGalleryDynamicSnapshot?,
        stableData: Data,
        dynamicData: Data?,
        estimatedTransferBytes: Int64
    ) throws -> Self {
        return try Self(
            stableCapturedAt: stable.capturedAt,
            stableCompleteness: stable.completeness,
            stableFingerprint: Data(SHA256.hash(data: stableData)),
            dynamicCapturedAt: dynamic?.capturedAt,
            dynamicCompleteness: dynamic?.completeness,
            dynamicFingerprint: dynamicData.map { Data(SHA256.hash(data: $0)) },
            estimatedTransferBytes: estimatedTransferBytes
        )
    }

    fileprivate var stableCompletenessScore: Int {
        Self.loadedFieldCount(stableCompleteness)
    }

    fileprivate var dynamicCompletenessScore: Int {
        dynamicCompleteness.map(Self.loadedFieldCount) ?? 0
    }

    private static func loadedFieldCount(_ completeness: GalleryMetadataCompleteness) -> Int {
        [
            completeness.title, completeness.japaneseTitle, completeness.authors,
            completeness.uploader, completeness.tags, completeness.category,
            completeness.language, completeness.pageCount, completeness.postedAt,
            completeness.thumbnailURL, completeness.fileSize, completeness.description,
            completeness.externalURL, completeness.pages, completeness.rating,
            completeness.ratingCount, completeness.favorite, completeness.comments
        ].filter(\.isLoaded).count
    }
}

public struct DeviceSyncGalleryEntry: Codable, Hashable, Sendable, Identifiable {
    public let key: GalleryKey
    public let pages: [DeviceSyncPageEntry]
    public let metadata: DeviceSyncMetadataDigest

    public init(
        key: GalleryKey,
        pages: [DeviceSyncPageEntry],
        metadata: DeviceSyncMetadataDigest
    ) throws {
        guard Self.isValid(key: key) else {
            throw DeviceSyncManifestError.invalidGalleryKey
        }
        var pageIndexes = Set<Int>()
        for page in pages {
            guard pageIndexes.insert(page.pageIndex).inserted else {
                throw DeviceSyncManifestError.duplicatePageIndex
            }
        }
        self.key = key
        self.pages = pages.sorted { $0.pageIndex < $1.pageIndex }
        self.metadata = metadata
    }

    public var id: String { key.id }

    static func isValid(key: GalleryKey) -> Bool {
        guard key.gid > 0,
              key.token.isEmpty == false,
              key.token.count <= 512 else { return false }
        return key.token.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 0x20 && scalar != "/" && scalar != "\\"
        }
    }
}

public struct DeviceSyncManifest: Codable, Hashable, Sendable {
    public static let currentFormatVersion = 2
    public static let maximumGalleryCount = 100_000
    public static let maximumPageCount = 1_000_000

    public let formatVersion: Int
    public let galleries: [DeviceSyncGalleryEntry]
    public let translations: [DeviceSyncTranslationEntry]?

    public init(
        galleries: [DeviceSyncGalleryEntry],
        formatVersion: Int = Self.currentFormatVersion,
        translations: [DeviceSyncTranslationEntry]? = nil
    ) throws {
        guard galleries.count <= Self.maximumGalleryCount else {
            throw DeviceSyncManifestError.tooManyGalleries
        }
        var keys = Set<GalleryKey>()
        var pageCount = 0
        for gallery in galleries {
            guard keys.insert(gallery.key).inserted else {
                throw DeviceSyncManifestError.duplicateGalleryKey
            }
            pageCount += gallery.pages.count
        }
        guard pageCount <= Self.maximumPageCount else {
            throw DeviceSyncManifestError.tooManyPages
        }
        self.formatVersion = formatVersion
        self.galleries = galleries.sorted { $0.key.id < $1.key.id }
        self.translations = translations
    }

    public init(
        records: [GalleryTransferRecord],
        pagesByGallery: [GalleryKey: [DeviceSyncPageEntry]],
        formatVersion: Int = Self.currentFormatVersion
    ) throws {
        var keys = Set<GalleryKey>()
        var entries = [DeviceSyncGalleryEntry]()
        entries.reserveCapacity(records.count)
        for record in records {
            guard keys.insert(record.stable.key).inserted else {
                throw DeviceSyncManifestError.duplicateGalleryKey
            }
            let metadata = try DeviceSyncMetadataDigest.make(for: record)
            entries.append(try DeviceSyncGalleryEntry(
                key: record.stable.key,
                pages: pagesByGallery[record.stable.key] ?? [],
                metadata: metadata
            ))
        }
        guard Set(pagesByGallery.keys).isSubset(of: keys) else {
            throw DeviceSyncManifestError.orphanPageEntries
        }
        try self.init(galleries: entries, formatVersion: formatVersion)
    }

    public var galleryKeys: Set<GalleryKey> {
        Set(galleries.map(\.key))
    }

    public var pageCount: Int {
        galleries.reduce(0) { $0 + $1.pages.count } + (translations ?? []).reduce(0) { $0 + $1.availablePages.count }
    }

    public func validate() throws {
        let validated = try galleries.map { gallery in
            let pages = try gallery.pages.map { try DeviceSyncPageEntry(pageIndex: $0.pageIndex, byteCount: $0.byteCount) }
            return try DeviceSyncGalleryEntry(key: gallery.key, pages: pages, metadata: gallery.metadata)
        }
        _ = try DeviceSyncManifest(galleries: validated, formatVersion: formatVersion)
        try DeviceSyncTranslationReconciler.validate(local: translations ?? [], remote: [])
        let keys = Set(galleries.map(\.key))
        guard (translations ?? []).allSatisfy({ keys.contains($0.manifest.gallery.key) }) else { throw DeviceSyncManifestError.orphanPageEntries }
    }
}

public struct DeviceSyncPageTransfer: Codable, Hashable, Sendable, Identifiable {
    public let key: GalleryKey
    public let pageIndex: Int
    public let byteCount: Int64

    public init(key: GalleryKey, pageIndex: Int, byteCount: Int64) throws {
        let page = try DeviceSyncPageEntry(pageIndex: pageIndex, byteCount: byteCount)
        guard DeviceSyncGalleryEntry.isValid(key: key) else {
            throw DeviceSyncManifestError.invalidGalleryKey
        }
        self.key = key
        self.pageIndex = page.pageIndex
        self.byteCount = page.byteCount
    }

    public var id: String { "\(key.id)-\(pageIndex)" }
}

public struct DeviceSyncPlan: Codable, Hashable, Sendable {
    public let receiveGalleries: [GalleryKey]
    public let receiveMetadata: [GalleryKey]
    public let receivePages: [DeviceSyncPageTransfer]
    public let sendGalleries: [GalleryKey]
    public let sendMetadata: [GalleryKey]
    public let sendPages: [DeviceSyncPageTransfer]
    public let receiveTranslations: [DeviceSyncTranslationEntry]
    public let sendTranslations: [DeviceSyncTranslationEntry]

    public init(
        receiveGalleries: [GalleryKey],
        receiveMetadata: [GalleryKey],
        receivePages: [DeviceSyncPageTransfer],
        sendGalleries: [GalleryKey],
        sendMetadata: [GalleryKey],
        sendPages: [DeviceSyncPageTransfer],
        receiveTranslations: [DeviceSyncTranslationEntry] = [],
        sendTranslations: [DeviceSyncTranslationEntry] = []
    ) {
        self.receiveGalleries = receiveGalleries.sorted { $0.id < $1.id }
        self.receiveMetadata = receiveMetadata.sorted { $0.id < $1.id }
        self.receivePages = receivePages.sorted { $0.id < $1.id }
        self.sendGalleries = sendGalleries.sorted { $0.id < $1.id }
        self.sendMetadata = sendMetadata.sorted { $0.id < $1.id }
        self.sendPages = sendPages.sorted { $0.id < $1.id }
        self.receiveTranslations = receiveTranslations
        self.sendTranslations = sendTranslations
    }

    public var receiveBytes: Int64 {
        receivePages.reduce(0) { $0 + $1.byteCount } + receiveTranslations.reduce(0) { $0 + $1.byteCount }
    }

    public var sendBytes: Int64 {
        sendPages.reduce(0) { $0 + $1.byteCount } + sendTranslations.reduce(0) { $0 + $1.byteCount }
    }
}

public enum DeviceSyncReconciler {
    public static func plan(
        local: DeviceSyncManifest,
        remote: DeviceSyncManifest
    ) -> DeviceSyncPlan {
        let localByKey = Dictionary(uniqueKeysWithValues: local.galleries.map { ($0.key, $0) })
        let remoteByKey = Dictionary(uniqueKeysWithValues: remote.galleries.map { ($0.key, $0) })

        var receiveGalleries = [GalleryKey]()
        var receiveMetadata = [GalleryKey]()
        var receivePages = [DeviceSyncPageTransfer]()
        var sendGalleries = [GalleryKey]()
        var sendMetadata = [GalleryKey]()
        var sendPages = [DeviceSyncPageTransfer]()

        for key in remoteByKey.keys.sorted(by: { $0.id < $1.id }) {
            guard let remoteEntry = remoteByKey[key] else { continue }
            guard let localEntry = localByKey[key] else {
                receiveGalleries.append(key)
                receiveMetadata.append(key)
                for page in remoteEntry.pages {
                    receivePages.append(try! DeviceSyncPageTransfer(
                        key: key,
                        pageIndex: page.pageIndex,
                        byteCount: page.byteCount
                    ))
                }
                continue
            }

            let localPages = Set(localEntry.pages.map(\.pageIndex))
            for page in remoteEntry.pages where localPages.contains(page.pageIndex) == false {
                receivePages.append(try! DeviceSyncPageTransfer(
                    key: key,
                    pageIndex: page.pageIndex,
                    byteCount: page.byteCount
                ))
            }
            if metadataNeedsTransfer(local: localEntry.metadata, remote: remoteEntry.metadata) {
                receiveMetadata.append(key)
            }
        }

        for key in localByKey.keys.sorted(by: { $0.id < $1.id }) {
            guard let localEntry = localByKey[key] else { continue }
            guard let remoteEntry = remoteByKey[key] else {
                sendGalleries.append(key)
                sendMetadata.append(key)
                for page in localEntry.pages {
                    sendPages.append(try! DeviceSyncPageTransfer(
                        key: key,
                        pageIndex: page.pageIndex,
                        byteCount: page.byteCount
                    ))
                }
                continue
            }

            let remotePages = Set(remoteEntry.pages.map(\.pageIndex))
            for page in localEntry.pages where remotePages.contains(page.pageIndex) == false {
                sendPages.append(try! DeviceSyncPageTransfer(
                    key: key,
                    pageIndex: page.pageIndex,
                    byteCount: page.byteCount
                ))
            }
            if metadataNeedsTransfer(local: remoteEntry.metadata, remote: localEntry.metadata) {
                sendMetadata.append(key)
            }
        }

        return DeviceSyncPlan(
            receiveGalleries: receiveGalleries,
            receiveMetadata: receiveMetadata,
            receivePages: receivePages,
            sendGalleries: sendGalleries,
            sendMetadata: sendMetadata,
            sendPages: sendPages,
            receiveTranslations: DeviceSyncTranslationReconciler.missing(local: local.translations ?? [], remote: remote.translations ?? []),
            sendTranslations: DeviceSyncTranslationReconciler.missing(local: remote.translations ?? [], remote: local.translations ?? [])
        )
    }

    private static func metadataNeedsTransfer(
        local: DeviceSyncMetadataDigest,
        remote: DeviceSyncMetadataDigest
    ) -> Bool {
        stableComparison(local: local, remote: remote) == .remotePreferred
            || dynamicComparison(local: local, remote: remote) == .remotePreferred
    }

    private enum Comparison {
        case equal
        case localPreferred
        case remotePreferred
    }

    private static func stableComparison(
        local: DeviceSyncMetadataDigest,
        remote: DeviceSyncMetadataDigest
    ) -> Comparison {
        if local.stableCapturedAt != remote.stableCapturedAt {
            return remote.stableCapturedAt > local.stableCapturedAt ? .remotePreferred : .localPreferred
        }
        if local.stableCompletenessScore != remote.stableCompletenessScore {
            return remote.stableCompletenessScore > local.stableCompletenessScore
                ? .remotePreferred
                : .localPreferred
        }
        return compare(local.stableFingerprint, remote.stableFingerprint)
    }

    private static func dynamicComparison(
        local: DeviceSyncMetadataDigest,
        remote: DeviceSyncMetadataDigest
    ) -> Comparison {
        switch (local.dynamicCapturedAt, remote.dynamicCapturedAt) {
        case (nil, nil):
            return .equal
        case (nil, .some):
            return .remotePreferred
        case (.some, nil):
            return .localPreferred
        case let (.some(localDate), .some(remoteDate)):
            if localDate != remoteDate {
                return remoteDate > localDate ? .remotePreferred : .localPreferred
            }
            if local.dynamicCompletenessScore != remote.dynamicCompletenessScore {
                return remote.dynamicCompletenessScore > local.dynamicCompletenessScore
                    ? .remotePreferred
                    : .localPreferred
            }
            return compare(local.dynamicFingerprint ?? Data(), remote.dynamicFingerprint ?? Data())
        }
    }

    private static func compare(_ local: Data, _ remote: Data) -> Comparison {
        if local == remote { return .equal }
        return remote.lexicographicallyPrecedes(local) ? .localPreferred : .remotePreferred
    }
}
