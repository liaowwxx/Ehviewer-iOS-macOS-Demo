import SwiftUI
import ImageIO
import EHDomain

struct GalleryDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    let key: GalleryKey
    @State private var detail: GalleryDetail?
    @State private var isFavorite = false
    @State private var commentText = ""
    @State private var comments: [GalleryComment] = []
    @State private var torrents: [TorrentDescriptor] = []
    @State private var archiveOptions: [ArchiveOption] = []

    var body: some View {
        Group {
            if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        GalleryDetailHero(summary: detail.summary)
                        Text(detail.summary.title).font(.title.bold())
                        if let subtitle = detail.summary.secondaryTitle { Text(subtitle).foregroundStyle(.secondary) }
                        HStack {
                            Label("\(detail.pages.count) 页", systemImage: "doc.text")
                            if let category = detail.summary.category { Label(category, systemImage: "folder") }
                            Spacer()
                            if let rating = detail.summary.rating { Label(String(format: "%.1f", rating), systemImage: "star.fill") }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        if model.useDemoData == false, detail.apiUID != nil, detail.apiKey != nil {
                            Menu("我的评分", systemImage: "star") {
                                ForEach(1...5, id: \.self) { value in
                                    Button("评分 \(value)") {
                                        Task { await model.rate(detail, value: Double(value)) }
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        if detail.tags.isEmpty == false {
                            FlowTags(tags: detail.tags)
                        }
                        if let descriptionText = detail.descriptionText {
                            Text(descriptionText).font(.body)
                        }
                        if let externalURL = detail.externalURL {
                            Link("在站点打开", destination: externalURL)
                                .font(.subheadline)
                        }
                        if model.useDemoData == false, (detail.torrentURL != nil || detail.archiveURL != nil) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("下载资源").font(.headline)
                                if torrents.isEmpty == false {
                                    ForEach(torrents) { torrent in
                                        Link(destination: torrent.url) {
                                            Label(torrent.name, systemImage: "arrow.down.doc")
                                        }
                                    }
                                }
                                if archiveOptions.isEmpty == false {
                                    Menu("站点归档", systemImage: "archivebox") {
                                        ForEach(archiveOptions) { option in
                                            Button(option.name) {
                                                Task {
                                                    if let url = await model.archiveDownloadURL(for: key, resolution: option.resolution) {
                                                        openURL(url)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                }
                                if torrents.isEmpty && archiveOptions.isEmpty {
                                    Text("正在读取可用资源，或当前账户没有权限。")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 10)],
                            alignment: .leading,
                            spacing: 10
                        ) {
                            NavigationLink(value: AppRoute.reader(key, page: 0)) {
                                Label("开始阅读", systemImage: "book")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("start-reading-action")
                            #if os(macOS)
                            Button {
                                openWindow(value: AppRoute.reader(key, page: 0))
                            } label: {
                                Label("新窗口阅读", systemImage: "rectangle.split.2x1")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("new-window-reader-action")
                            #endif
                            Button {
                                Task { await model.enqueue(detail) }
                            } label: {
                                Label("加入下载", systemImage: "arrow.down.circle")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("enqueue-download-action")
                            Button {
                                Task {
                                    await model.toggleFavorite(for: key, remoteDetail: detail)
                                    isFavorite = await model.favoriteState(for: key)
                                }
                            } label: {
                                Label(isFavorite ? "取消收藏" : "收藏", systemImage: isFavorite ? "heart.fill" : "heart")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("favorite-action")
                        }
                    }
                    .padding()
                    .frame(maxWidth: 760, alignment: .leading)
                    if comments.isEmpty == false || model.useDemoData == false {
                        GalleryCommentsSection(comments: comments, commentText: $commentText, canSubmit: model.useDemoData == false && model.isGuestMode == false) {
                            guard commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
                            let body = commentText
                            commentText = ""
                            Task {
                                if let updated = await model.submitComment(for: detail, body: body) {
                                    comments = updated
                                }
                            }
                        }
                        .padding(.horizontal)
                        .frame(maxWidth: 760, alignment: .leading)
                    }
                }
            } else {
                ProgressView("读取详情…")
            }
        }
        .navigationTitle("详情")
        .task(id: key) {
            detail = await model.detail(for: key)
            isFavorite = await model.favoriteState(for: key)
            comments = detail?.comments ?? []
            if detail != nil, model.useDemoData == false {
                async let loadedTorrents = model.torrents(for: key)
                async let loadedArchives = model.archiveOptions(for: key)
                torrents = await loadedTorrents
                archiveOptions = await loadedArchives
            }
        }
    }
}

private struct GalleryCommentsSection: View {
    let comments: [GalleryComment]
    @Binding var commentText: String
    let canSubmit: Bool
    let submit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("评论").font(.headline)
            ForEach(comments) { comment in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(comment.author).font(.subheadline.bold())
                        Spacer()
                        if comment.score != 0 { Text("评分 \(comment.score)").font(.caption).foregroundStyle(.secondary) }
                    }
                    Text(comment.body)
                        .font(.callout)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(10)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            }
            TextField(canSubmit ? "写评论" : "登录后发表评论", text: $commentText, axis: .vertical)
                .lineLimit(3...6)
                .disabled(canSubmit == false)
            Button("发布评论", systemImage: "paperplane") { submit() }
                .buttonStyle(.bordered)
                .disabled(canSubmit == false || commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

private struct GalleryDetailHero: View {
    @Environment(AppModel.self) private var model
    let summary: GallerySummary
    @State private var image: Image?

    var body: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(LinearGradient(colors: [.blue.opacity(0.7), .mint.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(height: 190)
            .overlay {
                if let image {
                    image.resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 18))
                } else {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .accessibilityLabel("画廊封面预览")
            .task(id: summary.thumbnailURL) {
                guard let thumbnailURL = summary.thumbnailURL else { return }
                do {
                    let page = GalleryPageImage(galleryKey: summary.key, index: 0, imageURL: thumbnailURL)
                    let data = try await model.imageData(for: page)
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
                    image = Image(decorative: cgImage, scale: 1, orientation: .up)
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            }
    }
}

private struct FlowTags: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let tags: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Button {
                    dismiss()
                    model.searchTag(tag)
                } label: {
                    Text(model.localizedTag(tag))
                        .font(.caption)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .background(.quaternary, in: Capsule())
                .contentShape(Capsule())
                .accessibilityIdentifier("tag-search-\(tag)")
                .accessibilityLabel("搜索标签 \(model.localizedTag(tag))")
                .accessibilityHint("在浏览页显示这个标签的结果")
            }
        }
    }
}
