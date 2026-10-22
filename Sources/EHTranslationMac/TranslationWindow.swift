#if os(macOS)
import AppKit
import SwiftUI
import EHDomain
import EHDownloads

public struct TranslationWindow: View {
    @Bindable private var workspace: TranslationWorkspace
    private let available: [DownloadJob]
    private let downloads: DownloadFileStore
    @State private var section = "current"
    @State private var showingPicker = false
    @State private var selectedBooks = Set<GalleryKey>()
    @State private var historySelection: UUID?
    @State private var historySearch = ""
    @State private var settingsTab = "translation"

    public init(workspace: TranslationWorkspace, available: [DownloadJob], downloads: DownloadFileStore) {
        self.workspace = workspace
        self.available = available.filter { $0.state == .completed }
        self.downloads = downloads
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Label("当前任务", systemImage: "play.rectangle").badge(workspace.currentTasks.count).tag("current")
                Label("历史任务", systemImage: "clock.arrow.circlepath").tag("history")
                Label("设置", systemImage: "slider.horizontal.3").tag("settings")
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 230)
            .safeAreaInset(edge: .bottom) {
                if workspace.coordinator.isBusy {
                    Label("后台正在处理", systemImage: "gearshape.2").font(.caption).foregroundStyle(.secondary).padding()
                }
            }
        } detail: {
            VStack(spacing: 0) {
                if let error = workspace.error {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                        Text(error).textSelection(.enabled)
                        Spacer()
                        Button("关闭", systemImage: "xmark") { workspace.error = nil }.labelStyle(.iconOnly)
                    }
                    .font(.callout).padding().background(.orange.opacity(0.12))
                }
                switch section {
                case "settings":
                    VStack(spacing: 0) {
                        Picker("设置分类", selection: $settingsTab) {
                            Text("翻译配置").tag("translation")
                            Text("环境与模型").tag("environment")
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 360)
                        .padding()
                        Divider()
                        if settingsTab == "environment" {
                            TranslationEnvironmentView(workspace: workspace)
                        } else {
                            TranslationSettingsView(workspace: workspace)
                        }
                    }
                case "history": historyView
                default: currentView
                }
            }
            .navigationTitle(section == "current" ? "当前任务" : section == "history" ? "历史任务" : "翻译设置")
        }
        .frame(minWidth: 960, minHeight: 680)
        .sheet(isPresented: $showingPicker) { bookPicker }
        .task {
            await workspace.importReadyResults()
            if workspace.focusedTaskID == nil {
                workspace.focusedTaskID = workspace.currentTasks.first(where: \.isActive)?.id ?? workspace.currentTasks.first?.id
            }
            if !workspace.coordinator.enginePath.isEmpty { workspace.configureFromInstallation() }
            if !workspace.coordinator.enginePath.isEmpty, workspace.catalog.object.isEmpty, !workspace.coordinator.isBusy {
                workspace.coordinator.perform("catalog", workspace: workspace)
            }
        }
        .onChange(of: workspace.focusedTaskID) { _, id in
            if workspace.currentTasks.contains(where: { $0.id == id }) { section = "current" }
        }
    }

    private var currentTask: TranslationTaskRecord? {
        let focused = workspace.tasks.first { $0.id == workspace.focusedTaskID }
        if let focused, focused.isCurrent { return focused }
        return workspace.currentTasks.first(where: \.isActive) ?? workspace.currentTasks.first ?? focused
    }

    private var currentView: some View {
        VStack(spacing: 0) {
            if workspace.currentTasks.isEmpty && currentTask == nil {
                ContentUnavailableView {
                    Label("添加漫画开始翻译", systemImage: "character.book.closed")
                } description: {
                    Text("选择完整下载的漫画，确认语言和模型后手动开始。关闭此窗口后，任务仍会继续。")
                } actions: {
                    Button("添加漫画", systemImage: "plus") { showingPicker = true }.buttonStyle(.borderedProminent)
                    Button("配置环境与模型") { settingsTab = "environment"; section = "settings" }
                }
            } else {
                if !workspace.currentTasks.isEmpty {
                    Table(workspace.currentTasks, selection: $workspace.focusedTaskID) {
                        TableColumn("漫画") { task in Text(task.input.gallery.title).lineLimit(2) }
                        TableColumn("状态") { task in Text(task.stateTitle) }.width(100)
                        TableColumn("已生成") { task in Text("\(task.completedPages) / \(task.input.pageCount)").monospacedDigit() }.width(85)
                    }
                    .frame(height: min(150, CGFloat(workspace.currentTasks.count) * 34 + 32))
                    Divider()
                }
                if let task = currentTask {
                    TranslationTaskDetailView(workspace: workspace, task: task)
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button("添加漫画", systemImage: "plus") { selectedBooks = []; showingPicker = true }
                    .disabled(workspace.isAdding || workspace.coordinator.isDraining)
                    .accessibilityIdentifier("translation-add-books")
            }
        }
    }

    private var historyTasks: [TranslationTaskRecord] {
        workspace.historyTasks.filter { historySearch.isEmpty || $0.input.gallery.title.localizedStandardContains(historySearch) }
    }

    private var historyView: some View {
        VStack(spacing: 0) {
            if workspace.historyTasks.isEmpty {
                ContentUnavailableView("暂无历史任务", systemImage: "clock.arrow.circlepath",
                                       description: Text("已完成、失败、取消和中断的任务会保留在这里。"))
            } else {
                Table(historyTasks, selection: $historySelection) {
                    TableColumn("漫画") { task in Text(task.input.gallery.title).lineLimit(2) }
                    TableColumn("状态") { task in Text(task.stateTitle).foregroundStyle(task.state == "failed" ? .red : .secondary) }.width(100)
                    TableColumn("目标语言", value: \.targetLanguage).width(100)
                    TableColumn("创建时间") { task in Text(task.created, format: .dateTime.month().day().hour().minute()) }.width(130)
                }
                .frame(minHeight: 110, idealHeight: 150, maxHeight: 210)
                .overlay { if historyTasks.isEmpty { ContentUnavailableView.search(text: historySearch) } }
                Divider()
                if let task = historyTasks.first(where: { $0.id == historySelection }) {
                    TranslationTaskDetailView(workspace: workspace, task: task)
                } else {
                    ContentUnavailableView("选择一个历史任务", systemImage: "doc.text.magnifyingglass",
                                           description: Text("查看译图、模型输出与诊断，或建立重试任务。"))
                }
            }
        }
        .searchable(text: $historySearch, prompt: "搜索历史任务")
    }

    private var bookPicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("添加漫画").font(.title2.bold())
            Text("仅列出已完整下载的漫画；添加后不会自动开始。").foregroundStyle(.secondary)
            List(available, id: \.key, selection: $selectedBooks) { job in
                HStack { Text(job.title).lineLimit(2); Spacer(); Text("\(job.totalPageCount) 页").foregroundStyle(.secondary) }
            }.overlay { if available.isEmpty { ContentUnavailableView("没有完整下载的漫画", systemImage: "books.vertical") } }
            HStack {
                Spacer()
                Button("取消") { showingPicker = false }
                Button("添加所选漫画") {
                    let selected = available.filter { selectedBooks.contains($0.key) }
                    showingPicker = false
                    Task { await workspace.add(selected, downloads: downloads) }
                }.buttonStyle(.borderedProminent).disabled(selectedBooks.isEmpty)
            }
        }.padding(24).frame(width: 620, height: 480)
    }
}
#endif
