import Foundation
import Testing
import SwiftData
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

    @Test("Reading a downloaded-only gallery creates a history record")
    func downloadedOnlyProgressCreatesHistory() async throws {
        let store = PersistenceStore(modelContainer: try ModelContainerFactory.make(inMemory: true))
        let key = GalleryKey(gid: 73, token: "downloaded-only")
        try await store.promoteToDownloadedGallery(
            stable: StableGalleryMetadataSnapshot(
                key: key,
                sourceSite: .eHentai,
                title: "Downloaded only"
            )
        )

        try await store.updateReadingProgress(for: key, page: 2)

        let recent = try await store.recent()
        #expect(recent.count == 1)
        #expect(recent.first?.key == key)
        #expect(recent.first?.title == "Downloaded only")
    }

    @Test("Batch library removal keeps the other library state")
    func batchLibraryRemovalKeepsIndependentState() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = PersistenceStore(modelContainer: container)
        let historyKey = GalleryKey(gid: 70, token: "history")
        let favoriteKey = GalleryKey(gid: 71, token: "favorite")
        let untouchedKey = GalleryKey(gid: 72, token: "untouched")

        try await store.upsert([
            GallerySummary(key: historyKey, title: "History"),
            GallerySummary(key: favoriteKey, title: "Favorite"),
            GallerySummary(key: untouchedKey, title: "Untouched")
        ])
        try await store.updateReadingProgress(for: historyKey, page: 4)
        try await store.updateReadingProgress(for: favoriteKey, page: 2)
        try await store.setFavorite(for: historyKey, isFavorite: true)
        try await store.setFavorite(for: favoriteKey, isFavorite: true)
        try await store.setFavorite(for: untouchedKey, isFavorite: true)

        try await store.removeFromHistory(for: [historyKey])
        #expect(try await store.recent().contains { $0.key == historyKey } == false)
        #expect(try await store.readingPage(for: historyKey) == 0)
        #expect(try await store.isFavorite(for: historyKey) == true)

        try await store.removeFromFavorites(for: [favoriteKey])
        #expect(try await store.favorites().contains { $0.key == favoriteKey } == false)
        #expect(try await store.readingPage(for: favoriteKey) == 2)
        #expect(try await store.favorites().contains { $0.key == untouchedKey })
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

    @Test("Download baseline can skip the separate metadata blob")
    func downloadBaselineCanSkipMetadataBlob() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = PersistenceStore(modelContainer: container)
        let key = GalleryKey(gid: 9, token: "download-baseline")
        let summary = GallerySummary(key: key, title: "Metadata", tags: ["artist:sample"])
        try await store.promoteToDownloadedGallery(
            stable: StableGalleryMetadataSnapshot(summary: summary, sourceSite: .eHentai)
        )
        try await store.upsertDownload(
            key: key,
            title: summary.title,
            tags: summary.tags,
            pages: [],
            completedPageIndexes: [],
            stateRaw: "paused",
            errorMessage: nil
        )

        let baseline = try await store.downloadJobs(includeTags: false)
        #expect(baseline.first?.tags.isEmpty == true)
        #expect(try await store.downloadJobs().first?.tags == summary.tags)
    }

    @MainActor
    @Test("Deleting a download removes all duplicate persisted job rows")
    func deleteDownloadRemovesDuplicateRows() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = PersistenceStore(modelContainer: container)
        let key = GalleryKey(gid: 81, token: "duplicate-delete")
        let context = container.mainContext
        context.insert(DownloadJobRecord(key: key, title: "Duplicate 1", totalPages: 0))
        context.insert(DownloadJobRecord(key: key, title: "Duplicate 2", totalPages: 0))
        try context.save()

        #expect(try await store.downloadJobs().count == 2)
        try await store.deleteDownload(for: key)
        #expect(try await store.downloadJobs().isEmpty)
    }

    @Test("Device sync commits gallery metadata and validated pages together")
    func deviceSyncCompletesReceivedDownload() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = PersistenceStore(modelContainer: container)
        let key = GalleryKey(gid: 9, token: "device-sync-complete")
        let pages = (0..<2).map { index in
            GalleryPageDescriptor(
                galleryKey: key,
                index: index,
                pageURL: URL(string: "https://example.invalid/sync/(index)")!
            )
        }
        let transfer = try GalleryTransferRecord(
            stable: StableGalleryMetadataSnapshot(
                key: key,
                sourceSite: .eHentai,
                title: "同步完成",
                pageCount: pages.count,
                pages: pages
            )
        )

        try await store.commitDeviceSyncGallery(transfer, completedPages: [0: 10, 1: 20])

        let restored = try #require(await store.downloadJobs().first)
        #expect(restored.completedPageIndexes == [0, 1])
        #expect(restored.stateRaw == "completed")
        #expect(try await store.downloadedGallerySummary(for: key)?.title == "同步完成")
    }

    @Test("Deleting an abnormal synced download preserves history and favorites")
    func abnormalSyncDeletionPreservesLibraryState() async throws {
        let store = PersistenceStore(modelContainer: try ModelContainerFactory.make(inMemory: true))
        let key = GalleryKey(gid: 901, token: "abnormal-sync")
        try await store.upsert([GallerySummary(key: key, title: "Browse copy")])
        try await store.updateReadingProgress(for: key, page: 3)
        try await store.setFavorite(for: key, isFavorite: true)
        let transfer = try GalleryTransferRecord(stable: StableGalleryMetadataSnapshot(
            key: key,
            sourceSite: .eHentai,
            title: "Downloaded copy"
        ))
        try await store.commitDeviceSyncGallery(transfer, completedPages: [0: 42])

        try await store.deleteDownload(for: key)

        #expect(try await store.downloadJobs().contains { $0.key == key } == false)
        #expect(try await store.downloadedGallerySummary(for: key) == nil)
        #expect(try await store.readingPage(for: key) == 3)
        #expect(try await store.isFavorite(for: key) == true)
    }

    @Test("SwiftData deletes a batch of downloads in one operation")
    func batchDownloadDeletion() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = PersistenceStore(modelContainer: container)
        let keys = (0..<3).map { GalleryKey(gid: Int64(80 + $0), token: "batch-\($0)") }

        for key in keys {
            try await store.upsertDownload(
                key: key,
                title: "Batch \(key.gid)",
                pages: [],
                completedPageIndexes: [],
                stateRaw: "paused",
                errorMessage: nil
            )
        }

        try await store.deleteDownloads(for: Set(keys))

        #expect(try await store.downloadJobs().isEmpty)
        #expect(try await store.downloadedTransferRecord(for: keys[0]) == nil)
        #expect(try await store.gallerySummary(for: keys[0]) == nil)
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
        #expect(try await store.localGallerySummaries(for: [missing.key, existingKey]).isEmpty)
    }

    @Test("Gallery sync merges titles and tags without changing local reading state")
    func gallerySyncMergesTransferMetadata() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = PersistenceStore(modelContainer: container)
        let key = GalleryKey(gid: 92, token: "merge")
        try await store.upsert([GallerySummary(key: key, title: "旧标题", tags: ["old:tag"])])
        try await store.updateReadingProgress(for: key, page: 6)
        try await store.setFavorite(for: key, isFavorite: true)

        let incoming = GallerySummary(
            key: key,
            title: "普通标题",
            japaneseTitle: "日本語タイトル",
            tags: ["artist:sample", "female:sub tag"]
        )
        let outcome = try await store.mergeGallerySyncSummaries([incoming])

        #expect(outcome.existingCount == 1)
        #expect(outcome.insertedCount == 0)
        let restored = try #require(await store.gallerySummary(for: key))
        #expect(restored.title == "普通标题")
        #expect(restored.japaneseTitle == "日本語タイトル")
        #expect(restored.tags == ["artist:sample", "female:sub tag"])
        #expect(try await store.readingPage(for: key) == 6)
        #expect(try await store.isFavorite(for: key) == true)
    }

    @Test("Ordinary cache and downloaded metadata have independent values and lifetimes")
    func cacheAndDownloadedMetadataAreIndependent() async throws {
        let store = PersistenceStore(modelContainer: try ModelContainerFactory.make(inMemory: true))
        let key = GalleryKey(gid: 93, token: "separated")
        try await store.upsertStableSnapshot(StableGalleryMetadataSnapshot(
            key: key,
            sourceSite: .eHentai,
            title: "在线缓存标题",
            tags: ["artist:cache"],
            capturedAt: Date(timeIntervalSince1970: 200)
        ))
        try await store.promoteToDownloadedGallery(stable: StableGalleryMetadataSnapshot(
            key: key,
            sourceSite: .eHentai,
            title: "本地下载标题",
            tags: ["artist:download"],
            capturedAt: Date(timeIntervalSince1970: 100)
        ))

        #expect(try await store.stableSnapshot(for: key)?.title == "在线缓存标题")
        #expect(try await store.downloadedGallerySummary(for: key)?.title == "本地下载标题")
        #expect(try await store.downloadedGallerySummary(for: key)?.tags == ["artist:download"])

        try await store.deleteDownload(for: key)

        #expect(try await store.downloadedTransferRecord(for: key) == nil)
        #expect(try await store.localGallerySummaries(for: [key]).isEmpty)
        #expect(try await store.stableSnapshot(for: key)?.title == "在线缓存标题")
    }

    @Test("Local gallery summary batch returns only requested downloaded metadata")
    func localGallerySummaryBatchFiltersRequestedKeys() async throws {
        let store = PersistenceStore(modelContainer: try ModelContainerFactory.make(inMemory: true))
        let requested = GalleryKey(gid: 94, token: "requested")
        let unrequested = GalleryKey(gid: 95, token: "unrequested")
        try await store.promoteToDownloadedGallery(stable: StableGalleryMetadataSnapshot(
            key: requested,
            sourceSite: .eHentai,
            title: "Requested local gallery"
        ))
        try await store.promoteToDownloadedGallery(stable: StableGalleryMetadataSnapshot(
            key: unrequested,
            sourceSite: .eHentai,
            title: "Unrequested local gallery"
        ))

        let summaries = try await store.localGallerySummaries(for: [requested])

        #expect(summaries.map(\.key) == [requested])
        #expect(summaries.first?.title == "Requested local gallery")
    }
}
