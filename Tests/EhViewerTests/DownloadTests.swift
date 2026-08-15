import Foundation
import Testing
import EHDomain
import EHDownloads
@testable import EhViewerPreview

struct DownloadTests {
    @Test("Download coordinator limits a job to bounded page batches")
    func completesJob() async throws {
        let pages = (0..<5).map { index in
            GalleryPageDescriptor(
                galleryKey: GalleryKey(gid: 1, token: "t"),
                index: index,
                pageURL: URL(string: "https://example.invalid/\(index)")!
            )
        }
        let coordinator = DownloadCoordinator(maxConcurrentPages: 2) { _ in Data("page".utf8) }
        await coordinator.enqueue(key: pages[0].galleryKey, title: "Test", pages: pages)

        for _ in 0..<100 {
            let job = await coordinator.snapshot().first
            if job?.state == .completed {
                #expect(job?.completedPageIndexes.count == 5)
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("download job did not complete within the test budget")
    }

    @Test("Download file store atomically promotes a partial file")
    func fileStoreAtomicWrite() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ehviewer-download-\(UUID().uuidString)")
        let store = DownloadFileStore(root: root, minimumFreeBytes: 1)
        let key = GalleryKey(gid: 2, token: "file")
        let imageData = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        let finalURL = try await store.write(imageData, for: key, pageIndex: 0)
        #expect(FileManager.default.fileExists(atPath: finalURL.path))
        #expect(FileManager.default.fileExists(atPath: finalURL.appendingPathExtension("part").path) == false)
        #expect(try Data(contentsOf: finalURL) == imageData)
        #expect(try await store.data(for: key, pageIndex: 0) == imageData)
        #expect(await store.readablePageIndexes(for: key, pageIndexes: [0, 1]) == [0])
        try await store.remove(key)
    }

    @Test("Download file store rejects successful HTML responses as image pages")
    func fileStoreRejectsNonImageData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ehviewer-download-invalid-\(UUID().uuidString)")
        let store = DownloadFileStore(root: root, minimumFreeBytes: 1)
        let key = GalleryKey(gid: 3, token: "invalid")

        do {
            _ = try await store.write(Data("<html>login required</html>".utf8), for: key, pageIndex: 0)
            Issue.record("non-image data must not be marked as a completed page")
        } catch let error as EHError {
            guard case .parsingFailed = error else {
                Issue.record("unexpected error: \(error)")
                return
            }
        }

        #expect(await store.contains(key, pageIndex: 0) == false)
    }

