#if os(macOS)
import Foundation

/// Small disk snapshots keep polling independent of the image/model workers.
struct TranslationTaskActivity: Sendable {
    var stages: [String: Int] = [:]
    var enabledStages: Set<String> = ["detect", "ocr", "translate", "inpaint"]
    var previewURL: URL?
    var previewIndex: Int?
    var output = ""
    var requestState = ""
    var log = ""

    @concurrent
    static func read(directory: URL, task: TranslationTaskRecord) async -> Self {
        var activity = Self()
        let status = json(directory.appendingPathComponent("engine-status.json"))
        if status["requestID"].string == task.input.requestID {
            for stage in ["detect", "ocr", "translate", "inpaint"] {
                let count = status["stages"][stage].number
                if count.isFinite, count >= 0, count <= Double(task.input.pageCount) {
                    activity.stages[stage] = Int(count)
                }
            }
            activity.setPreview(status["latestPage"], directory: directory, pageCount: task.input.pageCount)
        }
        // Completed tasks from earlier releases have only the final manifest.
        if activity.previewURL == nil, task.state == "delivered" {
            let result = json(directory.appendingPathComponent("result.json"))
            if let last = result["pages"].array.last {
                activity.setPreview(last, directory: directory, pageCount: task.input.pageCount)
            }
        }
        let module = json(directory.appendingPathComponent("preset.json"))["module"]
        for stage in activity.enabledStages where module["enable_" + stage] == .bool(false) {
            activity.enabledStages.remove(stage)
        }
        let llm = json(directory.appendingPathComponent("llm-output.json"))
        if llm["requestID"].string == task.input.requestID {
            activity.output = llm["text"].string
            activity.requestState = llm["state"].string
        }
        activity.log = tail(directory.appendingPathComponent("engine.log"))
        if activity.log.isEmpty { activity.log = tail(directory.appendingPathComponent("bridge.log")) }
        return activity
    }

    private mutating func setPreview(_ page: TranslationJSON, directory: URL, pageCount: Int) {
        let name = page["fileName"].string
        guard case .number(let index) = page["index"] else { return }
        guard !name.isEmpty, URL(fileURLWithPath: name).lastPathComponent == name,
              !name.contains("/"), !name.contains("\\"), name != ".", name != "..",
              index.isFinite, index >= 0, index < Double(pageCount), index.rounded() == index else { return }
        let root = directory.appendingPathComponent("project/result").resolvingSymlinksInPath()
        guard root.path.hasPrefix(directory.resolvingSymlinksInPath().path + "/") else { return }
        let url = root.appendingPathComponent(name).resolvingSymlinksInPath()
        guard url.deletingLastPathComponent() == root, FileManager.default.fileExists(atPath: url.path) else { return }
        previewURL = url
        previewIndex = Int(index)
    }

    private static func json(_ url: URL) -> TranslationJSON {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .null }
        defer { try? handle.close() }
        let limit = 4 * 1024 * 1024
        guard let data = try? handle.read(upToCount: limit + 1), data.count <= limit,
              let value = try? JSONDecoder().decode(TranslationJSON.self, from: data) else { return .null }
        return value
    }

    private static func tail(_ url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return "" }
        try? handle.seek(toOffset: size > 32_768 ? size - 32_768 : 0)
        guard let data = try? handle.read(upToCount: 32_768) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
#endif
