import Foundation
import Testing
import EHDomain
import EHDownloads

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
        let finalURL = try await store.write(Data("payload".utf8), for: key, pageIndex: 0)
        #expect(FileManager.default.fileExists(atPath: finalURL.path))
        #expect(FileManager.default.fileExists(atPath: finalURL.appendingPathExtension("part").path) == false)
        #expect(try Data(contentsOf: finalURL) == Data("payload".utf8))
        try await store.remove(key)
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
