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

import CryptoKit
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

public struct DownloadReceiveHandle: Sendable, Hashable {
    fileprivate let id: UUID

    fileprivate init(id: UUID) {
        self.id = id
    }
}

public enum DownloadReceiveResult: Sendable, Equatable {
    case committed(URL)
    case alreadyPresent(URL)
}

public enum DownloadReceiveError: Error, LocalizedError, Sendable, Equatable {
    case unknownHandle
    case byteCountExceeded
    case byteCountMismatch
    case hashMismatch
    case invalidMedia

    public var errorDescription: String? {
        switch self {
        case .unknownHandle:
            String(localized: "设备同步接收句柄已失效。")
        case .byteCountExceeded:
            String(localized: "设备同步页面超过声明的大小。")
        case .byteCountMismatch:
            String(localized: "设备同步页面大小校验失败。")
        case .hashMismatch:
            String(localized: "设备同步页面完整性校验失败。")
        case .invalidMedia:
            String(localized: "设备同步页面不是有效媒体。")
        }
    }
}

public actor DownloadFileStore {
    private let root: URL
    private let minimumFreeBytes: Int64
    private var receivingPages: [UUID: ReceivingPage] = [:]

    private struct ReceivingPage {
        let key: GalleryKey
        let pageIndex: Int
        let expectedByteCount: Int64
        let expectedSHA256: Data
        let temporaryURL: URL
        let handle: FileHandle
        var receivedByteCount: Int64 = 0
        var hasher = SHA256()
    }

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
            return FileManager.default.fileExists(atPath: url.path)
                && DownloadMediaValidator.kind(of: url) != nil
        })
    }

    /// Enumerates only real, final page files. Incomplete `.part` files and
    /// names that do not follow the store's page naming convention are ignored.
    public func localPageEntries(for key: GalleryKey) -> [DownloadFileExportEntry] {
        let directory = directory(for: key)
        guard let names = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return names.compactMap { url in
            let name = url.lastPathComponent
            guard name.hasPrefix("page-"), name.hasSuffix(".bin") else { return nil }
            let number = name.dropFirst("page-".count).dropLast(".bin".count)
            guard let oneBasedIndex = Int(number), oneBasedIndex > 0 else { return nil }
            let pageIndex = oneBasedIndex - 1
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  fileSize > 0,
                  DownloadMediaValidator.kind(of: url) != nil else { return nil }
            return DownloadFileExportEntry(
                pageIndex: pageIndex,
                fileURL: url,
                byteCount: Int64(fileSize),
                fileExtension: DownloadMediaValidator.fileExtension(of: url) ?? "bin"
            )
        }.sorted { $0.pageIndex < $1.pageIndex }
    }

    /// Reads a page in bounded chunks. The callback is awaited after each
    /// chunk, so the caller can apply transport back-pressure without loading
    /// the complete media file into memory.
    public func readPageChunks(
        for key: GalleryKey,
        pageIndex: Int,
        chunkSize: Int = 64 * 1024,
        consume: @Sendable (Data) async throws -> Void
    ) async throws {
        guard chunkSize > 0 else { throw EHError.storageFailed("Invalid chunk size") }
        let url = finalURL(for: key, pageIndex: pageIndex)
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let initialSize = values.fileSize,
              initialSize > 0 else {
            throw EHError.storageFailed(String(localized: "同步页面不存在。"))
        }
        guard DownloadMediaValidator.kind(of: url) != nil else {
            throw EHError.parsingFailed(String(localized: "同步页面不是有效媒体。"))
        }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            while true {
                try Task.checkCancellation()
                guard let chunk = try handle.read(upToCount: chunkSize), chunk.isEmpty == false else { break }
                try await consume(chunk)
            }
        } catch let error as EHError {
            throw error
        } catch {
            throw EHError.storageFailed(error.localizedDescription)
        }

        let finalSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard finalSize == initialSize else {
            throw EHError.storageFailed(String(localized: "同步页面在读取期间发生变化。"))
        }
    }

    /// Starts a streamed receive into a store-owned temporary file.
    public func beginReceive(
        for key: GalleryKey,
        pageIndex: Int,
        expectedByteCount: Int64,
        expectedSHA256: Data
    ) throws -> DownloadReceiveHandle {
        guard expectedByteCount > 0,
              expectedByteCount <= 256 * 1024 * 1024,
              expectedSHA256.count == SHA256.Digest.byteCount else {
            throw DeviceSyncManifestError.invalidPageByteCount
        }
        guard hasSufficientFreeSpace else { throw EHError.diskSpaceLow }

        var directory = directory(for: key)
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? directory.setResourceValues(values)
            let id = UUID()
            let temporaryURL = directory.appendingPathComponent("sync-\(id.uuidString).part")
            guard fileManager.createFile(atPath: temporaryURL.path, contents: nil) else {
                throw EHError.storageFailed(String(localized: "无法创建同步临时文件。"))
            }
            let handle = try FileHandle(forWritingTo: temporaryURL)
            receivingPages[id] = ReceivingPage(
                key: key,
                pageIndex: pageIndex,
                expectedByteCount: expectedByteCount,
                expectedSHA256: expectedSHA256,
                temporaryURL: temporaryURL,
                handle: handle
            )
            return DownloadReceiveHandle(id: id)
        } catch let error as EHError {
            throw error
        } catch {
            throw EHError.storageFailed(error.localizedDescription)
        }
    }

    public func appendReceiveChunk(_ data: Data, to handle: DownloadReceiveHandle) throws {
        guard var receiving = receivingPages[handle.id] else {
            throw DownloadReceiveError.unknownHandle
        }
        guard receiving.receivedByteCount + Int64(data.count) <= receiving.expectedByteCount else {
            try discardReceive(handle)
            throw DownloadReceiveError.byteCountExceeded
        }
        do {
            try receiving.handle.write(contentsOf: data)
            receiving.hasher.update(data: data)
            receiving.receivedByteCount += Int64(data.count)
            receivingPages[handle.id] = receiving
        } catch {
            try? discardReceive(handle)
            throw EHError.storageFailed(error.localizedDescription)
        }
    }

    public func finishReceive(_ handle: DownloadReceiveHandle) throws -> DownloadReceiveResult {
        guard let receiving = receivingPages.removeValue(forKey: handle.id) else {
            throw DownloadReceiveError.unknownHandle
        }
        defer { try? receiving.handle.close() }

        guard receiving.receivedByteCount == receiving.expectedByteCount else {
            try? FileManager.default.removeItem(at: receiving.temporaryURL)
            throw DownloadReceiveError.byteCountMismatch
        }
        guard Data(receiving.hasher.finalize()) == receiving.expectedSHA256 else {
            try? FileManager.default.removeItem(at: receiving.temporaryURL)
            throw DownloadReceiveError.hashMismatch
        }
        guard DownloadMediaValidator.kind(of: receiving.temporaryURL) != nil else {
            try? FileManager.default.removeItem(at: receiving.temporaryURL)
            throw DownloadReceiveError.invalidMedia
        }

        let finalURL = finalURL(for: receiving.key, pageIndex: receiving.pageIndex)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: finalURL.path), DownloadMediaValidator.kind(of: finalURL) != nil {
            try? fileManager.removeItem(at: receiving.temporaryURL)
            return .alreadyPresent(finalURL)
        }
        do {
            if fileManager.fileExists(atPath: finalURL.path) {
                try fileManager.removeItem(at: finalURL)
            }
            try fileManager.moveItem(at: receiving.temporaryURL, to: finalURL)
            return .committed(finalURL)
        } catch {
            try? fileManager.removeItem(at: receiving.temporaryURL)
            throw EHError.storageFailed(error.localizedDescription)
        }
    }

    public func discardReceive(_ handle: DownloadReceiveHandle) throws {
        guard let receiving = receivingPages.removeValue(forKey: handle.id) else { return }
        try? receiving.handle.close()
        try? FileManager.default.removeItem(at: receiving.temporaryURL)
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
            if fileManager.fileExists(atPath: finalURL.path), DownloadMediaValidator.kind(of: finalURL) != nil {
                return finalURL
            }
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
