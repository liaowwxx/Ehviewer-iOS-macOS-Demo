import Foundation
import EHDomain

public actor TagSuggestionProvider {
    public static let originalProjectSourceURL = URL(
        string: "https://raw.githubusercontent.com/Mapaler/EhViewer/tag-translations/tag-translations/tag-translations-zh-rCN"
    )!

    private let sourceURL: URL
    private let cacheURL: URL
    private let session: URLSession
    private var entries: [SearchTagSuggestion]?
    private var loadingTask: Task<[SearchTagSuggestion], Error>?

    public init(
        sourceURL: URL = TagSuggestionProvider.originalProjectSourceURL,
        cacheURL: URL? = nil,
        session: URLSession? = nil
    ) {
        self.sourceURL = sourceURL
        self.cacheURL = cacheURL ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "EhViewer/TagSuggestions/tag-translations-zh-rCN")
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            self.session = URLSession(configuration: configuration)
        }
    }

    public func suggestions(for keyword: String, limit: Int = 40) async throws -> [SearchTagSuggestion] {
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyword.isEmpty == false, limit > 0 else { return [] }
        let entries = try await loadEntries()
        var matches: [SearchTagSuggestion] = []
        matches.reserveCapacity(min(limit, 40))
        for (index, entry) in entries.enumerated() {
            if index.isMultiple(of: 512) { try Task.checkCancellation() }
            if entry.english.localizedCaseInsensitiveContains(keyword)
                || entry.localizedText?.localizedCaseInsensitiveContains(keyword) == true {
                matches.append(entry)
                if matches.count == limit { break }
            }
        }
        return matches
    }

    /// Loads the same tag database used by the original client so the first
    /// search keystroke does not have to wait for the download to begin.
    public func preload() async {
        _ = try? await loadEntries()
    }

    public static func decodeDatabase(_ data: Data) throws -> [SearchTagSuggestion] {
        guard data.count >= 4 else { throw EHError.parsingFailed("标签数据库文件不完整") }
        let declaredLength = data.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        guard declaredLength == data.count - 4 else {
            throw EHError.parsingFailed("标签数据库长度校验失败")
        }
        let payload = String(decoding: data.dropFirst(4), as: UTF8.self)
        return payload.split(separator: "\n").compactMap { substring in
            let line = String(substring)
            guard let separator = line.firstIndex(of: "\r") else { return nil }
            let rawEnglish = String(line[..<separator])
            let encodedTranslation = String(line[line.index(after: separator)...])
            guard let localizedData = Data(base64Encoded: encodedTranslation),
                  let localizedText = String(data: localizedData, encoding: .utf8) else { return nil }
            return SearchTagSuggestion(
                english: expandedNamespace(in: rawEnglish),
                localizedText: localizedText == "null" ? nil : localizedText
            )
        }
    }

    private func loadEntries() async throws -> [SearchTagSuggestion] {
        if let entries { return entries }

        if let loadingTask {
            return try await loadingTask.value
        }

        let task = Task { [sourceURL, cacheURL, session] in
            try await Self.loadEntries(sourceURL: sourceURL, cacheURL: cacheURL, session: session)
        }
        loadingTask = task
        do {
            let decoded = try await task.value
            entries = decoded
            loadingTask = nil
            return decoded
        } catch {
            loadingTask = nil
            throw error
        }
    }

    private static func loadEntries(
        sourceURL: URL,
        cacheURL: URL,
        session: URLSession
    ) async throws -> [SearchTagSuggestion] {
        let cachedData = try? Data(contentsOf: cacheURL)
        if let cachedData, isCacheFresh(at: cacheURL),
           let decoded = try? Self.decodeDatabase(cachedData) {
            return decoded
        }

        do {
            let (data, response) = try await session.data(from: sourceURL)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else { throw EHError.invalidResponse }
            let decoded = try Self.decodeDatabase(data)
            try persist(data, to: cacheURL)
            return decoded
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if let cachedData, let decoded = try? Self.decodeDatabase(cachedData) {
                return decoded
            }
            throw error
        }
    }

    private static func isCacheFresh(at cacheURL: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
              let modifiedAt = attributes[.modificationDate] as? Date else { return false }
        return Date.now.timeIntervalSince(modifiedAt) < 7 * 24 * 60 * 60
    }

    private static func persist(_ data: Data, to cacheURL: URL) throws {
        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: cacheURL, options: .atomic)
    }

    private static func expandedNamespace(in tag: String) -> String {
        let namespaceByPrefix = [
            "n": "rows",
            "a": "artist",
            "cos": "cosplayer",
            "c": "character",
            "f": "female",
            "g": "group",
            "l": "language",
            "m": "male",
            "": "misc",
            "x": "mixed",
            "o": "other",
            "p": "parody",
            "r": "reclass"
        ]
        guard let separator = tag.firstIndex(of: ":") else { return tag }
        let prefix = String(tag[..<separator])
        guard let namespace = namespaceByPrefix[prefix] else { return tag }
        return "\(namespace):\(tag[tag.index(after: separator)...])"
    }
}
