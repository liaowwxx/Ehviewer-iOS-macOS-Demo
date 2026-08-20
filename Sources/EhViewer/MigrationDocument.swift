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

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

extension UTType {
    static let ehViewerDownloadArchive = UTType(
        exportedAs: "com.liao.ehviewer.downloadarchive",
        conformingTo: .zip
    )

    static let ehViewerGallerySync = UTType(
        exportedAs: "com.liao.ehviewer.gallerysync",
        conformingTo: .zip
    )
}

enum BackupFileFormat {
    static let downloadArchiveExtension = "eharchive"
    static let gallerySyncExtension = "ehgallery"
    static let legacyZipExtension = "zip"

    static var downloadImportTypes: [UTType] { [.ehViewerDownloadArchive, .zip] }
    static var gallerySyncImportTypes: [UTType] { [.ehViewerGallerySync] }

    static func isDownloadArchiveURL(_ url: URL) -> Bool {
        [downloadArchiveExtension, legacyZipExtension].contains(url.pathExtension.lowercased())
    }

    static func isGallerySyncURL(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare(gallerySyncExtension) == .orderedSame
    }
}

struct ArchiveExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.ehViewerDownloadArchive]
    static let writableContentTypes: [UTType] = [.ehViewerDownloadArchive]

    let sourceURL: URL?
    let data: Data

    init(data: Data) {
        sourceURL = nil
        self.data = data
    }

    init(sourceURL: URL) {
        self.sourceURL = sourceURL
        data = Data()
    }

    init(configuration: ReadConfiguration) throws {
        sourceURL = nil
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if let sourceURL {
            return try FileWrapper(url: sourceURL, options: [])
        }
        return FileWrapper(regularFileWithContents: data)
    }
}

struct GallerySyncExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.ehViewerGallerySync]
    static let writableContentTypes: [UTType] = [.ehViewerGallerySync]

    let sourceURL: URL?
    let data: Data

    init(data: Data) {
        sourceURL = nil
        self.data = data
    }

    init(sourceURL: URL) {
        self.sourceURL = sourceURL
        data = Data()
    }

    init(configuration: ReadConfiguration) throws {
        sourceURL = nil
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if let sourceURL {
            return try FileWrapper(url: sourceURL, options: [])
        }
        return FileWrapper(regularFileWithContents: data)
    }
}

#if os(macOS)
@MainActor
enum DownloadArchiveSavePanel {
    static func save(_ sourceURL: URL) async throws -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.ehViewerDownloadArchive]
        panel.nameFieldStringValue = sourceURL.lastPathComponent

        guard await panel.begin() == .OK, let destinationURL = panel.url else {
            return false
        }

        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }.value
        return true
    }
}
#endif
