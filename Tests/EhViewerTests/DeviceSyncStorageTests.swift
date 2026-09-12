import CryptoKit
import Foundation
import Testing
import EHDomain
import EHDeviceSync
import EHDownloads

struct DeviceSyncStorageTests {
    @Test("Local page enumeration accepts only legal validated media files")
    func enumeratesValidatedPages() async throws {
        let root = temporaryRoot("enumeration")
        let store = DownloadFileStore(root: root, minimumFreeBytes: 1)
        let key = GalleryKey(gid: 20, token: "media")
        let image = try imageData()
        _ = try await store.write(image, for: key, pageIndex: 0)

        let directory = (await store.finalURL(for: key, pageIndex: 0)).deletingLastPathComponent()
        try Data(image).write(to: directory.appendingPathComponent("page-2.bin.part"))
        try Data("not media".utf8).write(to: directory.appendingPathComponent("page-3.bin"))
        try Data(image).write(to: directory.appendingPathComponent("other.bin"))

        let entries = await store.localPageEntries(for: key)
        #expect(entries.map(\.pageIndex) == [0])
        #expect(entries.first?.byteCount == Int64(image.count))
        try await store.remove(key)
    }

    @Test("Streaming receive commits only after size, hash and media validation")
    func receivesAndCommitsValidatedPage() async throws {
        let root = temporaryRoot("receive")
        let store = DownloadFileStore(root: root, minimumFreeBytes: 1)
        let key = GalleryKey(gid: 21, token: "receive")
        let image = try imageData()
        let digest = Data(SHA256.hash(data: image))
        let handle = try await store.beginReceive(
            for: key,
            pageIndex: 0,
            expectedByteCount: Int64(image.count),
            expectedSHA256: digest
        )
        try await store.appendReceiveChunk(image.prefix(image.count / 2), to: handle)
        try await store.appendReceiveChunk(image.suffix(image.count - image.count / 2), to: handle)
        let result = try await store.finishReceive(handle)

        #expect(result == .committed(await store.finalURL(for: key, pageIndex: 0)))
        #expect(await store.readablePageIndexes(for: key, pageIndexes: [0]) == [0])
        try await store.remove(key)
    }

    @Test("A streamed page accepts the digest produced by the sender's single read")
    func receivesDigestAtPageFinish() async throws {
        let root = temporaryRoot("receive-late-digest")
        let store = DownloadFileStore(root: root, minimumFreeBytes: 1)
        let key = GalleryKey(gid: 211, token: "receive-late-digest")
        let image = try imageData()
        let handle = try await store.beginReceive(
            for: key,
            pageIndex: 0,
            expectedByteCount: Int64(image.count)
        )
        try await store.appendReceiveChunk(image, to: handle)

        let result = try await store.finishReceive(
            handle,
            expectedSHA256: Data(SHA256.hash(data: image))
        )

        #expect(result == .committed(await store.finalURL(for: key, pageIndex: 0)))
        try await store.remove(key)
    }

