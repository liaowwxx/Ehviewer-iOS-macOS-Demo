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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import EHDomain
import EHNetworking

public enum DownloadState: String, Codable, Hashable, Sendable {
    case queued
    case running
    case paused
    case completed
    case failed
    case authenticationRequired
    case rateLimited
    case bandwidthLimited
    case cancelled
}

public struct DownloadJob: Identifiable, Hashable, Sendable {
    public let key: GalleryKey
    public let title: String
    public let japaneseTitle: String?
    public let tags: [String]
    public let pages: [GalleryPageDescriptor]
    public let addedAt: Date
    public var label: String?
    public var completedPageIndexes: Set<Int>
    public var state: DownloadState
    public var errorMessage: String?

    public init(
        key: GalleryKey,
        title: String,
        japaneseTitle: String? = nil,
        tags: [String] = [],
        pages: [GalleryPageDescriptor],
        label: String? = nil,
        addedAt: Date = Date()
    ) {
        self.key = key
        self.title = title
        self.japaneseTitle = japaneseTitle
        self.tags = tags
        self.pages = pages
        self.label = label
        self.addedAt = addedAt
        completedPageIndexes = []
        state = .queued
        errorMessage = nil
    }

    public var id: GalleryKey { key }
    public var progress: Double {
        guard pages.isEmpty == false else { return 0 }
        return Double(completedPageIndexes.count) / Double(pages.count)
    }

    /// Mirrors the reference client's `EhUtils.getSuitableTitle` for download
    /// rows: the stored title snapshot stays the on-disk name, while the list
    /// follows the Japanese-title preference live.
    public func displayTitle(showJapaneseTitle: Bool) -> String {
        let japanese = japaneseTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if showJapaneseTitle {
            if let japanese, japanese.isEmpty == false { return japanese }
            return title
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty == false { return title }
        if let japanese, japanese.isEmpty == false { return japanese }
        return title
    }

    /// Mirrors the reference client's `judgeSuitableTitle`: download search
    /// matches against both stored titles.
    public func containsTitle(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return true }
        let haystack = "\(japaneseTitle ?? "")\(title)"
        return haystack.localizedCaseInsensitiveContains(query)
    }

    public func containsTag(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return true }
        return tags.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    /// Matches the pending search syntax used by the browse search field.
    /// Quoted tag tokens are ANDed, while any remaining free text matches the
    /// title, label, or tags. A local summary is accepted because older
    /// persisted download jobs may not have their gallery tags hydrated yet.
    public func matchesSearch(
        query: String,
        summary: GallerySummary? = nil,
        localizedTag: (String) -> String = { $0 }
    ) -> Bool {
        let normalizedQuery = SearchQueryComposer.normalized(query)
        guard normalizedQuery.isEmpty == false else { return true }

        var candidateTags = tags
        if let summary {
            candidateTags.append(contentsOf: summary.tags)
        }

        for token in SearchQueryComposer.tagTokens(in: normalizedQuery) {
            let fullTag = SearchQueryComposer.normalized(token.fullTag)
            let databaseTag = SearchQueryComposer.databaseTagKey(for: fullTag)
            let matched = candidateTags.contains { tag in
                let normalizedTag = SearchQueryComposer.normalized(tag)
                return normalizedTag.localizedCaseInsensitiveCompare(fullTag) == .orderedSame
                    || normalizedTag.localizedCaseInsensitiveCompare(databaseTag) == .orderedSame
            }
            guard matched else { return false }
        }

        let freeText = SearchQueryComposer.tagTokens(in: normalizedQuery)
            .reduce(normalizedQuery) { query, token in
                SearchQueryComposer.removing(token, from: query)
            }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard freeText.isEmpty == false else { return true }

        let textValues = [
            title,
            japaneseTitle,
            summary?.title,
            summary?.japaneseTitle,
            label
        ].compactMap { $0 }
        if textValues.contains(where: { $0.localizedCaseInsensitiveContains(freeText) }) {
            return true
        }
        return candidateTags.contains {
            $0.localizedCaseInsensitiveContains(freeText)
                || localizedTag($0).localizedCaseInsensitiveContains(freeText)
        }
    }
}

