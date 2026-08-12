import Foundation

public actor ImagePipeline {
    private struct CacheEntry: Sendable {
        let data: Data
        let lastAccess: Date
    }

    private var cache: [URL: CacheEntry] = [:]
    private var inFlight: [URL: Task<Data, Error>] = [:]
    private var cachedBytes = 0
    private let byteLimit: Int
    private let diskRoot: URL?

    public init(byteLimit: Int? = nil, diskRoot: URL? = nil) {
#if os(macOS)
        self.byteLimit = byteLimit ?? 2 * 1024 * 1024 * 1024
#else
        self.byteLimit = byteLimit ?? 512 * 1024 * 1024
#endif
        self.diskRoot = diskRoot ?? Self.defaultDiskRoot
    }

    public func data(for url: URL, using transport: any HTTPTransport) async throws -> Data {
        try await data(for: url) {
            let (data, response) = try await transport.send(URLRequest(url: url))
            guard (200..<300).contains(response.statusCode) else { throw EHNetworkingError.httpStatus(response.statusCode) }
            return data
        }
    }

    public func data(for url: URL, fetcher: @escaping @Sendable () async throws -> Data) async throws -> Data {
        if let entry = cache[url] {
            cache[url] = CacheEntry(data: entry.data, lastAccess: Date())
            return entry.data
        }
        if let diskData = readFromDisk(url: url) {
            insert(diskData, for: url)
            return diskData
        }
        if let task = inFlight[url] {
            return try await task.value
        }

        let task = Task<Data, Error> { try await fetcher() }
        inFlight[url] = task
        do {
            let data = try await task.value
            inFlight[url] = nil
            insert(data, for: url)
            writeToDisk(data, url: url)
            return data
        } catch {
            inFlight[url] = nil
            throw error
        }
    }

    public func prefetch(_ urls: [URL], fetcher: @escaping @Sendable (URL) async throws -> Data) async {
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask {
                    _ = try? await self.data(for: url) { try await fetcher(url) }
                }
            }
        }
    }

    public func removeAll() {
        cache.removeAll()
        cachedBytes = 0
        if let diskRoot {
            try? FileManager.default.removeItem(at: diskRoot)
        }
    }

    private func insert(_ data: Data, for url: URL) {
        if let old = cache[url] { cachedBytes -= old.data.count }
        cache[url] = CacheEntry(data: data, lastAccess: Date())
        cachedBytes += data.count
        evictIfNeeded()
    }

    private func evictIfNeeded() {
        while cachedBytes > byteLimit, let oldest = cache.min(by: { $0.value.lastAccess < $1.value.lastAccess }) {
            cachedBytes -= oldest.value.data.count
            cache.removeValue(forKey: oldest.key)
        }
        evictDiskIfNeeded()
    }

    private func readFromDisk(url: URL) -> Data? {
        guard let fileURL = diskURL(for: url),
              let data = try? Data(contentsOf: fileURL) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
        return data
    }

    private func writeToDisk(_ data: Data, url: URL) {
        guard let fileURL = diskURL(for: url) else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            var resourceURL = fileURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? resourceURL.setResourceValues(values)
        } catch {
            return
        }
    }

    private func evictDiskIfNeeded() {
        guard let diskRoot,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: diskRoot,
                  includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                  options: [.skipsHiddenFiles]
              ) else { return }
        var entries = files.compactMap { fileURL -> (URL, Int, Date)? in
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize else { return nil }
            return (fileURL, size, values.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.1 }
        guard total > byteLimit else { return }
        entries.sort { $0.2 < $1.2 }
        for entry in entries where total > byteLimit {
            try? FileManager.default.removeItem(at: entry.0)
            total -= entry.1
        }
    }

    private func diskURL(for url: URL) -> URL? {
        guard let diskRoot else { return nil }
        let key = Data(url.absoluteString.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return diskRoot.appendingPathComponent("\(key).bin", isDirectory: false)
    }

    private static var defaultDiskRoot: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("EhViewer/ImageCache", isDirectory: true)
    }
}

private enum EHNetworkingError: LocalizedError {
    case httpStatus(Int)

    var errorDescription: String? {
        switch self { case .httpStatus(let status): "图片请求失败：HTTP \(status)" }
    }
}
