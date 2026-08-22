/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai gallery browsing client
 * Copyright (C) 2026 EhViewer Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation
import EHDomain

public struct GalleryCacheUsage: Hashable, Sendable {
    public let byteCount: Int64

    public init(byteCount: Int64 = 0) {
        self.byteCount = max(0, byteCount)
    }
}

/// Persistent cache used only by the detail screen and its preview images.
/// It intentionally lives outside both SwiftData and the download file store.
public actor GalleryCacheStore {
    private let root: URL
    private let imagePipeline: ImagePipeline
    private var generation: UInt64 = 0

    public init(root: URL? = nil, imageByteLimit: Int? = nil) {
        let resolvedRoot = root ?? Self.defaultRoot
        self.root = resolvedRoot
        imagePipeline = ImagePipeline(
            byteLimit: imageByteLimit,
            diskRoot: resolvedRoot.appendingPathComponent("Images", isDirectory: true)
        )
        try? FileManager.default.createDirectory(at: resolvedRoot, withIntermediateDirectories: true)
        Self.excludeFromBackup(resolvedRoot)
    }

    public func detail(for key: GalleryKey, site: SiteMode) -> GalleryDetail? {
        stableSnapshot(for: key, site: site)?.detail()
    }

    /// Reads the new stable snapshot first, then performs a read-only fallback
    /// to the old detail JSON format so the app can migrate one successful
    /// record at a time into SwiftData.
    public func stableSnapshot(for key: GalleryKey, site: SiteMode) -> StableGalleryMetadataSnapshot? {
        if let data = try? Data(contentsOf: stableURL(for: key, site: site), options: .mappedIfSafe),
           let snapshot = try? JSONDecoder().decode(StableGalleryMetadataSnapshot.self, from: data) {
            return snapshot
        }
        let legacyURL = detailURL(for: key, site: site)
        guard let data = try? Data(contentsOf: legacyURL, options: .mappedIfSafe),
              let detail = try? JSONDecoder().decode(GalleryDetail.self, from: data) else {
            return nil
        }
        return StableGalleryMetadataSnapshot(detail: Self.staticSnapshot(from: detail), sourceSite: site)
    }

    /// Returns legacy JSON details without mutating or deleting them. The
    /// application imports these snapshots into SwiftData and can safely retry
    /// the operation after an interrupted launch.
    public func legacyStableSnapshots() -> [StableGalleryMetadataSnapshot] {
        let directory = root.appendingPathComponent("Details", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls.compactMap { url in
            guard url.pathExtension.caseInsensitiveCompare("json") == .orderedSame,
                  let (_, site) = Self.decodeCacheKey(url.deletingPathExtension().lastPathComponent),
                  let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let detail = try? JSONDecoder().decode(GalleryDetail.self, from: data) else {
                return nil
            }
            return StableGalleryMetadataSnapshot(
                detail: Self.staticSnapshot(from: detail),
                sourceSite: site,
                capturedAt: .distantPast
            )
        }
    }

    public func save(
        _ detail: GalleryDetail,
        for key: GalleryKey,
        site: SiteMode,
        generation: UInt64? = nil
    ) {
        if let generation, generation != self.generation { return }
        save(
            StableGalleryMetadataSnapshot(
                detail: Self.staticSnapshot(from: detail),
                sourceSite: site
            ),
            for: key,
            site: site,
            generation: generation
        )
    }

    public func save(
        _ snapshot: StableGalleryMetadataSnapshot,
        for key: GalleryKey,
        site: SiteMode,
        generation: UInt64? = nil
    ) {
        if let generation, generation != self.generation { return }
        guard snapshot.key == key,
              let data = try? JSONEncoder().encode(snapshot) else { return }

        let url = stableURL(for: key, site: site)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            Self.excludeFromBackup(url)
        } catch {
            return
        }
    }

    public func imageData(
        for image: GalleryPageImage,
        resolution: ImageResolution,
        fetcher: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        let url = resolution == .original ? (image.originImageURL ?? image.imageURL) : image.imageURL
        return try await imagePipeline.data(for: url, fetcher: fetcher)
    }

    public func imageCachePath(
        for image: GalleryPageImage,
        resolution: ImageResolution
    ) async -> String? {
        let url = resolution == .original ? (image.originImageURL ?? image.imageURL) : image.imageURL
        return await imagePipeline.diskPath(for: url)
    }

    public func usage() -> GalleryCacheUsage {
        GalleryCacheUsage(byteCount: Self.byteCount(at: root))
    }

    public func currentGeneration() -> UInt64 {
        generation
    }

    public func removeAll() async {
        generation &+= 1
        await imagePipeline.removeAll()
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        Self.excludeFromBackup(root)
    }

    private func detailURL(for key: GalleryKey, site: SiteMode) -> URL {
        root
            .appendingPathComponent("Details", isDirectory: true)
            .appendingPathComponent(Self.cacheKey(for: key, site: site) + ".json", isDirectory: false)
    }

    private func stableURL(for key: GalleryKey, site: SiteMode) -> URL {
        root
            .appendingPathComponent("Stable", isDirectory: true)
            .appendingPathComponent(Self.cacheKey(for: key, site: site) + ".json", isDirectory: false)
    }

    private static func staticSnapshot(from detail: GalleryDetail) -> GalleryDetail {
        var summary = detail.summary
        // Ratings and favorite information are intentionally refreshed from the site.
        summary.rating = nil
        summary.ratingCount = nil
        summary.favoriteCategory = nil

        return GalleryDetail(
            summary: summary,
            pages: detail.pages,
            tags: detail.tags,
            comments: [],
            descriptionText: detail.descriptionText,
            externalURL: detail.externalURL,
            apiUID: nil,
            apiKey: nil,
            favoriteCount: nil,
            favoriteName: nil,
            ratingCount: nil,
            language: detail.language,
            fileSize: detail.fileSize,
            torrentURL: nil,
            torrentCount: nil,
            archiveURL: nil
        )
    }

    private static func cacheKey(for key: GalleryKey, site: SiteMode) -> String {
        let rawValue = "\(site.rawValue)|\(key.id)"
        return Data(rawValue.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decodeCacheKey(_ value: String) -> (GalleryKey, SiteMode)? {
        var encoded = value
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: "-", with: "+")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let raw = String(data: data, encoding: .utf8),
              let separator = raw.firstIndex(of: "|"),
              let site = SiteMode(rawValue: String(raw[..<separator])) else { return nil }
        let keyValue = String(raw[raw.index(after: separator)...])
        guard let dash = keyValue.firstIndex(of: "-"),
              let gid = Int64(keyValue[..<dash]) else { return nil }
        let token = String(keyValue[keyValue.index(after: dash)...])
        guard token.isEmpty == false else { return nil }
        return (GalleryKey(gid: gid, token: token), site)
    }

    private static func byteCount(at root: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize else { continue }
            total += Int64(fileSize)
        }
        return total
    }

    private static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    public static var defaultRootURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("EhViewer/GalleryCache", isDirectory: true)
    }

    private static var defaultRoot: URL { defaultRootURL }
}
