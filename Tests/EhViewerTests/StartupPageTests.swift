import Foundation
import Testing
import EHDomain
import EHPersistence
import EHDownloads
@testable import EhViewerPreview

@MainActor
struct StartupPageTests {
    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "StartupPageTests-\(UUID().uuidString)"))
    }

    @Test("启动页未设置或无效时保留本地默认值")
    func defaultAndInvalidPreference() throws {
        let defaults = try defaults()
        #expect(StartupPage.load(from: defaults) == .local)
        defaults.set("unsupported", forKey: "startupPage")
        #expect(StartupPage.load(from: defaults) == .local)
        #expect(StartupPage.allCases.map(\.route) == [.browse, .local, .history, .favorites, .settings])
    }

    @Test("每种启动页面都恢复本地数据，加载期间可以切换页面", arguments: StartupPage.allCases)
    func startupPageLoadsIndependently(page: StartupPage) async throws {
        let defaults = try defaults()
        defaults.set(page.rawValue, forKey: "startupPage")
        let gate = AsyncStream<Void>.makeStream()
        let started = AsyncStream<Void>.makeStream()
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            beforeLocalRestore: {
                started.continuation.yield(())
                for await _ in gate.stream { break }
            }, defaults: defaults
        )
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
        #expect(model.selectedRoute == page.route)
        #expect(model.isLoadingDownloads)
        model.selectedRoute = .settings
        #expect(model.selectedRoute == .settings)
        await model.loadLibrary(mode: .history)
        await model.loadLibrary(mode: .favorites)
        #expect(model.isLoadingDownloads)
        let first = Task { await model.waitUntilReady() }
        let second = Task { await model.waitUntilReady() }
        await Task.yield()
        gate.continuation.yield(())
        gate.continuation.finish()
        await first.value
        await second.value
        #expect(!model.isLoadingDownloads)
        #expect(model.localDownloadLoadError == nil)
        #expect(model.selectedRoute == .settings)
        #expect(await model.downloads.snapshot().isEmpty)
        await model.shutdown()
    }

    @Test("修改启动偏好立即保存，当前页面与其他空间保持独立")
    func preferencePersistenceAndIsolation() async throws {
        let firstDefaults = try defaults()
        let secondDefaults = try defaults()
        let model = AppModel(container: try ModelContainerFactory.make(inMemory: true), defaults: firstDefaults)
        model.selectedRoute = .settings
        model.startupPage = .history
        #expect(StartupPage.load(from: firstDefaults) == .history)
        #expect(StartupPage.load(from: secondDefaults) == .local)
        #expect(model.selectedRoute == .settings)
        await model.shutdown()
    }

    @Test("合并启动基线不取消恢复期间新启动的下载")
    func baselineMergeKeepsRunningDownload() async throws {
        let started = AsyncStream<Void>.makeStream()
        let gate = AsyncStream<Void>.makeStream()
        let completed = AsyncStream<Bool>.makeStream()
        let coordinator = DownloadCoordinator(pageLoader: { _ in
            started.continuation.yield(())
            for await _ in gate.stream { break }
            completed.continuation.yield(Task.isCancelled)
            return Data([1])
        })
        let key = GalleryKey(gid: 98, token: "new-download")
        let page = GalleryPageDescriptor(galleryKey: key, index: 0, pageURL: URL(string: "https://example.com/page")!)
        await coordinator.enqueue(key: key, title: "Fresh", pages: [page])
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
        await coordinator.loadPersisted([])
        #expect(await coordinator.job(for: key)?.state == .running)
        gate.continuation.finish()
        var completionIterator = completed.stream.makeAsyncIterator()
        #expect(await completionIterator.next() == false)
        await coordinator.stopAll()
    }

    private enum LoadFailure: Error { case unavailable }

    private actor FailingBaselineLoader {
        private var attempts = 0
        func load() throws -> [PersistedDownload] {
            attempts += 1
            if attempts == 1 { throw LoadFailure.unavailable }
            return []
        }
    }

    private struct Authenticator: ProfileAuthenticating {
        func authenticate(reason: String) async throws -> Bool { true }
    }

    private struct RegistryFixture: Encodable {
        let formatVersion = 1
        let profiles: [ProfileDescriptor]
        let lastUsedProfileID: UUID
    }

    @Test("空间激活不等待本地加载，切换时关闭旧空间任务", .timeLimit(.minutes(1)))
    func activationDoesNotWaitForLocalRestore() async throws {
        let gate = AsyncStream<Void>.makeStream()
        let started = AsyncStream<Void>.makeStream()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let profile = ProfileDescriptor(name: "First", usesLegacyStorage: false)
        let registry = RegistryFixture(profiles: [profile], lastUsedProfileID: profile.id)
        try JSONEncoder().encode(registry).write(to: root.appendingPathComponent("registry.json"))
        let session = ProfileSession(
            profilesRoot: root,
            authenticator: Authenticator(),
            beforeLocalRestore: {
                started.continuation.yield(())
                for await _ in gate.stream { break }
            }
        )
        await session.prepare()
        let oldModel = try #require(session.runtime?.model)
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
        #expect(!session.isActivatingProfile)
        #expect(oldModel.isLoadingDownloads)
        oldModel.startupPage = .history
        let oldID = try #require(session.runtime?.descriptor.id)
        await session.createProfile(named: "Second")
        #expect(session.runtime?.descriptor.id != oldID)
        #expect(oldModel.isReady)
        #expect(session.runtime?.model.startupPage == .local)
        gate.continuation.finish()
        await session.switchProfile(to: oldID)
        #expect(session.runtime?.model.selectedRoute == .history)
        await session.runtime?.model.shutdown()
    }

    @Test("大批量下载转换在后台执行，主 actor 可继续操作")
    func largeBaselineConversionRunsOffMainActor() async throws {
        let persisted = (0..<2_000).map { index in
            PersistedDownload(key: GalleryKey(gid: index + 1, token: "large"), title: "Gallery", pages: [],
                              completedPageIndexes: [], stateRaw: "paused", errorMessage: nil)
        }
        let started = AsyncStream<Void>.makeStream()
        let gate = AsyncStream<Void>.makeStream()
        let conversion = Task {
            await AppModel.downloadBaselines(persisted, onStart: {
                started.continuation.yield(())
                for await _ in gate.stream { break }
            })
        }
        var iterator = started.stream.makeAsyncIterator()
        _ = try #require(await iterator.next())
        // This action runs on MainActor while the worker is still suspended.
        let model = AppModel(container: try ModelContainerFactory.make(inMemory: true), defaults: try defaults())
        model.selectedRoute = .favorites
        #expect(model.selectedRoute == .favorites)
        gate.continuation.finish()
        #expect(await conversion.value.count == persisted.count)
        await model.shutdown()
    }

    @Test("本地恢复失败显示错误，重试只恢复本地数据")
    func failedLoadCanRetry() async throws {
        let loader = FailingBaselineLoader()
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            downloadBaselineLoader: { try await loader.load() }, defaults: try defaults()
        )
        await model.waitUntilReady()
        #expect(!model.isLoadingDownloads)
        #expect(model.localDownloadLoadError != nil)
        model.selectedRoute = .browse
        model.retryLocalDownloadLoad()
        // Retry must synchronously advertise loading before another action can run.
        #expect(model.isLoadingDownloads)
        await model.waitForLocalRestore()
        #expect(model.localDownloadLoadError == nil)
        #expect(model.selectedRoute == .browse)
        await model.shutdown()
    }

    @Test("关闭空间取消未完成加载并释放等待者")
    func shutdownReleasesWaiters() async throws {
        let gate = AsyncStream<Void>.makeStream()
        let started = AsyncStream<Void>.makeStream()
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            beforeLocalRestore: {
                started.continuation.yield(())
                for await _ in gate.stream { break }
            }, defaults: try defaults()
        )
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
        let waiter = Task { await model.waitUntilReady() }
        await Task.yield()
        await model.shutdown()
        await waiter.value
        gate.continuation.finish()
        #expect(await model.downloads.snapshot().isEmpty)
    }
}
