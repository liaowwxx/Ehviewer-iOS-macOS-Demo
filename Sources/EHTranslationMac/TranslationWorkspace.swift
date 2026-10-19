#if os(macOS)
import Foundation
import Observation
import EHDomain
import EHDownloads

@MainActor @Observable
public final class TranslationWorkspace {
    public let profileID: UUID
    public let root: URL
    public private(set) var tasks: [TranslationTaskRecord] = []
    public var configuration: TranslationJSON = .object([:])
    public var catalog: TranslationJSON = .object([:])
    public var report: TranslationJSON = .object([:])
    var checkedConfiguration: TranslationJSON?
    public var error: String?
    public var environmentSummary = "请选择安装目录，然后检查环境。"
    public var isAdding = false
    public var focusedTaskID: UUID?
    public var onImported: (@MainActor () async -> Void)?
    let coordinator: TranslationCoordinator
    private let files: TranslationFileStore
    private var configRevision: Data?
    private var storageHealthy = true
    private var importing = false

    init(profileID: UUID, files: TranslationFileStore, coordinator: TranslationCoordinator) {
        self.profileID = profileID
        self.files = files
        self.coordinator = coordinator
        root = files.root.appendingPathComponent("NativeWorkstation", isDirectory: true)
        do {
            let list = root.appendingPathComponent("tasks.json")
            if FileManager.default.fileExists(atPath: list.path) {
                tasks = try JSONDecoder().decode([TranslationTaskRecord].self, from: Data(contentsOf: list))
                for index in tasks.indices where tasks[index].isActive { tasks[index].state = "interrupted" }
            }
            let preset = root.appendingPathComponent("preset.json")
            if FileManager.default.fileExists(atPath: preset.path) {
                let data = try Data(contentsOf: preset)
                configuration = try JSONDecoder().decode(TranslationJSON.self, from: data)
                configRevision = data
            }
        } catch { self.error = "无法恢复翻译记录，请保留工作目录检查。"; storageHealthy = false }
    }

    public func configureFromInstallation() {
        guard configuration.object.isEmpty else { return }
        importPreset(URL(fileURLWithPath: coordinator.enginePath).appendingPathComponent("config/config.json"))
    }

    func applyModelList(_ models: [String], to requestedProfile: TranslationJSON) throws {
        var profiles = configuration["module"]["llm_profiles"].array
        guard let index = profiles.firstIndex(where: { $0["id"] == requestedProfile["id"] }), profiles[index] == requestedProfile else {
            throw TranslationBridgeError(message: "服务配置已变更，请重新刷新模型列表。")
        }
        guard !models.isEmpty else {
            throw TranslationBridgeError(message: "服务没有返回可用模型。可继续使用已有选项或自定义模型名。")
        }
        profiles[index]["model_options"] = .array(models.map(TranslationJSON.string))
        configuration[path: ["module", "llm_profiles"]] = .array(profiles)
    }

