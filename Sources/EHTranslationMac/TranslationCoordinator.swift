#if os(macOS)
import AppKit
import Foundation
import Observation
import EHDomain
import EHDownloads

/// Application-owned scheduler; windows never own the engine lifetime.
@MainActor @Observable
public final class TranslationCoordinator {
    public static let shared = TranslationCoordinator()
    public private(set) var workspaces: [UUID: TranslationWorkspace] = [:]
    public var enginePath: String {
        didSet {
            UserDefaults.standard.set(enginePath, forKey: "translation.native.engine")
            for workspace in workspaces.values {
                workspace.catalog = .object([:]); workspace.report = .object([:]); workspace.checkedConfiguration = nil
            }
        }
    }
    public var interpreterPath: String {
        didSet { UserDefaults.standard.set(interpreterPath, forKey: "translation.native.python") }
    }
    public private(set) var isBusy = false
    public private(set) var isDraining = false
    public private(set) var activeProfile: UUID?
    public private(set) var preparingProfileID: UUID?
    private let runner = TranslationProcess()
    private var operation: Task<Void, Never>?
    private var pending: [(TranslationWorkspace, UUID)] = []
    private var running: (TranslationWorkspace, UUID)?
    private var helperProfileID: UUID?
    private var quitReply: (@MainActor () -> Void)?

    init() {
        enginePath = UserDefaults.standard.string(forKey: "translation.native.engine") ?? ""
        interpreterPath = UserDefaults.standard.string(forKey: "translation.native.python") ?? ""
    }

    public func workspace(profileID: UUID, files: TranslationFileStore) -> TranslationWorkspace {
        if let workspace = workspaces[profileID] { return workspace }
        let workspace = TranslationWorkspace(profileID: profileID, files: files, coordinator: self)
        workspace.catalog = workspaces.values.first(where: { !$0.catalog.object.isEmpty })?.catalog ?? .object([:])
        workspaces[profileID] = workspace
        return workspace
    }

    public func activate(_ profileID: UUID?) {
        activeProfile = profileID
        if let profileID, let workspace = workspaces[profileID] {
            Task { await workspace.importReadyResults() }
        }
    }

    var python: URL? {
        let installed = URL(fileURLWithPath: enginePath).appendingPathComponent(".venv/bin/python")
        if FileManager.default.isExecutableFile(atPath: installed.path) { return installed }
        if !interpreterPath.isEmpty, FileManager.default.isExecutableFile(atPath: interpreterPath) {
            return URL(fileURLWithPath: interpreterPath)
        }
        return nil
    }

    func call(_ command: String, workspace: TranslationWorkspace, directory: URL? = nil, profileID: String? = nil) async throws -> TranslationJSON {
        guard !enginePath.isEmpty, let python else {
            throw TranslationBridgeError(message: "请选择 BallonsTranslator 目录；缺少虚拟环境时请先选择兼容的 Python 3.10–3.12。")
        }
        var payload: TranslationJSON = .object([
            "command": .string(command), "engine": .string(enginePath), "root": .string(workspace.root.path),
            "config": workspace.configuration
        ])
        if let directory { payload["directory"] = .string(directory.path) }
        if let profileID { payload["profileID"] = .string(profileID) }
        // Running books always use the immutable saved snapshot.
        if command == "run", let directory {
            payload["config"] = try JSONDecoder().decode(TranslationJSON.self, from: Data(contentsOf: directory.appendingPathComponent("preset.json")))
        }
        return try await runner.request(python: python, payload: payload,
                                        log: (directory ?? workspace.root).appendingPathComponent("bridge.log"))
    }

