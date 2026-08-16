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

public struct LegacyDownloadArchiveInspection: Sendable {
    public let candidates: [LegacyDownloadCandidate]
    public let invalidItemCount: Int

    public init(candidates: [LegacyDownloadCandidate], invalidItemCount: Int) {
        self.candidates = candidates
        self.invalidItemCount = invalidItemCount
    }
}

public struct LegacyDownloadCandidate: Identifiable, Sendable {
    public let key: GalleryKey
    public let directoryPath: String
    public let declaredPageCount: Int
    public let pageTokens: [Int: String]
    public let images: [LegacyDownloadImageEntry]

    public var id: String { directoryPath }

    public init(
        key: GalleryKey,
        directoryPath: String,
        declaredPageCount: Int,
        pageTokens: [Int: String],
        images: [LegacyDownloadImageEntry]
    ) {
        self.key = key
        self.directoryPath = directoryPath
        self.declaredPageCount = declaredPageCount
        self.pageTokens = pageTokens
        self.images = images
    }
}

public struct LegacyDownloadImageEntry: Hashable, Sendable {
    public let archivePath: String
    public let pageIndex: Int
    public let byteCount: Int64

    public init(archivePath: String, pageIndex: Int, byteCount: Int64) {
        self.archivePath = archivePath
        self.pageIndex = pageIndex
        self.byteCount = byteCount
    }
}

public struct LegacyDownloadPageSelection: Hashable, Sendable {
    public let archivePath: String
    public let key: GalleryKey
    public let pageIndex: Int

    public init(archivePath: String, key: GalleryKey, pageIndex: Int) {
        self.archivePath = archivePath
        self.key = key
        self.pageIndex = pageIndex
    }
}

public struct LegacyExtractedPage: Hashable, Sendable {
    public let fileURL: URL
    public let key: GalleryKey
    public let pageIndex: Int

    public init(fileURL: URL, key: GalleryKey, pageIndex: Int) {
        self.fileURL = fileURL
        self.key = key
        self.pageIndex = pageIndex
    }
}

public struct LegacyDownloadArchiveExtraction: Sendable {
    public let temporaryDirectory: URL
    public let pages: [LegacyExtractedPage]
    public let failedPageCount: Int

    public init(temporaryDirectory: URL, pages: [LegacyExtractedPage], failedPageCount: Int) {
        self.temporaryDirectory = temporaryDirectory
        self.pages = pages
        self.failedPageCount = failedPageCount
    }
}

public enum LegacyDownloadArchive {
    private static let archiveEOF: Int32 = 1
    private static let maximumMetadataBytes = 16 * 1_024 * 1_024
    private static let maximumPageBytes: Int64 = 256 * 1_024 * 1_024
    private static let minimumFreeBytes: Int64 = 1_024 * 1_024 * 1_024
    private static let supportedMediaExtensions = Set([
        "jpg", "jpeg", "png", "gif", "webp",
        "mp4", "webm", "mkv", "mpg", "mpeg"
    ])

    @concurrent
    public static func inspect(_ archiveURL: URL) async throws -> LegacyDownloadArchiveInspection {
        try Task.checkCancellation()
        let didAccess = archiveURL.startAccessingSecurityScopedResource()
        defer { if didAccess { archiveURL.stopAccessingSecurityScopedResource() } }

        guard let reader = eh_archive_open(archiveURL.path) else {
            throw EHError.parsingFailed(String(localized: "无法打开备份压缩包"))
        }
        defer { eh_archive_close(reader) }

        var spiderInfoByDirectory: [String: LegacySpiderInfo] = [:]
        var imagesByDirectory: [String: [LegacyDownloadImageEntry]] = [:]
        var invalidItemCount = 0

        while true {
            try Task.checkCancellation()
            var pathPointer: UnsafePointer<CChar>?
            var size: UInt64 = 0
            var isDirectory: Int32 = 0
            let result = eh_archive_next(reader, &pathPointer, &size, &isDirectory)
            if result == archiveEOF { break }
            guard result == 0 else { throw archiveError(reader) }

            let rawPath = pathPointer.map { String(cString: $0) } ?? ""
            guard isDirectory == 0, let components = safePathComponents(rawPath) else {
                guard eh_archive_skip(reader) == 0 else { throw archiveError(reader) }
                continue
            }

            if components.last == ".ehviewer", let directoryPath = legacyGalleryDirectory(in: components) {
                let data = try readMetadata(reader, maximumBytes: maximumMetadataBytes)
                if let spiderInfo = LegacySpiderInfo(data: data) {
                    spiderInfoByDirectory[directoryPath] = spiderInfo
                } else {
                    invalidItemCount += 1
                }
                guard eh_archive_skip(reader) == 0 else { throw archiveError(reader) }
                continue
            }

            if let (directoryPath, pageIndex) = legacyImageLocation(in: components) {
                let byteCount = Int64(min(size, UInt64(Int64.max)))
                imagesByDirectory[directoryPath, default: []].append(
                    LegacyDownloadImageEntry(
                        archivePath: rawPath,
                        pageIndex: pageIndex,
                        byteCount: byteCount
                    )
                )
            }
            guard eh_archive_skip(reader) == 0 else { throw archiveError(reader) }
        }

        let candidates: [LegacyDownloadCandidate] = spiderInfoByDirectory.map { directoryPath, spiderInfo in
            let images = deduplicatedImages(imagesByDirectory[directoryPath] ?? [])
            return LegacyDownloadCandidate(
                key: spiderInfo.key,
                directoryPath: directoryPath,
                declaredPageCount: spiderInfo.pageCount,
                pageTokens: spiderInfo.pageTokens,
                images: images
            )
        }.sorted { lhs, rhs in
            lhs.directoryPath.localizedStandardCompare(rhs.directoryPath) == .orderedAscending
        }

        return LegacyDownloadArchiveInspection(candidates: candidates, invalidItemCount: invalidItemCount)
    }

