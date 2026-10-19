#if os(macOS)
import Foundation
import Testing
import EHDomain
import EHDownloads
@testable import EHTranslationMac

struct TranslationWorkstationTests {
    @Test func parameterEditsPreserveUnknownFieldsAndDescriptors() throws {
        let original = Data(#"{"module":{"ocr":"test","ocr_params":{"test":{"device":{"type":"selector","options":["cpu","mps"],"value":"cpu","extension":17}}}},"future":{"nested":[true,null,4]}}"#.utf8)
        var value = try JSONDecoder().decode(TranslationJSON.self, from: original)
        value[path: ["module", "ocr_params", "test", "device", "value"]] = .string("mps")
        let restored = try JSONDecoder().decode(TranslationJSON.self, from: JSONEncoder().encode(value))
        #expect(restored["module"]["ocr_params"]["test"]["device"]["extension"] == .number(17))
        #expect(restored["future"]["nested"] == .array([.bool(true), .null, .number(4)]))
        #expect(restored["module"]["ocr_params"]["test"]["device"]["value"] == .string("mps"))
    }

    @Test func portableCredentialIsNotTreatedAsAModelParameterDescriptor() throws {
        let secret: TranslationJSON = .object(["storage": .string("portable_obfuscated"), "version": .number(1), "value": .string("encoded-value")])
        #expect(secret.isParameterDescriptor == false)
        #expect(TranslationJSON.object(["type": .string("selector"), "value": .string("cpu")]).isParameterDescriptor)
    }

    @Test @MainActor func recoveryNeverAutomaticallyRestartsAcceptedTasks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TranslationTest-\(UUID())")
        let id = UUID()
        let input = TranslationInput(formatVersion: 1, requestID: id.uuidString.lowercased(),
                                     gallery: .init(key: .init(gid: 1, token: "test"), title: "Test"), pageCount: 1, pages: [])
        let task = TranslationTaskRecord(id: id, input: input, created: .now, state: "accepted")
        let file = root.appendingPathComponent("NativeWorkstation/tasks.json")
        try TranslationWorkspace.write(JSONEncoder().encode([task]), to: file)
        let workspace = TranslationWorkspace(profileID: UUID(), files: TranslationFileStore(root: root), coordinator: .shared)
        #expect(workspace.tasks.count == 1)
        #expect(workspace.tasks.first?.state == "interrupted")
        #expect(workspace.tasks.first?.canStart == false)
        #expect(workspace.tasks.first?.canRetry == true)
    }

