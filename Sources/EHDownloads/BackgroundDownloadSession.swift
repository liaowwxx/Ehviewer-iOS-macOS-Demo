/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import EHDomain
import EHNetworking

/// UIKit's completion belongs to one session and one delivery cycle.
@MainActor
public enum BackgroundDownloadEvents {
    private static var handlers: [String: () -> Void] = [:]
    private static var finishedBeforeRegistration: Set<String> = []

    public static func register(identifier: String, _ completion: @escaping () -> Void) {
        if finishedBeforeRegistration.remove(identifier) != nil { completion() }
        else { handlers[identifier] = completion }
    }

    public static func finish(identifier: String) {
        if let handler = handlers.removeValue(forKey: identifier) { handler() }
        else { finishedBeforeRegistration.insert(identifier) }
    }
}

public actor BackgroundDownloadSession: DownloadTransferService {
    public typealias Resolver = @Sendable (GalleryPageDescriptor) async throws -> GalleryPageImage
    public typealias RequestBuilder = @Sendable (GalleryPageDescriptor, GalleryPageImage) async throws -> URLRequest
    public typealias FileCompletion = @Sendable (DownloadTransferTicket, URL) async throws -> Void
    public typealias BatchObserver = @Sendable (GalleryKey, UUID?) async -> Void
    public typealias TaskObserver = @Sendable (GalleryPageDescriptor, Int) async throws -> Void
    public typealias LegacyCompletion = @Sendable (String, URL, Int) async throws -> Void
    public typealias LegacyIdentity = @Sendable (String) -> (GalleryKey, Int)?

    struct Receipt: Codable, Sendable {
        let id: UUID
        let taskDescription: String
        let fileName: String
        let statusCode: Int
        let accessDenied: Bool
    }

    private struct Entry: Codable {
        let ticket: DownloadTransferTicket
        var completed = false
    }

    private struct Batch: Codable {
        let id: UUID
        let key: GalleryKey
        var active: Bool
        var entries: [String: Entry]
        var preservesStagedFiles: Bool? = true
    }

    private struct Journal: Codable {
        var version = 1
        var batches: [String: Batch] = [:]
    }

    private enum Event: Sendable {
        case receipt(Receipt)
        case completed(description: String, status: Int, error: String?)
        case finishEvents
        case recover(CheckedContinuation<Void, Never>)
    }

    /// URLSession serializes this delegate on its dedicated operation queue.
    /// The only cross-thread output is an immutable AsyncStream continuation.
    private final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let stagingRoot: URL
        let continuation: AsyncStream<Event>.Continuation

        init(stagingRoot: URL, continuation: AsyncStream<Event>.Continuation) {
            self.stagingRoot = stagingRoot
            self.continuation = continuation
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            let id = UUID()
            let fileName = id.uuidString + ".download"
            do {
                try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
                // URLSession owns location only until this delegate method returns.
                try FileManager.default.moveItem(at: location, to: stagingRoot.appendingPathComponent(fileName))
                let response = downloadTask.response as? HTTPURLResponse
                let receipt = Receipt(
                    id: id, taskDescription: downloadTask.taskDescription ?? "",
                    fileName: fileName, statusCode: response?.statusCode ?? 0,
                    accessDenied: response?.value(forHTTPHeaderField: "Content-Disposition")?.contains("sadpanda.jpg") == true
                )
                try JSONEncoder().encode(receipt).write(
                    to: stagingRoot.appendingPathComponent(id.uuidString + ".json"), options: .atomic
                )
                continuation.yield(.receipt(receipt))
            } catch {
                continuation.yield(.completed(
                    description: downloadTask.taskDescription ?? "", status: 0,
                    error: error.localizedDescription
                ))
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            continuation.yield(.completed(
                description: task.taskDescription ?? "",
                status: (task.response as? HTTPURLResponse)?.statusCode ?? 0,
                error: error?.localizedDescription
            ))
        }

        func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
            continuation.yield(.finishEvents)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            var redirected = request
            if request.url.map(CookieHeader.isTrustedURL) != true {
                redirected.setValue(nil, forHTTPHeaderField: "Cookie")
            }
            completionHandler(redirected)
        }
    }

    public nonisolated let identifier: String
    private let root: URL
    private let stagingRoot: URL
    private let session: URLSession
    private let resolver: Resolver
    private let requestBuilder: RequestBuilder
    private let fileCompletion: FileCompletion
    private let taskObserver: TaskObserver?
    private let batchObserver: BatchObserver?
    private let legacyCompletion: LegacyCompletion?
    private let legacyIdentity: LegacyIdentity?
    private let events: AsyncStream<Event>
    private let eventContinuation: AsyncStream<Event>.Continuation
    private var eventTask: Task<Void, Never>?
    private var journal: Journal
    private var startupError: EHError?
    private var waiters: [UUID: [UUID: CheckedContinuation<Void, Error>]] = [:]
    private var failures: [UUID: EHError] = [:]
    private var received: Set<UUID> = []
    private var preparationEnabled = true

    public init(
        identifier: String = "com.liao.ehviewer.background-downloads",
        root: URL,
        resolver: @escaping Resolver,
        requestBuilder: @escaping RequestBuilder,
        fileCompletion: @escaping FileCompletion,
        taskObserver: TaskObserver? = nil,
        batchObserver: BatchObserver? = nil,
        legacyCompletion: LegacyCompletion? = nil,
        legacyIdentity: LegacyIdentity? = nil
    ) {
        self.identifier = identifier
        self.root = root
        stagingRoot = root.appendingPathComponent("Staging", isDirectory: true)
        self.resolver = resolver
        self.requestBuilder = requestBuilder
        self.fileCompletion = fileCompletion
        self.taskObserver = taskObserver
        self.batchObserver = batchObserver
        self.legacyCompletion = legacyCompletion
        self.legacyIdentity = legacyIdentity
        let channel = AsyncStream<Event>.makeStream()
        events = channel.stream
        eventContinuation = channel.continuation
        let journalURL = root.appendingPathComponent("queue.json")
        if FileManager.default.fileExists(atPath: journalURL.path) {
            do {
                let decoded = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journalURL))
                guard decoded.version == 1 else { throw EHError.storageFailed("Unsupported download queue version") }
                journal = decoded
            } catch {
                journal = Journal()
                startupError = .storageFailed(error.localizedDescription)
            }
        } else {
            journal = Journal()
        }