    @Test("Download coordinator runs only one gallery while keeping three-page batches")
    func oneGalleryAtATime() async throws {
        let firstKey = GalleryKey(gid: 10, token: "first")
        let secondKey = GalleryKey(gid: 11, token: "second")
        let probe = ActiveGalleryProbe()
        let coordinator = DownloadCoordinator(maxConcurrentPages: 3) { page in
            await probe.enter(page.galleryKey)
            try await Task.sleep(for: .milliseconds(20))
            await probe.leave(page.galleryKey)
            return Data(page.id.utf8)
        }
        let firstPages = (0..<4).map { index in
            GalleryPageDescriptor(galleryKey: firstKey, index: index, pageURL: URL(string: "https://example.invalid/first/\(index)")!)
        }
        let secondPages = (0..<4).map { index in
            GalleryPageDescriptor(galleryKey: secondKey, index: index, pageURL: URL(string: "https://example.invalid/second/\(index)")!)
        }
        await coordinator.enqueue(key: firstKey, title: "First", pages: firstPages)
        await coordinator.enqueue(key: secondKey, title: "Second", pages: secondPages)

        for _ in 0..<200 {
            let jobs = await coordinator.snapshot()
            if jobs.allSatisfy({ $0.state == .completed }) {
                #expect(await probe.maximumActiveGalleryCount == 1)
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("download jobs did not complete within the test budget")
    }

    @Test("Persisted downloads load as one snapshot without saving or starting work")
    func persistedDownloadsLoadWithoutSideEffects() async throws {
        let saveProbe = DownloadSaveProbe()
        let loadProbe = DownloadLoadProbe()
        let first = restoredJob(gid: 20, token: "first", title: "First")
        let second = restoredJob(gid: 21, token: "second", title: "Second")
        let coordinator = DownloadCoordinator(
            pageLoader: { page in
                await loadProbe.record(page.galleryKey)
                return Data(page.id.utf8)
            },
            persistence: { job in await saveProbe.record(job) }
        )
        let events = await coordinator.events()

        await coordinator.loadPersisted([first, second])

        #expect(await saveProbe.count == 0)
        #expect(await loadProbe.count == 0)
        var iterator = events.makeAsyncIterator()
        guard case let .reset(jobs)? = await iterator.next() else {
            Issue.record("bulk loading should publish one reset event")
            return
        }
        #expect(Set(jobs.map(\.key)) == [first.key, second.key])
    }

    @Test("Download restore merges existing pages instead of replacing the job")
    func mergeRestoredJobs() async throws {
        let key = GalleryKey(gid: 23, token: "merge")
        let localPage = GalleryPageDescriptor(
            galleryKey: key,
            index: 0,
            pageURL: URL(string: "https://example.invalid/local/0")!
        )
        let importedPage = GalleryPageDescriptor(
            galleryKey: key,
            index: 1,
            pageURL: URL(string: "https://example.invalid/imported/1")!
        )
        var local = DownloadJob(key: key, title: "Local", pages: [localPage], label: "本地")
        local.completedPageIndexes = [0]
        local.state = .paused
        var imported = DownloadJob(key: key, title: "Imported", pages: [importedPage])
        imported.completedPageIndexes = [1]
        imported.state = .paused

        let coordinator = DownloadCoordinator(pageLoader: { _ in Data() })
        await coordinator.restore([local])
        await coordinator.mergeRestored([imported])

        let merged = try #require(await coordinator.snapshot().first)
        #expect(merged.title == "Local")
        #expect(merged.label == "本地")
        #expect(merged.pages.map(\.index) == [0, 1])
        #expect(merged.pages.first?.pageURL == localPage.pageURL)
        #expect(merged.completedPageIndexes == [0, 1])
        #expect(merged.state == .completed)
    }

    @Test("A stale persisted reconciliation cannot overwrite a newer user change")
    func staleReconciliationDoesNotOverwriteNewerState() async throws {
        let saveProbe = DownloadSaveProbe()
        var baseline = restoredJob(gid: 22, token: "stale", title: "Original")
        baseline.state = .paused
        let coordinator = DownloadCoordinator(
            pageLoader: { page in Data(page.id.utf8) },
            persistence: { job in await saveProbe.record(job) }
        )
        await coordinator.loadPersisted([baseline])
        await coordinator.setLabel("用户标签", for: baseline.key)

        var reconciled = baseline
        reconciled.completedPageIndexes = [0]
        let applied = await coordinator.reconcilePersisted(reconciled, replacing: baseline)

        #expect(applied == false)
        #expect(await coordinator.snapshot().first?.label == "用户标签")
        #expect(await coordinator.snapshot().first?.completedPageIndexes.isEmpty == true)
        #expect(await saveProbe.count == 1)
    }

    @Test("Download coordinator retries ordinary network failures at most three times")
    func retriesNetworkFailure() async throws {
        let attempts = RetryCounter()
        let key = GalleryKey(gid: 12, token: "retry")
        let page = GalleryPageDescriptor(
            galleryKey: key,
            index: 0,
            pageURL: URL(string: "https://example.invalid/retry")!
        )
        let coordinator = DownloadCoordinator { page in
            let attempt = await attempts.next()
            if attempt < 3 { throw EHError.networkFailed("temporary") }
            return Data(page.id.utf8)
        }
        await coordinator.enqueue(key: key, title: "Retry", pages: [page])

        for _ in 0..<100 {
            if await coordinator.snapshot().first?.state == .completed {
                #expect(await attempts.value == 3)
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("retrying download did not complete within the test budget")
    }

    @Test("Download coordinator leaves media re-resolution to its page loader")
    func parsingFailureIsNotBlindlyRetried() async throws {
        let attempts = RetryCounter()
        let key = GalleryKey(gid: 14, token: "stale-node")
        let page = GalleryPageDescriptor(
            galleryKey: key,
            index: 0,
            pageURL: URL(string: "https://e-hentai.org/s/page/14-1")!
        )
        let coordinator = DownloadCoordinator { _ in
            _ = await attempts.next()
            throw EHError.parsingFailed("下载结果不是有效图片或视频")
        }
        await coordinator.enqueue(key: key, title: "Retry stale node", pages: [page])

        for _ in 0..<100 {
            if await coordinator.snapshot().first?.state == .failed {
                #expect(await attempts.value == 1)
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("permanent parsing failure did not stop the job")
    }

    @Test("Download media validation recognizes ISO base media video data")
    func recognizesVideoData() {
        let header: [UInt8] = [0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x6D, 0x70, 0x34, 0x32]
        #expect(DownloadMediaValidator.kind(of: Data(header)) == .video)
        #expect(DownloadMediaValidator.kind(of: Data("<html>error</html>".utf8)) == nil)
    }

    @Test("Downloads can sort by the time they were added in both directions")
    func sortsByAddedTime() {
        let older = DownloadJob(
            key: GalleryKey(gid: 15, token: "older"),
            title: "Older",
            pages: [],
            addedAt: Date(timeIntervalSince1970: 1)
        )
        let newer = DownloadJob(
            key: GalleryKey(gid: 16, token: "newer"),
            title: "Newer",
            pages: [],
            addedAt: Date(timeIntervalSince1970: 2)
        )

        #expect([older, newer].sorted(by: DownloadSortOrder.addedNewest.areInIncreasingOrder).map(\.key) == [newer.key, older.key])
        #expect([older, newer].sorted(by: DownloadSortOrder.addedOldest.areInIncreasingOrder).map(\.key) == [older.key, newer.key])
    }

    @Test("A failed download removal keeps the job visible with an actionable error")
    func failedRemovalKeepsJobVisible() async throws {
        let key = GalleryKey(gid: 13, token: "remove")
        let page = GalleryPageDescriptor(
            galleryKey: key,
            index: 0,
            pageURL: URL(string: "https://example.invalid/remove")!
        )
        let coordinator = DownloadCoordinator(
            pageLoader: { _ in Data("page".utf8) },
            removal: { _ in throw EHError.storageFailed("文件正被占用") }
        )
        await coordinator.enqueue(key: key, title: "Remove", pages: [page])

        let result = await coordinator.remove(key)
        guard case .failed = result else {
            Issue.record("removal failure should be reported to the caller")
            return
        }
        let job = await coordinator.snapshot().first(where: { $0.key == key })
        #expect(job?.state == .failed)
        #expect(job?.errorMessage?.contains("删除失败") == true)
    }
}

private func restoredJob(gid: Int64, token: String, title: String) -> DownloadJob {
    let key = GalleryKey(gid: gid, token: token)
    return DownloadJob(
        key: key,
        title: title,
        pages: [GalleryPageDescriptor(
            galleryKey: key,
            index: 0,
            pageURL: URL(string: "https://example.invalid/\(gid)/0")!
        )]
    )
}

private actor DownloadSaveProbe {
    private(set) var jobs: [DownloadJob] = []
    var count: Int { jobs.count }

    func record(_ job: DownloadJob) {
        jobs.append(job)
    }
}

private actor DownloadLoadProbe {
    private(set) var keys: [GalleryKey] = []
    var count: Int { keys.count }

    func record(_ key: GalleryKey) {
        keys.append(key)
    }
}

private actor ActiveGalleryProbe {
    private var active: Set<GalleryKey> = []
    private(set) var maximumActiveGalleryCount = 0

    func enter(_ key: GalleryKey) {
        active.insert(key)
        maximumActiveGalleryCount = max(maximumActiveGalleryCount, active.count)
    }

    func leave(_ key: GalleryKey) {
        active.remove(key)
    }
}

private actor RetryCounter {
    private(set) var value = 0

    func next() -> Int {
        value += 1
        return value
    }
}
