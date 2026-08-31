/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai gallery browsing client
 * Copyright (C) 2026 EhViewer Contributors
 */

import Foundation

public enum DeviceSyncIndexStatus: String, Codable, Hashable, Sendable {
    case ready
    case needsBuild
    case rebuilding
}

public enum DeviceSyncIndexError: Error, LocalizedError, Sendable, Equatable {
    case notReady
    case invalidSnapshot
    case persistenceFailed

    public var errorDescription: String? {
        switch self {
        case .notReady:
            String(localized: "设备同步索引尚未建立。")
        case .invalidSnapshot:
            String(localized: "设备同步索引已损坏，需要重新建立。")
        case .persistenceFailed:
            String(localized: "设备同步索引保存失败，需要重新建立。")
        }
    }
}

public struct DeviceSyncIndexMetadataEntry: Codable, Hashable, Sendable {
    public let key: GalleryKey
    public let metadata: DeviceSyncMetadataDigest

    public init(key: GalleryKey, metadata: DeviceSyncMetadataDigest) {
        self.key = key
        self.metadata = metadata
    }
}

/// The persistent sidecar index deliberately keeps media and metadata
/// separate. A page can be indexed before its metadata is available, and a
/// metadata update does not require enumerating the page directory again.
public struct DeviceSyncIndexEntry: Codable, Hashable, Sendable {
    public let key: GalleryKey
    public let pages: [DeviceSyncPageEntry]
    public let metadata: DeviceSyncMetadataDigest?

    public init(
        key: GalleryKey,
        pages: [DeviceSyncPageEntry] = [],
        metadata: DeviceSyncMetadataDigest? = nil
    ) throws {
        guard DeviceSyncGalleryEntry.isValid(key: key) else {
            throw DeviceSyncManifestError.invalidGalleryKey
        }
        var pageIndexes = Set<Int>()
        for page in pages {
            _ = try DeviceSyncPageEntry(pageIndex: page.pageIndex, byteCount: page.byteCount)
            guard pageIndexes.insert(page.pageIndex).inserted else {
                throw DeviceSyncManifestError.duplicatePageIndex
            }
        }
        self.key = key
        self.pages = pages.sorted { $0.pageIndex < $1.pageIndex }
        self.metadata = metadata
    }
}

public struct DeviceSyncIndexSnapshot: Codable, Hashable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let entries: [DeviceSyncIndexEntry]

    public init(
        entries: [DeviceSyncIndexEntry],
        formatVersion: Int = Self.currentFormatVersion
    ) throws {
        var keys = Set<GalleryKey>()
        for entry in entries {
            guard keys.insert(entry.key).inserted else {
                throw DeviceSyncManifestError.duplicateGalleryKey
            }
        }
        self.formatVersion = formatVersion
        self.entries = entries.sorted { $0.key.id < $1.key.id }
    }

    public var entriesByKey: [GalleryKey: DeviceSyncIndexEntry] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0) })
    }

    public func manifest() throws -> DeviceSyncManifest {
        var galleries: [DeviceSyncGalleryEntry] = []
        galleries.reserveCapacity(entries.count)
        for entry in entries {
            guard let metadata = entry.metadata, entry.pages.isEmpty == false else { continue }
            galleries.append(try DeviceSyncGalleryEntry(
                key: entry.key,
                pages: entry.pages,
                metadata: metadata
            ))
        }
        return try DeviceSyncManifest(galleries: galleries)
    }
}

/// Shared mutation boundary used by persistence and file storage. Keeping the
/// protocol in EHDomain avoids a dependency cycle between the storage modules
/// and EHDeviceSync.
public protocol DeviceSyncIndexSink: AnyObject, Sendable {
    func status() async -> DeviceSyncIndexStatus
    func snapshot() async throws -> DeviceSyncIndexSnapshot
    func beginRebuild() async throws
    func finishRebuild(with snapshot: DeviceSyncIndexSnapshot) async throws
    func cancelRebuild() async
    func upsertMediaPage(key: GalleryKey, pageIndex: Int, byteCount: Int64) async
    func removeMediaPage(key: GalleryKey, pageIndex: Int) async
    func removeMedia(for key: GalleryKey) async
    func upsertMetadata(_ entry: DeviceSyncIndexMetadataEntry) async
    func removeMetadata(for key: GalleryKey) async
}