    @Test @MainActor func invalidLLMCapabilitiesPreventStarting() throws {
        let workspace = TranslationWorkspace(profileID: UUID(), files: TranslationFileStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), coordinator: .shared)
        workspace.configuration = .object(["module": .object([
            "translate_target": .string("简体中文"), "translator": .string("LLMTranslator"),
            "translator_llm_id": .string("vision-only"), "llm_profiles": .array([
                .object(["id": .string("vision-only"), "support_vision": .bool(true), "support_text": .bool(false)])
            ])
        ])])
        #expect(throws: TranslationBridgeError.self) { try workspace.validateSettings() }
    }

    @Test @MainActor func externalPresetRevisionIsNotOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TranslationTest-\(UUID())")
        let workspace = TranslationWorkspace(profileID: UUID(), files: TranslationFileStore(root: root), coordinator: .shared)
        workspace.configuration = .object(["module": .object(["translate_target": .string("English")])])
        workspace.saveSettings()
        let target = workspace.root.appendingPathComponent("preset.json")
        let replacement = Data(#"{"module":{"translate_target":"日本語"}}"#.utf8)
        try replacement.write(to: target)
        workspace.saveSettings()
        #expect(workspace.error != nil)
        #expect(try Data(contentsOf: target) == replacement)
        let attrs = try FileManager.default.attributesOfItem(atPath: target.path)
        #expect((attrs[.posixPermissions] as? Int) == 0o600)
    }

    @Test func incompleteDownloadCannotCreateAnInputSnapshot() async throws {
        let key = GalleryKey(gid: 42, token: "incomplete")
        let job = DownloadJob(key: key, title: "Incomplete", pages: [], totalPageCount: 2)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        await #expect(throws: TranslationBridgeError.self) {
            try await TranslationWorkspace.snapshot(job, downloads: DownloadFileStore(root: root), directory: root.appendingPathComponent("job"), id: UUID())
        }
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("job/request.json").path) == false)
    }

    @Test(.timeLimit(.minutes(1))) func privatePipeRepliesAndCancellationReapHelper() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TranslationProcessTest-\(UUID())")
        let bridge = root.appendingPathComponent("bridge")
        try FileManager.default.createDirectory(at: bridge, withIntermediateDirectories: true)
        try Data().write(to: bridge.appendingPathComponent("__init__.py"))
        let script = """
        import json,sys,time
        from pathlib import Path
        request=json.loads(sys.stdin.readline())
        if request['command']=='sleep':
            Path(request['marker']).write_text('ready')
            time.sleep(90)
        else:
            print(json.dumps({'result':{'ok':True}}),flush=True)
        """
        try Data(script.utf8).write(to: bridge.appendingPathComponent("service.py"))
        let runner = TranslationProcess(bridgeDirectory: bridge)
        let python = URL(fileURLWithPath: "/usr/bin/python3")
        let reply = try await runner.request(python: python, payload: .object(["command": .string("echo")]), log: root.appendingPathComponent("reply.log"))
        #expect(reply["ok"].bool)
        let marker = root.appendingPathComponent("started")
        let request = Task { try await runner.request(python: python, payload: .object(["command": .string("sleep"), "marker": .string(marker.path)]), log: root.appendingPathComponent("cancel.log")) }
        let deadline = ContinuousClock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: marker.path), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(FileManager.default.fileExists(atPath: marker.path))
        request.cancel()
        do { _ = try await request.value; Issue.record("Cancelled helper unexpectedly succeeded") }
        catch { #expect(error is CancellationError || error is DecodingError) }
        // A second request proves the previous owner was fully released.
        let after = try await runner.request(python: python, payload: .object(["command": .string("echo")]), log: root.appendingPathComponent("after.log"))
        #expect(after["ok"].bool)
    }

    @Test @MainActor func wholeBookImportWaitsForOwnerProfileAndIsIdempotent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TranslationImportTest-\(UUID())")
        let files = TranslationFileStore(root: root)
        let restoredSessionFiles = TranslationFileStore(root: root)
        #expect(try await restoredSessionFiles.allManifests().isEmpty)
        let coordinator = TranslationCoordinator()
        let owner = UUID(), id = UUID(), key = GalleryKey(gid: 55, token: "profile-import")
        let workspaceRoot = root.appendingPathComponent("NativeWorkstation")
        let directory = workspaceRoot.appendingPathComponent("jobs/\(id.uuidString.lowercased())")
        let result = directory.appendingPathComponent("project/result/page-00000.png")
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6qVQAAAAASUVORK5CYII="))
        try TranslationWorkspace.write(png, to: result)
        let sha = try TranslationFileStore.sha256(of: result)
        let input = TranslationInput(formatVersion: 1, requestID: id.uuidString.lowercased(), gallery: .init(key: key, title: "Test"), pageCount: 1,
                                     pages: [.init(index: 0, fileName: result.lastPathComponent, byteCount: Int64(png.count), sha256: sha)])
        let record = TranslationTaskRecord(id: id, input: input, created: .now, state: "awaitingImport")
        try TranslationWorkspace.write(JSONEncoder().encode([record]), to: workspaceRoot.appendingPathComponent("tasks.json"))
        let manifest = GalleryTranslationManifest(versionID: UUID(), gallery: input.gallery, createdAt: Date.now.timeIntervalSince1970,
                                                  targetLanguage: "English", presetFingerprint: String(repeating: "a", count: 64),
                                                  pages: [.init(index: 0, fileName: result.lastPathComponent, byteCount: Int64(png.count), sha256: sha, sourceSHA256: sha)])
        try TranslationWorkspace.write(JSONEncoder().encode(manifest), to: directory.appendingPathComponent("result.json"))
        let workspace = coordinator.workspace(profileID: owner, files: files)
        coordinator.activate(UUID())
        await workspace.importReadyResults()
        #expect(try await files.allManifests().isEmpty)
        coordinator.activate(owner)
        await workspace.importReadyResults()
        #expect(workspace.tasks.first?.state == "delivered")
        #expect(workspace.tasks.first?.completedPages == 1)
        try await files.importVersion(manifest, pagesDirectory: directory.appendingPathComponent("project/result"))
        #expect(try await files.allManifests().count == 1)
        #expect(try await restoredSessionFiles.allManifests(refresh: true).count == 1)
        #expect(try await restoredSessionFiles.data(for: key, versionID: manifest.versionID, index: 0) == png)
    }
}
#endif
