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
import ImageIO
import EHDomain

public enum DownloadMediaKind: Sendable {
    case image
    case video
}

public enum DownloadMediaValidator {
    public static func kind(of url: URL) -> DownloadMediaKind? {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           CGImageSourceGetCount(source) > 0 {
            return .image
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 12) else { return nil }
        return kind(of: data)
    }

    public static func fileExtension(of url: URL) -> String? {
        guard let kind = kind(of: url) else { return nil }
        switch kind {
        case .image:
            return "jpg"
        case .video:
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            guard let data = try? handle.read(upToCount: 12) else { return nil }
            let bytes = [UInt8](data.prefix(12))
            if bytes.count >= 8,
               bytes[4] == 0x66, bytes[5] == 0x74, bytes[6] == 0x79, bytes[7] == 0x70 {
                return "mp4"
            }
            if bytes.count >= 4, bytes[0...3].elementsEqual([0x1A, 0x45, 0xDF, 0xA3]) {
                return "webm"
            }
            return "mpg"
        }
    }

    public static func kind(of data: Data) -> DownloadMediaKind? {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           CGImageSourceGetCount(source) > 0 {
            return .image
        }
        return hasSupportedVideoSignature(data) ? .video : nil
    }

    public static func validate(_ data: Data) throws {
        guard kind(of: data) != nil else {
            throw EHError.parsingFailed("下载结果不是有效图片或视频")
        }
    }

    private static func hasSupportedVideoSignature(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(12))
        guard bytes.count >= 4 else { return false }

        if bytes.count >= 8,
           bytes[4] == 0x66, bytes[5] == 0x74, bytes[6] == 0x79, bytes[7] == 0x70 {
            return true
        }
        if bytes[0...3].elementsEqual([0x1A, 0x45, 0xDF, 0xA3]) {
            return true
        }
        return bytes[0...3].elementsEqual([0x00, 0x00, 0x01, 0xBA])
    }
}
