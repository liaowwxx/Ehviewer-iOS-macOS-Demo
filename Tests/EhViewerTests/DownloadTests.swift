import Foundation
import Testing
import EHDomain
import EHDownloads
@testable import EhViewerPreview

private actor DemandDownloadProbe {
    let key: GalleryKey
    let total: Int
    private var completed: Set<Int> = []
    private(set) var requests: [Int] = []
    private(set) var requestedTooEarly = false
    private(set) var fullSaves = 0

    init(key: GalleryKey, total: Int) {
        self.key = key
        self.total = total
    }

    func batch(startingAt index: Int) -> [GalleryPageDescriptor] {
        if !(0..<index).allSatisfy({ completed.contains($0) }) { requestedTooEarly = true }
        requests.append(index)
        return (index..<min(index + 20, total)).map {
            GalleryPageDescriptor(galleryKey: key, index: $0, pageURL: URL(string: "https://example.invalid/\($0)")!)
        }
    }

    func complete(_ index: Int) { completed.insert(index) }
    func save(_ job: DownloadJob) { fullSaves += 1 }
}

struct DownloadTests {
    @Test("Partial download jobs retain their source site from persisted page URLs")
    func partialDownloadSourceSite() {
        let key = GalleryKey(gid: 1007, token: "site-source")
        let page = GalleryPageDescriptor(galleryKey: key, index: 0, pageURL: URL(string: "https://exhentai.org/s/token/1007-1")!)
        let job = DownloadJob(key: key, title: "Partial", pages: [page], totalPageCount: 1001)
        #expect(job.sourceSite == .exHentai)
        #expect(DownloadJob(key: key, title: "Empty", pages: []).sourceSite == nil)
    }

    @Test("Local lists ignore invisible progress but apply completion and redownload transitions")
    func localListDownloadUpdatePolicy() {
        let key = GalleryKey(gid: 1005, token: "local-list")
        var running = DownloadJob(key: key, title: "Running", pages: [])
        running.state = .running
        var completed = running
        completed.state = .completed
        #expect(DownloadsPage.local.shouldApplyUpdate(running, previous: nil) == false)
        #expect(DownloadsPage.local.shouldApplyUpdate(running, previous: running) == false)
        #expect(DownloadsPage.local.shouldApplyUpdate(completed, previous: running))
        #expect(DownloadsPage.local.shouldApplyUpdate(running, previous: completed))
        #expect(DownloadsPage.downloading.shouldApplyUpdate(running, previous: nil))
    }

    @Test("Pausing while page-list pagination is suspended keeps the partial job paused", .timeLimit(.minutes(1)))
    func pauseDuringPageListLoad() async throws {
        let key = GalleryKey(gid: 1003, token: "pause-demand")
        let started = AsyncStream<Int>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let initial = GalleryPageDescriptor(galleryKey: key, index: 0, pageURL: URL(string: "https://example.invalid/0")!)
        let coordinator = DownloadCoordinator(
            pageLoader: { _ in Data("page".utf8) },
            pageListLoader: { _, index in
                started.continuation.yield(index)
                for await _ in release.stream { break }
                try Task.checkCancellation()
                return [GalleryPageDescriptor(galleryKey: key, index: index, pageURL: URL(string: "https://example.invalid/\(index)")!)]
            }
        )
        await coordinator.enqueue(key: key, title: "Pause", pages: [initial], totalPageCount: 1001)
        var iterator = started.stream.makeAsyncIterator()
        #expect(await iterator.next() == 1)
        await coordinator.pause(key)
        release.continuation.finish()
        let job = try #require(await coordinator.job(for: key))
        #expect(job.state == .paused)
        #expect(job.pages.map(\.index) == [0])
        #expect(job.completedPageIndexes == [0])
    }

    @Test("Invalid pagination fails instead of completing a partial job", .timeLimit(.minutes(1)))
    func invalidDownloadPaginationFails() async throws {
        let key = GalleryKey(gid: 1004, token: "invalid-demand")
        let coordinator = DownloadCoordinator(
            pageLoader: { _ in Data("page".utf8) },
            pageListLoader: { _, _ in [] }
        )
        let events = await coordinator.events()
        await coordinator.enqueue(key: key, title: "Invalid", pages: [], totalPageCount: 1001)
        for await event in events {
            if case .changed(let job) = event, job.state == .failed {
                #expect(job.completedPageIndexes.isEmpty)
                #expect(job.errorMessage != nil)
                return
            }
        }
        Issue.record("Expected a pagination failure")
    }

