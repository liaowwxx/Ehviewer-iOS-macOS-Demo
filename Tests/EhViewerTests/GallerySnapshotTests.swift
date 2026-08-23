import Foundation
import Testing
import EHDomain
import EHPersistence

struct GallerySnapshotTests {
    @Test("Preferred card authors use artists before groups")
    func preferredCardAuthors() {
        let artistGallery = GallerySummary(
            key: GalleryKey(gid: 90, token: "artist"),
            title: "Artist",
            tags: ["group:backup", "artist:first", "artist:second"]
        )
        let groupGallery = GallerySummary(
            key: GalleryKey(gid: 91, token: "group"),
            title: "Group",
            tags: ["group:circle", "language:english"]
        )

        #expect(artistGallery.preferredAuthorTags == ["artist:first", "artist:second"])
        #expect(groupGallery.preferredAuthorTags == ["group:circle"])
    }

    @Test("Gallery metadata completeness decodes the boolean fields from old archives")
    func decodesLegacyBooleanCompleteness() throws {
        let data = Data(#"{"title":true,"japaneseTitle":false,"tags":true}"#.utf8)
        let decoded = try JSONDecoder().decode(GalleryMetadataCompleteness.self, from: data)

        #expect(decoded.title == .loadedWithValue)
        #expect(decoded.japaneseTitle == .notLoaded)
        #expect(decoded.tags == .loadedWithValue)
        #expect(decoded.category == .notLoaded)
    }

    @Test("Gallery metadata completeness preserves three distinct field states")
    func completenessHasThreeStates() throws {
        let value = GalleryMetadataCompleteness(
            title: .loadedWithValue,
            japaneseTitle: .loadedEmpty,
            tags: .notLoaded
        )
        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(GalleryMetadataCompleteness.self, from: encoded)

        #expect(decoded.title == .loadedWithValue)
        #expect(decoded.japaneseTitle == .loadedEmpty)
        #expect(decoded.tags == .notLoaded)
        #expect(decoded.isComplete == false)

        let summaryOnly = GalleryMetadataCompleteness(
            title: .loadedWithValue,
            japaneseTitle: .loadedEmpty,
            authors: .loadedEmpty,
            uploader: .loadedEmpty,
            tags: .loadedWithValue,
            category: .loadedWithValue,
            pageCount: .loadedWithValue,
            postedAt: .loadedWithValue,
            thumbnailURL: .loadedWithValue,
            rating: .loadedWithValue
        )
        #expect(summaryOnly.isSummaryComplete)
        #expect(summaryOnly.isComplete == false)
    }

    @Test("Stable snapshot merge keeps complete fields when incoming data is missing")
    func stableMergeKeepsCompleteFields() {
        let key = GalleryKey(gid: 100, token: "merge")
        let old = StableGalleryMetadataSnapshot(
            key: key,
            sourceSite: .eHentai,
            title: "完整标题",
            tags: ["artist:one"],
            postedAt: Date(timeIntervalSince1970: 100),
            capturedAt: Date(timeIntervalSince1970: 100),
            completeness: GalleryMetadataCompleteness(
                title: .loadedWithValue,
                authors: .loadedWithValue,
                tags: .loadedWithValue,
                postedAt: .loadedWithValue
            )
        )
        let incoming = StableGalleryMetadataSnapshot(
            key: key,
            sourceSite: .exHentai,
            title: "",
            tags: [],
            capturedAt: Date(timeIntervalSince1970: 200),
            completeness: GalleryMetadataCompleteness()
        )

        let merged = GallerySnapshotMerger.merge(existing: old, incoming: incoming)
        #expect(merged.title == "完整标题")
        #expect(merged.tags == ["artist:one"])
        #expect(merged.postedAt == Date(timeIntervalSince1970: 100))
        #expect(merged.sourceSite == .exHentai)
    }

    @Test("Summary projections do not claim unavailable detail fields")
    func summaryProjectionDoesNotEraseDetailCompleteness() {
        let key = GalleryKey(gid: 104, token: "summary-projection")
        let summary = GallerySummary(
            key: key,
            title: "摘要标题",
            category: "Artist CG",
            pageCount: 12,
            postedAt: Date(timeIntervalSince1970: 123),
            rating: 4.5,
            ratingCount: 42,
            favoriteCategory: 3,
            tags: ["artist:someone"],
            metadataCompleteness: .complete
        )

        let snapshot = StableGalleryMetadataSnapshot(
            summary: summary,
            sourceSite: .eHentai,
            capturedAt: Date(timeIntervalSince1970: 200)
        )

        #expect(snapshot.category == "Artist CG")
        #expect(snapshot.postedAt == Date(timeIntervalSince1970: 123))
        #expect(snapshot.completeness.category == .loadedWithValue)
        #expect(snapshot.completeness.postedAt == .loadedWithValue)
        #expect(snapshot.completeness.language == .notLoaded)
        #expect(snapshot.completeness.fileSize == .notLoaded)
        #expect(snapshot.completeness.description == .notLoaded)
        #expect(snapshot.completeness.externalURL == .notLoaded)
        #expect(snapshot.completeness.pages == .notLoaded)
        #expect(snapshot.completeness.comments == .notLoaded)
        #expect(snapshot.summary.metadataCompleteness?.rating == .notLoaded)
        #expect(snapshot.summary.metadataCompleteness?.favorite == .notLoaded)
    }

    @Test("Summary metadata updates preserve downloaded detail fields")
    func summaryMetadataUpdatePreservesDownloadedDetails() async throws {
        let key = GalleryKey(gid: 105, token: "summary-merge")
        let store = PersistenceStore(modelContainer: try ModelContainerFactory.make(inMemory: true))
        let postedAt = Date(timeIntervalSince1970: 321)
        let pageURL = try #require(URL(string: "https://example.invalid/page.jpg"))
        let stable = StableGalleryMetadataSnapshot(
            key: key,
            sourceSite: .eHentai,
            title: "完整标题",
            tags: ["artist:detail"],
            category: "Image Set",
            language: "English",
            pageCount: 1,
            postedAt: postedAt,
            fileSize: "1 MB",
            descriptionText: "完整描述",
            externalURL: URL(string: "https://example.invalid/gallery"),
            pages: [GalleryPageDescriptor(galleryKey: key, index: 0, pageURL: pageURL)],
            capturedAt: Date(timeIntervalSince1970: 100),
            completeness: .complete
        )
        let dynamic = DownloadedGalleryDynamicSnapshot(
            key: key,
            rating: 4.0,
            ratingCount: 10,
            favoriteCount: 8,
            favoriteName: "收藏夹",
            favoriteCategory: 1,
            comments: [DownloadedGalleryCommentSnapshot(
                id: "comment",
                author: "reader",
                body: "评论"
            )],
            capturedAt: Date(timeIntervalSince1970: 100),
            completeness: .complete
        )
        try await store.promoteToDownloadedGallery(stable: stable, dynamic: dynamic)

        let newerSummary = GallerySummary(
            key: key,
            title: "更新后的标题",
            category: "Image Set",
            pageCount: 1,
            postedAt: postedAt,
            rating: 4.5,
            ratingCount: 11,
            favoriteCategory: 2,
            tags: ["artist:detail"],
            metadataCompleteness: .complete
        )
        try await store.saveDownloadedMetadata(
            stableSnapshots: [StableGalleryMetadataSnapshot(summary: newerSummary, sourceSite: .eHentai)],
            dynamicSnapshots: [DownloadedGalleryDynamicSnapshot(
                key: key,
                rating: newerSummary.rating,
                ratingCount: newerSummary.ratingCount,
                favoriteCategory: newerSummary.favoriteCategory,
                capturedAt: Date(),
                completeness: GalleryMetadataCompleteness(
                    rating: .loadedWithValue,
                    ratingCount: .loadedWithValue,
                    favorite: .loadedWithValue,
                    comments: .notLoaded
                )
            )]
        )

        let restoredStable = try #require(await store.downloadedTransferRecord(for: key)?.stable)
        #expect(restoredStable.title == "更新后的标题")
        #expect(restoredStable.descriptionText == "完整描述")
        #expect(restoredStable.fileSize == "1 MB")
        #expect(restoredStable.externalURL == URL(string: "https://example.invalid/gallery"))
        #expect(restoredStable.pages.count == 1)

        let restoredDynamic = try #require(await store.downloadedDynamicSnapshot(for: key))
        #expect(restoredDynamic.rating == 4.5)
        #expect(restoredDynamic.ratingCount == 11)
        #expect(restoredDynamic.favoriteCount == 8)
        #expect(restoredDynamic.favoriteName == "收藏夹")
        #expect(restoredDynamic.favoriteCategory == 2)
        #expect(restoredDynamic.comments.first?.body == "评论")
    }

    @Test("Persistence separates ordinary stable cache from downloaded dynamic data")
    func persistenceSeparatesStableAndDynamicData() async throws {
        let store = PersistenceStore(modelContainer: try ModelContainerFactory.make(inMemory: true))
        let ordinaryKey = GalleryKey(gid: 101, token: "ordinary")
        let downloadedKey = GalleryKey(gid: 102, token: "downloaded")
        let stable = StableGalleryMetadataSnapshot(
            key: ordinaryKey,
            sourceSite: .eHentai,
            title: "普通缓存",
            tags: ["artist:cache"]
        )
        try await store.upsertStableSnapshot(stable)
        try await store.updateReadingProgress(for: ordinaryKey, page: 4)
        try await store.setFavorite(for: ordinaryKey, isFavorite: true)

        let downloadedStable = StableGalleryMetadataSnapshot(
            key: downloadedKey,
            sourceSite: .eHentai,
            title: "下载画廊",
            tags: ["artist:download"]
        )
        try await store.promoteToDownloadedGallery(
            stable: downloadedStable,
            dynamic: DownloadedGalleryDynamicSnapshot(
                key: downloadedKey,
                rating: 4.5,
                favoriteCategory: 2,
                comments: [DownloadedGalleryCommentSnapshot(
                    id: "comment",
                    author: "reader",
                    body: "body"
                )]
            )
        )

        #expect(try await store.gallerySummary(for: ordinaryKey)?.rating == nil)
        #expect(try await store.downloadedDynamicSnapshot(for: downloadedKey)?.rating == 4.5)
        #expect(try await store.downloadedDynamicSnapshot(for: downloadedKey)?.comments.first?.galleryComment.isEditable == false)

        try await store.clearOrdinaryCache()
        #expect(try await store.stableSnapshot(for: ordinaryKey) == nil)
        #expect(try await store.readingPage(for: ordinaryKey) == 4)
        #expect(try await store.isFavorite(for: ordinaryKey) == true)
        #expect(try await store.stableSnapshot(for: downloadedKey) == nil)
        #expect(try await store.downloadedTransferRecord(for: downloadedKey)?.stable.title == "下载画廊")
        #expect(try await store.downloadedDynamicSnapshot(for: downloadedKey)?.favoriteCategory == 2)
    }

    @Test("Clearing library state removes favorites and history but keeps downloads")
    func clearLibraryStatePreservesDownloads() async throws {
        let store = PersistenceStore(modelContainer: try ModelContainerFactory.make(inMemory: true))
        let key = GalleryKey(gid: 103, token: "library-state")
        try await store.upsert([
            GallerySummary(key: key, title: "下载画廊", tags: ["artist:test"])
        ])
        try await store.updateReadingProgress(for: key, page: 3)
        try await store.setFavorite(for: key, isFavorite: true)
        try await store.promoteToDownloadedGallery(
            stable: StableGalleryMetadataSnapshot(
                key: key,
                sourceSite: .eHentai,
                title: "下载画廊"
            )
        )

        try await store.clearLibraryState()

        #expect(try await store.recent().isEmpty)
        #expect(try await store.isFavorite(for: key) == false)
        #expect(try await store.downloadedTransferRecord(for: key)?.stable.title == "下载画廊")
    }
}
