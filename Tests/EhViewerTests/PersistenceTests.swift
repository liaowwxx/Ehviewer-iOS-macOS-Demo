import Foundation
import Testing
import EHDomain
import EHPersistence

struct PersistenceTests {
    @Test("SwiftData upsert keeps one gallery record and stores reading progress")
    func upsertAndProgress() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = PersistenceStore(modelContainer: container)
        let summary = GallerySummary(key: GalleryKey(gid: 7, token: "token"), title: "Persistent sample", pageCount: 8)

        try await store.upsert([summary])
        try await store.upsert([summary])
        try await store.updateReadingProgress(for: summary.key, page: 4)

        let recent = try await store.recent()
        #expect(recent.count == 1)
        #expect(recent.first?.key == summary.key)
        #expect(recent.first?.postedAt != nil)
    }

    @Test("SwiftData persists resumable download pages and completion state")
    func downloadRoundTrip() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = PersistenceStore(modelContainer: container)
        let key = GalleryKey(gid: 8, token: "download")
        let pages = (0..<3).map { index in
            GalleryPageDescriptor(
                galleryKey: key,
                index: index,
                pageURL: URL(string: "https://example.invalid/page/\(index)")!,
                previewURL: URL(string: "https://example.invalid/preview/\(index).jpg")!
            )
        }

        try await store.upsertDownload(
            key: key,
            title: "Resumable",
            pages: pages,
            completedPageIndexes: [0, 2],
            stateRaw: "paused",
            errorMessage: "磁盘空间不足"
        )
        try await store.setBackgroundTaskIdentifier(42, for: key, pageIndex: 1)
        let restored = try await store.downloadJobs()
        #expect(restored.count == 1)
        #expect(restored.first?.pages.map(\.index) == [0, 1, 2])
        #expect(restored.first?.totalPageCount == 3)
        #expect(restored.first?.pages.first?.previewURL?.absoluteString == "https://example.invalid/preview/0.jpg")
        #expect(restored.first?.completedPageIndexes == [0, 2])
        #expect(restored.first?.stateRaw == "paused")
        #expect(restored.first?.errorMessage == "磁盘空间不足")
        #expect(restored.first?.inFlightPageIndexes == [1])
        #expect((restored.first?.createdAt.timeIntervalSinceNow ?? 1) <= 0)

        try await store.deleteDownload(for: key)
        #expect(try await store.downloadJobs().isEmpty)
    }

    @Test("SwiftData keeps recent quick searches and filter rules as values")
    func quickSearchAndFilters() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = PersistenceStore(modelContainer: container)
        try await store.recordQuickSearch("  cats  ")
        try await store.recordQuickSearch("dogs")
        try await store.recordQuickSearch("catgirl")
        try await store.setFilterRule(pattern: "spoiler", isEnabled: true)

        #expect(Set(try await store.quickSearches()) == ["dogs", "cats", "catgirl"])
        #expect(Set(try await store.quickSearchSuggestions(prefix: "cat")) == ["cats", "catgirl"])
        try await store.deleteQuickSearch("cats")
        #expect(try await store.quickSearchSuggestions(prefix: "cat") == ["catgirl"])
        #expect(try await store.filterRules().first?.pattern == "spoiler")
    }

    @Test("SwiftData stores tag translations by locale")
    func tagTranslations() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = PersistenceStore(modelContainer: container)
        try await store.saveTagTranslation(tag: "language:english", locale: "zh-Hans", localizedText: "语言：英语")
        try await store.saveTagTranslation(tag: "language:english", locale: "ja", localizedText: "言語：英語")
        #expect(try await store.tagTranslations(locale: "zh-Hans")["language:english"] == "语言：英语")
        #expect(try await store.tagTranslations(locale: "ja")["language:english"] == "言語：英語")
    }

    @Test("Gallery sync only inserts missing summaries and preserves local state")
    func gallerySyncInsertOnly() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = PersistenceStore(modelContainer: container)
        let existingKey = GalleryKey(gid: 90, token: "existing")
        let existing = GallerySummary(key: existingKey, title: "Local title", tags: ["local:tag"])
        let missing = GallerySummary(key: GalleryKey(gid: 91, token: "missing"), title: "Imported title")
        try await store.upsert([existing])
        try await store.updateReadingProgress(for: existingKey, page: 3)
        try await store.setFavorite(for: existingKey, isFavorite: true)

        let outcome = try await store.insertMissingGallerySyncSummaries([
            GallerySummary(key: existingKey, title: "Must not overwrite"),
            missing,
            missing
        ])

        #expect(outcome.sourceCount == 3)
        #expect(outcome.duplicateInFileCount == 1)
        #expect(outcome.existingCount == 1)
        #expect(outcome.insertedCount == 1)
        #expect(try await store.gallerySummary(for: existingKey)?.title == "Local title")
        #expect(try await store.readingPage(for: existingKey) == 3)
        #expect(try await store.isFavorite(for: existingKey) == true)
        #expect(try await store.gallerySummary(for: missing.key)?.title == "Imported title")
        #expect(try await store.gallerySyncSummaries(for: [existingKey, missing.key]).map(\.key) == [existingKey, missing.key])
    }
}
