import Foundation
import EHDomain

public struct GalleryAPIParser: Sendable {
    public init() {}

    public func parse(data: Data, site: SiteMode) throws -> [GallerySummary] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EHError.parsingFailed("画廊 API 响应不是 JSON")
        }
        if let error = object["error"] as? String, error.isEmpty == false {
            throw EHError.parsingFailed(error)
        }
        guard let metadata = object["gmetadata"] as? [[String: Any]] else {
            throw EHError.parsingFailed("画廊 API 响应缺少 gmetadata")
        }

        return metadata.compactMap { item in
            guard let gid = Self.intValue(item["gid"]),
                  let token = item["token"] as? String,
                  token.isEmpty == false,
                  item["error"] == nil else { return nil }

            let title = (item["title"] as? String)?.nilIfEmpty ?? "Gallery \(gid)"
            let secondaryTitle = (item["title_jpn"] as? String)?.nilIfEmpty
            let thumbnailURL = Self.urlValue(item["thumb"], site: site)
            let category = (item["category"] as? String)?.nilIfEmpty
            let pageCount = Self.intValue(item["filecount"]).flatMap(Int.init(exactly:))
            let postedAt = (item["posted"] as? String).flatMap(Self.date(from:))
            let rating = Self.doubleValue(item["rating"])
            let tags = item["tags"] as? [String] ?? []

            return GallerySummary(
                key: GalleryKey(gid: gid, token: token),
                title: title,
                secondaryTitle: secondaryTitle,
                thumbnailURL: thumbnailURL,
                category: category,
                pageCount: pageCount,
                postedAt: postedAt,
                rating: rating,
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