    public func importPreset(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 4 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
            let value = try JSONDecoder().decode(TranslationJSON.self, from: data)
            guard !value["module"].object.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            configuration = value
            saveSettings()
        } catch { self.error = error.localizedDescription }
    }

    public func saveSettings() {
        do {
            guard storageHealthy else { throw CocoaError(.fileWriteUnknown) }
            let target = root.appendingPathComponent("preset.json")
            if let configRevision, try Data(contentsOf: target) != configRevision {
                throw TranslationBridgeError(message: "配置已由其他窗口修改，请重新载入后保存。")
            }
            let data = try JSONEncoder().encode(configuration)
            try Self.write(data, to: target)
            configRevision = data
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    public func add(_ jobs: [DownloadJob], downloads: DownloadFileStore) async {
        guard storageHealthy, !isAdding, !coordinator.isDraining else { return }
        isAdding = true
        defer { isAdding = false }
        do {
            for job in jobs {
                guard job.state == .completed else { throw TranslationBridgeError(message: "仅支持完整下载的漫画。") }
                if let existing = tasks.first(where: { $0.input.gallery.key == job.key && ($0.canStart || $0.isActive) }) {
                    focusedTaskID = existing.id
                    continue
                }
                let id = UUID()
                let input = try await Self.snapshot(job, downloads: downloads, directory: directory(id), id: id)
                tasks.append(.init(id: id, input: input, created: .now, state: "queued"))
                focusedTaskID = id
                try persist()
            }
        } catch { self.error = error.localizedDescription }
    }

    public func start(_ id: UUID) {
        guard storageHealthy, tasks.first(where: { $0.id == id })?.canStart == true else { return }
        do {
            try validateSettings()
            try Self.write(JSONEncoder().encode(configuration), to: directory(id).appendingPathComponent("preset.json"))
            if let index = tasks.firstIndex(where: { $0.id == id }) { tasks[index].targetLanguage = configuration["module"]["translate_target"].string }
            coordinator.enqueue(self, id: id)
        } catch { self.error = error.localizedDescription }
    }

    func validateSettings() throws {
        let module = configuration["module"]
        guard !module.object.isEmpty, !module["translate_target"].string.isEmpty else {
            throw TranslationBridgeError(message: "请先完成翻译设置。")
        }
        for (stage, model, selector, capability) in [
            ("translator", "LLMTranslator", "translator_llm_id", "support_text"),
            ("ocr", "LLMOCR", "ocr_llm_id", "support_vision"),
            ("inpainter", "LLMInpaint", "inpaint_llm_id", "support_image")
        ] where module[stage].string == model && module["enable_" + (stage == "translator" ? "translate" : stage == "inpainter" ? "inpaint" : "ocr")] != .bool(false) {
            guard module["llm_profiles"].array.contains(where: { $0["id"] == module[selector] && $0[capability].bool }) else {
                throw TranslationBridgeError(message: "所选 LLM 配置不支持对应阶段，请检查服务能力。")
            }
        }
        let translator = catalog["translator"][module["translator"].string]
        for (field, languages) in [("translate_source", "sourceLanguages"), ("translate_target", "targetLanguages")] {
            let supported = translator[languages].array.map(\.string)
            if !supported.isEmpty, !supported.contains(module[field].string) {
                throw TranslationBridgeError(message: "所选翻译模型不支持当前语言。")
            }
        }
    }

    public func cancel(_ id: UUID) { coordinator.cancel(self, id: id) }

    public func retry(_ id: UUID) async {
        guard let previous = tasks.first(where: { $0.id == id }), previous.canRetry else { return }
        do {
            let nextID = UUID(), target = directory(nextID)
            try FileManager.default.createDirectory(at: target.appendingPathComponent("project"), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            for page in previous.input.pages {
                try FileManager.default.copyItem(at: directory(id).appendingPathComponent("project/\(page.fileName)"),
                                                 to: target.appendingPathComponent("project/\(page.fileName)"))
            }
            let input = TranslationInput(formatVersion: 1, requestID: nextID.uuidString.lowercased(), gallery: previous.input.gallery,
                                         pageCount: previous.input.pageCount, pages: previous.input.pages)
            try Self.write(JSONEncoder().encode(input), to: target.appendingPathComponent("request.json"))
            tasks.append(.init(id: nextID, input: input, created: .now, state: "queued"))
            focusedTaskID = nextID
            try persist()
        } catch { self.error = error.localizedDescription }
    }

    func directory(_ id: UUID) -> URL { root.appendingPathComponent("jobs/\(id.uuidString.lowercased())") }

    func update(_ id: UUID, state: String, error: String? = nil) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].state = state; tasks[index].error = error
        do { try persist() } catch { self.error = error.localizedDescription; storageHealthy = false }
    }

    func refreshProgress(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }), tasks[index].isActive,
              let data = try? Data(contentsOf: directory(id).appendingPathComponent("engine-status.json")),
              let status = try? JSONDecoder().decode(TranslationJSON.self, from: data) else { return }
        tasks[index].completedPages = Int(status["completedPages"].number)
        if ["preparing", "running", "rendering"].contains(status["state"].string) { tasks[index].state = status["state"].string }
    }

    public func importReadyResults() async {
        guard coordinator.activeProfile == profileID, !importing else { return }
        importing = true
        defer { importing = false }
        for task in tasks where task.state == "awaitingImport" || task.state == "interrupted" {
            let resultURL = directory(task.id).appendingPathComponent("result.json")
            guard FileManager.default.fileExists(atPath: resultURL.path) else { continue }
            do {
                let manifest = try JSONDecoder().decode(GalleryTranslationManifest.self, from: Data(contentsOf: resultURL))
                try manifest.validate()
                guard manifest.gallery.key == task.input.gallery.key,
                      manifest.pages.map(\.sourceSHA256) == task.input.pages.map(\.sha256) else { throw CocoaError(.fileReadCorruptFile) }
                try await files.importVersion(manifest, pagesDirectory: directory(task.id).appendingPathComponent("project/result"))
                if let index = tasks.firstIndex(where: { $0.id == task.id }) { tasks[index].completedPages = task.input.pageCount }
                update(task.id, state: "delivered")
                await onImported?()
            } catch { self.error = error.localizedDescription }
        }
    }

    private func persist() throws { try Self.write(JSONEncoder().encode(tasks), to: root.appendingPathComponent("tasks.json")) }

    nonisolated static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    @concurrent
    static func snapshot(_ job: DownloadJob, downloads: DownloadFileStore, directory: URL, id: UUID) async throws -> TranslationInput {
        guard job.state == .completed, (1...10_000).contains(job.totalPageCount),
              job.completedPageIndexes.count == job.totalPageCount,
              Set(job.pages.map(\.index)) == Set(0..<job.totalPageCount) else {
            throw TranslationBridgeError(message: "仅支持完整下载的漫画。")
        }
        let project = directory.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var pages: [TranslationInput.Page] = []
        for index in 0..<job.totalPageCount {
            try Task.checkCancellation()
            guard let entry = await downloads.exportEntry(for: job.key, pageIndex: index), entry.byteCount > 0,
                  entry.byteCount <= DeviceSyncPageEntry.maximumByteCount else { throw CocoaError(.fileReadCorruptFile) }
            let ext = entry.fileExtension == "jpeg" ? "jpg" : entry.fileExtension
            guard ["png", "jpg", "webp", "bmp", "tif"].contains(ext) else { throw CocoaError(.fileReadUnknown) }
            let name = String(format: "page-%05d.%@", index, ext)
            let destination = project.appendingPathComponent(name)
            try FileManager.default.copyItem(at: entry.fileURL, to: destination)
            let sha = try TranslationFileStore.sha256(of: destination)
            try TranslationFileStore.validateFile(destination, page: .init(index: index, fileName: name, byteCount: entry.byteCount, sha256: sha, sourceSHA256: sha))
            pages.append(.init(index: index, fileName: name, byteCount: entry.byteCount, sha256: sha))
        }
        let input = TranslationInput(formatVersion: 1, requestID: id.uuidString.lowercased(), gallery: .init(key: job.key, title: job.title), pageCount: pages.count, pages: pages)
        try write(JSONEncoder().encode(input), to: directory.appendingPathComponent("request.json"))
        return input
    }
}
#endif
