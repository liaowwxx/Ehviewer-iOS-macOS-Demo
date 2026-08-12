import Foundation
import EHDomain
import SwiftSoup

public struct AdvancedHTMLParser: Sendable {
    public init() {}

    public func parseTorrents(data: Data, site: SiteMode) throws -> [TorrentDescriptor] {
        let html = String(decoding: data, as: UTF8.self)
        let document = try SwiftSoup.parse(html)
        return try document.select("form").compactMap { form in
            guard let link = try form.select("a[href]").first() else { return nil }
            let name = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.isEmpty == false else { return nil }
            let posted: String?
            if let postedLabel = try form.select("span").first(where: { try $0.text().contains("Posted:") }) {
                posted = try postedLabel.nextElementSibling()?.text().trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                posted = nil
            }
            guard let url = URL(string: try link.attr("href"), relativeTo: URL(string: "https://\(site.host)/"))?.absoluteURL else { return nil }
            return TorrentDescriptor(url: url, name: name, postedAt: posted)
        }
    }

    public func parseArchiveOptions(data: Data) throws -> [ArchiveOption] {
        let document = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))
        return try document.select("a[onclick*='do_hathdl']").compactMap { element in
            let onclick = try element.attr("onclick")
            guard let resolution = capture(onclick, pattern: #"do_hathdl\(['"]([^'"]+)['"]\)"#) else { return nil }
            return ArchiveOption(resolution: resolution, name: try element.text().trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func parseArchiveDownloadURL(data: Data, site: SiteMode) throws -> URL? {
        let body = String(decoding: data, as: UTF8.self)
        guard let value = capture(body, pattern: #"href\s*=\s*['"]([^'"]+)['"][^>]*>\s*Click Here To Start Downloading"#) else { return nil }
        return URL(string: value, relativeTo: URL(string: "https://\(site.host)/"))?.absoluteURL
    }

    public func parseWatchedTags(data: Data) throws -> [WatchedTag] {
        let document = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))
        return try document.select("#usertags_outer > *").compactMap { element in
            let id = element.id()
            guard id.isEmpty == false, id != "usertags_header" else { return nil }
            let name = try element.select("[id^=tagpreview]").first()?.attr("title") ?? ""
            guard name.isEmpty == false else { return nil }
            let watched = try element.select("[id^=tagwatch]").first()?.hasAttr("checked") ?? false
            let hidden = try element.select("[id^=taghide]").first()?.hasAttr("checked") ?? false
            let color = try element.select("[id^=tagcolor]").first()?.attr("placeholder")
            let weight = Int(try element.select("[id^=tagweight]").first()?.attr("value") ?? "") ?? 0
            return WatchedTag(id: id, name: name, isWatched: watched, isHidden: hidden, color: color, weight: weight)
        }
    }

    public func parseImageQuota(data: Data) throws -> ImageQuota {
        let body = String(decoding: data, as: UTF8.self)
        let patterns = [
            #"currently at\s*<strong>([\d,]+)</strong>\s*towards(?: a limit of| your account limit of)\s*<strong>([\d,]+)</strong>.*?(?:Reset Cost:|reset your image quota by spending)\s*<strong>([\d,]+)</strong>"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)) else { continue }
            func integer(_ index: Int) -> Int64? {
                guard let range = Range(match.range(at: index), in: body) else { return nil }
                return Int64(body[range].replacingOccurrences(of: ",", with: ""))
            }
            if let used = integer(1), let total = integer(2), let resetCost = integer(3) {
                return ImageQuota(used: used, total: total, resetCost: resetCost)
            }
        }
        throw EHError.parsingFailed("找不到图片配额")
    }

    private func capture(_ value: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[range])
    }
}
