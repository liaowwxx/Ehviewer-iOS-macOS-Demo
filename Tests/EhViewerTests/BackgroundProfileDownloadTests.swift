import Foundation
import Testing
import EHDomain
import EHPersistence
@testable import EHDownloads
@testable import EhViewerPreview

@MainActor
struct BackgroundProfileDownloadTests {
    @Test("Background launch restores the owning profile and publishes files without constructing its UI", .timeLimit(.minutes(1)))
    func headlessProfileRestoration() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EHHeadless-\(UUID().uuidString)")
        let profile = ProfileDescriptor(name: "Background")
        let layout = ProfileStorageLayout.isolated(for: profile.id, profilesRoot: root)
        try FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        let profileObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile))
        try JSONSerialization.data(withJSONObject: ["formatVersion": 1, "profiles": [profileObject], "lastUsedProfileID": profile.id.uuidString]).write(to: root.appendingPathComponent("registry.json"))
        let store = PersistenceStore(modelContainer: try ModelContainerFactory.make(storeURL: layout.storeURL))
        let key = GalleryKey(gid: 913, token: "headless")
        let page = GalleryPageDescriptor(galleryKey: key, index: 0, pageURL: URL(string: "https://e-hentai.org/s/page/913-1")!)
        try await store.upsertDownload(key: key, title: "Headless", pages: [page], totalPageCount: 2, completedPageIndexes: [], stateRaw: "running", errorMessage: nil)
        let ticket = DownloadTransferTicket(batchID: UUID(), page: page, image: GalleryPageImage(galleryKey: key, index: 0, imageURL: URL(string: "https://example.invalid/image")!), taskIdentifier: 1)
        let queueRoot = layout.downloadsRoot.appendingPathComponent(".background-transfers")
        let staging = queueRoot.appendingPathComponent("Staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let ticketObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ticket))
        let batch: [String: Any] = ["id": ticket.batchID.uuidString, "key": try JSONSerialization.jsonObject(with: JSONEncoder().encode(key)), "active": true, "entries": [ticket.id.uuidString: ["ticket": ticketObject, "completed": false]]]
        try JSONSerialization.data(withJSONObject: ["version": 1, "batches": [key.id: batch]]).write(to: queueRoot.appendingPathComponent("queue.json"))
        let receipt = BackgroundDownloadSession.Receipt(id: UUID(), taskDescription: ticket.id.uuidString, fileName: "image.download", statusCode: 200, accessDenied: false)
        let image = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        try image.write(to: staging.appendingPathComponent(receipt.fileName))
        try JSONEncoder().encode(receipt).write(to: staging.appendingPathComponent(receipt.id.uuidString + ".json"))

        try await ProfileDownloadResources.reconnect(identifier: "com.liao.ehviewer.background-downloads.\(profile.id.uuidString)", profilesRoot: root)
        let resources = try await ProfileDownloadResources.get(descriptor: profile, profilesRoot: root)
        let reused = try await ProfileDownloadResources.get(descriptor: profile, profilesRoot: root)
        #expect(resources === reused)
        #expect(try await resources.store.downloadJobs().first?.completedPageIndexes == [0])
        let final = await resources.files.finalURL(for: key, pageIndex: 0)
        #expect(try Data(contentsOf: final) == image)
        await resources.session.cancelAll()
        ProfileDownloadResources.release(id: profile.id, profilesRoot: root)
    }
}