    @concurrent
    public static func extractPages(
        from archiveURL: URL,
        selections: [LegacyDownloadPageSelection]
    ) async throws -> LegacyDownloadArchiveExtraction {
        try Task.checkCancellation()
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("EhViewerRestore-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        do {
            let didAccess = archiveURL.startAccessingSecurityScopedResource()
            defer { if didAccess { archiveURL.stopAccessingSecurityScopedResource() } }
            guard let reader = eh_archive_open(archiveURL.path) else {
                throw EHError.parsingFailed(String(localized: "无法重新打开备份压缩包"))
            }
            defer { eh_archive_close(reader) }

            var selectionByPath: [String: LegacyDownloadPageSelection] = [:]
            for selection in selections where selectionByPath[selection.archivePath] == nil {
                selectionByPath[selection.archivePath] = selection
            }
            var extractedPages: [LegacyExtractedPage] = []
            var failedPageCount = 0

            while true {
                try Task.checkCancellation()
                var pathPointer: UnsafePointer<CChar>?
                var size: UInt64 = 0
                var isDirectory: Int32 = 0
                let result = eh_archive_next(reader, &pathPointer, &size, &isDirectory)
                if result == archiveEOF { break }
                guard result == 0 else { throw archiveError(reader) }

                let path = pathPointer.map { String(cString: $0) } ?? ""
                guard isDirectory == 0, let selection = selectionByPath[path] else {
                    guard eh_archive_skip(reader) == 0 else { throw archiveError(reader) }
                    continue
                }

                if size > UInt64(maximumPageBytes) {
                    failedPageCount += 1
                    guard eh_archive_skip(reader) == 0 else { throw archiveError(reader) }
                    continue
                }

                let destination = temporaryDirectory.appendingPathComponent(UUID().uuidString)
                do {
                    try extractCurrentEntry(reader, to: destination, volumeURL: temporaryDirectory)
                    extractedPages.append(
                        LegacyExtractedPage(
                            fileURL: destination,
                            key: selection.key,
                            pageIndex: selection.pageIndex
                        )
                    )
                } catch let error as EHError where error == .diskSpaceLow {
                    throw error
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    failedPageCount += 1
                    try? fileManager.removeItem(at: destination)
                }
                guard eh_archive_skip(reader) == 0 else { throw archiveError(reader) }
            }

            return LegacyDownloadArchiveExtraction(
                temporaryDirectory: temporaryDirectory,
                pages: extractedPages,
                failedPageCount: failedPageCount
            )
        } catch {
            try? fileManager.removeItem(at: temporaryDirectory)
            throw error
        }
    }

