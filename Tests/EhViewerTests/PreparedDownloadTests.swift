import Foundation
import Testing
import EHDomain
import EHDownloads

private actor PreparationProbe: DownloadTransferService {
    let submissions = AsyncStream<DownloadTransferTicket>.makeStream()
    let resolutions = AsyncStream<Int>.makeStream()
    var activeResolvers = 0
    var maximumResolvers = 0
    var resolverWaiters: [CheckedContinuation<Void, Never>] = []
    var blockResolvers = false
    var blockedIndexes: Set<Int> = []
    var finished: [UUID: Result<Void, EHError>] = [:]
    var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    var tickets: [DownloadTransferTicket] = []
    var cancelled: [GalleryKey] = []
    var restored: [DownloadTransferTicket] = []
    var automaticError: EHError?

    func begin(_ job: DownloadJob) -> DownloadTransferBatch {
        DownloadTransferBatch(id: restored.first?.batchID ?? UUID(), tickets: restored)
    }

    func blockResolution() { blockResolvers = true }
    func blockResolution(of index: Int) { blockedIndexes.insert(index) }
    func failEveryTransfer(_ error: EHError) { automaticError = error }
    func restore(_ ticket: DownloadTransferTicket) { restored = [ticket] }

    func prepare(_ page: GalleryPageDescriptor, batchID: UUID, attempt: Int) async throws -> DownloadTransferTicket {
        activeResolvers += 1
        maximumResolvers = max(maximumResolvers, activeResolvers)
        resolutions.continuation.yield(page.index)
        if blockResolvers || blockedIndexes.contains(page.index) { await withCheckedContinuation { resolverWaiters.append($0) } }
        activeResolvers -= 1
        try Task.checkCancellation()
        let ticket = DownloadTransferTicket(
            batchID: batchID, page: page,
            image: GalleryPageImage(galleryKey: page.galleryKey, index: page.index, imageURL: URL(string: "https://example.invalid/image")!, skipHathKey: "next-node"),
            attempt: attempt, taskIdentifier: tickets.count + 1
        )
        tickets.append(ticket)
        submissions.continuation.yield(ticket)
        return ticket
    }

    func releaseResolvers() {
        blockResolvers = false
        blockedIndexes.removeAll()
        let waiting = resolverWaiters
        resolverWaiters.removeAll()
        waiting.forEach { $0.resume() }
    }

    func finish(_ ticket: DownloadTransferTicket) async throws {
        if let automaticError { throw automaticError }
        if let result = finished[ticket.id] { return try result.get() }
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { waiters[ticket.id] = $0 }
        } onCancel: {
            Task { await self.cancelWaiter(ticket.id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    func complete(_ ticket: DownloadTransferTicket, error: EHError? = nil) {
        let result: Result<Void, EHError> = error.map(Result.failure) ?? .success(())
        finished[ticket.id] = result
        if let waiter = waiters.removeValue(forKey: ticket.id) {
            switch result {
            case .success: waiter.resume()
            case .failure(let error): waiter.resume(throwing: error)
            }
        }
    }

    func cancel(_ key: GalleryKey, preservingStagedFiles: Bool) {
        cancelled.append(key)
        for ticket in tickets where ticket.page.galleryKey == key { cancelWaiter(ticket.id) }
    }

    func setPreparationEnabled(_ enabled: Bool) {}
}

struct PreparedDownloadTests {
    private func pages(_ key: GalleryKey, _ range: Range<Int>) -> [GalleryPageDescriptor] {
        range.map { GalleryPageDescriptor(galleryKey: key, index: $0, pageURL: URL(string: "https://e-hentai.org/s/page/\(key.gid)-\($0 + 1)")!) }
    }

    @Test("Resolution and pagination continue while every image transfer is blocked", .timeLimit(.minutes(1)))
    func preparesWholeGalleryBeforeTransfersFinish() async throws {
        let key = GalleryKey(gid: 801, token: "independent")
        let probe = PreparationProbe()
        await probe.blockResolution()
        let coordinator = DownloadCoordinator(
            transferService: probe,
            pageListLoader: { job, index in pages(job.key, index..<min(index + 20, job.totalPageCount)) }
        )
        let events = await coordinator.events()
        await coordinator.enqueue(key: key, title: "A", pages: pages(key, 0..<20), totalPageCount: 61)
        let second = GalleryKey(gid: 802, token: "queued")
        await coordinator.enqueue(key: second, title: "B", pages: pages(second, 0..<1))
        var starts = probe.resolutions.stream.makeAsyncIterator()
        for _ in 0..<3 { #expect(await starts.next() != nil) }
        #expect(await probe.activeResolvers == 3)
        await probe.releaseResolvers()
        for await event in events {
            if case .changed(let job) = event, job.key == key, job.preparedPageIndexes.count == 61 {
                #expect(job.completedPageIndexes.isEmpty)
                #expect(job.pages.count == 61)
                #expect(await probe.maximumResolvers == 3)
                #expect(await coordinator.job(for: second)?.state == .queued)
                #expect(await probe.tickets.allSatisfy { $0.page.galleryKey == key })
                await coordinator.stopAll()
                return
            }
        }
        Issue.record("Preparation did not complete")
    }

    @Test("The first image is submitted without waiting for later page lists", .timeLimit(.minutes(1)))
    func firstImageDoesNotWaitForPagination() async throws {
        let key = GalleryKey(gid: 803, token: "first")
        let probe = PreparationProbe()
        let gate = AsyncStream<Void>.makeStream()
        let coordinator = DownloadCoordinator(transferService: probe, pageListLoader: { _, _ in
            for await _ in gate.stream { break }
            try Task.checkCancellation()
            return []
        })
        await coordinator.enqueue(key: key, title: "First", pages: pages(key, 0..<1), totalPageCount: 21)
        var submissions = probe.submissions.stream.makeAsyncIterator()
        #expect(await submissions.next()?.page.index == 0)
        await coordinator.stopAll()
        gate.continuation.finish()
    }

    @Test("Suspending preparation does not cancel already submitted transfers", .timeLimit(.minutes(1)))
    func preparationSuspensionKeepsTransfers() async throws {
        let key = GalleryKey(gid: 804, token: "suspend")
        let probe = PreparationProbe()
        let coordinator = DownloadCoordinator(transferService: probe)
        let events = await coordinator.events()
        await coordinator.enqueue(key: key, title: "Suspend", pages: pages(key, 0..<3))
        var submitted = probe.submissions.stream.makeAsyncIterator()
        var tickets: [DownloadTransferTicket] = []
        for _ in 0..<3 { tickets.append(try #require(await submitted.next())) }
        await coordinator.setPreparationEnabled(false)
        #expect(await probe.cancelled.isEmpty)
        for ticket in tickets { await probe.complete(ticket) }
        for await event in events {
            if case .changed(let job) = event, job.state == .completed {
                #expect(job.completedPageIndexes == Set(0..<3))
                return
            }
        }
        Issue.record("Submitted transfers did not finish")
    }

    @Test("Restored system tasks are awaited without resolving or submitting duplicates", .timeLimit(.minutes(1)))
    func restoresExistingTask() async throws {
        let key = GalleryKey(gid: 805, token: "restore")
        let page = pages(key, 0..<1)[0]
        let ticket = DownloadTransferTicket(batchID: UUID(), page: page, image: GalleryPageImage(galleryKey: key, index: 0, imageURL: page.pageURL), taskIdentifier: 42)
        let probe = PreparationProbe()
        await probe.restore(ticket)
        await probe.complete(ticket)
        let coordinator = DownloadCoordinator(transferService: probe)
        let events = await coordinator.events()
        await coordinator.enqueue(key: key, title: "Restore", pages: [page])
        for await event in events {
            if case .changed(let job) = event, job.state == .completed {
                #expect(await probe.tickets.isEmpty)
                #expect(job.completedPageIndexes == [0])
                return
            }
        }
        Issue.record("Restored transfer did not finish")
    }

    @Test("Invalid media re-resolves with the alternate H@H node", .timeLimit(.minutes(1)))
    func invalidMediaChangesNode() async throws {
        let key = GalleryKey(gid: 806, token: "retry")
        let probe = PreparationProbe()
        let coordinator = DownloadCoordinator(transferService: probe)
        let events = await coordinator.events()
        await coordinator.enqueue(key: key, title: "Retry", pages: pages(key, 0..<1))
        var submitted = probe.submissions.stream.makeAsyncIterator()
        let first = try #require(await submitted.next())
        await probe.complete(first, error: .parsingFailed("Invalid media"))
        let replacement = try #require(await submitted.next())
        #expect(replacement.attempt == 1)
        #expect(URLComponents(url: replacement.page.pageURL, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "nl", value: "next-node")) == true)
        await probe.complete(replacement)
        for await event in events {
            if case .changed(let job) = event, job.state == .completed {
                #expect(job.completedPageIndexes == [0])
                return
            }
        }
    }

    @Test("Invalid media stops after five attempts", .timeLimit(.minutes(1)))
    func invalidMediaAttemptLimit() async throws {
        let key = GalleryKey(gid: 807, token: "limit")
        let probe = PreparationProbe()
        await probe.failEveryTransfer(.parsingFailed("Invalid media"))
        let coordinator = DownloadCoordinator(transferService: probe)
        let events = await coordinator.events()
        await coordinator.enqueue(key: key, title: "Limit", pages: pages(key, 0..<1))
        for await event in events {
            if case .changed(let job) = event, job.state == .failed {
                #expect(await probe.tickets.count == 5)
                #expect(job.completedPageIndexes.isEmpty)
                return
            }
        }
    }

    @Test("Pausing rejects the late result of an outstanding resolution", .timeLimit(.minutes(1)))
    func pauseDuringResolution() async throws {
        let key = GalleryKey(gid: 808, token: "pause")
        let probe = PreparationProbe()
        await probe.blockResolution()
        let coordinator = DownloadCoordinator(transferService: probe)
        await coordinator.enqueue(key: key, title: "Pause", pages: pages(key, 0..<1))
        var starts = probe.resolutions.stream.makeAsyncIterator()
        #expect(await starts.next() == 0)
        await coordinator.pause(key)
        await probe.releaseResolvers()
        #expect(await coordinator.job(for: key)?.state == .paused)
        #expect(await coordinator.job(for: key)?.completedPageIndexes.isEmpty == true)
        #expect(await probe.cancelled.contains(key))
    }

    @Test("One slow resolver does not stall other resolver slots", .timeLimit(.minutes(1)))
    func slowResolverDoesNotBlockPreparation() async throws {
        let key = GalleryKey(gid: 809, token: "slow")
        let probe = PreparationProbe()
        await probe.blockResolution(of: 0)
        let coordinator = DownloadCoordinator(transferService: probe)
        await coordinator.enqueue(key: key, title: "Slow", pages: pages(key, 0..<10))
        var submitted = probe.submissions.stream.makeAsyncIterator()
        for _ in 0..<9 { #expect(await submitted.next()?.page.index != 0) }
        #expect(await probe.tickets.count == 9)
        #expect(await probe.maximumResolvers <= 3)
        await coordinator.stopAll()
        await probe.releaseResolvers()
    }

    @Test("Transient transfer failures resolve fresh links and retry", .timeLimit(.minutes(1)))
    func transientTransferRetry() async throws {
        let key = GalleryKey(gid: 810, token: "network")
        let probe = PreparationProbe()
        let coordinator = DownloadCoordinator(transferService: probe)
        let events = await coordinator.events()
        await coordinator.enqueue(key: key, title: "Network", pages: pages(key, 0..<1))
        var submitted = probe.submissions.stream.makeAsyncIterator()
        let first = try #require(await submitted.next())
        await probe.complete(first, error: .networkFailed("Connection lost"))
        let retry = try #require(await submitted.next())
        #expect(retry.id != first.id)
        #expect(retry.attempt == 0)
        await probe.complete(retry)
        for await event in events {
            if case .changed(let job) = event, job.state == .completed { return }
        }
    }

    @Test("Authentication, limits and disk errors retain their actionable states", .timeLimit(.minutes(1)), arguments: [
        (EHError.authenticationRequired, DownloadState.authenticationRequired),
        (.httpStatus(429), .rateLimited), (.httpStatus(509), .bandwidthLimited), (.diskSpaceLow, .paused)
    ])
    func actionableErrors(_ error: EHError, _ expected: DownloadState) async throws {
        let key = GalleryKey(gid: 811, token: UUID().uuidString)
        let probe = PreparationProbe()
        await probe.failEveryTransfer(error)
        let coordinator = DownloadCoordinator(transferService: probe)
        let events = await coordinator.events()
        await coordinator.enqueue(key: key, title: "Error", pages: pages(key, 0..<1))
        for await event in events {
            if case .changed(let job) = event, job.state == expected {
                #expect(job.completedPageIndexes.isEmpty)
                #expect(job.errorMessage != nil)
                #expect(await probe.tickets.count == 1)
                return
            }
        }
    }
}
