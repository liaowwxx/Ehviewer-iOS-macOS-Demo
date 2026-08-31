import CryptoKit
import Foundation
import Testing
import SwiftData
import EHDomain
import EHDeviceSync
import EHDownloads
import EHPersistence

struct DeviceSyncIndexTests {
    @Test("Index rebuild is published atomically and later media changes are journaled")
    func rebuildAndIncrementalMediaChanges() async throws {
        let indexRoot = temporaryRoot("index")
        let index = DeviceSyncIndexStore(root: indexRoot)
        let key = GalleryKey(gid: 30, token: "indexed")
        let metadata = try DeviceSyncMetadataDigest(
            stableCapturedAt: Date(timeIntervalSince1970: 100),
            stableCompleteness: GalleryMetadataCompleteness(title: .loadedWithValue),
            stableFingerprint: Data(SHA256.hash(data: Data("title".utf8))),
            estimatedTransferBytes: 128
        )

        try await index.beginRebuild()
        try await index.finishRebuild(with: DeviceSyncIndexSnapshot(entries: [
            try DeviceSyncIndexEntry(key: key, metadata: metadata)
        ]))
        let readyStatus = await index.status()
        #expect(readyStatus == .ready)
        #expect(try await index.snapshot().entries.first?.metadata == metadata)
        #expect(try await index.snapshot().manifest().galleries.isEmpty)

        let store = DownloadFileStore(
            root: temporaryRoot("media"),
            minimumFreeBytes: 1,
            indexSink: index
        )
        let image = try imageData()
        _ = try await store.write(image, for: key, pageIndex: 0)

        let updated = try await index.snapshot()
        #expect(updated.entries.first?.pages.map(\.pageIndex) == [0])
        #expect(updated.entries.first?.pages.first?.byteCount == Int64(image.count))

        let reopened = DeviceSyncIndexStore(root: indexRoot)
        let reopenedStatus = await reopened.status()
        #expect(reopenedStatus == .ready)
        #expect(try await reopened.snapshot().entries.first?.pages.map(\.pageIndex) == [0])

        try await store.remove(key)
        let reopenedAfterRemoval = DeviceSyncIndexStore(root: indexRoot)
        #expect(try await reopenedAfterRemoval.snapshot().entries.first?.pages.isEmpty == true)
    }

    @Test("A cancelled rebuild never exposes a partial index")
    func cancelledRebuildNeedsAnotherBuild() async throws {
        let index = DeviceSyncIndexStore(root: temporaryRoot("cancelled"))
        try await index.beginRebuild()
        await index.cancelRebuild()

        let cancelledStatus = await index.status()
        #expect(cancelledStatus == .needsBuild)
        do {
            _ = try await index.snapshot()
            Issue.record("a cancelled rebuild must not expose a snapshot")
        } catch let error as DeviceSyncIndexError {
            #expect(error == .notReady)
        }
    }

    @Test("Downloaded metadata changes update the index sink without a media scan")
    func persistenceUpdatesMetadataIndex() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = PersistenceStore(modelContainer: container)
        let sink = RecordingIndexSink()
        await store.configureDeviceSyncIndex(sink)
        let key = GalleryKey(gid: 31, token: "metadata-index")

        try await store.promoteToDownloadedGallery(stable: StableGalleryMetadataSnapshot(
            key: key,
            sourceSite: .eHentai,
            title: "Indexed metadata",
            capturedAt: Date(timeIntervalSince1970: 200)
        ))
        #expect(await sink.upsertedKeys == [key])

        try await store.deleteDownload(for: key)
        #expect(await sink.removedKeys == [key])
    }

    private func imageData() throws -> Data {
        try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
    }

    private func temporaryRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ehviewer-sync-index-\(name)-\(UUID().uuidString)")
    }
}

private actor RecordingIndexSink: DeviceSyncIndexSink {
    var upsertedKeys: [GalleryKey] = []
    var removedKeys: [GalleryKey] = []

    func status() async -> DeviceSyncIndexStatus { .ready }

    func snapshot() async throws -> DeviceSyncIndexSnapshot {
        try DeviceSyncIndexSnapshot(entries: [])
    }

    func beginRebuild() async throws {}
    func finishRebuild(with snapshot: DeviceSyncIndexSnapshot) async throws {}
    func cancelRebuild() async {}
    func upsertMediaPage(key: GalleryKey, pageIndex: Int, byteCount: Int64) async {}
    func removeMediaPage(key: GalleryKey, pageIndex: Int) async {}
    func removeMedia(for key: GalleryKey) async {}

    func upsertMetadata(_ entry: DeviceSyncIndexMetadataEntry) async {
        upsertedKeys.append(entry.key)
    }

    func removeMetadata(for key: GalleryKey) async {
        removedKeys.append(key)
    }
}
