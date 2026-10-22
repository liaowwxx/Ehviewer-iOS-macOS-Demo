#if os(macOS)
import Foundation
import Testing
import EHDomain
import EHDownloads
@testable import EHTranslationMac

struct TranslationTaskActivityTests {
    private func record(state: String = "running") -> TranslationTaskRecord {
        let id = UUID()
        return TranslationTaskRecord(id: id, input: .init(formatVersion: 1, requestID: id.uuidString.lowercased(),
            gallery: .init(key: .init(gid: 1, token: "activity"), title: "Activity"), pageCount: 3, pages: []),
            created: .now, state: state)
    }

    @Test(arguments: ["queued", "accepted", "preparing", "running", "rendering", "awaitingImport"])
    func unfinishedTasksStayInCurrentTasks(state: String) {
        #expect(record(state: state).isCurrent)
    }

    @Test(arguments: ["delivered", "failed", "cancelled", "interrupted"])
    func terminalTasksBelongToHistory(state: String) {
        #expect(record(state: state).isCurrent == false)
    }

    @Test func activityReadsSavedPreviewAndBoundedOutput() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TranslationActivity-\(UUID())")
        let task = record()
        let image = directory.appendingPathComponent("project/result/page.png")
        try TranslationWorkspace.write(Data([1]), to: image)
        let status: TranslationJSON = .object([
            "requestID": .string(task.input.requestID), "stages": .object(["ocr": .number(2)]),
            "latestPage": .object(["index": .number(1), "fileName": .string("page.png")])
        ])
        try TranslationWorkspace.write(JSONEncoder().encode(status), to: directory.appendingPathComponent("engine-status.json"))
        try TranslationWorkspace.write(Data("{\"module\":{\"enable_detect\":false}}".utf8), to: directory.appendingPathComponent("preset.json"))
        let llm: TranslationJSON = .object(["requestID": .string(task.input.requestID), "text": .string("你好"), "state": .string("received")])
        try TranslationWorkspace.write(JSONEncoder().encode(llm), to: directory.appendingPathComponent("llm-output.json"))
        try TranslationWorkspace.write(Data(String(repeating: "x", count: 100_000).utf8), to: directory.appendingPathComponent("engine.log"))

        let activity = await TranslationTaskActivity.read(directory: directory, task: task)
        #expect(activity.previewURL == image)
        #expect(activity.previewIndex == 1)
        #expect(activity.stages["ocr"] == 2)
        #expect(activity.enabledStages.contains("detect") == false)
        #expect(activity.output == "你好")
        #expect(activity.requestState == "received")
        #expect(activity.log.utf8.count == 32_768)
    }

    @Test(arguments: ["../outside.png", "/tmp/outside.png", "page.png"])
    func invalidOrForeignPreviewIsIgnored(name: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TranslationActivity-\(UUID())")
        let task = record()
        try TranslationWorkspace.write(Data([1]), to: directory.appendingPathComponent("project/result/page.png"))
        var status: TranslationJSON = .object([
            "requestID": .string(task.input.requestID),
            "latestPage": .object(["index": .number(name == "page.png" ? 3 : 0), "fileName": .string(name)])
        ])
        try TranslationWorkspace.write(JSONEncoder().encode(status), to: directory.appendingPathComponent("engine-status.json"))
        #expect(await TranslationTaskActivity.read(directory: directory, task: task).previewURL == nil)
        status["requestID"] = .string("another-task")
        status["latestPage"] = .object(["index": .number(0), "fileName": .string("page.png")])
        try TranslationWorkspace.write(JSONEncoder().encode(status), to: directory.appendingPathComponent("engine-status.json"))
        #expect(await TranslationTaskActivity.read(directory: directory, task: task).previewURL == nil)
    }

    @Test func completedLegacyTaskUsesFinalManifestForPreview() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TranslationActivity-\(UUID())")
        let image = directory.appendingPathComponent("project/result/last.png")
        try TranslationWorkspace.write(Data([1]), to: image)
        let manifest: TranslationJSON = .object([
            "pages": .array([.object(["index": .number(2), "fileName": .string("last.png")])]),
            "extension": .string(String(repeating: "x", count: 1_100_000))
        ])
        try TranslationWorkspace.write(JSONEncoder().encode(manifest), to: directory.appendingPathComponent("result.json"))
        let activity = await TranslationTaskActivity.read(directory: directory, task: record(state: "delivered"))
        #expect(activity.previewURL == image)
        #expect(activity.previewIndex == 2)
    }

    @Test @MainActor func progressRejectsAnotherTasksStatus() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TranslationActivity-\(UUID())")
        let task = record(state: "queued")
        try TranslationWorkspace.write(JSONEncoder().encode([task]), to: root.appendingPathComponent("NativeWorkstation/tasks.json"))
        let workspace = TranslationWorkspace(profileID: UUID(), files: TranslationFileStore(root: root), coordinator: TranslationCoordinator())
        workspace.update(task.id, state: "running")
        try TranslationWorkspace.write(Data("{\"requestID\":\"foreign\",\"completedPages\":3,\"state\":\"rendering\"}".utf8),
                                       to: workspace.directory(task.id).appendingPathComponent("engine-status.json"))
        workspace.refreshProgress(task.id)
        #expect(workspace.tasks.first?.completedPages == 0)
        #expect(workspace.tasks.first?.state == "running")
    }
}
#endif
