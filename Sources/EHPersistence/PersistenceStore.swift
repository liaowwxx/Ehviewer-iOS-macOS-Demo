import Foundation
import SwiftData
import EHDomain

public struct PersistedDownload: Hashable, Sendable {
    public let key: GalleryKey
    public let title: String
    public let pages: [GalleryPageDescriptor]
    public let label: String?
    public let completedPageIndexes: Set<Int>
    public let stateRaw: String
    public let errorMessage: String?
    public let inFlightPageIndexes: Set<Int>

    public init(
        key: GalleryKey,
        title: String,
        pages: [GalleryPageDescriptor],
        label: String? = nil,
        completedPageIndexes: Set<Int>,
        stateRaw: String,
        errorMessage: String?,
        inFlightPageIndexes: Set<Int> = []
    ) {
        self.key = key
        self.title = title
        self.pages = pages
        self.label = label
        self.completedPageIndexes = completedPageIndexes
        self.stateRaw = stateRaw
        self.errorMessage = errorMessage
        self.inFlightPageIndexes = inFlightPageIndexes
    }
}

public struct FilterRuleSnapshot: Hashable, Sendable {
    public let pattern: String
    public let isEnabled: Bool

    public init(pattern: String, isEnabled: Bool) {
        self.pattern = pattern
        self.isEnabled = isEnabled
    }
}

public enum ModelContainerFactory {
    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            GalleryRecord.self,
            DownloadJobRecord.self,
            DownloadPageRecord.self,
            DownloadLabelRecord.self,
            QuickSearchRecord.self,
            FilterRuleRecord.self,
            TagTranslationRecord.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: configuration)
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

    public func upsertDownload(
        key: GalleryKey,
        title: String,
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
            record = DownloadJobRecord(key: key, title: title, totalPages: pages.count)
            modelContext.insert(record)
        }
        record.title = title
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
        let records = try modelContext.fetch(FetchDescriptor<DownloadJobRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
        return records.map { record in
            let pages = record.pages.compactMap { page -> GalleryPageDescriptor? in
                guard let directURLString = page.directURLString, let pageURL = URL(string: directURLString) else { return nil }
                return GalleryPageDescriptor(
                    galleryKey: record.key,
                    index: page.pageIndex,
                    pageURL: pageURL,
                    previewURL: page.previewURLString.flatMap(URL.init(string:))
                )
            }.sorted { $0.index < $1.index }
            let completed = Set(record.pages.filter { $0.stateRaw == "completed" }.map(\.pageIndex))
            let inFlight = Set(record.pages.compactMap { page in
                page.backgroundTaskIdentifier == nil ? nil : page.pageIndex
            })
            return PersistedDownload(
                key: record.key,
                title: record.title,
                pages: pages,
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
            FilterRuleSnapshot(pattern: $0.pattern, isEnabled: $0.isEnabled)
        }
    }

    public func setFilterRule(pattern: String, isEnabled: Bool) throws {
        var descriptor = FetchDescriptor<FilterRuleRecord>(predicate: #Predicate {
            $0.pattern == pattern
        })
        descriptor.fetchLimit = 1
        if let record = try modelContext.fetch(descriptor).first {
            record.isEnabled = isEnabled
        } else {
            modelContext.insert(FilterRuleRecord(pattern: pattern, isEnabled: isEnabled))
        }
        try modelContext.save()
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
}

private extension GalleryRecord {
    var summary: GallerySummary {
        GallerySummary(
            key: key,
            title: title,
            secondaryTitle: secondaryTitle,
            thumbnailURL: thumbnailURL,
            category: category,
            pageCount: pageCount,
            postedAt: postedAt,
            rating: rating,
            ratingCount: ratingCount,
            favoriteCategory: favoriteCategory,
            tags: tags
        )
    }
}
