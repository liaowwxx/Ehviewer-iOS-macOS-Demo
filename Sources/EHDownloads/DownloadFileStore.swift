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
import EHDomain

public struct DownloadFileExportEntry: Sendable, Hashable {
    public let pageIndex: Int
    public let fileURL: URL
    public let byteCount: Int64
    public let fileExtension: String

    public init(pageIndex: Int, fileURL: URL, byteCount: Int64, fileExtension: String) {
        self.pageIndex = pageIndex
        self.fileURL = fileURL
        self.byteCount = byteCount
        self.fileExtension = fileExtension
    }
}

public actor DownloadFileStore {
    private let root: URL
    private let minimumFreeBytes: Int64

    public init(root: URL? = nil, minimumFreeBytes: Int64 = 1_024 * 1_024 * 1_024) {
        var resolvedRoot = root ?? Self.defaultRoot
        self.root = resolvedRoot
        self.minimumFreeBytes = minimumFreeBytes
        try? FileManager.default.createDirectory(at: resolvedRoot, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? resolvedRoot.setResourceValues(values)
    }

    public func finalURL(for key: GalleryKey, pageIndex: Int) -> URL {
        directory(for: key).appendingPathComponent("page-\(pageIndex + 1).bin")
    }

    public func contains(_ key: GalleryKey, pageIndex: Int) -> Bool {
        FileManager.default.fileExists(atPath: finalURL(for: key, pageIndex: pageIndex).path)
    }

    public func readablePageIndexes(for key: GalleryKey, pageIndexes: [Int]) -> Set<Int> {
        Set(pageIndexes.filter { pageIndex in
            let url = finalURL(for: key, pageIndex: pageIndex)
            guard FileManager.default.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
            return DownloadMediaValidator.kind(of: data) != nil
        })
    }

    public func data(for key: GalleryKey, pageIndex: Int) throws -> Data {
        do {
            return try Data(contentsOf: finalURL(for: key, pageIndex: pageIndex), options: .mappedIfSafe)
        } catch {
            throw EHError.storageFailed(error.localizedDescription)
        }
    }

    public func exportEntry(for key: GalleryKey, pageIndex: Int) -> DownloadFileExportEntry? {
        let url = finalURL(for: key, pageIndex: pageIndex)
        guard FileManager.default.fileExists(atPath: url.path),
              let fileExtension = DownloadMediaValidator.fileExtension(of: url),
              let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let byteCount = resourceValues.fileSize,
              byteCount >= 0 else { return nil }
        return DownloadFileExportEntry(
            pageIndex: pageIndex,
            fileURL: url,
            byteCount: Int64(byteCount),
            fileExtension: fileExtension
        )
    }

    @discardableResult
    public func write(_ data: Data, for key: GalleryKey, pageIndex: Int) throws -> URL {
        try DownloadMediaValidator.validate(data)
        if hasSufficientFreeSpace == false {
            throw EHError.diskSpaceLow
        }

        var directory = directory(for: key)
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            var directoryValues = URLResourceValues()
            directoryValues.isExcludedFromBackup = true
            try? directory.setResourceValues(directoryValues)

            let finalURL = finalURL(for: key, pageIndex: pageIndex)
            let partialURL = finalURL.appendingPathExtension("part")
            try data.write(to: partialURL, options: .atomic)
            if fileManager.fileExists(atPath: finalURL.path) {
                try fileManager.removeItem(at: finalURL)
            }
            try fileManager.moveItem(at: partialURL, to: finalURL)
            return finalURL
        } catch let error as EHError {
            throw error
        } catch {
            throw EHError.storageFailed(error.localizedDescription)
        }
    }

    @discardableResult
    public func importFile(at sourceURL: URL, for key: GalleryKey, pageIndex: Int) throws -> URL {
        guard FileManager.default.fileExists(atPath: sourceURL.path),
              let data = try? Data(contentsOf: sourceURL, options: .mappedIfSafe),
              DownloadMediaValidator.kind(of: data) != nil else {
            throw EHError.parsingFailed(String(localized: "恢复文件不是有效图片或视频"))
        }
        if hasSufficientFreeSpace == false {
            throw EHError.diskSpaceLow
        }

        var directory = directory(for: key)
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            var directoryValues = URLResourceValues()
            directoryValues.isExcludedFromBackup = true
            try? directory.setResourceValues(directoryValues)

            let finalURL = finalURL(for: key, pageIndex: pageIndex)
            let partialURL = finalURL.appendingPathExtension("part")
            if fileManager.fileExists(atPath: partialURL.path) {
                try fileManager.removeItem(at: partialURL)
            }
            do {
                try fileManager.moveItem(at: sourceURL, to: partialURL)
            } catch {
                try fileManager.copyItem(at: sourceURL, to: partialURL)
                try? fileManager.removeItem(at: sourceURL)
            }
            if fileManager.fileExists(atPath: finalURL.path) {
                try fileManager.removeItem(at: finalURL)
            }
            try fileManager.moveItem(at: partialURL, to: finalURL)
            return finalURL
        } catch let error as EHError {
            throw error
        } catch {
            throw EHError.storageFailed(error.localizedDescription)
        }
    }

    public func remove(_ key: GalleryKey) throws {
        let directory = directory(for: key)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            throw EHError.storageFailed(error.localizedDescription)
        }
    }

    private func directory(for key: GalleryKey) -> URL {
        let encoded = Data(key.id.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return root.appendingPathComponent(encoded, isDirectory: true)
    }

    /// macOS sandboxed processes can report zero for the important-usage
    /// capacity while still exposing a valid regular capacity. Only use that
    /// fallback when it also satisfies the configured safety threshold.
    private var hasSufficientFreeSpace: Bool {
        guard let values = try? root.resourceValues(
            forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ]
        ) else { return true }
        let available: Int64? = if let important = values.volumeAvailableCapacityForImportantUsage,
                                  important > 0 {
            important
        } else {
            values.volumeAvailableCapacity.map(Int64.init)
        }
        guard let available else { return true }
        return available >= minimumFreeBytes
    }

    public static var defaultRootURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("EhViewer/Downloads", isDirectory: true)
    }

    private static var defaultRoot: URL { defaultRootURL }
}
