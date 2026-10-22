import Foundation
import Testing
import EHDomain
@testable import EHDownloads

private actor FileDeliveryProbe {
    let entered = AsyncStream<Void>.makeStream()
    let release = AsyncStream<Void>.makeStream()
    var block = false
    var failure: EHError?
    var calls = 0

    func configure(block: Bool = false, failure: EHError? = nil) {
        self.block = block
        self.failure = failure
    }

    func save(_ ticket: DownloadTransferTicket, _ url: URL) async throws {
        calls += 1
        entered.continuation.yield(())
        if block { for await _ in release.stream { break } }
        if let failure { throw failure }
    }
}

struct BackgroundTransferTests {
    private enum SubmissionProbeError: Error {
        case stoppedBeforeResume
    }

    private struct JournalSnapshot: Decodable {
        struct Batch: Decodable {
            struct Entry: Decodable {
                let ticket: DownloadTransferTicket
                let completed: Bool
            }
            let entries: [String: Entry]
        }
        let batches: [String: Batch]
    }

    private struct Fixture {
        let root: URL
        let ticket: DownloadTransferTicket
        let receipt: BackgroundDownloadSession.Receipt
        let job: DownloadJob
    }

    private func fixture(hasReceipt: Bool = true, totalPageCount: Int = 1) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EHBackground-\(UUID().uuidString)")
        let staging = root.appendingPathComponent("Staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let key = GalleryKey(gid: 901, token: "journal")
        let page = GalleryPageDescriptor(galleryKey: key, index: 0, pageURL: URL(string: "https://e-hentai.org/s/page/901-1")!)
        let ticket = DownloadTransferTicket(batchID: UUID(), page: page, image: GalleryPageImage(galleryKey: key, index: 0, imageURL: URL(string: "https://example.invalid/image")!), taskIdentifier: 7)
        let receipt = BackgroundDownloadSession.Receipt(id: UUID(), taskDescription: ticket.id.uuidString, fileName: "saved.download", statusCode: 200, accessDenied: false)
        let ticketObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ticket))
        let batch: [String: Any] = ["id": ticket.batchID.uuidString, "key": try JSONSerialization.jsonObject(with: JSONEncoder().encode(key)), "active": true, "entries": [ticket.id.uuidString: ["ticket": ticketObject, "completed": false]]]
        let journal: [String: Any] = ["version": 1, "batches": [key.id: batch]]
        try JSONSerialization.data(withJSONObject: journal).write(to: root.appendingPathComponent("queue.json"))
        if hasReceipt {
            try Data("durable bytes".utf8).write(to: staging.appendingPathComponent(receipt.fileName))
            try JSONEncoder().encode(receipt).write(to: staging.appendingPathComponent(receipt.id.uuidString + ".json"))
        }
        return Fixture(root: root, ticket: ticket, receipt: receipt, job: DownloadJob(key: key, title: "Journal", pages: [page], totalPageCount: totalPageCount))
    }

    private func session(_ fixture: Fixture, probe: FileDeliveryProbe) -> BackgroundDownloadSession {
        BackgroundDownloadSession(
            identifier: "EHTest.\(UUID().uuidString)", root: fixture.root,
            resolver: { _ in throw EHError.parsingFailed("Unexpected resolver call") },
            requestBuilder: { _, _ in throw EHError.parsingFailed("Unexpected request") },
            fileCompletion: { try await probe.save($0, $1) }
        )
    }

    @Test("Preparing and replacing a task preserves a partial download without overlapping journal access", .timeLimit(.minutes(1)))
    func preparingPartialDownloadPreservesCompletedPages() async throws {
        let fixture = try fixture(totalPageCount: 2)
        let probe = FileDeliveryProbe()
        let session = BackgroundDownloadSession(
            identifier: "EHSubmissionTest.\(UUID().uuidString)", root: fixture.root,
            resolver: { page in
                GalleryPageImage(galleryKey: page.galleryKey, index: page.index, imageURL: URL(string: "https://example.invalid/image")!)
            },
            requestBuilder: { _, image in URLRequest(url: image.imageURL) },
            fileCompletion: { try await probe.save($0, $1) },
            // Exercise production URLSession task creation and journal writing,
            // then stop before resume so this test performs no network I/O.
            taskObserver: { _, _ in throw SubmissionProbeError.stoppedBeforeResume }
        )
        let batch = try await session.begin(fixture.job)
        let key = fixture.job.key
        let page = GalleryPageDescriptor(galleryKey: key, index: 1, pageURL: URL(string: "https://e-hentai.org/s/page/901-2")!)
        var previousAttemptID: UUID?
        for attempt in 0..<2 {
            await #expect(throws: SubmissionProbeError.stoppedBeforeResume) {
                _ = try await session.prepare(page, batchID: batch.id, attempt: attempt)
            }
            let snapshot = try JSONDecoder().decode(JournalSnapshot.self, from: Data(contentsOf: fixture.root.appendingPathComponent("queue.json")))
            let entries = try #require(snapshot.batches[key.id]?.entries)
            #expect(entries.count == 2)
            #expect(entries[fixture.ticket.id.uuidString]?.completed == true)
            let current = try #require(entries.values.first { $0.ticket.page.index == 1 })
            #expect(current.ticket.attempt == attempt)
            if let previousAttemptID { #expect(entries[previousAttemptID.uuidString] == nil) }
            previousAttemptID = current.ticket.id
        }
        try await session.finish(fixture.ticket)
        #expect(await probe.calls == 1)
        await session.cancelAll()
    }

    @Test("A durable receipt is saved once and remains completed across reconstruction", .timeLimit(.minutes(1)))
    func durableReceiptRecovery() async throws {
        let fixture = try fixture()
        let probe = FileDeliveryProbe()
        let first = session(fixture, probe: probe)
        await first.reconnect()
        await first.receive(fixture.receipt)
        try await first.finish(fixture.ticket)
        #expect(await probe.calls == 1)
        let restored = session(fixture, probe: probe)
        let batch = try await restored.begin(fixture.job)
        #expect(batch.tickets.map(\.id) == [fixture.ticket.id])
        try await restored.finish(fixture.ticket)
        #expect(await probe.calls == 1)
    }

    @Test("A missing system task without a receipt is prepared again", .timeLimit(.minutes(1)))
    func missingSystemTask() async throws {
        let fixture = try fixture(hasReceipt: false)
        let session = session(fixture, probe: FileDeliveryProbe())
        let batch = try await session.begin(fixture.job)
        #expect(batch.id == fixture.ticket.batchID)
        #expect(batch.tickets.isEmpty)
    }

    @Test("Cancelled batches reject late file callbacks", .timeLimit(.minutes(1)))
    func cancelledBatchRejectsReceipt() async throws {
        let fixture = try fixture()
        let probe = FileDeliveryProbe()
        let session = session(fixture, probe: probe)
        await session.cancel(fixture.job.key)
        await session.receive(fixture.receipt)
        #expect(await probe.calls == 0)
        await #expect(throws: CancellationError.self) { try await session.finish(fixture.ticket) }
        #expect(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Staging/saved.download").path))
    }

    @Test("Disk failures retain staged results for replay", .timeLimit(.minutes(1)))
    func diskFailureCanBeReplayed() async throws {
        let fixture = try fixture()
        let probe = FileDeliveryProbe()
        await probe.configure(failure: .diskSpaceLow)
        let session = session(fixture, probe: probe)
        await session.reconnect()
        await #expect(throws: EHError.diskSpaceLow) { try await session.finish(fixture.ticket) }
        #expect(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Staging/saved.download").path))
        await session.cancel(fixture.job.key)
        await probe.configure()
        let batch = try await session.begin(fixture.job)
        let rebound = try #require(batch.tickets.first)
        #expect(rebound.id != fixture.ticket.id)
        #expect(rebound.batchID != fixture.ticket.batchID)
        try await session.finish(rebound)
        #expect(await probe.calls == 2)
    }

    @MainActor
    @Test("Background completion waits for asynchronous file persistence and runs once", .timeLimit(.minutes(1)))
    func backgroundCompletionBarrier() async throws {
        let fixture = try fixture()
        let probe = FileDeliveryProbe()
        await probe.configure(block: true)
        let session = session(fixture, probe: probe)
        var calls = 0
        BackgroundDownloadEvents.register(identifier: session.identifier) { calls += 1 }
        let recovery = Task { await session.reconnect() }
        var entered = probe.entered.stream.makeAsyncIterator()
        #expect(await entered.next() != nil)
        await session.deliveryFinished()
        #expect(calls == 0)
        probe.release.continuation.yield(())
        await recovery.value
        // A recovery barrier queued after finishEvents proves all earlier
        // delivery and the main-actor completion have actually finished.
        await session.reconnect()
        #expect(calls == 1)
        await session.deliveryFinished()
        await session.reconnect()
        #expect(calls == 1)
    }

    @MainActor
    @Test("Session completion handlers do not overwrite another profile's handler")
    func independentCompletionHandlers() {
        let first = UUID().uuidString
        let second = UUID().uuidString
        var calls: [String] = []
        BackgroundDownloadEvents.register(identifier: first) { calls.append(first) }
        BackgroundDownloadEvents.register(identifier: second) { calls.append(second) }
        BackgroundDownloadEvents.finish(identifier: second)
        BackgroundDownloadEvents.finish(identifier: first)
        BackgroundDownloadEvents.finish(identifier: first)
        #expect(calls == [second, first])
    }

    @Test("Redownload never salvages a previous batch's staged files", .timeLimit(.minutes(1)))
    func redownloadDiscardsStagedIdentity() async throws {
        let fixture = try fixture()
        let probe = FileDeliveryProbe()
        let session = session(fixture, probe: probe)
        await session.cancel(fixture.job.key, preservingStagedFiles: false)
        let next = try await session.begin(fixture.job)
        #expect(next.id != fixture.ticket.batchID)
        #expect(next.tickets.isEmpty)
        #expect(await probe.calls == 0)
    }

    @Test("File publication checks the active batch before touching existing media")
    func staleFileCannotPublish() async throws {
        let fixture = try fixture()
        let files = DownloadFileStore(root: fixture.root.appendingPathComponent("Downloads"), minimumFreeBytes: 0)
        let url = fixture.root.appendingPathComponent("Staging/saved.download")
        await files.setDownloadBatch(UUID(), for: fixture.job.key)
        await #expect(throws: CancellationError.self) {
            try await files.publishBackgroundFile(at: url, ticket: fixture.ticket)
        }
        #expect(await files.contains(fixture.job.key, pageIndex: 0) == false)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    @Test("An event cycle finished before UIKit registration still completes once")
    func completionBeforeRegistration() {
        let identifier = UUID().uuidString
        var calls = 0
        BackgroundDownloadEvents.finish(identifier: identifier)
        BackgroundDownloadEvents.register(identifier: identifier) { calls += 1 }
        #expect(calls == 1)
    }
}
