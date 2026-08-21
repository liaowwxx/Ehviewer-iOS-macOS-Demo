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
        #expect(try await store.stableSnapshot(for: downloadedKey)?.title == "下载画廊")
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
        #expect(try await store.stableSnapshot(for: key)?.title == "下载画廊")
    }
}
