/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import SwiftData
import EHDomain

public struct PersistedDownload: Hashable, Sendable {
    public let key: GalleryKey
    public let title: String
    public let japaneseTitle: String?
    public let tags: [String]
    public let pages: [GalleryPageDescriptor]
    public let totalPageCount: Int
    public let createdAt: Date
    public let updatedAt: Date
    public let label: String?
    public let completedPageIndexes: Set<Int>
    public let stateRaw: String
    public let errorMessage: String?
    public let inFlightPageIndexes: Set<Int>

    public init(
        key: GalleryKey,
        title: String,
        japaneseTitle: String? = nil,
        tags: [String] = [],
        pages: [GalleryPageDescriptor],
        totalPageCount: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        label: String? = nil,
        completedPageIndexes: Set<Int>,
        stateRaw: String,
        errorMessage: String?,
        inFlightPageIndexes: Set<Int> = []
    ) {
        self.key = key
        self.title = title
        self.japaneseTitle = japaneseTitle
        self.tags = tags
        self.pages = pages
        self.totalPageCount = totalPageCount ?? pages.count
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.label = label
        self.completedPageIndexes = completedPageIndexes
        self.stateRaw = stateRaw
        self.errorMessage = errorMessage
        self.inFlightPageIndexes = inFlightPageIndexes
    }
}

public struct FilterRuleSnapshot: Hashable, Sendable, Codable {
    public let pattern: String
    public var isEnabled: Bool
    public var mode: GalleryFilterMode

    public init(pattern: String, isEnabled: Bool, mode: GalleryFilterMode = .title) {
        self.pattern = pattern
        self.isEnabled = isEnabled
        self.mode = mode
    }

    private enum CodingKeys: String, CodingKey {
        case pattern
        case isEnabled
        case mode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pattern = try container.decode(String.self, forKey: .pattern)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        // Older migration exports predate rule modes.
        mode = try container.decodeIfPresent(GalleryFilterMode.self, forKey: .mode) ?? .title
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pattern, forKey: .pattern)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(mode, forKey: .mode)
    }
}

public enum ModelContainerFactory {
    // Keep this snapshot in sync with the store that existed before the
    // per-gallery metadata completeness flags were added.
    public enum SchemaV1: VersionedSchema {
        public static let versionIdentifier = Schema.Version(1, 0, 0)

        @Model
        public final class GalleryRecord {
            #Index<GalleryRecord>([\.gid], [\.lastReadAt])

            public var gid: Int64
            public var token: String
            public var title: String
            public var japaneseTitle: String?
            public var thumbnailURLString: String?
            public var category: String?
            public var pageCount: Int?
            public var postedAt: Date?
            public var rating: Double?
            public var ratingCount: Int?
            public var favoriteCategory: Int?
            public var uploader: String?
            public var lastReadAt: Date?
            public var lastReadPage: Int
            public var isFavorite: Bool
            public var tags: [String]

            public init(
                snapshot: GallerySummary,
                lastReadPage: Int = 0,
                lastReadAt: Date? = nil,
                isFavorite: Bool = false
            ) {
                gid = snapshot.key.gid
                token = snapshot.key.token
                title = snapshot.title
                japaneseTitle = snapshot.japaneseTitle
                thumbnailURLString = snapshot.thumbnailURL?.absoluteString
                category = snapshot.category
                pageCount = snapshot.pageCount
                postedAt = snapshot.postedAt
                rating = snapshot.rating
                ratingCount = snapshot.ratingCount
                favoriteCategory = snapshot.favoriteCategory
                uploader = snapshot.uploader
                self.lastReadPage = lastReadPage
                self.lastReadAt = lastReadAt
                self.isFavorite = isFavorite
                tags = snapshot.tags
            }
        }

        public static let models: [any PersistentModel.Type] = [
            SchemaV1.GalleryRecord.self,
            DownloadJobRecord.self,
            DownloadPageRecord.self,
            DownloadLabelRecord.self,
            QuickSearchRecord.self,
            FilterRuleRecord.self,
            TagTranslationRecord.self
        ]
    }

    public enum SchemaV2: VersionedSchema {
        public static let versionIdentifier = Schema.Version(2, 0, 0)

        @Model
        public final class GalleryRecord {
            #Index<GalleryRecord>([\.gid], [\.lastReadAt])

            public var gid: Int64
            public var token: String
            public var title: String
            public var japaneseTitle: String?
            public var thumbnailURLString: String?
            public var category: String?
            public var pageCount: Int?
            public var postedAt: Date?
            public var rating: Double?
            public var ratingCount: Int?
            public var favoriteCategory: Int?
            public var uploader: String?
            public var lastReadAt: Date?
            public var lastReadPage: Int
            public var isFavorite: Bool
            public var tags: [String]
            public var metadataTitleComplete: Bool
            public var metadataJapaneseTitleComplete: Bool
            public var metadataTagsComplete: Bool

            public init(
                gid: Int64,
                token: String,
                title: String,
                japaneseTitle: String? = nil,
                thumbnailURLString: String? = nil,
                category: String? = nil,
                pageCount: Int? = nil,
                postedAt: Date? = nil,
                rating: Double? = nil,
                ratingCount: Int? = nil,
                favoriteCategory: Int? = nil,
                uploader: String? = nil,
                lastReadAt: Date? = nil,
                lastReadPage: Int = 0,
                isFavorite: Bool = false,
                tags: [String] = [],
                metadataTitleComplete: Bool = false,
                metadataJapaneseTitleComplete: Bool = false,
                metadataTagsComplete: Bool = false
            ) {
                self.gid = gid
                self.token = token
                self.title = title
                self.japaneseTitle = japaneseTitle
                self.thumbnailURLString = thumbnailURLString
                self.category = category
                self.pageCount = pageCount
                self.postedAt = postedAt
                self.rating = rating
                self.ratingCount = ratingCount
                self.favoriteCategory = favoriteCategory
                self.uploader = uploader
                self.lastReadAt = lastReadAt
                self.lastReadPage = lastReadPage
                self.isFavorite = isFavorite
                self.tags = tags
                self.metadataTitleComplete = metadataTitleComplete
                self.metadataJapaneseTitleComplete = metadataJapaneseTitleComplete
                self.metadataTagsComplete = metadataTagsComplete
            }
        }

