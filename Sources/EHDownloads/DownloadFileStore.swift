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

/// The on-disk usage of download jobs that still have readable local pages.
/// Keeping the keys alongside the totals lets callers present an accurate
/// library count and delete exactly the files represented by that count.
public struct LocalDownloadLibraryUsage: Sendable, Hashable {
    public let galleryKeys: [GalleryKey]
    public let byteCount: Int64

    public init(galleryKeys: [GalleryKey], byteCount: Int64) {
        self.galleryKeys = galleryKeys
        self.byteCount = byteCount
    }

    public var galleryCount: Int { galleryKeys.count }
}

public struct DownloadGalleryFileAudit: Sendable, Hashable {
    public let validPages: [DownloadFileExportEntry]
    public let invalidFinalFileCount: Int
    public let removedTemporaryFileCount: Int

    public init(
        validPages: [DownloadFileExportEntry],
        invalidFinalFileCount: Int,
        removedTemporaryFileCount: Int
    ) {
        self.validPages = validPages
        self.invalidFinalFileCount = invalidFinalFileCount
        self.removedTemporaryFileCount = removedTemporaryFileCount
    }
}

public struct DownloadPageStreamResult: Sendable, Hashable {
    public let byteCount: Int64
    public let sha256: Data

    public init(byteCount: Int64, sha256: Data) {
        self.byteCount = byteCount
        self.sha256 = sha256
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

public enum DownloadImportResult: Sendable, Equatable {
    case imported(URL, sha256: Data)
    case alreadyPresent(URL)

    public var url: URL {
        switch self {
        case let .imported(url, _), let .alreadyPresent(url): url
        }
    }
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
    private var indexSink: (any DeviceSyncIndexSink)?
    private var receivingPages: [UUID: ReceivingPage] = [:]

    private struct ReceivingPage {
        let key: GalleryKey
        let pageIndex: Int
        let expectedByteCount: Int64
        let expectedSHA256: Data?
        let temporaryURL: URL
        let handle: FileHandle
        var receivedByteCount: Int64 = 0
        var hasher = SHA256()
    }

    public init(
        root: URL? = nil,
        minimumFreeBytes: Int64 = 1_024 * 1_024 * 1_024,
        indexSink: (any DeviceSyncIndexSink)? = nil
    ) {
        var resolvedRoot = root ?? Self.defaultRoot
        self.root = resolvedRoot
        self.minimumFreeBytes = minimumFreeBytes
        self.indexSink = indexSink
        try? FileManager.default.createDirectory(at: resolvedRoot, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? resolvedRoot.setResourceValues(values)
    }

    public func configureDeviceSyncIndex(_ indexSink: (any DeviceSyncIndexSink)?) {
        self.indexSink = indexSink
    }

    public func finalURL(for key: GalleryKey, pageIndex: Int) -> URL {
        directory(for: key).appendingPathComponent("page-\(pageIndex + 1).bin")
    }

    public func contains(_ key: GalleryKey, pageIndex: Int) -> Bool {
        FileManager.default.fileExists(atPath: finalURL(for: key, pageIndex: pageIndex).path)
    }

    public func readablePageIndexes(
        for key: GalleryKey,
        pageIndexes: [Int],
        refreshValidIndexEntries: Bool = true
    ) async -> Set<Int> {
        var readable: Set<Int> = []
        for pageIndex in pageIndexes {
            let url = finalURL(for: key, pageIndex: pageIndex)
            guard FileManager.default.fileExists(atPath: url.path),
                  let kind = DownloadMediaValidator.kind(of: url),
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = values.fileSize,
                  fileSize > 0 else {
                await indexSink?.removeMediaPage(key: key, pageIndex: pageIndex)
                continue
            }
            readable.insert(pageIndex)
            if refreshValidIndexEntries {
                await indexSink?.upsertMediaPage(key: key, pageIndex: pageIndex, byteCount: Int64(fileSize))
            }
            _ = kind
        }
        return readable
    }

    /// Enumerates only real, final page files. Incomplete `.part` files and
    /// names that do not follow the store's page naming convention are ignored.
    public func localPageEntries(for key: GalleryKey) -> [DownloadFileExportEntry] {
        auditLocalGallery(for: key, removeInvalidFiles: false).validPages
    }

    /// Counts only galleries that contain at least one valid, readable page.
    /// Queued jobs and incomplete temporary files are intentionally excluded.
    public func localLibraryUsage(for keys: [GalleryKey]) async -> LocalDownloadLibraryUsage {
        // Media validation uses ImageIO and can be expensive for a large
        // library. Keep it off this actor so local page reads are not queued
        // behind the storage-management scan.
        let root = root
        return await Task.detached(priority: .utility) {
            var seen = Set<GalleryKey>()
            var localKeys: [GalleryKey] = []
            var byteCount: Int64 = 0

            for key in keys where seen.insert(key).inserted {
                let pages = Self.auditLocalGallery(
                    root: root,
                    key: key,
                    removeInvalidFiles: false
                ).validPages
                guard pages.isEmpty == false else { continue }
                localKeys.append(key)
                byteCount += pages.reduce(into: Int64.zero) { $0 += $1.byteCount }
            }

            return LocalDownloadLibraryUsage(galleryKeys: localKeys, byteCount: byteCount)
        }.value
    }

    /// Performs the full validation pass used to build or rebuild the
    /// device-sync index. Keeping the loop inside this actor avoids an actor
    /// hop for every page while still reporting completion per gallery and
    /// checking cancellation between galleries.
    public func scanLocalPageEntries(
        for keys: [GalleryKey],
        progress: (@MainActor @Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [GalleryKey: [DeviceSyncPageEntry]] {
        var result: [GalleryKey: [DeviceSyncPageEntry]] = [:]
        result.reserveCapacity(keys.count)
        for (offset, key) in keys.enumerated() {
            try Task.checkCancellation()
            let entries = auditLocalGallery(for: key, removeInvalidFiles: false).validPages.compactMap { entry in
                try? DeviceSyncPageEntry(pageIndex: entry.pageIndex, byteCount: entry.byteCount)
            }
            if entries.isEmpty == false {
                result[key] = entries
            }
            await progress?(offset + 1, keys.count)
        }
        return result
    }

    /// Reconciles the physical gallery directory without consulting download
    /// task state. Only store-owned `page-N.bin` and temporary `.part` files
    /// are considered; unrelated files are left untouched.
    public func auditLocalGallery(
        for key: GalleryKey,
        removeInvalidFiles: Bool
    ) -> DownloadGalleryFileAudit {
        Self.auditLocalGallery(root: root, key: key, removeInvalidFiles: removeInvalidFiles)
    }

    private static func auditLocalGallery(
        root: URL,
        key: GalleryKey,
        removeInvalidFiles: Bool
    ) -> DownloadGalleryFileAudit {
        let directory = directory(for: key, root: root)
        guard let names = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return DownloadGalleryFileAudit(
                validPages: [],
                invalidFinalFileCount: 0,
                removedTemporaryFileCount: 0
            )
        }

        let fileManager = FileManager.default
        var validPages: [DownloadFileExportEntry] = []
        var invalidFinalFileCount = 0
        var removedTemporaryFileCount = 0

        for url in names {
            let name = url.lastPathComponent
            if name.hasSuffix(".part"),
               name.hasPrefix("page-") || name.hasPrefix("sync-") {
                if removeInvalidFiles, (try? fileManager.removeItem(at: url)) != nil {
                    removedTemporaryFileCount += 1
                }
                continue
            }
            guard name.hasPrefix("page-"), name.hasSuffix(".bin") else { continue }
            let number = name.dropFirst("page-".count).dropLast(".bin".count)
            guard let oneBasedIndex = Int(number), oneBasedIndex > 0 else {
                invalidFinalFileCount += 1
                if removeInvalidFiles { try? fileManager.removeItem(at: url) }
                continue
            }
            let pageIndex = oneBasedIndex - 1
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  fileSize > 0,
                  let mediaKind = DownloadMediaValidator.kind(of: url) else {
                invalidFinalFileCount += 1
                if removeInvalidFiles { try? fileManager.removeItem(at: url) }
                continue
            }
            validPages.append(DownloadFileExportEntry(
                pageIndex: pageIndex,
                fileURL: url,
                byteCount: Int64(fileSize),
                fileExtension: DownloadMediaValidator.fileExtension(of: url, kind: mediaKind) ?? "bin"
            ))
        }

        return DownloadGalleryFileAudit(
            validPages: validPages.sorted { $0.pageIndex < $1.pageIndex },
            invalidFinalFileCount: invalidFinalFileCount,
            removedTemporaryFileCount: removedTemporaryFileCount
        )
    }

    /// Removes only store-owned interrupted-write files. Call this during app
    /// startup, before downloads or device sync can create new partials.
    @discardableResult
    public func sweepTemporaryFiles() -> Int {
        let fileManager = FileManager.default
        guard let directories = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var removed = 0
        for directory in directories {
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let files = try? fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                  ) else { continue }
            for file in files {
                let name = file.lastPathComponent
                guard name.hasSuffix(".part"),
                      name.hasPrefix("page-") || name.hasPrefix("sync-") else { continue }
                if (try? fileManager.removeItem(at: file)) != nil {
                    removed += 1
                }
            }
        }
        return removed
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
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var byteCount: Int64 = 0
            while let chunk = try handle.read(upToCount: chunkSize), chunk.isEmpty == false {
                try Task.checkCancellation()
                byteCount += Int64(chunk.count)
                try await consume(chunk)
            }
            let finalSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard finalSize == initialSize, byteCount == Int64(initialSize) else {
                throw EHError.storageFailed(String(localized: "同步页面在读取期间发生变化。"))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as EHError {
            throw error
        } catch {
            // The consumer performs the network send. Preserve transport
            // errors instead of misclassifying them as local-storage errors.
            throw error
        }
    }

    /// Performs the expensive media parse only after the network stage has
    /// acknowledged all declared bytes.
    nonisolated public static func validateDeviceSyncStagedFile(at url: URL, expectedByteCount: Int64) throws {
        guard expectedByteCount > 0,
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              Int64(size) == expectedByteCount else {
            throw DownloadReceiveError.byteCountMismatch
        }
        guard DownloadMediaValidator.kind(of: url) != nil else {
            throw DownloadReceiveError.invalidMedia
        }
    }

    /// Moves one validated staging file into the download store. Existing
    /// valid media wins so a concurrent local download is never overwritten.
    public func commitDeviceSyncStagedFile(
        at url: URL,
        for key: GalleryKey,
        pageIndex: Int
    ) async throws -> URL {
        let commitURL = url.appendingPathExtension("commit-\(UUID().uuidString)")
        do {
            try FileManager.default.linkItem(at: url, to: commitURL)
        } catch {
            try FileManager.default.copyItem(at: url, to: commitURL)
        }
        defer { try? FileManager.default.removeItem(at: commitURL) }
        return try await importFileResult(
            at: commitURL,
            for: key,
            pageIndex: pageIndex,
            updateIndex: false
        ).url
    }

    /// Streams one page and computes its digest in the same file read. Keeping
    /// the hasher beside the file handle avoids an actor hop for every chunk
    /// while retaining bounded memory and transport back-pressure.
    public func readPageChunksAndHash(
        for key: GalleryKey,
        pageIndex: Int,
        chunkSize: Int = 256 * 1024,
        consume: @Sendable (Data) async throws -> Void
    ) async throws -> DownloadPageStreamResult {
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
            var byteCount: Int64 = 0
            var hasher = SHA256()
            while true {
                try Task.checkCancellation()
                guard let chunk = try handle.read(upToCount: chunkSize), chunk.isEmpty == false else { break }
                hasher.update(data: chunk)
                byteCount += Int64(chunk.count)
                try await consume(chunk)
            }

            let finalSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard finalSize == initialSize, byteCount == Int64(initialSize) else {
                throw EHError.storageFailed(String(localized: "同步页面在读取期间发生变化。"))
            }
            return DownloadPageStreamResult(
                byteCount: byteCount,
                sha256: Data(hasher.finalize())
            )
        } catch let error as EHError {
            throw error
        } catch {
            throw EHError.storageFailed(error.localizedDescription)
        }
    }

    /// Starts a streamed receive into a store-owned temporary file.
    public func beginReceive(
        for key: GalleryKey,
        pageIndex: Int,
        expectedByteCount: Int64,
        expectedSHA256: Data
    ) throws -> DownloadReceiveHandle {
        try beginReceive(
            for: key,
            pageIndex: pageIndex,
            expectedByteCount: expectedByteCount,
            expectedSHA256: Optional(expectedSHA256)
        )
    }

    /// Starts a streamed receive when the sender computes the digest during
    /// the same read that supplies network chunks. The expected digest is
    /// supplied to `finishReceive` after the raw bytes have arrived.
    public func beginReceive(
        for key: GalleryKey,
        pageIndex: Int,
        expectedByteCount: Int64
    ) throws -> DownloadReceiveHandle {
        try beginReceive(
            for: key,
            pageIndex: pageIndex,
            expectedByteCount: expectedByteCount,
            expectedSHA256: nil
        )
    }

    private func beginReceive(
        for key: GalleryKey,
        pageIndex: Int,
        expectedByteCount: Int64,
        expectedSHA256: Data?
    ) throws -> DownloadReceiveHandle {
        guard expectedByteCount > 0,
              expectedByteCount <= 256 * 1024 * 1024,
              expectedSHA256.map({ $0.count == SHA256.Digest.byteCount }) ?? true else {
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

    public func finishReceive(_ handle: DownloadReceiveHandle) async throws -> DownloadReceiveResult {
        try await finishReceive(handle, expectedSHA256: nil)
    }

    public func finishReceive(
        _ handle: DownloadReceiveHandle,
        expectedSHA256: Data,
        updateIndex: Bool = true
    ) async throws -> DownloadReceiveResult {
        try await finishReceive(
            handle,
            expectedSHA256: Optional(expectedSHA256),
            updateIndex: updateIndex
        )
    }

    private func finishReceive(
        _ handle: DownloadReceiveHandle,
        expectedSHA256 suppliedSHA256: Data?,
        updateIndex: Bool = true
    ) async throws -> DownloadReceiveResult {
        guard let receiving = receivingPages.removeValue(forKey: handle.id) else {
            throw DownloadReceiveError.unknownHandle
        }
        defer { try? receiving.handle.close() }

        guard receiving.receivedByteCount == receiving.expectedByteCount else {
            try? FileManager.default.removeItem(at: receiving.temporaryURL)
            throw DownloadReceiveError.byteCountMismatch
        }
        guard let expectedSHA256 = suppliedSHA256 ?? receiving.expectedSHA256,
              expectedSHA256.count == SHA256.Digest.byteCount,
              Data(receiving.hasher.finalize()) == expectedSHA256 else {
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
            if updateIndex {
                await indexSink?.upsertMediaPage(
                    key: receiving.key,
                    pageIndex: receiving.pageIndex,
                    byteCount: receiving.expectedByteCount
                )
            }
            return .alreadyPresent(finalURL)
        }
        do {
            if fileManager.fileExists(atPath: finalURL.path) {
                try fileManager.removeItem(at: finalURL)
            }
            try fileManager.moveItem(at: receiving.temporaryURL, to: finalURL)
            if updateIndex {
                await indexSink?.upsertMediaPage(
                    key: receiving.key,
                    pageIndex: receiving.pageIndex,
                    byteCount: receiving.expectedByteCount
                )
            }
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

    /// Removes a page committed by an interrupted gallery transaction only
    /// when it still matches the bytes received in that transaction. This
    /// prevents rollback from deleting a valid concurrent download write.
    public func rollbackReceivedPage(
        for key: GalleryKey,
        pageIndex: Int,
        sha256: Data
    ) async throws {
        guard sha256.count == SHA256.Digest.byteCount else { return }
        let url = finalURL(for: key, pageIndex: pageIndex)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = SHA256()
            while let chunk = try handle.read(upToCount: 64 * 1024), chunk.isEmpty == false {
                hasher.update(data: chunk)
            }
            guard Data(hasher.finalize()) == sha256 else { return }
            try FileManager.default.removeItem(at: url)
            await indexSink?.removeMediaPage(key: key, pageIndex: pageIndex)
        } catch {
            throw EHError.storageFailed(error.localizedDescription)
        }
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
    public func write(_ data: Data, for key: GalleryKey, pageIndex: Int) async throws -> URL {
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
                await indexSink?.upsertMediaPage(key: key, pageIndex: pageIndex, byteCount: Int64(data.count))
                return finalURL
            }
            let partialURL = finalURL.appendingPathExtension("part")
            try data.write(to: partialURL, options: .atomic)
            if fileManager.fileExists(atPath: finalURL.path) {
                try fileManager.removeItem(at: finalURL)
            }
            try fileManager.moveItem(at: partialURL, to: finalURL)
            await indexSink?.upsertMediaPage(key: key, pageIndex: pageIndex, byteCount: Int64(data.count))
            return finalURL
        } catch let error as EHError {
            throw error
        } catch {
            throw EHError.storageFailed(error.localizedDescription)
        }
    }

    @discardableResult
    public func importFile(at sourceURL: URL, for key: GalleryKey, pageIndex: Int) async throws -> URL {
        try await importFileResult(at: sourceURL, for: key, pageIndex: pageIndex).url
    }

    public func importFileResult(
        at sourceURL: URL,
        for key: GalleryKey,
        pageIndex: Int,
        knownSHA256: Data? = nil,
        updateIndex: Bool = true
    ) async throws -> DownloadImportResult {
        guard FileManager.default.fileExists(atPath: sourceURL.path),
              DownloadMediaValidator.kind(of: sourceURL) != nil else {
            throw EHError.parsingFailed(String(localized: "恢复文件不是有效图片或视频"))
        }
        if hasSufficientFreeSpace == false {
            throw EHError.diskSpaceLow
        }
        let sourceSHA256: Data
        if let knownSHA256 {
            guard knownSHA256.count == SHA256.Digest.byteCount else {
                throw EHError.parsingFailed(String(localized: "恢复文件的完整性信息无效"))
            }
            sourceSHA256 = knownSHA256
        } else {
            sourceSHA256 = try sha256(of: sourceURL)
        }

        var directory = directory(for: key)
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            var directoryValues = URLResourceValues()
            directoryValues.isExcludedFromBackup = true
            try? directory.setResourceValues(directoryValues)

            let finalURL = finalURL(for: key, pageIndex: pageIndex)
            if fileManager.fileExists(atPath: finalURL.path),
               DownloadMediaValidator.kind(of: finalURL) != nil {
                let byteCount = (try? finalURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                if updateIndex, byteCount > 0 {
                    await indexSink?.upsertMediaPage(key: key, pageIndex: pageIndex, byteCount: byteCount)
                }
                return .alreadyPresent(finalURL)
            }
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
            if fileManager.fileExists(atPath: finalURL.path),
               DownloadMediaValidator.kind(of: finalURL) != nil {
                try? fileManager.removeItem(at: partialURL)
                let byteCount = (try? finalURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                if updateIndex, byteCount > 0 {
                    await indexSink?.upsertMediaPage(key: key, pageIndex: pageIndex, byteCount: byteCount)
                }
                return .alreadyPresent(finalURL)
            }
            if fileManager.fileExists(atPath: finalURL.path) {
                try fileManager.removeItem(at: finalURL)
            }
            try fileManager.moveItem(at: partialURL, to: finalURL)
            if updateIndex {
                await indexSink?.upsertMediaPage(
                    key: key,
                    pageIndex: pageIndex,
                    byteCount: Int64(try finalURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
                )
            }
            return .imported(finalURL, sha256: sourceSHA256)
        } catch let error as EHError {
            throw error
        } catch {
            throw EHError.storageFailed(error.localizedDescription)
        }
    }

    public func remove(_ key: GalleryKey) async throws {
        let directory = directory(for: key)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            await indexSink?.removeMedia(for: key)
            return
        }
        do {
            try FileManager.default.removeItem(at: directory)
            await indexSink?.removeMedia(for: key)
        } catch {
            throw EHError.storageFailed(error.localizedDescription)
        }
    }

    private func sha256(of url: URL) throws -> Data {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = SHA256()
            while let chunk = try handle.read(upToCount: 1 * 1_024 * 1_024), chunk.isEmpty == false {
                try Task.checkCancellation()
                hasher.update(data: chunk)
            }
            return Data(hasher.finalize())
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw EHError.storageFailed(error.localizedDescription)
        }
    }

    private func directory(for key: GalleryKey) -> URL {
        Self.directory(for: key, root: root)
    }

    private static func directory(for key: GalleryKey, root: URL) -> URL {
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
