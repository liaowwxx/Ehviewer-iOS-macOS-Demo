/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation

/// The metadata-only payload stored inside an `.ehgallery` archive.
///
/// This deliberately contains no local state (reading progress, favorites,
/// downloads, filters, searches, settings) and no media bytes.
public struct GallerySyncSnapshot: Codable, Hashable, Sendable {
    public static let currentVersion = 2
    public static let legacyVersion = 1

    public let schemaVersion: Int
    public let exportedAt: Date
    public let records: [GalleryTransferRecord]

    /// Compatibility projection for callers that still consume v1 summaries.
    public var galleries: [GallerySummary] {
        records.map { record in
            var summary = record.stable.summary
            if let dynamic = record.dynamic {
                summary.rating = dynamic.rating
                summary.ratingCount = dynamic.ratingCount
                summary.favoriteCategory = dynamic.favoriteCategory
                let stableCompleteness = summary.metadataCompleteness ?? GalleryMetadataCompleteness()
                let stableFields = [
                    stableCompleteness.title,
                    stableCompleteness.japaneseTitle,
                    stableCompleteness.authors,
                    stableCompleteness.uploader,
                    stableCompleteness.tags,
                    stableCompleteness.category,
                    stableCompleteness.language,
                    stableCompleteness.pageCount,
                    stableCompleteness.postedAt,
                    stableCompleteness.thumbnailURL,
                    stableCompleteness.fileSize,
                    stableCompleteness.description,
                    stableCompleteness.externalURL,
                    stableCompleteness.pages
                ]
                if dynamic.completeness.comments == .loadedWithValue
                    || stableFields.allSatisfy(\.isLoaded) {
                    var completeness = stableCompleteness
                    completeness.rating = dynamic.completeness.rating
                    completeness.ratingCount = dynamic.completeness.ratingCount
                    completeness.favorite = dynamic.completeness.favorite
                    completeness.comments = dynamic.completeness.comments
                    summary.metadataCompleteness = completeness
                }
            } else if summary.metadataCompleteness?.isComplete == true {
                // Keep the legacy `galleries` projection lossless for callers
                // that supplied the old all-fields `.complete` marker. New
                // consumers use `records` and its stable/dynamic snapshots.
                summary.metadataCompleteness = .complete
            }
            return summary
        }
    }

    public init(
        schemaVersion: Int = GallerySyncSnapshot.currentVersion,
        exportedAt: Date = Date(),
        records: [GalleryTransferRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.records = records
    }

    public init(
        schemaVersion: Int = GallerySyncSnapshot.currentVersion,
        exportedAt: Date = Date(),
        galleries: [GallerySummary]
    ) {
        self.init(
            schemaVersion: schemaVersion,
            exportedAt: exportedAt,
            records: galleries.map {
                GalleryTransferRecord(summary: $0, sourceSite: .eHentai, exportedAt: exportedAt)
            }
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case exportedAt
        case records
        case galleries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        let decodedExportedAt = try container.decode(Date.self, forKey: .exportedAt)
        schemaVersion = decodedSchemaVersion
        exportedAt = decodedExportedAt
        if let records = try container.decodeIfPresent([GalleryTransferRecord].self, forKey: .records) {
            self.records = records
        } else {
            let galleries = try container.decode([GallerySummary].self, forKey: .galleries)
            self.records = try galleries.map {
                let legacyRecord = GalleryTransferRecord(
                    summary: $0,
                    sourceSite: .eHentai,
                    exportedAt: decodedExportedAt
                )
                return try GalleryTransferRecord(
                    stable: legacyRecord.stable,
                    dynamic: legacyRecord.dynamic,
                    formatVersion: GallerySyncSnapshot.legacyVersion
                )
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(exportedAt, forKey: .exportedAt)
        try container.encode(records, forKey: .records)
    }
}
