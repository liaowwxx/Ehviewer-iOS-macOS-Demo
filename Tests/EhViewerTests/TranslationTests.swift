import CryptoKit
import Foundation
import Testing
import EHDomain
import EHDownloads
import EHPersistence
import Network
@testable import EHDeviceSync
@testable import EhViewerPreview

struct TranslationTests {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6qVQAAAAASUVORK5CYII=")!

    private func workspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("eh-translation-test-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func manifest(id: UUID = UUID(), count: Int = 2) -> GalleryTranslationManifest {
        let sha = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        return GalleryTranslationManifest(versionID: id, gallery: .init(key: GalleryKey(gid: 123, token: "abc"), title: "Test"),
                                          createdAt: 100, targetLanguage: "简体中文", presetFingerprint: String(repeating: "a", count: 64),
                                          pages: (0..<count).map { .init(index: $0, fileName: "page-\($0).png", byteCount: Int64(png.count), sha256: sha, sourceSHA256: sha) })
    }

    private func sources(_ manifest: GalleryTranslationManifest, in directory: URL) throws {
        for page in manifest.pages { try png.write(to: directory.appendingPathComponent(page.fileName)) }
    }

    @Test func completeImportSurvivesRestartAndIsIdempotent() async throws {
        let input = try workspace()
        let root = try workspace()
        let version = manifest()
        try sources(version, in: input)
        let store = TranslationFileStore(root: root)
        try await store.importVersion(version, pagesDirectory: input)
        try await store.importVersion(version, pagesDirectory: input)
        #expect(try await store.manifests(for: version.gallery.key).count == 1)
        let restored = TranslationFileStore(root: root)
        #expect(try await restored.data(for: version.gallery.key, versionID: version.id, index: 1) == png)
    }

    @Test func incompleteImportNeverReplacesReadableVersion() async throws {
        let input = try workspace()
        let store = TranslationFileStore(root: try workspace())
        let original = manifest(count: 1)
        try sources(original, in: input)
        try await store.importVersion(original, pagesDirectory: input)
        let incomplete = manifest(count: 2)
        await #expect(throws: (any Error).self) { try await store.importVersion(incomplete, pagesDirectory: input) }
        #expect(try await store.allManifests().map(\.id) == [original.id])
        #expect(try await store.data(for: original.gallery.key, versionID: original.id, index: 0) == png)
    }

    @Test func sameVersionWithDifferentContentIsRejected() async throws {
        let input = try workspace()
        let store = TranslationFileStore(root: try workspace())
        let version = manifest(count: 1)
        try sources(version, in: input)
        try await store.importVersion(version, pagesDirectory: input)
        let conflicting = GalleryTranslationManifest(versionID: version.id, gallery: version.gallery, createdAt: 101,
                                                     targetLanguage: version.targetLanguage, presetFingerprint: version.presetFingerprint, pages: version.pages)
        await #expect(throws: (any Error).self) { try await store.importVersion(conflicting, pagesDirectory: input) }
        #expect(try await store.allManifests() == [version])
    }

    @Test func corruptPageIsRejectedBeforePublicationAndOnRead() async throws {
        let input = try workspace()
        let store = TranslationFileStore(root: try workspace())
        let version = manifest(count: 1)
        try Data("corrupt".utf8).write(to: input.appendingPathComponent(version.pages[0].fileName))
        await #expect(throws: (any Error).self) { try await store.importVersion(version, pagesDirectory: input) }
        #expect(try await store.allManifests().isEmpty)
        try sources(version, in: input)
        try await store.importVersion(version, pagesDirectory: input)
        let file = try await store.pageURL(for: version, index: 0)
        try Data("changed".utf8).write(to: file)
        await #expect(throws: (any Error).self) { try await store.data(for: version.gallery.key, versionID: version.id, index: 0) }
    }

    @Test func interruptedTransferRequestsOnlyMissingPagesAfterRestart() async throws {
        let root = try workspace()
        let store = TranslationFileStore(root: root)
        let version = manifest()
        let receiver = try await store.beginIncomingPage(version, index: 0)
        try await receiver.append(png)
        try await receiver.finish()
        try await store.finishIncomingPage(version, index: 0)
        #expect(try await store.allManifests().isEmpty)
        let restored = TranslationFileStore(root: root)
        let local = try await restored.syncEntries()
        let remote = try DeviceSyncTranslationEntry(manifest: version, availablePages: [0, 1])
        let missing = DeviceSyncTranslationReconciler.missing(local: local, remote: [remote])
        #expect(missing.first?.availablePages == [1])
        let next = try await restored.beginIncomingPage(version, index: 1)
        try await next.append(png)
        try await next.finish()
        try await restored.finishIncomingPage(version, index: 1)
        #expect(try await restored.allManifests() == [version])
        #expect(DeviceSyncTranslationReconciler.missing(local: try await restored.syncEntries(), remote: [remote]).isEmpty)
    }

