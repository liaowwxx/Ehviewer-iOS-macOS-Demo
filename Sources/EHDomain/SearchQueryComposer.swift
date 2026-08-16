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

public enum SearchQueryComposer {
    private static let namespacePrefixes: [String: String] = [
        "rows": "n:",
        "artist": "a:",
        "cosplayer": "cos:",
        "character": "c:",
        "female": "f:",
        "group": "g:",
        "language": "l:",
        "male": "m:",
        "misc": "",
        "mixed": "x:",
        "other": "o:",
        "parody": "p:",
        "reclass": "r:"
    ]

    private static let namespacesByPrefix: [String: String] = [
        "n": "rows",
        "a": "artist",
        "cos": "cosplayer",
        "c": "character",
        "f": "female",
        "g": "group",
        "l": "language",
        "m": "male",
        "x": "mixed",
        "o": "other",
        "p": "parody",
        "r": "reclass",
    ]

    /// The full namespace name for a search prefix, e.g. `p` → `parody`.
    public static func namespace(forPrefix prefix: String) -> String? {
        namespacesByPrefix[prefix.lowercased()]
    }

    /// One tag token inside a search query, e.g. `p:"blue archive$"`.
    public struct SearchTagToken: Hashable, Sendable {
        public let namespace: String
        public let value: String
        public let raw: String

        public init(namespace: String, value: String, raw: String) {
            self.namespace = namespace
            self.value = value
            self.raw = raw
        }

        /// The `namespace:value` form used for translation lookups.
        public var fullTag: String { "\(namespace):\(value)" }
    }

    /// Extracts every `<prefix>:"value$"` tag token from the query in order,
    /// leaving free-text keywords untouched.
    public static func tagTokens(in query: String) -> [SearchTagToken] {
        let pattern = #"([a-z]{1,3}):"([^"]*?)\$?""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(query.startIndex..., in: query)
        return regex.matches(in: query, range: range).compactMap { match in
            guard let prefixRange = Range(match.range(at: 1), in: query),
                  let valueRange = Range(match.range(at: 2), in: query),
                  let rawRange = Range(match.range(at: 0), in: query),
                  let namespace = namespace(forPrefix: String(query[prefixRange])) else { return nil }
            return SearchTagToken(
                namespace: namespace,
                value: String(query[valueRange]),
                raw: String(query[rawRange])
            )
        }
    }

    /// Removes one tag token from the query and collapses leftover spacing.
    public static func removing(_ token: SearchTagToken, from query: String) -> String {
        let raw = token.raw
        let pattern = NSRegularExpression.escapedPattern(for: raw)
        guard let regex = try? NSRegularExpression(pattern: #"(?:\s+)?"# + pattern),
              let range = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query))?.range,
              let matchRange = Range(range, in: query) else {
            return query
        }
        return query.replacingCharacters(in: matchRange, with: " ")
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func normalized(_ query: String) -> String {
        query
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func suggestionFragment(in query: String) -> String {
        let query = normalized(query)
        guard query.isEmpty == false else { return "" }
        var trailingComponents: [Substring] = []
        for component in query.split(whereSeparator: \.isWhitespace).reversed() {
            if component.contains(":") || component.contains("$") {
                break
            }
            trailingComponents.append(component)
        }
        return trailingComponents
            .reversed()
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func searchSyntax(for tag: String) -> String {
        let tag = normalized(tag)
        guard let separator = tag.firstIndex(of: ":") else { return tag }
        let namespace = String(tag[..<separator]).lowercased()
        let value = String(tag[tag.index(after: separator)...])
        guard let prefix = namespacePrefixes[namespace], value.isEmpty == false else { return tag }
        return "\(prefix)\"\(value)$\""
    }

    public static func completing(tag: String, in query: String) -> String {
        let syntax = searchSyntax(for: tag)
        let query = normalized(query)
        guard query.isEmpty == false else { return syntax }

        let fragment = suggestionFragment(in: query)
        guard fragment.isEmpty == false,
              let fragmentRange = query.range(of: fragment, options: .backwards) else {
            return "\(query) \(syntax)"
        }
        let prefix = query[..<fragmentRange.lowerBound].trimmingCharacters(in: .whitespaces)
        return prefix.isEmpty ? syntax : "\(prefix) \(syntax)"
    }

    public static func galleryKey(in query: String) -> GalleryKey? {
        guard let url = URL(string: normalized(query)),
              let host = url.host?.lowercased(),
              host == "e-hentai.org" || host == "exhentai.org" else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard let galleryIndex = components.firstIndex(of: "g"),
              components.count > galleryIndex + 2,
              let gid = Int64(components[galleryIndex + 1]),
              components[galleryIndex + 2].isEmpty == false else { return nil }
        return GalleryKey(gid: gid, token: components[galleryIndex + 2])
    }

    /// Quotes a keyword so the site treats it as an exact phrase.
    public static func exactKeyword(_ keyword: String) -> String {
        let escaped = keyword.replacingOccurrences(of: "\"", with: "")
        return "\"\(escaped)\""
    }

    /// Search syntax for one uploader's galleries.
    public static func uploaderSyntax(_ name: String) -> String {
        "uploader:\(exactKeyword(name))"
    }

    /// Converts a full-namespace tag like `artist:john` into the reference
    /// tag database's short key form like `a:john`, so detail-page tags can
    /// find their translation the same way the reference client does.
    public static func databaseTagKey(for tag: String) -> String {
        let tag = normalized(tag)
        guard let separator = tag.firstIndex(of: ":") else { return tag }
        let namespace = String(tag[..<separator]).lowercased()
        let value = String(tag[tag.index(after: separator)...])
        guard value.isEmpty == false else { return tag }
        switch namespace {
        case "artist": return "a:\(value)"
        case "cosplayer": return "cos:\(value)"
        case "character": return "c:\(value)"
        case "female": return "f:\(value)"
        case "group": return "g:\(value)"
        case "language": return "l:\(value)"
        case "male": return "m:\(value)"
        case "misc": return value
        case "mixed": return "x:\(value)"
        case "other": return "o:\(value)"
        case "parody": return "p:\(value)"
        case "reclass": return "r:\(value)"
        default: return tag
        }
    }

    /// Mirrors the reference client's `EhUtils.extractTitle`: removes leading
    /// and trailing `(...)`/`[...]`/`{...}`/`~...~` decorations and keeps only
    /// the part before the first `|` (the romaji/English title).
    public static func extractTitleKeyword(from title: String) -> String? {
        var value = title
        if let prefix = try? NSRegularExpression(
            pattern: #"^(?:(?:\([^)]*\))|(?:\[[^\]]*\])|(?:\{[^}]*\})|(?:~[^~]*~)|\s+)*"#
        ) {
            value = prefix.stringByReplacingMatches(
                in: value,
                range: NSRange(value.startIndex..., in: value),
                withTemplate: ""
            )
        }
        if let suffix = try? NSRegularExpression(
            pattern: #"(?:\s+ch.[\s\d-]+)?(?:(?:\([^)]*\))|(?:\[[^\]]*\])|(?:\{[^}]*\})|(?:~[^~]*~)|\s+)*$"#,
            options: [.caseInsensitive]
        ) {
            value = suffix.stringByReplacingMatches(
                in: value,
                range: NSRange(value.startIndex..., in: value),
                withTemplate: ""
            )
        }
        if let separator = value.firstIndex(of: "|") {
            value = String(value[..<separator])
        }
        let keyword = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return keyword.isEmpty ? nil : keyword
    }
}
