/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import ImageIO
import EHDomain
import EHDownloads

private enum SelectedGalleryShareFormat {
    case gallerySync
    case downloadArchive
}

struct DownloadsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let page: DownloadsPage
    @State private var jobs: [DownloadJob] = []
    @State private var localSummariesByKey: [GalleryKey: GallerySummary] = [:]
    @State private var editingJob: DownloadJob?
    @State private var labelInput = ""
    @State private var searchText = ""
    @State private var tagSearchSuggestions: [SearchTagSuggestion] = []
    @State private var isUpdatingTagSearchSuggestions = false
    @State private var showingResetProgressConfirmation = false
    @State private var jobPendingRemoval: DownloadJob?
    @State private var removalErrorMessage: String?
    @State private var jobPendingRedownload: DownloadJob?
    @State private var isSelectionMode = false
    @State private var selectedKeys: Set<GalleryKey> = []
    @State private var showingDeleteSelectedConfirmation = false
    @State private var bulkRemovalProgress: DownloadRemovalProgress?
    @State private var bulkRemovalTask: Task<Void, Never>?
    @State private var showingShareFormatDialog = false
    @State private var jobForReader: DownloadJob?
#if os(iOS)
    @State private var showingShareSheet = false
#else
    @State private var showingGallerySyncExporter = false
    @State private var gallerySyncExportDocument: GallerySyncExportDocument?
    @State private var gallerySyncExportFilename = "EhViewer-Galleries.ehgallery"
