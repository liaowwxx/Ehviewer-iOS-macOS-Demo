import Foundation

/// Published versions have every index. Interrupted incoming versions advertise
/// only verified staged pages, so a later session resumes at page boundaries.
public struct DeviceSyncTranslationEntry: Codable, Hashable, Sendable, Identifiable {
    public let manifest: GalleryTranslationManifest
    public let availablePages: [Int]
    public var id: UUID { manifest.versionID }

    public init(manifest: GalleryTranslationManifest, availablePages: [Int]) throws {
        try manifest.validate()
        guard Set(availablePages).count == availablePages.count,
              availablePages.allSatisfy({ manifest.pages.indices.contains($0) }) else { throw DeviceSyncManifestError.invalidPageIndex }
        self.manifest = manifest
        self.availablePages = availablePages.sorted()
    }

    public var byteCount: Int64 { availablePages.reduce(0) { $0 + manifest.pages[$1].byteCount } }
}

public enum DeviceSyncTranslationReconciler {
    public static func validate(local: [DeviceSyncTranslationEntry], remote: [DeviceSyncTranslationEntry]) throws {
        for entries in [local, remote] {
            var ids = Set<UUID>()
            guard entries.count <= 10_000 else { throw DeviceSyncManifestError.tooManyGalleries }
            var pages = 0
            for entry in entries {
                _ = try DeviceSyncTranslationEntry(manifest: entry.manifest, availablePages: entry.availablePages)
                guard ids.insert(entry.id).inserted else { throw DeviceSyncManifestError.duplicateGalleryKey }
                pages += entry.manifest.pages.count
            }
            guard pages <= DeviceSyncManifest.maximumPageCount else { throw DeviceSyncManifestError.tooManyPages }
        }
        let localByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0.manifest) })
        for entry in remote {
            if let existing = localByID[entry.id], existing != entry.manifest {
                throw EHError.parsingFailed(String(localized: "相同译件版本包含不同内容。"))
            }
        }
    }

    public static func missing(local: [DeviceSyncTranslationEntry], remote: [DeviceSyncTranslationEntry]) -> [DeviceSyncTranslationEntry] {
        let indexed = Dictionary(local.map { ($0.id, Set($0.availablePages)) }, uniquingKeysWith: { first, _ in first })
        return remote.compactMap { entry in
            let pages = entry.availablePages.filter { !(indexed[entry.id] ?? []).contains($0) }
            guard !pages.isEmpty else { return nil }
            return try? DeviceSyncTranslationEntry(manifest: entry.manifest, availablePages: pages)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}
