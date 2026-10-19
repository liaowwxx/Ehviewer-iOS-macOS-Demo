#if os(macOS)
import AppKit
import SwiftUI
import EHDomain
import EHDownloads

public struct TranslationWindow: View {
    @Bindable private var workspace: TranslationWorkspace
    private let available: [DownloadJob]
    private let downloads: DownloadFileStore
    @State private var section = "tasks"
    @State private var showingPicker = false
    @State private var selectedBooks = Set<GalleryKey>()
    @State private var filter = "all"

    public init(workspace: TranslationWorkspace, available: [DownloadJob], downloads: DownloadFileStore) {
        self.workspace = workspace
        self.available = available.filter { $0.state == .completed }
        self.downloads = downloads
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Label("任务", systemImage: "list.bullet.rectangle").tag("tasks")
                Label("翻译设置", systemImage: "slider.horizontal.3").tag("settings")
                Label("环境与模型", systemImage: "shippingbox").tag("environment")
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
                case "settings": TranslationSettingsView(workspace: workspace)
                case "environment": TranslationEnvironmentView(workspace: workspace)
                default: tasksView
                }
            }
            .navigationTitle(section == "tasks" ? "漫画翻译" : section == "settings" ? "翻译设置" : "环境与模型")
        }
        .frame(minWidth: 880, minHeight: 600)
        .sheet(isPresented: $showingPicker) { bookPicker }
        .task {
            await workspace.importReadyResults()
            if workspace.focusedTaskID == nil { workspace.focusedTaskID = workspace.tasks.last?.id }
            if !workspace.coordinator.enginePath.isEmpty { workspace.configureFromInstallation() }
            if !workspace.coordinator.enginePath.isEmpty, workspace.catalog.object.isEmpty, !workspace.coordinator.isBusy {
                workspace.coordinator.perform("catalog", workspace: workspace)
            }
        }
        .onChange(of: workspace.focusedTaskID) { _, id in
            if !filteredTasks.contains(where: { $0.id == id }) { filter = "all" }
        }
    }

    private var filteredTasks: [TranslationTaskRecord] {
        workspace.tasks.filter { filter == "all" || (filter == "active" ? $0.isActive || $0.canStart : $0.state == "delivered") }
    }

    private var tasksView: some View {
        VStack(spacing: 0) {
            if workspace.tasks.isEmpty {
                ContentUnavailableView {
                    Label("添加漫画开始翻译", systemImage: "character.book.closed")
                } description: {
                    Text("选择完整下载的漫画，确认语言和模型后手动开始。关闭此窗口后，任务仍会继续。")
                } actions: {
                    Button("添加漫画", systemImage: "plus") { showingPicker = true }.buttonStyle(.borderedProminent)
                    Button("配置环境与模型") { section = "environment" }
                }
            } else {
                Table(filteredTasks, selection: $workspace.focusedTaskID) {
                    TableColumn("漫画") { task in Text(task.input.gallery.title).lineLimit(2) }
                    TableColumn("状态") { task in Text(task.stateTitle).foregroundStyle(task.state == "failed" ? .red : .secondary) }.width(100)
                    TableColumn("页数") { task in Text("\(task.completedPages) / \(task.input.pageCount)").monospacedDigit() }.width(85)
                    TableColumn("目标语言", value: \.targetLanguage).width(110)
                }
                .alternatingRowBackgrounds(.disabled)
                if let task = workspace.tasks.first(where: { $0.id == workspace.focusedTaskID }) {
                    Divider()
                    taskInspector(task).padding(20)
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Picker("筛选任务", selection: $filter) {
                    Text("全部").tag("all"); Text("待处理").tag("active"); Text("已完成").tag("completed")
                }.frame(width: 120)
            }
            ToolbarItem {
                Button("添加漫画", systemImage: "plus") { showingPicker = true }
                    .disabled(workspace.isAdding || workspace.coordinator.isDraining)
                    .accessibilityIdentifier("translation-add-books")
            }
        }
    }

    private func taskInspector(_ task: TranslationTaskRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(task.input.gallery.title).font(.headline).textSelection(.enabled)
            Text("\(task.input.pageCount) 页 · \(task.stateTitle)").foregroundStyle(.secondary)
            if let error = task.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if task.canStart {
                    Button("开始翻译", systemImage: "play.fill") { workspace.start(task.id) }
                        .buttonStyle(.borderedProminent).disabled(workspace.coordinator.isDraining)
                }
                if task.isActive || task.canStart { Button("取消任务", systemImage: "stop") { workspace.cancel(task.id) } }
                if task.canRetry {
                    Button(task.state == "delivered" ? "重新翻译" : "建立重试任务", systemImage: "arrow.clockwise") {
                        Task { await workspace.retry(task.id) }
                    }.disabled(workspace.coordinator.isDraining)
                }
                Spacer()
                Button("打开诊断目录", systemImage: "folder") { NSWorkspace.shared.open(workspace.directory(task.id)) }
            }
        }
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