    @Test func partialPageNeverBecomesVisible() async throws {
        let store = TranslationFileStore(root: try workspace())
        let version = manifest(count: 1)
        let receiver = try await store.beginIncomingPage(version, index: 0)
        try await receiver.append(Data(png.prefix(10)))
        await #expect(throws: (any Error).self) { try await receiver.finish() }
        #expect(try await store.syncEntries().first?.availablePages == [])
        #expect(try await store.allManifests().isEmpty)
    }

    @Test func archiveDoesNotRestoreFromStagingAfterRestart() async throws {
        let root = try workspace()
        let store = TranslationFileStore(root: root)
        let version = manifest(count: 1)
        let receiver = try await store.beginIncomingPage(version, index: 0)
        try await receiver.append(png)
        try await receiver.finish()
        try await store.finishIncomingPage(version, index: 0)
        try await store.archiveVersion(for: version.gallery.key, versionID: version.id)
        let restored = TranslationFileStore(root: root)
        #expect(try await restored.allManifests().isEmpty)
        #expect(try await restored.syncEntries().isEmpty)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("deleted_file/info.md").path))
    }

    @Test func syncRejectsConflictAndKeepsDifferentVersions() throws {
        let version = manifest()
        let same = try DeviceSyncTranslationEntry(manifest: version, availablePages: [0, 1])
        let other = try DeviceSyncTranslationEntry(manifest: manifest(), availablePages: [0, 1])
        try DeviceSyncTranslationReconciler.validate(local: [same], remote: [other])
        #expect(DeviceSyncTranslationReconciler.missing(local: [same], remote: [other]) == [other])
        let conflicting = GalleryTranslationManifest(versionID: version.id, gallery: version.gallery, createdAt: 101,
                                                     targetLanguage: version.targetLanguage, presetFingerprint: version.presetFingerprint, pages: version.pages)
        let entry = try DeviceSyncTranslationEntry(manifest: conflicting, availablePages: [0])
        #expect(throws: (any Error).self) { try DeviceSyncTranslationReconciler.validate(local: [same], remote: [entry]) }
    }

    @Test func unsafeFileNamesAreRejected() throws {
        let version = manifest(count: 1)
        let page = version.pages[0]
        let bad = GalleryTranslationManifest(versionID: version.id, gallery: version.gallery, createdAt: 100,
                                             targetLanguage: version.targetLanguage, presetFingerprint: version.presetFingerprint,
                                             pages: [.init(index: 0, fileName: "../outside.png", byteCount: page.byteCount, sha256: page.sha256, sourceSHA256: page.sourceSHA256)])
        #expect(throws: (any Error).self) { try bad.validate() }
    }

    @Test("Translation pages traverse the existing framed sync transport", .timeLimit(.minutes(1)))
    @MainActor
    func translationWireTransfer() async throws {
        let senderFiles = TranslationFileStore(root: try workspace())
        let receiverFiles = TranslationFileStore(root: try workspace())
        let version = manifest()
        let input = try workspace()
        try sources(version, in: input)
        try await senderFiles.importVersion(version, pagesDirectory: input)
        let sender = DeviceSyncCoordinator(persistence: PersistenceStore(modelContainer: try ModelContainerFactory.make(inMemory: true)),
                                            files: DownloadFileStore(root: try workspace()), translations: senderFiles,
                                            index: DeviceSyncIndexStore(root: try workspace()), transactionRoot: try workspace())
        let receiver = DeviceSyncCoordinator(persistence: PersistenceStore(modelContainer: try ModelContainerFactory.make(inMemory: true)),
                                              files: DownloadFileStore(root: try workspace()), translations: receiverFiles,
                                              index: DeviceSyncIndexStore(root: try workspace()), transactionRoot: try workspace())
        let listener = try NWListener(using: .tcp, on: .any)
        let ready = DeviceSyncContinuationGate<NWEndpoint.Port>()
        let accepted = DeviceSyncContinuationGate<NWConnection>()
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let port = listener.port { ready.succeed(port) }
            case .failed(let error): ready.fail(error); accepted.fail(error)
            default: break
            }
        }
        listener.newConnectionHandler = { accepted.succeed($0) }
        listener.start(queue: DispatchQueue(label: "EhViewerTests.Translation.Listener"))
        defer { listener.cancel() }
        let port = try await withCheckedThrowingContinuation { ready.install($0) }
        let client = DeviceSyncWireConnection(connection: NWConnection(host: "127.0.0.1", port: port, using: .tcp))
        async let clientStart: Void = client.start(timeout: .seconds(5))
        let server = DeviceSyncWireConnection(connection: try await withCheckedThrowingContinuation { accepted.install($0) })
        try await server.start(timeout: .seconds(5))
        try await clientStart
        defer { client.cancel(); server.cancel() }
        let entries = try await senderFiles.syncEntries()
        async let receive: Void = {
            let data = try await server.receivePayload(expected: .translationBegin)
            let entry = try JSONDecoder().decode(DeviceSyncTranslationEntry.self, from: data)
            try await receiver.receiveTranslation(entry, wire: server)
        }()
        try await sender.sendTranslations(entries, wire: client)
        _ = try await client.flush()
        try await receive
        #expect(try await receiverFiles.allManifests() == [version])
        #expect(try await receiverFiles.data(for: version.gallery.key, versionID: version.id, index: 1) == png)
        #expect(DeviceSyncTranslationReconciler.missing(local: try await receiverFiles.syncEntries(), remote: entries).isEmpty)
        #expect(try Data(contentsOf: input.appendingPathComponent(version.pages[0].fileName)) == png)
    }

    @Test @MainActor func editionSelectionIsRestoredAndProfileScoped() async throws {
        let input = try workspace()
        let files = TranslationFileStore(root: try workspace())
        let version = manifest(count: 1)
        try sources(version, in: input)
        try await files.importVersion(version, pagesDirectory: input)
        let defaults = try #require(UserDefaults(suiteName: "translation-test-\(UUID())"))
        let library = AppTranslationLibrary(files: files, defaults: defaults)
        await library.refresh()
        library.select(.translated(versionID: version.id), for: version.gallery.key)
        let restored = AppTranslationLibrary(files: files, defaults: defaults)
        await restored.refresh()
        #expect(restored.edition(for: version.gallery.key) == .translated(versionID: version.id))
        let other = AppTranslationLibrary(files: files, defaults: try #require(UserDefaults(suiteName: "translation-other-\(UUID())")))
        await other.refresh()
        #expect(other.edition(for: version.gallery.key) == .original)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["EH_COMPANION_RESULT"] != nil))
    func importRealCompanionResult() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["EH_COMPANION_RESULT"])
        let directory = URL(filePath: path)
        let manifest = try JSONDecoder().decode(GalleryTranslationManifest.self, from: Data(contentsOf: directory.appendingPathComponent("result.json")))
        let root = try workspace()
        let store = TranslationFileStore(root: root)
        try await store.importVersion(manifest, pagesDirectory: directory.appendingPathComponent("project/result"))
        let restored = TranslationFileStore(root: root)
        for page in manifest.pages {
            let data = try await restored.data(for: manifest.gallery.key, versionID: manifest.id, index: page.index)
            #expect(Int64(data.count) == page.byteCount)
        }
    }