    func perform(_ command: String, workspace: TranslationWorkspace, profileID: String? = nil) {
        guard !isBusy, !isDraining else { return }
        isBusy = true
        helperProfileID = workspace.profileID
        if command == "prepare" { preparingProfileID = workspace.profileID }
        workspace.error = nil
        let requestedProfile = workspace.configuration["module"]["llm_profiles"].array.first { $0["id"].string == profileID }
        operation = Task {
            defer { helperProfileID = nil; preparingProfileID = nil; isBusy = false; operation = nil; startNext() }
            do {
                if command == "prepare" {
                    workspace.environmentSummary = "正在准备依赖与模型…"
                    _ = try await call(command, workspace: workspace)
                    // A fresh interpreter verifies the actual installation.
                    let checked = workspace.configuration
                    workspace.report = try await call("check", workspace: workspace)
                    workspace.checkedConfiguration = checked
                } else if command == "models", let profileID, let requestedProfile {
                    let result = try await call(command, workspace: workspace, profileID: profileID)
                    try workspace.applyModelList(result["models"].array.map(\.string), to: requestedProfile)
                    return
                } else if command == "catalog" {
                    workspace.catalog = try await call(command, workspace: workspace)
                    for other in workspaces.values where other.profileID != workspace.profileID { other.catalog = workspace.catalog }
                } else {
                    let checked = workspace.configuration
                    workspace.report = try await call(command, workspace: workspace)
                    workspace.checkedConfiguration = checked
                }
                workspace.environmentSummary = command == "catalog" ? "模型目录已载入，请检查当前环境。" : workspace.report["ready"].bool ? "所选模型已就绪" : "请检查下方缺失项目"
            } catch is CancellationError { workspace.environmentSummary = "已停止，请重新检查实际状态" }
            catch { workspace.error = error.localizedDescription }
        }
    }

    func enqueue(_ workspace: TranslationWorkspace, id: UUID) {
        guard !isDraining, !pending.contains(where: { $0.1 == id }), running?.1 != id else { return }
        pending.append((workspace, id))
        workspace.update(id, state: "accepted")
        startNext()
    }

    func cancel(_ workspace: TranslationWorkspace, id: UUID) {
        guard workspace.tasks.contains(where: { $0.id == id }) else { return }
        pending.removeAll { $0.1 == id }
        workspace.update(id, state: "cancelled")
        if running?.1 == id { operation?.cancel() }
        finishDrainIfNeeded()
    }

    public func stopPreparation(profileID: UUID) {
        guard preparingProfileID == profileID else { return }
        operation?.cancel()
    }

    public func hasActiveWork(profileID: UUID) -> Bool {
        helperProfileID == profileID || workspaces[profileID]?.isAdding == true || workspaces[profileID]?.tasks.contains(where: \.isActive) == true
    }

    private func startNext() {
        guard !isBusy else { return }
        guard !pending.isEmpty else { finishDrainIfNeeded(); return }
        let (workspace, id) = pending.removeFirst()
        running = (workspace, id)
        isBusy = true
        workspace.update(id, state: "preparing")
        operation = Task {
            let progress = Task {
                while !Task.isCancelled {
                    workspace.refreshProgress(id)
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            defer {
                progress.cancel()
                running = nil; isBusy = false; operation = nil
                startNext()
            }
            do {
                _ = try await call("run", workspace: workspace, directory: workspace.directory(id))
                try Task.checkCancellation()
                workspace.update(id, state: "awaitingImport")
                await workspace.importReadyResults()
            } catch is CancellationError {
                if workspace.tasks.first(where: { $0.id == id })?.state != "cancelled" {
                    workspace.update(id, state: "interrupted")
                }
            } catch { workspace.update(id, state: "failed", error: error.localizedDescription) }
        }
    }

    public func drainAndQuit(_ reply: @escaping @MainActor () -> Void) {
        isDraining = true; quitReply = reply
        finishDrainIfNeeded()
    }

    public func stopAndQuit(_ reply: @escaping @MainActor () -> Void) {
        isDraining = true; quitReply = reply
        for (workspace, id) in pending { workspace.update(id, state: "interrupted") }
        pending.removeAll()
        operation?.cancel()
        finishDrainIfNeeded()
    }

    private func finishDrainIfNeeded() {
        guard isDraining, !isBusy, pending.isEmpty, let reply = quitReply else { return }
        quitReply = nil
        reply()
    }
}
#endif
