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
import UniformTypeIdentifiers
import EHDomain
import EHDownloads

struct DownloadsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var jobs: [DownloadJob] = []
    @State private var editingJob: DownloadJob?
    @State private var labelInput = ""
    @State private var searchText = ""
    @State private var showingResetProgressConfirmation = false
    @State private var jobPendingRemoval: DownloadJob?
    @State private var removalErrorMessage: String?
    @State private var isSelectionMode = false
    @State private var selectedKeys: Set<GalleryKey> = []
    @State private var showingDownloadShareSheet = false
    @State private var showingDownloadExporter = false
    @State private var downloadExportDocument: ArchiveExportDocument?
    @State private var downloadExportFilename = ""
    @State private var downloadExportError: String?

    private var visibleJobs: [DownloadJob] {
        jobs
            .filter { model.downloadStatusFilter.matches($0.state) }
            .filter {
                searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || $0.containsTitle(searchText)
                    || ($0.label?.localizedCaseInsensitiveContains(searchText) == true)
            }
            .sorted(by: model.downloadSortOrder.areInIncreasingOrder)
    }

    var body: some View {
        @Bindable var model = model
        Group {
            if jobs.isEmpty {
                if model.isLoadingDownloads {
                    ProgressView("正在加载下载内容…")
                } else {
                    ContentUnavailableView("暂无下载", systemImage: "arrow.down.circle", description: Text("从画廊详情页加入下载队列"))
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
        .navigationTitle("downloads_title")
        .searchable(text: $searchText, prompt: "搜索下载标题或标签")
        .toolbar {
            if isSelectionMode {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { exitSelectionMode() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(selectedKeys.count == visibleJobs.count && visibleJobs.isEmpty == false ? String(localized: "取消全选") : String(localized: "全选")) {
                        toggleSelectAll()
                    }
#if os(iOS)
                    Button {
                        Task { await shareSelectedDownloads() }
                    } label: {
                        Label(String(localized: "分享(\(selectedKeys.count))"), systemImage: "square.and.arrow.up")
                    }
                    .disabled(selectedKeys.isEmpty || model.isMigrating)
#endif
                    Button {
                        Task { await saveSelectedDownloadsToFiles() }
                    } label: {
                        Label("保存到文件", systemImage: "folder")
                    }
                    .disabled(selectedKeys.isEmpty || model.isMigrating)
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
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
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("选择") {
                        enterSelectionMode()
                    }
                    .disabled(visibleJobs.isEmpty)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu("下载管理", systemImage: "ellipsis.circle") {
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
                        Picker("排序", selection: $model.downloadSortOrder) {
                            ForEach(DownloadSortOrder.allCases) { order in
                                Text(order.title).tag(order)
                            }
                        }
                        .onChange(of: model.downloadSortOrder) { _, _ in
                            model.persistDownloadPreferences()
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
        .confirmationDialog("重置所有下载内容的阅读进度？", isPresented: $showingResetProgressConfirmation, titleVisibility: .visible) {
            Button("重置进度", role: .destructive) {
                Task { await model.resetAllDownloadReadingProgress() }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog(
            "删除《\(jobPendingRemoval?.title ?? "")》？",
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
            Button("取消", role: .cancel) { jobPendingRemoval = nil }
        } message: {
            Text("将移除 \(jobPendingRemoval?.completedPageIndexes.count ?? 0) 个已下载页面，并从下载列表中移除。")
        }
        .alert("删除下载失败", isPresented: Binding(
            get: { removalErrorMessage != nil },
            set: { if $0 == false { removalErrorMessage = nil } }
        )) {
            Button("好", role: .cancel) { removalErrorMessage = nil }
        } message: {
            Text(removalErrorMessage ?? String(localized: "请稍后重试。"))
        }
        .task(id: model.isLoadingDownloads) { jobs = await model.downloads.snapshot() }
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
        .sheet(isPresented: $showingDownloadShareSheet) {
#if os(iOS)
            if let url = model.pendingSharedFileURL {
                ShareSheet(items: [url])
            }
#endif
        }
        .fileExporter(
            isPresented: $showingDownloadExporter,
            document: downloadExportDocument,
            contentTypes: [.ehViewerDownloadArchive],
            defaultFilename: downloadExportFilename
        ) { result in
            if let sourceURL = downloadExportDocument?.sourceURL {
                model.discardPendingSharedFile(sourceURL)
            }
            downloadExportDocument = nil
            if case let .failure(error) = result {
                downloadExportError = error.localizedDescription
            }
        }
        .alert("下载包导出失败", isPresented: Binding(
            get: { downloadExportError != nil },
            set: { if $0 == false { downloadExportError = nil } }
        )) {
            Button("好", role: .cancel) { downloadExportError = nil }
        } message: {
            Text(downloadExportError ?? String(localized: "请稍后重试。"))
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

    private func shareSelectedDownloads() async {
        guard await prepareSelectedDownloadsForExport() else { return }
        showingDownloadShareSheet = true
    }

    private func saveSelectedDownloadsToFiles() async {
        guard await prepareSelectedDownloadsForExport() else { return }
        showingDownloadExporter = true
    }

    private func prepareSelectedDownloadsForExport() async -> Bool {
        guard selectedKeys.isEmpty == false else {
            downloadExportError = String(localized: "请先选择要分享的下载项。")
            return false
        }
        guard let url = await model.exportDownloadArchive(keys: selectedKeys) else {
            downloadExportError = model.errorMessage ?? String(localized: "下载包导出失败，请稍后重试。")
            return false
        }
        downloadExportFilename = url.lastPathComponent
        downloadExportDocument = ArchiveExportDocument(sourceURL: url)
        return true
    }

    private var downloadsList: some View {
        List(visibleJobs) { job in
            DownloadCard(
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
            } cancel: {
                Task { await model.downloads.cancel(job.key) }
            } remove: {
                jobPendingRemoval = job
            } label: {
                labelInput = job.label ?? ""
                editingJob = job
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(.secondary.opacity(0.08))
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
                    } cancel: {
                        Task { await model.downloads.cancel(job.key) }
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
        jobs.contains { [.paused, .failed, .authenticationRequired, .rateLimited, .bandwidthLimited].contains($0.state) }
    }

    private var canStopAll: Bool {
        jobs.contains { $0.state == .running || $0.state == .queued }
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

private struct DownloadCard: View {
    @Environment(AppModel.self) private var model
    let job: DownloadJob
    let isSelectionMode: Bool
    let isSelected: Bool
    let select: () -> Void
    let requestSelection: () -> Void
    let toggle: () -> Void
    let cancel: () -> Void
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
                .accessibilityLabel(isSelected ? String(localized: "取消选择《\(displayTitle)》") : String(localized: "选择《\(displayTitle)》"))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            } else {
                HStack(alignment: .top, spacing: 8) {
                    NavigationLink {
                        ReaderView(downloaded: job, initialPage: 0)
                    } label: {
                        cardContent
                    }
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
                        if job.state != .completed && job.state != .cancelled {
                            Button("取消下载", systemImage: "xmark.circle", role: .destructive, action: cancel)
                        }
                        Button("设置标签", systemImage: "tag", action: label)
                        Button("删除下载", systemImage: "trash", role: .destructive, action: remove)
                    }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44, alignment: .topTrailing)
                    .accessibilityLabel("《\(displayTitle)》下载操作")
                }
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .contextMenu {
            if isSelectionMode == false {
                Button("选择", systemImage: "checkmark.circle", action: requestSelection)
            }
        }
    }

    private var cardContent: some View {
        HStack(alignment: .top, spacing: 12) {
            DownloadCover(job: job, title: displayTitle)
            VStack(alignment: .leading, spacing: 8) {
                Text(displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                if let label = job.label, label.isEmpty == false {
                    Label(label, systemImage: "tag")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: job.progress)
                HStack {
                    Text(statusTitle)
                    Spacer()
                    Text("\(job.completedPageIndexes.count)/\(job.pages.count) 页")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
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
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(minWidth: 28, minHeight: 44, alignment: .top)
            .accessibilityLabel(isSelected ? String(localized: "已选择") : String(localized: "未选择"))
    }

    private var displayTitle: String {
        job.displayTitle(showJapaneseTitle: model.readingSettings.showJapaneseTitle)
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
    let cancel: () -> Void
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
                    if job.state != .completed && job.state != .cancelled {
                        Button("取消下载", systemImage: "xmark.circle", role: .destructive, action: cancel)
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

private struct DownloadCover: View {
    @Environment(AppModel.self) private var model
    let job: DownloadJob
    let title: String
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
        job.pages.lazy.compactMap(\.previewURL).first
    }

    private var coverTaskID: String {
        "\(job.key.id)|\(coverPageIndex.map(String.init) ?? "remote")|\(previewURL?.absoluteString ?? "none")"
    }
}