        public static let models: [any PersistentModel.Type] = [
            SchemaV2.GalleryRecord.self,
            DownloadJobRecord.self,
            DownloadPageRecord.self,
            DownloadLabelRecord.self,
            QuickSearchRecord.self,
            FilterRuleRecord.self,
            TagTranslationRecord.self
        ]
    }

    public enum SchemaV3: VersionedSchema {
        public static let versionIdentifier = Schema.Version(3, 0, 0)

        public static let models: [any PersistentModel.Type] = [
            GalleryRecord.self,
            StableGalleryMetadataRecord.self,
            GalleryPreviewPageRecord.self,
            DownloadedGalleryDynamicRecord.self,
            GalleryImageIndexRecord.self,
            DownloadJobRecord.self,
            DownloadPageRecord.self,
            DownloadLabelRecord.self,
            QuickSearchRecord.self,
            FilterRuleRecord.self,
            TagTranslationRecord.self
        ]
    }

    public enum MigrationPlan: SchemaMigrationPlan {
        public static let schemas: [any VersionedSchema.Type] = [SchemaV1.self, SchemaV2.self, SchemaV3.self]
        public static let stages: [MigrationStage] = [
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
            .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self)
        ]
    }

    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(
            for: Schema(SchemaV3.models),
            migrationPlan: MigrationPlan.self,
            configurations: configuration
        )
    }
}

