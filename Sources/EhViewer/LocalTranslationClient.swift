#if os(macOS)
import Foundation
import Observation
import EHDomain
import EHDownloads

struct LocalTranslationRequest: Codable, Sendable {
    struct Page: Codable, Sendable {
        let index: Int
        let fileName: String
        let byteCount: Int64
        let sha256: String
    }
    let formatVersion: Int
    let requestID: String
    let gallery: GalleryTranslationManifest.Gallery
    let pageCount: Int
    let pages: [Page]
}

private final class TranslationHTTPDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

actor LocalTranslationAPI {
    private var token: String?
    private let base = URL(string: "http://127.0.0.1:49179/v1/")!
    private let session = URLSession(configuration: .ephemeral, delegate: TranslationHTTPDelegate(), delegateQueue: nil)

    func request(_ path: String, method: String = "GET", json: Data? = nil, file: URL? = nil, authenticated: Bool = true) async throws -> Data {
        for attempt in 0...1 {
            try Task.checkCancellation()
            var request = URLRequest(url: base.appendingPathComponent(path))
            request.httpMethod = method
            request.timeoutInterval = authenticated ? 30 : 3
            let credential = authenticated ? try await credential() : nil
            if let credential { request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization") }
            request.setValue("EhViewer-macOS", forHTTPHeaderField: "X-EhViewer-Client")
            if let json {
                request.httpBody = json
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            let data: Data
            let response: URLResponse
            if let file {
                request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                (data, response) = try await session.upload(for: request, fromFile: file)
            } else {
                (data, response) = try await session.data(for: request)
            }
            if authenticated, attempt == 0, (response as? HTTPURLResponse)?.statusCode == 401 {
                if token == credential { token = nil }
                continue
            }
            try validate(response)
            guard data.count <= 4 * 1024 * 1024 else { throw EHError.parsingFailed(String(localized: "翻译服务响应过大。")) }
            return data
        }
        throw EHError.invalidResponse
    }

    func download(_ path: String, to target: URL, expectedBytes: Int64) async throws {
        for attempt in 0...1 {
            try Task.checkCancellation()
            let credential = try await credential()
            var request = URLRequest(url: base.appendingPathComponent(path))
            request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 120
            let (temporary, response) = try await session.download(for: request)
            if attempt == 0, (response as? HTTPURLResponse)?.statusCode == 401 {
                if token == credential { token = nil }
                continue
            }
            try validate(response)
            guard try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init) == expectedBytes else {
                throw EHError.parsingFailed(String(localized: "译件页面大小不匹配。"))
            }
            try FileManager.default.moveItem(at: temporary, to: target)
            return
        }
        throw EHError.invalidResponse
    }

    func checkConnection() async throws {
        struct Capabilities: Decodable { let protocolVersion: Int }
        let reply = try JSONDecoder().decode(Capabilities.self, from: await request("capabilities"))
        guard reply.protocolVersion == 1 else {
            throw EHError.parsingFailed(String(localized: "翻译服务协议不兼容。"))
        }
    }

    private func credential() async throws -> String {
        if let token { return token }
        struct Reply: Decodable { let token: String; let protocolVersion: Int; let service: String }
        let reply = try JSONDecoder().decode(Reply.self, from: await request("connect", method: "POST",
            json: JSONEncoder().encode(["protocolVersion": 1]), authenticated: false))
        guard reply.protocolVersion == 1, reply.service == "EhViewerTranslationCompanion",
              reply.token.count >= 32, reply.token.count <= 256 else {
            throw EHError.parsingFailed(String(localized: "翻译服务协议不兼容。"))
        }
        try Task.checkCancellation()
        token = reply.token
        return reply.token
    }

    private func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse, response.url?.scheme == "http",
              response.url?.host == "127.0.0.1", response.url?.port == 49179, response.statusCode == 200 else {
            throw EHError.networkFailed(String(localized: "本机翻译服务请求失败，请检查应用和任务状态。"))
        }
    }
}

@MainActor
@Observable
final class LocalTranslationClient {
    private struct Pending: Codable {
        let request: LocalTranslationRequest
        var uploaded: Bool
        var importedVersionID: UUID?
    }
    private struct Job: Decodable {
        let id: String
        let state: String
        let error: String?
        let request: LocalTranslationRequest
    }
    private struct Jobs: Decodable { let jobs: [Job]; let nextCursor: String? }
    private let api: LocalTranslationAPI
    private let root: URL
    private let library: AppTranslationLibrary
    private var pending: [String: Pending] = [:]
    private var pollTask: Task<Void, Never>?
    private var submitTask: Task<Void, Never>?
    private var canPersist = true
    private var isStopped = false
    private(set) var statuses: [GalleryKey: String] = [:]
    private(set) var isSubmitting = false
    private(set) var isConnected = false
    var hasUnfinishedRequests: Bool { pending.values.contains { $0.importedVersionID == nil } }
    var error: String?

