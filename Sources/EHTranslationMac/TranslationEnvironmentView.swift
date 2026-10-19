#if os(macOS)
import AppKit
import SwiftUI

struct TranslationEnvironmentView: View {
    @Bindable var workspace: TranslationWorkspace
    @State private var showingPreparation = false
    @State private var preparationLog = ""
    private var coordinator: TranslationCoordinator { workspace.coordinator }

    var body: some View {
        Form {
            Section("BallonsTranslator 安装") {
                LabeledContent("安装目录") {
                    Text(coordinator.enginePath.isEmpty ? "尚未选择" : coordinator.enginePath).textSelection(.enabled).lineLimit(3)
                }
                Button("选择安装目录…", systemImage: "folder") { chooseDirectory() }
                    .disabled(coordinator.isBusy || coordinator.isDraining)
                LabeledContent("备用解释器") {
                    Text(coordinator.interpreterPath.isEmpty ? "优先使用安装内的 .venv/bin/python" : coordinator.interpreterPath).lineLimit(3)
                }
                Button("选择 Python 3.10–3.12…") { chooseInterpreter() }.disabled(coordinator.isBusy || coordinator.isDraining)
                Text("复用现有 Python 环境和模型，不复制权重。源码与原软件配置保持只读。").font(.caption).foregroundStyle(.secondary)
            }
            Section("环境状态") {
                Text(workspace.environmentSummary)
                if coordinator.isBusy { ProgressView().controlSize(.small) }
                if !workspace.report["python"].string.isEmpty { LabeledContent("Python", value: workspace.report["python"].string) }
                ForEach(workspace.report["packages"].array.map(\.string), id: \.self) { item in
                    Label(item, systemImage: "shippingbox").textSelection(.enabled)
                }
                ForEach(workspace.report["files"].array.map(\.string), id: \.self) { item in
                    Label(item, systemImage: "arrow.down.doc").textSelection(.enabled)
                }
                HStack {
                    Button("检查环境", systemImage: "checkmark.shield") { coordinator.perform("check", workspace: workspace) }
                    Button("刷新模型目录", systemImage: "arrow.clockwise") { coordinator.perform("catalog", workspace: workspace) }
                }.disabled(coordinator.isBusy || coordinator.enginePath.isEmpty || coordinator.isDraining)
            }
            Section("手动准备") {
                Text("仅在点击开始后安装缺失依赖、下载所选模型；写入范围为安装内的 .venv、data/models 和应用私有缓存。不执行整套安装脚本，不更新源码。").foregroundStyle(.secondary)
                Button("准备环境与模型…", systemImage: "arrow.down.circle") { showingPreparation = true }
                    .disabled(coordinator.isBusy || coordinator.enginePath.isEmpty || workspace.configuration["module"].object.isEmpty || coordinator.isDraining || workspace.checkedConfiguration != workspace.configuration)
                if workspace.checkedConfiguration != workspace.configuration {
                    Text("开始准备前，请先检查当前配置的缺失项目。").font(.caption).foregroundStyle(.secondary)
                }
                if coordinator.preparingProfileID == workspace.profileID {
                    Button("停止准备", systemImage: "stop") { coordinator.stopPreparation(profileID: workspace.profileID) }
                }
                Button("打开工作与诊断目录", systemImage: "folder") { NSWorkspace.shared.open(workspace.root) }
                if !preparationLog.isEmpty {
                    DisclosureGroup("准备进度与日志") {
                        Text(preparationLog).font(.caption.monospaced()).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            while !Task.isCancelled {
                let path = workspace.root.appendingPathComponent("bridge.log")
                if let handle = try? FileHandle(forReadingFrom: path) {
                    let size = (try? handle.seekToEnd()) ?? 0
                    try? handle.seek(toOffset: size > 4096 ? size - 4096 : 0)
                    if let data = try? handle.readToEnd() { preparationLog = String(decoding: data, as: UTF8.self) }
                    try? handle.close()
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
        .confirmationDialog("准备所选模型与运行环境？", isPresented: $showingPreparation) {
            Button("开始准备") { coordinator.perform("prepare", workspace: workspace) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将使用上游依赖管理和模型下载接口，可能下载较大文件。上方列出已检查的缺失项；停止后请重新检查，安装过程不提供回滚。写入：\(coordinator.enginePath)/.venv、data/models，以及应用工作目录。")
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.message = "选择现有 BallonsTranslator 安装目录"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard FileManager.default.fileExists(atPath: url.appendingPathComponent("ballontranslator/launch.py").path) else {
                workspace.error = "所选目录不是 BallonsTranslator 安装。"; return
            }
            coordinator.enginePath = url.path
            workspace.checkedConfiguration = nil
            workspace.configureFromInstallation()
            coordinator.perform("catalog", workspace: workspace)
        }
    }

    private func chooseInterpreter() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.allowsMultipleSelection = false; panel.message = "缺少 .venv 时，用此解释器创建环境；不会安装系统工具。"
        panel.begin { response in
            if response == .OK, let url = panel.url { coordinator.interpreterPath = url.path }
        }
    }
}
#endif
