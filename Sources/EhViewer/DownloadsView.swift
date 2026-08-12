import SwiftUI
import UniformTypeIdentifiers
import EHDomain
import EHDownloads

struct DownloadsView: View {
    @Environment(AppModel.self) private var model
    @State private var jobs: [DownloadJob] = []
    @State private var editingJob: DownloadJob?
    @State private var labelInput = ""
    @State private var showingArchiveImporter = false
    @State private var archiveDocument: LocalArchiveDocument?

    var body: some View {
        Group {
            if jobs.isEmpty {
                ContentUnavailableView("暂无下载", systemImage: "arrow.down.circle", description: Text("从画廊详情页加入下载队列"))
            } else {
                List(jobs) { job in
                    DownloadRow(job: job) {
                        Task {
                            if job.state == .running || job.state == .queued { await model.downloads.pause(job.key) }
                            else { await model.downloads.resume(job.key) }
                            jobs = await model.downloads.snapshot()
                        }
                    } cancel: {
                        Task {
                            await model.downloads.cancel(job.key)
                            jobs = await model.downloads.snapshot()
                        }
                    } label: {
                        labelInput = job.label ?? ""
                        editingJob = job
                    }
                }
            }
        }
        .navigationTitle("downloads_title")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("打开本地归档", systemImage: "archivebox") {
                    showingArchiveImporter = true
                }
                .accessibilityIdentifier("open-local-archive")
            }
        }
        .fileImporter(
            isPresented: $showingArchiveImporter,
            allowedContentTypes: LocalArchiveView.supportedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else {
                if case let .failure(error) = result { model.errorMessage = error.localizedDescription }
                return
            }
            Task {
                archiveDocument = await model.openLocalArchive(from: url)
            }
        }
        .sheet(item: $archiveDocument) { document in
            NavigationStack {
                LocalArchiveView(document: document)
                    .environment(model)
            }
        }
        .task { jobs = await model.downloads.snapshot() }
        .task {
            for await _ in await model.downloads.events() {
                jobs = await model.downloads.snapshot()
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
                                jobs = await model.downloads.snapshot()
                                editingJob = nil
                            }
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

private struct DownloadRow: View {
    let job: DownloadJob
    let toggle: () -> Void
    let cancel: () -> Void
    let label: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(job.title).font(.headline).lineLimit(2)
                Spacer()
                Menu("下载操作", systemImage: "ellipsis.circle") {
                    Button(job.state == .running || job.state == .queued ? "暂停" : "继续", systemImage: job.state == .running ? "pause" : "play", action: toggle)
                    Button("取消", systemImage: "xmark.circle", role: .destructive, action: cancel)
                    Button("设置标签", systemImage: "tag", action: label)
                }
            }
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
            if let errorMessage = job.errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
        }
        .padding(.vertical, 4)
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
}
