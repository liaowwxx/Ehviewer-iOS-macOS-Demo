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

public enum GallerySummaryResponseStatus: Hashable, Sendable {
    case success
    case apiError(String)
    case missingResponse
    case invalidResponse(String)

    public var hasUsableResponse: Bool {
        if case .success = self { return true }
        return false
    }

    public var shouldStopRefresh: Bool {
        guard case let .apiError(message) = self else { return false }
        let normalized = message.localizedLowercase
        return normalized.contains("rate")
            || normalized.contains("limit")
            || normalized.contains("bandwidth")
            || normalized.contains("login")
            || normalized.contains("access")
            || normalized.contains("auth")
    }
}

public struct GallerySummaryResponse: Hashable, Sendable {
    public let key: GalleryKey
    public let summary: GallerySummary?
    public let status: GallerySummaryResponseStatus

    public init(
        key: GalleryKey,
        summary: GallerySummary? = nil,
        status: GallerySummaryResponseStatus
    ) {
        self.key = key
        self.summary = summary
        self.status = status
    }
}

public struct GallerySummaryBatchResult: Hashable, Sendable {
    public let responses: [GallerySummaryResponse]

    public init(responses: [GallerySummaryResponse]) {
        self.responses = responses
    }

    public var summaries: [GallerySummary] {
        responses.compactMap(\.summary)
    }

    public var hasBlockingResponse: Bool {
        responses.contains { $0.status.shouldStopRefresh }
    }
}

public struct GalleryAPIParser: Sendable {
    public init() {}