@ModelActor
public actor PersistenceStore {
    public func upsert(_ snapshots: [GallerySummary], site: SiteMode = .eHentai) throws {
        for snapshot in snapshots {
            try upsertStableSnapshot(
                StableGalleryMetadataSnapshot(summary: snapshot, sourceSite: site)
            )
        }
    }

    /// Converts pre-V3 scalar records into the separated content records. A
    /// legacy dynamic value is retained only when a matching download job is
    /// present; otherwise it is intentionally discarded from the ordinary
    /// cache path.
    @discardableResult
    public func migrateLegacyGalleryRecords() throws -> Int {
        let galleries = try modelContext.fetch(FetchDescriptor<GalleryRecord>())
        guard galleries.isEmpty == false else { return 0 }
        let downloadKeys = Set(try modelContext.fetch(FetchDescriptor<DownloadJobRecord>()).map(\.key))
        var migratedCount = 0
        for record in galleries where record.stableMetadata == nil {
            var completeness = GalleryMetadataCompleteness(
                title: record.metadataTitleComplete ? .loadedWithValue : .notLoaded,
                japaneseTitle: record.metadataJapaneseTitleComplete ? .loadedWithValue : .notLoaded,
                tags: record.metadataTagsComplete ? .loadedWithValue : .notLoaded
            )
            completeness.category = record.category == nil ? .notLoaded : .loadedWithValue
            completeness.pageCount = record.pageCount == nil ? .notLoaded : .loadedWithValue
            completeness.postedAt = record.postedAt == nil ? .notLoaded : .loadedWithValue
            completeness.thumbnailURL = record.thumbnailURLString == nil ? .notLoaded : .loadedWithValue
            completeness.uploader = record.uploader == nil ? .notLoaded : .loadedWithValue
            let stable = StableGalleryMetadataSnapshot(
                key: record.key,
                sourceSite: .eHentai,
                title: record.title,
                japaneseTitle: record.japaneseTitle,
                uploader: record.uploader,
                tags: record.tags,
                category: record.category,
                pageCount: record.pageCount,
                postedAt: record.postedAt,
                thumbnailURL: record.thumbnailURL,
                capturedAt: .distantPast,
                completeness: completeness
            )
            let stableRecord = StableGalleryMetadataRecord(snapshot: stable)
            stableRecord.gallery = record
            record.stableMetadata = stableRecord
            record.cacheRetention = true
            modelContext.insert(stableRecord)

            if downloadKeys.contains(record.key) {
                record.downloadRetention = true
                var dynamicCompleteness = GalleryMetadataCompleteness()
                dynamicCompleteness.rating = record.rating == nil ? .notLoaded : .loadedWithValue
                dynamicCompleteness.ratingCount = record.ratingCount == nil ? .notLoaded : .loadedWithValue
                dynamicCompleteness.favorite = record.favoriteCategory == nil ? .notLoaded : .loadedWithValue
                let dynamic = DownloadedGalleryDynamicSnapshot(
                    key: record.key,
                    rating: record.rating,
                    ratingCount: record.ratingCount,
                    favoriteCategory: record.favoriteCategory,
                    capturedAt: .distantPast,
                    completeness: dynamicCompleteness
                )
                let dynamicRecord = DownloadedGalleryDynamicRecord(snapshot: dynamic)
                dynamicRecord.gallery = record
                record.dynamicSnapshot = dynamicRecord
                modelContext.insert(dynamicRecord)
            } else {
                record.rating = nil
                record.ratingCount = nil
                record.favoriteCategory = nil
            }
            migratedCount += 1
        }
        if migratedCount > 0 { try modelContext.save() }
        return migratedCount
    }

    /// Stores only stable content. Ratings, favorites and comments never enter
    /// this path, so ordinary list/detail cache writes cannot retain dynamic
    /// account data.
    public func upsertStableSnapshot(
        _ snapshot: StableGalleryMetadataSnapshot,
        retainForDownload: Bool = false
    ) throws {
        let record = try record(for: snapshot.key, creatingFrom: snapshot.summary)
        let merged: StableGalleryMetadataSnapshot
        if let existing = record.stableMetadata {
            merged = GallerySnapshotMerger.merge(existing: existing.snapshot, incoming: snapshot)
            existing.update(from: merged)
            syncPreviewPages(existing, with: merged.pages, state: merged.completeness.pages)
        } else {
            merged = snapshot
            let stable = StableGalleryMetadataRecord(snapshot: merged)
            stable.gallery = record
            record.stableMetadata = stable
            modelContext.insert(stable)
            syncPreviewPages(stable, with: merged.pages, state: merged.completeness.pages)
        }
        record.cacheRetention = true
        if retainForDownload {
            record.downloadRetention = true
        }
        record.applyStableCompatibilityFields(from: merged)
        try modelContext.save()
    }

    public func stableSnapshot(for key: GalleryKey) throws -> StableGalleryMetadataSnapshot? {
        guard let record = try record(for: key) else { return nil }
        guard record.cacheRetention || record.downloadRetention else { return nil }
        if let stable = record.stableMetadata {
            return stable.snapshot
        }
        return StableGalleryMetadataSnapshot(
            summary: record.summary,
            sourceSite: .eHentai,
            capturedAt: .distantPast
        )
    }

    public func stableSnapshots(for keys: Set<GalleryKey>) throws -> [StableGalleryMetadataSnapshot] {
        guard keys.isEmpty == false else { return [] }
        return try modelContext.fetch(FetchDescriptor<GalleryRecord>())
            .compactMap { record in
                guard keys.contains(record.key) else { return nil }
                if let stable = record.stableMetadata { return stable.snapshot }
                return StableGalleryMetadataSnapshot(summary: record.summary, sourceSite: .eHentai, capturedAt: .distantPast)
            }
    }

    public func downloadedStableSnapshots() throws -> [StableGalleryMetadataSnapshot] {
        try modelContext.fetch(FetchDescriptor<GalleryRecord>())
            .filter(\.downloadRetention)
            .compactMap { $0.stableMetadata?.snapshot ?? StableGalleryMetadataSnapshot(
                summary: $0.summary,
                sourceSite: .eHentai,
                capturedAt: .distantPast
            ) }
    }

    public func saveDownloadedDynamicSnapshot(_ snapshot: DownloadedGalleryDynamicSnapshot) throws {
        let fallback = GallerySummary(key: snapshot.key, title: "Gallery \(snapshot.key.gid)")
        let record = try record(for: snapshot.key, creatingFrom: fallback)
        record.downloadRetention = true
        if let existing = record.dynamicSnapshot {
            let merged = GallerySnapshotMerger.merge(existing: existing.snapshot, incoming: snapshot)
            existing.update(from: merged)
            record.applyDynamicCompatibilityFields(from: merged)
        } else {
            let dynamic = DownloadedGalleryDynamicRecord(snapshot: snapshot)
            dynamic.gallery = record
            record.dynamicSnapshot = dynamic
            modelContext.insert(dynamic)
            record.applyDynamicCompatibilityFields(from: snapshot)
        }
        try modelContext.save()
    }

    public func downloadedDynamicSnapshot(for key: GalleryKey) throws -> DownloadedGalleryDynamicSnapshot? {
        try record(for: key)?.dynamicSnapshot?.snapshot
    }

    public func galleryTransferRecords(for keys: Set<GalleryKey>) throws -> [GalleryTransferRecord] {
        guard keys.isEmpty == false else { return [] }
        let records = try modelContext.fetch(FetchDescriptor<GalleryRecord>())
        return try records.compactMap { record in
            guard keys.contains(record.key) else { return nil }
            let stable = record.stableMetadata?.snapshot ?? StableGalleryMetadataSnapshot(
                summary: record.summary,
                sourceSite: .eHentai,
                capturedAt: .distantPast
            )
            let dynamic = record.downloadRetention ? record.dynamicSnapshot?.snapshot : nil
            return try GalleryTransferRecord(
                stable: stable,
                dynamic: dynamic,
                exportedAt: Date(),
                sourceSite: stable.sourceSite
            )
        }
    }

    public func promoteToDownloadedGallery(
        stable: StableGalleryMetadataSnapshot,
        dynamic: DownloadedGalleryDynamicSnapshot? = nil
    ) throws {
        try upsertStableSnapshot(stable, retainForDownload: true)
        if let dynamic {
            try saveDownloadedDynamicSnapshot(dynamic)
        } else if let record = try record(for: stable.key) {
            record.downloadRetention = true
            try modelContext.save()
        }
    }

    /// Removes ordinary content and image index entries while preserving the
    /// identity record, reading state, local favorite state and all downloads.
    public func clearOrdinaryCache() throws {
        let records = try modelContext.fetch(FetchDescriptor<GalleryRecord>())
        let removableKeys = Set(records.filter { $0.cacheRetention && !$0.downloadRetention }.map(\.key))
        for record in records where removableKeys.contains(record.key) {
            if let stable = record.stableMetadata {
                modelContext.delete(stable)
                record.stableMetadata = nil
            }
            record.cacheRetention = false
            record.title = ""
            record.japaneseTitle = nil
            record.thumbnailURLString = nil
            record.category = nil
            record.pageCount = nil
            record.postedAt = nil
            record.uploader = nil
            record.tags = []
            record.metadataTitleComplete = false
            record.metadataJapaneseTitleComplete = false
            record.metadataTagsComplete = false
        }
        let imageRecords = try modelContext.fetch(FetchDescriptor<GalleryImageIndexRecord>())
        for image in imageRecords where removableKeys.contains(GalleryKey(gid: image.gid, token: image.token)) {
            modelContext.delete(image)
        }
        if removableKeys.isEmpty == false || imageRecords.isEmpty == false {
            try modelContext.save()
        }
    }

    /// Clears the local library lists without touching downloaded content,
    /// download jobs, or reading files.
    public func clearLibraryState() throws {
        let records = try modelContext.fetch(FetchDescriptor<GalleryRecord>())
        var didChange = false
        for record in records where record.isFavorite || record.lastReadAt != nil || record.lastReadPage != 0 {
            record.isFavorite = false
            record.lastReadAt = nil
            record.lastReadPage = 0
            didChange = true
        }
        if didChange {
            try modelContext.save()
        }
    }

    public func recordImageIndex(
        key: GalleryKey,
        site: SiteMode,
        kind: String,
        pageIndex: Int? = nil,
        originalURL: URL,
        localPath: String,
        byteCount: Int64,
        lastAccessedAt: Date = Date()
    ) throws {
        let existing = try modelContext.fetch(FetchDescriptor<GalleryImageIndexRecord>()).first {
            $0.gid == key.gid && $0.token == key.token
                && $0.siteRaw == site.rawValue && $0.kindRaw == kind
                && $0.pageIndex == pageIndex && $0.originalURLString == originalURL.absoluteString
        }
        if let existing {
            existing.localPath = localPath
            existing.byteCount = max(0, byteCount)
            existing.lastAccessedAt = lastAccessedAt
        } else {
            modelContext.insert(GalleryImageIndexRecord(
                key: key,
                site: site,
                kind: kind,
                pageIndex: pageIndex,
                originalURL: originalURL,
                localPath: localPath,
                byteCount: byteCount,
                lastAccessedAt: lastAccessedAt
            ))
        }
        try modelContext.save()
    }

    private func record(for key: GalleryKey) throws -> GalleryRecord? {
        var descriptor = FetchDescriptor<GalleryRecord>(predicate: #Predicate {
            $0.gid == key.gid && $0.token == key.token
        })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func record(
        for key: GalleryKey,
        creatingFrom summary: GallerySummary
    ) throws -> GalleryRecord {
        if let existing = try record(for: key) { return existing }
        let created = GalleryRecord(snapshot: summary)
        modelContext.insert(created)
        return created
    }

    private func syncPreviewPages(
        _ metadata: StableGalleryMetadataRecord,
        with pages: [GalleryPageDescriptor],
        state: GalleryFieldState
    ) {
        guard state.isLoaded else { return }
        let byIndex = Dictionary(uniqueKeysWithValues: pages.map { ($0.index, $0) })
        for page in metadata.pages {
            guard let descriptor = byIndex[page.pageIndex] else {
                modelContext.delete(page)
                continue
            }
            page.pageURLString = descriptor.pageURL.absoluteString
            page.previewURLString = descriptor.previewURL?.absoluteString
            page.clipXOffset = descriptor.previewClip?.xOffset
            page.clipWidth = descriptor.previewClip?.width
            page.clipHeight = descriptor.previewClip?.height
        }
        let existingIndexes = Set(metadata.pages.map(\.pageIndex))
        for page in pages where existingIndexes.contains(page.index) == false {
            let record = GalleryPreviewPageRecord(page: page)
            record.metadata = metadata
            metadata.pages.append(record)
            modelContext.insert(record)
        }
    }

    public func updateReadingProgress(for key: GalleryKey, page: Int) throws {
        var descriptor = FetchDescriptor<GalleryRecord>(predicate: #Predicate {
            $0.gid == key.gid && $0.token == key.token
        })
        descriptor.fetchLimit = 1
        if let record = try modelContext.fetch(descriptor).first {
            record.lastReadPage = page
            record.lastReadAt = Date()
            try modelContext.save()
        }
    }

    public func readingPage(for key: GalleryKey) throws -> Int? {
        var descriptor = FetchDescriptor<GalleryRecord>(predicate: #Predicate {
            $0.gid == key.gid && $0.token == key.token
        })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.lastReadPage
    }

    public func resetReadingProgress(for keys: [GalleryKey]) throws {
        guard keys.isEmpty == false else { return }
        let records = try modelContext.fetch(FetchDescriptor<GalleryRecord>())
        let keySet = Set(keys)
        var didChange = false
        for record in records where keySet.contains(record.key) {
            record.lastReadPage = 0
            record.lastReadAt = nil
            didChange = true
        }
        if didChange { try modelContext.save() }
    }

    public func isFavorite(for key: GalleryKey) throws -> Bool? {
        var descriptor = FetchDescriptor<GalleryRecord>(predicate: #Predicate {
            $0.gid == key.gid && $0.token == key.token
        })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.isFavorite
    }

    public func setFavorite(for key: GalleryKey, isFavorite: Bool) throws {
        var descriptor = FetchDescriptor<GalleryRecord>(predicate: #Predicate {
            $0.gid == key.gid && $0.token == key.token
        })
        descriptor.fetchLimit = 1
        if let record = try modelContext.fetch(descriptor).first {
            record.isFavorite = isFavorite
            try modelContext.save()
        }
    }

    public func recent(limit: Int = 50) throws -> [GallerySummary] {
        let records = try modelContext.fetch(FetchDescriptor<GalleryRecord>(sortBy: [SortDescriptor(\.lastReadAt, order: .reverse)]))
        return records.filter { $0.lastReadAt != nil }.prefix(limit).map { record in
            var summary = record.summary
            summary.postedAt = record.lastReadAt
            return summary
        }
    }

    public func favorites(limit: Int = 50) throws -> [GallerySummary] {
        let records = try modelContext.fetch(FetchDescriptor<GalleryRecord>(sortBy: [SortDescriptor(\.title)]))
        return records.filter(\.isFavorite).prefix(limit).map(\.summary)
    }

    public func gallerySummary(for key: GalleryKey) throws -> GallerySummary? {
        var descriptor = FetchDescriptor<GalleryRecord>(predicate: #Predicate {
            $0.gid == key.gid && $0.token == key.token
        })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.summary
    }

    public func upsertDownload(
        key: GalleryKey,
        title: String,
        japaneseTitle: String? = nil,
        pages: [GalleryPageDescriptor],
        completedPageIndexes: Set<Int>,
        stateRaw: String,
        errorMessage: String?,
        label: String? = nil
    ) throws {
        if let gallery = try record(for: key) {
            gallery.downloadRetention = true
        } else {
            var completeness = GalleryMetadataCompleteness()
            completeness.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .loadedEmpty
                : .loadedWithValue
            completeness.japaneseTitle = japaneseTitle == nil ? .notLoaded : .loadedWithValue
            completeness.pageCount = .loadedWithValue
            completeness.pages = pages.isEmpty ? .loadedEmpty : .loadedWithValue
            try upsertStableSnapshot(
                StableGalleryMetadataSnapshot(
                    key: key,
                    sourceSite: .eHentai,
                    title: title,
                    japaneseTitle: japaneseTitle,
                    pageCount: pages.count,
                    pages: pages,
                    completeness: completeness
                ),
                retainForDownload: true
            )
        }
        var descriptor = FetchDescriptor<DownloadJobRecord>(predicate: #Predicate {
            $0.gid == key.gid && $0.token == key.token
        })
        descriptor.fetchLimit = 1
        let record: DownloadJobRecord
        if let existing = try modelContext.fetch(descriptor).first {
            record = existing
        } else {
            record = DownloadJobRecord(key: key, title: title, japaneseTitle: japaneseTitle, totalPages: pages.count)
            modelContext.insert(record)
        }
        record.title = title
        record.japaneseTitle = japaneseTitle
        record.totalPages = pages.count
        record.completedPages = completedPageIndexes.count
        record.stateRaw = stateRaw
        record.errorMessage = errorMessage
        record.label = label
        record.updatedAt = Date()

        for page in pages {
            let pageRecord: DownloadPageRecord
            if let existing = record.pages.first(where: { $0.pageIndex == page.index }) {
                pageRecord = existing
            } else {
                pageRecord = DownloadPageRecord(pageIndex: page.index, fileName: "page-\(page.index + 1).bin")
                pageRecord.job = record
                record.pages.append(pageRecord)
                modelContext.insert(pageRecord)
            }
            pageRecord.directURLString = page.pageURL.absoluteString
            pageRecord.previewURLString = page.previewURL?.absoluteString
            pageRecord.stateRaw = completedPageIndexes.contains(page.index) ? "completed" : "queued"
            if completedPageIndexes.contains(page.index) {
                pageRecord.backgroundTaskIdentifier = nil
            }
        }
        try modelContext.save()
    }

    public func downloadJobs() throws -> [PersistedDownload] {
        var descriptor = FetchDescriptor<DownloadJobRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.pages]
        let records = try modelContext.fetch(descriptor)
        let galleryRecords = try modelContext.fetch(FetchDescriptor<GalleryRecord>())
        let summariesByKey = Dictionary(uniqueKeysWithValues: galleryRecords.map { ($0.key, $0.summary) })
        return records.map { record in
            let key = record.key
            var pages: [GalleryPageDescriptor] = []
            var completed: Set<Int> = []
            var inFlight: Set<Int> = []
            pages.reserveCapacity(record.pages.count)

            for page in record.pages {
                if page.stateRaw == "completed" { completed.insert(page.pageIndex) }
                if page.backgroundTaskIdentifier != nil { inFlight.insert(page.pageIndex) }
                guard let directURLString = page.directURLString,
                      let pageURL = URL(string: directURLString) else { continue }
                pages.append(GalleryPageDescriptor(
                    galleryKey: key,
                    index: page.pageIndex,
                    pageURL: pageURL,
                    previewURL: page.previewURLString.flatMap(URL.init(string:))
                ))
            }
            pages.sort { $0.index < $1.index }
            return PersistedDownload(
                key: key,
                title: record.title,
                japaneseTitle: record.japaneseTitle,
                tags: summariesByKey[key]?.tags ?? [],
                pages: pages,
                totalPageCount: record.totalPages,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                label: record.label,
                completedPageIndexes: completed,
                stateRaw: record.stateRaw,
                errorMessage: record.errorMessage,
                inFlightPageIndexes: inFlight
            )
        }
    }

    public func setBackgroundTaskIdentifier(_ identifier: Int?, for key: GalleryKey, pageIndex: Int) throws {
        var descriptor = FetchDescriptor<DownloadJobRecord>(predicate: #Predicate {
            $0.gid == key.gid && $0.token == key.token
        })
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first,
              let page = record.pages.first(where: { $0.pageIndex == pageIndex }) else { return }
        page.backgroundTaskIdentifier = identifier
        record.updatedAt = Date()
        try modelContext.save()
    }

    public func markDownloadPageCompleted(for key: GalleryKey, pageIndex: Int, bytes: Int64) throws {
        var descriptor = FetchDescriptor<DownloadJobRecord>(predicate: #Predicate {
            $0.gid == key.gid && $0.token == key.token
        })
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first,
              let page = record.pages.first(where: { $0.pageIndex == pageIndex }) else { return }
        page.stateRaw = "completed"
        page.bytes = bytes
        page.backgroundTaskIdentifier = nil
        record.completedPages = record.pages.filter { $0.stateRaw == "completed" }.count
        record.updatedAt = Date()
        try modelContext.save()
    }

    public func deleteDownload(for key: GalleryKey) throws {
        var descriptor = FetchDescriptor<DownloadJobRecord>(predicate: #Predicate {
            $0.gid == key.gid && $0.token == key.token
        })
        descriptor.fetchLimit = 1
        if let downloadRecord = try modelContext.fetch(descriptor).first {
            modelContext.delete(downloadRecord)
            if let gallery = try record(for: key) {
                gallery.downloadRetention = false
                if let dynamic = gallery.dynamicSnapshot {
                    modelContext.delete(dynamic)
                    gallery.dynamicSnapshot = nil
                }
            }
            try modelContext.save()
        }
    }

    /// Removes several download records in one SwiftData transaction. The
    /// coordinator deletes media files separately so file work can report
    /// progress without holding this context open between every item.
    public func deleteDownloads(for keys: Set<GalleryKey>) throws {
        guard keys.isEmpty == false else { return }

        let downloadRecords = try modelContext.fetch(FetchDescriptor<DownloadJobRecord>())
        let galleryRecords = try modelContext.fetch(FetchDescriptor<GalleryRecord>())
        let galleriesByKey = Dictionary(uniqueKeysWithValues: galleryRecords.map { ($0.key, $0) })
        var didChange = false

        for downloadRecord in downloadRecords where keys.contains(downloadRecord.key) {
            modelContext.delete(downloadRecord)
            didChange = true

            guard let gallery = galleriesByKey[downloadRecord.key] else { continue }
            gallery.downloadRetention = false
            if let dynamic = gallery.dynamicSnapshot {
                modelContext.delete(dynamic)
                gallery.dynamicSnapshot = nil
            }
        }

        if didChange {
            try modelContext.save()
        }
    }

    public func recordQuickSearch(_ query: String) throws {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else { return }
        var descriptor = FetchDescriptor<QuickSearchRecord>(predicate: #Predicate {
            $0.query == normalized
        })
        descriptor.fetchLimit = 1
        if let record = try modelContext.fetch(descriptor).first {
            record.lastUsedAt = Date()
        } else {
            modelContext.insert(QuickSearchRecord(query: normalized))
        }
        try modelContext.save()
    }

    public func quickSearches(limit: Int = 20) throws -> [String] {
        var descriptor = FetchDescriptor<QuickSearchRecord>(sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map(\.query)
    }

    public func quickSearchSuggestions(prefix: String, limit: Int = 100) throws -> [String] {
        let normalizedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        var descriptor = FetchDescriptor<QuickSearchRecord>(sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)])
        descriptor.fetchLimit = max(limit, 0)
        let searches = try modelContext.fetch(descriptor).map(\.query)
        guard normalizedPrefix.isEmpty == false else { return searches }
        return searches.filter {
            $0 != normalizedPrefix
                && $0.range(of: normalizedPrefix, options: [.caseInsensitive, .anchored]) != nil
        }
    }

    public func deleteQuickSearch(_ query: String) throws {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else { return }
        let records = try modelContext.fetch(FetchDescriptor<QuickSearchRecord>(predicate: #Predicate {
            $0.query == normalized
        }))
        for record in records { modelContext.delete(record) }
        if records.isEmpty == false { try modelContext.save() }
    }

    public func downloadLabels() throws -> [String] {
        try modelContext.fetch(FetchDescriptor<DownloadLabelRecord>(sortBy: [SortDescriptor(\.createdAt)] )).map(\.name)
    }

    public func saveDownloadLabel(_ name: String) throws {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else { return }
        var descriptor = FetchDescriptor<DownloadLabelRecord>(predicate: #Predicate { $0.name == normalized })
        descriptor.fetchLimit = 1
        if try modelContext.fetch(descriptor).isEmpty {
            modelContext.insert(DownloadLabelRecord(name: normalized))
            try modelContext.save()
        }
    }

    public func filterRules() throws -> [FilterRuleSnapshot] {
        try modelContext.fetch(FetchDescriptor<FilterRuleRecord>(sortBy: [SortDescriptor(\.pattern)])).map {
            FilterRuleSnapshot(
                pattern: $0.pattern,
                isEnabled: $0.isEnabled,
                mode: GalleryFilterMode(rawValue: $0.modeRaw) ?? .title
            )
        }
    }

    public func setFilterRule(pattern: String, isEnabled: Bool, mode: GalleryFilterMode = .title) throws {
        let normalized = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else { return }
        var descriptor = FetchDescriptor<FilterRuleRecord>(predicate: #Predicate {
            $0.pattern == normalized && $0.modeRaw == mode.rawValue
        })
        descriptor.fetchLimit = 1
        if let record = try modelContext.fetch(descriptor).first {
            record.isEnabled = isEnabled
        } else {
            modelContext.insert(FilterRuleRecord(pattern: normalized, isEnabled: isEnabled, mode: mode))
        }
        try modelContext.save()
    }

    public func deleteFilterRule(pattern: String, mode: GalleryFilterMode = .title) throws {
        let normalized = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else { return }
        let records = try modelContext.fetch(FetchDescriptor<FilterRuleRecord>(predicate: #Predicate {
            $0.pattern == normalized && $0.modeRaw == mode.rawValue
        }))
        for record in records { modelContext.delete(record) }
        if records.isEmpty == false { try modelContext.save() }
    }

    public func saveTagTranslation(tag: String, locale: String, localizedText: String) throws {
        let normalizedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLocale = locale.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedText = localizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedTag.isEmpty == false, normalizedLocale.isEmpty == false, normalizedText.isEmpty == false else { return }
        var descriptor = FetchDescriptor<TagTranslationRecord>(predicate: #Predicate {
            $0.tag == normalizedTag && $0.locale == normalizedLocale
        })
        descriptor.fetchLimit = 1
        if let record = try modelContext.fetch(descriptor).first {
            record.localizedText = normalizedText
            record.updatedAt = Date()
        } else {
            modelContext.insert(TagTranslationRecord(tag: normalizedTag, locale: normalizedLocale, localizedText: normalizedText))
        }
        try modelContext.save()
    }

    public func tagTranslations(locale: String) throws -> [String: String] {
        let normalizedLocale = locale.trimmingCharacters(in: .whitespacesAndNewlines)
        let records = try modelContext.fetch(FetchDescriptor<TagTranslationRecord>(predicate: #Predicate {
            $0.locale == normalizedLocale
        }))
        return Dictionary(uniqueKeysWithValues: records.map { ($0.tag, $0.localizedText) })
    }

    /// Bulk import of the reference tag database: inserts missing keys for a
    /// locale in a single save, leaving existing translations untouched.
    public func saveTagTranslations(_ entries: [(tag: String, localizedText: String)], locale: String) throws {
        let normalizedLocale = locale.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedLocale.isEmpty == false else { return }
        let existing = Set(try modelContext.fetch(
            FetchDescriptor<TagTranslationRecord>(predicate: #Predicate { $0.locale == normalizedLocale })
        ).map(\.tag))
        var insertedCount = 0
        for (rawTag, text) in entries {
            let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard tag.isEmpty == false, existing.contains(tag) == false else { continue }
            modelContext.insert(
                TagTranslationRecord(tag: tag, locale: normalizedLocale, localizedText: text)
            )
            insertedCount += 1
        }
        guard insertedCount > 0 else { return }
        try modelContext.save()
    }

    public func gallerySyncSummaries(for keys: Set<GalleryKey>) throws -> [GallerySummary] {
        guard keys.isEmpty == false else { return [] }
        return try modelContext.fetch(FetchDescriptor<GalleryRecord>())
            .map(\.summary)
            .filter { keys.contains($0.key) }
            .sorted { $0.key.id < $1.key.id }
    }

    /// Reads only the requested local gallery records. The local scrolling
    /// page calls this with its visible window, so it must not scan and
    /// materialize the entire gallery cache like the transfer-oriented query
    /// above does.
    public func localGallerySummaries(for keys: Set<GalleryKey>) throws -> [GallerySummary] {
        guard keys.isEmpty == false else { return [] }
        return try keys.sorted { $0.id < $1.id }.compactMap { key in
            try record(for: key)?.summary
        }
    }

    /// Inserts only galleries that do not already exist locally. Existing
    /// records are intentionally untouched, including their metadata and all
    /// local state.
    public func insertMissingGallerySyncSummaries(
        _ summaries: [GallerySummary]
    ) throws -> GallerySyncImportOutcome {
        var uniqueSummaries: [GallerySummary] = []
        var incomingKeys = Set<GalleryKey>()
        uniqueSummaries.reserveCapacity(summaries.count)
        for summary in summaries where incomingKeys.insert(summary.key).inserted {
            uniqueSummaries.append(summary)
        }

        let existingKeys = Set(try modelContext.fetch(FetchDescriptor<GalleryRecord>()).map(\.key))
        let missing = uniqueSummaries.filter { existingKeys.contains($0.key) == false }
        for summary in missing {
            try upsertStableSnapshot(
                StableGalleryMetadataSnapshot(summary: summary, sourceSite: .eHentai)
            )
        }

        return GallerySyncImportOutcome(
            sourceCount: summaries.count,
            duplicateInFileCount: summaries.count - uniqueSummaries.count,
            existingCount: uniqueSummaries.count - missing.count,
            insertedCount: missing.count
        )
    }

    /// Merges transferable gallery metadata while preserving local reading
    /// progress, favorite state and all downloaded page records.
    public func mergeGallerySyncSummaries(
        _ summaries: [GallerySummary]
    ) throws -> GallerySyncImportOutcome {
        var uniqueSummaries: [GallerySummary] = []
        var incomingKeys = Set<GalleryKey>()
        uniqueSummaries.reserveCapacity(summaries.count)
        for summary in summaries where incomingKeys.insert(summary.key).inserted {
            uniqueSummaries.append(summary)
        }

        let records = try modelContext.fetch(FetchDescriptor<GalleryRecord>())
        let existingKeys = Set(records.map(\.key))
        var insertedCount = 0
        for summary in uniqueSummaries {
            if existingKeys.contains(summary.key) == false {
                insertedCount += 1
            }
            try upsertStableSnapshot(
                StableGalleryMetadataSnapshot(summary: summary, sourceSite: .eHentai)
            )
        }

        return GallerySyncImportOutcome(
            sourceCount: summaries.count,
            duplicateInFileCount: summaries.count - uniqueSummaries.count,
            existingCount: uniqueSummaries.count - insertedCount,
            insertedCount: insertedCount
        )
    }
}

