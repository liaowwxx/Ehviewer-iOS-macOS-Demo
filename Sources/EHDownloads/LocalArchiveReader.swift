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

public enum LocalArchiveFormat: String, CaseIterable, Codable, Sendable {
    case zip
    case sevenZip = "7z"
    case rar
    case other

    public init(url: URL) {
        switch url.pathExtension.lowercased() {
        case "zip": self = .zip
        case "7z": self = .sevenZip
        case "rar", "cbr": self = .rar
        default: self = .other
        }
    }

    public var title: String {
        switch self {
        case .zip: "ZIP"
        case .sevenZip: "7z"
        case .rar: "RAR"
        case .other: String(localized: "归档")
        }
    }
}

public struct LocalArchiveEntry: Identifiable, Hashable, Sendable {
    public let path: String
    public let size: Int64
    public let isDirectory: Bool

    public var id: String { path }

    public var isImage: Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return [
            "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "avif", "bmp",
            "mp4", "m4v", "mov", "webm"
        ].contains(ext)
    }

    public init(path: String, size: Int64, isDirectory: Bool) {
        self.path = path
        self.size = size
        self.isDirectory = isDirectory
    }
}

public struct LocalArchiveDocument: Identifiable, Hashable, Sendable {
    public let url: URL
    public let format: LocalArchiveFormat
    public let entries: [LocalArchiveEntry]

    public var id: URL { url }
    public var imageEntries: [LocalArchiveEntry] { entries.filter { $0.isImage && !$0.isDirectory } }

    public init(url: URL, format: LocalArchiveFormat, entries: [LocalArchiveEntry]) {
        self.url = url
        self.format = format
        self.entries = entries
    }
}

public enum LocalArchiveReader {
    private static let eof = 1
    private static let readBufferSize = 64 * 1024
    private static let defaultEntryLimit = 256 * 1024 * 1024

    public static func open(_ url: URL) throws -> LocalArchiveDocument {
        let entries = try withSecurityScope(for: url) {
            try listEntries(in: url)
        }
        guard entries.contains(where: { !$0.isDirectory }) else {
            throw EHError.parsingFailed(String(localized: "归档中没有可阅读的文件"))
        }
        return LocalArchiveDocument(url: url, format: LocalArchiveFormat(url: url), entries: entries)
    }

    public static func readData(
        for entry: LocalArchiveEntry,
        in document: LocalArchiveDocument,
        maxBytes: Int64 = 256 * 1024 * 1024
    ) throws -> Data {
        guard entry.isDirectory == false else { return Data() }
        guard entry.size <= maxBytes else {
            throw EHError.storageFailed(String(localized: "归档条目超过 \(maxBytes / 1_024 / 1_024) MiB"))
        }

        return try withSecurityScope(for: document.url) {
            guard let reader = eh_archive_open(document.url.path) else {
                throw EHError.parsingFailed(String(localized: "无法打开 \(document.format.title) 归档"))
            }
            defer { eh_archive_close(reader) }

            while true {
                var pathPointer: UnsafePointer<CChar>?
                var size: UInt64 = 0
                var isDirectory: Int32 = 0
                let result = eh_archive_next(reader, &pathPointer, &size, &isDirectory)
                if result == eof { break }
                guard result == 0 else {
                    throw archiveError(reader)
                }
                let path = pathPointer.map { String(cString: $0) } ?? ""
                if path == entry.path {
                    var data = Data(capacity: Int(min(size, UInt64(maxBytes))))
                    var buffer = [UInt8](repeating: 0, count: readBufferSize)
                    while true {
                        let count = buffer.withUnsafeMutableBytes { bytes in
                            eh_archive_read(reader, bytes.baseAddress, bytes.count)
                        }
                        if count == 0 { break }
                        guard count > 0 else { throw archiveError(reader) }
                        data.append(buffer, count: Int(count))
                        guard Int64(data.count) <= maxBytes else {
                            throw EHError.storageFailed(String(localized: "归档条目超过 \(maxBytes / 1_024 / 1_024) MiB"))
                        }
                    }
                    return data
                }
                guard eh_archive_skip(reader) == 0 else { throw archiveError(reader) }
            }

            throw EHError.notFound
        }
    }

    private static func listEntries(in url: URL) throws -> [LocalArchiveEntry] {
        guard let reader = eh_archive_open(url.path) else {
            throw EHError.parsingFailed(String(localized: "无法打开 \(LocalArchiveFormat(url: url).title) 归档"))
        }
        defer { eh_archive_close(reader) }

        var entries: [LocalArchiveEntry] = []
        while true {
            var pathPointer: UnsafePointer<CChar>?
            var size: UInt64 = 0
            var isDirectory: Int32 = 0
            let result = eh_archive_next(reader, &pathPointer, &size, &isDirectory)
            if result == eof { break }
            guard result == 0 else { throw archiveError(reader) }
            let path = pathPointer.map { String(cString: $0) } ?? ""
            guard path.isEmpty == false else {
                _ = eh_archive_skip(reader)
                continue
            }
            entries.append(LocalArchiveEntry(path: path, size: Int64(min(size, UInt64(Int64.max))), isDirectory: isDirectory != 0))
            guard eh_archive_skip(reader) == 0 else { throw archiveError(reader) }
        }
        return entries.sorted { lhs, rhs in
            lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
    }

    private static func archiveError(_ reader: OpaquePointer) -> EHError {
        let message = eh_archive_error(reader).map { String(cString: $0) } ?? String(localized: "读取归档失败")
        return .parsingFailed(message)
    }

    private static func withSecurityScope<T>(for url: URL, _ body: () throws -> T) rethrows -> T {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }
        return try body()
    }
}