#endif

    init(page: DownloadsPage = .downloading) {
        self.page = page
    }

    private var pageJobs: [DownloadJob] {
        jobs.filter { page.contains($0) }
    }

    private var visibleJobs: [DownloadJob] {
        pageJobs
            .filter { page == .local || model.downloadStatusFilter.matches($0.state) }
            .filter {
                searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || $0.containsTitle(searchText)
                    || $0.containsTag(searchText)
                    || $0.tags.contains { model.displayTag($0).localizedCaseInsensitiveContains(searchText) }
                    || ($0.label?.localizedCaseInsensitiveContains(searchText) == true)
            }
            .sorted(by: effectiveSortOrder.areInIncreasingOrder)
    }

    private var availableSortOrders: [DownloadSortOrder] {
        if page == .local {
            return [.addedNewest, .addedOldest, .titleAscending, .titleDescending]
        }
        return Array(DownloadSortOrder.allCases)
    }

    private var effectiveSortOrder: DownloadSortOrder {
        availableSortOrders.contains(model.downloadSortOrder)
            ? model.downloadSortOrder
            : .titleAscending
    }

    var body: some View {
        @Bindable var model = model
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if let progress = bulkRemovalProgress {
                    bulkRemovalProgressView(progress)
                }
            }
            .navigationDestination(item: $jobForReader) { job in
                ReaderView(downloaded: job, initialPage: 0)
            }
            .confirmationDialog("重置所有下载内容的阅读进度？", isPresented: $showingResetProgressConfirmation, titleVisibility: .visible) {
                Button("重置进度", role: .destructive) {
                    Task { await model.resetAllDownloadReadingProgress() }
                }
                Button("取消", role: .cancel) {}
            }
            .confirmationDialog(
                "删除《\(displayTitle(for: jobPendingRemoval))》？",
                isPresented: Binding(
                    get: { jobPendingRemoval != nil },
                    set: { if $0 == false { jobPendingRemoval = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除下载及本地图片", role: .destructive) {
                    guard let job = jobPendingRemoval else { return }
                    jobPendingRemoval = nil
                    Task {
                        if case let .failed(message) = await model.downloads.remove(job.key) {
                            removalErrorMessage = message
                        }
                    }
                }
                .disabled(bulkRemovalProgress != nil)
                Button("取消", role: .cancel) { jobPendingRemoval = nil }
            } message: {
                Text("将移除 \(jobPendingRemoval?.completedPageIndexes.count ?? 0) 个已下载页面，并从下载列表中移除。")
            }
            .confirmationDialog(
                "重新下载《\(displayTitle(for: jobPendingRedownload))》？",
                isPresented: Binding(
                    get: { jobPendingRedownload != nil },
                    set: { if $0 == false { jobPendingRedownload = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("重新下载", role: .destructive) {
                    guard let job = jobPendingRedownload else { return }
                    jobPendingRedownload = nil
                    Task { await model.redownloadDownload(job.key) }
                }
                .disabled(bulkRemovalProgress != nil)
                Button("取消", role: .cancel) { jobPendingRedownload = nil }
            } message: {
                Text("将删除已下载的 \(jobPendingRedownload?.completedPageIndexes.count ?? 0) 个页面，并重新开始下载。")
            }
            .confirmationDialog(
                "删除选中的 \(selectedKeys.count) 项下载？",
                isPresented: $showingDeleteSelectedConfirmation,
                titleVisibility: .visible
            ) {
                Button("删除下载及本地图片", role: .destructive) {
                    deleteSelectedDownloads()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将移除所选下载的本地图片，并从下载列表中移除。")
            }
            .confirmationDialog(
                "选择分享格式",
                isPresented: $showingShareFormatDialog,
                titleVisibility: .visible
            ) {
                Button("元数据(.ehgallery)", systemImage: "doc.text") {
                    shareSelectedGalleries(as: .gallerySync)
                }
                Button("下载归档(.eharchive)", systemImage: "archivebox") {
                    shareSelectedGalleries(as: .downloadArchive)
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("元数据只包含画廊信息；下载归档包含本地图片。")
            }
            .alert("删除下载失败", isPresented: Binding(
                get: { removalErrorMessage != nil },
                set: { if $0 == false { removalErrorMessage = nil } }
            )) {
                Button("好", role: .cancel) { removalErrorMessage = nil }
            } message: {
                Text(removalErrorMessage ?? String(localized: "请稍后重试。"))
            }
#if os(iOS)
            .sheet(isPresented: $showingShareSheet, onDismiss: discardPendingSharedFileIfAny) {
                if let url = model.pendingSharedFileURL {
                    ShareSheet(items: [url])
                }
            }
#else
            .fileExporter(
                isPresented: $showingGallerySyncExporter,
                document: gallerySyncExportDocument,
                contentTypes: [.ehViewerGallerySync],
                defaultFilename: gallerySyncExportFilename
            ) { result in
                if let sourceURL = gallerySyncExportDocument?.sourceURL {
                    model.discardPendingSharedFile(sourceURL)
                }
                gallerySyncExportDocument = nil
                if case let .failure(error) = result {
                    model.errorMessage = error.localizedDescription
                }
            }
#endif
    }

    private func displayTitle(for job: DownloadJob?) -> String {
        job?.displayTitle(showJapaneseTitle: model.readingSettings.showJapaneseTitle) ?? ""
    }

    private var content: some View {
        @Bindable var model = model
        return Group {
            if pageJobs.isEmpty {
                if model.isLoadingDownloads {
                    ProgressView("正在加载下载内容…")
                } else {
                    ContentUnavailableView(
                        page.emptyTitle,
                        systemImage: page.systemImage,
                        description: Text(page.emptyDescription)
                    )
                }
            } else if visibleJobs.isEmpty {
                ContentUnavailableView("没有匹配的下载", systemImage: "line.3.horizontal.decrease.circle", description: Text("调整搜索或筛选条件"))
            } else {
                if model.downloadLayoutMode == .grid {
                    downloadsGrid
                } else {
                    downloadsList
                }
            }
        }
        .navigationTitle(page == .downloading ? "downloads_title" : "本地")
        .searchable(text: $searchText, prompt: "搜索下载标题或标签")
        .searchSuggestions {
            if isUpdatingTagSearchSuggestions {
                Section {
                    HStack {
                        ProgressView()
                        Text("正在读取标签候选…")
                    }
                    .foregroundStyle(.secondary)
                }
            } else if tagSearchSuggestions.isEmpty == false {
                Section("标签") {
                    ForEach(tagSearchSuggestions) { suggestion in
                        Button {
                            searchText = suggestion.english
                        } label: {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(suggestion.english)
                                    if let localizedText = suggestion.localizedText,
                                       localizedText.localizedCaseInsensitiveCompare(suggestion.english) != .orderedSame {
                                        Text(localizedText)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            } icon: {
                                Image(systemName: "tag")
                            }
                        }
                    }
                }
            }
        }
        .toolbar {
            if isSelectionMode {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { exitSelectionMode() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(selectAllTitle) {
                        toggleSelectAll()
                    }
                    if page == .local {
                        Button {
                            showingShareFormatDialog = true
                        } label: {
                            Label("分享(\(selectedKeys.count))", systemImage: "square.and.arrow.up")
                        }
                        .disabled(selectedKeys.isEmpty || model.isMigrating || model.isRestoringDownloads)
                        .accessibilityIdentifier("downloads-share-selected")
                    }
                    Button {
                        showingDeleteSelectedConfirmation = true
                    } label: {
                        Label("删除(\(selectedKeys.count))", systemImage: "trash")
                    }
                    .disabled(selectedKeys.isEmpty || bulkRemovalProgress != nil)
                }
            } else {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        enterSelectionMode()
                    } label: {
                        Image(systemName: "checkmark.circle")
                    }
                    .accessibilityLabel("选择")
                    .accessibilityHint("选择要操作的下载项")
                    .disabled(visibleJobs.isEmpty || bulkRemovalProgress != nil)
                    Button {
                        model.downloadLayoutMode = model.downloadLayoutMode == .list ? .grid : .list
                        model.persistDownloadPreferences()
                    } label: {
                        Label(
                            model.downloadLayoutMode == .list
                                ? String(localized: "切换到卡片")
                                : String(localized: "切换到列表"),
                            systemImage: model.downloadLayoutMode == .list
                                ? "square.grid.2x2"
                                : "list.bullet"
                        )
                    }
                    .accessibilityIdentifier("downloads-layout-toggle")
                    Menu("下载管理", systemImage: "ellipsis.circle") {
                        if page == .downloading {
                            Button("开始全部", systemImage: "play.fill") {
                                Task { await model.startAllDownloads() }
                            }
                            .disabled(canStartAll == false)
                            Button("暂停全部", systemImage: "pause.fill") {
                                Task { await model.downloads.stopAll() }
                            }
                            .disabled(canStopAll == false)
                            Divider()
                            Picker("筛选状态", selection: $model.downloadStatusFilter) {
                                ForEach(DownloadStatusFilter.allCases) { filter in
                                    Text(filter.title).tag(filter)
                                }
                            }
                            .onChange(of: model.downloadStatusFilter) { _, _ in
                                model.persistDownloadPreferences()
                            }
                        }
                        Picker(
                            "排序",
                            selection: Binding(
                                get: { effectiveSortOrder },
                                set: {
                                    model.downloadSortOrder = $0
                                    model.persistDownloadPreferences()
                                }
                            )
                        ) {
                            ForEach(availableSortOrders) { order in
                                Text(order.title).tag(order)
                            }
                        }
                        Divider()
                        Button("重置阅读进度", systemImage: "arrow.counterclockwise", role: .destructive) {
                            showingResetProgressConfirmation = true
                        }
                    }
                    .accessibilityIdentifier("download-management-menu")
                }
            }
        }
        .task(id: model.isLoadingDownloads) { jobs = await model.downloads.snapshot() }
        .task(id: localSummaryTaskID) {
            await loadLocalSummaries()
        }
        .task(id: searchText) {
            await refreshTagSearchSuggestions(for: searchText)
        }
        .task {
            for await event in await model.downloads.events() {
                apply(event)
            }
        }
        .sheet(item: $editingJob) { job in
            NavigationStack {
                Form {
                    TextField("下载标签", text: $labelInput)
                }
                .navigationTitle("下载标签")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { editingJob = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            Task {
                                await model.setDownloadLabel(labelInput, for: job.key)
                                editingJob = nil
                            }
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func refreshTagSearchSuggestions(for query: String) async {
        tagSearchSuggestions = []
        isUpdatingTagSearchSuggestions = false

        let normalizedQuery = SearchQueryComposer.normalized(query)
        let fragment = SearchQueryComposer.suggestionFragment(in: normalizedQuery)
        guard fragment.isEmpty == false else { return }

        isUpdatingTagSearchSuggestions = true
        defer {
            if Task.isCancelled == false {
                isUpdatingTagSearchSuggestions = false
            }
        }

        do {
            try await Task.sleep(for: .milliseconds(120))
            try Task.checkCancellation()
            let suggestions = await model.filterTagSuggestions(for: fragment, limit: 20)
            try Task.checkCancellation()
            guard SearchQueryComposer.normalized(searchText) == normalizedQuery else { return }
            tagSearchSuggestions = suggestions
        } catch is CancellationError {
            return
        } catch {
            tagSearchSuggestions = []
        }
    }

    private func apply(_ event: DownloadEvent) {
        switch event {
        case .reset(let restoredJobs):
            jobs = restoredJobs
        case .changed(let changedJob):
            if let index = jobs.firstIndex(where: { $0.key == changedJob.key }) {
                jobs[index] = changedJob
            } else {
                jobs.append(changedJob)
            }
        case .removed(let key):
            jobs.removeAll { $0.key == key }
        case .removedMany(let keys):
            let keySet = Set(keys)
            jobs.removeAll { keySet.contains($0.key) }
        }
    }

    private func enterSelectionMode(selecting key: GalleryKey? = nil) {
        isSelectionMode = true
        if let key {
            selectedKeys.insert(key)
        }
    }

    private func exitSelectionMode() {
        isSelectionMode = false
        selectedKeys.removeAll()
    }

    private func toggleSelection(_ key: GalleryKey) {
        if selectedKeys.contains(key) {
            selectedKeys.remove(key)
        } else {
            selectedKeys.insert(key)
        }
    }

    private func toggleSelectAll() {
        if selectedKeys.count == visibleJobs.count {
            selectedKeys.removeAll()
        } else {
            selectedKeys.formUnion(visibleJobs.map(\.key))
        }
    }

    private var selectAllTitle: String {
        selectedKeys.count == visibleJobs.count && visibleJobs.isEmpty == false
            ? String(localized: "取消全选")
            : String(localized: "全选")
    }

    private func deleteSelectedDownloads() {
        guard bulkRemovalProgress == nil else { return }
        let keys = selectedKeys.sorted { $0.id < $1.id }
        guard keys.isEmpty == false else { return }
        exitSelectionMode()
        bulkRemovalProgress = DownloadRemovalProgress(completed: 0, total: keys.count)
        bulkRemovalTask = Task { @MainActor in
            let result = await model.downloads.remove(keys) { progress in
                await MainActor.run {
                    bulkRemovalProgress = progress
                }
            }

            bulkRemovalProgress = nil
            if result.failures.isEmpty == false {
                let details = result.failures.prefix(5).map {
                    "\($0.key.gid)：\($0.message)"
                }.joined(separator: "\n")
                let suffix = result.failures.count > 5
                    ? String(localized: "\n另有 \(result.failures.count - 5) 项失败。")
                    : ""
                removalErrorMessage = details + suffix
            }
        }
    }

    private func bulkRemovalProgressView(_ progress: DownloadRemovalProgress) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("正在删除画廊")
                    Spacer()
                    Text("\(progress.completed)/\(progress.total)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress.fraction)
                    .progressViewStyle(.linear)
                if progress.failed > 0 {
                    Text("失败 \(progress.failed) 项，将在完成后提示")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Button("取消") {
                bulkRemovalTask?.cancel()
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("正在删除画廊，已完成 \(progress.completed)/\(progress.total)")
    }

    private func shareSelectedGalleries(as format: SelectedGalleryShareFormat) {
        let keys = selectedKeys
        Task {
            let url: URL?
            switch format {
            case .gallerySync:
                url = await model.exportGallerySync(keys: keys)
            case .downloadArchive:
                url = await model.exportDownloadArchive(keys: keys)
            }
            guard let url else { return }
            exitSelectionMode()
#if os(iOS)
            showingShareSheet = true
#else
            switch format {
            case .gallerySync:
                gallerySyncExportFilename = url.lastPathComponent
                gallerySyncExportDocument = GallerySyncExportDocument(sourceURL: url)
                showingGallerySyncExporter = true
            case .downloadArchive:
                await saveDownloadArchive(url)
            }
#endif
        }
    }

    private func discardPendingSharedFileIfAny() {
        if let url = model.pendingSharedFileURL {
            model.discardPendingSharedFile(url)
        }
    }

#if os(macOS)
    private func saveDownloadArchive(_ sourceURL: URL) async {
        defer { model.discardPendingSharedFile(sourceURL) }
        do {
            _ = try await DownloadArchiveSavePanel.save(sourceURL)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
#endif

    private var downloadsList: some View {
#if os(macOS)
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(visibleJobs) { job in
                    listCard(for: job)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
        }
        .background(.secondary.opacity(0.08))
#else
        List(visibleJobs) { job in
            listCard(for: job)
            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(.secondary.opacity(0.08))
#endif
    }

    @ViewBuilder
    private func listCard(for job: DownloadJob) -> some View {
        if page == .local {
            LocalDownloadCard(
                job: job,
                gallery: localGallerySummary(for: job),
                isSelectionMode: isSelectionMode,
                isSelected: selectedKeys.contains(job.key),
                select: { toggleSelection(job.key) },
                requestSelection: { enterSelectionMode(selecting: job.key) },
                openReader: { jobForReader = job },
                remove: {
                    guard bulkRemovalProgress == nil else { return }
                    jobPendingRemoval = job
                },
                label: {
                    labelInput = job.label ?? ""
                    editingJob = job
                }
            )
        } else {
            DownloadCard(
                job: job,
                isSelectionMode: isSelectionMode,
                isSelected: selectedKeys.contains(job.key),
                select: { toggleSelection(job.key) },
                requestSelection: { enterSelectionMode(selecting: job.key) },
                openReader: { jobForReader = job }
            ) {
                Task {
                    if job.state == .running || job.state == .queued { await model.downloads.pause(job.key) }
                    else { await model.resumeDownload(job.key) }
                }
                } redownload: {
                    guard bulkRemovalProgress == nil else { return }
                    jobPendingRedownload = job
                } remove: {
                    guard bulkRemovalProgress == nil else { return }
                    jobPendingRemoval = job
                } label: {
                labelInput = job.label ?? ""
                editingJob = job
            }
        }
    }

    private var localSummaryTaskID: String {
        guard page == .local else { return "not-local" }
        return jobs.map { "\($0.key.id)|\($0.title)|\($0.tags.joined(separator: "\u{1F}"))" }
            .joined(separator: "\u{1E}")
    }

    private func loadLocalSummaries() async {
        guard page == .local else {
            localSummariesByKey = [:]
            return
        }
        let keys = Set(jobs.map(\.key))
        guard keys.isEmpty == false else {
            localSummariesByKey = [:]
            return
        }
        let summaries = await model.localGallerySummaries(for: keys)
        guard Task.isCancelled == false else { return }
        localSummariesByKey = Dictionary(
            summaries.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func localGallerySummary(for job: DownloadJob) -> GallerySummary {
        var summary = localSummariesByKey[job.key] ?? GallerySummary(
            key: job.key,
            title: job.title,
            japaneseTitle: job.japaneseTitle,
            pageCount: job.pages.isEmpty ? nil : job.pages.count,
            tags: job.tags
        )
        if summary.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            summary.title = job.title
        }
        if summary.japaneseTitle == nil {
            summary.japaneseTitle = job.japaneseTitle
        }
        if summary.tags.isEmpty {
            summary.tags = job.tags
        }
        if summary.pageCount == nil, job.pages.isEmpty == false {
            summary.pageCount = job.pages.count
        }
        return summary
    }

    private var downloadsGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: gridColumns,
                spacing: gridSpacing
            ) {
                ForEach(visibleJobs) { job in
                    DownloadGridCard(
                        job: job,
                        isSelectionMode: isSelectionMode,
                        isSelected: selectedKeys.contains(job.key),
                        select: { toggleSelection(job.key) },
                        requestSelection: { enterSelectionMode(selecting: job.key) }
                    ) {
                        Task {
                            if job.state == .running || job.state == .queued { await model.downloads.pause(job.key) }
                            else { await model.resumeDownload(job.key) }
                        }
                    } redownload: {
                        jobPendingRedownload = job
                    } remove: {
                        jobPendingRemoval = job
                    } label: {
                        labelInput = job.label ?? ""
                        editingJob = job
                    }
                }
            }
            .padding(gridSpacing)
        }
        .background(.secondary.opacity(0.08))
    }

    /// iPadOS 与桌面端使用更大的卡片，紧凑设备保持适中尺寸。
    private var gridColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            return [GridItem(.adaptive(minimum: 140, maximum: 190), spacing: 16)]
        }
        return [GridItem(.adaptive(minimum: 104, maximum: 140), spacing: 12)]
    }

    private var gridSpacing: CGFloat {
        horizontalSizeClass == .regular ? 16 : 12
    }

    private var canStartAll: Bool {
        pageJobs.contains { [.paused, .failed, .authenticationRequired, .rateLimited, .bandwidthLimited].contains($0.state) }
    }

    private var canStopAll: Bool {
        pageJobs.contains { $0.state == .running || $0.state == .queued }
    }
}

enum DownloadsPage: String, CaseIterable, Identifiable, Hashable {
    case downloading
    case local

    var id: Self { self }

    var title: String {
        switch self {
        case .downloading: String(localized: "下载中")
        case .local: String(localized: "本地画廊")
        }
    }

    var emptyTitle: String {
        switch self {
        case .downloading: String(localized: "暂无下载任务")
        case .local: String(localized: "暂无本地画廊")
        }
    }

    var emptyDescription: String {
        switch self {
        case .downloading: String(localized: "从画廊详情页加入下载队列")
        case .local: String(localized: "完成下载的画廊会显示在这里")
        }
    }

    var systemImage: String {
        switch self {
        case .downloading: "arrow.down.circle"
        case .local: "books.vertical"
        }
    }

    func contains(_ job: DownloadJob) -> Bool {
        switch self {
        case .downloading: job.state != .completed
        case .local: job.state == .completed
        }
    }
}

enum DownloadStatusFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case paused
    case completed
    case failed

    var id: Self { self }

    var title: String {
        switch self {
        case .all: String(localized: "全部")
        case .active: String(localized: "进行中")
        case .paused: String(localized: "已暂停")
        case .completed: String(localized: "已完成")
        case .failed: String(localized: "异常")
        }
    }

    func matches(_ state: DownloadState) -> Bool {
        switch self {
        case .all: true
        case .active: state == .queued || state == .running
        case .paused: state == .paused
        case .completed: state == .completed
        case .failed:
            state == .failed || state == .authenticationRequired || state == .rateLimited || state == .bandwidthLimited
        }
    }
}

enum DownloadSortOrder: String, CaseIterable, Identifiable {
    case addedNewest
    case addedOldest
    case titleAscending
    case titleDescending
    case progress
    case status

    var id: Self { self }

    var title: String {
        switch self {
        case .addedNewest: String(localized: "添加时间（最新）")
        case .addedOldest: String(localized: "添加时间（最早）")
        case .titleAscending: String(localized: "标题 A-Z")
        case .titleDescending: String(localized: "标题 Z-A")
        case .progress: String(localized: "完成度")
        case .status: String(localized: "状态")
        }
    }

    func areInIncreasingOrder(_ lhs: DownloadJob, _ rhs: DownloadJob) -> Bool {
        switch self {
        case .addedNewest:
            if lhs.addedAt == rhs.addedAt { return titleAscending(lhs, rhs) }
            return lhs.addedAt > rhs.addedAt
        case .addedOldest:
            if lhs.addedAt == rhs.addedAt { return titleAscending(lhs, rhs) }
            return lhs.addedAt < rhs.addedAt
        case .titleAscending:
            return titleAscending(lhs, rhs)
        case .titleDescending:
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedDescending
        case .progress:
            if lhs.progress == rhs.progress { return titleAscending(lhs, rhs) }
            return lhs.progress > rhs.progress
        case .status:
            if lhs.state.rawValue == rhs.state.rawValue { return titleAscending(lhs, rhs) }
            return lhs.state.rawValue < rhs.state.rawValue
        }
    }

    private func titleAscending(_ lhs: DownloadJob, _ rhs: DownloadJob) -> Bool {
        lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}

enum DownloadsLayoutMode: String, CaseIterable, Identifiable {
    case list
    case grid

    var id: Self { self }

    var title: String {
        switch self {
        case .list: String(localized: "列表")
        case .grid: String(localized: "卡片")
        }
    }

    var systemImage: String {
        switch self {
        case .list: "list.bullet"
        case .grid: "square.grid.2x2"
        }
    }
}

private struct LocalDownloadCard: View {
    @Environment(AppModel.self) private var model
    let job: DownloadJob
    let gallery: GallerySummary
    let isSelectionMode: Bool
    let isSelected: Bool
    let select: () -> Void
    let requestSelection: () -> Void
    let openReader: () -> Void
    let remove: () -> Void
    let label: () -> Void

    var body: some View {
        Group {
            if isSelectionMode {
                Button(action: select) {
                    HStack(alignment: .top, spacing: 10) {
                        selectionIndicator
                        galleryCard
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSelected ? String(localized: "取消选择《\(displayTitle)》") : String(localized: "选择《\(displayTitle)》"))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            } else {
#if os(macOS)
                HStack(alignment: .top, spacing: 8) {
                    Button(action: openReader) {
                        galleryCard
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .buttonStyle(.plain)
                    .accessibilityLabel("打开《\(displayTitle)》")
                    .accessibilityHint("使用阅读器打开，优先读取已下载页面")

                    VStack(spacing: 6) {
                        NavigationLink(value: AppRoute.gallery(job.key)) {
                            Label("查看详情", systemImage: "info.circle")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .frame(width: 32, height: 32)
                        .help("查看详情")

                        Button("删除下载", systemImage: "trash", role: .destructive, action: remove)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .frame(width: 32, height: 32)
                            .help("删除下载")
                    }
                    .accessibilityElement(children: .contain)
                }
#else
                ZStack(alignment: .topTrailing) {
                    Button(action: openReader) {
                        galleryCard
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .buttonStyle(.plain)
                    .accessibilityLabel("打开《\(displayTitle)》")
                    .accessibilityHint("使用阅读器打开，优先读取已下载页面")

                    Menu("本地画廊操作", systemImage: "ellipsis.circle") {
                        NavigationLink(value: AppRoute.gallery(job.key)) {
                            Label("查看详情", systemImage: "info.circle")
                        }
                        Button("设置标签", systemImage: "tag", action: label)
                        Button("删除下载", systemImage: "trash", role: .destructive, action: remove)
                    }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44, alignment: .topTrailing)
                    .padding(.top, 2)
                    .padding(.trailing, 2)
                    .accessibilityLabel("《\(displayTitle)》本地画廊操作")
                }
#endif
            }
        }
        .contextMenu {
#if os(macOS)
            if isSelectionMode == false {
                Button("选择", systemImage: "checkmark.circle", action: requestSelection)
            }
            Button("设置标签", systemImage: "tag", action: label)
            Button("删除下载", systemImage: "trash", role: .destructive, action: remove)
#else
            if isSelectionMode == false {
                Button("选择", systemImage: "checkmark.circle", action: requestSelection)
            }
#endif
        }
    }

    private var galleryCard: some View {
        GalleryCard(gallery: gallery, showsTags: true, localJob: job)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectionIndicator: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(minWidth: 28, minHeight: 44, alignment: .top)
            .accessibilityLabel(isSelected ? String(localized: "已选择") : String(localized: "未选择"))
    }

    private var displayTitle: String {
        job.displayTitle(showJapaneseTitle: model.readingSettings.showJapaneseTitle)
    }
}

private struct DownloadCard: View {
    @Environment(AppModel.self) private var model
    let job: DownloadJob
    let isSelectionMode: Bool
    let isSelected: Bool
    let select: () -> Void
    let requestSelection: () -> Void
    let openReader: () -> Void
    let toggle: () -> Void
    let redownload: () -> Void
    let remove: () -> Void
    let label: () -> Void

    var body: some View {
        Group {
            if isSelectionMode {
                Button(action: select) {
                    HStack(alignment: .top, spacing: 10) {
                        selectionIndicator
                        cardContent
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
#if os(macOS)
                .foregroundStyle(.primary)
#endif
                .accessibilityLabel(isSelected ? String(localized: "取消选择《\(displayTitle)》") : String(localized: "选择《\(displayTitle)》"))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            } else {
#if os(macOS)
                HStack(alignment: .top, spacing: 8) {
                    Button(action: openReader) {
                        cardContent
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .buttonStyle(.plain)
                    .accessibilityLabel("打开《\(displayTitle)》")
                    .accessibilityHint("使用阅读器打开，优先读取已下载页面")

                    VStack(spacing: 6) {
                        NavigationLink(value: AppRoute.gallery(job.key)) {
                            Label("查看详情", systemImage: "info.circle")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .frame(width: 32, height: 32)
                        .help("查看详情")

                        Button("删除下载", systemImage: "trash", role: .destructive, action: remove)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .frame(width: 32, height: 32)
                            .help("删除下载")
                    }
                    .accessibilityElement(children: .contain)
                }
#else
                HStack(alignment: .top, spacing: 8) {
                    Button(action: openReader) {
                        cardContent
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .buttonStyle(.plain)
                    .accessibilityLabel("打开《\(displayTitle)》")
                    .accessibilityHint("使用阅读器打开，优先读取已下载页面")

                    Menu("下载操作", systemImage: "ellipsis.circle") {
                        NavigationLink(value: AppRoute.gallery(job.key)) {
                            Label("查看详情", systemImage: "info.circle")
                        }
                        if canToggle {
                            Button(job.state == .running || job.state == .queued ? String(localized: "暂停") : String(localized: "继续"), systemImage: job.state == .running ? "pause" : "play", action: toggle)
                        }
                        if job.state != .completed {
                            Button("重新下载", systemImage: "arrow.clockwise", action: redownload)
                        }
                        Button("设置标签", systemImage: "tag", action: label)
                        Button("删除下载", systemImage: "trash", role: .destructive, action: remove)
                    }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44, alignment: .topTrailing)
                    .accessibilityLabel("《\(displayTitle)》下载操作")
                }
#endif
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .contextMenu {
#if os(macOS)
            if isSelectionMode == false {
                Button("选择", systemImage: "checkmark.circle", action: requestSelection)
            }
            if canToggle {
                Button(
                    job.state == .running || job.state == .queued ? String(localized: "暂停") : String(localized: "继续"),
                    systemImage: job.state == .running ? "pause" : "play",
                    action: toggle
                )
            }
            if job.state != .completed {
                Button("重新下载", systemImage: "arrow.clockwise", action: redownload)
            }
            Button("设置标签", systemImage: "tag", action: label)
#else
            if isSelectionMode == false {
                Button("选择", systemImage: "checkmark.circle", action: requestSelection)
            }
#endif
        }
    }

    private var cardContent: some View {
        HStack(alignment: .top, spacing: 12) {
            DownloadCover(
                job: job,
                title: displayTitle,
                size: CGSize(width: 88, height: 120),
                cornerRadius: 12
            )
            VStack(alignment: .leading, spacing: 7) {
                Text(displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let authorText {
                    Label(authorText, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if job.tags.isEmpty == false {
                    TagFlowLayout(horizontalSpacing: 5, verticalSpacing: 4) {
                        ForEach(Array(job.tags.enumerated()), id: \.offset) { item in
                            Text(model.displayTag(item.element))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(.horizontal, 7)
                                .frame(height: 22)
                                .frame(maxWidth: 160, alignment: .leading)
                                .background(Color.secondary.opacity(0.14), in: Capsule())
                                .accessibilityLabel("标签 \(model.displayTag(item.element))")
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: 48, alignment: .topLeading)
                    .clipped()
                }
                if job.state != .completed {
                    ProgressView(value: job.progress)
                }
                if job.state == .completed {
                    Label(statusTitle, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text(statusTitle)
                        Spacer()
                        Text("\(job.completedPageIndexes.count)/\(job.pages.count) 页")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if let errorMessage = job.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var selectionIndicator: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title2)
#if os(macOS)
            .foregroundStyle(isSelected ? AppTheme.accent : Color.secondary)
#else
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
#endif
            .frame(minWidth: 28, minHeight: 44, alignment: .top)
            .accessibilityLabel(isSelected ? String(localized: "已选择") : String(localized: "未选择"))
    }

    private var displayTitle: String {
        job.displayTitle(showJapaneseTitle: model.readingSettings.showJapaneseTitle)
    }

    private var authorText: String? {
        let tags = GallerySummary.preferredAuthorTags(from: job.tags)
        guard tags.isEmpty == false else { return nil }
        return tags.map(model.displayTag).joined(separator: ", ")
    }

    private var statusTitle: String {
        switch job.state {
        case .queued: String(localized: "等待中")
        case .running: String(localized: "下载中")
        case .paused: String(localized: "已暂停")
        case .completed: String(localized: "已完成")
        case .failed: String(localized: "失败")
        case .authenticationRequired: String(localized: "需要登录")
        case .rateLimited: String(localized: "请求受限")
        case .bandwidthLimited: String(localized: "流量受限")
        case .cancelled: String(localized: "已取消")
        }
    }

    private var canToggle: Bool {
        job.state != .completed && job.state != .cancelled
    }
}

private struct DownloadGridCard: View {
    @Environment(AppModel.self) private var model
    let job: DownloadJob
    let isSelectionMode: Bool
    let isSelected: Bool
    let select: () -> Void
    let requestSelection: () -> Void
    let toggle: () -> Void
    let redownload: () -> Void
    let remove: () -> Void
    let label: () -> Void

    var body: some View {
        Group {
            if isSelectionMode {
                Button(action: select) {
                    coverContent
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSelected ? String(localized: "取消选择《\(displayTitle)》") : String(localized: "选择《\(displayTitle)》"))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            } else {
                NavigationLink {
                    ReaderView(downloaded: job, initialPage: 0)
                } label: {
                    coverContent
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("选择", systemImage: "checkmark.circle", action: requestSelection)
                    NavigationLink(value: AppRoute.gallery(job.key)) {
                        Label("查看详情", systemImage: "info.circle")
                    }
                    if canToggle {
                        Button(job.state == .running || job.state == .queued ? String(localized: "暂停") : String(localized: "继续"), systemImage: job.state == .running ? "pause" : "play", action: toggle)
                    }
                    if job.state != .completed {
                        Button("重新下载", systemImage: "arrow.clockwise", action: redownload)
                    }
                    Button("设置标签", systemImage: "tag", action: label)
                    Button("删除下载", systemImage: "trash", role: .destructive, action: remove)
                }
                .accessibilityLabel("打开《\(displayTitle)》")
                .accessibilityHint("使用阅读器打开，优先读取已下载页面")
            }
        }
    }

    private var coverContent: some View {
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                DownloadCover(job: job, title: displayTitle, size: nil, cornerRadius: 14)
            }
            .overlay(alignment: .bottom) {
                if showsProgress {
                    VStack(spacing: 3) {
                        ProgressView(value: job.progress)
                            .progressViewStyle(.linear)
                            .tint(.white)
                        Text("\(Int((job.progress * 100).rounded()))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(.black.opacity(0.45))
                }
            }
            .overlay(alignment: .topLeading) {
                if isSelectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                        .padding(8)
                        .background(.black.opacity(0.45), in: Circle())
                        .padding(8)
                        .accessibilityLabel(isSelected ? String(localized: "已选择") : String(localized: "未选择"))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
    }

    private var displayTitle: String {
        job.displayTitle(showJapaneseTitle: model.readingSettings.showJapaneseTitle)
    }

    private var showsProgress: Bool {
        job.state != .completed && job.state != .cancelled
    }

    private var canToggle: Bool {
        job.state != .completed && job.state != .cancelled
    }
}

struct DownloadCover: View {
    @Environment(AppModel.self) private var model
    let job: DownloadJob
    let title: String
    var fallbackPreviewURL: URL?
    var size: CGSize? = CGSize(width: 72, height: 96)
    var cornerRadius: CGFloat = 10
    @State private var image: Image?

    /// 解码后的封面缓存：滚动来回时直接命中，避免重复解码。
    @MainActor
    private static let imageCache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 400
        cache.totalCostLimit = 80_000_000
        return cache
    }()

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size?.width, height: size?.height)
        .frame(maxWidth: size == nil ? .infinity : nil, maxHeight: size == nil ? .infinity : nil)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: cornerRadius))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .accessibilityLabel("《\(title)》封面")
        .task(id: coverTaskID, priority: .utility) {
            image = nil
            if let cached = Self.cachedCoverImage(for: coverTaskID) {
                image = cached
                return
            }
            if let coverPageIndex {
                do {
                    let data = try await model.downloadFiles.data(for: job.key, pageIndex: coverPageIndex)
                    if let decoded = await Self.decodeCoverImage(data, key: coverTaskID, maxPixelSize: 320) {
                        withAnimation(.easeOut(duration: 0.25)) { image = decoded }
                        return
                    }
                } catch is CancellationError {
                    return
                } catch {
                    // Fall through to the remote preview while the download is incomplete.
                }
            }

            guard let previewURL else { return }
            do {
                let preview = GalleryPageImage(galleryKey: job.key, index: 0, imageURL: previewURL)
                let data = try await model.imageData(for: preview)
                if let decoded = await Self.decodeCoverImage(data, key: coverTaskID, maxPixelSize: 320) {
                    withAnimation(.easeOut(duration: 0.25)) { image = decoded }
                }
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    @MainActor
    private static func cachedCoverImage(for key: String) -> Image? {
        guard let cgImage = imageCache.object(forKey: key as NSString) else { return nil }
        return Image(decorative: cgImage, scale: 1, orientation: .up)
    }

    /// 在后台解码并写入缓存；返回可在主线程直接使用的 `Image`。
    @MainActor
    private static func decodeCoverImage(_ data: Data, key: String, maxPixelSize: Int) async -> Image? {
        guard let cgImage = await decodeImage(from: data, maxPixelSize: maxPixelSize) else { return nil }
        imageCache.setObject(cgImage, forKey: key as NSString, cost: cgImage.width * cgImage.height)
        return Image(decorative: cgImage, scale: 1, orientation: .up)
    }

    /// 封面解码放到后台执行（utility 优先级），主线程只做轻量包装，
    /// 大量封面时也不会阻塞滚动。
    private static func decodeImage(from data: Data, maxPixelSize: Int) async -> CGImage? {
        let decoding = Task.detached(priority: .utility) { () -> CGImage? in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
                  ] as CFDictionary) else { return nil }
            return cgImage
        }
        return await withTaskCancellationHandler {
            await decoding.value
        } onCancel: {
            decoding.cancel()
        }
    }

    private var coverPageIndex: Int? {
        job.pages.first(where: { job.completedPageIndexes.contains($0.index) })?.index
    }

    private var previewURL: URL? {
        job.pages.lazy.compactMap(\.previewURL).first ?? fallbackPreviewURL
    }

    private var coverTaskID: String {
        "\(job.key.id)|\(coverPageIndex.map(String.init) ?? "remote")|\(previewURL?.absoluteString ?? "none")"
    }
}
