import Foundation
import Testing
import EHDomain

struct DeviceSyncManifestTests {
    @Test("Device sync reconciles gallery and partial page unions")
    func reconcilesGalleryAndPageUnion() throws {
        let shared = GalleryKey(gid: 1, token: "shared")
        let localOnly = GalleryKey(gid: 2, token: "local")
        let remoteOnly = GalleryKey(gid: 3, token: "remote")
        let local = try manifest(
            records: [
                record(for: shared, title: "same"),
                record(for: localOnly, title: "local")
            ],
            pages: [shared: [0, 1], localOnly: [0]]
        )
        let remote = try manifest(
            records: [
                record(for: shared, title: "same"),
                record(for: remoteOnly, title: "remote")
            ],
            pages: [shared: [1, 2], remoteOnly: [0, 1]]
        )

        let plan = DeviceSyncReconciler.plan(local: local, remote: remote)

        #expect(plan.receiveGalleries == [remoteOnly])
        #expect(plan.sendGalleries == [localOnly])
        #expect(plan.receivePages.map(\.id) == ["1-shared-2", "3-remote-0", "3-remote-1"])
        #expect(plan.sendPages.map(\.id) == ["1-shared-0", "2-local-0"])
        #expect(plan.receiveBytes == 6)
        #expect(plan.sendBytes == 2)
    }

    @Test("Identical pages and metadata produce an empty transfer plan")
    func identicalDataIsNotTransferred() throws {
        let key = GalleryKey(gid: 4, token: "duplicate")
        let record = record(for: key, title: "same")
        let first = try manifest(records: [record], pages: [key: [0, 1]])
        let second = try manifest(records: [record], pages: [key: [0, 1]])
        let plan = DeviceSyncReconciler.plan(local: first, remote: second)

        #expect(plan.receiveGalleries.isEmpty)
        #expect(plan.receiveMetadata.isEmpty)
        #expect(plan.receivePages.isEmpty)
        #expect(plan.sendGalleries.isEmpty)
        #expect(plan.sendMetadata.isEmpty)
        #expect(plan.sendPages.isEmpty)
    }

    @Test("A more complete remote metadata digest is selected")
    func moreCompleteMetadataIsSelected() throws {
        let key = GalleryKey(gid: 5, token: "metadata")
        let date = Date(timeIntervalSince1970: 1_000)
        let incomplete = try GalleryTransferRecord(
            stable: StableGalleryMetadataSnapshot(
                key: key,
                sourceSite: .eHentai,
                title: "title",
                capturedAt: date,
                completeness: GalleryMetadataCompleteness(title: .loadedWithValue)
            ),
            exportedAt: date
        )
        let complete = try GalleryTransferRecord(
            stable: StableGalleryMetadataSnapshot(
                key: key,
                sourceSite: .eHentai,
                title: "title",
                tags: ["artist:one"],
                capturedAt: date,
                completeness: GalleryMetadataCompleteness(
                    title: .loadedWithValue,
                    authors: .loadedEmpty,
                    tags: .loadedWithValue
                )
            ),
            exportedAt: date
        )

        let local = try manifest(records: [incomplete], pages: [key: []])
        let remote = try manifest(records: [complete], pages: [key: []])
        let plan = DeviceSyncReconciler.plan(local: local, remote: remote)

        #expect(plan.receiveMetadata == [key])
        #expect(plan.sendMetadata.isEmpty)
    }

    @Test("Equal timestamp metadata uses a deterministic fingerprint order")
    func equalTimestampMetadataConvergesDeterministically() throws {
        let key = GalleryKey(gid: 6, token: "tie")
        let date = Date(timeIntervalSince1970: 2_000)
        let first = record(for: key, title: "alpha", date: date)
        let second = record(for: key, title: "beta", date: date)
        let firstManifest = try manifest(records: [first], pages: [key: []])
        let secondManifest = try manifest(records: [second], pages: [key: []])

        let forward = DeviceSyncReconciler.plan(local: firstManifest, remote: secondManifest)
        let reverse = DeviceSyncReconciler.plan(local: secondManifest, remote: firstManifest)
        let firstFingerprint = firstManifest.galleries[0].metadata.stableFingerprint
        let secondFingerprint = secondManifest.galleries[0].metadata.stableFingerprint

        if secondFingerprint.lexicographicallyPrecedes(firstFingerprint) {
            #expect(forward.receiveMetadata.isEmpty)
            #expect(reverse.receiveMetadata == [key])
        } else {
            #expect(forward.receiveMetadata == [key])
            #expect(reverse.receiveMetadata.isEmpty)
        }
    }

    @Test("Manifest rejects duplicate, invalid and orphan entries")
    func rejectsInvalidManifestInput() throws {
        let key = GalleryKey(gid: 7, token: "invalid")
        let metadata = try DeviceSyncMetadataDigest(
            stableCapturedAt: Date(),
            stableCompleteness: .init(),
            stableFingerprint: Data(repeating: 0, count: 32),
            estimatedTransferBytes: 1
        )
        let page = try DeviceSyncPageEntry(pageIndex: 0, byteCount: 1)
        let entry = try DeviceSyncGalleryEntry(key: key, pages: [page], metadata: metadata)

        #expect(throws: DeviceSyncManifestError.duplicateGalleryKey) {
            try DeviceSyncManifest(galleries: [entry, entry])
        }
        #expect(throws: DeviceSyncManifestError.invalidPageIndex) {
            try DeviceSyncPageEntry(pageIndex: -1, byteCount: 1)
        }
        #expect(throws: DeviceSyncManifestError.invalidGalleryKey) {
            try DeviceSyncGalleryEntry(
                key: GalleryKey(gid: 0, token: "bad"),
                pages: [],
                metadata: metadata
            )
        }
        #expect(throws: DeviceSyncManifestError.orphanPageEntries) {
            try DeviceSyncManifest(records: [record(for: key, title: "record")], pagesByGallery: [
                GalleryKey(gid: 8, token: "orphan"): []
            ])
        }
    }

    private func manifest(
        records: [GalleryTransferRecord],
        pages: [GalleryKey: [Int]]
    ) throws -> DeviceSyncManifest {
        let pageEntries = try pages.mapValues { indexes in
            try indexes.map { try DeviceSyncPageEntry(pageIndex: $0, byteCount: Int64($0 + 1)) }
        }
        return try DeviceSyncManifest(records: records, pagesByGallery: pageEntries)
    }

    private func record(
        for key: GalleryKey,
        title: String,
        date: Date = Date(timeIntervalSince1970: 100)
    ) -> GalleryTransferRecord {
        try! GalleryTransferRecord(
            stable: StableGalleryMetadataSnapshot(
                key: key,
                sourceSite: .eHentai,
                title: title,
                capturedAt: date
            ),
            exportedAt: date
        )
    }
}