#if os(iOS)
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.sessionSendsLaunchEvents = true
#else
        let configuration = URLSessionConfiguration.default
#endif
        configuration.waitsForConnectivity = true
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.isDiscretionary = false
        configuration.httpMaximumConnectionsPerHost = 3
        let delegate = Delegate(stagingRoot: stagingRoot, continuation: channel.continuation)
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: delegateQueue)
    }

    private func startEvents() {
        guard eventTask == nil else { return }
        eventTask = Task { [weak self, events] in
            for await event in events {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    /// Also used by a background launch before any SwiftUI view is constructed.
    public func reconnect() async {
        for batch in journal.batches.values where batch.active {
            await batchObserver?(batch.key, batch.id)
        }
        startEvents()
        await withCheckedContinuation { eventContinuation.yield(.recover($0)) }
    }

    public func begin(_ job: DownloadJob) async throws -> DownloadTransferBatch {
        if let startupError { throw startupError }
        startEvents()
        // Keep the journal bounded by unfinished work rather than the entire
        // historical library. SwiftData remains the completed-library index.
        journal.batches = journal.batches.filter { key, batch in
            key == job.key.id || !batch.entries.values.allSatisfy(\.completed)
        }
        // Pause/cancel makes the old batch permanently ineligible for publication.
        if journal.batches[job.key.id]?.active != true {
            let previous = journal.batches[job.key.id]
            let newID = UUID()
            var entries: [String: Entry] = [:]
            // Salvage durable files from an interrupted publication without
            // allowing a late network callback from the old batch to match.
            for receipt in pendingReceipts() where (200..<300).contains(receipt.statusCode) && !receipt.accessDenied {
                guard previous?.preservesStagedFiles != false,
                      let old = previous?.entries[receipt.taskDescription], !old.completed,
                      !job.completedPageIndexes.contains(old.ticket.page.index) else { continue }
                let ticket = DownloadTransferTicket(batchID: newID, page: old.ticket.page, image: old.ticket.image, attempt: old.ticket.attempt, taskIdentifier: -1)
                let rebound = Receipt(id: UUID(), taskDescription: ticket.id.uuidString, fileName: receipt.fileName, statusCode: receipt.statusCode, accessDenied: false)
                try JSONEncoder().encode(rebound).write(to: stagingRoot.appendingPathComponent(rebound.id.uuidString + ".json"), options: .atomic)
                entries[ticket.id.uuidString] = Entry(ticket: ticket)
            }
            journal.batches[job.key.id] = Batch(id: newID, key: job.key, active: true, entries: entries)
            try persist()
        }
        await reconnect()
        let active = await allTasks()
        try Task.checkCancellation()
        guard var batch = journal.batches[job.key.id], batch.active else { throw CancellationError() }
        for task in active {
            guard let description = task.taskDescription,
                  let (key, index) = legacyIdentity?(description), key == job.key,
                  !job.completedPageIndexes.contains(index),
                  let page = job.pages.first(where: { $0.index == index }) else { continue }
            let ticket = DownloadTransferTicket(
                batchID: batch.id, page: page,
                image: GalleryPageImage(galleryKey: key, index: index, imageURL: task.originalRequest?.url ?? page.pageURL),
                taskIdentifier: task.taskIdentifier
            )
            batch.entries[ticket.id.uuidString] = Entry(ticket: ticket)
            journal.batches[key.id] = batch
            try persist()
            task.taskDescription = ticket.id.uuidString
        }
        let activeIDs = Dictionary(active.compactMap { task in
            task.taskDescription.map { ($0, task.taskIdentifier) }
        }, uniquingKeysWith: { first, _ in first })
        // A missing system task without a durable receipt must be resolved again.
        batch.entries = batch.entries.filter { _, entry in
            entry.completed || received.contains(entry.ticket.id) || activeIDs[entry.ticket.id.uuidString] == entry.ticket.taskIdentifier
        }
        journal.batches[job.key.id] = batch
        try persist()
        for task in active where batch.entries[task.taskDescription ?? ""] != nil && task.state == .suspended {
            task.resume()
        }
        return DownloadTransferBatch(id: batch.id, tickets: batch.entries.values.map(\.ticket))
    }

    public func prepare(_ page: GalleryPageDescriptor, batchID: UUID, attempt: Int) async throws -> DownloadTransferTicket {
        try Task.checkCancellation()
        guard preparationEnabled else { throw CancellationError() }
        let image = try await resolver(page)
        try Task.checkCancellation()
        guard preparationEnabled else { throw CancellationError() }
        guard image.galleryKey == page.galleryKey, image.index == page.index else {
            throw EHError.parsingFailed("Resolved image does not match the download page")
        }
        let request = try await requestBuilder(page, image)
        try Task.checkCancellation()
        guard var batch = journal.batches[page.galleryKey.id],
              batch.id == batchID, batch.active else { throw CancellationError() }
        let id = UUID()
        let task = session.downloadTask(with: request)
        task.taskDescription = id.uuidString
        let ticket = DownloadTransferTicket(id: id, batchID: batchID, page: page, image: image, attempt: attempt, taskIdentifier: task.taskIdentifier)
        // Retire earlier attempts at the same page before a replacement is published.
        // Optional-chained nested writeback holds a modifying access to the
        // journal while evaluating its RHS. Transform a local batch instead.
        batch.entries = batch.entries.filter {
            $0.value.ticket.page.index != page.index
        }
        batch.entries[id.uuidString] = Entry(ticket: ticket)
        journal.batches[page.galleryKey.id] = batch
        do {
            try persist()
            try await taskObserver?(page, task.taskIdentifier)
            try Task.checkCancellation()
            guard isCurrent(ticket) else { throw CancellationError() }
            task.resume()
            return ticket
        } catch {
            task.cancel()
            throw error
        }
    }

    public func finish(_ ticket: DownloadTransferTicket) async throws {
        try Task.checkCancellation()
        guard isCurrent(ticket) else { throw CancellationError() }
        if journal.batches[ticket.page.galleryKey.id]?.entries[ticket.id.uuidString]?.completed == true { return }
        if let error = failures[ticket.id] { throw error }
        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters[ticket.id, default: [:]][waiterID] = continuation
            }
        } onCancel: {
            Task { await self.cancelWaiter(ticket.id, waiterID: waiterID) }
        }
    }

    public func cancel(_ key: GalleryKey, preservingStagedFiles: Bool) async {
        guard let batch = journal.batches[key.id] else { return }
        journal.batches[key.id]?.active = false
        journal.batches[key.id]?.preservesStagedFiles = preservingStagedFiles
        try? persist()
        await batchObserver?(key, nil)
        let descriptions = Set(batch.entries.keys)
        // Release awaiters before crossing the URLSession boundary.
        for entry in batch.entries.values { resolve(entry.ticket.id, error: CancellationError()) }
        let tasks = await allTasks()
        for task in tasks where descriptions.contains(task.taskDescription ?? "") { task.cancel() }
    }

    public func setPreparationEnabled(_ enabled: Bool) {
        preparationEnabled = enabled
    }

    public func cancelAll() async {
        for key in journal.batches.values.map(\.key) { await cancel(key) }
        // Include tasks submitted by older application versions.
        for task in await allTasks() { task.cancel() }
    }

    public func activeTaskIdentifiers() async -> [Int] {
        await allTasks().map(\.taskIdentifier)
    }

    private func allTasks() async -> [URLSessionTask] {
        await withCheckedContinuation { continuation in
            session.getAllTasks { continuation.resume(returning: $0) }
        }
    }

    private func isCurrent(_ ticket: DownloadTransferTicket) -> Bool {
        guard let batch = journal.batches[ticket.page.galleryKey.id] else { return false }
        return batch.active && batch.id == ticket.batchID && batch.entries[ticket.id.uuidString] != nil
    }

    private func ticket(description: String) -> DownloadTransferTicket? {
        journal.batches.values.lazy.compactMap { $0.entries[description]?.ticket }.first
    }

    private func persist() throws {
        if let startupError { throw startupError }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try JSONEncoder().encode(journal).write(to: root.appendingPathComponent("queue.json"), options: .atomic)
        } catch {
            throw EHError.storageFailed(error.localizedDescription)
        }
    }

    private func cancelWaiter(_ id: UUID, waiterID: UUID) {
        waiters[id]?.removeValue(forKey: waiterID)?.resume(throwing: CancellationError())
        if waiters[id]?.isEmpty == true { waiters[id] = nil }
    }

    private func resolve(_ id: UUID, error: (any Error)? = nil) {
        let continuations = waiters.removeValue(forKey: id)?.values
        for continuation in continuations ?? Dictionary<UUID, CheckedContinuation<Void, Error>>().values {
            if let error { continuation.resume(throwing: error) }
            else { continuation.resume() }
        }
    }

    private func handle(_ event: Event) async {
        switch event {
        case .receipt(let receipt):
            await receive(receipt)
        case let .completed(description, status, error):
            guard let ticket = ticket(description: description), isCurrent(ticket),
                  journal.batches[ticket.page.galleryKey.id]?.entries[description]?.completed != true,
                  received.contains(ticket.id) == false else { return }
            let failure: EHError = error.map(EHError.networkFailed) ?? .httpStatus(status)
            failures[ticket.id] = failure
            resolve(ticket.id, error: failure)
        case .finishEvents:
            // The stream is consumed serially, including asynchronous file/DB work.
            await BackgroundDownloadEvents.finish(identifier: identifier)
        case .recover(let continuation):
            for receipt in pendingReceipts() { await receive(receipt) }
            continuation.resume()
        }
    }

    private func pendingReceipts() -> [Receipt] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: stagingRoot, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(Receipt.self, from: data)
        }
    }

    func deliveryFinished() {
        startEvents()
        eventContinuation.yield(.finishEvents)
    }

    private func archiveReceipt(_ receipt: Receipt) {
        let directory = root.appendingPathComponent("Processed", isDirectory: true)
        let source = stagingRoot.appendingPathComponent(receipt.id.uuidString + ".json")
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.moveItem(at: source, to: directory.appendingPathComponent(receipt.id.uuidString + ".json"))
    }

    // Internal so deterministic tests can exercise delivery without live networking.
    func receive(_ receipt: Receipt) async {
        guard receipt.fileName == URL(fileURLWithPath: receipt.fileName).lastPathComponent,
              !receipt.fileName.isEmpty else { return }
        let fileURL = stagingRoot.appendingPathComponent(receipt.fileName)
        guard let ticket = ticket(description: receipt.taskDescription) else {
            // Old releases used profile|gid|token|page descriptions.
            if receipt.taskDescription.contains("|"), let legacyCompletion {
                do {
                    try await legacyCompletion(receipt.taskDescription, fileURL, receipt.statusCode)
                    archiveReceipt(receipt)
                } catch { /* Keep the receipt for a later restore. */ }
            }
            return
        }
        guard isCurrent(ticket),
              journal.batches[ticket.page.galleryKey.id]?.entries[ticket.id.uuidString]?.completed != true else { return }
        received.insert(ticket.id)
        do {
            if receipt.accessDenied { throw EHError.exHentaiAccessDenied }
            guard (200..<300).contains(receipt.statusCode) else { throw EHError.httpStatus(receipt.statusCode) }
            if FileManager.default.fileExists(atPath: fileURL.path) {
                // Inspect only a bounded prefix for the site's HTML error page.
                let handle = try FileHandle(forReadingFrom: fileURL)
                let prefix = try handle.read(upToCount: 8192) ?? Data()
                try handle.close()
                if String(data: prefix, encoding: .utf8)?.contains("exhentai.org/img/kokomade.jpg") == true {
                    throw EHError.siteAccessLimited
                }
            }
            try await fileCompletion(ticket, fileURL)
            guard isCurrent(ticket) else { return }
            journal.batches[ticket.page.galleryKey.id]?.entries[ticket.id.uuidString]?.completed = true
            try persist()
            archiveReceipt(receipt)
            failures[ticket.id] = nil
            resolve(ticket.id)
        } catch {
            guard isCurrent(ticket) else { return }
            let failure = (error as? EHError) ?? .storageFailed(error.localizedDescription)
            failures[ticket.id] = failure
            resolve(ticket.id, error: failure)
        }
    }
}
