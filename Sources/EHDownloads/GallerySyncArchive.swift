/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation
import EHArchiveSupport
import EHDomain

public enum GallerySyncArchiveError: LocalizedError, Sendable {
    case archiveTooLarge
    case invalidArchive
    case payloadTooLarge
    case unsupportedVersion(Int)
    case tooManyGalleries
    case invalidGallery
    case cannotCreateArchive(String?)

    public var errorDescription: String? {
        switch self {
        case .archiveTooLarge:
            String(localized: "画廊同步包超过 64 MiB 限制。")
        case .invalidArchive:
            String(localized: "画廊同步包格式无效。")
        case .payloadTooLarge:
            String(localized: "画廊同步包中的数据超过 64 MiB 限制。")
        case .unsupportedVersion(let version):
            String(localized: "不支持的画廊同步包版本：\(version)。")
        case .tooManyGalleries:
            String(localized: "画廊同步包包含的画廊数量超过限制。")
        case .invalidGallery:
            String(localized: "画廊同步包包含无效的画廊标识。")
        case .cannotCreateArchive(let detail):
            detail.map { String(localized: "无法创建画廊同步包：\($0)") }
                ?? String(localized: "无法创建画廊同步包。")
        }
    }
}

/// Reads and writes the deliberately narrow `.ehgallery` ZIP container.
public enum GallerySyncArchive {
    public static let payloadEntryName = "ehviewer-gallery-sync"
    public static let maximumArchiveBytes: Int64 = 64 * 1_024 * 1_024
    public static let maximumPayloadBytes: Int64 = 64 * 1_024 * 1_024
    public static let maximumGalleryCount = 100_000

    private static let archiveEOF = 1
    private static let readBufferSize = 64 * 1_024

    public static func export(_ snapshot: GallerySyncSnapshot, to archiveURL: URL) throws {
        try validate(snapshot)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        guard data.count <= Int(maximumPayloadBytes) else {
            throw GallerySyncArchiveError.payloadTooLarge
        }

        guard let writer = eh_archive_writer_open(archiveURL.path) else {
            throw GallerySyncArchiveError.cannotCreateArchive(nil)
        }
        defer { eh_archive_writer_close(writer) }

        guard eh_archive_writer_begin_file(writer, payloadEntryName, UInt64(data.count)) == 0 else {
            throw GallerySyncArchiveError.cannotCreateArchive(writerError(writer))
        }
        let written = data.withUnsafeBytes { bytes in
            eh_archive_writer_write(writer, bytes.baseAddress, bytes.count)
        }
        guard written == Int64(data.count), eh_archive_writer_end_file(writer) == 0 else {
            throw GallerySyncArchiveError.cannotCreateArchive(writerError(writer))
        }
    }

    public static func read(from archiveURL: URL) throws -> GallerySyncSnapshot {
        let values = try archiveURL.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize, Int64(size) > maximumArchiveBytes {
            throw GallerySyncArchiveError.archiveTooLarge
        }

        guard let reader = eh_archive_open(archiveURL.path) else {
            throw GallerySyncArchiveError.invalidArchive
        }
        defer { eh_archive_close(reader) }

        var payload: Data?
        var entryCount = 0
        while true {
            try Task.checkCancellation()
            var pathPointer: UnsafePointer<CChar>?
            var size: UInt64 = 0
            var isDirectory: Int32 = 0
            let result = eh_archive_next(reader, &pathPointer, &size, &isDirectory)
            if result == archiveEOF { break }
            guard result == 0 else { throw GallerySyncArchiveError.invalidArchive }

            entryCount += 1
            let path = pathPointer.map { String(cString: $0) } ?? ""
            guard entryCount == 1,
                  isDirectory == 0,
                  path == payloadEntryName,
                  size <= UInt64(maximumPayloadBytes) else {
                throw GallerySyncArchiveError.invalidArchive
            }
            payload = try readPayload(from: reader, declaredSize: size)
        }

        guard entryCount == 1, let payload else {
            throw GallerySyncArchiveError.invalidArchive
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot: GallerySyncSnapshot
        do {
            snapshot = try decoder.decode(GallerySyncSnapshot.self, from: payload)
        } catch {
            throw GallerySyncArchiveError.invalidArchive
        }
        try validate(snapshot)
        return snapshot
    }

    private static func readPayload(from reader: OpaquePointer, declaredSize: UInt64) throws -> Data {
        var data = Data(capacity: Int(min(declaredSize, UInt64(maximumPayloadBytes))))
        var buffer = [UInt8](repeating: 0, count: readBufferSize)
        while true {
            try Task.checkCancellation()
            let count = buffer.withUnsafeMutableBytes { bytes in
                eh_archive_read(reader, bytes.baseAddress, bytes.count)
            }
            if count == 0 { break }
            guard count > 0 else { throw GallerySyncArchiveError.invalidArchive }
            data.append(buffer, count: Int(count))
            guard Int64(data.count) <= maximumPayloadBytes else {
                throw GallerySyncArchiveError.payloadTooLarge
            }
        }
        return data
    }

    private static func validate(_ snapshot: GallerySyncSnapshot) throws {
        guard [GallerySyncSnapshot.legacyVersion, GallerySyncSnapshot.currentVersion].contains(snapshot.schemaVersion) else {
            throw GallerySyncArchiveError.unsupportedVersion(snapshot.schemaVersion)
        }
        guard snapshot.galleries.count <= maximumGalleryCount else {
            throw GallerySyncArchiveError.tooManyGalleries
        }
        for record in snapshot.records {
            guard [GallerySyncSnapshot.legacyVersion, GalleryTransferRecord.currentFormatVersion]
                .contains(record.formatVersion) else {
                throw GallerySyncArchiveError.unsupportedVersion(record.formatVersion)
            }
            guard record.dynamic?.key == nil || record.dynamic?.key == record.stable.key else {
                throw GallerySyncArchiveError.invalidGallery
            }
        }
        guard snapshot.galleries.allSatisfy({ $0.key.gid > 0 && $0.key.token.isEmpty == false }) else {
            throw GallerySyncArchiveError.invalidGallery
        }
    }

    private static func writerError(_ writer: OpaquePointer) -> String? {
        eh_archive_writer_error(writer).map { String(cString: $0) }.flatMap { $0.isEmpty ? nil : $0 }
    }
}