    init(root: URL, library: AppTranslationLibrary) {
        api = LocalTranslationAPI()
        self.root = root
        self.library = library
        let url = root.appendingPathComponent("requests.json")
        if FileManager.default.fileExists(atPath: url.path) {
            do { pending = try JSONDecoder().decode([String: Pending].self, from: Data(contentsOf: url)) }
            catch { canPersist = false; self.error = String(localized: "无法恢复翻译请求记录，请保留文件并检查诊断。") }
        }
    }

    func start() {
        guard !isStopped, pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard self != nil else { return }
                await self?.poll()
                do { try await Task.sleep(for: .seconds(3)) } catch { break }
            }
        }
    }

    func stop() {
        isStopped = true
        isConnected = false
        pollTask?.cancel(); pollTask = nil
        submitTask?.cancel(); submitTask = nil
    }

    func submit(job: DownloadJob, downloads: DownloadFileStore) {
        guard !isStopped, canPersist, !isSubmitting, job.state == .completed else { return }
        isSubmitting = true
        submitTask = Task {
            defer { isSubmitting = false; submitTask = nil; start() }
            do {
                error = nil
                // Retry interrupted uploads with the original requestID.
                if let existing = pending.values.first(where: { $0.request.gallery.key == job.key && !$0.uploaded }) {
                    try await upload(existing.request)
                } else {
                    let request = try await Self.prepare(job: job, downloads: downloads, root: root)
                    pending[request.requestID] = Pending(request: request, uploaded: false)
                    try persist()
                    try await upload(request)
                }
                start()
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled, !isStopped else { return }
                if error is URLError { isConnected = false }
                self.error = error is URLError ? nil : error.localizedDescription
            }
        }
    }

    private func upload(_ request: LocalTranslationRequest) async throws {
        let job = try JSONDecoder().decode(Job.self, from: await api.request("jobs", method: "POST", json: JSONEncoder().encode(request)))
        if job.state == "receiving" {
            for page in request.pages {
                try Task.checkCancellation()
                statuses[request.gallery.key] = String(localized: "正在发送第 \(page.index + 1) / \(request.pageCount) 页")
                _ = try await api.request("jobs/\(request.requestID)/pages/\(page.index)", method: "PUT",
                                          file: workspace(request.requestID).appendingPathComponent(page.fileName))
            }
            _ = try await api.request("jobs/\(request.requestID)/commit", method: "POST")
        }
        pending[request.requestID]?.uploaded = true
        try persist()
        statuses[request.gallery.key] = String(localized: "等待在翻译应用中配置并开始")
    }

    private func poll() async {
        do {
            try await api.checkConnection()
            try Task.checkCancellation()
            guard !isStopped else { return }
            isConnected = true
        } catch {
            guard !Task.isCancelled, !isStopped else { return }
            isConnected = false
            // A companion that is not running is an ordinary idle state.
            if canPersist { self.error = error is URLError ? nil : error.localizedDescription }
            return
        }
        guard canPersist else { return }
        do {
            guard !pending.isEmpty else { error = nil; return }
            if !isSubmitting {
                for item in pending.values.filter({ !$0.uploaded }) {
                    try await upload(item.request)
                }
            }
            var cursor: String?
            var visited = Set<String>()
            repeat {
                let path = cursor.map { "jobs/after/\($0)" } ?? "jobs"
                let response = try JSONDecoder().decode(Jobs.self, from: await api.request(path))
                for job in response.jobs {
                    // Include explicit retranslations from the companion, but only
                    // for input identities previously submitted by this profile.
                    guard UUID(uuidString: job.id) != nil, let known = pending.values.first(where: {
                        $0.request.gallery.key == job.request.gallery.key &&
                        $0.request.pages.map(\.sha256) == job.request.pages.map(\.sha256)
                    }) else { continue }
                    if pending[job.id] == nil {
                        pending[job.id] = Pending(request: job.request, uploaded: true)
                        try persist()
                    }
                    statuses[job.request.gallery.key] = Self.stateTitle(job.state)
                    if let jobError = job.error { statuses[job.request.gallery.key] = Self.stateTitle(job.state) + " · " + jobError }
                    if job.state == "awaitingImport" || job.state == "delivered" {
                        if pending[job.id]?.importedVersionID == nil {
                            let manifest = try JSONDecoder().decode(GalleryTranslationManifest.self, from: await api.request("jobs/\(job.id)/result"))
                            try manifest.validate()
                            guard manifest.gallery.key == known.request.gallery.key,
                                  manifest.pages.map(\.sourceSHA256) == known.request.pages.map(\.sha256) else {
                                throw EHError.parsingFailed(String(localized: "译件与提交的原图不匹配。"))
                            }
                            let stage = root.appendingPathComponent("Results/\(UUID().uuidString)", isDirectory: true)
                            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
                            for page in manifest.pages {
                                try await api.download("jobs/\(job.id)/result/pages/\(page.index)", to: stage.appendingPathComponent(page.fileName), expectedBytes: page.byteCount)
                            }
                            try await library.files.importVersion(manifest, pagesDirectory: stage)
                            pending[job.id]?.importedVersionID = manifest.versionID
                            try persist()
                            await library.refresh()
                        }
                        if job.state != "delivered", let id = pending[job.id]?.importedVersionID {
                            _ = try await api.request("jobs/\(job.id)/ack", method: "POST", json: JSONEncoder().encode(["versionID": id.uuidString.lowercased()]))
                            statuses[job.request.gallery.key] = Self.stateTitle("delivered")
                        }
                    }
                }
                cursor = response.nextCursor
                if let cursor {
                    guard UUID(uuidString: cursor) != nil, visited.insert(cursor).inserted, visited.count <= 10_000 else { throw EHError.invalidResponse }
                }
            } while cursor != nil
            error = nil
        } catch is CancellationError { return }
        catch {
            guard !Task.isCancelled, !isStopped else { return }
            if error is URLError { isConnected = false }
            self.error = error is URLError ? nil : error.localizedDescription
        }
    }

    private func workspace(_ id: String) -> URL { root.appendingPathComponent("Inputs/\(id)", isDirectory: true) }

    private func persist() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(pending).write(to: root.appendingPathComponent("requests.json"), options: .atomic)
    }

    @concurrent
    private static func prepare(job: DownloadJob, downloads: DownloadFileStore, root: URL) async throws -> LocalTranslationRequest {
        guard job.totalPageCount > 0, job.totalPageCount <= 10_000,
              job.completedPageIndexes.count == job.totalPageCount,
              Set(job.pages.map(\.index)) == Set(0..<job.totalPageCount) else {
            throw EHError.storageFailed(String(localized: "仅支持完整下载的漫画。"))
        }
        let id = UUID().uuidString.lowercased()
        let workspace = root.appendingPathComponent("Inputs/\(id)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        var pages: [LocalTranslationRequest.Page] = []
        for index in 0..<job.totalPageCount {
            guard let entry = await downloads.exportEntry(for: job.key, pageIndex: index),
                  entry.byteCount > 0, entry.byteCount <= DeviceSyncPageEntry.maximumByteCount else {
                throw EHError.storageFailed(String(localized: "原图缺失或格式不受支持。"))
            }
            let fileExtension = entry.fileExtension == "jpeg" ? "jpg" : entry.fileExtension
            guard ["png", "jpg", "webp", "bmp", "tif"].contains(fileExtension) else {
                throw EHError.unsupportedFeature(String(localized: "原图缺失或格式不受支持。"))
            }
            let fileName = String(format: "page-%05d.%@", index, fileExtension)
            let target = workspace.appendingPathComponent(fileName)
            try FileManager.default.copyItem(at: entry.fileURL, to: target)
            let sha = try TranslationFileStore.sha256(of: target)
            let page = GalleryTranslationManifest.Page(index: index, fileName: fileName, byteCount: entry.byteCount, sha256: sha, sourceSHA256: sha)
            try TranslationFileStore.validateFile(target, page: page)
            pages.append(.init(index: index, fileName: fileName, byteCount: entry.byteCount, sha256: sha))
        }
        return LocalTranslationRequest(formatVersion: 1, requestID: id, gallery: .init(key: job.key, title: job.title), pageCount: pages.count, pages: pages)
    }

    private static func stateTitle(_ state: String) -> String {
        switch state {
        case "receiving": String(localized: "正在接收原图")
        case "queued": String(localized: "等待在翻译应用中配置并开始")
        case "preparing": String(localized: "正在准备模型")
        case "running": String(localized: "正在翻译")
        case "rendering": String(localized: "正在生成译图")
        case "awaitingImport": String(localized: "译件等待导入")
        case "delivered": String(localized: "译件已保存")
        case "cancelled": String(localized: "任务已取消")
        case "interrupted": String(localized: "任务已中断，可在翻译应用中重试")
        default: String(localized: "翻译失败，请在翻译应用中查看诊断")
        }
    }
}
#endif
