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
import EHArchiveSupport
import EHDomain

public struct DownloadArchiveExportItem: Sendable, Hashable {
    public let key: GalleryKey
    public let title: String
    public let totalPageCount: Int
    public let pageTokens: [Int: String]

    public init(key: GalleryKey, title: String, totalPageCount: Int, pageTokens: [Int: String]) {
        self.key = key
        self.title = title
        self.totalPageCount = totalPageCount
        self.pageTokens = pageTokens
    }
}

public struct DownloadArchiveExportProgress: Sendable, Hashable {
    public let completedBytes: Int64
    public let totalBytes: Int64
    public let completedFiles: Int
    public let totalFiles: Int
    public let currentTitle: String?

    public var fraction: Double {
        guard totalBytes > 0 else {
            guard totalFiles > 0 else { return 1 }
            return min(1, Double(completedFiles) / Double(totalFiles))
        }
        return min(1, max(0, Double(completedBytes) / Double(totalBytes)))
    }

    public init(
        completedBytes: Int64,
        totalBytes: Int64,
        completedFiles: Int,
        totalFiles: Int,
        currentTitle: String?
    ) {
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.completedFiles = completedFiles
        self.totalFiles = totalFiles
        self.currentTitle = currentTitle
    }
}

public enum DownloadArchiveExporter {
    public typealias ProgressHandler = @Sendable (DownloadArchiveExportProgress) async -> Void

    private static let bufferSize = 64 * 1_024

    public static func export(
        items: [DownloadArchiveExportItem],
        files: DownloadFileStore,
        to archiveURL: URL,
        progress: ProgressHandler? = nil
    ) async throws -> DownloadArchiveExportProgress {
        try Task.checkCancellation()

        let prepared = try await prepare(items: items, files: files)
        let totalBytes = prepared.reduce(0) { $0 + $1.entry.byteCount }
        let totalFiles = prepared.count
        var currentProgress = DownloadArchiveExportProgress(
            completedBytes: 0,
            totalBytes: totalBytes,
            completedFiles: 0,
            totalFiles: totalFiles,
            currentTitle: nil
        )
        await progress?(currentProgress)

        guard let writer = eh_archive_writer_open(archiveURL.path) else {
            throw EHError.storageFailed("无法创建下载压缩包")
        }
        defer { eh_archive_writer_close(writer) }

        var completedBytes: Int64 = 0
        var completedFiles = 0
        var currentDirectory: String?

        for item in prepared {
            try Task.checkCancellation()
            if currentDirectory != item.directory {
                let metadataPath = "\(item.directory)/.ehviewer"
                let metadata = metadata(for: item)
                try writeData(metadata, to: metadataPath, writer: writer)
                currentDirectory = item.directory
            }

            let archivePath = "\(item.directory)/\(String(format: "%08d", item.entry.pageIndex + 1)).\(item.entry.fileExtension)"
            try beginFile(archivePath, size: item.entry.byteCount, writer: writer)
            let handle = try FileHandle(forReadingFrom: item.entry.fileURL)
            defer { try? handle.close() }

            var fileBytes: Int64 = 0
            while true {
                try Task.checkCancellation()
                guard let data = try handle.read(upToCount: bufferSize), data.isEmpty == false else { break }
                try writeData(data, writer: writer)
                fileBytes += Int64(data.count)
                currentProgress = DownloadArchiveExportProgress(
                    completedBytes: min(totalBytes, completedBytes + fileBytes),
                    totalBytes: totalBytes,
                    completedFiles: completedFiles,
                    totalFiles: totalFiles,
                    currentTitle: item.title
                )
                await progress?(currentProgress)
            }
            guard fileBytes == item.entry.byteCount else {
                throw EHError.storageFailed("下载文件在导出过程中发生变化")
            }
            guard eh_archive_writer_end_file(writer) == 0 else {
                throw writerError(writer, operation: "结束文件")
            }
            completedBytes += item.entry.byteCount
            completedFiles += 1
            currentProgress = DownloadArchiveExportProgress(
                completedBytes: completedBytes,
                totalBytes: totalBytes,
                completedFiles: completedFiles,
                totalFiles: totalFiles,
                currentTitle: item.title
            )
            await progress?(currentProgress)
        }

        return currentProgress
    }

    private struct PreparedEntry: Sendable {
        let key: GalleryKey
        let directory: String
        let title: String
        let totalPageCount: Int
        let pageTokens: [Int: String]
        let entry: DownloadFileExportEntry
    }

    private static func prepare(
        items: [DownloadArchiveExportItem],
        files: DownloadFileStore
    ) async throws -> [PreparedEntry] {
        var prepared: [PreparedEntry] = []
        var usedDirectories = Set<String>()

        for item in items.sorted(by: { $0.key.id < $1.key.id }) {
            try Task.checkCancellation()
            let directory = uniqueDirectory(
                base: archiveDirectoryName(for: item),
                used: &usedDirectories
            )
            let pageCount = max(1, min(100_000, item.totalPageCount))
            for pageIndex in 0..<pageCount {
                try Task.checkCancellation()
                guard let entry = await files.exportEntry(for: item.key, pageIndex: pageIndex) else { continue }
                prepared.append(
                    PreparedEntry(
                        key: item.key,
                        directory: directory,
                        title: item.title,
                        totalPageCount: pageCount,
                        pageTokens: item.pageTokens,
                        entry: entry
                    )
                )
            }
        }
        return prepared
    }

    private static func metadata(for item: PreparedEntry) -> Data {
        var lines = [
            "VERSION2",
            "",
            String(item.key.gid),
            item.key.token,
            "",
            "",
            "",
            String(item.totalPageCount)
        ]
        for index in 0..<item.totalPageCount {
            lines.append("\(index) \(item.pageTokens[index] ?? "failed")")
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    private static func archiveDirectoryName(for item: DownloadArchiveExportItem) -> String {
        let title = item.title
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTitle = title.isEmpty ? "Gallery" : String(title.prefix(80))
        let token = String(item.key.token.prefix(24)).map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "_"
        }
        return "download/\(item.key.gid)-\(String(token))-\(safeTitle)"
    }

    private static func uniqueDirectory(base: String, used: inout Set<String>) -> String {
        guard used.insert(base).inserted else {
            var suffix = 2
            while used.contains("\(base)-\(suffix)") { suffix += 1 }
            let result = "\(base)-\(suffix)"
            used.insert(result)
            return result
        }
        return base
    }

    private static func writeData(_ data: Data, to path: String? = nil, writer: OpaquePointer) throws {
        if let path {
            try beginFile(path, size: Int64(data.count), writer: writer)
        }
        let written = data.withUnsafeBytes { bytes in
            eh_archive_writer_write(writer, bytes.baseAddress, bytes.count)
        }
        guard written == Int64(data.count) else { throw writerError(writer, operation: "写入数据") }
        if path != nil, eh_archive_writer_end_file(writer) != 0 {
            throw writerError(writer, operation: "结束文件")
        }
    }

    private static func beginFile(_ path: String, size: Int64, writer: OpaquePointer) throws {
        guard eh_archive_writer_begin_file(writer, path, UInt64(size)) == 0 else {
            throw writerError(writer, operation: "创建条目 \(path)")
        }
    }

    private static func writerError(_ writer: OpaquePointer, operation: String) -> EHError {
        let detail = eh_archive_writer_error(writer).map { String(cString: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        return .storageFailed(detail.map { "\(operation)：\($0)" } ?? "\(operation)失败")
    }
}
