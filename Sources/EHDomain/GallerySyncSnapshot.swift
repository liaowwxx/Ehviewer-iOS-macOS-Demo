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
    public static let currentVersion = 1

    public let schemaVersion: Int
    public let exportedAt: Date
    public let galleries: [GallerySummary]

    public init(
        schemaVersion: Int = GallerySyncSnapshot.currentVersion,
        exportedAt: Date = Date(),
        galleries: [GallerySummary]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.galleries = galleries
    }
}