    @Test("Large downloads acquire page lists only after downloading the current batch", .timeLimit(.minutes(1)))
    func largeDownloadPageListsAreDemandDriven() async throws {
        let key = GalleryKey(gid: 1001, token: "demand")
        let probe = DemandDownloadProbe(key: key, total: 1001)
        let coordinator = DownloadCoordinator(
            maxConcurrentPages: 3,
            pageLoader: { _ in Data("page".utf8) },
            pageListLoader: { _, index in await probe.batch(startingAt: index) },
            pageCompletionPersistence: { _, index in await probe.complete(index) },
            persistence: { job in await probe.save(job) }
        )
        let events = await coordinator.events()
        await coordinator.enqueue(key: key, title: "Large", pages: await probe.batch(startingAt: 0), totalPageCount: 1001)
        for await event in events {
            if case .changed(let job) = event, job.state == .completed {
                #expect(job.pages.count == 1001)
                #expect(job.completedPageIndexes.count == 1001)
                #expect(job.progress == 1)
                #expect(await probe.requests == Array(stride(from: 0, to: 1001, by: 20)))
                #expect(await probe.requestedTooEarly == false)
                #expect(await probe.fullSaves < 60)
                return
            }
        }
        Issue.record("Download event stream ended without completion")
    }

    @Test("Resumed partial jobs obtain missing page lists before completion", .timeLimit(.minutes(1)))
    func resumedPartialDownloadLoadsMissingPages() async throws {
        let key = GalleryKey(gid: 1002, token: "resume-demand")
        let probe = DemandDownloadProbe(key: key, total: 23)
        var job = DownloadJob(key: key, title: "Partial", pages: await probe.batch(startingAt: 0), totalPageCount: 23)
        job.completedPageIndexes = Set(0..<20)
        job.state = .paused
        #expect(job.progress == Double(20) / 23)
        for index in 0..<20 { await probe.complete(index) }
        let coordinator = DownloadCoordinator(
            pageLoader: { _ in Data("page".utf8) },
            pageListLoader: { _, index in await probe.batch(startingAt: index) }
        )
        let events = await coordinator.events()
        await coordinator.restore([job])
        await coordinator.resume(key)
        for await event in events {
            if case .changed(let updated) = event, updated.state == .completed {
                #expect(updated.completedPageIndexes == Set(0..<23))
                #expect(await probe.requests == [0, 20])
                return
            }
        }
        Issue.record("Download event stream ended without completion")
    }

    @Test("Local download titles follow the Japanese-title preference")
    func localDownloadTitlePreference() {
        let key = GalleryKey(gid: 1, token: "local-title")
        let job = DownloadJob(
            key: key,
            title: "English title",
            japaneseTitle: "日本語タイトル",
            pages: []
        )

        #expect(job.displayTitle(showJapaneseTitle: false) == "English title")
        #expect(job.displayTitle(showJapaneseTitle: true) == "日本語タイトル")
    }

    @Test("Download search matches raw gallery tags")
    func downloadTagSearch() {
        let key = GalleryKey(gid: 2, token: "tag-search")
        let job = DownloadJob(
            key: key,
            title: "Title",
            tags: ["artist:sample", "female:sub tag"],
            pages: []
        )

        #expect(job.containsTag("artist:sample"))
        #expect(job.containsTag("sub tag"))
        #expect(job.containsTag("missing") == false)
    }