public enum DownloadEvent: Sendable, Hashable {
    case reset([DownloadJob])
    case changed(DownloadJob)
    case removed(GalleryKey)
    case removedMany([GalleryKey])
}

public enum DownloadRemovalResult: Sendable, Equatable {
    case removed
    case failed(String)
}

public struct DownloadRemovalProgress: Sendable, Equatable {
    public let completed: Int
    public let total: Int
    public let failed: Int

    public var fraction: Double {
        guard total > 0 else { return 1 }
        return min(1, max(0, Double(completed) / Double(total)))
    }

    public init(completed: Int, total: Int, failed: Int = 0) {
        self.completed = completed
        self.total = total
        self.failed = failed
    }
}

public struct DownloadRemovalFailure: Sendable, Equatable {
    public let key: GalleryKey
    public let message: String

    public init(key: GalleryKey, message: String) {
        self.key = key
        self.message = message
    }
}

public struct DownloadBatchRemovalResult: Sendable, Equatable {
    public let requestedCount: Int
    public let removedCount: Int
    public let failures: [DownloadRemovalFailure]
    public let cancelled: Bool

    public init(
        requestedCount: Int,
        removedCount: Int,
        failures: [DownloadRemovalFailure],
        cancelled: Bool
    ) {
        self.requestedCount = requestedCount
        self.removedCount = removedCount
        self.failures = failures
        self.cancelled = cancelled
    }
}

