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

    public enum SchemaV4: VersionedSchema {
        public static let versionIdentifier = Schema.Version(4, 0, 0)

        public static let models: [any PersistentModel.Type] = [
            GalleryRecord.self,
            StableGalleryMetadataRecord.self,
            GalleryPreviewPageRecord.self,
            DownloadedGalleryDynamicRecord.self,
            DownloadedGalleryMetadataRecord.self,
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
        public static let schemas: [any VersionedSchema.Type] = [SchemaV4.self]
        public static let stages: [MigrationStage] = []
    }

    public static func make(storeURL: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let configuration = if let storeURL {
            ModelConfiguration(url: storeURL)
        } else {
            ModelConfiguration(isStoredInMemoryOnly: inMemory)
        }
        return try ModelContainer(
            for: Schema(SchemaV4.models),
            migrationPlan: MigrationPlan.self,
            configurations: configuration
        )
    }

    /// The default on-disk store URL used by `make()`. Keeping this derived
    /// from the same SwiftData configuration lets recovery remove a broken
    /// store without guessing its sandbox path.
    public static var persistentStoreURL: URL {
        ModelConfiguration(isStoredInMemoryOnly: false).url
    }
}

@ModelActor
public actor PersistenceStore {
    private var deviceSyncIndex: (any DeviceSyncIndexSink)?
    private var pendingDeviceSyncMetadataKeys = Set<GalleryKey>()
    private var pendingDeviceSyncMetadataRemovals = Set<GalleryKey>()

    public func configureDeviceSyncIndex(_ index: (any DeviceSyncIndexSink)?) async {
        deviceSyncIndex = index
        await flushDeviceSyncIndex()
    }

    public func upsert(_ snapshots: [GallerySummary], site: SiteMode = .eHentai) throws {
        for snapshot in snapshots {
            let stable = StableGalleryMetadataSnapshot(summary: snapshot, sourceSite: site)
            try applyStableSnapshot(stable, retainForDownload: false)
            try applyDynamicSnapshotIfPresent(from: snapshot, capturedAt: stable.capturedAt, retainForDownload: false)
        }
        try modelContext.save()
    }

    /// Stores only stable content. Ratings, favorites and comments never enter
    /// this path, so ordinary list/detail cache writes cannot retain dynamic
    /// account data.
    public func upsertStableSnapshot(
        _ snapshot: StableGalleryMetadataSnapshot,
        retainForDownload: Bool = false
    ) async throws {
        try applyStableSnapshot(snapshot, retainForDownload: retainForDownload)
        try applyDynamicSnapshotIfPresent(
            from: snapshot.summary,
            capturedAt: snapshot.capturedAt,
            retainForDownload: retainForDownload
        )
        try modelContext.save()
        await flushDeviceSyncIndex()
    }

    /// Applies several stable snapshots in one SwiftData transaction. This is
    /// used by metadata refresh so a 25-item gdata response does not cause 25
    /// independent context saves.
    public func upsertStableSnapshots(
        _ snapshots: [StableGalleryMetadataSnapshot],
        retainForDownload: Bool = false
    ) async throws {
        for snapshot in snapshots {
            try applyStableSnapshot(snapshot, retainForDownload: retainForDownload)
            try applyDynamicSnapshotIfPresent(
                from: snapshot.summary,
                capturedAt: snapshot.capturedAt,
                retainForDownload: retainForDownload
            )
        }
        try modelContext.save()
        await flushDeviceSyncIndex()
    }

    /// Persists stable metadata and downloaded dynamic values together. The
    /// field-level merge runs before the single save, preserving values when a
    /// response marks a field as `.notLoaded`.
    public func saveDownloadedMetadata(
        stableSnapshots: [StableGalleryMetadataSnapshot],
        dynamicSnapshots: [DownloadedGalleryDynamicSnapshot]
    ) async throws {
        for snapshot in stableSnapshots {
            try applyStableSnapshot(snapshot, retainForDownload: true)
        }
        for snapshot in dynamicSnapshots {
            try applyDownloadedDynamicSnapshot(snapshot)
        }
        try modelContext.save()
        await flushDeviceSyncIndex()
    }

    private func applyStableSnapshot(
        _ snapshot: StableGalleryMetadataSnapshot,
        retainForDownload: Bool
    ) throws {
        if retainForDownload {
            try applyDownloadedStableSnapshot(snapshot)
            return
        }
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
        record.applyStableCompatibilityFields(from: merged)
    }

    public func stableSnapshot(for key: GalleryKey) throws -> StableGalleryMetadataSnapshot? {
        guard let record = try record(for: key) else { return nil }
        guard record.cacheRetention else { return nil }
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
                guard keys.contains(record.key), record.cacheRetention else { return nil }
                if let stable = record.stableMetadata { return stable.snapshot }
                return StableGalleryMetadataSnapshot(summary: record.summary, sourceSite: .eHentai, capturedAt: .distantPast)
            }
    }

    public func downloadedStableSnapshots() throws -> [StableGalleryMetadataSnapshot] {
        try modelContext.fetch(FetchDescriptor<DownloadedGalleryMetadataRecord>())
            .compactMap { try? decodeStable(from: $0) }
    }

    public func saveDownloadedDynamicSnapshot(_ snapshot: DownloadedGalleryDynamicSnapshot) async throws {
        try applyDownloadedDynamicSnapshot(snapshot)
        try modelContext.save()
        await flushDeviceSyncIndex()
    }

    public func saveDownloadedDynamicSnapshots(_ snapshots: [DownloadedGalleryDynamicSnapshot]) async throws {
        for snapshot in snapshots {
            try applyDownloadedDynamicSnapshot(snapshot)
        }
        try modelContext.save()
        await flushDeviceSyncIndex()
    }

    private func applyDownloadedDynamicSnapshot(
        _ snapshot: DownloadedGalleryDynamicSnapshot,
        retainForDownload: Bool = true
    ) throws {
        guard retainForDownload else { return }
        let record: DownloadedGalleryMetadataRecord
        if let existing = try downloadedMetadataRecord(for: snapshot.key) {
            record = existing
        } else {
            let stable = StableGalleryMetadataSnapshot(
                summary: GallerySummary(key: snapshot.key, title: "Gallery \(snapshot.key.gid)"),
                sourceSite: .eHentai,
                capturedAt: .distantPast
            )
            record = try insertDownloadedMetadata(stable: stable, dynamic: nil)
        }
        let existingDynamic = try decodeDynamic(from: record)
        let merged = GallerySnapshotMerger.merge(existing: existingDynamic, incoming: snapshot)
        record.dynamicData = try JSONEncoder().encode(merged)
        record.updatedAt = Date()
        pendingDeviceSyncMetadataKeys.insert(snapshot.key)
        pendingDeviceSyncMetadataRemovals.remove(snapshot.key)
    }

    private func flushDeviceSyncIndex() async {
        guard let index = deviceSyncIndex else { return }
        let keys = pendingDeviceSyncMetadataKeys
        let removals = pendingDeviceSyncMetadataRemovals
        pendingDeviceSyncMetadataKeys.removeAll(keepingCapacity: true)
        pendingDeviceSyncMetadataRemovals.removeAll(keepingCapacity: true)

        for key in keys.sorted(by: { $0.id < $1.id }) where removals.contains(key) == false {
            let record: DownloadedGalleryMetadataRecord?
            do {
                record = try downloadedMetadataRecord(for: key)
            } catch {
                await index.removeMetadata(for: key)
                continue
            }
            guard let record, let stable = try? decodeStable(from: record) else {
                await index.removeMetadata(for: key)
                continue
            }
            let dynamic: DownloadedGalleryDynamicSnapshot?
            do {
                dynamic = try decodeDynamic(from: record)
            } catch {
                await index.removeMetadata(for: key)
                continue
            }
            guard let metadata = try? DeviceSyncMetadataDigest.make(stable: stable, dynamic: dynamic) else {
                await index.removeMetadata(for: key)
                continue
            }
            await index.upsertMetadata(DeviceSyncIndexMetadataEntry(key: key, metadata: metadata))
        }
        for key in removals.sorted(by: { $0.id < $1.id }) {
            await index.removeMetadata(for: key)
        }
    }

    private func applyDynamicSnapshotIfPresent(
        from summary: GallerySummary,
        capturedAt: Date,
        retainForDownload: Bool
    ) throws {
        let sourceCompleteness = summary.metadataCompleteness
        let ratingState = summaryOptionalState(
            explicit: sourceCompleteness?.rating,
            value: summary.rating
        )
        let ratingCountState = summaryOptionalState(
            explicit: sourceCompleteness?.ratingCount,
            value: summary.ratingCount
        )
        let favoriteState = summaryFavoriteState(
            explicit: sourceCompleteness?.favorite,
            value: summary.favoriteCategory
        )
        guard ratingState.isLoaded || ratingCountState.isLoaded || favoriteState.isLoaded else { return }

        if retainForDownload {
            try applyDownloadedDynamicSnapshot(DownloadedGalleryDynamicSnapshot(
                key: summary.key,
                rating: summary.rating,
                ratingCount: summary.ratingCount,
                favoriteCategory: summary.favoriteCategory,
                capturedAt: capturedAt,
                completeness: GalleryMetadataCompleteness(
                    rating: ratingState,
                    ratingCount: ratingCountState,
                    favorite: favoriteState,
                    comments: .notLoaded
                )
            ))
            return
        }

        let fallback = GallerySummary(key: summary.key, title: summary.title)
        let record = try record(for: summary.key, creatingFrom: fallback)
        if retainForDownload {
            record.downloadRetention = true
        }

        if let existing = record.dynamicSnapshot {
            var merged = existing.snapshot
            let incomingIsNewer = capturedAt >= merged.capturedAt
            if ratingState.isLoaded,
               merged.completeness.rating.isLoaded == false || incomingIsNewer {
                merged.rating = summary.rating
                merged.completeness.rating = ratingState
            }
            if ratingCountState.isLoaded,
               merged.completeness.ratingCount.isLoaded == false || incomingIsNewer {
                merged.ratingCount = summary.ratingCount
                merged.completeness.ratingCount = ratingCountState
            }
            if favoriteState == .loadedEmpty, incomingIsNewer {
                merged.favoriteCount = nil
                merged.favoriteName = nil
                merged.favoriteCategory = nil
                merged.completeness.favorite = .loadedEmpty
            } else if favoriteState.isLoaded,
                      summary.favoriteCategory != nil,
                      incomingIsNewer {
                // A GallerySummary contains only the favorite category. Do
                // not let this summary-only projection erase the detail-only
                // favorite count, name or comments already in persistence.
                merged.favoriteCategory = summary.favoriteCategory
                if merged.favoriteCount == nil, merged.favoriteName == nil {
                    merged.completeness.favorite = favoriteState
                }
            }
            merged.capturedAt = max(merged.capturedAt, capturedAt)
            existing.update(from: merged)
            record.applyDynamicCompatibilityFields(from: merged)
        } else {
            let dynamic = DownloadedGalleryDynamicSnapshot(
                key: summary.key,
                rating: summary.rating,
                ratingCount: summary.ratingCount,
                favoriteCategory: summary.favoriteCategory,
                capturedAt: capturedAt,
                completeness: GalleryMetadataCompleteness(
                    rating: ratingState,
                    ratingCount: ratingCountState,
                    favorite: favoriteState,
                    comments: .notLoaded
                )
            )
            let dynamicRecord = DownloadedGalleryDynamicRecord(snapshot: dynamic)
            dynamicRecord.gallery = record
            record.dynamicSnapshot = dynamicRecord
            modelContext.insert(dynamicRecord)
            record.applyDynamicCompatibilityFields(from: dynamic)
        }
    }

    public func downloadedDynamicSnapshot(for key: GalleryKey) throws -> DownloadedGalleryDynamicSnapshot? {
        guard let record = try downloadedMetadataRecord(for: key) else { return nil }
        return try decodeDynamic(from: record)
    }

    public func galleryTransferRecords(for keys: Set<GalleryKey>) throws -> [GalleryTransferRecord] {
        guard keys.isEmpty == false else { return [] }
        var transfers: [GalleryTransferRecord] = []
        transfers.reserveCapacity(keys.count)
        for key in keys {
            guard let record = try downloadedMetadataRecord(for: key) else { continue }
            let stable = try decodeStable(from: record)
            transfers.append(try GalleryTransferRecord(
                stable: stable,
                dynamic: try decodeDynamic(from: record),
                exportedAt: Date(),
                sourceSite: stable.sourceSite
            ))
        }
        return transfers
    }

    /// Returns only galleries retained by a download job. Ordinary gallery
    /// cache records are deliberately excluded from device synchronization.
    public func downloadedGalleryTransferRecords() throws -> [GalleryTransferRecord] {
        return try modelContext.fetch(FetchDescriptor<DownloadedGalleryMetadataRecord>()).compactMap { record in
            let stable = try decodeStable(from: record)
            return try GalleryTransferRecord(
                stable: stable,
                dynamic: try decodeDynamic(from: record),
                exportedAt: Date(),
                sourceSite: stable.sourceSite
            )
        }.sorted { $0.stable.key.id < $1.stable.key.id }
    }

    /// Merges metadata received from another device through the existing
    /// field-level snapshot merger. This does not alter reading progress,
    /// favorites or any account-scoped state.
    public func mergeDeviceSyncMetadata(_ transfer: GalleryTransferRecord) async throws {
        try applyStableSnapshot(transfer.stable, retainForDownload: true)
        if let dynamic = transfer.dynamic {
            try applyDownloadedDynamicSnapshot(dynamic)
        }
        try modelContext.save()
        await flushDeviceSyncIndex()
    }

    /// Creates the minimum download-job/page rows needed for received media.
    /// Existing completed rows are preserved, so a reconnect or a concurrent
    /// local download cannot turn a completed page back into a queued page.
    public func prepareDeviceSyncDownload(
        _ transfer: GalleryTransferRecord,
        pageIndexes: Set<Int>
    ) async throws {
        _ = try applyDeviceSyncDownload(transfer, pageIndexes: pageIndexes)
        try modelContext.save()
        await flushDeviceSyncIndex()
    }

    /// Atomically merges a gallery's metadata, creates any required download
    /// rows, and marks the validated pages complete in one SwiftData save.
    /// Callers commit the corresponding files before invoking this method.
    public func commitDeviceSyncGallery(
        _ transfer: GalleryTransferRecord,
        completedPages: [Int: Int64],
        flushIndex: Bool = true
    ) async throws {
        do {
            let job = try applyDeviceSyncDownload(
                transfer,
                pageIndexes: Set(completedPages.keys)
            )
            let pagesByIndex = Dictionary(uniqueKeysWithValues: job.pages.map { ($0.pageIndex, $0) })
            for (pageIndex, byteCount) in completedPages {
                guard let page = pagesByIndex[pageIndex] else { continue }
                page.stateRaw = "completed"
                page.bytes = byteCount
                page.backgroundTaskIdentifier = nil
            }
            job.completedPages = job.pages.filter { $0.stateRaw == "completed" }.count
            if job.totalPages > 0, job.completedPages >= job.totalPages {
                job.stateRaw = "completed"
                job.errorMessage = nil
            } else if job.stateRaw == "completed" {
                job.stateRaw = "paused"
            }
            job.updatedAt = Date()
            try modelContext.save()
            if flushIndex {
                await flushDeviceSyncIndex()
            }
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func applyDeviceSyncDownload(
        _ transfer: GalleryTransferRecord,
        pageIndexes: Set<Int>
    ) throws -> DownloadJobRecord {
        try applyStableSnapshot(transfer.stable, retainForDownload: true)
        if let dynamic = transfer.dynamic {
            try applyDownloadedDynamicSnapshot(dynamic)
        }

        let key = transfer.stable.key
        var descriptor = FetchDescriptor<DownloadJobRecord>(predicate: #Predicate {
            $0.gid == key.gid && $0.token == key.token
        })
        descriptor.fetchLimit = 1
        let job: DownloadJobRecord
        if let existing = try modelContext.fetch(descriptor).first {
            job = existing
        } else {
            job = DownloadJobRecord(
                key: key,
                title: transfer.stable.title,
                japaneseTitle: transfer.stable.japaneseTitle,
                totalPages: transfer.stable.pageCount ?? pageIndexes.count
            )
            modelContext.insert(job)
        }

        let descriptorsByIndex = Dictionary(uniqueKeysWithValues: transfer.stable.pages.map { ($0.index, $0) })
        var pagesByIndex = Dictionary(uniqueKeysWithValues: job.pages.map { ($0.pageIndex, $0) })
        let allIndexes = Set(pagesByIndex.keys)
            .union(descriptorsByIndex.keys)
            .union(pageIndexes)
        for index in allIndexes.sorted() {
            let page: DownloadPageRecord
            if let existing = pagesByIndex[index] {
                page = existing
            } else {
                page = DownloadPageRecord(pageIndex: index, fileName: "page-\(index + 1).bin")
                page.job = job
                job.pages.append(page)
                modelContext.insert(page)
                pagesByIndex[index] = page
            }
            if let source = descriptorsByIndex[index] {
                page.directURLString = source.pageURL.absoluteString
                page.previewURLString = source.previewURL?.absoluteString
            } else if page.directURLString == nil {
                page.directURLString = "ehviewer-sync://\(key.id)/page/\(index)"
            }
            if page.stateRaw != "completed" {
                page.stateRaw = "queued"
            }
        }
        job.title = transfer.stable.title
        job.japaneseTitle = transfer.stable.japaneseTitle
        job.totalPages = max(transfer.stable.pageCount ?? 0, job.pages.count)
        job.completedPages = job.pages.filter { $0.stateRaw == "completed" }.count
        if job.stateRaw == "completed" && job.completedPages < job.totalPages {
            job.stateRaw = "queued"
        }
        job.updatedAt = Date()
        return job
    }

    public func promoteToDownloadedGallery(
        stable: StableGalleryMetadataSnapshot,
        dynamic: DownloadedGalleryDynamicSnapshot? = nil
    ) async throws {
        try applyDownloadedStableSnapshot(stable)
        if let dynamic {
            try applyDownloadedDynamicSnapshot(dynamic)
        }
        try modelContext.save()
        await flushDeviceSyncIndex()
    }

    /// Removes all ordinary browsing metadata and media indexes. Downloaded
    /// metadata lives in a separate model and is therefore unaffected.
    public func clearOrdinaryCache() throws {
        let records = try modelContext.fetch(FetchDescriptor<GalleryRecord>())
        var didChange = false
        for record in records where record.cacheRetention {
            if let stable = record.stableMetadata {
                modelContext.delete(stable)
                record.stableMetadata = nil
            }
            if let dynamic = record.dynamicSnapshot {
                modelContext.delete(dynamic)
                record.dynamicSnapshot = nil
            }
            record.cacheRetention = false
            record.title = ""
            record.japaneseTitle = nil
            record.thumbnailURLString = nil
            record.category = nil
            record.pageCount = nil
            record.postedAt = nil
            record.rating = nil
            record.ratingCount = nil
            record.favoriteCategory = nil
            record.uploader = nil
            record.tags = []
            record.metadataTitleComplete = false
            record.metadataJapaneseTitleComplete = false
            record.metadataTagsComplete = false
            didChange = true
        }
        let imageRecords = try modelContext.fetch(FetchDescriptor<GalleryImageIndexRecord>())
        for image in imageRecords {
            modelContext.delete(image)
        }
        if didChange || imageRecords.isEmpty == false {
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

    private func downloadedMetadataRecords(
        for key: GalleryKey
    ) throws -> [DownloadedGalleryMetadataRecord] {
        try modelContext.fetch(FetchDescriptor<DownloadedGalleryMetadataRecord>(predicate: #Predicate {
            $0.gid == key.gid && $0.token == key.token
        }))
    }

    private func downloadedMetadataRecord(
        for key: GalleryKey
    ) throws -> DownloadedGalleryMetadataRecord? {
        var descriptor = FetchDescriptor<DownloadedGalleryMetadataRecord>(predicate: #Predicate {
            $0.gid == key.gid && $0.token == key.token
        })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    @discardableResult
    private func insertDownloadedMetadata(
        stable: StableGalleryMetadataSnapshot,
        dynamic: DownloadedGalleryDynamicSnapshot?
    ) throws -> DownloadedGalleryMetadataRecord {
        let record = DownloadedGalleryMetadataRecord(
            key: stable.key,
            stableData: try JSONEncoder().encode(stable),
            dynamicData: try dynamic.map { try JSONEncoder().encode($0) }
        )
        modelContext.insert(record)
        return record
    }

    private func applyDownloadedStableSnapshot(
        _ snapshot: StableGalleryMetadataSnapshot,
        accumulatingPages: Bool = false
    ) throws {
        if let record = try downloadedMetadataRecord(for: snapshot.key) {
            let existing = try decodeStable(from: record)
            var merged = GallerySnapshotMerger.merge(
                existing: existing,
                incoming: snapshot
            )
            if accumulatingPages {
                let pagesByIndex = Dictionary((existing.pages + snapshot.pages).map { ($0.index, $0) }, uniquingKeysWith: { first, _ in first })
                merged.pages = pagesByIndex.values.sorted { $0.index < $1.index }
                if merged.pages.isEmpty == false { merged.completeness.pages = .loadedWithValue }
            }
            record.stableData = try JSONEncoder().encode(merged)
            record.updatedAt = Date()
        } else {
            try insertDownloadedMetadata(stable: snapshot, dynamic: nil)
        }
        pendingDeviceSyncMetadataKeys.insert(snapshot.key)
        pendingDeviceSyncMetadataRemovals.remove(snapshot.key)
    }

    private func decodeStable(
        from record: DownloadedGalleryMetadataRecord
    ) throws -> StableGalleryMetadataSnapshot {
        try JSONDecoder().decode(StableGalleryMetadataSnapshot.self, from: record.stableData)
    }

    private func decodeDynamic(
        from record: DownloadedGalleryMetadataRecord
    ) throws -> DownloadedGalleryDynamicSnapshot? {
        guard let data = record.dynamicData else { return nil }
        return try JSONDecoder().decode(DownloadedGalleryDynamicSnapshot.self, from: data)
    }

    private func downloadedSummary(
        from record: DownloadedGalleryMetadataRecord
    ) throws -> GallerySummary {
        let decoder = JSONDecoder()
        let stable = try decoder.decode(DownloadedGallerySummaryProjection.self, from: record.stableData)
        var summary = stable.summary
        var completeness = stable.completeness
        if let data = record.dynamicData {
            let dynamic = try decoder.decode(DownloadedGallerySummaryDynamicProjection.self, from: data)
            summary.rating = dynamic.rating
            summary.ratingCount = dynamic.ratingCount
            summary.favoriteCategory = dynamic.favoriteCategory
            completeness.rating = dynamic.completeness.rating
            completeness.ratingCount = dynamic.completeness.ratingCount
            completeness.favorite = dynamic.completeness.favorite
            completeness.comments = dynamic.completeness.comments
        }
        summary.metadataCompleteness = completeness
        return summary
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

    public func updateReadingProgress(
        for key: GalleryKey,
        page: Int,
        fallbackSummary: GallerySummary? = nil
    ) throws {
        var descriptor = FetchDescriptor<GalleryRecord>(predicate: #Predicate {
            $0.gid == key.gid && $0.token == key.token
        })
        descriptor.fetchLimit = 1
        let record: GalleryRecord
        if let existing = try modelContext.fetch(descriptor).first {
            record = existing
        } else {
            let summaryFromDownload = try downloadedMetadataRecord(for: key)
                .flatMap { try? downloadedSummary(from: $0) }
            guard let summary = fallbackSummary ?? summaryFromDownload else { return }
            record = GalleryRecord(snapshot: summary)
            modelContext.insert(record)
        }
        record.lastReadPage = page
        record.lastReadAt = Date()
        try modelContext.save()
    }

    public func readingPage(for key: GalleryKey) throws -> Int? {
        var descriptor = FetchDescriptor<GalleryRecord>(predicate: #Predicate {
            $0.gid == key.gid && $0.token == key.token
        })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.lastReadPage
    }

    public func readingPages(for keys: Set<GalleryKey>) throws -> [GalleryKey: Int] {
        guard keys.isEmpty == false else { return [:] }
        let gids = keys.map(\.gid)
        let descriptor = FetchDescriptor<GalleryRecord>(predicate: #Predicate {
            gids.contains($0.gid)
        })
        return Dictionary(
            try modelContext.fetch(descriptor).filter { keys.contains($0.key) }.map { ($0.key, $0.lastReadPage) },
            uniquingKeysWith: { first, _ in first }
        )
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

    public func removeFromHistory(for keys: Set<GalleryKey>) throws {
        guard keys.isEmpty == false else { return }
        let records = try modelContext.fetch(FetchDescriptor<GalleryRecord>())
        var didChange = false
        for record in records where keys.contains(record.key) {
            guard record.lastReadAt != nil || record.lastReadPage != 0 else { continue }
            record.lastReadPage = 0
            record.lastReadAt = nil
            didChange = true
        }
        if didChange { try modelContext.save() }
    }

    public func removeFromFavorites(for keys: Set<GalleryKey>) throws {
        guard keys.isEmpty == false else { return }
        let records = try modelContext.fetch(FetchDescriptor<GalleryRecord>())
        var didChange = false
        for record in records where keys.contains(record.key) && record.isFavorite {
            record.isFavorite = false
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
        guard limit > 0 else { return [] }
        var descriptor = FetchDescriptor<GalleryRecord>(
            predicate: #Predicate { $0.lastReadAt != nil },
            sortBy: [SortDescriptor(\.lastReadAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map { record in
            var summary = record.summary
            summary.postedAt = record.lastReadAt
            return summary
        }
    }

    public func favorites(limit: Int = 50) throws -> [GallerySummary] {
        guard limit > 0 else { return [] }
        var descriptor = FetchDescriptor<GalleryRecord>(
            predicate: #Predicate { $0.isFavorite },
            sortBy: [SortDescriptor(\.title)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map(\.summary)
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
        tags: [String] = [],
        pages: [GalleryPageDescriptor],
        totalPageCount: Int? = nil,
        completedPageIndexes: Set<Int>,
        stateRaw: String,
        errorMessage: String?,
        label: String? = nil
    ) async throws {
        let job = PersistedDownload(
            key: key,
            title: title,
            japaneseTitle: japaneseTitle,
            tags: tags,
            pages: pages,
            totalPageCount: totalPageCount,
            label: label,
            completedPageIndexes: completedPageIndexes,
            stateRaw: stateRaw,
            errorMessage: errorMessage
        )
        try applyDownload(job)
        try modelContext.save()
        await flushDeviceSyncIndex()
    }

    /// Applies several download state changes in one SwiftData transaction.
    /// Startup reconciliation can touch hundreds of jobs; saving each job
    /// independently makes the store repeatedly rebuild the same indexes and
    /// flush the device-sync metadata queue.
    public func upsertDownloads(_ jobs: [PersistedDownload]) async throws {
        guard jobs.isEmpty == false else { return }
        for job in jobs {
            try applyDownload(job)
        }
        try modelContext.save()
        await flushDeviceSyncIndex()
    }

    private func applyDownload(_ job: PersistedDownload) throws {
        let key = job.key
        let title = job.title
        let japaneseTitle = job.japaneseTitle
        let tags = job.tags
        let pages = job.pages
        let completedPageIndexes = job.completedPageIndexes
        let stateRaw = job.stateRaw
        let errorMessage = job.errorMessage
        let label = job.label
        var completeness = GalleryMetadataCompleteness()
        completeness.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .loadedEmpty
            : .loadedWithValue
        completeness.japaneseTitle = japaneseTitle == nil ? .notLoaded : .loadedWithValue
        completeness.tags = tags.isEmpty ? .notLoaded : .loadedWithValue
        completeness.pageCount = pages.isEmpty ? .notLoaded : .loadedWithValue
        completeness.pages = pages.isEmpty ? .notLoaded : .loadedWithValue
        try applyDownloadedStableSnapshot(StableGalleryMetadataSnapshot(
            key: key,
            sourceSite: .eHentai,
            title: title,
            japaneseTitle: japaneseTitle,
            tags: tags,
            pageCount: job.totalPageCount > 0 ? job.totalPageCount : nil,
            pages: pages,
            capturedAt: .distantPast,
            completeness: completeness
        ), accumulatingPages: true)
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
        record.totalPages = job.totalPageCount
        record.completedPages = completedPageIndexes.count
        record.stateRaw = stateRaw
        record.errorMessage = errorMessage
        record.label = label
        record.updatedAt = Date()

        let recordsByIndex = Dictionary(record.pages.map { ($0.pageIndex, $0) }, uniquingKeysWith: { first, _ in first })
        for page in pages {
            let pageRecord: DownloadPageRecord
            if let existing = recordsByIndex[page.index] {
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
    }

    public func downloadJobs(includeTags: Bool = true) async throws -> [PersistedDownload] {
        var descriptor = FetchDescriptor<DownloadJobRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.pages]
        let records = try modelContext.fetch(descriptor)
        let summariesByKey: [GalleryKey: GallerySummary]
        if includeTags {
            let metadataRecords = try modelContext.fetch(FetchDescriptor<DownloadedGalleryMetadataRecord>())
            summariesByKey = Dictionary(
                metadataRecords.compactMap { record in
                    (try? downloadedSummary(from: record)).map { (record.key, $0) }
                },
                uniquingKeysWith: { first, _ in first }
            )
        } else {
            summariesByKey = [:]
        }
        var result: [PersistedDownload] = []
        result.reserveCapacity(records.count)
        for (offset, record) in records.enumerated() {
            try Task.checkCancellation()
            if offset.isMultiple(of: 32) { await Task.yield() }
            guard record.modelContext != nil else { continue }
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
            result.append(PersistedDownload(
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
            ))
        }
        return result
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

    public func markDownloadPageCompleted(for key: GalleryKey, pageIndex: Int, bytes: Int64? = nil) throws {
        var descriptor = FetchDescriptor<DownloadJobRecord>(predicate: #Predicate {
            $0.gid == key.gid && $0.token == key.token
        })
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first,
              let page = record.pages.first(where: { $0.pageIndex == pageIndex }) else { return }
        if page.stateRaw == "completed", page.backgroundTaskIdentifier == nil,
           bytes == nil || bytes == page.bytes { return }
        let wasCompleted = page.stateRaw == "completed"
        page.stateRaw = "completed"
        if let bytes { page.bytes = bytes }
        page.backgroundTaskIdentifier = nil
        if !wasCompleted { record.completedPages += 1 }
        if record.stateRaw != "cancelled", record.totalPages > 0, record.completedPages >= record.totalPages {
            record.stateRaw = "completed"
            record.errorMessage = nil
        } else if record.stateRaw == "completed" {
            record.stateRaw = "paused"
        }
        record.updatedAt = Date()
        try modelContext.save()
    }

    public func deleteDownload(for key: GalleryKey) async throws {
        let descriptor = FetchDescriptor<DownloadJobRecord>(predicate: #Predicate {
            $0.gid == key.gid && $0.token == key.token
        })
        let downloadRecords = try modelContext.fetch(descriptor)
        for downloadRecord in downloadRecords {
            modelContext.delete(downloadRecord)
        }

        let metadataRecords = try downloadedMetadataRecords(for: key)
        for metadata in metadataRecords {
            modelContext.delete(metadata)
        }
        if downloadRecords.isEmpty == false || metadataRecords.isEmpty == false {
            try modelContext.save()
            pendingDeviceSyncMetadataRemovals.insert(key)
            await flushDeviceSyncIndex()
        }
    }

    /// Removes several download records in one SwiftData transaction. The
    /// coordinator deletes media files separately so file work can report
    /// progress without holding this context open between every item.
    public func deleteDownloads(for keys: Set<GalleryKey>) async throws {
        guard keys.isEmpty == false else { return }

        let downloadRecords = try modelContext.fetch(FetchDescriptor<DownloadJobRecord>())
        let metadataRecords = try modelContext.fetch(FetchDescriptor<DownloadedGalleryMetadataRecord>())
        var didChange = false

        for downloadRecord in downloadRecords where keys.contains(downloadRecord.key) {
            modelContext.delete(downloadRecord)
            didChange = true
        }

        for metadata in metadataRecords where keys.contains(metadata.key) {
            modelContext.delete(metadata)
            didChange = true
        }

        if didChange {
            try modelContext.save()
            pendingDeviceSyncMetadataRemovals.formUnion(keys)
            await flushDeviceSyncIndex()
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

    /// Replaces one locale's reference database in a single save after a
    /// validated database update. Existing user-facing translations for other
    /// locales remain untouched.
    public func replaceTagTranslations(_ entries: [(tag: String, localizedText: String)], locale: String) throws {
        let normalizedLocale = locale.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedLocale.isEmpty == false else { return }

        let existing = try modelContext.fetch(
            FetchDescriptor<TagTranslationRecord>(predicate: #Predicate { $0.locale == normalizedLocale })
        )
        for record in existing {
            modelContext.delete(record)
        }
        for (rawTag, rawText) in entries {
            let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard tag.isEmpty == false, text.isEmpty == false else { continue }
            modelContext.insert(
                TagTranslationRecord(tag: tag, locale: normalizedLocale, localizedText: text)
            )
        }
        try modelContext.save()
    }

    public func gallerySyncSummaries(for keys: Set<GalleryKey>) throws -> [GallerySummary] {
        guard keys.isEmpty == false else { return [] }
        return try modelContext.fetch(FetchDescriptor<GalleryRecord>())
            .map(\.summary)
            .filter { keys.contains($0.key) }
            .sorted { $0.key.id < $1.key.id }
    }

    /// Reads only requested entries from the separate downloaded-metadata
    /// table. Fetch only requested galleries and decode card fields without
    /// constructing their page tables or comments.
    public func localGallerySummaries(for keys: Set<GalleryKey>) throws -> [GallerySummary] {
        guard keys.isEmpty == false else { return [] }
        let gids = keys.map(\.gid)
        let descriptor = FetchDescriptor<DownloadedGalleryMetadataRecord>(predicate: #Predicate {
            gids.contains($0.gid)
        })
        return try modelContext.fetch(descriptor)
            .compactMap { record in
                guard keys.contains(record.key) else { return nil }
                return try downloadedSummary(from: record)
            }
            .sorted { $0.key.id < $1.key.id }
    }

    public func downloadedGallerySummary(for key: GalleryKey) throws -> GallerySummary? {
        guard let record = try downloadedMetadataRecord(for: key) else { return nil }
        return try downloadedSummary(from: record)
    }

    public func downloadedGallerySummaries(for keys: Set<GalleryKey>) throws -> [GallerySummary] {
        try localGallerySummaries(for: keys)
    }

    public func downloadedTransferRecord(for key: GalleryKey) throws -> GalleryTransferRecord? {
        guard let record = try downloadedMetadataRecord(for: key) else { return nil }
        let stable = try decodeStable(from: record)
        return try GalleryTransferRecord(
            stable: stable,
            dynamic: try decodeDynamic(from: record),
            exportedAt: Date(),
            sourceSite: stable.sourceSite
        )
    }

    /// Imports summary-only metadata directly into the local download library.
    /// It never creates or mutates an ordinary browsing-cache record.
    public func mergeDownloadedGallerySyncSummaries(
        _ summaries: [GallerySummary]
    ) async throws -> GallerySyncImportOutcome {
        var uniqueSummaries: [GallerySummary] = []
        var incomingKeys = Set<GalleryKey>()
        for summary in summaries where incomingKeys.insert(summary.key).inserted {
            uniqueSummaries.append(summary)
        }
        let existingKeys = Set(try modelContext.fetch(
            FetchDescriptor<DownloadedGalleryMetadataRecord>()
        ).map(\.key))
        for summary in uniqueSummaries {
            try applyDownloadedStableSnapshot(
                StableGalleryMetadataSnapshot(summary: summary, sourceSite: .eHentai)
            )
            try applyDynamicSnapshotIfPresent(
                from: summary,
                capturedAt: Date(),
                retainForDownload: true
            )
        }
        try modelContext.save()
        await flushDeviceSyncIndex()
        let insertedCount = uniqueSummaries.filter { existingKeys.contains($0.key) == false }.count
        return GallerySyncImportOutcome(
            sourceCount: summaries.count,
            duplicateInFileCount: summaries.count - uniqueSummaries.count,
            existingCount: uniqueSummaries.count - insertedCount,
            insertedCount: insertedCount
        )
    }

    /// Inserts only galleries that do not already exist locally. Existing
    /// records are intentionally untouched, including their metadata and all
    /// local state.
    public func insertMissingGallerySyncSummaries(
        _ summaries: [GallerySummary]
    ) async throws -> GallerySyncImportOutcome {
        var uniqueSummaries: [GallerySummary] = []
        var incomingKeys = Set<GalleryKey>()
        uniqueSummaries.reserveCapacity(summaries.count)
        for summary in summaries where incomingKeys.insert(summary.key).inserted {
            uniqueSummaries.append(summary)
        }

        let existingKeys = Set(try modelContext.fetch(FetchDescriptor<GalleryRecord>()).map(\.key))
        let missing = uniqueSummaries.filter { existingKeys.contains($0.key) == false }
        for summary in missing {
            try await upsertStableSnapshot(
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
    ) async throws -> GallerySyncImportOutcome {
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
            try await upsertStableSnapshot(
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
            if let dynamicSnapshot {
                var completeness = value.metadataCompleteness ?? GalleryMetadataCompleteness()
                let ratingState = GalleryFieldState(rawValue: dynamicSnapshot.ratingStateRaw) ?? .notLoaded
                let ratingCountState = GalleryFieldState(rawValue: dynamicSnapshot.ratingCountStateRaw) ?? .notLoaded
                let favoriteState = GalleryFieldState(rawValue: dynamicSnapshot.favoriteStateRaw) ?? .notLoaded
                if ratingState != .notLoaded {
                    value.rating = dynamicSnapshot.rating
                    completeness.rating = ratingState
                }
                if ratingCountState != .notLoaded {
                    value.ratingCount = dynamicSnapshot.ratingCount
                    completeness.ratingCount = ratingCountState
                }
                if favoriteState != .notLoaded {
                    value.favoriteCategory = dynamicSnapshot.favoriteCategory
                    completeness.favorite = favoriteState
                }
                value.metadataCompleteness = completeness
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

private func summaryOptionalState<T>(
    explicit: GalleryFieldState?,
    value: T?
) -> GalleryFieldState {
    if let explicit, explicit == .notLoaded {
        return .notLoaded
    }
    if value != nil {
        return explicit?.isLoaded == true ? explicit! : .loadedWithValue
    }
    return explicit?.isLoaded == true ? .loadedEmpty : .notLoaded
}

private func summaryFavoriteState(
    explicit: GalleryFieldState?,
    value: Int?
) -> GalleryFieldState {
    if value != nil {
        return explicit?.isLoaded == true ? explicit! : .loadedWithValue
    }
    return explicit == .loadedEmpty ? .loadedEmpty : .notLoaded
}
