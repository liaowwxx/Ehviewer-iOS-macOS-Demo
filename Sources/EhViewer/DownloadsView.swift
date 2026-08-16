import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import EHDomain
import EHDownloads

struct DownloadsView: View {
    @Environment(AppModel.self) private var model
    @State private var jobs: [DownloadJob] = []
    @State private var editingJob: DownloadJob?
    @State private var labelInput = ""
    @State private var showingDownloadRestoreImporter = false
    @State private var searchText = ""
    @State private var showingResetProgressConfirmation = false
    @State private var jobPendingRemoval: DownloadJob?
    @State private var removalErrorMessage: String?
    @State private var showingDownloadRestoreResult = false
    @State private var downloadRestoreMessage = ""

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
                List(visibleJobs) { job in
                    DownloadCard(job: job) {
                        Task {
                            if job.state == .running || job.state == .queued { await model.downloads.pause(job.key) }
                            else { await model.downloads.resume(job.key) }
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
        }
        .navigationTitle("downloads_title")
        .searchable(text: $searchText, prompt: "搜索下载标题或标签")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("下载管理", systemImage: "ellipsis.circle") {
                    Button("开始全部", systemImage: "play.fill") {
                        Task { await model.downloads.startAll() }
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
                    Button("恢复下载项", systemImage: "arrow.counterclockwise.circle") {
                        showingDownloadRestoreImporter = true
                    }
                    .disabled(model.isRestoringDownloads)
                    Divider()
                    Button("重置阅读进度", systemImage: "arrow.counterclockwise", role: .destructive) {
                        showingResetProgressConfirmation = true
                    }
                }
                .accessibilityIdentifier("download-management-menu")
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
            Text(removalErrorMessage ?? "请稍后重试。")
        }
        .fileImporter(
            isPresented: $showingDownloadRestoreImporter,
            allowedContentTypes: LocalArchiveView.supportedContentTypes,
            allowsMultipleSelection: false,
            onCompletion: handleDownloadRestoreSelection
        )
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
        .alert("恢复下载项", isPresented: $showingDownloadRestoreResult) {
        } message: {
            Text(downloadRestoreMessage)
        }
        .overlay {
            if model.isRestoringDownloads {
                ProgressView(model.downloadRestoreStatus)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel(model.downloadRestoreStatus)
            }
        }
    }

    private func handleDownloadRestoreSelection(_ result: Result<[URL], any Error>) {
        guard case let .success(urls) = result, let url = urls.first else {
            if case let .failure(error) = result {
                downloadRestoreMessage = error.localizedDescription
                showingDownloadRestoreResult = true
            }
            return
        }
        Task {
            downloadRestoreMessage = await model.restoreDownloads(from: url)
            showingDownloadRestoreResult = true
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
        case .all: "全部"
        case .active: "进行中"
        case .paused: "已暂停"
        case .completed: "已完成"
        case .failed: "异常"
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
        case .addedNewest: "添加时间（最新）"
        case .addedOldest: "添加时间（最早）"
        case .titleAscending: "标题 A-Z"
        case .titleDescending: "标题 Z-A"
        case .progress: "完成度"
        case .status: "状态"
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

private struct DownloadCard: View {
    @Environment(AppModel.self) private var model
    let job: DownloadJob
    let toggle: () -> Void
    let cancel: () -> Void
    let remove: () -> Void
    let label: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            NavigationLink {
                ReaderView(downloaded: job, initialPage: 0)
            } label: {
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
            .buttonStyle(.plain)
            .accessibilityLabel("打开《\(displayTitle)》")
            .accessibilityHint("使用阅读器打开，优先读取已下载页面")

            Menu("下载操作", systemImage: "ellipsis.circle") {
                NavigationLink(value: AppRoute.gallery(job.key)) {
                    Label("查看详情", systemImage: "info.circle")
                }
                if canToggle {
                    Button(job.state == .running || job.state == .queued ? "暂停" : "继续", systemImage: job.state == .running ? "pause" : "play", action: toggle)
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
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var displayTitle: String {
        job.displayTitle(showJapaneseTitle: model.readingSettings.showJapaneseTitle)
    }

    private var statusTitle: String {
        switch job.state {
        case .queued: "等待中"
        case .running: "下载中"
        case .paused: "已暂停"
        case .completed: "已完成"
        case .failed: "失败"
        case .authenticationRequired: "需要登录"
        case .rateLimited: "请求受限"
        case .bandwidthLimited: "流量受限"
        case .cancelled: "已取消"
        }
    }

    private var canToggle: Bool {
        job.state != .completed && job.state != .cancelled
    }
}

private struct DownloadCover: View {
    @Environment(AppModel.self) private var model
    let job: DownloadJob
    let title: String
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 72, height: 96)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel("《\(title)》封面")
        .task(id: coverTaskID) {
            image = nil
            if let coverPageIndex {
                do {
                    let data = try await model.downloadFiles.data(for: job.key, pageIndex: coverPageIndex)
                    if let decoded = decodedImage(from: data, maxPixelSize: 320) {
                        image = decoded
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
                image = decodedImage(from: data, maxPixelSize: 320)
            } catch is CancellationError {
                return
            } catch {
                return
            }
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

private func decodedImage(from data: Data, maxPixelSize: Int) -> Image? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceCreateThumbnailWithTransform: true,
              kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
          ] as CFDictionary) else { return nil }
    return Image(decorative: cgImage, scale: 1, orientation: .up)
}
