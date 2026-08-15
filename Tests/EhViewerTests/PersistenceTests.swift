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

    @Test("Migration snapshots round-trip library, downloads and preferences")
    func migrationRoundTrip() async throws {
        let sourceContainer = try ModelContainerFactory.make(inMemory: true)
        let source = PersistenceStore(modelContainer: sourceContainer)
        let key = GalleryKey(gid: 9, token: "migration")
        let summary = GallerySummary(
            key: key,
            title: "迁移样本",
            thumbnailURL: URL(string: "https://example.invalid/cover.jpg"),
            pageCount: 2,
            tags: ["language:chinese"]
        )
        let pages = (0..<2).map { index in
            GalleryPageDescriptor(
                galleryKey: key,
                index: index,
                pageURL: URL(string: "https://example.invalid/page/\(index)")!
            )
        }

        try await source.upsert([summary])
        try await source.updateReadingProgress(for: key, page: 1)
        try await source.setFavorite(for: key, isFavorite: true)
        try await source.upsertDownload(
            key: key,
            title: summary.title,
            pages: pages,
            completedPageIndexes: [0],
            stateRaw: "paused",
            errorMessage: "暂停"
        )
        try await source.recordQuickSearch("migration")
        try await source.setFilterRule(pattern: "spoiler", isEnabled: false)
        try await source.saveTagTranslation(tag: "language:chinese", locale: "zh-Hans", localizedText: "语言：中文")

        let snapshot = try await source.exportSnapshot()
        let destinationContainer = try ModelContainerFactory.make(inMemory: true)
        let destination = PersistenceStore(modelContainer: destinationContainer)
        try await destination.importSnapshot(snapshot)

        #expect(try await destination.readingPage(for: key) == 1)
        #expect(try await destination.isFavorite(for: key) == true)
        #expect(try await destination.downloadJobs().first?.completedPageIndexes == [0])
        #expect(try await destination.quickSearches() == ["migration"])
        #expect(try await destination.filterRules().first?.isEnabled == false)
        #expect(try await destination.tagTranslations(locale: "zh-Hans")["language:chinese"] == "语言：中文")
    }
}