    private static func extractCurrentEntry(
        _ reader: OpaquePointer,
        to destination: URL,
        volumeURL: URL
    ) throws {
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw EHError.storageFailed(String(localized: "无法创建恢复临时文件"))
        }
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var totalBytes: Int64 = 0
        var bytesSinceCapacityCheck: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            try Task.checkCancellation()
            let count = buffer.withUnsafeMutableBytes { bytes in
                eh_archive_read(reader, bytes.baseAddress, bytes.count)
            }
            if count == 0 { break }
            guard count > 0 else { throw archiveError(reader) }
            totalBytes += count
            bytesSinceCapacityCheck += count
            guard totalBytes <= maximumPageBytes else {
                throw EHError.storageFailed(String(localized: "归档中的单页图片超过 256 MiB"))
            }
            if bytesSinceCapacityCheck >= 16 * 1_024 * 1_024 {
                bytesSinceCapacityCheck = 0
                if let available = try? volumeURL.resourceValues(
                    forKeys: [.volumeAvailableCapacityForImportantUsageKey]
                ).volumeAvailableCapacityForImportantUsage,
                   available < minimumFreeBytes {
                    throw EHError.diskSpaceLow
                }
            }
            try handle.write(contentsOf: Data(buffer.prefix(Int(count))))
        }
    }

    private static func readMetadata(_ reader: OpaquePointer, maximumBytes: Int) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4 * 1_024)
        while data.count < maximumBytes {
            let count = buffer.withUnsafeMutableBytes { bytes in
                eh_archive_read(reader, bytes.baseAddress, min(bytes.count, maximumBytes - data.count))
            }
            if count == 0 { break }
            guard count > 0 else { throw archiveError(reader) }
            data.append(buffer, count: Int(count))
        }
        return data
    }

    private static func safePathComponents(_ rawPath: String) -> [String]? {
        let normalized = rawPath.replacingOccurrences(of: "\\", with: "/")
        guard normalized.isEmpty == false,
              normalized.hasPrefix("/") == false,
              normalized.unicodeScalars.contains(where: { $0.value == 0 }) == false else { return nil }
        let rawComponents = normalized.split(separator: "/", omittingEmptySubsequences: false)
        guard rawComponents.first?.contains(":") == false else { return nil }

        var components: [String] = []
        for component in rawComponents {
            if component.isEmpty || component == "." { continue }
            guard component != ".." else { return nil }
            components.append(String(component))
        }
        return components.isEmpty ? nil : components
    }

    private static func legacyGalleryDirectory(in components: [String]) -> String? {
        guard components.count >= 3,
              components[components.count - 3] == "download",
              components.count - 3 <= 1 else { return nil }
        return components.dropLast().joined(separator: "/")
    }

    private static func legacyImageLocation(in components: [String]) -> (String, Int)? {
        guard components.count >= 3,
              components[components.count - 3] == "download",
              components.count - 3 <= 1 else { return nil }
        let fileName = components[components.count - 1]
        let fileURL = URL(fileURLWithPath: fileName)
        guard supportedMediaExtensions.contains(fileURL.pathExtension.lowercased()) else { return nil }
        let stem = fileURL.deletingPathExtension().lastPathComponent
        guard stem.count == 8,
              stem.allSatisfy(\.isNumber),
              let pageNumber = Int(stem),
              pageNumber > 0 else { return nil }
        return (components.dropLast().joined(separator: "/"), pageNumber - 1)
    }

    private static func deduplicatedImages(_ images: [LegacyDownloadImageEntry]) -> [LegacyDownloadImageEntry] {
        var seen = Set<Int>()
        return images.sorted { lhs, rhs in
            if lhs.pageIndex == rhs.pageIndex {
                return lhs.archivePath.localizedStandardCompare(rhs.archivePath) == .orderedAscending
            }
            return lhs.pageIndex < rhs.pageIndex
        }.filter { seen.insert($0.pageIndex).inserted }
    }

    private static func archiveError(_ reader: OpaquePointer) -> EHError {
        let message = eh_archive_error(reader).map { String(cString: $0) } ?? String(localized: "读取备份压缩包失败")
        return .parsingFailed(message)
    }
}

private struct LegacySpiderInfo {
    let key: GalleryKey
    let pageCount: Int
    let pageTokens: [Int: String]

    init?(data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let gidIndex: Int
        let tokenIndex: Int
        let pageCountIndex: Int
        if lines.first == "VERSION2" {
            gidIndex = 2
            tokenIndex = 3
            pageCountIndex = 7
        } else if lines.first?.hasPrefix("VERSION") == true {
            return nil
        } else {
            gidIndex = 1
            tokenIndex = 2
            pageCountIndex = 6
        }
        guard lines.indices.contains(gidIndex),
              lines.indices.contains(tokenIndex),
              lines.indices.contains(pageCountIndex),
              let gid = Int64(lines[gidIndex]),
              gid > 0,
              lines[tokenIndex].isEmpty == false,
              lines[tokenIndex].count <= 1_024,
              let pageCount = Int(lines[pageCountIndex]),
              (1...100_000).contains(pageCount) else { return nil }
        key = GalleryKey(gid: gid, token: lines[tokenIndex])
        self.pageCount = pageCount
        var parsedTokens: [Int: String] = [:]
        for line in lines.dropFirst(pageCountIndex + 1) {
            guard let separator = line.firstIndex(of: " "),
                  let index = Int(line[..<separator]),
                  (0..<pageCount).contains(index) else { continue }
            let token = String(line[line.index(after: separator)...])
            guard token.isEmpty == false, token.count <= 1_024, token != "failed" else { continue }
            parsedTokens[index] = token
        }
        pageTokens = parsedTokens
    }
}
