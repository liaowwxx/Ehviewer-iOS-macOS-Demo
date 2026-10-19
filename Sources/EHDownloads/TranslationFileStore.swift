import CryptoKit
import Foundation
import ImageIO
import EHDomain

/// The manifest inside a renamed version directory is the commit record.
/// There is no second database write to lose after a crash: incomplete staging
/// directories are invisible and a committed manifest reconstructs the catalog.
public actor TranslationFileStore {
    public nonisolated let root: URL
    private var catalog: [GalleryKey: [GalleryTranslationManifest]]?
    private var incoming: [UUID: DeviceSyncTranslationEntry]?

    public init(root: URL = TranslationFileStore.defaultRootURL) {
        self.root = root
    }

    public static var defaultRootURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("EhViewer/Translations", isDirectory: true)
    }

    public func manifests(for key: GalleryKey) throws -> [GalleryTranslationManifest] {
        try loadCatalog()
        return catalog?[key] ?? []
    }

    public func allManifests(refresh: Bool = false) throws -> [GalleryTranslationManifest] {
        if refresh { catalog = nil }
        try loadCatalog()
        return (catalog ?? [:]).values.flatMap { $0 }.sorted { $0.versionID.uuidString < $1.versionID.uuidString }
    }

    public func storeGalleryMetadata(_ record: GalleryTransferRecord) throws {
        let directory = root.appendingPathComponent("Metadata", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(Self.metadataFileName(record.stable.key))
        try JSONEncoder().encode(record).write(to: file, options: .atomic)
    }

    public func galleryMetadata(for key: GalleryKey) throws -> GalleryTransferRecord? {
        let file = root.appendingPathComponent("Metadata").appendingPathComponent(Self.metadataFileName(key))
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let record = try JSONDecoder().decode(GalleryTransferRecord.self, from: Data(contentsOf: file))
        guard record.stable.key == key else { throw EHError.invalidResponse }
        return record
    }

    private static func metadataFileName(_ key: GalleryKey) -> String {
        SHA256.hash(data: Data(key.id.utf8)).map { String(format: "%02x", $0) }.joined() + ".json"
    }

    public func syncEntries() throws -> [DeviceSyncTranslationEntry] {
        try loadIncoming()
        var result = incoming ?? [:]
        for manifest in try allManifests() {
            result[manifest.id] = try DeviceSyncTranslationEntry(manifest: manifest, availablePages: Array(manifest.pages.indices))
        }
        return result.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    public func beginIncoming(_ manifest: GalleryTranslationManifest) throws {
        try manifest.validate()
        try loadIncoming()
        if let existing = try manifests(for: manifest.gallery.key).first(where: { $0.id == manifest.id }), existing != manifest {
            throw EHError.storageFailed(String(localized: "相同译件版本包含不同内容。"))
        }
        if let existing = incoming?[manifest.id], existing.manifest != manifest {
            throw EHError.storageFailed(String(localized: "相同译件版本包含不同内容。"))
        }
        let directory = incomingDirectory(manifest.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
        if incoming?[manifest.id] == nil {
            incoming?[manifest.id] = try DeviceSyncTranslationEntry(manifest: manifest, availablePages: [])
        }
    }

    public func beginIncomingPage(_ manifest: GalleryTranslationManifest, index: Int) throws -> TranslationPageReceiver {
        try beginIncoming(manifest)
        guard manifest.pages.indices.contains(index) else { throw DeviceSyncManifestError.invalidPageIndex }
        return try TranslationPageReceiver(directory: incomingDirectory(manifest.id), page: manifest.pages[index])
    }

    public func finishIncomingPage(_ manifest: GalleryTranslationManifest, index: Int) throws {
        let file = incomingDirectory(manifest.id).appendingPathComponent(manifest.pages[index].fileName)
        try Self.validateFile(file, page: manifest.pages[index])
        let available = Set(incoming?[manifest.id]?.availablePages ?? []).union([index])
        incoming?[manifest.id] = try DeviceSyncTranslationEntry(manifest: manifest, availablePages: Array(available))
        if available.count == manifest.pages.count {
            try importVersion(manifest, pagesDirectory: incomingDirectory(manifest.id))
        }
    }

    public func streamPage(_ manifest: GalleryTranslationManifest, index: Int,
                           consume: @Sendable (Data) async throws -> Void) async throws {
        let published = try manifests(for: manifest.gallery.key).contains(where: { $0 == manifest })
        let file = published ? try pageURL(for: manifest, index: index)
            : incomingDirectory(manifest.id).appendingPathComponent(manifest.pages[index].fileName)
        try Self.validateFile(file, page: manifest.pages[index])
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        var count: Int64 = 0
        while let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
            count += Int64(chunk.count)
            try await consume(chunk)
        }
        let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard count == manifest.pages[index].byteCount, hash == manifest.pages[index].sha256 else {
            throw EHError.storageFailed(String(localized: "译件页面在传输期间发生变化。"))
        }
    }

    private func incomingDirectory(_ id: UUID) -> URL { root.appendingPathComponent("Incoming/\(id.uuidString)", isDirectory: true) }

    private func loadIncoming() throws {
        guard incoming == nil else { return }
        incoming = [:]
        let directory = root.appendingPathComponent("Incoming")
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        for version in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let url = version.appendingPathComponent("manifest.json")
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 4 * 1024 * 1024,
                  let data = try? Data(contentsOf: url),
                  let manifest = try? JSONDecoder().decode(GalleryTranslationManifest.self, from: data),
                  (try? manifest.validate()) != nil, version.lastPathComponent == manifest.id.uuidString else { continue }
            let available = manifest.pages.filter {
                (try? Self.validateFile(version.appendingPathComponent($0.fileName), page: $0)) != nil
            }.map(\.index)
            incoming?[manifest.id] = try DeviceSyncTranslationEntry(manifest: manifest, availablePages: available)
            if available.count == manifest.pages.count {
                try importVersion(manifest, pagesDirectory: version)
            }
        }
    }

    public func pageURL(for manifest: GalleryTranslationManifest, index: Int) throws -> URL {
        try manifest.validate()
        guard manifest.pages.indices.contains(index) else { throw EHError.storageFailed(String(localized: "译件页面不存在。")) }
        return versionDirectory(manifest).appendingPathComponent("pages", isDirectory: true)
            .appendingPathComponent(manifest.pages[index].fileName)
    }

    public func data(for key: GalleryKey, versionID: UUID, index: Int) throws -> Data {
        guard let manifest = try manifests(for: key).first(where: { $0.versionID == versionID }) else {
            throw EHError.storageFailed(String(localized: "译件缺失或损坏，请切换原件。"))
        }
        let url = try pageURL(for: manifest, index: index)
        let page = manifest.pages[index]
        try Self.validateFile(url, page: page)
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    /// Copies from a caller-owned staging directory; originals and existing
    /// versions are never overwritten. Retrying the same immutable version is safe.
    public func importVersion(_ manifest: GalleryTranslationManifest, pagesDirectory: URL) throws {
        try manifest.validate()
        if let existing = try manifests(for: manifest.gallery.key).first(where: { $0.versionID == manifest.versionID }) {
            guard existing == manifest else { throw EHError.storageFailed(String(localized: "相同译件版本包含不同内容。")) }
            for page in existing.pages { try Self.validateFile(pageURL(for: existing, index: page.index), page: page) }
            return
        }
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let required = manifest.pages.reduce(Int64(0)) { $0 + $1.byteCount }
        if let free = try? root.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity,
           Int64(free) < required + 128 * 1024 * 1024 { throw EHError.diskSpaceLow }
        let stage = root.appendingPathComponent("Staging/\(UUID().uuidString)", isDirectory: true)
        let pages = stage.appendingPathComponent("pages", isDirectory: true)
        try manager.createDirectory(at: pages, withIntermediateDirectories: true)
        for page in manifest.pages {
            try Task.checkCancellation()
            let source = pagesDirectory.appendingPathComponent(page.fileName)
            let destination = pages.appendingPathComponent(page.fileName)
            try manager.copyItem(at: source, to: destination)
            try Self.validateFile(destination, page: page)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(to: stage.appendingPathComponent("manifest.json"), options: .atomic)
        let target = versionDirectory(manifest)
        try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard !manager.fileExists(atPath: target.path) else { throw EHError.storageFailed(String(localized: "译件版本已存在。")) }
        try manager.moveItem(at: stage, to: target)
        catalog?[manifest.gallery.key, default: []].append(manifest)
        catalog?[manifest.gallery.key]?.sort { $0.createdAt > $1.createdAt }
    }

    /// User-requested removal is recoverable; it does not touch source pages.
    public func archiveVersion(for key: GalleryKey, versionID: UUID) throws {
        guard let manifest = try manifests(for: key).first(where: { $0.versionID == versionID }) else { return }
        let source = versionDirectory(manifest)
        let batch = UUID().uuidString
        let archiveRoot = root.appendingPathComponent("deleted_file", isDirectory: true)
        try FileManager.default.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
        let target = archiveRoot.appendingPathComponent(batch, isDirectory: true)
        let info = archiveRoot.appendingPathComponent("info.md")
        let staged = incomingDirectory(versionID)
        let stagedArchive = archiveRoot.appendingPathComponent(batch + "-incoming", isDirectory: true)
        guard !FileManager.default.fileExists(atPath: target.path), !FileManager.default.fileExists(atPath: stagedArchive.path) else { throw EHError.invalidResponse }
        let manifestSHA256 = try Self.sha256(of: source.appendingPathComponent("manifest.json"))
        let record = "\n- \(ISO8601DateFormatter().string(from: Date())): \(source.path) -> \(target.path); staging \(staged.path) -> \(stagedArchive.path) if present; Gallery translation assets; user requested translation removal; manifest SHA-256 \(manifestSHA256); restore by moving the version directory back; page SHA-256 values remain in manifest.json.\n"
        if !FileManager.default.fileExists(atPath: info.path) { try Data("# Translation archives\n".utf8).write(to: info) }
        let handle = try FileHandle(forWritingTo: info)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(record.utf8))
        try handle.synchronize()
        if FileManager.default.fileExists(atPath: staged.path) {
            try FileManager.default.moveItem(at: staged, to: stagedArchive)
        }
        try FileManager.default.moveItem(at: source, to: target)
        guard !FileManager.default.fileExists(atPath: source.path), FileManager.default.fileExists(atPath: target.path) else { throw EHError.invalidResponse }
        catalog?[key]?.removeAll { $0.versionID == versionID }
        // Staged input is retained for diagnostics, but no longer advertised.
        incoming?[versionID] = nil
    }

    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func validateFile(_ url: URL, page: GalleryTranslationManifest.Page) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              values.fileSize.map(Int64.init) == page.byteCount,
              try sha256(of: url) == page.sha256,
              let image = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(image) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 100_000_000 / height,
              CGImageSourceGetStatus(image) == .statusComplete else {
            throw EHError.storageFailed(String(localized: "译件缺失或损坏，请切换原件。"))
        }
    }

    private func loadCatalog() throws {
        guard catalog == nil else { return }
        let galleries = root.appendingPathComponent("Galleries", isDirectory: true)
        guard FileManager.default.fileExists(atPath: galleries.path) else { catalog = [:]; return }
        var result: [GalleryKey: [GalleryTranslationManifest]] = [:]
        for galleryURL in try FileManager.default.contentsOfDirectory(at: galleries, includingPropertiesForKeys: nil) {
            for versionURL in try FileManager.default.contentsOfDirectory(at: galleryURL, includingPropertiesForKeys: nil) {
                let url = versionURL.appendingPathComponent("manifest.json")
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                      let size = values.fileSize, size <= 4 * 1024 * 1024,
                      let data = try? Data(contentsOf: url),
                      let manifest = try? JSONDecoder().decode(GalleryTranslationManifest.self, from: data),
                      (try? manifest.validate()) != nil,
                      versionDirectory(manifest).standardizedFileURL == versionURL.standardizedFileURL else { continue }
                result[manifest.gallery.key, default: []].append(manifest)
            }
        }
        catalog = result.mapValues { $0.sorted { $0.createdAt > $1.createdAt } }
    }

    private func versionDirectory(_ manifest: GalleryTranslationManifest) -> URL {
        let key = Data(manifest.gallery.key.id.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return root.appendingPathComponent("Galleries", isDirectory: true)
            .appendingPathComponent(key, isDirectory: true)
            .appendingPathComponent(manifest.versionID.uuidString, isDirectory: true)
    }
}