public struct GallerySyncImportOutcome: Sendable, Hashable {
    public let sourceCount: Int
    public let duplicateInFileCount: Int
    public let existingCount: Int
    public let insertedCount: Int

    public init(
        sourceCount: Int,
        duplicateInFileCount: Int,
        existingCount: Int,
        insertedCount: Int
    ) {
        self.sourceCount = sourceCount
        self.duplicateInFileCount = duplicateInFileCount
        self.existingCount = existingCount
        self.insertedCount = insertedCount
    }
}

private extension GalleryRecord {
    var summary: GallerySummary {
        if cacheRetention == false, downloadRetention == false {
            return GallerySummary(key: key, title: "")
        }
        if let stableMetadata {
            var value = stableMetadata.snapshot.summary
            if downloadRetention, let dynamicSnapshot {
                value.rating = dynamicSnapshot.rating
                value.ratingCount = dynamicSnapshot.ratingCount
                value.favoriteCategory = dynamicSnapshot.favoriteCategory
            }
            return value
        }
        return GallerySummary(
            key: key,
            title: title,
            japaneseTitle: japaneseTitle,
            thumbnailURL: thumbnailURL,
            category: category,
            pageCount: pageCount,
            postedAt: postedAt,
            rating: rating,
            ratingCount: ratingCount,
            favoriteCategory: favoriteCategory,
            uploader: uploader,
            tags: tags,
            metadataCompleteness: GalleryMetadataCompleteness(
                title: metadataTitleComplete ? .loadedWithValue : .notLoaded,
                japaneseTitle: metadataJapaneseTitleComplete ? .loadedWithValue : .notLoaded,
                tags: metadataTagsComplete ? .loadedWithValue : .notLoaded
            )
        )
    }

