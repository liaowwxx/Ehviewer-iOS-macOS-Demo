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
    @State private var showingArchiveImporter = false
    @State private var archiveDocument: LocalArchiveDocument?
    @State private var selectedDownloadedJob: DownloadJob?

    var body: some View {
        Group {
            if jobs.isEmpty {
                ContentUnavailableView("暂无下载", systemImage: "arrow.down.circle", description: Text("从画廊详情页加入下载队列"))
            } else {
                List(jobs) { job in
                    DownloadRow(job: job, open: job.state == .completed ? {
                        selectedDownloadedJob = job
                    } : nil) {
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
                    } remove: {
                        Task {
                            await model.downloads.remove(job.key)
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
        .sheet(item: $selectedDownloadedJob) { job in
            NavigationStack {
                DownloadedGalleryView(job: job)
                    .environment(model)
            }
        }
    }
}

private struct DownloadRow: View {
    let job: DownloadJob
    let open: (() -> Void)?
    let toggle: () -> Void
    let cancel: () -> Void
    let remove: () -> Void
    let label: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DownloadCover(job: job)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(job.title).font(.headline).lineLimit(2)
                    Spacer(minLength: 8)
                    Menu("下载操作", systemImage: "ellipsis.circle") {
                        if let open {
                            Button("打开下载", systemImage: "book") { open() }
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
                if let open {
                    Button(action: open) {
                        Label("打开下载", systemImage: "book")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let errorMessage = job.errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
            }
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

    private var canToggle: Bool {
        job.state != .completed && job.state != .cancelled
    }
}

private struct DownloadCover: View {
    @Environment(AppModel.self) private var model
    let job: DownloadJob
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
        .accessibilityLabel("《\(job.title)》封面")
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

private struct DownloadedGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    let job: DownloadJob

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(job.pages) { page in
                    DownloadedPageView(job: job, page: page)
                }
            }
            .padding()
        }
        .navigationTitle("已下载 · \(job.title)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("完成", action: dismiss.callAsFunction)
            }
        }
    }
}

private struct DownloadedPageView: View {
    @Environment(AppModel.self) private var model
    let job: DownloadJob
    let page: GalleryPageDescriptor
    @State private var image: Image?
    @State private var isMissing = false

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
            } else if isMissing {
                Label("第 \(page.index + 1) 页文件不可用", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ProgressView("读取第 \(page.index + 1) 页…")
                    .frame(maxWidth: .infinity, minHeight: 180)
            }
        }
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: page.id) {
            image = nil
            isMissing = false
            do {
                let data = try await model.downloadFiles.data(for: job.key, pageIndex: page.index)
                guard let decoded = decodedImage(from: data, maxPixelSize: 2_800) else {
                    isMissing = true
                    return
                }
                image = decoded
            } catch is CancellationError {
                return
            } catch {
                isMissing = true
            }
        }
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