    public func parse(data: Data, site: SiteMode) throws -> [GallerySummary] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metadata = object["gmetadata"] as? [[String: Any]] else {
            throw EHError.parsingFailed(String(localized: "画廊 API 响应缺少 gmetadata"))
        }
        let keys = Set(metadata.compactMap { item -> GalleryKey? in
            guard let gid = Self.intValue(item["gid"]),
                  let token = item["token"] as? String,
                  token.isEmpty == false else { return nil }
            return GalleryKey(gid: gid, token: token)
        })
        return try parseBatch(data: data, requestedKeys: keys, site: site).summaries
    }

    /// Parses a gdata response without discarding per-gallery errors or
    /// galleries omitted by the server. The caller receives one response for
    /// every requested key, so a partial response can be retried precisely.
    public func parseBatch(
        data: Data,
        requestedKeys: Set<GalleryKey>,
        site: SiteMode
    ) throws -> GallerySummaryBatchResult {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EHError.parsingFailed(String(localized: "画廊 API 响应不是 JSON"))
        }
        if let error = object["error"] as? String, error.isEmpty == false {
            throw EHError.parsingFailed(error)
        }
        guard let metadata = object["gmetadata"] as? [[String: Any]] else {
            throw EHError.parsingFailed(String(localized: "画廊 API 响应缺少 gmetadata"))
        }

        var responseByKey: [GalleryKey: GallerySummaryResponse] = [:]
        for item in metadata {
            guard let gid = Self.intValue(item["gid"]),
                  let token = item["token"] as? String,
                  token.isEmpty == false else { continue }
            let key = GalleryKey(gid: gid, token: token)
            guard requestedKeys.isEmpty || requestedKeys.contains(key) else { continue }
            if let error = item["error"] as? String, error.isEmpty == false {
                responseByKey[key] = GallerySummaryResponse(
                    key: key,
                    status: .apiError(error)
                )
                continue
            }
            guard let summary = Self.parseSummary(item, key: key, site: site) else {
                responseByKey[key] = GallerySummaryResponse(
                    key: key,
                    status: .invalidResponse(String(localized: "画廊字段解析失败"))
                )
                continue
            }
            responseByKey[key] = GallerySummaryResponse(
                key: key,
                summary: summary,
                status: .success
            )
        }

        let keys: Set<GalleryKey> = requestedKeys.isEmpty
            ? Set(responseByKey.keys)
            : requestedKeys
        return GallerySummaryBatchResult(
            responses: keys.sorted { $0.id < $1.id }.map { key in
                responseByKey[key] ?? GallerySummaryResponse(key: key, status: .missingResponse)
            }
        )
    }

    private static func parseSummary(
        _ item: [String: Any],
        key: GalleryKey,
        site: SiteMode
    ) -> GallerySummary? {
        let title = stringField(item, key: "title")
        let japaneseTitle = stringField(item, key: "title_jpn")
        let category = stringField(item, key: "category")
        let uploader = stringField(item, key: "uploader")
        let tags = tagsField(item, key: "tags")
        let pageCount = integerField(item, key: "filecount")
        let postedAt = dateField(item, key: "posted")
        let thumbnailURL = urlField(item, key: "thumb", site: site)
        let rating = doubleField(item, key: "rating")
        let ratingCount = integerField(item, key: "rating_count")

        var completeness = GalleryMetadataCompleteness(
            title: title.state,
            japaneseTitle: japaneseTitle.state,
            authors: tags.state == .notLoaded
                ? .notLoaded
                : (StableGalleryMetadataSnapshot.authors(from: tags.value).isEmpty ? .loadedEmpty : .loadedWithValue),
            uploader: uploader.state,
            tags: tags.state,
            category: category.state,
            pageCount: pageCount.state,
            postedAt: postedAt.state,
            thumbnailURL: thumbnailURL.state,
            rating: rating.state,
            ratingCount: ratingCount.state
        )
        // gdata does not resolve these fields. They must remain unresolved so
        // the caller can decide whether a detail-only fallback is needed.
        completeness.language = .notLoaded
        completeness.fileSize = .notLoaded
        completeness.description = .notLoaded
        completeness.externalURL = .notLoaded
        completeness.pages = .notLoaded

        return GallerySummary(
            key: key,
            title: title.value ?? "",
            japaneseTitle: japaneseTitle.value,
            thumbnailURL: thumbnailURL.value,
            category: category.value,
            pageCount: pageCount.value,
            postedAt: postedAt.value,
            rating: rating.value,
            ratingCount: ratingCount.value,
            uploader: uploader.value,
            tags: tags.value,
            metadataCompleteness: completeness
        )
    }

    private static func stringField(
        _ item: [String: Any],
        key: String
    ) -> (value: String?, state: GalleryFieldState) {
        guard item.keys.contains(key) else { return (nil, .notLoaded) }
        guard let raw = item[key] else { return (nil, .loadedEmpty) }
        if raw is NSNull { return (nil, .loadedEmpty) }
        guard let value = raw as? String else { return (nil, .notLoaded) }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (nil, .loadedEmpty) : (value, .loadedWithValue)
    }

    private static func tagsField(
        _ item: [String: Any],
        key: String
    ) -> (value: [String], state: GalleryFieldState) {
        guard item.keys.contains(key) else { return ([], .notLoaded) }
        if item[key] is NSNull { return ([], .loadedEmpty) }
        guard let tags = item[key] as? [String] else { return ([], .notLoaded) }
        return tags.isEmpty ? ([], .loadedEmpty) : (tags, .loadedWithValue)
    }

    private static func integerField(
        _ item: [String: Any],
        key: String
    ) -> (value: Int?, state: GalleryFieldState) {
        guard item.keys.contains(key) else { return (nil, .notLoaded) }
        if item[key] is NSNull { return (nil, .loadedEmpty) }
        guard let value = intValue(item[key]), value >= 0,
              let integer = Int(exactly: value) else { return (nil, .notLoaded) }
        return (integer, .loadedWithValue)
    }

    private static func doubleField(
        _ item: [String: Any],
        key: String
    ) -> (value: Double?, state: GalleryFieldState) {
        guard item.keys.contains(key) else { return (nil, .notLoaded) }
        if item[key] is NSNull { return (nil, .loadedEmpty) }
        guard let value = doubleValue(item[key]), value.isFinite else { return (nil, .notLoaded) }
        return (value, .loadedWithValue)
    }

    private static func dateField(
        _ item: [String: Any],
        key: String
    ) -> (value: Date?, state: GalleryFieldState) {
        guard item.keys.contains(key) else { return (nil, .notLoaded) }
        if item[key] is NSNull { return (nil, .loadedEmpty) }
        if let value = item[key] as? String,
           value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (nil, .loadedEmpty)
        }
        guard let date = dateValue(item[key]) else { return (nil, .notLoaded) }
        return (date, .loadedWithValue)
    }

    private static func urlField(
        _ item: [String: Any],
        key: String,
        site: SiteMode
    ) -> (value: URL?, state: GalleryFieldState) {
        guard item.keys.contains(key) else { return (nil, .notLoaded) }
        if item[key] is NSNull { return (nil, .loadedEmpty) }
        guard let raw = item[key] as? String else { return (nil, .notLoaded) }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return (nil, .loadedEmpty) }
        guard let url = URL(string: trimmed, relativeTo: URL(string: "https://\(site.host)/"))?.absoluteURL else {
            return (nil, .notLoaded)
        }
        return (url, .loadedWithValue)
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

    private static func dateValue(_ value: Any?) -> Date? {
        if let value = value as? NSNumber {
            return Date(timeIntervalSince1970: value.doubleValue)
        }
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let timestamp = Double(trimmed) {
            return Date(timeIntervalSince1970: timestamp)
        }
        return date(from: trimmed)
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