    @Test("Download search matches local metadata and multiple selected tags")
    func downloadSearchMatchesLocalMetadataAndMultipleTags() {
        let key = GalleryKey(gid: 3, token: "multi-tag-search")
        let job = DownloadJob(
            key: key,
            title: "Stored title",
            pages: []
        )
        let summary = GallerySummary(
            key: key,
            title: "Stored title",
            tags: ["artist:sample", "female:sub tag"]
        )

        #expect(job.matchesSearch(
            query: #"a:"sample$" f:"sub tag$""#,
            summary: summary
        ))
        #expect(job.matchesSearch(
            query: #"a:"sample$" f:"missing$""#,
            summary: summary
        ) == false)
    }

    @Test("Downloads sort by rating with missing ratings last")
    func downloadSortByRating() {
        let lower = DownloadJob(
            key: GalleryKey(gid: 4, token: "lower-rating"),
            title: "Lower rating",
            pages: []
        )
        let higher = DownloadJob(
            key: GalleryKey(gid: 5, token: "higher-rating"),
            title: "Higher rating",
            pages: []
        )
        let missing = DownloadJob(
            key: GalleryKey(gid: 6, token: "missing-rating"),
            title: "Missing rating",
            pages: []
        )
        let summaries = [
            lower.key: GallerySummary(key: lower.key, title: lower.title, rating: 3.5),
            higher.key: GallerySummary(key: higher.key, title: higher.title, rating: 4.5)
        ]

        let sorted = [lower, missing, higher].sorted {
            DownloadSortOrder.rating.areInIncreasingOrder($0, $1, summaries: summaries)
        }

        #expect(sorted.map(\.key) == [higher.key, lower.key, missing.key])
    }

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

    @Test("Local download usage counts only galleries with readable pages")
    func localDownloadUsage() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehviewer-download-usage-\(UUID().uuidString)")
        let store = DownloadFileStore(root: root, minimumFreeBytes: 1)
        let localKey = GalleryKey(gid: 21, token: "local")
        let emptyKey = GalleryKey(gid: 22, token: "empty")
        let imageData = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))

        _ = try await store.write(imageData, for: localKey, pageIndex: 0)
        _ = try await store.write(imageData, for: localKey, pageIndex: 1)
        let usage = await store.localLibraryUsage(for: [emptyKey, localKey, localKey])

        #expect(usage.galleryKeys == [localKey])
        #expect(usage.galleryCount == 1)
        #expect(usage.byteCount == Int64(imageData.count * 2))
        try await store.remove(localKey)
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

    @Test("A deleted download is not resurrected by a stale persisted snapshot")
    func deletedDownloadIsNotResurrectedByRestore() async throws {
        let key = GalleryKey(gid: 25, token: "deleted-restore")
        let job = restoredJob(gid: key.gid, token: key.token, title: "Deleted")
        let coordinator = DownloadCoordinator(pageLoader: { _ in Data() })

        await coordinator.loadPersisted([job])
        #expect(await coordinator.snapshot().map(\.key) == [key])

        #expect(await coordinator.remove(key) == .removed)
        #expect(await coordinator.snapshot().isEmpty)

        // This simulates the startup restore task completing with a snapshot
        // fetched before the user pressed Delete.
        await coordinator.loadPersisted([job])
        #expect(await coordinator.snapshot().isEmpty)

        // Removing a gallery must not permanently block a deliberate new
        // download of the same gallery.
        await coordinator.enqueue(key: key, title: "Downloaded again", pages: [])
        #expect(await coordinator.snapshot().map(\.key) == [key])
    }

    @Test("In-memory metadata merge avoids per-gallery persistence and events")
    func inMemoryMetadataMergeIsBatched() async throws {
        let saveProbe = DownloadSaveProbe()
        let first = restoredJob(gid: 22, token: "first", title: "First")
        let second = restoredJob(gid: 23, token: "second", title: "Second")
        let coordinator = DownloadCoordinator(
            pageLoader: { _ in Data() },
            persistence: { job in await saveProbe.record(job) }
        )
        let events = await coordinator.events()
        var iterator = events.makeAsyncIterator()
        await coordinator.loadPersisted([first, second])
        guard case .reset? = await iterator.next() else {
            Issue.record("bulk loading should publish its reset event")
            return
        }

        let refreshed = [first, second].map { job in
            GallerySummary(
                key: job.key,
                title: "Refreshed \(job.key.gid)",
                tags: ["artist:refreshed"],
                metadataCompleteness: .complete
            )
        }
        await coordinator.mergeMetadataInMemory(refreshed)

        #expect(await saveProbe.count == 0)
        #expect(await coordinator.job(for: first.key)?.title == "Refreshed 22")
        #expect(await coordinator.job(for: second.key)?.tags == ["artist:refreshed"])
        guard case let .reset(jobs)? = await iterator.next() else {
            Issue.record("batched metadata merge should publish one reset event")
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

    @Test("A resolvable page replaces a restored placeholder at the same index")
    func mergeRestoredReplacesPlaceholderPage() async throws {
        let key = GalleryKey(gid: 24, token: "placeholder-upgrade")
        let placeholder = GalleryPageDescriptor(
            galleryKey: key,
            index: 0,
            pageURL: URL(string: "https://example.invalid/g/24/placeholder-upgrade/#restored-1")!
        )
        let resolvable = GalleryPageDescriptor(
            galleryKey: key,
            index: 0,
            pageURL: URL(string: "https://example.invalid/s/page-token/24-1")!
        )
        let existing = DownloadJob(key: key, title: "Existing", pages: [placeholder])
        let incoming = DownloadJob(key: key, title: "Incoming", pages: [resolvable])

        let coordinator = DownloadCoordinator(pageLoader: { _ in Data() })
        await coordinator.restore([existing])
        await coordinator.mergeRestored([incoming])

        #expect(await coordinator.job(for: key)?.pages.first?.pageURL == resolvable.pageURL)
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

    @Test("Download coordinator retries ordinary network failures")
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

    @Test("Transient downloads continue retrying beyond the old three-attempt limit", .timeLimit(.minutes(1)))
    func retriesBeyondThreeAttempts() async throws {
        let attempts = RetryCounter()
        let key = GalleryKey(gid: 120, token: "continued-retry")
        let page = GalleryPageDescriptor(galleryKey: key, index: 0, pageURL: URL(string: "https://example.invalid/retry")!)
        let coordinator = DownloadCoordinator { _ in
            if await attempts.next() < 4 { throw URLError(.timedOut) }
            return Data([1])
        }
        let events = await coordinator.events()
        await coordinator.enqueue(key: key, title: "Retry", pages: [page])
        for await event in events {
            if case .changed(let job) = event, job.state == .completed {
                #expect(await attempts.value == 4)
                #expect(job.completedPageIndexes == [0])
                return
            }
        }
        Issue.record("download event stream ended before completion")
    }

    @Test("Pausing a transiently failing download stops automatic retry", .timeLimit(.minutes(1)))
    func pauseStopsAutomaticRetry() async throws {
        let attempts = RetryCounter()
        let key = GalleryKey(gid: 121, token: "pause-retry")
        let page = GalleryPageDescriptor(galleryKey: key, index: 0, pageURL: URL(string: "https://example.invalid/retry")!)
        let (failures, continuation) = AsyncStream<Void>.makeStream()
        let coordinator = DownloadCoordinator { _ in
            _ = await attempts.next()
            continuation.yield(())
            throw EHError.networkFailed("temporary")
        }
        await coordinator.enqueue(key: key, title: "Retry", pages: [page])
        for await _ in failures { break }
        await coordinator.pause(key)
        let count = await attempts.value
        try await Task.sleep(for: .milliseconds(350))
        #expect(await attempts.value == count)
        #expect(await coordinator.job(for: key)?.state == .paused)
        continuation.finish()
    }

    @Test("Completed pages are persisted while another page in the batch is pending", .timeLimit(.minutes(1)))
    func savesPartialBatchProgress() async throws {
        let gate = DownloadGate()
        let key = GalleryKey(gid: 122, token: "partial-batch")
        let pages = (0..<2).map {
            GalleryPageDescriptor(galleryKey: key, index: $0, pageURL: URL(string: "https://example.invalid/\($0)")!)
        }
        let (saved, continuation) = AsyncStream<DownloadJob>.makeStream()
        let coordinator = DownloadCoordinator(
            pageLoader: { page in
                if page.index == 1 { await gate.wait() }
                try Task.checkCancellation()
                return Data([1])
            },
            persistence: { job in continuation.yield(job) }
        )
        await coordinator.enqueue(key: key, title: "Partial", pages: pages)
        for await job in saved where job.completedPageIndexes == [0] {
            #expect(job.state == .running)
            await coordinator.pause(key)
            await gate.open()
            continuation.finish()
            return
        }
        await gate.open()
        Issue.record("partial batch was not persisted")
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

    @Test("Local downloads sort by gallery upload time with missing metadata last")
    func sortsByPostedTime() {
        let older = DownloadJob(
            key: GalleryKey(gid: 15, token: "older"),
            title: "Older",
            pages: [],
            addedAt: Date(timeIntervalSince1970: 3)
        )
        let newer = DownloadJob(
            key: GalleryKey(gid: 16, token: "newer"),
            title: "Newer",
            pages: [],
            addedAt: Date(timeIntervalSince1970: 1)
        )
        let missing = DownloadJob(
            key: GalleryKey(gid: 17, token: "missing"),
            title: "Missing",
            pages: [],
            addedAt: Date(timeIntervalSince1970: 4)
        )
        let summaries = [
            older.key: GallerySummary(
                key: older.key,
                title: older.title,
                postedAt: Date(timeIntervalSince1970: 1)
            ),
            newer.key: GallerySummary(
                key: newer.key,
                title: newer.title,
                postedAt: Date(timeIntervalSince1970: 2)
            )
        ]

        #expect(
            [older, newer, missing]
                .sorted { DownloadSortOrder.addedNewest.areInIncreasingOrder($0, $1, summaries: summaries) }
                .map(\.key) == [newer.key, older.key, missing.key]
        )
        #expect(
            [older, newer, missing]
                .sorted { DownloadSortOrder.addedOldest.areInIncreasingOrder($0, $1, summaries: summaries) }
                .map(\.key) == [older.key, newer.key, missing.key]
        )
    }

    @Test("本地画廊可按加入下载队列的时间排序")
    func sortsByTimeAddedToDownloads() {
        let firstAdded = DownloadJob(
            key: GalleryKey(gid: 18, token: "first-added"),
            title: "First",
            pages: [],
            addedAt: Date(timeIntervalSince1970: 1)
        )
        let lastAdded = DownloadJob(
            key: GalleryKey(gid: 19, token: "last-added"),
            title: "Last",
            pages: [],
            addedAt: Date(timeIntervalSince1970: 2)
        )

        #expect(
            [firstAdded, lastAdded]
                .sorted { DownloadSortOrder.downloadAddedNewest.areInIncreasingOrder($0, $1) }
                .map(\.key) == [lastAdded.key, firstAdded.key]
        )
        #expect(
            [firstAdded, lastAdded]
                .sorted { DownloadSortOrder.downloadAddedOldest.areInIncreasingOrder($0, $1) }
                .map(\.key) == [firstAdded.key, lastAdded.key]
        )
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

    @Test("Bulk removal reports progress and publishes one removal event")
    func bulkRemovalReportsProgress() async throws {
        let keys = (0..<4).map { GalleryKey(gid: Int64(40 + $0), token: "bulk-\($0)") }
        let batchProbe = BatchRemovalProbe()
        let progressProbe = RemovalProgressProbe()
        let coordinator = DownloadCoordinator(
            pageLoader: { _ in Data() },
            batchRemoval: { keys in
                await batchProbe.record(keys)
            }
        )
        let jobs = keys.map { key -> DownloadJob in
            var job = DownloadJob(key: key, title: "Bulk \(key.gid)", pages: [])
            job.state = .paused
            return job
        }
        await coordinator.restore(jobs)
        let events = await coordinator.events()

        let result = await coordinator.remove(keys) { progress in
            await progressProbe.record(progress)
        }

        #expect(result.requestedCount == keys.count)
        #expect(result.removedCount == keys.count)
        #expect(result.failures.isEmpty)
        #expect(result.cancelled == false)
        #expect(await batchProbe.keys == Set(keys))
        #expect((await coordinator.snapshot()).isEmpty)

        let progress = await progressProbe.values
        #expect(progress.first == DownloadRemovalProgress(completed: 0, total: keys.count))
        #expect(progress.last == DownloadRemovalProgress(completed: keys.count, total: keys.count))
        #expect(zip(progress, progress.dropFirst()).allSatisfy { $0.completed <= $1.completed })

        var iterator = events.makeAsyncIterator()
        guard case let .removedMany(removedKeys)? = await iterator.next() else {
            Issue.record("bulk removal should publish one removedMany event")
            return
        }
        #expect(removedKeys == keys)
    }

    @Test("Bulk removal removes downloaded files before persisting the batch")
    func bulkRemovalDeletesFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ehviewer-bulk-removal-\(UUID().uuidString)")
        let store = DownloadFileStore(root: root, minimumFreeBytes: 1)
        let keys = (0..<2).map { GalleryKey(gid: Int64(50 + $0), token: "file-bulk-\($0)") }
        let imageData = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))

        for key in keys {
            _ = try await store.write(imageData, for: key, pageIndex: 0)
        }

        let coordinator = DownloadCoordinator(
            fileStore: store,
            batchRemoval: { _ in }
        )
        await coordinator.restore(keys.map { DownloadJob(key: $0, title: "File bulk", pages: []) })

        let result = await coordinator.remove(keys)

        #expect(result.removedCount == keys.count)
        #expect(result.failures.isEmpty)
        for key in keys {
            #expect(await store.contains(key, pageIndex: 0) == false)
            #expect(FileManager.default.fileExists(atPath: await store.finalURL(for: key, pageIndex: 0).path) == false)
        }
    }

    @Test("Redownload deletes local pages and restarts the job from scratch")
    func redownloadClearsFilesAndRestarts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ehviewer-redownload-\(UUID().uuidString)")
        let store = DownloadFileStore(root: root, minimumFreeBytes: 1)
        let key = GalleryKey(gid: 30, token: "redownload")
        let pages = (0..<3).map { index in
            GalleryPageDescriptor(
                galleryKey: key,
                index: index,
                pageURL: URL(string: "https://example.invalid/redownload/\(index)")!
            )
        }
        let imageData = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        let gate = DownloadGate()
        await gate.open()
        let coordinator = DownloadCoordinator(
            maxConcurrentPages: 2,
            pageLoader: { _ in
                await gate.wait()
                return imageData
            },
            fileStore: store
        )
        await coordinator.enqueue(key: key, title: "Redownload", pages: pages)

        for _ in 0..<100 {
            if await coordinator.snapshot().first?.state == .completed { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await coordinator.snapshot().first?.state == .completed)
        #expect(try await store.readablePageIndexes(for: key, pageIndexes: [0, 1, 2]) == [0, 1, 2])

        // Hold the restarted run at the loader so the reset stays observable.
        await gate.close()
        await coordinator.redownload(key)

        #expect(try await store.readablePageIndexes(for: key, pageIndexes: [0, 1, 2]).isEmpty)
        #expect(await coordinator.snapshot().first?.completedPageIndexes.isEmpty == true)

        await gate.open()
        for _ in 0..<100 {
            if let job = await coordinator.snapshot().first(where: { $0.key == key }),
               job.state == .completed {
                #expect(job.completedPageIndexes == [0, 1, 2])
                #expect(try await store.readablePageIndexes(for: key, pageIndexes: [0, 1, 2]) == [0, 1, 2])
                try? FileManager.default.removeItem(at: root)
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        try? FileManager.default.removeItem(at: root)
        Issue.record("redownloaded job did not complete within the test budget")
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

private actor BatchRemovalProbe {
    private(set) var keys: Set<GalleryKey> = []

    func record(_ keys: Set<GalleryKey>) {
        self.keys = keys
    }
}

private actor RemovalProgressProbe {
    private(set) var values: [DownloadRemovalProgress] = []

    func record(_ value: DownloadRemovalProgress) {
        values.append(value)
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

/// Lets a test hold a download run at the page loader so that a restarted
/// job stays in its reset state while assertions run.
private actor DownloadGate {
    private var isOpen = false

    func open() {
        isOpen = true
    }

    func close() {
        isOpen = false
    }

    func wait() async {
        while isOpen == false {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

private actor RetryCounter {
    private(set) var value = 0

    func next() -> Int {
        value += 1
        return value
    }
}
