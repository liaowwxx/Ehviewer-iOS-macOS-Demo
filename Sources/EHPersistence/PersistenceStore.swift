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

        public static let models: [any PersistentModel.Type] = [
            GalleryRecord.self,
            DownloadJobRecord.self,
            DownloadPageRecord.self,
            DownloadLabelRecord.self,
            QuickSearchRecord.self,
            FilterRuleRecord.self,
            TagTranslationRecord.self
        ]
    }

    public enum MigrationPlan: SchemaMigrationPlan {
        public static let schemas: [any VersionedSchema.Type] = [SchemaV1.self, SchemaV2.self]
        public static let stages: [MigrationStage] = [
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)
        ]
    }

    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(
            for: Schema(SchemaV2.models),
            migrationPlan: MigrationPlan.self,
            configurations: configuration
        )
    }
}

@ModelActor
public actor PersistenceStore {
    public func upsert(_ snapshots: [GallerySummary]) throws {
        for snapshot in snapshots {
            let gid = snapshot.key.gid
            let token = snapshot.key.token
            var descriptor = FetchDescriptor<GalleryRecord>(predicate: #Predicate {
                $0.gid == gid && $0.token == token
            })
            descriptor.fetchLimit = 1
            if let existing = try modelContext.fetch(descriptor).first {
                existing.update(from: snapshot)
            } else {
                modelContext.insert(GalleryRecord(snapshot: snapshot))
            }
        }
        try modelContext.save()
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
        if let record = try modelContext.fetch(descriptor).first {
            modelContext.delete(record)
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
            modelContext.insert(GalleryRecord(snapshot: summary))
        }
        if missing.isEmpty == false {
            try modelContext.save()
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
        let recordsByKey = Dictionary(uniqueKeysWithValues: records.map { ($0.key, $0) })
        var insertedCount = 0
        for summary in uniqueSummaries {
            if let record = recordsByKey[summary.key] {
                record.update(from: summary)
            } else {
                modelContext.insert(GalleryRecord(snapshot: summary))
                insertedCount += 1
            }
        }
        if uniqueSummaries.isEmpty == false {
            try modelContext.save()
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
        GallerySummary(
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
                title: metadataTitleComplete,
                japaneseTitle: metadataJapaneseTitleComplete,
                tags: metadataTagsComplete
            )
        )
    }
}
