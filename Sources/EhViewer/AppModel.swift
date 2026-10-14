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
import CoreGraphics
import Observation
import SwiftData
import EHDomain
import EHNetworking
import EHPersistence
import EHDownloads
import EHDeviceSync

struct MigrationProgress: Sendable, Hashable {
    let status: String
    let completed: Int
    let total: Int
    let fraction: Double?
    let estimatedRemainingSeconds: TimeInterval?

    init(
        status: String,
        completed: Int = 0,
        total: Int = 0,
        fraction: Double? = nil,
        estimatedRemainingSeconds: TimeInterval? = nil
    ) {
        self.status = status
        self.completed = completed
        self.total = total
        self.fraction = fraction ?? (total > 0 ? min(1, max(0, Double(completed) / Double(total))) : nil)
        self.estimatedRemainingSeconds = estimatedRemainingSeconds
    }
}

struct PendingIncomingArchive: Identifiable, Sendable, Equatable {
    let id = UUID()
    let stagedURL: URL
    let fileName: String
}

struct PendingIncomingGallerySync: Identifiable, Sendable, Equatable {
    let id = UUID()
    let stagedURL: URL
    let fileName: String
}

private struct GallerySyncImportResult: Sendable {
    let galleryOutcome: GallerySyncImportOutcome
    let queuedDownloadCount: Int
    let incompleteMetadataCount: Int
}

enum DownloadedGalleryMetadataRefreshMode: String, CaseIterable, Identifiable, Sendable {
    case all
    case missingOnly

    var id: Self { self }
}

struct DownloadedGalleryMetadataRefreshResult: Sendable, Hashable {
    let targetCount: Int
    let completeCount: Int
    let failedCount: Int
    let incompleteCount: Int
    let gdataRetriedCount: Int
    let detailCompletionCount: Int
    let removedEmptyGalleryCount: Int
    let invalidPageCount: Int

    static let empty = DownloadedGalleryMetadataRefreshResult(
        targetCount: 0,
        completeCount: 0,
        failedCount: 0,
        incompleteCount: 0,
        gdataRetriedCount: 0,
        detailCompletionCount: 0,
        removedEmptyGalleryCount: 0,
        invalidPageCount: 0
    )
}

struct DownloadRestoreOutcome: Sendable {
    let candidateCount: Int
    let importedItemCount: Int
    let mergedItemCount: Int
    let skippedDuplicateItemCount: Int
    let importedPageCount: Int
    let skippedDuplicatePageCount: Int
    let failedPageCount: Int
    let invalidItemCount: Int
    let incompleteMetadataCount: Int
    let issues: [FileOperationIssue]
    let message: String

    init(
        candidateCount: Int = 0,
        importedItemCount: Int = 0,
        mergedItemCount: Int = 0,
        skippedDuplicateItemCount: Int = 0,
        importedPageCount: Int = 0,
        skippedDuplicatePageCount: Int = 0,
        failedPageCount: Int = 0,
        invalidItemCount: Int = 0,
        incompleteMetadataCount: Int = 0,
        issues: [FileOperationIssue] = [],
        message: String
    ) {
        self.candidateCount = candidateCount
        self.importedItemCount = importedItemCount
        self.mergedItemCount = mergedItemCount
        self.skippedDuplicateItemCount = skippedDuplicateItemCount
        self.importedPageCount = importedPageCount
        self.skippedDuplicatePageCount = skippedDuplicatePageCount
        self.failedPageCount = failedPageCount
        self.invalidItemCount = invalidItemCount
        self.incompleteMetadataCount = incompleteMetadataCount
        self.issues = issues
        self.message = message
    }
}

private struct StagedIncomingFile: Sendable {
    let directory: URL
    let stagedURL: URL
    let fileName: String
}