    @Test("Gallery audit removes invalid store files and reports an empty shell")
    func auditsAndCleansEmptyGallery() async throws {
        let root = temporaryRoot("audit-empty")
        let store = DownloadFileStore(root: root, minimumFreeBytes: 1)
        let key = GalleryKey(gid: 212, token: "audit-empty")
        let finalURL = await store.finalURL(for: key, pageIndex: 0)
        try FileManager.default.createDirectory(
            at: finalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("invalid".utf8).write(to: finalURL)
        let partialURL = finalURL.appendingPathExtension("part")
        try Data("partial".utf8).write(to: partialURL)

        let audit = await store.auditLocalGallery(for: key, removeInvalidFiles: true)

        #expect(audit.validPages.isEmpty)
        #expect(audit.invalidFinalFileCount == 1)
        #expect(audit.removedTemporaryFileCount == 1)
        #expect(FileManager.default.fileExists(atPath: finalURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: partialURL.path) == false)
        try await store.remove(key)
    }

    @Test("Wrong hash, size and invalid media never reach the final path")
    func rejectsInvalidReceivedPages() async throws {
        let root = temporaryRoot("invalid-receive")
        let store = DownloadFileStore(root: root, minimumFreeBytes: 1)
        let key = GalleryKey(gid: 22, token: "invalid")
        let image = try imageData()

        let wrongHash = try await store.beginReceive(
            for: key,
            pageIndex: 0,
            expectedByteCount: Int64(image.count),
            expectedSHA256: Data(repeating: 0, count: 32)
        )
        try await store.appendReceiveChunk(image, to: wrongHash)
        do {
            _ = try await store.finishReceive(wrongHash)
            Issue.record("wrong hash must be rejected")
        } catch let error as DownloadReceiveError {
            #expect(error == .hashMismatch)
        }
        #expect(await store.contains(key, pageIndex: 0) == false)

        let invalid = Data("<html>not a page</html>".utf8)
        let invalidHandle = try await store.beginReceive(
            for: key,
            pageIndex: 1,
            expectedByteCount: Int64(invalid.count),
            expectedSHA256: Data(SHA256.hash(data: invalid))
        )
        try await store.appendReceiveChunk(invalid, to: invalidHandle)
        do {
            _ = try await store.finishReceive(invalidHandle)
            Issue.record("invalid media must be rejected")
        } catch let error as DownloadReceiveError {
            #expect(error == .invalidMedia)
        }
        #expect(await store.contains(key, pageIndex: 1) == false)
        try await store.remove(key)
    }

    @Test("A valid page written locally is never overwritten by a received duplicate")
    func keepsExistingValidPage() async throws {
        let root = temporaryRoot("duplicate")
        let store = DownloadFileStore(root: root, minimumFreeBytes: 1)
        let key = GalleryKey(gid: 23, token: "duplicate")
        let image = try imageData()
        _ = try await store.write(image, for: key, pageIndex: 0)
        let handle = try await store.beginReceive(
            for: key,
            pageIndex: 0,
            expectedByteCount: Int64(image.count),
            expectedSHA256: Data(SHA256.hash(data: image))
        )
        try await store.appendReceiveChunk(image, to: handle)
        #expect(try await store.finishReceive(handle) == .alreadyPresent(await store.finalURL(for: key, pageIndex: 0)))
        try await store.remove(key)
    }

    @Test("Page chunks are bounded and preserve the original file size")
    func readsPageChunksWithoutWholeFileBuffer() async throws {
        let root = temporaryRoot("chunks")
        let store = DownloadFileStore(root: root, minimumFreeBytes: 1)
        let key = GalleryKey(gid: 24, token: "chunks")
        let image = try imageData()
        _ = try await store.write(image, for: key, pageIndex: 0)
        let probe = ChunkProbe()
        let streamResult = try await store.readPageChunksAndHash(for: key, pageIndex: 0, chunkSize: 3) { chunk in
            await probe.add(chunk.count)
        }
        let (total, largestChunk) = await probe.result()
        #expect(total == image.count)
        #expect(largestChunk <= 3)
        #expect(streamResult.byteCount == Int64(image.count))
        #expect(streamResult.sha256 == Data(SHA256.hash(data: image)))
        try await store.remove(key)
    }

    @Test("Device sync v4 uses one MiB chunks and bounded transfer windows")
    func usesV4TransferTuning() {
        #expect(DeviceSyncCoordinator.protocolVersion == 4)
        #expect(DeviceSyncCoordinator.preferredPageChunkBytes(forPageByteCount: 1 * 1024 * 1024) == 1 * 1024 * 1024)
        #expect(DeviceSyncCoordinator.preferredPageChunkBytes(forPageByteCount: 16 * 1024 * 1024) == 1 * 1024 * 1024)
        #expect(DeviceSyncCoordinator.sendWindowBytes == 16 * 1024 * 1024)
        #expect(DeviceSyncCoordinator.receiveQueueBytes == 16 * 1024 * 1024)
        #expect(DeviceSyncCoordinator.maximumPageChunkBytes <= DeviceSyncCoordinator.sendWindowBytes)
    }

#if os(macOS)
    @Test("Native macOS always reports Wi-Fi Aware unavailable")
    func macOSUsesLegacyTransport() {
        #expect(DeviceSyncWiFiAwareSupport.isAvailable == false)
        #expect(DeviceSyncWiFiAwareSupport.fallbackReason != nil)
    }
#endif

    private func imageData() throws -> Data {
        try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
    }

    private func temporaryRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ehviewer-sync-\(name)-\(UUID().uuidString)")
    }
}

private actor ChunkProbe {
    private var total = 0
    private var largest = 0

    func add(_ count: Int) {
        total += count
        largest = max(largest, count)
    }

    func result() -> (Int, Int) {
        (total, largest)
    }
}
