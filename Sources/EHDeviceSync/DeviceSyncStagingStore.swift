/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai gallery browsing client
 * Copyright (C) 2026 EhViewer Contributors
 */

import Foundation
import EHDomain
import EHPersistence

struct DeviceSyncStagingPage: Codable, Hashable, Sendable {
    let pageIndex: Int
    let byteCount: Int64
}

struct DeviceSyncStagingGalleryPlan: Codable, Hashable, Sendable {
    let key: GalleryKey
    let pages: [DeviceSyncStagingPage]
    let requiresMetadata: Bool
}

struct DeviceSyncStagingPlan: Codable, Sendable {
    let id: UUID
    let galleries: [DeviceSyncStagingGalleryPlan]
}

struct DeviceSyncStagedGallery: Sendable {
    let key: GalleryKey
    let record: GalleryTransferRecord?
    let pages: [DeviceSyncStagingPage]
}

actor DeviceSyncStagingStore {
    private struct Journal: Codable, Sendable {
        let plan: DeviceSyncStagingPlan
        var startedKeys: Set<GalleryKey>
        var completedKeys: Set<GalleryKey>
        var resolvedKeys: Set<GalleryKey>

        private enum CodingKeys: String, CodingKey {
            case plan
            case startedKeys
            case completedKeys
            case resolvedKeys
        }

        init(
            plan: DeviceSyncStagingPlan,
            startedKeys: Set<GalleryKey> = [],
            completedKeys: Set<GalleryKey> = [],
            resolvedKeys: Set<GalleryKey> = []
        ) {
            self.plan = plan
            self.startedKeys = startedKeys
            self.completedKeys = completedKeys
            self.resolvedKeys = resolvedKeys
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            plan = try container.decode(DeviceSyncStagingPlan.self, forKey: .plan)
            completedKeys = try container.decode(Set<GalleryKey>.self, forKey: .completedKeys)
            resolvedKeys = try container.decode(Set<GalleryKey>.self, forKey: .resolvedKeys)
            // Sessions created before startedKeys was introduced only know
            // about completed galleries. Treat those as the conservative set
            // of started galleries; untracked partial files are removed with
            // the session directory during recovery.
            startedKeys = try container.decodeIfPresent(Set<GalleryKey>.self, forKey: .startedKeys)
                ?? completedKeys
        }
    }

    private struct OpenPage {
        let expectedByteCount: Int64
        let url: URL
        let handle: FileHandle
        var receivedByteCount: Int64
    }

    private let root: URL
    private var journals: [UUID: Journal] = [:]
    private var openPages: [UUID: OpenPage] = [:]

    init(root: URL) {
        self.root = root.appendingPathComponent("Sessions", isDirectory: true)
    }

    func create(plan galleries: [DeviceSyncStagingGalleryPlan]) throws -> UUID {
        let id = UUID()
        let plan = DeviceSyncStagingPlan(id: id, galleries: galleries)
        let journal = Journal(plan: plan)
        try FileManager.default.createDirectory(at: sessionURL(id), withIntermediateDirectories: true)
        journals[id] = journal
        try persist(journal)
        return id
    }

    func storeMetadata(_ data: Data, for key: GalleryKey, sessionID: UUID) throws {
        guard let gallery = try galleryPlan(key, sessionID: sessionID), gallery.requiresMetadata else {
            throw DeviceSyncError.transferNotPlanned
        }
        try markStarted(key, sessionID: sessionID)
        try FileManager.default.createDirectory(at: galleryURL(key, sessionID: sessionID), withIntermediateDirectories: true)
        try data.write(to: metadataURL(key, sessionID: sessionID), options: .atomic)
    }

    func beginPage(
        for key: GalleryKey,
        pageIndex: Int,
        byteCount: Int64,
        sessionID: UUID
    ) throws -> UUID {
        guard let gallery = try galleryPlan(key, sessionID: sessionID),
              gallery.pages.contains(where: { $0.pageIndex == pageIndex && $0.byteCount == byteCount }) else {
            throw DeviceSyncError.transferNotPlanned
        }
        try markStarted(key, sessionID: sessionID)
        let directory = galleryURL(key, sessionID: sessionID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = pageURL(key, pageIndex: pageIndex, sessionID: sessionID)
        try? FileManager.default.removeItem(at: url)
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw DeviceSyncError.network("无法创建设备同步暂存文件。")
        }
        let id = UUID()
        openPages[id] = OpenPage(
            expectedByteCount: byteCount,
            url: url,
            handle: try FileHandle(forWritingTo: url),
            receivedByteCount: 0
        )
        return id
    }

    func append(_ data: Data, to id: UUID) throws {
        guard var page = openPages[id] else { throw DeviceSyncError.transferNotPlanned }
        guard page.receivedByteCount + Int64(data.count) <= page.expectedByteCount else {
            throw DeviceSyncError.transferNotPlanned
        }
        try page.handle.write(contentsOf: data)
        page.receivedByteCount += Int64(data.count)
        openPages[id] = page
    }

    func finishPage(_ id: UUID) throws {
        guard let page = openPages.removeValue(forKey: id) else {
            throw DeviceSyncError.transferNotPlanned
        }
        try page.handle.close()
        guard page.receivedByteCount == page.expectedByteCount else {
            throw DeviceSyncError.transferNotPlanned
        }
    }

    func abandonPage(_ id: UUID) {
        guard let page = openPages.removeValue(forKey: id) else { return }
        try? page.handle.close()
    }

    func finishGallery(_ key: GalleryKey, sessionID: UUID) throws {
        guard var journal = try load(sessionID),
              let gallery = journal.plan.galleries.first(where: { $0.key == key }),
              gallery.pages.allSatisfy({ FileManager.default.fileExists(atPath: pageURL(key, pageIndex: $0.pageIndex, sessionID: sessionID).path) }),
              gallery.requiresMetadata == false || FileManager.default.fileExists(atPath: metadataURL(key, sessionID: sessionID).path) else {
            throw DeviceSyncError.transferNotPlanned
        }
        journal.completedKeys.insert(key)
        journals[sessionID] = journal
        try persist(journal)
    }

    func completedGalleries(sessionID: UUID) throws -> [DeviceSyncStagedGallery] {
        guard let journal = try load(sessionID) else { return [] }
        return try journal.plan.galleries.compactMap { gallery in
            guard journal.completedKeys.contains(gallery.key),
                  journal.resolvedKeys.contains(gallery.key) == false else { return nil }
            let record: GalleryTransferRecord?
            if gallery.requiresMetadata {
                record = try JSONDecoder().decode(
                    GalleryTransferRecord.self,
                    from: Data(contentsOf: metadataURL(gallery.key, sessionID: sessionID))
                )
                guard record?.stable.key == gallery.key,
                      record?.dynamic.map({ $0.key == gallery.key }) ?? true else {
                    throw DeviceSyncError.transferNotPlanned
                }
            } else {
                record = nil
            }
            return DeviceSyncStagedGallery(key: gallery.key, record: record, pages: gallery.pages)
        }
    }

    func incompleteKeys(sessionID: UUID) throws -> Set<GalleryKey> {
        guard let journal = try load(sessionID) else { return [] }
        return journal.startedKeys
            .subtracting(journal.completedKeys)
            .subtracting(journal.resolvedKeys)
    }

    func unstartedKeys(sessionID: UUID) throws -> Set<GalleryKey> {
        guard let journal = try load(sessionID) else { return [] }
        return Set(journal.plan.galleries.map(\.key))
            .subtracting(journal.startedKeys)
    }

    func markResolved(_ key: GalleryKey, sessionID: UUID) throws {
        guard var journal = try load(sessionID) else { return }
        journal.resolvedKeys.insert(key)
        journals[sessionID] = journal
        try persist(journal)
    }

    func pageURL(for key: GalleryKey, pageIndex: Int, sessionID: UUID) -> URL {
        pageURL(key, pageIndex: pageIndex, sessionID: sessionID)
    }

    func pendingSessionIDs() -> [UUID] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.compactMap { UUID(uuidString: $0.lastPathComponent) }
    }

    func removeSession(_ id: UUID) {
        journals[id] = nil
        try? FileManager.default.removeItem(at: sessionURL(id))
    }

    private func galleryPlan(_ key: GalleryKey, sessionID: UUID) throws -> DeviceSyncStagingGalleryPlan? {
        try load(sessionID)?.plan.galleries.first { $0.key == key }
    }

    private func markStarted(_ key: GalleryKey, sessionID: UUID) throws {
        guard var journal = try load(sessionID) else {
            throw DeviceSyncError.transferNotPlanned
        }
        guard journal.startedKeys.insert(key).inserted else { return }
        journals[sessionID] = journal
        try persist(journal)
    }

    private func load(_ id: UUID) throws -> Journal? {
        if let journal = journals[id] { return journal }
        let url = sessionURL(id).appendingPathComponent("plan.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: url))
        journals[id] = journal
        return journal
    }

    private func persist(_ journal: Journal) throws {
        let data = try JSONEncoder().encode(journal)
        try data.write(
            to: sessionURL(journal.plan.id).appendingPathComponent("plan.json"),
            options: .atomic
        )
    }

    private func sessionURL(_ id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func galleryURL(_ key: GalleryKey, sessionID: UUID) -> URL {
        sessionURL(sessionID).appendingPathComponent(Self.encodedKey(key), isDirectory: true)
    }

    private func metadataURL(_ key: GalleryKey, sessionID: UUID) -> URL {
        galleryURL(key, sessionID: sessionID).appendingPathComponent("metadata.json")
    }

    private func pageURL(_ key: GalleryKey, pageIndex: Int, sessionID: UUID) -> URL {
        galleryURL(key, sessionID: sessionID).appendingPathComponent("page-\(pageIndex + 1).stage")
    }

    private static func encodedKey(_ key: GalleryKey) -> String {
        Data(key.id.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }
}