#if os(macOS)
    @Test(.enabled(if: ProcessInfo.processInfo.environment["EH_COMPANION_TEST"] == "1"), .timeLimit(.minutes(1)))
    @MainActor
    func nativeClientAutoConnectsReconnectsUploadsRestartsImportsAndAcknowledges() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["EH_COMPANION_SOURCE"])
        let data = try Data(contentsOf: URL(filePath: path))
        let downloads = DownloadFileStore(root: try workspace(), minimumFreeBytes: 0)
        let root = try workspace()
        let defaults = try #require(UserDefaults(suiteName: "translation-client-\(UUID())"))
        let library = AppTranslationLibrary(files: TranslationFileStore(root: try workspace()), defaults: defaults)
        let key = GalleryKey(gid: 999, token: "companion-client-test")
        var job = DownloadJob(key: key, title: "Client test", pages: (0..<2).map {
            GalleryPageDescriptor(galleryKey: key, index: $0, pageURL: URL(string: "https://example.com/\($0).jpg")!)
        })
        job.state = .completed
        job.completedPageIndexes = [0, 1]
        for index in 0..<2 { _ = try await downloads.write(data, for: key, pageIndex: index) }
        let first = LocalTranslationClient(root: root, library: library)
        defer { first.stop() }
        let control = URL(filePath: path).deletingLastPathComponent()
        let deadline = ContinuousClock.now + .seconds(50)
        func waitUntil(_ condition: () -> Bool) async throws {
            while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
            #expect(condition())
        }
        // With no pending jobs, keep discovering silently until the service opens.
        first.start()
        try await Task.sleep(for: .milliseconds(250))
        #expect(!first.isConnected)
        #expect(first.error == nil)
        try Data().write(to: control.appendingPathComponent("start-server"))
        try await waitUntil { first.isConnected }
        #expect(first.error == nil)
        // Quit/relaunch the service: the in-memory token changes, with no pairing.
        try Data().write(to: control.appendingPathComponent("stop-server"))
        try await waitUntil { !first.isConnected }
        #expect(first.error == nil)
        try Data().write(to: control.appendingPathComponent("restart-server"))
        try await waitUntil { first.isConnected }
        #expect(first.error == nil)
        first.submit(job: job, downloads: downloads)
        while first.isSubmitting && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        #expect(first.error == nil)
        first.stop()
        let restored = LocalTranslationClient(root: root, library: library)
        restored.start()
        defer { restored.stop() }
        try await waitUntil { restored.isConnected }
        while (library.versions[key]?.isEmpty ?? true) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        let version = try #require(library.versions[key]?.first)
        #expect(version.pages.count == 2)
        #expect(try await library.files.data(for: key, versionID: version.id, index: 1).isEmpty == false)
        #expect(try await downloads.data(for: key, pageIndex: 0) == data)
        // The service exits only after observing the durable import's ACK.
        try await Task.sleep(for: .milliseconds(500))
    }
#endif
}
