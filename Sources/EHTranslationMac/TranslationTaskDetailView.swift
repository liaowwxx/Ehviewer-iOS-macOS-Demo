#if os(macOS)
import AppKit
import SwiftUI

struct TranslationTaskDetailView: View {
    @Bindable var workspace: TranslationWorkspace
    let task: TranslationTaskRecord
    @State private var activity = TranslationTaskActivity()
    @State private var outputTab = "llm"
    @State private var followsOutput = true

    var body: some View {
        VStack(spacing: 0) {
            header.padding(20)
            Divider()
            HSplitView {
                TranslationPagePreview(url: activity.previewURL, pageIndex: activity.previewIndex)
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                output.frame(minWidth: 280, idealWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: task.id) {
            activity = TranslationTaskActivity()
            while !Task.isCancelled {
                guard let record = workspace.tasks.first(where: { $0.id == task.id }) else { return }
                let next = await TranslationTaskActivity.read(directory: workspace.directory(record.id), task: record)
                guard !Task.isCancelled else { return }
                activity = next
                if !record.isCurrent { return }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.input.gallery.title).font(.headline).lineLimit(2).textSelection(.enabled)
                    Text("\(task.stateTitle) · \(task.completedPages) / \(task.input.pageCount) 页")
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                actions
            }
            if let error = task.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if task.isActive || task.state == "awaitingImport" {
                ProgressView(value: Double(task.completedPages), total: Double(max(1, task.input.pageCount)))
                HStack(spacing: 16) {
                    ForEach(["detect", "ocr", "translate", "inpaint"], id: \.self) { stage in
                        if activity.enabledStages.contains(stage) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(stageTitle(stage)).foregroundStyle(.secondary)
                                ProgressView(value: Double(activity.stages[stage] ?? 0), total: Double(max(1, task.input.pageCount)))
                                Text("\(activity.stages[stage] ?? 0) / \(task.input.pageCount)").monospacedDigit()
                            }
                            .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private var actions: some View {
        HStack {
            if task.canStart {
                Button("开始翻译", systemImage: "play.fill") { workspace.start(task.id) }
                    .buttonStyle(.borderedProminent).disabled(workspace.coordinator.isDraining)
            }
            if task.isActive || task.canStart {
                Button("取消任务", systemImage: "stop") { workspace.cancel(task.id) }
            }
            if task.canRetry {
                Button(task.state == "delivered" ? "重新翻译" : "重试", systemImage: "arrow.clockwise") {
                    Task { await workspace.retry(task.id) }
                }.disabled(workspace.coordinator.isDraining)
            }
            Button("打开诊断目录", systemImage: "folder") { NSWorkspace.shared.open(workspace.directory(task.id)) }
                .labelStyle(.iconOnly).help("打开诊断目录")
        }
    }

    private var output: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("输出内容", selection: $outputTab) {
                Text("LLM 输出").tag("llm")
                Text("运行日志").tag("log")
            }.pickerStyle(.segmented).padding()
            HStack {
                if outputTab == "llm" {
                    Label(activity.requestState == "requesting" ? "正在等待模型响应" : activity.requestState == "failed" ? "请求失败" : "模型输出",
                          systemImage: activity.requestState == "requesting" ? "ellipsis.bubble" : "text.bubble")
                } else {
                    Label("运行日志", systemImage: "text.alignleft")
                }
                Spacer()
                Toggle("跟随输出", isOn: $followsOutput).toggleStyle(.checkbox)
            }
            .font(.caption).foregroundStyle(.secondary).padding(.horizontal).padding(.bottom, 12)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if outputText.isEmpty {
                            Text(outputTab == "llm" ? "等待模型输出…" : "暂无运行日志")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(outputText).textSelection(.enabled)
                        }
                        Color.clear.frame(height: 1).id("output-end")
                    }
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading).padding()
                }
                .onChange(of: outputText) { _, _ in
                    if followsOutput { proxy.scrollTo("output-end", anchor: .bottom) }
                }
                .onChange(of: followsOutput) { _, follows in
                    if follows { proxy.scrollTo("output-end", anchor: .bottom) }
                }
            }
        }
    }

    private var outputText: String { outputTab == "llm" ? activity.output : activity.log }

    private func stageTitle(_ stage: String) -> String {
        switch stage {
        case "detect": "文字检测"
        case "ocr": "OCR 识别"
        case "translate": "翻译"
        default: "图像修复"
        }
    }
}
#endif
