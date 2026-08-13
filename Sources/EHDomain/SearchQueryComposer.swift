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
        guard let separator = query.range(of: "  ", options: .backwards) else { return syntax }
        let prefix = query[..<separator.lowerBound].trimmingCharacters(in: .whitespaces)
        return prefix.isEmpty ? syntax : "\(prefix)  \(syntax)"
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
}