    func applyStableCompatibilityFields(from snapshot: StableGalleryMetadataSnapshot) {
        title = snapshot.title
        japaneseTitle = snapshot.japaneseTitle
        thumbnailURLString = snapshot.thumbnailURL?.absoluteString
        category = snapshot.category
        pageCount = snapshot.pageCount
        postedAt = snapshot.postedAt
        uploader = snapshot.uploader
        tags = snapshot.tags
        metadataTitleComplete = snapshot.completeness.title.isLoaded
        metadataJapaneseTitleComplete = snapshot.completeness.japaneseTitle.isLoaded
        metadataTagsComplete = snapshot.completeness.tags.isLoaded
    }

    func applyDynamicCompatibilityFields(from snapshot: DownloadedGalleryDynamicSnapshot) {
        rating = snapshot.rating
        ratingCount = snapshot.ratingCount
        favoriteCategory = snapshot.favoriteCategory
    }
}

private extension StableGalleryMetadataRecord {
    var snapshot: StableGalleryMetadataSnapshot {
        let pageDescriptors = pages.compactMap(\.descriptor).sorted { $0.index < $1.index }
        return StableGalleryMetadataSnapshot(
            key: key,
            sourceSite: SiteMode(rawValue: sourceSiteRaw) ?? .eHentai,
            title: title,
            japaneseTitle: japaneseTitle,
            authors: authors,
            uploader: uploader,
            tags: tags,
            category: category,
            language: language,
            pageCount: pageCount,
            postedAt: postedAt,
            thumbnailURL: thumbnailURLString.flatMap(URL.init(string:)),
            fileSize: fileSize,
            descriptionText: descriptionText,
            externalURL: externalURLString.flatMap(URL.init(string:)),
            pages: pageDescriptors,
            capturedAt: capturedAt,
            completeness: GalleryMetadataCompleteness(
                title: GalleryFieldState(rawValue: titleStateRaw) ?? .notLoaded,
                japaneseTitle: GalleryFieldState(rawValue: japaneseTitleStateRaw) ?? .notLoaded,
                authors: GalleryFieldState(rawValue: authorsStateRaw) ?? .notLoaded,
                uploader: GalleryFieldState(rawValue: uploaderStateRaw) ?? .notLoaded,
                tags: GalleryFieldState(rawValue: tagsStateRaw) ?? .notLoaded,
                category: GalleryFieldState(rawValue: categoryStateRaw) ?? .notLoaded,
                language: GalleryFieldState(rawValue: languageStateRaw) ?? .notLoaded,
                pageCount: GalleryFieldState(rawValue: pageCountStateRaw) ?? .notLoaded,
                postedAt: GalleryFieldState(rawValue: postedAtStateRaw) ?? .notLoaded,
                thumbnailURL: GalleryFieldState(rawValue: thumbnailURLStateRaw) ?? .notLoaded,
                fileSize: GalleryFieldState(rawValue: fileSizeStateRaw) ?? .notLoaded,
                description: GalleryFieldState(rawValue: descriptionStateRaw) ?? .notLoaded,
                externalURL: GalleryFieldState(rawValue: externalURLStateRaw) ?? .notLoaded,
                pages: GalleryFieldState(rawValue: pagesStateRaw) ?? .notLoaded
            )
        )
    }
}

private extension DownloadedGalleryDynamicRecord {
    var snapshot: DownloadedGalleryDynamicSnapshot {
        let comments = (try? JSONDecoder().decode(
            [DownloadedGalleryCommentSnapshot].self,
            from: commentsData
        )) ?? []
        return DownloadedGalleryDynamicSnapshot(
            key: key,
            rating: rating,
            ratingCount: ratingCount,
            favoriteCount: favoriteCount,
            favoriteName: favoriteName,
            favoriteCategory: favoriteCategory,
            comments: comments,
            capturedAt: capturedAt,
            completeness: GalleryMetadataCompleteness(
                rating: GalleryFieldState(rawValue: ratingStateRaw) ?? .notLoaded,
                ratingCount: GalleryFieldState(rawValue: ratingCountStateRaw) ?? .notLoaded,
                favorite: GalleryFieldState(rawValue: favoriteStateRaw) ?? .notLoaded,
                comments: GalleryFieldState(rawValue: commentsStateRaw) ?? .notLoaded
            )
        )
    }
}
