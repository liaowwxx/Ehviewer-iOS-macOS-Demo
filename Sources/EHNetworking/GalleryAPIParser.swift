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

public struct GalleryAPIParser: Sendable {
    public init() {}

    public func parse(data: Data, site: SiteMode) throws -> [GallerySummary] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EHError.parsingFailed(String(localized: "画廊 API 响应不是 JSON"))
        }
        if let error = object["error"] as? String, error.isEmpty == false {
            throw EHError.parsingFailed(error)
        }
        guard let metadata = object["gmetadata"] as? [[String: Any]] else {
            throw EHError.parsingFailed(String(localized: "画廊 API 响应缺少 gmetadata"))
        }

        return metadata.compactMap { item in
            guard let gid = Self.intValue(item["gid"]),
                  let token = item["token"] as? String,
                  token.isEmpty == false,
                  item["error"] == nil else { return nil }

            let title = (item["title"] as? String)?.nilIfEmpty ?? "Gallery \(gid)"
            let japaneseTitle = (item["title_jpn"] as? String)?.nilIfEmpty
            let thumbnailURL = Self.urlValue(item["thumb"], site: site)
            let category = (item["category"] as? String)?.nilIfEmpty
            let pageCount = Self.intValue(item["filecount"]).flatMap(Int.init(exactly:))
            let postedAt = (item["posted"] as? String).flatMap(Self.date(from:))
            let rating = Self.doubleValue(item["rating"])
            let uploader = (item["uploader"] as? String)?.nilIfEmpty
            let tags = item["tags"] as? [String] ?? []

            return GallerySummary(
                key: GalleryKey(gid: gid, token: token),
                title: title,
                japaneseTitle: japaneseTitle,
                thumbnailURL: thumbnailURL,
                category: category,
                pageCount: pageCount,
                postedAt: postedAt,
                rating: rating,
                uploader: uploader,
                tags: tags
            )
        }
    }

    private static func intValue(_ value: Any?) -> Int64? {
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String {
            return Int64(value.replacingOccurrences(of: ",", with: ""))
        }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func urlValue(_ value: Any?, site: SiteMode) -> URL? {
        guard let value = value as? String else { return nil }
        return URL(string: value, relativeTo: URL(string: "https://\(site.host)/"))?.absoluteURL
    }

    private static func date(from value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
