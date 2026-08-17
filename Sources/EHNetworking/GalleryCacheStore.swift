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
        let url = detailURL(for: key, site: site)
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        do {
            return try JSONDecoder().decode(GalleryDetail.self, from: data)
        } catch {
            return nil
        }
    }

    public func save(
        _ detail: GalleryDetail,
        for key: GalleryKey,
        site: SiteMode,
        generation: UInt64? = nil
    ) {
        if let generation, generation != self.generation { return }
        let snapshot = Self.staticSnapshot(from: detail)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }

        let url = detailURL(for: key, site: site)
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
            apiUID: detail.apiUID,
            apiKey: detail.apiKey,
            favoriteCount: nil,
            favoriteName: nil,
            ratingCount: nil,
            language: detail.language,
            fileSize: detail.fileSize,
            torrentURL: detail.torrentURL,
            torrentCount: detail.torrentCount,
            archiveURL: detail.archiveURL
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

    private static var defaultRoot: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("EhViewer/GalleryCache", isDirectory: true)
    }
}
