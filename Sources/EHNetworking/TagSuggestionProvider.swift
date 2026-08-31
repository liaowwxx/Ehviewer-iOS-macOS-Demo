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

public enum TagDatabaseUpdateStatus: Equatable, Sendable {
    case latest
    case updateAvailable
    case unknown
}

public actor TagSuggestionProvider {
    private struct SuggestionCacheKey: Hashable {
        let keyword: String
        let limit: Int
    }

    /// The database used by the reference CN fork, then the original
    /// project's mirror. Both share the same binary format.
    public static let referenceSourceURLs = [
        URL(string: "https://raw.githubusercontent.com/xiaojieonly/EhTagTranslation/main/tag-translations/tag-translations-zh-rCN.json")!,
        URL(string: "https://raw.githubusercontent.com/Mapaler/EhViewer/tag-translations/tag-translations/tag-translations-zh-rCN")!,
    ]

    public static let originalProjectSourceURL = referenceSourceURLs[0]

    private let sourceURLs: [URL]
    private let cacheURL: URL
    private let bundledDatabaseURL: URL?
    private let session: URLSession
    private let remoteDataLoader: (@Sendable (URL) async throws -> Data)?
    private var entries: [SearchTagSuggestion]?
    private var loadingTask: Task<[SearchTagSuggestion], Error>?
    private var suggestionCache: [SuggestionCacheKey: [SearchTagSuggestion]] = [:]

    public init(
        sourceURLs: [URL] = TagSuggestionProvider.referenceSourceURLs,
        cacheURL: URL? = nil,
        bundledDatabaseURL: URL? = nil,
        session: URLSession? = nil,
        remoteDataLoader: (@Sendable (URL) async throws -> Data)? = nil
    ) {
        self.sourceURLs = sourceURLs
        self.cacheURL = cacheURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "EhViewer/TagDatabase/tag-translations-zh-rCN")
        self.bundledDatabaseURL = bundledDatabaseURL
            ?? Bundle.module.url(forResource: "tag-translations-zh-rCN", withExtension: nil)
        self.remoteDataLoader = remoteDataLoader
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
        try Task.checkCancellation()
        let cacheKey = SuggestionCacheKey(keyword: keyword.localizedLowercase, limit: limit)
        if let cached = suggestionCache[cacheKey] {
            return cached
        }
        let entries = try await loadEntries()
        try Task.checkCancellation()
        var matches: [SearchTagSuggestion] = []
        matches.reserveCapacity(min(limit, 40))
        for (index, entry) in entries.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            if entry.english.localizedCaseInsensitiveContains(keyword)
                || entry.localizedText?.localizedCaseInsensitiveContains(keyword) == true {
                matches.append(entry)
                if matches.count == limit { break }
            }
        }
        suggestionCache[cacheKey] = matches
        if suggestionCache.count > 48,
           let oldestKey = suggestionCache.keys.first {
            suggestionCache.removeValue(forKey: oldestKey)
        }
        return matches
    }

    /// Loads the bundled database or a verified user-installed update. It never
    /// starts a network request, so initial use remains fully offline-capable.
    public func preload() async {
        _ = try? await loadEntries()
    }

    /// The complete decoded tag database, for bulk import into persistence.
    public func allEntries() async throws -> [SearchTagSuggestion] {
        try await loadEntries()
    }

    /// Downloads and validates a candidate database without changing the active
    /// database. The caller can then present an explicit update action.
    public func checkForUpdate() async throws -> TagDatabaseUpdateStatus {
        let current = try await activeDatabaseData()
        let candidate = try await downloadLatestDatabase()
        guard candidate != current else { return .latest }
        try Self.write(candidate, to: candidateURL)
        return .updateAvailable
    }

    /// Installs the previously checked candidate (or fetches one if necessary).
    /// The replacement is staged and the previous file is retained as a backup;
    /// if verification fails after replacement, the backup is restored.
    public func installAvailableUpdate() async throws -> TagDatabaseUpdateStatus {
        let current = try await activeDatabaseData()
        let candidate: Data
        if let staged = try? Data(contentsOf: candidateURL),
           (try? Self.decodeDatabase(staged)) != nil {
            candidate = staged
        } else {
            candidate = try await downloadLatestDatabase()
        }
        guard candidate != current else { return .latest }
        try Self.replaceActiveDatabase(with: candidate, at: cacheURL)
        entries = nil
        suggestionCache = [:]
        _ = try await loadEntries()
        return .latest
    }

    public static func decodeDatabase(_ data: Data) throws -> [SearchTagSuggestion] {
        guard data.count >= 4 else { throw EHError.parsingFailed(String(localized: "标签数据库文件不完整")) }
        let declaredLength = data.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        guard declaredLength == data.count - 4 else {
            throw EHError.parsingFailed(String(localized: "标签数据库长度校验失败"))
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
                localizedText: localizedText == "null" ? nil : localizedText,
                rawKey: rawEnglish
            )
        }
    }

    private func loadEntries() async throws -> [SearchTagSuggestion] {
        if let entries { return entries }

        if let loadingTask {
            return try await loadingTask.value
        }

        let task = Task { [cacheURL, bundledDatabaseURL] in
            try Self.loadActiveEntries(cacheURL: cacheURL, bundledDatabaseURL: bundledDatabaseURL)
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

    private var candidateURL: URL {
        cacheURL.deletingLastPathComponent()
            .appendingPathComponent("\(cacheURL.lastPathComponent).candidate")
    }

    private func activeDatabaseData() async throws -> Data {
        try Self.activeDatabaseData(cacheURL: cacheURL, bundledDatabaseURL: bundledDatabaseURL)
    }

    private static func loadActiveEntries(
        cacheURL: URL,
        bundledDatabaseURL: URL?
    ) throws -> [SearchTagSuggestion] {
        try decodeDatabase(activeDatabaseData(cacheURL: cacheURL, bundledDatabaseURL: bundledDatabaseURL))
    }

    private static func activeDatabaseData(
        cacheURL: URL,
        bundledDatabaseURL: URL?
    ) throws -> Data {
        if let installed = try? Data(contentsOf: cacheURL),
           (try? decodeDatabase(installed)) != nil {
            return installed
        }
        guard let bundledDatabaseURL,
              let bundled = try? Data(contentsOf: bundledDatabaseURL),
              (try? decodeDatabase(bundled)) != nil else {
            throw EHError.storageFailed(String(localized: "内置标签数据库不可用"))
        }
        return bundled
    }

    private func downloadLatestDatabase() async throws -> Data {
        var lastError: Error?
        for sourceURL in sourceURLs {
            do {
                let data: Data
                if let remoteDataLoader {
                    data = try await remoteDataLoader(sourceURL)
                } else {
                    let (loadedData, response) = try await session.data(from: sourceURL)
                    guard let response = response as? HTTPURLResponse,
                          (200..<300).contains(response.statusCode) else { throw EHError.invalidResponse }
                    data = loadedData
                }
                _ = try Self.decodeDatabase(data)
                return data
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw lastError ?? EHError.networkFailed(String(localized: "标签数据库下载失败"))
    }

    private static func replaceActiveDatabase(with data: Data, at cacheURL: URL) throws {
        let manager = FileManager.default
        let directory = cacheURL.deletingLastPathComponent()
        let stagingURL = directory.appendingPathComponent("\(cacheURL.lastPathComponent).staging-\(UUID().uuidString)")
        let backupName = "\(cacheURL.lastPathComponent).backup-\(UUID().uuidString)"
        let backupURL = directory.appendingPathComponent(backupName)

        try write(data, to: stagingURL)
        _ = try decodeDatabase(Data(contentsOf: stagingURL))

        if manager.fileExists(atPath: cacheURL.path) {
            _ = try manager.replaceItemAt(
                cacheURL,
                withItemAt: stagingURL,
                backupItemName: backupName,
                options: []
            )
        } else {
            try manager.moveItem(at: stagingURL, to: cacheURL)
        }

        do {
            _ = try decodeDatabase(Data(contentsOf: cacheURL))
        } catch {
            guard manager.fileExists(atPath: backupURL.path) else { throw error }
            _ = try manager.replaceItemAt(
                cacheURL,
                withItemAt: backupURL,
                backupItemName: nil,
                options: []
            )
            throw error
        }
    }

    private static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
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
