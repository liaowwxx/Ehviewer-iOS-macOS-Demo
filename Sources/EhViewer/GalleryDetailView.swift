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
    @State private var isLoadingDetail = true
    @State private var detailError: String?
    @State private var detailLoadToken = UUID()
    @State private var isEnqueueing = false
    @State private var isUpdatingFavorite = false
    @State private var isRating = false
    @State private var isSubmittingComment = false

    var body: some View {
        Group {
            if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        GalleryDetailHeader(summary: detail.summary, pageCount: detail.pages.count)

                        VStack(alignment: .leading, spacing: 20) {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 10)],
                                alignment: .leading,
                                spacing: 10
                            ) {
                                NavigationLink(value: AppRoute.reader(key, page: 0)) {
                                    Label("开始阅读", systemImage: "book")
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .foregroundStyle(AppTheme.onAccent)
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
                                    isEnqueueing = true
                                    Task {
                                        defer { isEnqueueing = false }
                                        await model.enqueue(detail)
                                    }
                                } label: {
                                    Label("加入下载", systemImage: "arrow.down.circle")
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.bordered)
                                .disabled(isEnqueueing)
                                .accessibilityIdentifier("enqueue-download-action")
                                Button {
                                    isUpdatingFavorite = true
                                    Task {
                                        defer { isUpdatingFavorite = false }
                                        await model.toggleFavorite(for: key, remoteDetail: detail)
                                        isFavorite = await model.favoriteState(for: key)
                                    }
                                } label: {
                                    Label(isFavorite ? "取消收藏" : "收藏", systemImage: isFavorite ? "heart.fill" : "heart")
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.bordered)
                                .disabled(isUpdatingFavorite)
                                .accessibilityIdentifier("favorite-action")
                            }

                            if detail.apiUID != nil, detail.apiKey != nil {
                                Menu("我的评分", systemImage: "star") {
                                    ForEach(1...5, id: \.self) { value in
                                        Button("评分 \(value)") {
                                            isRating = true
                                            Task {
                                                defer { isRating = false }
                                                await model.rate(detail, value: Double(value))
                                            }
                                        }
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(isRating)
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
                            if detail.torrentURL != nil || detail.archiveURL != nil {
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
                        }
                        .padding()
                        .frame(maxWidth: 760, alignment: .leading)
                    }
                    GalleryCommentsSection(
                        comments: comments,
                        commentText: $commentText,
                        canSubmit: model.isGuestMode == false,
                        isSubmitting: isSubmittingComment
                    ) {
                        guard commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
                        let body = commentText
                        isSubmittingComment = true
                        Task {
                            defer { isSubmittingComment = false }
                            if let updated = await model.submitComment(for: detail, body: body) {
                                comments = updated
                                commentText = ""
                            }
                        }
                    }
                    .padding(.horizontal)
                    .frame(maxWidth: 760, alignment: .leading)
                }
            } else if let detailError {
                VStack(spacing: 12) {
                    ContentUnavailableView("详情加载失败", systemImage: "exclamationmark.triangle", description: Text(detailError))
                    Button("重试", systemImage: "arrow.clockwise") {
                        detailLoadToken = UUID()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                ProgressView("读取详情…")
            }
        }
        .navigationTitle("详情")
        .task(id: "\(key.id)-\(detailLoadToken)") {
            await loadDetail()
        }
    }

    private func loadDetail() async {
        isLoadingDetail = true
        detailError = nil
        do {
            detail = try await model.detail(for: key)
            isFavorite = await model.favoriteState(for: key)
            comments = detail?.comments ?? []
            if detail != nil {
                async let loadedTorrents = model.torrents(for: key)
                async let loadedArchives = model.archiveOptions(for: key)
                torrents = await loadedTorrents
                archiveOptions = await loadedArchives
            }
        } catch is CancellationError {
            return
        } catch {
            detailError = error.localizedDescription
        }
        isLoadingDetail = false
    }
}

private struct GalleryCommentsSection: View {
    let comments: [GalleryComment]
    @Binding var commentText: String
    let canSubmit: Bool
    let isSubmitting: Bool
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
            Button {
                submit()
            } label: {
                if isSubmitting {
                    ProgressView()
                } else {
                    Label("发布评论", systemImage: "paperplane")
                }
            }
                .buttonStyle(.bordered)
                .disabled(isSubmitting || canSubmit == false || commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

private struct GalleryDetailHeader: View {
    @Environment(AppModel.self) private var model
    let summary: GallerySummary
    let pageCount: Int
    @State private var image: Image?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Group {
                if let image {
                    image
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 112, height: 158)
            .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.22), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 10) {
                Text(summary.preferredTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = summary.alternateTitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(2)
                }
                if let category = summary.category {
                    Text(category.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.18), in: Capsule())
                }
                HStack(spacing: 12) {
                    Label("\(pageCount) 页", systemImage: "doc.text")
                    if let rating = summary.rating {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.preferredTitle)，\(pageCount) 页")
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
        TagFlowLayout(horizontalSpacing: 6, verticalSpacing: 4) {
            ForEach(tags, id: \.self) { tag in
                Button {
                    dismiss()
                    model.searchTag(tag)
                } label: {
                    Text(model.localizedTag(tag))
                        .font(.caption)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 44, alignment: .leading)
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

private struct TagFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let availableWidth = proposal.width ?? intrinsicWidth(for: sizes)
        let rows = rows(for: sizes, in: availableWidth)
        let contentHeight = rows.reduce(into: CGFloat.zero) { height, row in
            height += row.map { sizes[$0].height }.max() ?? 0
        }
        let rowSpacing = CGFloat(max(rows.count - 1, 0)) * verticalSpacing

        return CGSize(
            width: proposal.width ?? rows.map { rowWidth($0, sizes: sizes) }.max() ?? 0,
            height: contentHeight + rowSpacing
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = rows(for: sizes, in: bounds.width)
        var y = bounds.minY

        for row in rows {
            let rowHeight = row.map { sizes[$0].height }.max() ?? 0
            var x = bounds.minX

            for index in row {
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(sizes[index])
                )
                x += sizes[index].width + horizontalSpacing
            }

            y += rowHeight + verticalSpacing
        }
    }

    private func rows(for sizes: [CGSize], in availableWidth: CGFloat) -> [[Int]] {
        guard sizes.isEmpty == false else { return [] }

        var rows: [[Int]] = [[]]
        var currentWidth: CGFloat = 0

        for index in sizes.indices {
            let itemWidth = sizes[index].width
            let spacing = rows[rows.count - 1].isEmpty ? 0 : horizontalSpacing

            if rows[rows.count - 1].isEmpty == false,
               currentWidth + spacing + itemWidth > availableWidth {
                rows.append([])
                currentWidth = 0
            }

            let rowSpacing = rows[rows.count - 1].isEmpty ? 0 : horizontalSpacing
            rows[rows.count - 1].append(index)
            currentWidth += rowSpacing + itemWidth
        }

        return rows
    }

    private func rowWidth(_ row: [Int], sizes: [CGSize]) -> CGFloat {
        row.reduce(into: CGFloat.zero) { width, index in
            width += sizes[index].width
        } + CGFloat(max(row.count - 1, 0)) * horizontalSpacing
    }

    private func intrinsicWidth(for sizes: [CGSize]) -> CGFloat {
        sizes.reduce(into: CGFloat.zero) { width, size in
            width += size.width
        } + CGFloat(max(sizes.count - 1, 0)) * horizontalSpacing
    }
}