private actor MetadataRequestScheduler {
    private let maximumConcurrentRequests = 2
    private let minimumStartInterval: TimeInterval = 0.3
    private var activeRequests = 0
    private var lastStart = Date.distantPast
    private var stopped = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async -> Bool {
        while activeRequests >= maximumConcurrentRequests, stopped == false {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
        guard stopped == false else { return false }

        activeRequests += 1
        let nextStart = max(Date(), lastStart.addingTimeInterval(minimumStartInterval))
        lastStart = nextStart
        let delay = nextStart.timeIntervalSinceNow
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        guard Task.isCancelled == false, stopped == false else {
            release()
            return false
        }
        return true
    }

    func release() {
        activeRequests = max(0, activeRequests - 1)
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        }
    }

    func stop() {
        stopped = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}

private enum IncomingStagingOutcome: Sendable {
    case success(StagedIncomingFile)
    case failure(String)
}

private struct SearchPageKey: Hashable {
    let query: String
    let advancedSearch: GalleryAdvancedSearch?
}

struct GalleryDownloadEnqueueProgress: Equatable, Sendable {
    let completed: Int
    let total: Int
    let enqueued: Int
    let failed: Int
}

struct GalleryDownloadEnqueueResult: Equatable, Sendable {
    let requested: Int
    let enqueued: Int
    let failed: Int
    let cancelled: Bool
}

private func makePersistedDownloadSnapshot(_ job: DownloadJob) -> PersistedDownload {
    PersistedDownload(
        key: job.key,
        title: job.title,
        japaneseTitle: job.japaneseTitle,
        tags: job.tags,
        pages: job.pages,
        totalPageCount: job.totalPageCount,
        createdAt: job.addedAt,
        label: job.label,
        completedPageIndexes: job.completedPageIndexes,
        stateRaw: job.state.rawValue,
        errorMessage: job.errorMessage
    )
}

@MainActor
@Observable
final class AppModel {
    @ObservationIgnored private let downloadBaselineLoader: (@Sendable () async throws -> [PersistedDownload])?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let forceGuestMode: Bool
    let api: any EHAPI
    let persistence: PersistenceStore
    let downloads: DownloadCoordinator
    let sessionVault: SessionVault
    let imagePipeline: ImagePipeline
    let galleryCoverLoader: GalleryCoverLoader
    let backgroundSession: BackgroundDownloadSession
    let downloadFiles: DownloadFileStore
    let deviceSync: DeviceSyncCoordinator
#if os(iOS)
    let deviceSyncRuntime: DeviceSyncRuntime
    let downloadBackgroundTask: DownloadBackgroundTaskController
#endif
    let deviceSyncIndex: DeviceSyncIndexStore
    let galleryCache: GalleryCacheStore
    let tagSuggestionProvider: TagSuggestionProvider

    var site: SiteMode
    var readingSettings: ReadingSettings
    var downloadSortOrder: DownloadSortOrder
    var downloadStatusFilter: DownloadStatusFilter
    var downloadLayoutMode: DownloadsLayoutMode
    var downloadCategoryFilter: Set<GalleryCategory>
    private(set) var galleryCacheByteCount: Int64 = 0
    private(set) var localDownloadGalleryCount = 0
    private(set) var localDownloadByteCount: Int64 = 0
    private(set) var hasLoadedLocalDownloadUsage = false
    private(set) var isRefreshingLocalDownloadUsage = false
    private(set) var isDeletingAllLocalManga = false
    private(set) var localMangaDeletionProgress: DownloadRemovalProgress?
    var galleries: [GallerySummary] = []
    var historyGalleries: [GallerySummary] = []
    var favoriteGalleries: [GallerySummary] = []
    var filterRules: [FilterRuleSnapshot] = []
    var tagTranslations: [String: String] = [:] {
        didSet { tagTranslationsRevision &+= 1 }
    }
    private(set) var tagTranslationsRevision = 0
    var tagDatabaseUpdateStatus: TagDatabaseUpdateStatus = .unknown
    private(set) var tagDatabaseUpdateError: String?
    private(set) var isCheckingTagDatabaseUpdate = false
    private(set) var isUpdatingTagDatabase = false
    var quickSearches: [String] = []
    var searchHistorySuggestions: [String] = []
    var tagSearchSuggestions: [SearchTagSuggestion] = []
    var localArchive: LocalArchiveDocument?
    var startupPage: StartupPage = .local {
        didSet { defaults.set(startupPage.rawValue, forKey: "startupPage") }
    }
    var selectedRoute: AppRoute? = .local
    private(set) var localDownloadLoadError: String?
    var browseRefreshToken = 0
    private(set) var localLibraryRevision = 0
    var isLoading = false
    var searchText = ""
    var submittedSearchText = ""
    var pendingSearchQuery: String?
    var isGuestMode = true
    var isPasswordLoginInProgress = false
    var errorMessage: String?
    var pendingIncomingArchive: PendingIncomingArchive?
    var pendingIncomingGallerySync: PendingIncomingGallerySync?
    var importResultMessage: String?
    var pendingSharedFileURL: URL?
    var isRestoringDownloads = false
    var downloadRestoreStatus = ""
    private(set) var downloadRestoreProgress: MigrationProgress?
    private(set) var isMigrating = false
    private(set) var migrationProgress: MigrationProgress?
    private(set) var isLoadingDownloads = true
    private(set) var isReady = false
    var isDeviceSyncIndexSetupRequired = false
    private(set) var nextPageURL: URL?
    var hasMorePage: Bool { nextPageURL != nil }
    private var activeQuery = GalleryListQuery()
    private var activeListRequestID = UUID()
    @ObservationIgnored private var searchPageModels: [SearchPageKey: BrowsePageModel] = [:]
    @ObservationIgnored private var incomingStagingGeneration = 0
    @ObservationIgnored private var incomingStagingTask: Task<Void, Never>?
    @ObservationIgnored private var currentFileOperationTask: Task<Void, Never>?
    @ObservationIgnored private var fileOperationGeneration = 0
    @ObservationIgnored private var tagTranslationLoadTask: Task<Void, Never>?
    @ObservationIgnored private var tagTranslationImportTask: Task<Void, Never>?
    @ObservationIgnored private var hasLoadedReferenceTagTranslations = false
    @ObservationIgnored private var downloadRevisionTask: Task<Void, Never>?
    @ObservationIgnored private var readyContinuations: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var localRestoreTask: Task<Void, Never>?
    @ObservationIgnored private var startupMaintenanceTask: Task<Void, Never>?
    @ObservationIgnored private var isShuttingDown = false

    init(
        container: ModelContainer,
        persistenceStore: PersistenceStore? = nil,
        beforeLocalRestore: (@Sendable () async throws -> Void)? = nil,
        downloadBaselineLoader: (@Sendable () async throws -> [PersistedDownload])? = nil,
        api: (any EHAPI)? = nil,
        sessionVault: SessionVault = SessionVault(),
        defaults: UserDefaults = .standard,
        downloadFiles: DownloadFileStore? = nil,
        galleryCache: GalleryCacheStore? = nil,
        tagSuggestionProvider: TagSuggestionProvider = TagSuggestionProvider(),
        imagePipeline: ImagePipeline? = nil,
        galleryCoverLoader: GalleryCoverLoader? = nil,
        deviceSyncIndex: DeviceSyncIndexStore? = nil,
        deviceSyncTransactionRoot: URL? = nil,
        backgroundDownloadIdentifier: String = "com.liao.ehviewer.background-downloads",
        profileID: UUID? = nil
    ) {
        let arguments = ProcessInfo.processInfo.arguments
        let forceGuestModeForUITest = arguments.contains("-UITestUseGuestMode")
        self.defaults = defaults
#if DEBUG
        let useLocalSearchFixtures = forceGuestModeForUITest
            && arguments.contains("-UITestLocalSearchFixtures")
        if useLocalSearchFixtures, downloadBaselineLoader == nil {
            self.downloadBaselineLoader = {
                [
                    ("Blue Archive A", "female:elf"),
                    ("Blue Archive Z", "female:elf"),
                    ("Green Garden", "female:fairy")
                ].enumerated().map { index, fixture in
                    let key = GalleryKey(gid: Int64(900_000 + index), token: "local-search-test")
                    let page = GalleryPageDescriptor(
                        galleryKey: key,
                        index: 0,
                        pageURL: URL(string: "https://example.invalid/local-search/\(index)")!
                    )
                    return PersistedDownload(
                        key: key,
                        title: fixture.0,
                        tags: [fixture.1],
                        pages: [page],
                        completedPageIndexes: [0],
                        stateRaw: DownloadState.completed.rawValue,
                        errorMessage: nil
                    )
                }
            }
        } else {
            self.downloadBaselineLoader = downloadBaselineLoader
        }
        let initialPage: StartupPage = useLocalSearchFixtures ? .local : StartupPage.load(from: defaults)
#else
        self.downloadBaselineLoader = downloadBaselineLoader
        let initialPage = StartupPage.load(from: defaults)
#endif
        startupPage = initialPage
        selectedRoute = initialPage.route
        forceGuestMode = forceGuestModeForUITest
        let savedSite = SiteMode(rawValue: defaults.string(forKey: "site") ?? "") ?? .eHentai
        let selectedSite = forceGuestModeForUITest ? SiteMode.eHentai : savedSite
        site = selectedSite
        readingSettings = ReadingSettings.load(from: defaults)
        downloadSortOrder = DownloadSortOrder(
            rawValue: defaults.string(forKey: "downloadSortOrder") ?? ""
        ) ?? .titleAscending
        downloadStatusFilter = DownloadStatusFilter(
            rawValue: defaults.string(forKey: "downloadStatusFilter") ?? ""
        ) ?? .all
        downloadLayoutMode = DownloadsLayoutMode(
            rawValue: defaults.string(forKey: "downloadLayoutMode") ?? ""
        ) ?? .list
        downloadCategoryFilter = Self.loadDownloadCategoryFilter(from: defaults)
#if DEBUG
        if useLocalSearchFixtures {
            downloadSortOrder = .titleAscending
            downloadLayoutMode = .list
            downloadCategoryFilter = Set(GalleryCategory.allCases)
        }
#endif
        if forceGuestModeForUITest {
            isGuestMode = true
        }
        defaults.removeObject(forKey: "appLockEnabled")
        self.sessionVault = sessionVault
        self.tagSuggestionProvider = tagSuggestionProvider
        let client: any EHAPI = api ?? EHClient(sessionVault: sessionVault)
        self.api = client
        let index = deviceSyncIndex ?? DeviceSyncIndexStore()
        let store = persistenceStore ?? PersistenceStore(modelContainer: container)
        persistence = store
        self.imagePipeline = imagePipeline ?? ImagePipeline()
        let fileStore = downloadFiles ?? DownloadFileStore()
        self.downloadFiles = fileStore
        self.deviceSyncIndex = index
        self.deviceSync = DeviceSyncCoordinator(
            persistence: store,
            files: fileStore,
            index: index,
            transactionRoot: deviceSyncTransactionRoot
        )
#if os(iOS)
        self.deviceSyncRuntime = DeviceSyncRuntime(coordinator: self.deviceSync)
#endif
        self.galleryCache = galleryCache ?? GalleryCacheStore()
        self.galleryCoverLoader = galleryCoverLoader ?? GalleryCoverLoader()
        let expectedProfileID = profileID?.uuidString
        let backgroundSession = BackgroundDownloadSession(
            identifier: backgroundDownloadIdentifier,
            taskObserver: { description, identifier in
                guard let parsed = parseDownloadTaskDescription(description),
                      parsed.profileID == expectedProfileID else { return }
                let (key, pageIndex) = (parsed.key, parsed.pageIndex)
                try? await store.setBackgroundTaskIdentifier(identifier, for: key, pageIndex: pageIndex)
            },
            orphanCompletion: { description, data, statusCode in
                guard (200..<300).contains(statusCode),
                      let parsed = parseDownloadTaskDescription(description),
                      parsed.profileID == expectedProfileID else { return }
                let (key, pageIndex) = (parsed.key, parsed.pageIndex)
                do {
                    _ = try await fileStore.write(data, for: key, pageIndex: pageIndex)
                    try await store.markDownloadPageCompleted(for: key, pageIndex: pageIndex, bytes: Int64(data.count))
                } catch {
                    return
                }
            }
        )
        self.backgroundSession = backgroundSession
        let downloadClient = client
        let downloadSite = selectedSite
        downloads = DownloadCoordinator(
            pageLoader: { descriptor in
                let pageSite = SiteMode.allCases.first { $0.host == descriptor.pageURL.host?.lowercased() } ?? downloadSite
                var pageDescriptor = descriptor
                var lastValidationError: EHError?

                for attempt in 0..<5 {
                    try Task.checkCancellation()
                    let pageImage: GalleryPageImage
                    if pageDescriptor.requiresPageResolution {
                        pageImage = try await downloadClient.pageImage(for: pageDescriptor, site: pageSite)
                    } else {
                        pageImage = GalleryPageImage(
                            galleryKey: pageDescriptor.galleryKey,
                            index: pageDescriptor.index,
                            imageURL: pageDescriptor.pageURL
                        )
                    }

                    var request = URLRequest(url: pageImage.imageURL)
                    request.httpMethod = "GET"
                    request.setValue("image/avif,image/webp,image/apng,video/mp4,video/*,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
                    request.setValue("EhViewer/0.1 (personal use)", forHTTPHeaderField: "User-Agent")
                    request.setValue(pageDescriptor.pageURL.absoluteString, forHTTPHeaderField: "Referer")
                    if CookieHeader.isTrustedURL(pageImage.imageURL),
                       let cookieHeader = try? await sessionVault.loadAuthenticatedCookieHeader() {
                        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
                    }

                    let data = try await backgroundSession.data(
                        for: request,
                        taskDescription: makeDownloadTaskDescription(
                            profileID: expectedProfileID,
                            key: descriptor.galleryKey,
                            pageIndex: descriptor.index
                        )
                    )
                    do {
                        try DownloadMediaValidator.validate(data)
                        return data
                    } catch let error as EHError {
                        lastValidationError = error
                        guard attempt < 4 else { throw error }
                        if descriptor.requiresPageResolution,
                           let skipHathKey = pageImage.skipHathKey {
                            pageDescriptor = Self.pageDescriptor(descriptor, skippingHathNodeWith: skipHathKey)
                        } else {
                            pageDescriptor = descriptor
                        }
                    }
                }
                throw lastValidationError ?? EHError.parsingFailed(String(localized: "下载结果不是有效图片或视频"))
            },
            pageListLoader: { job, index in
                try await downloadClient.previewPages(for: job.key, site: job.sourceSite ?? downloadSite, startingAt: index)
            },
            pageCompletionPersistence: { key, index in
                try? await store.markDownloadPageCompleted(for: key, pageIndex: index)
            },
            fileStore: fileStore,
            persistence: { job in
                try? await store.upsertDownload(
                    key: job.key,
                    title: job.title,
                    japaneseTitle: job.japaneseTitle,
                    tags: job.tags,
                    pages: job.pages,
                    totalPageCount: job.totalPageCount,
                    completedPageIndexes: job.completedPageIndexes,
                    stateRaw: job.state.rawValue,
                    errorMessage: job.errorMessage,
                    label: job.label
                )
            },
            batchPersistence: { jobs in
                try? await store.upsertDownloads(jobs.map(makePersistedDownloadSnapshot))
            },
            removal: { key in
                try await store.deleteDownload(for: key)
            },
            batchRemoval: { keys in
                try await store.deleteDownloads(for: keys)
            }
        )
        #if os(iOS)
        self.downloadBackgroundTask = DownloadBackgroundTaskController(coordinator: self.downloads)
        #endif
        startupMaintenanceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.migrateLegacyGalleryCache()
            guard !Task.isCancelled else { return }
            await self.galleryCoverLoader.removeLegacyLocalEntries()
            guard !Task.isCancelled else { return }
            await self.refreshGalleryCacheUsage()
            guard !Task.isCancelled else { return }
            if self.forceGuestMode == false {
                await self.refreshSessionStatus()
            }
            guard !Task.isCancelled else { return }
            await self.loadFilterRules()
        }
        localRestoreTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await beforeLocalRestore?()
                try Task.checkCancellation()
            } catch {
                guard !Task.isCancelled else { return }
                self.localDownloadLoadError = error.localizedDescription
                self.isLoadingDownloads = false
                self.markReady()
                return
            }
            await store.configureDeviceSyncIndex(index)
            guard !Task.isCancelled else { return }
            await fileStore.configureDeviceSyncIndex(index)
            guard !Task.isCancelled else { return }
            self.isDeviceSyncIndexSetupRequired = await index.status() != .ready
            _ = await self.downloadFiles.sweepTemporaryFiles()
            guard !Task.isCancelled else { return }
            let recovery = await self.deviceSync.recoverInterruptedTransfers()
            guard !Task.isCancelled else { return }
            if recovery.recoveredAnything {
                self.importResultMessage = String(
                    localized: "上次设备同步已恢复：保留 \(recovery.completedGalleryCount) 本，回滚未完成画廊 \(recovery.rolledBackGalleryCount) 本。"
                )
                self.publishLocalLibraryChange()
            }
            guard !Task.isCancelled else { return }
            await self.restoreDownloads()
        }
        Task.detached(priority: .utility) {
            Self.sweepStaleTemporaryFiles()
        }
        // The persisted translation lookup and the bundled database decode do
        // not depend on one another. Start both together, then import only
        // after the in-memory lookup has established whether the reference
        // locale is already present. This removes one full 44k-row query on
        // the warm path while allowing the two cold-start operations to
        // overlap.
        let tagTranslationTask = Task { @MainActor [weak self, tagSuggestionProvider] in
            guard let self else { return }
            async let loadTranslations: Void = self.loadTagTranslations()
            async let preloadDatabase: Void = tagSuggestionProvider.preload()
            await loadTranslations
            await preloadDatabase
            await self.importTagTranslationsIfNeeded()
        }
        self.tagTranslationLoadTask = tagTranslationTask
        self.tagTranslationImportTask = tagTranslationTask
        let downloads = self.downloads
        self.downloadRevisionTask = Task { @MainActor [weak self, downloads] in
            for await event in await downloads.events() {
                guard let self else { return }
                #if os(iOS)
                self.downloadBackgroundTask.update(event)
                #endif
                switch event {
                case .reset, .removed, .removedMany:
                    self.publishLocalLibraryChange()
                case .changed(let job) where job.state == .completed:
                    self.publishLocalLibraryChange()
                case .changed:
                    break
                }
            }
        }
    }

    /// Releases work that belongs to this runtime before another profile is
    /// installed. Every asynchronous callback is invalidated before the
    /// runtime's container can be discarded.
    func shutdown() async {
        isShuttingDown = true
        localRestoreTask?.cancel()
        startupMaintenanceTask?.cancel()
        await sessionVault.invalidatePendingRequests()
        markReady()
        activeListRequestID = UUID()
        incomingStagingGeneration &+= 1
        fileOperationGeneration &+= 1
        incomingStagingTask?.cancel()
        incomingStagingTask = nil
        currentFileOperationTask?.cancel()
        currentFileOperationTask = nil
        tagTranslationLoadTask?.cancel()
        tagTranslationLoadTask = nil
        tagTranslationImportTask?.cancel()
        tagTranslationImportTask = nil
        downloadRevisionTask?.cancel()
        downloadRevisionTask = nil
        await downloads.stopAll()
        await backgroundSession.cancelAll()
#if os(iOS)
        deviceSyncRuntime.shutdown()
        downloadBackgroundTask.shutdown()
#endif
        deviceSync.stop()
        await galleryCoverLoader.removeAll()
    }

    /// Waits until the persisted download baseline is available in the
    /// coordinator. The UI must not expose an empty in-memory snapshot as if
    /// it were an empty library while profile startup is still restoring.
    func waitUntilReady() async {
        guard isReady == false else { return }
        await withCheckedContinuation { continuation in
            if isReady {
                continuation.resume()
            } else {
                readyContinuations.append(continuation)
            }
        }
    }

    private func markReady() {
        guard isReady == false else { return }
        isReady = true
        let continuations = readyContinuations
        readyContinuations = []
        for continuation in continuations { continuation.resume() }
    }

    func load(query: GalleryListQuery? = nil) async {
        let requestID = UUID()
        activeListRequestID = requestID
        isLoading = true
        nextPageURL = nil
        var loadedNextPageURL: URL?
        var didLoadPage = false
        defer {
            if activeListRequestID == requestID {
                isLoading = false
                if didLoadPage {
                    nextPageURL = loadedNextPageURL
                }
            }
        }
        let query = query ?? GalleryListQuery(site: site, searchText: searchText.nilIfEmpty)
        activeQuery = query
        do {
            let result = if query.kind == .favorites {
                try await api.favorites(query: query)
            } else {
                try await api.list(query: query)
            }
            try Task.checkCancellation()
            guard activeListRequestID == requestID else { return }
            let items = await enrichedForBrowse(result.items)
            galleries = items.filter(matchesFilter)
            loadedNextPageURL = result.cursor?.nextPageURL
            didLoadPage = true
            for item in items {
                try await persistence.upsertStableSnapshot(
                    StableGalleryMetadataSnapshot(summary: item, sourceSite: site)
                )
            }
            if let searchText = query.searchText { try? await persistence.recordQuickSearch(searchText) }
            quickSearches = (try? await persistence.quickSearches()) ?? quickSearches
        } catch is CancellationError {
            // View lifecycle cancellation is expected.
        } catch {
            if activeListRequestID == requestID {
                errorMessage = error.localizedDescription
            }
        }
    }

    var canCancelCurrentFileOperation: Bool {
        currentFileOperationTask != nil || incomingStagingTask != nil
    }

    func runFileOperation(_ operation: @escaping @MainActor () async -> Void) {
        currentFileOperationTask?.cancel()
        fileOperationGeneration += 1
        let generation = fileOperationGeneration
        currentFileOperationTask = Task { @MainActor [weak self] in
            await operation()
            guard let self, self.fileOperationGeneration == generation else { return }
            self.currentFileOperationTask = nil
        }
    }

    func cancelCurrentFileOperation() {
        fileOperationGeneration += 1
        currentFileOperationTask?.cancel()
        currentFileOperationTask = nil
        incomingStagingGeneration += 1
        incomingStagingTask?.cancel()
        incomingStagingTask = nil
        migrationProgress = nil
    }

    func confirmDeviceSync() {
        guard !isLoadingDownloads, localDownloadLoadError == nil, !isShuttingDown else { return }
#if os(iOS)
        guard deviceSyncRuntime.prepareForUserInitiatedSync() else {
            errorMessage = String(
                localized: "系统当前无法为设备同步申请持续后台执行，请保持应用在前台后重试。"
            )
            return
        }
#endif
        deviceSync.confirmSync()
    }

    func buildDeviceSyncIndex() async {
        guard !isLoadingDownloads, localDownloadLoadError == nil, !isShuttingDown else { return }
        guard beginMigration(status: String(localized: "正在建立设备同步索引…")) else { return }
        defer { finishMigration() }
        do {
            try await deviceSync.rebuildIndex { [weak self] completed, total in
                let status: String
                if total > 1, completed <= total / 2 {
                    status = String(localized: "正在扫描本地页面…")
                } else {
                    status = String(localized: "正在整理同步索引…")
                }
                self?.setMigrationProgress(
                    status: status,
                    completed: completed,
                    total: total
                )
            }
            isDeviceSyncIndexSetupRequired = false
        } catch is CancellationError {
            // Keep synchronization blocked, but do not reopen the startup
            // prompt after the user explicitly cancelled the rebuild.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// List pages only carry a few summary tags. Fetch the full tag list for
    /// every browse page so cards can display the same tags used for filtering.
    func enrichedForBrowse(_ items: [GallerySummary]) async -> [GallerySummary] {
        guard items.isEmpty == false else { return items }
        guard let fetched = try? await api.gallerySummaries(for: items.map(\.key), site: site),
              fetched.isEmpty == false else { return items }
        let summariesByKey = Dictionary(uniqueKeysWithValues: fetched.map { ($0.key, $0) })
        return items.map { item in
            guard let fetchedSummary = summariesByKey[item.key] else { return item }
            var enriched = item
            enriched.tags = fetchedSummary.tags
            enriched.metadataCompleteness = fetchedSummary.metadataCompleteness
            return enriched
        }
    }

    func loadBrowseQuery(_ query: GalleryListQuery) async {
        guard galleries.isEmpty || isActiveList(query) == false else { return }
        await load(query: query)
    }

    private func isActiveList(_ query: GalleryListQuery) -> Bool {
        var requestedQuery = query
        requestedQuery.page = 0
        var currentQuery = activeQuery
        currentQuery.page = 0
        return requestedQuery == currentQuery
    }

    func searchTag(_ tag: String) {
        let normalizedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedTag.isEmpty == false else { return }
        let searchSyntax = SearchQueryComposer.searchSyntax(for: normalizedTag)
        pendingSearchQuery = searchSyntax
        selectedRoute = .browse
    }

    func searchPageModel(for query: String, advancedSearch: GalleryAdvancedSearch? = nil) -> BrowsePageModel {
        let normalized = SearchQueryComposer.normalized(query)
        let key = SearchPageKey(query: normalized, advancedSearch: advancedSearch)
        if let cached = searchPageModels[key] { return cached }
        let pageModel = BrowsePageModel(
            model: self,
            kind: .search,
            initialSearchText: normalized,
            initialAdvancedSearch: advancedSearch
        )
        searchPageModels[key] = pageModel
        return pageModel
    }

    func updateSearchSuggestions(for query: String) async {
        let normalizedQuery = SearchQueryComposer.normalized(query)
        searchHistorySuggestions = []
        tagSearchSuggestions = []
        do {
            if normalizedQuery.isEmpty == false {
                try await Task.sleep(for: .milliseconds(120))
            }
            async let history = persistence.quickSearchSuggestions(prefix: normalizedQuery)
            let fragment = SearchQueryComposer.suggestionFragment(in: normalizedQuery)
            async let tags = tagSuggestionProvider.suggestions(for: fragment)
            let (loadedHistory, loadedTags) = try await (history, tags)
            try Task.checkCancellation()
            guard SearchQueryComposer.normalized(searchText) == normalizedQuery else { return }
            searchHistorySuggestions = loadedHistory
            tagSearchSuggestions = loadedTags
        } catch is CancellationError {
            return
        } catch {
            searchHistorySuggestions = (try? await persistence.quickSearchSuggestions(prefix: normalizedQuery)) ?? []
            tagSearchSuggestions = []
        }
    }

    func completeTagSuggestion(_ tag: String) {
        searchText = SearchQueryComposer.completing(tag: tag, in: searchText)
    }

    func selectSearchHistory(_ query: String) {
        let normalized = SearchQueryComposer.normalized(query)
        searchText = normalized
    }

    func deleteSearchHistory(_ query: String) async {
        do {
            try await persistence.deleteQuickSearch(query)
            await loadQuickSearches()
            await updateSearchSuggestions(for: searchText)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submitSearch() {
        let normalized = SearchQueryComposer.normalized(searchText)
        searchText = normalized
        submittedSearchText = normalized
    }

    func loadMore() async {
        guard let pageURL = nextPageURL, isLoading == false else { return }
        let requestID = activeListRequestID
        var query = activeQuery
        query.page += 1
        isLoading = true
        var loadedNextPageURL: URL?
        var didLoadPage = false
        defer {
            if activeListRequestID == requestID {
                isLoading = false
                if didLoadPage {
                    nextPageURL = loadedNextPageURL
                }
            }
        }
        do {
            let result = try await api.list(query: query, pageURL: pageURL)
            try Task.checkCancellation()
            guard activeListRequestID == requestID else { return }
            appendUniqueGalleries(result.items)
            loadedNextPageURL = result.cursor?.nextPageURL
            didLoadPage = true
            activeQuery = query
            try await persistence.upsert(result.items)
        } catch is CancellationError {
            return
        } catch {
            if activeListRequestID == requestID {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadMoreIfNeeded(after galleryKey: GalleryKey) async {
        guard galleries.last?.key == galleryKey else { return }
        await loadMore()
    }

    func retryLastListRequest() async {
        await load(query: activeQuery)
    }

    func requestBrowseRefresh() {
        browseRefreshToken &+= 1
    }

    func detail(for key: GalleryKey) async throws -> GalleryDetail {
        let detail = try await api.detail(for: key, site: site)
        let stable = StableGalleryMetadataSnapshot(detail: detail, sourceSite: site)
        if await downloads.job(for: key) != nil {
            try await persistence.promoteToDownloadedGallery(
                stable: stable,
                dynamic: DownloadedGalleryDynamicSnapshot(detail: detail)
            )
        } else {
            try await persistence.upsertStableSnapshot(stable)
        }
        return detail
    }

    func detailStream(for key: GalleryKey) -> AsyncThrowingStream<GalleryDetail, Error> {
        let api = api
        let site = site
        let (stream, continuation) = AsyncThrowingStream<GalleryDetail, Error>.makeStream()
        let task = Task {
            do {
                continuation.yield(try await api.detailPreview(for: key, site: site))
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    func previewPages(for key: GalleryKey, startingAt index: Int, sourceSite: SiteMode? = nil) async throws -> [GalleryPageDescriptor] {
        try await api.previewPages(for: key, site: sourceSite ?? site, startingAt: index)
    }

    /// Builds the detail page exclusively from download-owned metadata and the
    /// download job. Ordinary browsing metadata/cache is never consulted.
    func localGalleryDetail(for key: GalleryKey, job: DownloadJob? = nil) async -> GalleryDetail? {
        let resolvedJob: DownloadJob?
        if let job {
            resolvedJob = job
        } else {
            resolvedJob = await downloads.job(for: key)
        }
        guard let job = resolvedJob else { return nil }

        let transfer = try? await persistence.downloadedTransferRecord(for: key)
        let stable = transfer?.stable
        let dynamic = transfer?.dynamic
        let pagesByIndex = Dictionary(((stable?.pages ?? []) + job.pages).map { ($0.index, $0) }, uniquingKeysWith: { first, _ in first })
        let pages = pagesByIndex.values.sorted { $0.index < $1.index }
        var localSummary = stable?.detail(with: dynamic).summary ?? GallerySummary(
            key: key,
            title: job.title,
            japaneseTitle: job.japaneseTitle,
            pageCount: job.totalPageCount > 0 ? job.totalPageCount : nil,
            tags: job.tags
        )
        if localSummary.title.isEmpty { localSummary.title = job.title }
        if localSummary.japaneseTitle == nil { localSummary.japaneseTitle = job.japaneseTitle }
        if localSummary.tags.isEmpty,
           localSummary.metadataCompleteness?.tags.isLoaded != true {
            localSummary.tags = job.tags
        }
        if localSummary.pageCount == nil, pages.isEmpty == false {
            localSummary.pageCount = job.totalPageCount
        }
        return GalleryDetail(
            summary: localSummary,
            pages: pages,
            tags: localSummary.tags,
            comments: dynamic?.comments.map(\.galleryComment) ?? [],
            descriptionText: stable?.descriptionText,
            externalURL: stable?.externalURL ?? URL(string: "https://\(site.host)/g/\(key.gid)/\(key.token)/"),
            apiUID: nil,
            apiKey: nil,
            favoriteCount: dynamic?.favoriteCount,
            favoriteName: dynamic?.favoriteName,
            ratingCount: dynamic?.ratingCount ?? localSummary.ratingCount,
            language: stable?.language,
            fileSize: stable?.fileSize,
            torrentURL: nil,
            torrentCount: nil,
            archiveURL: nil
        )
    }

    /// Returns metadata already persisted for local galleries. The local page
    /// must remain offline-first: gdata refreshes belong to explicit import or
    /// update actions and must not be triggered by scrolling this list.
    func localGallerySummaries(for keys: Set<GalleryKey>) async -> [GallerySummary] {
        guard keys.isEmpty == false else { return [] }
        return (try? await persistence.localGallerySummaries(for: keys)) ?? []
    }

    private func publishLocalLibraryChange() {
        localLibraryRevision &+= 1
    }

    func prepareTagTranslations() async {
        await tagTranslationLoadTask?.value
        await tagTranslationImportTask?.value
    }

    func cachedDetail(for key: GalleryKey) async -> GalleryDetail? {
        if let stored = try? await persistence.stableSnapshot(for: key) {
            return stored.detail()
        }
        guard let migrated = await galleryCache.stableSnapshot(for: key, site: site) else { return nil }
        try? await persistence.upsertStableSnapshot(migrated)
        return migrated.detail()
    }

    private func migrateLegacyGalleryCache() async {
        let snapshots = await galleryCache.legacyStableSnapshots()
        for snapshot in snapshots {
            guard !Task.isCancelled else { return }
            try? await persistence.upsertStableSnapshot(snapshot)
        }
    }

    func cacheDetail(_ detail: GalleryDetail, generation: UInt64? = nil) async {
        let snapshot = StableGalleryMetadataSnapshot(detail: detail, sourceSite: site)
        try? await persistence.upsertStableSnapshot(snapshot)
        await galleryCache.save(snapshot, for: detail.summary.key, site: site, generation: generation)
    }

    func galleryCacheGeneration() async -> UInt64 {
        await galleryCache.currentGeneration()
    }

    func pageImage(for descriptor: GalleryPageDescriptor) async throws -> GalleryPageImage {
        try await api.pageImage(for: descriptor, site: site)
    }

    func imageData(for image: GalleryPageImage, resolution: ImageResolution = .preview) async throws -> Data {
        let api = self.api
        return try await imagePipeline.data(for: imageURL(for: image, resolution: resolution)) {
            try await api.imageData(for: image, resolution: resolution)
        }
    }

    func galleryImageData(for image: GalleryPageImage, resolution: ImageResolution = .preview) async throws -> Data {
        let api = self.api
        let data = try await galleryCache.imageData(for: image, resolution: resolution) {
            try await api.imageData(for: image, resolution: resolution)
        }
        if let localPath = await galleryCache.imageCachePath(for: image, resolution: resolution) {
            try? await persistence.recordImageIndex(
                key: image.galleryKey,
                site: site,
                kind: "preview",
                pageIndex: image.index,
                originalURL: image.originImageURL ?? image.imageURL,
                localPath: localPath,
                byteCount: Int64(data.count)
            )
        }
        return data
    }

    /// Loads a cover through the shared memory/disk thumbnail pipeline. The
    /// original page is fetched only when the generated thumbnail is absent.
    func coverImage(
        for key: GalleryKey,
        previewURL: URL,
        prefersGalleryCache: Bool = false,
        maxPixelSize: Int
    ) async throws -> CGImage? {
        let cacheKey = "remote|\(key.id)|\(previewURL.absoluteString)|\(prefersGalleryCache)|\(maxPixelSize)"
        return try await galleryCoverLoader.image(
            for: cacheKey,
            maxPixelSize: maxPixelSize
        ) { [self] in
            let page = GalleryPageImage(galleryKey: key, index: 0, imageURL: previewURL)
            if prefersGalleryCache {
                return try await galleryImageData(for: page)
            }
            return try await imageData(for: page)
        }
    }

    /// Loads a completed local page through the persistent thumbnail cache.
    /// Missing local media remains missing in the local UI.
    func coverImage(
        for job: DownloadJob,
        maxPixelSize: Int
    ) async throws -> CGImage? {
        guard let pageIndex = job.pages.first(where: {
            job.completedPageIndexes.contains($0.index)
        })?.index else { return nil }
        let url = await downloadFiles.finalURL(for: job.key, pageIndex: pageIndex)
        return await galleryCoverLoader.localImage(
            fileURL: url,
            maxPixelSize: maxPixelSize
        )
    }

    func coverImage(
        for key: GalleryKey,
        previewURL: URL?,
        localPage: GalleryPageDescriptor?,
        maxPixelSize: Int
    ) async throws -> CGImage? {
        if let localPage {
            let url = await downloadFiles.finalURL(for: key, pageIndex: localPage.index)
            return await galleryCoverLoader.localImage(
                fileURL: url,
                maxPixelSize: maxPixelSize
            )
        }
        guard let previewURL else { return nil }
        return try await coverImage(
            for: key,
            previewURL: previewURL,
            prefersGalleryCache: true,
            maxPixelSize: maxPixelSize
        )
    }

    func refreshGalleryCacheUsage() async {
        galleryCacheByteCount = await galleryCache.usage().byteCount
    }

    func clearGalleryCache() async {
        try? await persistence.clearOrdinaryCache()
        await galleryCache.removeAll()
        try? await persistence.clearLibraryState()
        historyGalleries = []
        favoriteGalleries = []
        await refreshGalleryCacheUsage()
    }

    func refreshLocalDownloadUsage() async {
        guard isRefreshingLocalDownloadUsage == false else { return }
        isRefreshingLocalDownloadUsage = true
        defer { isRefreshingLocalDownloadUsage = false }
        let keys = await downloads.snapshot().map(\.key)
        let usage = await downloadFiles.localLibraryUsage(for: keys)
        localDownloadGalleryCount = usage.galleryCount
        localDownloadByteCount = usage.byteCount
        hasLoadedLocalDownloadUsage = true
    }

    func deleteAllLocalManga() async {
        guard !isLoadingDownloads, localDownloadLoadError == nil, !isShuttingDown else { return }
        guard isDeletingAllLocalManga == false else { return }
        let keys = await downloads.snapshot().map(\.key)
        let usage = await downloadFiles.localLibraryUsage(for: keys)
        guard usage.galleryKeys.isEmpty == false else {
            await refreshLocalDownloadUsage()
            return
        }

        isDeletingAllLocalManga = true
        localMangaDeletionProgress = DownloadRemovalProgress(completed: 0, total: usage.galleryCount)
        defer {
            isDeletingAllLocalManga = false
            localMangaDeletionProgress = nil
        }

        let result = await downloads.remove(usage.galleryKeys) { [weak self] progress in
            await MainActor.run {
                self?.localMangaDeletionProgress = progress
            }
        }
        await refreshLocalDownloadUsage()
        // The coordinator also emits removal events, but this operation may be
        // started outside DownloadsView. Publish an authoritative completion
        // revision so an already visible local library reloads immediately.
        publishLocalLibraryChange()
        if result.failures.isEmpty == false {
            errorMessage = String(localized: "删除本地漫画时有 \(result.failures.count) 项失败。")
        }
    }

    func downloadedPageData(
        for descriptor: GalleryPageDescriptor,
        resolution: ImageResolution = .preview
    ) async throws -> Data {
        try await downloadFiles.data(
            for: descriptor.galleryKey,
            pageIndex: descriptor.index
        )
    }

    func downloadedPageDataIfAvailable(for descriptor: GalleryPageDescriptor) async -> Data? {
        guard await downloadFiles.contains(descriptor.galleryKey, pageIndex: descriptor.index) else {
            return nil
        }
        return try? await downloadFiles.data(for: descriptor.galleryKey, pageIndex: descriptor.index)
    }

    func savePage(_ descriptor: GalleryPageDescriptor, resolution: ImageResolution = .preview) async throws {
        let data: Data
        if await downloadFiles.contains(descriptor.galleryKey, pageIndex: descriptor.index) {
            data = try await downloadFiles.data(for: descriptor.galleryKey, pageIndex: descriptor.index)
        } else {
            let image = try await pageImage(for: descriptor)
            data = try await imageData(for: image, resolution: resolution)
        }
        #if os(iOS)
        guard let mediaKind = DownloadMediaValidator.kind(of: data) else {
            throw EHError.parsingFailed(String(localized: "媒体数据无效"))
        }
        try await PhotoLibrarySaver.save(data, kind: mediaKind)
        #else
        guard let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw EHError.storageFailed(String(localized: "找不到可写入的下载目录"))
        }
        try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        let fileExtension = DownloadMediaValidator.kind(of: data) == .video
            ? "mp4"
            : (descriptor.pageURL.pathExtension.isEmpty ? "img" : descriptor.pageURL.pathExtension)
        let fileName = "ehviewer-\(descriptor.galleryKey.gid)-\(descriptor.index + 1).\(fileExtension)"
        try data.write(to: downloadsDirectory.appendingPathComponent(fileName), options: .atomic)
        #endif
    }

    func prefetch(_ descriptors: [GalleryPageDescriptor], resolution: ImageResolution = .preview) async {
        let api = self.api
        let pipeline = self.imagePipeline
        let currentSite = site
        await withTaskGroup(of: Void.self) { group in
            for descriptor in descriptors {
                group.addTask {
                    guard Task.isCancelled == false else { return }
                    do {
                        let image = try await api.pageImage(for: descriptor, site: currentSite)
                        let url = resolution == .original ? (image.originImageURL ?? image.imageURL) : image.imageURL
                        _ = try await pipeline.data(for: url) {
                            try await api.imageData(for: image, resolution: resolution)
                        }
                    } catch is CancellationError {
                        return
                    } catch {
                        return
                    }
                }
            }
        }
    }

    func toggleFavorite(for key: GalleryKey) async {
        await toggleFavorite(for: key, remoteDetail: nil)
    }

    func toggleFavorite(for key: GalleryKey, remoteDetail: GalleryDetail?) async {
        do {
            if let remoteDetail {
                try await persistence.upsert([remoteDetail.summary])
            } else if let summary = galleries.first(where: { $0.key == key }) {
                try await persistence.upsert([summary])
            }
            let current = try await persistence.isFavorite(for: key) ?? false
            if remoteDetail != nil, isGuestMode == false {
                try await api.setFavorite(
                    for: key,
                    site: site,
                    category: current ? nil : 0,
                    note: nil
                )
            }
            try await persistence.setFavorite(for: key, isFavorite: !current)
            await loadLibrary(mode: .favorites)
        }
        catch { errorMessage = error.localizedDescription }
    }

    func rate(_ detail: GalleryDetail, value: Double) async {
        guard let apiUID = detail.apiUID, let apiKey = detail.apiKey else {
            errorMessage = EHError.authenticationRequired.localizedDescription
            return
        }
        do {
            _ = try await api.rateGallery(for: detail.summary.key, site: site, rating: value, apiUID: apiUID, apiKey: apiKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func comments(for key: GalleryKey) async throws -> [GalleryComment] {
        if let dynamic = try? await persistence.downloadedDynamicSnapshot(for: key),
           dynamic.completeness.comments.isLoaded {
            return dynamic.comments.map(\.galleryComment)
        }
        return try await api.comments(for: key, site: site)
    }

    func submitComment(for key: GalleryKey, body: String) async -> [GalleryComment]? {
        do {
            return try await api.submitComment(for: key, site: site, body: body, editing: nil)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func submitComment(for detail: GalleryDetail, body: String) async -> [GalleryComment]? {
        await submitComment(for: detail.summary.key, body: body)
    }

    func torrents(for key: GalleryKey) async -> [TorrentDescriptor] {
        do {
            return try await api.torrents(for: key, site: site)
        } catch is CancellationError {
            return []
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func archiveOptions(for key: GalleryKey) async -> [ArchiveOption] {
        do {
            return try await api.archiveOptions(for: key, site: site)
        } catch is CancellationError {
            return []
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func archiveDownloadURL(for key: GalleryKey, resolution: String) async -> URL? {
        do {
            return try await api.archiveDownloadURL(for: key, site: site, resolution: resolution)
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func openLocalArchive(from url: URL) async -> LocalArchiveDocument? {
        do {
            let document = try await Task.detached(priority: .userInitiated) {
                try LocalArchiveReader.open(url)
            }.value
            localArchive = document
            return document
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func data(for entry: LocalArchiveEntry, in document: LocalArchiveDocument) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try LocalArchiveReader.readData(for: entry, in: document)
        }.value
    }

    func closeLocalArchive() {
        localArchive = nil
    }

    func updateProgress(for key: GalleryKey, page: Int) async {
        let fallbackSummary = await downloads.job(for: key).map { job in
            GallerySummary(
                key: job.key,
                title: job.title,
                japaneseTitle: job.japaneseTitle,
                pageCount: job.totalPageCount > 0 ? job.totalPageCount : nil,
                tags: job.tags
            )
        }
        do {
            try await persistence.updateReadingProgress(
                for: key,
                page: page,
                fallbackSummary: fallbackSummary
            )
        }
        catch { errorMessage = error.localizedDescription }
    }

    func readingPage(for key: GalleryKey) async -> Int? {
        try? await persistence.readingPage(for: key)
    }

    func favoriteState(for key: GalleryKey) async -> Bool {
        (try? await persistence.isFavorite(for: key)) ?? false
    }

    func loadLibrary(mode: LibraryView.Mode) async {
        do {
            switch mode {
            case .history:
                let loaded = try await persistence.recent()
                if loaded != historyGalleries { historyGalleries = loaded }
            case .favorites:
                let loaded = try await persistence.favorites()
                if loaded != favoriteGalleries { favoriteGalleries = loaded }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeLibraryItems(_ keys: Set<GalleryKey>, mode: LibraryView.Mode) async {
        guard keys.isEmpty == false else { return }
        do {
            switch mode {
            case .history:
                try await persistence.removeFromHistory(for: keys)
            case .favorites:
                try await persistence.removeFromFavorites(for: keys)
            }
            await loadLibrary(mode: mode)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadFilterRules() async {
        filterRules = (try? await persistence.filterRules()) ?? []
    }

    func loadTagTranslations() async {
        let reference = (try? await persistence.tagTranslations(locale: Self.tagTranslationLocale)) ?? [:]
        hasLoadedReferenceTagTranslations = reference.isEmpty == false
        var loaded = reference
        if Locale.current.identifier != Self.tagTranslationLocale,
           let local = try? await persistence.tagTranslations(locale: Locale.current.identifier) {
            loaded.merge(local) { _, new in new }
        }
        guard !Task.isCancelled, !isShuttingDown else { return }
        tagTranslations = loaded
    }

    static let tagTranslationLocale = "zh-rCN"

    /// Imports the reference tag database once so detail pages can show the
    /// same Chinese tag translations as the original client.
    func importTagTranslationsIfNeeded() async {
        let hasImportMarker = defaults.string(forKey: "tagTranslationImportLocale") == Self.tagTranslationLocale
        let hasReferenceTranslations = hasLoadedReferenceTagTranslations
        guard hasImportMarker == false || hasReferenceTranslations == false else { return }
        guard let entries = try? await tagSuggestionProvider.allEntries() else { return }
        let pairs = await Self.translationPairs(entries)
        guard !Task.isCancelled, !isShuttingDown else { return }
        guard pairs.isEmpty == false else { return }
        do {
            try await persistence.saveTagTranslations(pairs, locale: Self.tagTranslationLocale)
        } catch {
            return
        }
        defaults.set(Self.tagTranslationLocale, forKey: "tagTranslationImportLocale")
        await loadTagTranslations()
    }

    @concurrent
    private static func translationPairs(_ entries: [SearchTagSuggestion]) async -> [(tag: String, localizedText: String)] {
        entries.compactMap { entry in
            guard let text = entry.localizedText, !text.isEmpty else { return nil }
            return (entry.rawKey ?? entry.english, text)
        }
    }

    func checkTagDatabaseForUpdate() async {
        guard isCheckingTagDatabaseUpdate == false, isUpdatingTagDatabase == false else { return }
        isCheckingTagDatabaseUpdate = true
        tagDatabaseUpdateError = nil
        defer { isCheckingTagDatabaseUpdate = false }

        do {
            tagDatabaseUpdateStatus = try await tagSuggestionProvider.checkForUpdate()
        } catch is CancellationError {
            return
        } catch {
            tagDatabaseUpdateStatus = .unknown
            tagDatabaseUpdateError = error.localizedDescription
        }
    }

    func updateTagDatabase() async {
        guard isCheckingTagDatabaseUpdate == false, isUpdatingTagDatabase == false else { return }
        isUpdatingTagDatabase = true
        tagDatabaseUpdateError = nil
        defer { isUpdatingTagDatabase = false }

        do {
            let status = try await tagSuggestionProvider.installAvailableUpdate()
            guard status == .latest else {
                tagDatabaseUpdateStatus = status
                return
            }
            try await replaceTagTranslationsFromDatabase()
            tagDatabaseUpdateStatus = .latest
        } catch is CancellationError {
            return
        } catch {
            // Keep the available-update state so the button remains a direct
            // retry of the already validated candidate.
            tagDatabaseUpdateStatus = .updateAvailable
            tagDatabaseUpdateError = error.localizedDescription
        }
    }

    private func replaceTagTranslationsFromDatabase() async throws {
        let entries = try await tagSuggestionProvider.allEntries()
        let pairs = entries.compactMap { entry -> (tag: String, localizedText: String)? in
            guard let text = entry.localizedText, text.isEmpty == false else { return nil }
            return (entry.rawKey ?? entry.english, text)
        }
        guard pairs.isEmpty == false else {
            throw EHError.parsingFailed(String(localized: "标签数据库不包含可用翻译"))
        }
        try await persistence.replaceTagTranslations(pairs, locale: Self.tagTranslationLocale)
        defaults.set(Self.tagTranslationLocale, forKey: "tagTranslationImportLocale")
        await loadTagTranslations()
    }

    func localizedTag(_ tag: String) -> String {
        tagTranslations[tag] ?? tag
    }

    /// Detail-page tag display, mirroring the reference client: only the tag
    /// value is shown (never the `misc:`/`artist:` prefix), translated when
    /// the reference database has an entry for it and translations are on.
    func displayTag(_ tag: String) -> String {
        let value: String
        if let separator = tag.firstIndex(of: ":") {
            value = String(tag[tag.index(after: separator)...])
        } else {
            value = tag
        }
        guard readingSettings.showTagTranslations else { return value }
        if let translated = tagTranslations[tag] { return translated }
        let databaseKey = SearchQueryComposer.databaseTagKey(for: tag)
        if databaseKey != tag, let translated = tagTranslations[databaseKey] { return translated }
        if value != tag, let translated = tagTranslations[value] { return translated }
        return value
    }

    func loadQuickSearches() async {
        quickSearches = (try? await persistence.quickSearches()) ?? []
    }

    func setFilterRule(pattern: String, isEnabled: Bool, mode: GalleryFilterMode = .title) async {
        do {
            try await persistence.setFilterRule(pattern: pattern, isEnabled: isEnabled, mode: mode)
            await loadFilterRules()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Tag candidates for the filter-rule keyword field, backed by the same
    /// database as the browse search suggestions.
    func filterTagSuggestions(for keyword: String, limit: Int = 10) async -> [SearchTagSuggestion] {
        let normalized = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else { return [] }
        return (try? await tagSuggestionProvider.suggestions(for: normalized, limit: limit)) ?? []
    }

    func deleteFilterRule(pattern: String, mode: GalleryFilterMode = .title) async {
        do {
            try await persistence.deleteFilterRule(pattern: pattern, mode: mode)
            await loadFilterRules()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setDownloadLabel(_ label: String?, for key: GalleryKey) async {
        let normalized = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalized, normalized.isEmpty == false {
            try? await persistence.saveDownloadLabel(normalized)
        }
        await downloads.setLabel(normalized, for: key)
    }

    func resetAllDownloadReadingProgress() async {
        do {
            let keys = await downloads.snapshot().map(\.key)
            try await persistence.resetReadingProgress(for: keys)
            historyGalleries = try await persistence.recent()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func enqueue(_ detail: GalleryDetail) async {
        let stable = StableGalleryMetadataSnapshot(detail: detail, sourceSite: site)
        let dynamic = DownloadedGalleryDynamicSnapshot(detail: detail)
        try? await persistence.promoteToDownloadedGallery(stable: stable, dynamic: dynamic)
        await downloads.enqueue(
            key: detail.summary.key,
            title: detail.summary.title,
            japaneseTitle: detail.summary.japaneseTitle,
            tags: detail.summary.tags,
            pages: detail.pages,
            totalPageCount: detail.summary.pageCount
        )
    }

    /// Resolves and queues selected galleries one at a time so bulk actions do not
    /// create an unbounded burst of detail requests for large local libraries.
    func enqueueUndownloadedGalleries(
        _ galleries: [GallerySummary],
        updateProgress: (GalleryDownloadEnqueueProgress) -> Void
    ) async -> GalleryDownloadEnqueueResult {
        let existingDownloadKeys = Set(await downloads.snapshot().map(\.key))
        let targets = Self.undownloadedDownloadTargets(
            from: galleries,
            existingDownloadKeys: existingDownloadKeys
        )
        let total = targets.count
        var completed = 0
        var enqueued = 0
        var failed = 0

        for gallery in targets {
            guard Task.isCancelled == false else {
                return GalleryDownloadEnqueueResult(
                    requested: total,
                    enqueued: enqueued,
                    failed: failed,
                    cancelled: true
                )
            }

            do {
                let detail = try await api.detailPreview(for: gallery.key, site: site)
                guard Task.isCancelled == false else {
                    return GalleryDownloadEnqueueResult(
                        requested: total,
                        enqueued: enqueued,
                        failed: failed,
                        cancelled: true
                    )
                }
                await enqueue(detail)
                enqueued += 1
            } catch is CancellationError {
                return GalleryDownloadEnqueueResult(
                    requested: total,
                    enqueued: enqueued,
                    failed: failed,
                    cancelled: true
                )
            } catch {
                failed += 1
            }

            completed += 1
            updateProgress(
                GalleryDownloadEnqueueProgress(
                    completed: completed,
                    total: total,
                    enqueued: enqueued,
                    failed: failed
                )
            )
        }

        return GalleryDownloadEnqueueResult(
            requested: total,
            enqueued: enqueued,
            failed: failed,
            cancelled: false
        )
    }

    static func undownloadedDownloadTargets(
        from galleries: [GallerySummary],
        existingDownloadKeys: Set<GalleryKey>
    ) -> [GallerySummary] {
        galleries.filter { existingDownloadKeys.contains($0.key) == false }
    }

    /// A synced gallery initially has no page descriptors. Resolve those only
    /// when the user chooses to download it, rather than making import depend
    /// on the network.
    func resumeDownload(_ key: GalleryKey) async {
        guard let job = await downloads.job(for: key) else { return }
        if job.pages.isEmpty {
            guard await hydrateSyncedDownload(job) else { return }
        }
        await downloads.resume(key)
    }

    /// Deletes every downloaded page and restarts the job from the beginning.
    func redownloadDownload(_ key: GalleryKey) async {
        guard let job = await downloads.job(for: key) else { return }
        if job.pages.isEmpty {
            guard await hydrateSyncedDownload(job) else { return }
        }
        if case let .failed(message) = await downloads.redownload(key) {
            errorMessage = message
        }
    }

    func startAllDownloads() async {
        guard !isLoadingDownloads, localDownloadLoadError == nil, !isShuttingDown else { return }
        let jobs = await downloads.snapshot()
        for job in jobs where [.paused, .failed, .authenticationRequired, .rateLimited, .bandwidthLimited].contains(job.state) {
            await resumeDownload(job.key)
        }
    }

    func downloadJob(for key: GalleryKey) async -> DownloadJob? {
        await downloads.job(for: key)
    }

    func restoreDownloads(
        from archiveURL: URL,
        progress: ((Int, Int) -> Void)? = nil
    ) async -> DownloadRestoreOutcome {
        guard !isLoadingDownloads, localDownloadLoadError == nil else {
            return DownloadRestoreOutcome(message: String(localized: "正在加载下载内容…"))
        }
        guard isMigrating == false else {
            return DownloadRestoreOutcome(message: String(localized: "已有导入或导出任务正在进行。"))
        }
        guard isRestoringDownloads == false else {
            return DownloadRestoreOutcome(message: String(localized: "已有恢复任务正在进行。"))
        }
        isRestoringDownloads = true
        downloadRestoreStatus = String(localized: "正在检查备份压缩包…")
        downloadRestoreProgress = MigrationProgress(status: downloadRestoreStatus)
        let restoreSite = site
        var operationIssues: [FileOperationIssue] = []
        defer {
            isRestoringDownloads = false
            downloadRestoreStatus = ""
            downloadRestoreProgress = nil
        }

        do {
            let inspection = try await LegacyDownloadArchive.inspect(archiveURL)
            let candidates = inspection.candidates
            guard candidates.isEmpty == false else {
                let message = inspection.invalidItemCount > 0
                    ? String(localized: "没有找到可恢复的下载项；发现 \(inspection.invalidItemCount) 个无效目录。")
                    : String(localized: "没有在压缩包的 download 目录中找到可恢复的下载项。")
                return DownloadRestoreOutcome(
                    candidateCount: 0,
                    invalidItemCount: inspection.invalidItemCount,
                    message: message
                )
            }

            let existingJobs = Dictionary(uniqueKeysWithValues: await downloads.snapshot().map { ($0.key, $0) })
            let storedSummaries = try await persistence.downloadedGallerySummaries(
                for: Set(candidates.map(\.key))
            )
            var existingLocalIndexes: [GalleryKey: Set<Int>] = [:]
            for candidate in candidates {
                let pageIndexes = Array(0..<candidate.declaredPageCount)
                existingLocalIndexes[candidate.key] = await downloadFiles.readablePageIndexes(
                    for: candidate.key,
                    pageIndexes: pageIndexes,
                    refreshValidIndexEntries: false
                )
            }

            let archiveSummaries = candidates.map { candidate in
                let transferred = candidate.transferRecord?.stable.summary
                let transferredDynamic = candidate.transferRecord?.dynamic
                var completeness = candidate.transferRecord?.stable.completeness
                    ?? candidate.metadataCompleteness
                if let dynamic = transferredDynamic {
                    var mergedCompleteness = completeness ?? GalleryMetadataCompleteness()
                    mergedCompleteness.rating = dynamic.completeness.rating
                    mergedCompleteness.ratingCount = dynamic.completeness.ratingCount
                    mergedCompleteness.favorite = dynamic.completeness.favorite
                    completeness = mergedCompleteness
                }
                return GallerySummary(
                    key: candidate.key,
                    title: transferred?.title
                        ?? candidate.title
                        ?? existingJobs[candidate.key]?.title
                        ?? fallbackDownloadTitle(for: candidate),
                    japaneseTitle: transferred?.japaneseTitle
                        ?? candidate.japaneseTitle
                        ?? existingJobs[candidate.key]?.japaneseTitle,
                    thumbnailURL: transferred?.thumbnailURL,
                    category: transferred?.category,
                    pageCount: transferred?.pageCount ?? candidate.declaredPageCount,
                    postedAt: transferred?.postedAt,
                    rating: transferredDynamic?.rating,
                    ratingCount: transferredDynamic?.ratingCount,
                    favoriteCategory: transferredDynamic?.favoriteCategory,
                    uploader: transferred?.uploader,
                    tags: transferred?.tags
                        ?? candidate.tags
                        ?? existingJobs[candidate.key]?.tags
                        ?? [],
                    metadataCompleteness: completeness
                )
            }

            downloadRestoreStatus = String(localized: "正在读取归档画廊信息…")
            let resolution = try await resolveTransferMetadata(
                archiveSummaries,
                existing: storedSummaries,
                fetchMissingMetadata: false
            )
            let summaryByKey = resolution.summariesByKey

            var importCandidates: [LegacyDownloadCandidate] = []
            var skippedDuplicateItemCount = 0
            for candidate in candidates {
                let expectedPages = Set(0..<candidate.declaredPageCount)
                if existingJobs[candidate.key] != nil,
                   expectedPages.isSubset(of: existingLocalIndexes[candidate.key] ?? []) {
                    skippedDuplicateItemCount += 1
                } else {
                    importCandidates.append(candidate)
                }
            }

            var skippedDuplicatePageCount = 0
            var countedSkippedPageKeys = Set<String>()
            for candidate in candidates {
                let localIndexes = existingLocalIndexes[candidate.key] ?? []
                for image in candidate.images
                where (0..<candidate.declaredPageCount).contains(image.pageIndex)
                    && localIndexes.contains(image.pageIndex) {
                    let pageKey = Self.restorePageKey(key: candidate.key, pageIndex: image.pageIndex)
                    if countedSkippedPageKeys.insert(pageKey).inserted {
                        skippedDuplicatePageCount += 1
                    }
                }
            }

            guard importCandidates.isEmpty == false else {
                for candidate in candidates {
                    guard let transfer = candidate.transferRecord else { continue }
                    let refreshedStable = summaryByKey[candidate.key].map {
                        GallerySnapshotMerger.merge(
                            existing: transfer.stable,
                            incoming: StableGalleryMetadataSnapshot(summary: $0, sourceSite: restoreSite)
                        )
                    } ?? transfer.stable
                    try await persistence.promoteToDownloadedGallery(
                        stable: refreshedStable,
                        dynamic: transfer.dynamic
                    )
                }
                await downloads.mergeMetadata(Array(summaryByKey.values))
                progress?(0, 0)
                return DownloadRestoreOutcome(
                    candidateCount: candidates.count,
                    skippedDuplicateItemCount: skippedDuplicateItemCount,
                    skippedDuplicatePageCount: skippedDuplicatePageCount,
                    invalidItemCount: inspection.invalidItemCount,
                    incompleteMetadataCount: resolution.incompleteCount,
                    message: Self.restoreOutcomeMessage(
                        importedItemCount: 0,
                        mergedItemCount: 0,
                        skippedDuplicateItemCount: skippedDuplicateItemCount,
                        skippedDuplicatePageCount: skippedDuplicatePageCount,
                        failedPageCount: 0,
                        invalidItemCount: inspection.invalidItemCount,
                        incompleteMetadataCount: resolution.incompleteCount
                    )
                )
            }
            progress?(0, importCandidates.count)

            var selectedPageKeys = Set<String>()
            let selections = importCandidates.flatMap { candidate -> [LegacyDownloadPageSelection] in
                let localIndexes = existingLocalIndexes[candidate.key] ?? []
                return candidate.images.compactMap { image in
                    guard (0..<candidate.declaredPageCount).contains(image.pageIndex) else { return nil }
                    guard localIndexes.contains(image.pageIndex) == false else { return nil }
                    let pageKey = Self.restorePageKey(key: candidate.key, pageIndex: image.pageIndex)
                    guard selectedPageKeys.insert(pageKey).inserted else { return nil }
                    return LegacyDownloadPageSelection(
                        archivePath: image.archivePath,
                        key: candidate.key,
                        pageIndex: image.pageIndex,
                        byteCount: image.byteCount
                    )
                }
            }

            downloadRestoreStatus = String(localized: "正在解压下载图片…")
            downloadRestoreProgress = MigrationProgress(
                status: downloadRestoreStatus,
                completed: 0,
                total: selections.count,
                fraction: 0
            )
            let extraction = try await LegacyDownloadArchive.extractPages(
                from: archiveURL,
                selections: selections
            ) { [weak self] progress in
                guard let self else { return }
                await self.setDownloadRestoreProgress(
                    completed: progress.completedFiles,
                    total: progress.totalFiles,
                    fraction: progress.fraction,
                    estimatedRemainingSeconds: progress.estimatedRemainingSeconds
                )
            }
            defer { try? FileManager.default.removeItem(at: extraction.temporaryDirectory) }

            var importedPageCount = 0
            var failedPageCount = extraction.failedPageCount
            if extraction.failedPageCount > 0 {
                operationIssues.append(FileOperationIssue(
                    phase: .extracting,
                    message: String(localized: "有 \(extraction.failedPageCount) 个归档页面无法解压。")
                ))
            }
            let extractedByKey = Dictionary(grouping: extraction.pages, by: \.key)
            var restoredJobs: [DownloadJob] = []
            restoredJobs.reserveCapacity(importCandidates.count)
            for (offset, candidate) in importCandidates.enumerated() {
                try Task.checkCancellation()

                var imported = existingLocalIndexes[candidate.key] ?? []
                var newlyImported: [(pageIndex: Int, sha256: Data)] = []
                var validatedPageEntries: [DeviceSyncPageEntry] = []
                var galleryImportFailed = false
                let galleryPages = extractedByKey[candidate.key] ?? []
                for (pageOffset, page) in galleryPages.enumerated() {
                    try Task.checkCancellation()
                    downloadRestoreStatus = String(
                        localized: "正在导入《\(summaryByKey[candidate.key]?.title ?? fallbackDownloadTitle(for: candidate))》图片 \(pageOffset + 1)/\(galleryPages.count)…"
                    )
                    do {
                        let result = try await downloadFiles.importFileResult(
                            at: page.fileURL,
                            for: page.key,
                            pageIndex: page.pageIndex,
                            knownSHA256: page.sha256,
                            updateIndex: false
                        )
                        imported.insert(page.pageIndex)
                        if let entry = try? DeviceSyncPageEntry(
                            pageIndex: page.pageIndex,
                            byteCount: page.byteCount
                        ) {
                            validatedPageEntries.append(entry)
                        }
                        if case let .imported(_, sha256) = result {
                            newlyImported.append((page.pageIndex, sha256))
                            importedPageCount += 1
                        }
                    } catch is CancellationError {
                        for newPage in newlyImported {
                            try? await downloadFiles.rollbackReceivedPage(
                                for: candidate.key,
                                pageIndex: newPage.pageIndex,
                                sha256: newPage.sha256
                            )
                        }
                        throw CancellationError()
                    } catch {
                        failedPageCount += 1
                        galleryImportFailed = true
                        operationIssues.append(FileOperationIssue(
                            galleryKey: candidate.key,
                            pageIndex: page.pageIndex,
                            phase: .validating,
                            message: error.localizedDescription
                        ))
                        break
                    }
                }

                if galleryImportFailed || imported.isEmpty {
                    for newPage in newlyImported {
                        try? await downloadFiles.rollbackReceivedPage(
                            for: candidate.key,
                            pageIndex: newPage.pageIndex,
                            sha256: newPage.sha256
                        )
                    }
                    continue
                }

                let legacyPages = legacyPageDescriptors(candidate: candidate, site: restoreSite)
                var pageByIndex = Dictionary(uniqueKeysWithValues: legacyPages.pages.map { ($0.index, $0) })
                if let existing = existingJobs[candidate.key] {
                    for page in existing.pages {
                        if let mergedPage = pageByIndex[page.index], mergedPage.requiresPageResolution {
                            continue
                        }
                        pageByIndex[page.index] = page
                    }
                }
                let pages = pageByIndex.values.sorted { $0.index < $1.index }
                let expected = Set(0..<max(candidate.declaredPageCount, (pages.map(\.index).max() ?? -1) + 1))
                let isComplete = expected.isEmpty == false && imported == expected
                var state: DownloadState = isComplete ? .completed : .paused
                var itemError: String?

                if isComplete == false {
                    downloadRestoreStatus = String(localized: "正在准备缺失页面 \(offset + 1)/\(importCandidates.count)…")
                    let missingIndexes = expected.subtracting(imported)
                    if missingIndexes.isSubset(of: legacyPages.resumableIndexes) == false {
                        state = .failed
                        itemError = String(localized: "已恢复 \(imported.count)/\(expected.count) 页，但部分缺页没有可用的页面 token")
                    } else {
                        itemError = String(localized: "已恢复 \(imported.count)/\(expected.count) 页，可继续下载缺失页面")
                    }
                }

                var job = DownloadJob(
                    key: candidate.key,
                    title: summaryByKey[candidate.key]?.title
                        ?? existingJobs[candidate.key]?.title
                        ?? fallbackDownloadTitle(for: candidate),
                    japaneseTitle: summaryByKey[candidate.key]?.japaneseTitle
                        ?? existingJobs[candidate.key]?.japaneseTitle,
                    tags: summaryByKey[candidate.key]?.tags
                        ?? existingJobs[candidate.key]?.tags
                        ?? [],
                    pages: pages,
                    totalPageCount: max(candidate.declaredPageCount, existingJobs[candidate.key]?.totalPageCount ?? 0),
                    label: existingJobs[candidate.key]?.label,
                    addedAt: existingJobs[candidate.key]?.addedAt ?? Date()
                )
                job.completedPageIndexes = imported
                job.state = state
                job.errorMessage = itemError
                do {
                    if let transfer = candidate.transferRecord {
                        let refreshedStable = summaryByKey[candidate.key].map {
                            GallerySnapshotMerger.merge(
                                existing: transfer.stable,
                                incoming: StableGalleryMetadataSnapshot(summary: $0, sourceSite: restoreSite)
                            )
                        } ?? transfer.stable
                        try await persistence.promoteToDownloadedGallery(
                            stable: refreshedStable,
                            dynamic: transfer.dynamic
                        )
                    } else if let summary = summaryByKey[candidate.key] {
                        try await persistence.upsertStableSnapshot(
                            StableGalleryMetadataSnapshot(summary: summary, sourceSite: restoreSite),
                            retainForDownload: true
                        )
                    }
                    await downloads.mergeRestored([job])
                    if let summary = summaryByKey[candidate.key] {
                        await downloads.mergeMetadata([summary])
                    }
                    await deviceSyncIndex.upsertMediaPages(
                        key: candidate.key,
                        pages: validatedPageEntries
                    )
                    restoredJobs.append(job)
                } catch {
                    for newPage in newlyImported {
                        try? await downloadFiles.rollbackReceivedPage(
                            for: candidate.key,
                            pageIndex: newPage.pageIndex,
                            sha256: newPage.sha256
                        )
                    }
                    failedPageCount += max(1, newlyImported.count)
                    operationIssues.append(FileOperationIssue(
                        galleryKey: candidate.key,
                        phase: .committing,
                        message: error.localizedDescription
                    ))
                    continue
                }
                progress?(offset + 1, importCandidates.count)
            }

            let mergedItemCount = restoredJobs.filter { existingJobs[$0.key] != nil }.count
            let importedItemCount = restoredJobs.count - mergedItemCount
            return DownloadRestoreOutcome(
                candidateCount: candidates.count,
                importedItemCount: importedItemCount,
                mergedItemCount: mergedItemCount,
                skippedDuplicateItemCount: skippedDuplicateItemCount,
                importedPageCount: importedPageCount,
                skippedDuplicatePageCount: skippedDuplicatePageCount,
                failedPageCount: failedPageCount,
                invalidItemCount: inspection.invalidItemCount,
                incompleteMetadataCount: resolution.incompleteCount,
                issues: operationIssues,
                message: Self.restoreOutcomeMessage(
                    importedItemCount: importedItemCount,
                    mergedItemCount: mergedItemCount,
                    skippedDuplicateItemCount: skippedDuplicateItemCount,
                    skippedDuplicatePageCount: skippedDuplicatePageCount,
                    failedPageCount: failedPageCount,
                    invalidItemCount: inspection.invalidItemCount,
                    incompleteMetadataCount: resolution.incompleteCount
                )
            )
        } catch is CancellationError {
            return DownloadRestoreOutcome(
                issues: operationIssues,
                message: String(localized: "已取消恢复下载项；已完整提交的画廊保持不变。")
            )
        } catch {
            operationIssues.append(FileOperationIssue(
                phase: .committing,
                message: error.localizedDescription
            ))
            return DownloadRestoreOutcome(
                issues: operationIssues,
                message: String(localized: "恢复下载项失败：\(error.localizedDescription)")
            )
        }
    }

    nonisolated private static func restorePageKey(key: GalleryKey, pageIndex: Int) -> String {
        "\(key.gid)|\(key.token)|\(pageIndex)"
    }

    nonisolated private static func restoreOutcomeMessage(
        importedItemCount: Int,
        mergedItemCount: Int,
        skippedDuplicateItemCount: Int,
        skippedDuplicatePageCount: Int,
        failedPageCount: Int,
        invalidItemCount: Int,
        incompleteMetadataCount: Int
    ) -> String {
        var parts = [
            String(localized: "已导入 \(importedItemCount) 项"),
            String(localized: "合并 \(mergedItemCount) 项")
        ]
        if skippedDuplicateItemCount > 0 {
            parts.append(String(localized: "跳过重复项 \(skippedDuplicateItemCount) 项"))
        }
        if skippedDuplicatePageCount > 0 {
            parts.append(String(localized: "跳过已有页面 \(skippedDuplicatePageCount) 页"))
        }
        if failedPageCount > 0 {
            parts.append(String(localized: "图片失败 \(failedPageCount) 页"))
        }
        if invalidItemCount > 0 {
            parts.append(String(localized: "无效目录 \(invalidItemCount) 个"))
        }
        if incompleteMetadataCount > 0 {
            parts.append(String(localized: "待联网补全信息 \(incompleteMetadataCount) 个"))
        }
        return parts.joined(separator: "，") + "。"
    }

    private func resolvedDownloadPages(
        _ descriptors: [GalleryPageDescriptor],
        maximumConcurrent: Int = 4,
        site requestedSite: SiteMode? = nil
    ) async throws -> [GalleryPageDescriptor] {
        let client = api
        let currentSite = requestedSite ?? site
        return try await withThrowingTaskGroup(
            of: GalleryPageDescriptor.self,
            returning: [GalleryPageDescriptor].self
        ) { group in
            var iterator = descriptors.makeIterator()
            for _ in 0..<min(maximumConcurrent, descriptors.count) {
                guard let descriptor = iterator.next() else { break }
                group.addTask { try await Self.resolveDownloadPage(descriptor, client: client, site: currentSite) }
            }

            var pages: [GalleryPageDescriptor] = []
            for try await page in group {
                pages.append(page)
                if let descriptor = iterator.next() {
                    group.addTask { try await Self.resolveDownloadPage(descriptor, client: client, site: currentSite) }
                }
            }
            return pages.sorted { $0.index < $1.index }
        }
    }

    private func legacyPageDescriptors(
        candidate: LegacyDownloadCandidate,
        site: SiteMode
    ) -> (pages: [GalleryPageDescriptor], resumableIndexes: Set<Int>) {
        var resumableIndexes = Set<Int>()
        let pages = (0..<candidate.declaredPageCount).map { index in
            if let pageToken = candidate.pageTokens[index],
               let pageURL = URL(string: "https://\(site.host)/s/\(pageToken)/\(candidate.key.gid)-\(index + 1)") {
                resumableIndexes.insert(index)
                return GalleryPageDescriptor(
                    galleryKey: candidate.key,
                    index: index,
                    pageURL: pageURL
                )
            }
            let placeholderURL = URL(
                string: "https://\(site.host)/g/\(candidate.key.gid)/\(candidate.key.token)/#restored-\(index + 1)"
            )!
            return GalleryPageDescriptor(
                galleryKey: candidate.key,
                index: index,
                pageURL: placeholderURL
            )
        }
        return (pages, resumableIndexes)
    }

    private func fallbackDownloadTitle(for candidate: LegacyDownloadCandidate) -> String {
        let directoryName = candidate.directoryPath.split(separator: "/").last.map(String.init) ?? ""
        let prefix = "\(candidate.key.gid)-"
        let title = directoryName.hasPrefix(prefix) ? String(directoryName.dropFirst(prefix.count)) : directoryName
        return title.isEmpty ? "Gallery \(candidate.key.gid)" : title
    }

    nonisolated private static func resolveDownloadPage(
        _ descriptor: GalleryPageDescriptor,
        client: any EHAPI,
        site: SiteMode
    ) async throws -> GalleryPageDescriptor {
        let image = try await client.pageImage(for: descriptor, site: site)
        return GalleryPageDescriptor(
            galleryKey: descriptor.galleryKey,
            index: descriptor.index,
            pageURL: image.imageURL,
            previewURL: descriptor.previewURL
        )
    }

    nonisolated private static func pageDescriptor(
        _ descriptor: GalleryPageDescriptor,
        skippingHathNodeWith key: String
    ) -> GalleryPageDescriptor {
        guard var components = URLComponents(url: descriptor.pageURL, resolvingAgainstBaseURL: false) else {
            return descriptor
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "nl" }
        queryItems.append(URLQueryItem(name: "nl", value: key))
        components.queryItems = queryItems
        guard let pageURL = components.url else { return descriptor }
        return GalleryPageDescriptor(
            galleryKey: descriptor.galleryKey,
            index: descriptor.index,
            pageURL: pageURL,
            previewURL: descriptor.previewURL
        )
    }

    /// Reloads downloads after device sync without resolving missing pages
    /// through the website or automatically starting queued jobs. Device sync
    /// owns only local media and must not turn a partial reconciliation into a
    /// background network download.
    func refreshDownloadsAfterDeviceSync() async {
        await restoreDownloads(startQueued: false)
        await refreshLocalDownloadUsage()
        // Device sync mutates files and persisted download metadata outside a
        // local-list interaction. Signal visible local lists after the reload
        // has reconciled those changes into the coordinator.
        publishLocalLibraryChange()
    }

    private func restoreDownloads(
        startQueued: Bool = true,
        progress: ((Int, Int) -> Void)? = nil
    ) async {
        isLoadingDownloads = true
        // Tags live in the downloaded-metadata snapshot and are not needed to
        // render the initial download baseline. Defer that large JSON decode
        // so the root view can be published with only the job/page records.
        localDownloadLoadError = nil
        let persisted: [PersistedDownload]
        do {
            if let downloadBaselineLoader {
                persisted = try await downloadBaselineLoader()
            } else {
                persisted = try await persistence.downloadJobs(includeTags: false)
            }
            try Task.checkCancellation()
        } catch {
            guard !Task.isCancelled, !isShuttingDown else { return }
            localDownloadLoadError = error.localizedDescription
            isLoadingDownloads = false
            markReady()
            return
        }

        let baselines = await Self.downloadBaselines(persisted)
        guard !Task.isCancelled, !isShuttingDown else { return }
        await downloads.loadPersisted(baselines)
        guard !Task.isCancelled, !isShuttingDown else { return }
        markReady()
        isLoadingDownloads = false
        progress?(0, persisted.count)

        async let downloadedSummaries = (try? await persistence.downloadedGallerySummaries(
            for: Set(persisted.map(\.key))
        )) ?? []
        let reconciliations = await Self.downloadReconciliations(persisted, baselines: baselines)
        guard !Task.isCancelled, !isShuttingDown else { return }
        _ = await downloads.reconcilePersisted(reconciliations)
        progress?(persisted.count, persisted.count)
        if startQueued, !Task.isCancelled, !isShuttingDown {
            await downloads.startRestoredJobs()
        }
        let restoredSummaries = await downloadedSummaries
        guard !Task.isCancelled, !isShuttingDown else { return }
        await downloads.mergeMetadataInMemory(restoredSummaries)
    }

    func retryLocalDownloadLoad() {
        guard !isLoadingDownloads, !isShuttingDown else { return }
        localRestoreTask?.cancel()
        isLoadingDownloads = true
        localDownloadLoadError = nil
        localRestoreTask = Task { [weak self] in
            await self?.restoreDownloads()
        }
    }

    func waitForLocalRestore() async {
        await localRestoreTask?.value
    }

    @concurrent
    static func downloadBaselines(
        _ persisted: [PersistedDownload],
        onStart: (@Sendable () async -> Void)? = nil
    ) async -> [DownloadJob] {
        await onStart?()
        var jobs: [DownloadJob] = []
        jobs.reserveCapacity(persisted.count)
        for item in persisted {
            guard !Task.isCancelled else { return [] }
            jobs.append(Self.makePersistedDownloadJob(item))
        }
        return jobs
    }

    @concurrent
    private static func downloadReconciliations(
        _ persisted: [PersistedDownload], baselines: [DownloadJob]
    ) async -> [(job: DownloadJob, baseline: DownloadJob)] {
        var reconciliations: [(job: DownloadJob, baseline: DownloadJob)] = []
        reconciliations.reserveCapacity(persisted.count)

        for (item, baseline) in zip(persisted, baselines) {
            if Task.isCancelled { return [] }
            let pages = item.pages
            var job = DownloadJob(
                key: item.key,
                title: item.title,
                japaneseTitle: item.japaneseTitle,
                tags: item.tags,
                pages: pages,
                totalPageCount: item.totalPageCount,
                addedAt: item.createdAt
            )
            let expectedPageIndexes = Set(pages.map(\.index))
            // Startup trusts the persisted completion bitmap. Full media
            // validation is intentionally left to explicit/local-file audit
            // flows instead of opening every completed page during launch.
            job.completedPageIndexes = item.completedPageIndexes.intersection(expectedPageIndexes)
            job.state = normalizedRestoredState(item.stateRaw)
            job.label = item.label
            job.errorMessage = item.errorMessage
            if expectedPageIndexes.isEmpty == false,
               expectedPageIndexes.count == job.totalPageCount,
               job.completedPageIndexes == expectedPageIndexes,
               job.state != .cancelled {
                job.state = .completed
                job.errorMessage = nil
            } else if job.state == .completed {
                job.state = .paused
                job.errorMessage = String(localized: "部分下载页面信息缺失，请继续下载")
            } else if item.inFlightPageIndexes.isEmpty == false {
                job.state = .paused
                job.errorMessage = String(localized: "后台下载任务恢复中")
            }
            reconciliations.append((job: job, baseline: baseline))
        }
        return reconciliations
    }

    nonisolated private static func makePersistedDownloadJob(_ item: PersistedDownload) -> DownloadJob {
        var job = DownloadJob(
            key: item.key,
            title: item.title,
            japaneseTitle: item.japaneseTitle,
            tags: item.tags,
            pages: item.pages,
            totalPageCount: item.totalPageCount,
            addedAt: item.createdAt
        )
        job.completedPageIndexes = item.completedPageIndexes
        job.state = normalizedRestoredState(item.stateRaw)
        job.label = item.label
        job.errorMessage = item.errorMessage
        if item.inFlightPageIndexes.isEmpty == false {
            job.state = .paused
            job.errorMessage = String(localized: "后台下载任务恢复中")
        }
        return job
    }

    nonisolated private static func normalizedRestoredState(_ rawValue: String) -> DownloadState {
        let state = DownloadState(rawValue: rawValue) ?? .queued
        return state == .running ? .queued : state
    }

    func saveCookie(_ cookieHeader: String) async -> Bool {
        do {
            try Task.checkCancellation()
            try await sessionVault.saveCookieHeader(cookieHeader)
            guard try await sessionVault.hasAuthenticatedSession() else {
                throw EHError.invalidCookie
            }
            try Task.checkCancellation()
            completeAuthentication()
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func login(username: String, password: String) async -> Bool {
        guard isPasswordLoginInProgress == false else { return false }
        isPasswordLoginInProgress = true
        defer { isPasswordLoginInProgress = false }
        do {
            _ = try await api.login(username: username, password: password)
            guard try await sessionVault.hasAuthenticatedSession() else {
                throw EHError.invalidCookie
            }
            completeAuthentication()
            return true
        } catch is CancellationError {
            isGuestMode = true
            return false
        } catch {
            isGuestMode = true
            errorMessage = error.localizedDescription
            return false
        }
    }

    func clearSession() async {
        do {
            try await sessionVault.clear()
            isGuestMode = true
            site = .eHentai
            persistSettings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshSessionStatus() async {
        isGuestMode = (try? await sessionVault.hasAuthenticatedSession()) != true
        if isGuestMode { site = .eHentai }
        persistSettings()
    }

    private func completeAuthentication() {
        isGuestMode = false
        selectedRoute = .browse
        errorMessage = nil
        persistSettings()
    }

    func handleIncomingURL(_ url: URL) {
        if url.scheme == "ehviewer",
           let sharedURLString = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value,
           let sharedURL = URL(string: sharedURLString) {
            handleIncomingURL(sharedURL)
            return
        }

        if BackupFileFormat.isGallerySyncURL(url) {
            stageIncomingGallerySync(url)
            return
        }

        if BackupFileFormat.isDownloadArchiveURL(url) {
            stageIncomingArchive(url)
            return
        }

        if let key = Self.galleryKey(from: url) {
            selectedRoute = .gallery(key)
        }
    }

    func confirmIncomingArchive() async {
        guard let pending = pendingIncomingArchive else { return }
        await confirmIncomingArchive(pending)
    }

    func discardIncomingArchive() {
        guard let pending = pendingIncomingArchive else { return }
        try? FileManager.default.removeItem(at: pending.stagedURL.deletingLastPathComponent())
        pendingIncomingArchive = nil
    }

    func stageGallerySyncImport(from url: URL) {
        stageIncomingGallerySync(url)
    }

    func confirmIncomingGallerySync() async {
        guard let pending = pendingIncomingGallerySync else { return }
        await confirmIncomingGallerySync(pending)
    }

    func discardIncomingGallerySync() {
        guard let pending = pendingIncomingGallerySync else { return }
        try? FileManager.default.removeItem(at: pending.stagedURL.deletingLastPathComponent())
        pendingIncomingGallerySync = nil
    }

    func discardPendingSharedFile(_ url: URL) {
        if pendingSharedFileURL == url {
            pendingSharedFileURL = nil
        }
        try? FileManager.default.removeItem(at: url)
    }

    /// 导入完成后删除系统留在应用临时目录内的文件副本（iOS 文件选择器与
    /// 「打开方式」会把文件复制到 tmp/Inbox）。macOS 的选择器返回原文件的
    /// 安全作用域 URL，位于临时目录之外，不会被误删。
    func discardTemporaryImportCopy(_ url: URL) {
        guard Self.isInsideTemporaryDirectory(url) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    nonisolated private static func isInsideTemporaryDirectory(_ url: URL) -> Bool {
        let temporaryPath = FileManager.default.temporaryDirectory.path
        let normalized = temporaryPath.hasSuffix("/") ? temporaryPath : temporaryPath + "/"
        return url.standardizedFileURL.path.hasPrefix(normalized)
    }

    private func stageIncomingArchive(_ url: URL) {
        incomingStagingTask?.cancel()
        incomingStagingGeneration += 1
        let generation = incomingStagingGeneration
        let previousDirectoryToRemove: URL?
        if let previous = pendingIncomingArchive,
           isMigrating == false,
           isRestoringDownloads == false {
            previousDirectoryToRemove = previous.stagedURL.deletingLastPathComponent()
        } else {
            previousDirectoryToRemove = nil
        }

        incomingStagingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.migrationProgress = MigrationProgress(status: String(localized: "正在暂存导入文件…"))
            let outcome = await Self.copyIncomingFileToTemporaryDirectory(
                url,
                previousDirectoryToRemove: previousDirectoryToRemove
            ) { copied, total in
                await MainActor.run {
                    guard generation == self.incomingStagingGeneration else { return }
                    self.migrationProgress = MigrationProgress(
                        status: String(localized: "正在暂存导入文件…"),
                        completed: Int(min(copied, Int64(Int.max))),
                        total: Int(min(total, Int64(Int.max)))
                    )
                }
            }

            guard generation == incomingStagingGeneration else {
                if case .success(let staged) = outcome {
                    Task.detached(priority: .utility) {
                        try? FileManager.default.removeItem(at: staged.directory)
                    }
                }
                return
            }
            self.migrationProgress = nil
            self.incomingStagingTask = nil

            switch outcome {
            case .success(let staged):
                self.importResultMessage = nil
                self.errorMessage = nil
                let pending = PendingIncomingArchive(
                    stagedURL: staged.stagedURL,
                    fileName: staged.fileName
                )
                self.pendingIncomingArchive = pending
            case .failure(let message):
                self.errorMessage = message
            }
        }
    }

    private func stageIncomingGallerySync(_ url: URL) {
        incomingStagingTask?.cancel()
        incomingStagingGeneration += 1
        let generation = incomingStagingGeneration
        let previousDirectoryToRemove: URL?
        if isMigrating == false, isRestoringDownloads == false {
            previousDirectoryToRemove = pendingIncomingGallerySync?.stagedURL.deletingLastPathComponent()
                ?? pendingIncomingArchive?.stagedURL.deletingLastPathComponent()
        } else {
            previousDirectoryToRemove = nil
        }

        incomingStagingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.migrationProgress = MigrationProgress(status: String(localized: "正在暂存画廊信息包…"))
            let outcome = await Self.copyIncomingFileToTemporaryDirectory(
                url,
                previousDirectoryToRemove: previousDirectoryToRemove,
                maximumBytes: GallerySyncArchive.maximumArchiveBytes
            ) { copied, total in
                await MainActor.run {
                    guard generation == self.incomingStagingGeneration else { return }
                    self.migrationProgress = MigrationProgress(
                        status: String(localized: "正在暂存画廊信息包…"),
                        completed: Int(min(copied, Int64(Int.max))),
                        total: Int(min(total, Int64(Int.max)))
                    )
                }
            }

            guard generation == incomingStagingGeneration else {
                if case .success(let staged) = outcome {
                    Task.detached(priority: .utility) {
                        try? FileManager.default.removeItem(at: staged.directory)
                    }
                }
                return
            }
            self.migrationProgress = nil
            self.incomingStagingTask = nil

            switch outcome {
            case .success(let staged):
                self.importResultMessage = nil
                self.errorMessage = nil
                self.pendingIncomingArchive = nil
                self.pendingIncomingGallerySync = PendingIncomingGallerySync(
                    stagedURL: staged.stagedURL,
                    fileName: staged.fileName
                )
            case .failure(let message):
                self.errorMessage = message
            }
        }
    }

    @concurrent
    nonisolated private static func copyIncomingFileToTemporaryDirectory(
        _ url: URL,
        previousDirectoryToRemove: URL?,
        maximumBytes: Int64? = nil,
        progress: (@Sendable (Int64, Int64) async -> Void)? = nil
    ) async -> IncomingStagingOutcome {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            try Task.checkCancellation()
            let totalBytes = Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            if let maximumBytes,
               totalBytes > maximumBytes {
                throw GallerySyncArchiveError.archiveTooLarge
            }
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("EhViewer-Incoming-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let fileName = url.lastPathComponent.isEmpty ? "EhViewer-Incoming" : url.lastPathComponent
            let stagedURL = directory.appendingPathComponent(fileName)
            do {
                guard FileManager.default.createFile(atPath: stagedURL.path, contents: nil) else {
                    throw EHError.storageFailed(String(localized: "无法创建导入暂存文件。"))
                }
                let source = try FileHandle(forReadingFrom: url)
                let destination = try FileHandle(forWritingTo: stagedURL)
                defer {
                    try? source.close()
                    try? destination.close()
                }
                var copiedBytes: Int64 = 0
                while let chunk = try source.read(upToCount: 64 * 1024), chunk.isEmpty == false {
                    try Task.checkCancellation()
                    copiedBytes += Int64(chunk.count)
                    if let maximumBytes, copiedBytes > maximumBytes {
                        throw GallerySyncArchiveError.archiveTooLarge
                    }
                    try destination.write(contentsOf: chunk)
                    await progress?(copiedBytes, max(totalBytes, copiedBytes))
                }
                guard totalBytes == 0 || copiedBytes == totalBytes else {
                    throw EHError.storageFailed(String(localized: "导入文件在复制期间发生变化。"))
                }
            } catch {
                try? FileManager.default.removeItem(at: directory)
                throw error
            }

            // iOS 文件选择器/「打开方式」会在 tmp/Inbox 留下源文件副本，
            // 复制到暂存目录后即可删除，避免导入后残留多份数据。
            if Self.isInsideTemporaryDirectory(url) {
                try? FileManager.default.removeItem(at: url)
            }

            if let previousDirectoryToRemove {
                try? FileManager.default.removeItem(at: previousDirectoryToRemove)
            }
            return .success(
                StagedIncomingFile(
                    directory: directory,
                    stagedURL: stagedURL,
                    fileName: fileName
                )
            )
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func confirmIncomingArchive(_ pending: PendingIncomingArchive) async {
        guard pendingIncomingArchive?.id == pending.id else { return }
        guard isMigrating == false else {
            errorMessage = nil
            importResultMessage = String(localized: "已有导入或导出任务进行中，请稍后重试。")
            return
        }
        guard isRestoringDownloads == false else {
            errorMessage = nil
            importResultMessage = String(localized: "已有恢复任务正在进行，请稍后重试。")
            return
        }

        let directory = pending.stagedURL.deletingLastPathComponent()
        let resultMessage = await restoreDownloads(from: pending.stagedURL).message

        if pendingIncomingArchive?.id == pending.id {
            pendingIncomingArchive = nil
        }
        try? FileManager.default.removeItem(at: directory)
        errorMessage = nil
        importResultMessage = resultMessage
    }

    func confirmIncomingGallerySync(_ pending: PendingIncomingGallerySync) async {
        guard pendingIncomingGallerySync?.id == pending.id else { return }
        let directory = pending.stagedURL.deletingLastPathComponent()
        defer {
            if pendingIncomingGallerySync?.id == pending.id {
                pendingIncomingGallerySync = nil
            }
            try? FileManager.default.removeItem(at: directory)
        }

        guard isMigrating == false, isRestoringDownloads == false else {
            errorMessage = nil
            importResultMessage = String(localized: "已有导入或导出任务进行中，请稍后重试。")
            return
        }

        guard let outcome = await importGallerySync(from: pending.stagedURL) else { return }
        errorMessage = nil
        importResultMessage = Self.gallerySyncOutcomeMessage(outcome)
    }

    static func galleryKey(from url: URL) -> GalleryKey? {
        let components = ([url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" })
        guard let gIndex = components.firstIndex(where: { $0.caseInsensitiveCompare("g") == .orderedSame }),
              components.count > gIndex + 2,
              let gid = Int64(components[gIndex + 1]),
              components[gIndex + 2].isEmpty == false else { return nil }
        return GalleryKey(gid: gid, token: components[gIndex + 2])
    }

    func persistSettings() {
        defaults.set(site.rawValue, forKey: "site")
    }

    func persistReadingSettings() {
        readingSettings.save(to: defaults)
    }

    func persistDownloadPreferences() {
        defaults.set(downloadSortOrder.rawValue, forKey: "downloadSortOrder")
        defaults.set(downloadStatusFilter.rawValue, forKey: "downloadStatusFilter")
        defaults.set(downloadLayoutMode.rawValue, forKey: "downloadLayoutMode")
        if let data = try? JSONEncoder().encode(downloadCategoryFilter) {
            defaults.set(data, forKey: "downloadCategoryFilter")
        }
    }

    private static func loadDownloadCategoryFilter(from defaults: UserDefaults) -> Set<GalleryCategory> {
        guard let data = defaults.data(forKey: "downloadCategoryFilter"),
              let categories = try? JSONDecoder().decode(Set<GalleryCategory>.self, from: data) else {
            return Set(GalleryCategory.allCases)
        }
        return categories
    }

    func exportGallerySync(keys: Set<GalleryKey>? = nil) async -> URL? {
        guard beginMigration(status: String(localized: "正在准备画廊同步包…")) else { return nil }
        defer { finishMigration() }

        let archiveName = if let keys {
            "EhViewer-Galleries-\(keys.count)items-\(Self.timestampForExportFilename()).ehgallery"
        } else {
            "EhViewer-Galleries-\(Self.timestampForExportFilename()).ehgallery"
        }
        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(archiveName)
        let partialURL = archiveURL.appendingPathExtension("part")
        var archiveReady = false
        defer {
            // 导出失败或取消时清理未完成的压缩包，避免残留占用存储。
            if archiveReady == false {
                try? FileManager.default.removeItem(at: archiveURL)
                try? FileManager.default.removeItem(at: partialURL)
            }
        }

        do {
            setMigrationProgress(status: String(localized: "正在读取下载列表…"), fraction: 0.15)
            let jobs = await downloads.snapshot()
            guard jobs.isEmpty == false else {
                errorMessage = String(localized: "下载列表中没有可导出的画廊。")
                return nil
            }

            let selectedJobs = if let keys {
                jobs.filter { keys.contains($0.key) }
            } else {
                jobs
            }
            guard selectedJobs.isEmpty == false else {
                errorMessage = keys == nil
                    ? String(localized: "下载列表中没有可导出的画廊。")
                    : String(localized: "所选项目没有可导出的画廊。")
                return nil
            }

            let storedSummaries = try await persistence.downloadedGallerySummaries(for: Set(selectedJobs.map(\.key)))
            let summariesByKey = try await transferSummaries(
                for: Set(selectedJobs.map(\.key)),
                stored: storedSummaries
            )
            for job in selectedJobs {
                let summary = summariesByKey[job.key] ?? GallerySummary(
                    key: job.key,
                    title: job.title,
                    japaneseTitle: job.japaneseTitle,
                    pageCount: job.totalPageCount > 0 ? job.totalPageCount : nil,
                    tags: job.tags
                )
                try await persistence.upsertStableSnapshot(
                    StableGalleryMetadataSnapshot(summary: summary, sourceSite: site),
                    retainForDownload: true
                )
            }
            let records = try await persistence.galleryTransferRecords(
                for: Set(selectedJobs.map(\.key))
            )

            setMigrationProgress(status: String(localized: "正在创建画廊同步包…"), fraction: 0.45)
            let snapshot = GallerySyncSnapshot(records: records)
            try await Task.detached(priority: .userInitiated) {
                try GallerySyncArchive.export(snapshot, to: partialURL)
                let verified = try GallerySyncArchive.read(from: partialURL)
                guard verified.records.count == snapshot.records.count,
                      verified.records.map(\.stable.key) == snapshot.records.map(\.stable.key) else {
                    throw GallerySyncArchiveError.invalidArchive
                }
                try FileManager.default.moveItem(at: partialURL, to: archiveURL)
            }.value
            setMigrationProgress(status: String(localized: "画廊同步包已准备完成"), fraction: 1)
            archiveReady = true
            replacePendingSharedFile(with: archiveURL)
            return archiveURL
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Refreshes downloaded-gallery metadata with one complete gdata pass,
    /// followed by up to three retries for failed or incomplete galleries and
    /// one lightweight detail-page fallback. Before making network requests,
    /// the download library is reconciled with the real media files so stale
    /// metadata-only entries cannot survive or participate in device sync.
    @discardableResult
    func refreshDownloadedGalleryMetadata(
        mode: DownloadedGalleryMetadataRefreshMode = .all
    ) async -> DownloadedGalleryMetadataRefreshResult {
        guard isRestoringDownloads == false else {
            errorMessage = String(localized: "正在恢复下载内容，请稍后再更新画廊信息。")
            return .empty
        }
        guard beginMigration(status: String(localized: "正在准备更新已下载画廊信息…")) else { return .empty }
        var didUpdateDownloadedMetadata = false
        defer {
            if didUpdateDownloadedMetadata {
                publishLocalLibraryChange()
            }
            finishMigration()
        }

        do {
            let originalJobs = await downloads.snapshot()
            guard originalJobs.isEmpty == false else {
                importResultMessage = String(localized: "下载列表中没有需要更新的画廊。")
                return .empty
            }

            var emptyKeys: [GalleryKey] = []
            var invalidPageCount = 0
            for (offset, job) in originalJobs.enumerated() {
                try Task.checkCancellation()
                setMigrationProgress(
                    status: String(
                        format: String(localized: "正在检查本地文件 %lld/%lld…"),
                        Int64(offset + 1),
                        Int64(originalJobs.count)
                    ),
                    completed: offset + 1,
                    total: originalJobs.count,
                    fraction: 0.1 * Double(offset + 1) / Double(originalJobs.count)
                )
                let audit = await downloadFiles.auditLocalGallery(
                    for: job.key,
                    removeInvalidFiles: true
                )
                invalidPageCount += audit.invalidFinalFileCount
                if audit.validPages.isEmpty {
                    emptyKeys.append(job.key)
                }
            }

            var removedEmptyGalleryCount = 0
            if emptyKeys.isEmpty == false {
                let removal = await downloads.remove(emptyKeys) { [weak self] progress in
                    guard let self else { return }
                    let normalized = progress.total > 0
                        ? Double(progress.completed) / Double(progress.total)
                        : 1
                    await MainActor.run {
                        self.setMigrationProgress(
                            status: String(
                                format: String(localized: "正在清理空壳画廊 %lld/%lld…"),
                                Int64(progress.completed),
                                Int64(progress.total)
                            ),
                            completed: progress.completed,
                            total: progress.total,
                            fraction: 0.1 + 0.05 * normalized
                        )
                    }
                }
                removedEmptyGalleryCount = removal.removedCount
                didUpdateDownloadedMetadata = removal.removedCount > 0
            }

            let emptyKeySet = Set(emptyKeys)
            let jobs = originalJobs.filter { emptyKeySet.contains($0.key) == false }
            guard jobs.isEmpty == false else {
                let result = DownloadedGalleryMetadataRefreshResult(
                    targetCount: 0,
                    completeCount: 0,
                    failedCount: 0,
                    incompleteCount: 0,
                    gdataRetriedCount: 0,
                    detailCompletionCount: 0,
                    removedEmptyGalleryCount: removedEmptyGalleryCount,
                    invalidPageCount: invalidPageCount
                )
                importResultMessage = refreshResultMessage(result)
                return result
            }

            let allKeys = jobs.map(\.key)
            let stored = try await persistence.downloadedGallerySummaries(for: Set(allKeys))
            var summariesByKey = Dictionary(
                stored.map { ($0.key, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            for job in jobs where summariesByKey[job.key] == nil {
                summariesByKey[job.key] = GallerySummary(
                    key: job.key,
                    title: job.title,
                    japaneseTitle: job.japaneseTitle,
                    pageCount: job.totalPageCount > 0 ? job.totalPageCount : nil,
                    tags: job.tags
                )
            }

            let targetKeys = allKeys.filter { key in
                guard let summary = summariesByKey[key] else { return true }
                return mode == .all || summary.metadataCompleteness?.isSummaryComplete != true
            }
            guard targetKeys.isEmpty == false else {
                let result = DownloadedGalleryMetadataRefreshResult(
                    targetCount: 0,
                    completeCount: 0,
                    failedCount: 0,
                    incompleteCount: 0,
                    gdataRetriedCount: 0,
                    detailCompletionCount: 0,
                    removedEmptyGalleryCount: removedEmptyGalleryCount,
                    invalidPageCount: invalidPageCount
                )
                importResultMessage = refreshResultMessage(result)
                return result
            }

            let maximumGdataRetries = 3
            let initialGdataStartFraction = 0.15
            let initialGdataEndFraction = 0.4
            let retryGdataStartFraction = 0.4
            let retryGdataEndFraction = 0.75
            let detailStartFraction = 0.75
            let detailEndFraction = 0.95

            var pendingKeys = targetKeys
            var hadUsableResponse = Set<GalleryKey>()
            var gdataRetriedKeys = Set<GalleryKey>()
            var gdataBlocked = false
            var nextGdataAttempt = 0 // 0 is the initial request; 1...3 are retries.

            while pendingKeys.isEmpty == false, nextGdataAttempt <= maximumGdataRetries {
                try Task.checkCancellation()
                let requestKeys = pendingKeys
                let attempt = nextGdataAttempt
                if attempt > 0 {
                    let retryFraction = retryGdataStartFraction
                        + (retryGdataEndFraction - retryGdataStartFraction)
                        * Double(attempt - 1) / Double(maximumGdataRetries)
                    setMigrationProgress(
                        status: String(format: String(localized: "正在等待第 %lld/3 次重试…"), Int64(attempt)),
                        completed: targetKeys.count - requestKeys.count,
                        total: targetKeys.count,
                        fraction: retryFraction
                    )
                    try await Task.sleep(for: .seconds(attempt))
                    gdataRetriedKeys.formUnion(requestKeys)
                } else {
                    setMigrationProgress(
                        status: String(format: String(localized: "正在获取画廊信息（首次） %lld/%lld…"), Int64(0), Int64(requestKeys.count)),
                        completed: 0,
                        total: requestKeys.count,
                        fraction: initialGdataStartFraction
                    )
                }

                let fetched = try await fetchGallerySummaryResponses(for: requestKeys) { [weak self] processed, total in
                    guard let self else { return }
                    let normalized = total > 0 ? Double(processed) / Double(total) : 1
                    let fraction: Double
                    let status: String
                    if attempt == 0 {
                        fraction = initialGdataStartFraction
                            + (initialGdataEndFraction - initialGdataStartFraction) * normalized
                        status = String(format: String(localized: "正在获取画廊信息（首次） %lld/%lld…"), Int64(processed), Int64(total))
                    } else {
                        fraction = retryGdataStartFraction
                            + (retryGdataEndFraction - retryGdataStartFraction)
                            * (Double(attempt - 1) + normalized) / Double(maximumGdataRetries)
                        status = String(format: String(localized: "正在重试画廊信息（第 %lld/3 次） %lld/%lld…"), Int64(attempt), Int64(processed), Int64(total))
                    }
                    self.setMigrationProgress(
                        status: status,
                        completed: processed,
                        total: total,
                        fraction: fraction
                    )
                }
                var nextPending: [GalleryKey] = []
                var successfulSummaries: [GallerySummary] = []
                for response in fetched.responses {
                    guard let incoming = response.summary else {
                        nextPending.append(response.key)
                        continue
                    }
                    hadUsableResponse.insert(response.key)
                    let resolved = incoming.metadataCompleteness == nil
                        ? fetchedMetadataSummary(incoming)
                        : incoming
                    let merged = mergeMetadataSummary(resolved, with: summariesByKey[response.key])
                    summariesByKey[response.key] = merged
                    successfulSummaries.append(merged)
                    if merged.metadataCompleteness?.isSummaryComplete != true {
                        nextPending.append(response.key)
                    }
                }

                if successfulSummaries.isEmpty == false {
                    let capturedAt = Date()
                    try await persistence.saveDownloadedMetadata(
                        stableSnapshots: successfulSummaries.map {
                            StableGalleryMetadataSnapshot(
                                summary: $0,
                                sourceSite: site,
                                capturedAt: capturedAt
                            )
                        },
                        dynamicSnapshots: successfulSummaries.map { summary in
                            var completeness = GalleryMetadataCompleteness()
                            completeness.rating = summary.metadataCompleteness?.rating ?? .notLoaded
                            completeness.ratingCount = summary.metadataCompleteness?.ratingCount ?? .notLoaded
                            return DownloadedGalleryDynamicSnapshot(
                                key: summary.key,
                                rating: summary.rating,
                                ratingCount: summary.ratingCount,
                                capturedAt: capturedAt,
                                completeness: completeness
                            )
                        }
                    )
                    await downloads.mergeMetadataInMemory(successfulSummaries)
                    didUpdateDownloadedMetadata = true
                }

                pendingKeys = Array(Set(nextPending)).sorted { $0.id < $1.id }
                gdataBlocked = fetched.blocked
                if pendingKeys.isEmpty || gdataBlocked { break }
                nextGdataAttempt += 1
            }

            var detailCompletionKeys = Set<GalleryKey>()
            let detailKeys = pendingKeys.filter { summariesByKey[$0]?.metadataCompleteness?.isSummaryComplete != true }
            if detailKeys.isEmpty == false, gdataBlocked == false {
                setMigrationProgress(
                    status: String(format: String(localized: "正在补全画廊详情 %lld/%lld…"), Int64(0), Int64(detailKeys.count)),
                    completed: 0,
                    total: detailKeys.count,
                    fraction: detailStartFraction
                )
                let detailResults = try await fetchDetailMetadata(for: detailKeys) { [weak self] completed, total in
                    guard let self else { return }
                    let normalized = total > 0 ? Double(completed) / Double(total) : 1
                    self.setMigrationProgress(
                        status: String(format: String(localized: "正在补全画廊详情 %lld/%lld…"), Int64(completed), Int64(total)),
                        completed: completed,
                        total: total,
                        fraction: detailStartFraction + (detailEndFraction - detailStartFraction) * normalized
                    )
                }
                var detailStable: [StableGalleryMetadataSnapshot] = []
                var detailDynamic: [DownloadedGalleryDynamicSnapshot] = []
                var detailSummaries: [GallerySummary] = []
                for result in detailResults {
                    guard let detail = result.detail else { continue }
                    let merged = mergeMetadataSummary(detail.summary, with: summariesByKey[result.key])
                    summariesByKey[result.key] = merged
                    detailSummaries.append(merged)
                    detailStable.append(
                        StableGalleryMetadataSnapshot(
                            detail: detail,
                            sourceSite: site,
                            includesPreviewPages: false
                        )
                    )
                    detailDynamic.append(DownloadedGalleryDynamicSnapshot(detail: detail))
                    detailCompletionKeys.insert(result.key)
                }
                if detailStable.isEmpty == false {
                    try await persistence.saveDownloadedMetadata(
                        stableSnapshots: detailStable,
                        dynamicSnapshots: detailDynamic
                    )
                    await downloads.mergeMetadataInMemory(detailSummaries)
                    didUpdateDownloadedMetadata = true
                }
            }

            let completeKeys = Set(targetKeys.filter {
                summariesByKey[$0]?.metadataCompleteness?.isSummaryComplete == true
            })
            let incompleteKeys = Set(targetKeys.filter { key in
                guard completeKeys.contains(key) == false else { return false }
                let summary = summariesByKey[key]
                let hasStoredField = summary?.metadataCompleteness.map { completeness in
                    [completeness.title, completeness.authors, completeness.tags, completeness.category,
                     completeness.pageCount, completeness.postedAt, completeness.thumbnailURL, completeness.rating]
                        .contains { $0.isLoaded }
                } ?? false
                return hadUsableResponse.contains(key) || hasStoredField
            })
            let failedKeys = Set(targetKeys).subtracting(completeKeys).subtracting(incompleteKeys)
            let result = DownloadedGalleryMetadataRefreshResult(
                targetCount: targetKeys.count,
                completeCount: completeKeys.count,
                failedCount: failedKeys.count,
                incompleteCount: incompleteKeys.count,
                gdataRetriedCount: gdataRetriedKeys.count,
                detailCompletionCount: detailCompletionKeys.count,
                removedEmptyGalleryCount: removedEmptyGalleryCount,
                invalidPageCount: invalidPageCount
            )
            setMigrationProgress(
                status: String(localized: "已完成画廊信息更新"),
                completed: targetKeys.count,
                total: targetKeys.count,
                fraction: 1
            )
            importResultMessage = refreshResultMessage(result)
            return result
        } catch is CancellationError {
            return .empty
        } catch {
            errorMessage = error.localizedDescription
            return .empty
        }
    }

    private struct GallerySummaryFetchResult: Sendable {
        let responses: [GallerySummaryResponse]
        let blocked: Bool
    }

    private func fetchGallerySummaryResponses(
        for keys: [GalleryKey],
        progress: ((Int, Int) -> Void)? = nil
    ) async throws -> GallerySummaryFetchResult {
        var responses: [GallerySummaryResponse] = []
        var blocked = false
        for start in stride(from: 0, to: keys.count, by: 25) {
            try Task.checkCancellation()
            let end = min(start + 25, keys.count)
            let batch = Array(keys[start..<end])
            do {
                let result = try await api.gallerySummaryBatch(for: batch, site: site)
                responses.append(contentsOf: result.responses)
                progress?(end, keys.count)
                if result.hasBlockingResponse {
                    blocked = true
                    responses.append(contentsOf: keys[end...].map {
                        GallerySummaryResponse(key: $0, status: .missingResponse)
                    })
                    break
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let status: GallerySummaryResponseStatus = .invalidResponse(error.localizedDescription)
                responses.append(contentsOf: batch.map {
                    GallerySummaryResponse(key: $0, status: status)
                })
                progress?(end, keys.count)
                if Self.shouldStopMetadataRefresh(for: error) {
                    blocked = true
                    responses.append(contentsOf: keys[end...].map {
                        GallerySummaryResponse(key: $0, status: .missingResponse)
                    })
                    break
                }
            }
        }
        return GallerySummaryFetchResult(responses: responses, blocked: blocked)
    }

    private struct DetailMetadataFetchResult: Sendable {
        let key: GalleryKey
        let detail: GalleryDetail?
    }

    private func fetchDetailMetadata(
        for keys: [GalleryKey],
        progress: ((Int, Int) -> Void)? = nil
    ) async throws -> [DetailMetadataFetchResult] {
        let scheduler = MetadataRequestScheduler()
        return try await withThrowingTaskGroup(of: DetailMetadataFetchResult.self) { group in
            for key in keys {
                group.addTask { [api, site] in
                    guard await scheduler.acquire() else {
                        return DetailMetadataFetchResult(key: key, detail: nil)
                    }
                    do {
                        let detail = try await api.detailMetadata(for: key, site: site)
                        await scheduler.release()
                        return DetailMetadataFetchResult(key: key, detail: detail)
                    } catch is CancellationError {
                        await scheduler.release()
                        throw CancellationError()
                    } catch {
                        if Self.shouldStopMetadataRefresh(for: error) {
                            await scheduler.stop()
                        }
                        await scheduler.release()
                        return DetailMetadataFetchResult(key: key, detail: nil)
                    }
                }
            }

            var results: [DetailMetadataFetchResult] = []
            for try await result in group {
                results.append(result)
                progress?(results.count, keys.count)
            }
            return results
        }
    }

    nonisolated private static func shouldStopMetadataRefresh(for error: Error) -> Bool {
        if let error = error as? EHError {
            switch error {
            case .authenticationRequired, .rateLimited, .bandwidthLimited, .exHentaiAccessDenied:
                return true
            default:
                break
            }
        }
        let message = error.localizedDescription.localizedLowercase
        return message.contains("rate")
            || message.contains("limit")
            || message.contains("bandwidth")
            || message.contains("login")
            || message.contains("auth")
            || message.contains("access denied")
    }

    private func refreshResultMessage(_ result: DownloadedGalleryMetadataRefreshResult) -> String {
        String(
            format: String(localized: "清理空壳画廊 %d，发现非法页面 %d；目标 %d，完整成功 %d，失败 %d，仍不完整 %d，gdata 重试 %d，详情补全 %d。"),
            result.removedEmptyGalleryCount,
            result.invalidPageCount,
            result.targetCount,
            result.completeCount,
            result.failedCount,
            result.incompleteCount,
            result.gdataRetriedCount,
            result.detailCompletionCount
        )
    }

    private func importGallerySync(from archiveURL: URL) async -> GallerySyncImportResult? {
        guard beginMigration(status: String(localized: "正在读取画廊同步包…")) else { return nil }
        defer { finishMigration() }

        do {
            setMigrationProgress(status: String(localized: "正在验证画廊同步包…"), fraction: 0.2)
            let snapshot = try await Task.detached(priority: .userInitiated) {
                try GallerySyncArchive.read(from: archiveURL)
            }.value
            let existing = try await persistence.downloadedGallerySummaries(
                for: Set(snapshot.galleries.map(\.key))
            )
            setMigrationProgress(status: String(localized: "正在恢复画廊信息…"), fraction: 0.5)
            let resolution = try await resolveTransferMetadata(
                snapshot.galleries,
                existing: existing,
                fetchMissingMetadata: false
            ) { [weak self] completed, total in
                guard let self else { return }
                let fraction = total > 0 ? Double(completed) / Double(total) : 1
                self.setMigrationProgress(
                    status: String(localized: "正在补全画廊信息 \(completed)/\(total)…"),
                    completed: completed,
                    total: total,
                    fraction: 0.5 + 0.25 * fraction
                )
            }
            let resolvedSummaries = Array(resolution.summariesByKey.values)
            let galleryOutcome = try await persistence.mergeDownloadedGallerySyncSummaries(resolvedSummaries)
            let resolvedByKey = Dictionary(uniqueKeysWithValues: resolvedSummaries.map { ($0.key, $0) })
            for record in snapshot.records {
                let refreshedStable: StableGalleryMetadataSnapshot
                if let summary = resolvedByKey[record.stable.key] {
                    refreshedStable = GallerySnapshotMerger.merge(
                        existing: record.stable,
                        incoming: StableGalleryMetadataSnapshot(summary: summary, sourceSite: site)
                    )
                } else {
                    refreshedStable = record.stable
                }
                try await persistence.promoteToDownloadedGallery(
                    stable: refreshedStable,
                    dynamic: record.dynamic
                )
            }
            setMigrationProgress(status: String(localized: "正在加入下载列表…"), fraction: 0.8)
            await downloads.mergeMetadata(resolvedSummaries)
            let queuedDownloadCount = await queueMissingSyncedDownloads(resolvedSummaries)
            setMigrationProgress(status: String(localized: "画廊同步完成"), fraction: 1)
            return GallerySyncImportResult(
                galleryOutcome: galleryOutcome,
                queuedDownloadCount: queuedDownloadCount,
                incompleteMetadataCount: resolution.incompleteCount
            )
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func exportDownloadArchive(keys: Set<GalleryKey>? = nil) async -> URL? {
        guard !isLoadingDownloads, localDownloadLoadError == nil else { return nil }
        guard beginMigration(status: String(localized: "正在准备下载包…")) else { return nil }
        defer { finishMigration() }

        let scopeName = keys.map { "\($0.count)items" } ?? "All"
        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("EhViewer-Downloads-\(scopeName)-\(Self.timestampForExportFilename()).eharchive")
        let partialURL = archiveURL.appendingPathExtension("part")
        var archiveReady = false
        defer {
            // 导出失败或取消时清理未完成的压缩包，避免残留占用存储。
            if archiveReady == false {
                try? FileManager.default.removeItem(at: archiveURL)
                try? FileManager.default.removeItem(at: partialURL)
            }
        }

        do {
            setMigrationProgress(status: String(localized: "正在读取下载任务…"), fraction: 0.05)
            let liveJobs = await downloads.snapshot()
            let persisted = (try? await persistence.downloadJobs()) ?? []
            let persistedJobs = persisted.map(Self.makePersistedDownloadJob)
            var totalPageCounts = Dictionary(
                uniqueKeysWithValues: persisted.map { ($0.key, $0.totalPageCount) }
            )
            var jobsByKey = Dictionary(uniqueKeysWithValues: persistedJobs.map { ($0.key, $0) })
            for job in liveJobs {
                jobsByKey[job.key] = job
                totalPageCounts[job.key] = max(totalPageCounts[job.key] ?? 0, job.totalPageCount)
            }
            let jobs = jobsByKey.values.sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            let selected = if let keys {
                jobs.filter { keys.contains($0.key) }
            } else {
                jobs
            }
            guard selected.isEmpty == false else {
                errorMessage = keys == nil
                    ? String(localized: "没有可导出的下载内容。")
                    : String(localized: "所选项目没有可导出的下载内容。")
                return nil
            }

            let storedSummaries = try await persistence.downloadedGallerySummaries(for: Set(selected.map(\.key)))
            let summariesByKey = try await transferSummaries(
                for: Set(selected.map(\.key)),
                stored: storedSummaries
            )
            for item in selected {
                let summary = summariesByKey[item.key] ?? GallerySummary(
                    key: item.key,
                    title: item.title,
                    japaneseTitle: item.japaneseTitle,
                    pageCount: item.totalPageCount > 0 ? item.totalPageCount : nil,
                    tags: item.tags
                )
                try await persistence.upsertStableSnapshot(
                    StableGalleryMetadataSnapshot(summary: summary, sourceSite: site),
                    retainForDownload: true
                )
            }
            let transferRecords = (try? await persistence.galleryTransferRecords(
                for: Set(selected.map(\.key))
            )) ?? []
            let transferRecordByKey = Dictionary(uniqueKeysWithValues: transferRecords.map { ($0.stable.key, $0) })

            let items = selected.map { item in
                let pageTokens = Dictionary(uniqueKeysWithValues: item.pages.compactMap { page -> (Int, String)? in
                    guard let token = pageToken(from: page.pageURL) else { return nil }
                    return (page.index, token)
                })
                let highestPage = item.pages.map { $0.index + 1 }.max() ?? 0
                let summary = summariesByKey[item.key]
                return DownloadArchiveExportItem(
                    key: item.key,
                    title: summary?.title ?? item.title,
                    japaneseTitle: summary?.japaneseTitle ?? item.japaneseTitle,
                    tags: summary?.tags ?? item.tags,
                    metadataCompleteness: summary?.metadataCompleteness,
                    transferRecord: transferRecordByKey[item.key],
                    totalPageCount: max(totalPageCounts[item.key] ?? item.pages.count, highestPage),
                    pageTokens: pageTokens
                )
            }

            setMigrationProgress(status: String(localized: "正在创建下载包…"), fraction: 0.1)
            _ = try await DownloadArchiveExporter.export(
                items: items,
                files: downloadFiles,
                to: partialURL
            ) { [weak self] progress in
                guard let self else { return }
                let archiveFraction = progress.fraction
                await self.setMigrationProgress(
                    status: progress.currentTitle.map { String(localized: "正在导出《\($0)》…") } ?? String(localized: "正在导出下载文件…"),
                    completed: progress.completedFiles,
                    total: progress.totalFiles,
                    fraction: 0.1 + archiveFraction * 0.9,
                    estimatedRemainingSeconds: progress.estimatedRemainingSeconds
                )
            }
            guard let archiveSize = try? partialURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  archiveSize > 0 else {
                throw EHError.parsingFailed(String(localized: "导出的下载包没有可恢复内容。"))
            }
            try FileManager.default.moveItem(at: partialURL, to: archiveURL)
            setMigrationProgress(status: String(localized: "下载包已准备完成"), fraction: 1)
            archiveReady = true
            replacePendingSharedFile(with: archiveURL)
            return archiveURL
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func replacePendingSharedFile(with url: URL) {
        if let previous = pendingSharedFileURL, previous != url {
            try? FileManager.default.removeItem(at: previous)
        }
        pendingSharedFileURL = url
    }

    private static func hasMetadataValue(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func normalizedMetadataSummary(_ summary: GallerySummary) -> GallerySummary {
        var normalized = summary
        let completeness = summary.metadataCompleteness ?? GalleryMetadataCompleteness()
        var normalizedCompleteness = completeness
        normalizedCompleteness.title = completeness.title.isLoaded
            ? (Self.hasMetadataValue(summary.title) ? .loadedWithValue : .loadedEmpty)
            : .notLoaded
        normalizedCompleteness.japaneseTitle = completeness.japaneseTitle.isLoaded
            ? (Self.hasMetadataValue(summary.japaneseTitle) ? .loadedWithValue : .loadedEmpty)
            : .notLoaded
        normalized.metadataCompleteness = normalizedCompleteness
        return normalized
    }

    /// A successful API response resolves the tag field even when the source
    /// legitimately returns an empty tag list. A title field is complete only
    /// when at least one actual title value was written.
    private func fetchedMetadataSummary(_ summary: GallerySummary) -> GallerySummary {
        var fetched = summary
        fetched.metadataCompleteness = GalleryMetadataCompleteness(
            title: Self.hasMetadataValue(summary.title) ? .loadedWithValue : .loadedEmpty,
            japaneseTitle: Self.hasMetadataValue(summary.japaneseTitle) ? .loadedWithValue : .loadedEmpty,
            authors: StableGalleryMetadataSnapshot.authors(from: summary.tags).isEmpty
                ? .loadedEmpty
                : .loadedWithValue,
            uploader: summary.uploader == nil ? .loadedEmpty : .loadedWithValue,
            tags: summary.tags.isEmpty ? .loadedEmpty : .loadedWithValue,
            category: summary.category == nil ? .loadedEmpty : .loadedWithValue,
            pageCount: summary.pageCount == nil ? .loadedEmpty : .loadedWithValue,
            postedAt: summary.postedAt == nil ? .loadedEmpty : .loadedWithValue,
            thumbnailURL: summary.thumbnailURL == nil ? .loadedEmpty : .loadedWithValue,
            rating: summary.rating == nil ? .loadedEmpty : .loadedWithValue
        )
        return fetched
    }

    /// Merges an incoming package summary without replacing a locally complete
    /// field with an incomplete package field.
    private func mergeMetadataSummary(
        _ incoming: GallerySummary,
        with existing: GallerySummary?
    ) -> GallerySummary {
        guard let existing else { return normalizedMetadataSummary(incoming) }

        let incomingStatus = incoming.metadataCompleteness ?? GalleryMetadataCompleteness()
        let existingStatus = existing.metadataCompleteness ?? GalleryMetadataCompleteness()
        let mergedStable = GallerySnapshotMerger.merge(
            existing: StableGalleryMetadataSnapshot(summary: existing, sourceSite: site),
            incoming: StableGalleryMetadataSnapshot(summary: incoming, sourceSite: site)
        )
        var merged = mergedStable.summary
        var mergedCompleteness = mergedStable.completeness

        func mergeDynamicField<T>(
            _ value: inout T?,
            _ state: inout GalleryFieldState,
            incomingValue: T?,
            incomingState: GalleryFieldState,
            existingValue: T?,
            existingState: GalleryFieldState
        ) {
            if incomingState.isLoaded {
                value = incomingState.hasValue ? incomingValue : nil
                state = incomingState
            } else {
                value = existingValue
                state = existingState
            }
        }

        mergeDynamicField(
            &merged.rating,
            &mergedCompleteness.rating,
            incomingValue: incoming.rating,
            incomingState: incomingStatus.rating,
            existingValue: existing.rating,
            existingState: existingStatus.rating
        )
        mergeDynamicField(
            &merged.ratingCount,
            &mergedCompleteness.ratingCount,
            incomingValue: incoming.ratingCount,
            incomingState: incomingStatus.ratingCount,
            existingValue: existing.ratingCount,
            existingState: existingStatus.ratingCount
        )
        mergeDynamicField(
            &merged.favoriteCategory,
            &mergedCompleteness.favorite,
            incomingValue: incoming.favoriteCategory,
            incomingState: incomingStatus.favorite,
            existingValue: existing.favoriteCategory,
            existingState: existingStatus.favorite
        )
        merged.metadataCompleteness = mergedCompleteness
        return normalizedMetadataSummary(merged)
    }

    private struct MetadataResolution: Sendable {
        let summariesByKey: [GalleryKey: GallerySummary]
        let incompleteCount: Int
    }

    /// Persists the package state before optionally requesting missing fields,
    /// then persists every successful gallery response independently. Archive
    /// restore passes `fetchMissingMetadata == false` so it remains offline;
    /// metadata import can still opt into resumable network completion.
    private func resolveTransferMetadata(
        _ incoming: [GallerySummary],
        existing: [GallerySummary] = [],
        fetchMissingMetadata: Bool = true,
        progress: ((Int, Int) -> Void)? = nil
    ) async throws -> MetadataResolution {
        let existingByKey = Dictionary(
            existing.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var summariesByKey: [GalleryKey: GallerySummary] = [:]
        for summary in incoming {
            summariesByKey[summary.key] = mergeMetadataSummary(summary, with: existingByKey[summary.key])
        }

        if summariesByKey.isEmpty == false {
            _ = try await persistence.mergeDownloadedGallerySyncSummaries(Array(summariesByKey.values))
        }

        var pendingKeys = summariesByKey.values
            .filter { $0.metadataCompleteness?.isSummaryComplete != true }
            .map(\.key)
            .sorted { $0.id < $1.id }
        guard fetchMissingMetadata else {
            return MetadataResolution(
                summariesByKey: summariesByKey,
                incompleteCount: pendingKeys.count
            )
        }
        progress?(0, pendingKeys.count)

        let requestSize = 25
        var completedCount = 0
        for start in stride(from: 0, to: pendingKeys.count, by: requestSize) {
            try Task.checkCancellation()
            let end = min(start + requestSize, pendingKeys.count)
            let batchKeys = Array(pendingKeys[start..<end])
            let fetched: [GallerySummary]
            do {
                fetched = try await api.gallerySummaries(for: batchKeys, site: site)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Keep this and all later keys incomplete. A subsequent import
                // resumes at this checkpoint instead of retrying earlier keys.
                break
            }

            let requestedKeys = Set(batchKeys)
            for summary in fetched where requestedKeys.contains(summary.key) {
                try Task.checkCancellation()
                let completed = fetchedMetadataSummary(summary)
                let merged = mergeMetadataSummary(completed, with: summariesByKey[summary.key])
                _ = try await persistence.mergeDownloadedGallerySyncSummaries([merged])
                summariesByKey[merged.key] = merged
                completedCount += 1
                progress?(completedCount, pendingKeys.count)
            }
        }

        pendingKeys = summariesByKey.values
            .filter { $0.metadataCompleteness?.isSummaryComplete != true }
            .map(\.key)
        return MetadataResolution(
            summariesByKey: summariesByKey,
            incompleteCount: pendingKeys.count
        )
    }

    /// Ensures exports carry complete title/tag metadata for older downloads
    /// that predate the local gallery cache. The API batches these requests in
    /// groups of 25; a failed refresh keeps the locally available metadata.
    private func transferSummaries(
        for keys: Set<GalleryKey>,
        stored: [GallerySummary]
    ) async throws -> [GalleryKey: GallerySummary] {
        var summariesByKey = Dictionary(
            stored.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let keysNeedingRefresh = keys.filter { key in
            guard let summary = summariesByKey[key] else { return true }
            return summary.metadataCompleteness?.isSummaryComplete != true
        }.sorted { $0.id < $1.id }
        guard keysNeedingRefresh.isEmpty == false else {
            return summariesByKey
        }

        let fetched: [GallerySummary]
        do {
            fetched = try await api.gallerySummaries(for: keysNeedingRefresh, site: site)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return summariesByKey
        }
        guard fetched.isEmpty == false else {
            return summariesByKey
        }

        var merged: [GallerySummary] = []
        merged.reserveCapacity(fetched.count)
        let requestedKeys = Set(keysNeedingRefresh)
        for fetchedSummary in fetched where requestedKeys.contains(fetchedSummary.key) {
            let completed = fetchedMetadataSummary(fetchedSummary)
            if let existing = summariesByKey[completed.key] {
                let resolved = mergeMetadataSummary(completed, with: existing)
                summariesByKey[resolved.key] = resolved
                merged.append(resolved)
            } else {
                summariesByKey[completed.key] = completed
                merged.append(completed)
            }
        }
        _ = try? await persistence.mergeDownloadedGallerySyncSummaries(merged)
        return summariesByKey
    }

    nonisolated private static func timestampForExportFilename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: Date())
    }

    /// 启动时清理上次会话遗留的导出/导入暂存临时文件（分享后未删除、
    /// 导入中断等场景）。只删除创建超过 1 小时的文件，避免误伤进行中的任务。
    nonisolated static func sweepStaleTemporaryFiles() {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: fileManager.temporaryDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-3600)
        for entry in entries {
            let name = entry.lastPathComponent
            guard name.hasPrefix("EhViewer-Downloads-")
                || name.hasPrefix("EhViewer-Galleries-")
                || name.hasPrefix("EhViewer-Incoming-") else { continue }
            let created = (try? entry.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            guard created < cutoff else { continue }
            try? fileManager.removeItem(at: entry)
        }
    }

    private func queueMissingSyncedDownloads(_ summaries: [GallerySummary]) async -> Int {
        var seen = Set<GalleryKey>()
        let uniqueSummaries = summaries.filter { seen.insert($0.key).inserted }
        let existingDownloadKeys = Set(await downloads.snapshot().map(\.key))
        let missing = uniqueSummaries
            .filter { existingDownloadKeys.contains($0.key) == false }
            .sorted { $0.key.id < $1.key.id }
        guard missing.isEmpty == false else { return 0 }

        let jobs = missing.map { summary -> DownloadJob in
            var job = DownloadJob(
                key: summary.key,
                title: summary.title,
                japaneseTitle: summary.japaneseTitle,
                tags: summary.tags,
                pages: []
            )
            job.state = .paused
            job.errorMessage = String(localized: "已从画廊同步包加入；开始下载时将获取页面信息。")
            return job
        }
        await downloads.restore(jobs)
        return jobs.count
    }

    private func hydrateSyncedDownload(_ job: DownloadJob) async -> Bool {
        do {
            let detail = try await api.detailPreview(for: job.key, site: site)
            guard detail.pages.isEmpty == false else {
                throw EHError.parsingFailed(String(localized: "画廊没有可下载的页面。"))
            }
            var hydrated = DownloadJob(
                key: job.key,
                title: job.title,
                japaneseTitle: job.japaneseTitle,
                tags: job.tags,
                pages: detail.pages,
                totalPageCount: detail.summary.pageCount,
                label: job.label,
                addedAt: job.addedAt
            )
            hydrated.state = .paused
            await downloads.mergeRestored([hydrated])
            return true
        } catch {
            errorMessage = String(localized: "无法准备《\(job.displayTitle(showJapaneseTitle: readingSettings.showJapaneseTitle))》下载：\(error.localizedDescription)")
            return false
        }
    }

    nonisolated private static func gallerySyncOutcomeMessage(_ result: GallerySyncImportResult) -> String {
        let outcome = result.galleryOutcome
        var parts = [String(localized: "已加入下载列表 \(result.queuedDownloadCount) 项")]
        if outcome.insertedCount > 0 {
            parts.append(String(localized: "新增画廊摘要 \(outcome.insertedCount) 个"))
        }
        if outcome.existingCount > 0 {
            parts.append(String(localized: "本地已有画廊 \(outcome.existingCount) 个"))
        }
        if outcome.duplicateInFileCount > 0 {
            parts.append(String(localized: "文件内重复 \(outcome.duplicateInFileCount) 个"))
        }
        if result.incompleteMetadataCount > 0 {
            parts.append(String(localized: "待联网补全信息 \(result.incompleteMetadataCount) 个"))
        }
        return parts.joined(separator: "，") + "。"
    }

    private func beginMigration(status: String) -> Bool {
        guard !isLoadingDownloads, localDownloadLoadError == nil, !isShuttingDown,
              isMigrating == false, isRestoringDownloads == false else { return false }
        isMigrating = true
        migrationProgress = MigrationProgress(status: status, fraction: 0)
        return true
    }

    private func finishMigration() {
        isMigrating = false
        migrationProgress = nil
    }

    private func setMigrationProgress(
        status: String,
        completed: Int = 0,
        total: Int = 0,
        fraction: Double? = nil,
        estimatedRemainingSeconds: TimeInterval? = nil
    ) {
        migrationProgress = MigrationProgress(
            status: status,
            completed: completed,
            total: total,
            fraction: fraction,
            estimatedRemainingSeconds: estimatedRemainingSeconds
        )
    }

    private func setDownloadRestoreProgress(
        completed: Int,
        total: Int,
        fraction: Double,
        estimatedRemainingSeconds: TimeInterval?
    ) {
        downloadRestoreProgress = MigrationProgress(
            status: downloadRestoreStatus,
            completed: completed,
            total: total,
            fraction: fraction,
            estimatedRemainingSeconds: estimatedRemainingSeconds
        )
    }

    private func pageToken(from url: URL) -> String? {
        let components = url.pathComponents
        guard let index = components.firstIndex(where: { $0.caseInsensitiveCompare("s") == .orderedSame }),
              components.indices.contains(index + 1),
              components[index + 1].isEmpty == false else { return nil }
        return components[index + 1]
    }

    private func imageURL(for image: GalleryPageImage, resolution: ImageResolution) -> URL {
        resolution == .original ? (image.originImageURL ?? image.imageURL) : image.imageURL
    }

    private func matchesFilter(_ gallery: GallerySummary) -> Bool {
        return filterRules.contains { rule in
            rule.isEnabled && GalleryFilterMatcher.isBlocked(gallery, mode: rule.mode, keyword: rule.pattern)
        } == false
    }

    private func appendUniqueGalleries(_ newGalleries: [GallerySummary]) {
        var existingKeys = Set(galleries.map(\.key))
        galleries.append(contentsOf: newGalleries.filter {
            matchesFilter($0) && existingKeys.insert($0.key).inserted
        })
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private struct BackgroundDownloadTaskDescription: Sendable {
    let profileID: String?
    let key: GalleryKey
    let pageIndex: Int
}

private func makeDownloadTaskDescription(profileID: String?, key: GalleryKey, pageIndex: Int) -> String {
    if let profileID {
        return "\(profileID)|\(key.gid)|\(key.token)|\(pageIndex)"
    }
    return "\(key.gid)|\(key.token)|\(pageIndex)"
}

private func parseDownloadTaskDescription(_ description: String) -> BackgroundDownloadTaskDescription? {
    let pieces = description.split(separator: "|", omittingEmptySubsequences: false)
    let offset: Int
    let profileID: String?
    switch pieces.count {
    case 3:
        offset = 0
        profileID = nil
    case 4:
        offset = 1
        profileID = String(pieces[0])
    default:
        return nil
    }
    guard let gid = Int64(pieces[offset]),
          let pageIndex = Int(pieces[offset + 2]),
          pieces[offset + 1].isEmpty == false else { return nil }
    return BackgroundDownloadTaskDescription(
        profileID: profileID,
        key: GalleryKey(gid: gid, token: String(pieces[offset + 1])),
        pageIndex: pageIndex
    )
}