public actor DownloadCoordinator {
    public typealias PageLoader = @Sendable (GalleryPageDescriptor) async throws -> Data
    public typealias JobPersistence = @Sendable (DownloadJob) async -> Void
    public typealias JobRemoval = @Sendable (GalleryKey) async throws -> Void
    public typealias BatchJobRemoval = @Sendable (Set<GalleryKey>) async throws -> Void

    private var jobs: [GalleryKey: DownloadJob] = [:]
    private var tasks: [GalleryKey: Task<Void, Never>] = [:]
    private var runTokens: [GalleryKey: UUID] = [:]
    private var subscribers: [UUID: AsyncStream<DownloadEvent>.Continuation] = [:]
    private var activeKey: GalleryKey?
    private let pageLoader: PageLoader
    private let maxConcurrentPages: Int
    private let fileStore: DownloadFileStore?
    private let persistence: JobPersistence?
    private let removal: JobRemoval?
    private let batchRemoval: BatchJobRemoval?

    public init(
        maxConcurrentPages: Int = 3,
        pageLoader: @escaping PageLoader = DownloadCoordinator.defaultPageLoader,
        fileStore: DownloadFileStore? = nil,
        persistence: JobPersistence? = nil,
        removal: JobRemoval? = nil,
        batchRemoval: BatchJobRemoval? = nil
    ) {
        self.maxConcurrentPages = max(1, maxConcurrentPages)
        self.pageLoader = pageLoader
        self.fileStore = fileStore
        self.persistence = persistence
        self.removal = removal
        self.batchRemoval = batchRemoval
    }

    public func events() -> AsyncStream<DownloadEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: DownloadEvent.self,
            bufferingPolicy: .bufferingNewest(100)
        )
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.removeSubscriber(id) }
        }
        subscribers[id] = continuation
        return stream
    }

    public func enqueue(
        key: GalleryKey,
        title: String,
        japaneseTitle: String? = nil,
        tags: [String] = [],
        pages: [GalleryPageDescriptor]
    ) async {
        guard jobs[key] == nil else { return }
        let job = DownloadJob(key: key, title: title, japaneseTitle: japaneseTitle, tags: tags, pages: pages)
        jobs[key] = job
        await save(job)
        emit(.changed(job))
        startNextQueuedJobIfNeeded()
    }

    public func pause(_ key: GalleryKey) async {
        guard var job = jobs[key], job.state == .running || job.state == .queued else { return }
        tasks[key]?.cancel()
        job.state = .paused
        jobs[key] = job
        await save(job)
        emit(.changed(job))
    }

    public func resume(_ key: GalleryKey) async {
        guard let job = jobs[key], job.state == .paused || job.state == .failed || job.state == .authenticationRequired || job.state == .rateLimited || job.state == .bandwidthLimited else { return }
        var resumed = job
        resumed.state = .queued
        resumed.errorMessage = nil
        jobs[key] = resumed
        await save(resumed)
        emit(.changed(resumed))
        startNextQueuedJobIfNeeded()
    }

    public func startAll() async {
        let keys = jobs.values
            .filter {
                switch $0.state {
                case .paused, .failed, .authenticationRequired, .rateLimited, .bandwidthLimited:
                    true
                default:
                    false
                }
            }
            .map(\.key)

        for key in keys {
            guard var job = jobs[key] else { continue }
            job.state = .queued
            job.errorMessage = nil
            jobs[key] = job
            await save(job)
            emit(.changed(job))
        }
        startNextQueuedJobIfNeeded()
    }

    public func stopAll() async {
        let keys = Array(jobs.keys)
        for key in keys {
            tasks[key]?.cancel()
            tasks[key] = nil
            runTokens[key] = nil
            guard var job = jobs[key] else { continue }
            guard job.state == .running || job.state == .queued else { continue }
            job.state = .paused
            jobs[key] = job
            await save(job)
            emit(.changed(job))
        }
        activeKey = nil
    }

    public func setLabel(_ label: String?, for key: GalleryKey) async {
        guard var job = jobs[key] else { return }
        let normalized = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        job.label = normalized?.isEmpty == true ? nil : normalized
        jobs[key] = job
        await save(job)
        emit(.changed(job))
    }

    public func cancel(_ key: GalleryKey) async {
        tasks[key]?.cancel()
        tasks[key] = nil
        runTokens[key] = nil
        if activeKey == key { activeKey = nil }
        guard var job = jobs[key] else { return }
        job.state = .cancelled
        jobs[key] = job
        await save(job)
        emit(.changed(job))
        startNextQueuedJobIfNeeded()
    }

    /// Deletes every downloaded page and restarts the job from the beginning.
    public func redownload(_ key: GalleryKey) async -> DownloadRemovalResult {
        tasks[key]?.cancel()
        tasks[key] = nil
        runTokens[key] = nil
        if activeKey == key { activeKey = nil }

        do {
            if let fileStore { try await fileStore.remove(key) }
            guard var job = jobs[key] else {
                startNextQueuedJobIfNeeded()
                return .removed
            }
            job.completedPageIndexes = []
            job.state = .queued
            job.errorMessage = nil
            jobs[key] = job
            await save(job)
            emit(.changed(job))
            startNextQueuedJobIfNeeded()
            return .removed
        } catch {
            guard var job = jobs[key] else {
                startNextQueuedJobIfNeeded()
                return .failed(error.localizedDescription)
            }
            job.state = .failed
            job.errorMessage = String(localized: "删除失败：\(error.localizedDescription)")
            jobs[key] = job
            await save(job)
            emit(.changed(job))
            startNextQueuedJobIfNeeded()
            return .failed(error.localizedDescription)
        }
    }

    public func remove(_ key: GalleryKey) async -> DownloadRemovalResult {
        tasks[key]?.cancel()
        tasks[key] = nil
        runTokens[key] = nil
        if activeKey == key { activeKey = nil }

        do {
            if let fileStore { try await fileStore.remove(key) }
            if let removal { try await removal(key) }
            jobs.removeValue(forKey: key)
            emit(.removed(key))
            startNextQueuedJobIfNeeded()
            return .removed
        } catch {
            guard var job = jobs[key] else {
                startNextQueuedJobIfNeeded()
                return .failed(error.localizedDescription)
            }
            job.state = .failed
            job.errorMessage = String(localized: "删除失败：\(error.localizedDescription)")
            jobs[key] = job
            await save(job)
            emit(.changed(job))
            startNextQueuedJobIfNeeded()
            return .failed(error.localizedDescription)
        }
    }

    /// Removes multiple downloads without saving or publishing each item one
    /// at a time. File deletion remains incremental so callers can report
    /// progress and cancel between galleries.
    public func remove(
        _ keys: [GalleryKey],
        progress: (@Sendable (DownloadRemovalProgress) async -> Void)? = nil
    ) async -> DownloadBatchRemovalResult {
        var seen = Set<GalleryKey>()
        let uniqueKeys = keys.filter { seen.insert($0).inserted }
        guard uniqueKeys.isEmpty == false else {
            await progress?(DownloadRemovalProgress(completed: 0, total: 0))
            return DownloadBatchRemovalResult(
                requestedCount: 0,
                removedCount: 0,
                failures: [],
                cancelled: false
            )
        }

        // Stop selected jobs before touching their files. Do not schedule a
        // replacement download until the batch has finished.
        for key in uniqueKeys {
            tasks[key]?.cancel()
            tasks[key] = nil
            runTokens[key] = nil
            if activeKey == key { activeKey = nil }
        }

        var completed = 0
        var successfullyPrepared: [GalleryKey] = []
        var failures: [DownloadRemovalFailure] = []
        await progress?(DownloadRemovalProgress(completed: 0, total: uniqueKeys.count))

        for key in uniqueKeys {
            if Task.isCancelled { break }

            do {
                if let fileStore {
                    try await fileStore.remove(key)
                }
                successfullyPrepared.append(key)
            } catch {
                failures.append(DownloadRemovalFailure(key: key, message: error.localizedDescription))
            }

            completed += 1
            await progress?(DownloadRemovalProgress(
                completed: completed,
                total: uniqueKeys.count,
                failed: failures.count
            ))
            await Task.yield()
        }

        // Persist all successfully removed files in one transaction. If the
        // store only provides the legacy single-key callback, retain the same
        // behavior as remove(_:), but still report incremental progress.
        var persistedKeys: [GalleryKey] = []
        if let batchRemoval {
            do {
                try await batchRemoval(Set(successfullyPrepared))
                persistedKeys = successfullyPrepared
            } catch {
                failures.append(contentsOf: successfullyPrepared.map {
                    DownloadRemovalFailure(key: $0, message: error.localizedDescription)
                })
            }
        } else if let removal {
            for key in successfullyPrepared {
                do {
                    try await removal(key)
                    persistedKeys.append(key)
                } catch {
                    failures.append(DownloadRemovalFailure(key: key, message: error.localizedDescription))
                }
            }
        } else {
            persistedKeys = successfullyPrepared
        }

        for key in persistedKeys {
            jobs.removeValue(forKey: key)
        }
        if persistedKeys.isEmpty == false {
            emit(.removedMany(persistedKeys))
        }

        for failure in failures {
            guard var job = jobs[failure.key] else { continue }
            job.state = .failed
            job.errorMessage = String(localized: "删除失败：\(failure.message)")
            jobs[failure.key] = job
            await save(job)
            emit(.changed(job))
        }

        startNextQueuedJobIfNeeded()
        return DownloadBatchRemovalResult(
            requestedCount: uniqueKeys.count,
            removedCount: persistedKeys.count,
            failures: failures,
            cancelled: Task.isCancelled || completed < uniqueKeys.count
        )
    }

    public func snapshot() -> [DownloadJob] {
        jobs.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public func job(for key: GalleryKey) -> DownloadJob? {
        jobs[key]
    }

    public func restore(_ restoredJobs: [DownloadJob]) async {
        for var job in restoredJobs {
            if job.state == .running { job.state = .queued }
            jobs[job.key] = job
            await save(job)
        }
        emit(.reset(snapshot()))
        startNextQueuedJobIfNeeded()
    }

    public func mergeRestored(_ restoredJobs: [DownloadJob]) async {
        for incoming in restoredJobs {
            if let existing = jobs[incoming.key] {
                var mergedPages = Dictionary(uniqueKeysWithValues: existing.pages.map { ($0.index, $0) })
                for page in incoming.pages {
                    guard let existingPage = mergedPages[page.index] else {
                        mergedPages[page.index] = page
                        continue
                    }
                    if page.requiresPageResolution,
                       existingPage.pageURL.fragment?.hasPrefix("restored-") == true {
                        mergedPages[page.index] = page
                    }
                }
                let pages = mergedPages.values.sorted { $0.index < $1.index }
                let expectedIndexes = Set(pages.map(\.index))
                let completedIndexes = existing.completedPageIndexes.union(incoming.completedPageIndexes)
                var merged = DownloadJob(
                    key: existing.key,
                    title: existing.title.isEmpty ? incoming.title : existing.title,
                    japaneseTitle: existing.japaneseTitle ?? incoming.japaneseTitle,
                    tags: existing.tags.isEmpty ? incoming.tags : existing.tags,
                    pages: pages,
                    label: existing.label ?? incoming.label,
                    addedAt: min(existing.addedAt, incoming.addedAt)
                )
                merged.completedPageIndexes = completedIndexes.intersection(expectedIndexes)
                if expectedIndexes.isEmpty == false && merged.completedPageIndexes == expectedIndexes {
                    merged.state = .completed
                    merged.errorMessage = nil
                } else if existing.state == .running || existing.state == .queued {
                    merged.state = existing.state
                    merged.errorMessage = existing.errorMessage ?? incoming.errorMessage
                } else {
                    merged.state = incoming.state == .running ? .paused : incoming.state
                    merged.errorMessage = existing.errorMessage ?? incoming.errorMessage
                }
                jobs[existing.key] = merged
                await save(merged)
                emit(.changed(merged))
            } else {
                var job = incoming
                if job.state == .running { job.state = .queued }
                jobs[job.key] = job
                await save(job)
                emit(.changed(job))
            }
        }
        startNextQueuedJobIfNeeded()
    }

    /// Updates only gallery metadata for an existing download. Local pages,
    /// progress, labels and state remain untouched.
    public func mergeMetadata(_ summaries: [GallerySummary]) async {
        for summary in summaries {
            guard let existing = jobs[summary.key] else { continue }
            var updated = DownloadJob(
                key: existing.key,
                title: summary.title,
                japaneseTitle: summary.japaneseTitle,
                tags: summary.tags,
                pages: existing.pages,
                label: existing.label,
                addedAt: existing.addedAt
            )
            updated.completedPageIndexes = existing.completedPageIndexes
            updated.state = existing.state
            updated.errorMessage = existing.errorMessage
            jobs[summary.key] = updated
            await save(updated)
            emit(.changed(updated))
        }
    }

    public func loadPersisted(_ restoredJobs: [DownloadJob]) {
        for task in tasks.values { task.cancel() }
        tasks.removeAll(keepingCapacity: true)
        runTokens.removeAll(keepingCapacity: true)
        activeKey = nil

        // Keep jobs that were enqueued while restoration was in flight instead
        // of wiping them: startup restore must never discard a fresh enqueue.
        for var restored in restoredJobs {
            if restored.state == .running { restored.state = .queued }
            if jobs[restored.key] == nil {
                jobs[restored.key] = restored
            }
        }
        emit(.reset(snapshot()))
    }

    @discardableResult
    public func reconcilePersisted(_ reconciledJob: DownloadJob, replacing baseline: DownloadJob) async -> Bool {
        guard jobs[baseline.key] == baseline else { return false }
        guard reconciledJob != baseline else { return true }
        jobs[reconciledJob.key] = reconciledJob
        await save(reconciledJob)
        guard jobs[reconciledJob.key] == reconciledJob else { return false }
        emit(.changed(reconciledJob))
        return true
    }

    public func startRestoredJobs() {
        startNextQueuedJobIfNeeded()
    }

    private func startNextQueuedJobIfNeeded() {
        guard activeKey == nil,
              let next = jobs.values
                  .filter({ $0.state == .queued })
                  .sorted(by: { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
                  .first else { return }
        let runToken = UUID()
        activeKey = next.key
        runTokens[next.key] = runToken
        tasks[next.key] = Task { [weak self] in
            await self?.run(key: next.key, runToken: runToken)
        }
    }

    private func run(key: GalleryKey, runToken: UUID) async {
        guard var job = jobs[key] else {
            finishRun(key: key, runToken: runToken)
            return
        }
        job.state = .running
        jobs[key] = job
        await save(job)
        emit(.changed(job))

        do {
            let pendingPages = job.pages.filter { job.completedPageIndexes.contains($0.index) == false }
            var iterator = pendingPages.makeIterator()
            while let first = iterator.next() {
                try Task.checkCancellation()
                var batch = [first]
                while batch.count < maxConcurrentPages, let next = iterator.next() {
                    batch.append(next)
                }

                let completed = try await withThrowingTaskGroup(of: Int.self) { group in
                    for page in batch {
                        group.addTask { [pageLoader, fileStore] in
                            let data = try await Self.loadWithRetry(page, loader: pageLoader)
                            if let fileStore {
                                _ = try await fileStore.write(data, for: page.galleryKey, pageIndex: page.index)
                            }
                            return page.index
                        }
                    }
                    var indexes: [Int] = []
                    for try await index in group { indexes.append(index) }
                    return indexes
                }

                guard Task.isCancelled == false, runTokens[key] == runToken else { return }
                guard var current = jobs[key] else { return }
                current.completedPageIndexes.formUnion(completed)
                jobs[key] = current
                await save(current)
                emit(.changed(current))
            }

            guard Task.isCancelled == false, runTokens[key] == runToken else { return }
            guard var completed = jobs[key] else { return }
            completed.state = .completed
            completed.errorMessage = nil
            jobs[key] = completed
            await save(completed)
            emit(.changed(completed))
        } catch is CancellationError {
            // pause/cancel have already published their intentional state.
        } catch EHError.diskSpaceLow {
            guard runTokens[key] == runToken else { return }
            guard var paused = jobs[key], paused.state != .cancelled else { return }
            paused.state = .paused
            paused.errorMessage = EHError.diskSpaceLow.localizedDescription
            jobs[key] = paused
            await save(paused)
            emit(.changed(paused))
        } catch let error as EHError {
            guard runTokens[key] == runToken else { return }
            guard var failed = jobs[key], failed.state != .cancelled else { return }
            failed.state = state(for: error)
            failed.errorMessage = error.localizedDescription
            jobs[key] = failed
            await save(failed)
            emit(.changed(failed))
        } catch {
            guard runTokens[key] == runToken else { return }
            guard var failed = jobs[key], failed.state != .cancelled else { return }
            failed.state = .failed
            failed.errorMessage = error.localizedDescription
            jobs[key] = failed
            await save(failed)
            emit(.changed(failed))
        }
        finishRun(key: key, runToken: runToken)
    }

    private func finishRun(key: GalleryKey, runToken: UUID) {
        guard runTokens[key] == runToken else { return }
        tasks[key] = nil
        runTokens[key] = nil
        if activeKey == key { activeKey = nil }
        startNextQueuedJobIfNeeded()
    }

    private static func loadWithRetry(_ page: GalleryPageDescriptor, loader: @escaping PageLoader) async throws -> Data {
        for attempt in 0..<3 {
            do {
                return try await loader(page)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as EHError where shouldRetry(error) && attempt < 2 {
                try await Task.sleep(for: .milliseconds(100 * (1 << attempt)))
            } catch {
                throw error
            }
        }
        throw EHError.networkFailed(String(localized: "重试次数已用尽"))
    }

    private static func shouldRetry(_ error: EHError) -> Bool {
        switch error {
        case .networkFailed:
            true
        case .httpStatus(let status):
            [408, 500, 502, 503, 504].contains(status)
        default:
            false
        }
    }

    private func state(for error: EHError) -> DownloadState {
        switch error {
        case .authenticationRequired: .authenticationRequired
        case .rateLimited: .rateLimited
        case .bandwidthLimited: .bandwidthLimited
        case .httpStatus(403): .authenticationRequired
        case .httpStatus(429): .rateLimited
        case .httpStatus(509): .bandwidthLimited
        default: .failed
        }
    }

    private func save(_ job: DownloadJob) async {
        if let persistence { await persistence(job) }
    }

    private func emit(_ event: DownloadEvent) {
        for continuation in subscribers.values { continuation.yield(event) }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }

    public static func defaultPageLoader(_ page: GalleryPageDescriptor) async throws -> Data {
        let (data, response) = try await URLSessionTransport().send(URLRequest(url: page.pageURL))
        guard (200..<300).contains(response.statusCode) else { throw EHError.httpStatus(response.statusCode) }
        return data
    }
}
