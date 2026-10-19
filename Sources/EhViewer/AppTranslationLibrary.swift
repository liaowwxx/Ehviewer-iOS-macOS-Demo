import Foundation
import Observation
import SwiftUI
import EHDomain
import EHDownloads
#if os(macOS)
import EHTranslationMac

extension AppTranslationLibrary {
    func reconnectNativeTranslation(profileID: UUID) {
        TranslationCoordinator.shared.workspaces[profileID]?.onImported = { [weak self] in await self?.refresh() }
    }
}

extension AppModel {
    var nativeTranslation: TranslationWorkspace {
        let workspace = TranslationCoordinator.shared.workspace(profileID: nativeTranslationProfileID, files: translationLibrary.files)
        workspace.onImported = { [weak translationLibrary] in await translationLibrary?.refresh() }
        return workspace
    }
}
#endif

private struct ReadingEditionKey: EnvironmentKey {
    static let defaultValue = ReadingEdition.original
}

extension EnvironmentValues {
    var readingEdition: ReadingEdition {
        get { self[ReadingEditionKey.self] }
        set { self[ReadingEditionKey.self] = newValue }
    }
}

@MainActor
@Observable
final class AppTranslationLibrary {
    let files: TranslationFileStore
    private let defaults: UserDefaults
    private(set) var versions: [GalleryKey: [GalleryTranslationManifest]] = [:]
    private(set) var editions: [GalleryKey: ReadingEdition] = [:]
    var error: String?

    init(files: TranslationFileStore, defaults: UserDefaults) {
        self.files = files
        self.defaults = defaults
    }

    func refresh() async {
        do {
            #if os(macOS)
            // A background workspace can outlive the profile's AppModel and its
            // file-store actor. Reload atomic manifests published by that owner.
            let manifests = try await files.allManifests(refresh: true)
            #else
            let manifests = try await files.allManifests()
            #endif
            versions = Dictionary(grouping: manifests, by: { $0.gallery.key })
            for key in versions.keys where editions[key] == nil {
                let saved = defaults.string(forKey: "translation.edition.\(key.id)")
                if let saved, let id = UUID(uuidString: saved) {
                    editions[key] = .translated(versionID: id)
                }
            }
        } catch { self.error = error.localizedDescription }
    }

    func edition(for key: GalleryKey) -> ReadingEdition { editions[key] ?? .original }

    func select(_ edition: ReadingEdition, for key: GalleryKey) {
        editions[key] = edition
        switch edition {
        case .original: defaults.set("original", forKey: "translation.edition.\(key.id)")
        case .translated(let id): defaults.set(id.uuidString, forKey: "translation.edition.\(key.id)")
        }
    }

    func archive(_ version: GalleryTranslationManifest) async {
        do {
            try await files.archiveVersion(for: version.gallery.key, versionID: version.versionID)
            if edition(for: version.gallery.key) == .translated(versionID: version.versionID) {
                select(.original, for: version.gallery.key)
            }
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
}

extension AppModel {
    func readerPageData(for descriptor: GalleryPageDescriptor, resolution: ImageResolution,
                        source: ReaderContentSource, edition: ReadingEdition) async throws -> Data {
        if case .translated(let versionID) = edition {
            return try await translationLibrary.files.data(for: descriptor.galleryKey, versionID: versionID, index: descriptor.index)
        }
        switch source {
        case .download:
            return try await downloadedPageData(for: descriptor, resolution: resolution)
        case .remote:
            let metadata = try await pageImage(for: descriptor)
            return try await imageData(for: metadata, resolution: resolution)
        }
    }
}
