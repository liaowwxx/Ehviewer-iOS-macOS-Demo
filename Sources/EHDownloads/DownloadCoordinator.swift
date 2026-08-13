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
    public let pages: [GalleryPageDescriptor]
    public var label: String?
    public var completedPageIndexes: Set<Int>
    public var state: DownloadState
    public var errorMessage: String?

    public init(key: GalleryKey, title: String, pages: [GalleryPageDescriptor], label: String? = nil) {
        self.key = key
        self.title = title
        self.pages = pages
        self.label = label
        completedPageIndexes = []
        state = .queued
        errorMessage = nil
    }

    public var id: GalleryKey { key }
    public var progress: Double {
        guard pages.isEmpty == false else { return 0 }
        return Double(completedPageIndexes.count) / Double(pages.count)
    }
}

public enum DownloadEvent: Sendable, Hashable {
    case changed(DownloadJob)
    case removed(GalleryKey)
}

public actor DownloadCoordinator {
    public typealias PageLoader = @Sendable (GalleryPageDescriptor) async throws -> Data
    public typealias JobPersistence = @Sendable (DownloadJob) async -> Void
    public typealias JobRemoval = @Sendable (GalleryKey) async -> Void

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

    public init(
        maxConcurrentPages: Int = 3,
        pageLoader: @escaping PageLoader = DownloadCoordinator.defaultPageLoader,
        fileStore: DownloadFileStore? = nil,
        persistence: JobPersistence? = nil,
        removal: JobRemoval? = nil
    ) {
        self.maxConcurrentPages = max(1, maxConcurrentPages)
        self.pageLoader = pageLoader
        self.fileStore = fileStore
        self.persistence = persistence
        self.removal = removal
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

    public func enqueue(key: GalleryKey, title: String, pages: [GalleryPageDescriptor]) async {
        guard jobs[key] == nil else { return }
        let job = DownloadJob(key: key, title: title, pages: pages)
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

    public func remove(_ key: GalleryKey) async {
        tasks[key]?.cancel()
        tasks[key] = nil
        runTokens[key] = nil
        if activeKey == key { activeKey = nil }
        jobs.removeValue(forKey: key)
        if let removal { await removal(key) }
        if let fileStore { try? await fileStore.remove(key) }
        emit(.removed(key))
        startNextQueuedJobIfNeeded()
    }

    public func snapshot() -> [DownloadJob] {
        jobs.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public func restore(_ restoredJobs: [DownloadJob]) async {
        for var job in restoredJobs {
            if job.state == .running { job.state = .queued }
            jobs[job.key] = job
            await save(job)
            emit(.changed(job))
        }
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

                guard var current = jobs[key] else { return }
                current.completedPageIndexes.formUnion(completed)
                jobs[key] = current
                await save(current)
                emit(.changed(current))
            }

            guard var completed = jobs[key] else { return }
            completed.state = .completed
            completed.errorMessage = nil
            jobs[key] = completed
            await save(completed)
            emit(.changed(completed))
        } catch is CancellationError {
            // pause/cancel have already published their intentional state.
        } catch EHError.diskSpaceLow {
            guard var paused = jobs[key], paused.state != .cancelled else { return }
            paused.state = .paused
            paused.errorMessage = EHError.diskSpaceLow.localizedDescription
            jobs[key] = paused
            await save(paused)
            emit(.changed(paused))
        } catch let error as EHError {
            guard var failed = jobs[key], failed.state != .cancelled else { return }
            failed.state = state(for: error)
            failed.errorMessage = error.localizedDescription
            jobs[key] = failed
            await save(failed)
            emit(.changed(failed))
        } catch {
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
        throw EHError.networkFailed("重试次数已用尽")
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
