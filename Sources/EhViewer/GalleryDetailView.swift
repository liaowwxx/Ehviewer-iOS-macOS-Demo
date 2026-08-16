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
    @State private var readingPage: Int?
    @State private var isLoadingDetail = true
    @State private var detailError: String?
    @State private var detailLoadToken = UUID()
    @State private var isEnqueueing = false
    @State private var isUpdatingFavorite = false
    @State private var isRating = false
    @State private var isSubmittingComment = false
    @State private var downloadJob: DownloadJob?

    var body: some View {
        Group {
            if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        GalleryDetailHeader(summary: detail.summary, pageCount: detail.pages.count)

                        VStack(alignment: .leading, spacing: 20) {
                            GalleryInfoCard(detail: detail, readingPage: readingPage)

                            actionSection(detail)

                            if detail.tags.isEmpty == false {
                                GroupedTags(tags: detail.tags)
                            }
                            if let descriptionText = detail.descriptionText {
                                Text(descriptionText).font(.body)
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

                        if detail.pages.isEmpty == false {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("预览").font(.headline)
                                GalleryPreviewGrid(key: key, pages: detail.pages)
                            }
                            .padding(.horizontal)
                            .frame(maxWidth: 760, alignment: .leading)
                            .padding(.bottom, 12)
                        }
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
                    .padding(.bottom, 12)
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if let externalURL = detail?.externalURL {
                        Link("在站点打开", destination: externalURL)
                    }
                    Button("刷新", systemImage: "arrow.clockwise") {
                        detailLoadToken = UUID()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("detail-more-menu")
            }
        }
        .task(id: "\(key.id)-\(detailLoadToken)") {
            await loadDetail()
        }
        .task(id: key.id) {
            readingPage = await model.readingPage(for: key)
        }
        .task {
            for await event in await model.downloads.events() {
                applyDownloadEvent(event)
            }
        }
    }

    @ViewBuilder
    private func actionSection(_ detail: GalleryDetail) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                NavigationLink(value: AppRoute.reader(key, page: 0)) {
                    Label(readingActionTitle, systemImage: downloadJob == nil ? "book" : "internaldrive")
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
                if let downloadJob {
                    Label(downloadStatusTitle(downloadJob), systemImage: downloadStatusIcon(downloadJob))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("download-status")
                } else {
                    Button {
                        isEnqueueing = true
                        Task {
                            defer { isEnqueueing = false }
                            await model.enqueue(detail)
                            downloadJob = await model.downloadJob(for: key)
                        }
                    } label: {
                        Label("加入下载", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isEnqueueing)
                    .accessibilityIdentifier("enqueue-download-action")
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 130), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                Button {
                    isUpdatingFavorite = true
                    Task {
                        defer { isUpdatingFavorite = false }
                        await model.toggleFavorite(for: key, remoteDetail: detail)
                        isFavorite = await model.favoriteState(for: key)
                    }
                } label: {
                    Label(favoriteTitle, systemImage: isFavorite ? "heart.fill" : "heart")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(isUpdatingFavorite)
                .accessibilityIdentifier("favorite-action")

                if detail.apiUID != nil, detail.apiKey != nil {
                    Menu {
                        ForEach(1...5, id: \.self) { value in
                            Button("评分 \(value)") {
                                isRating = true
                                Task {
                                    defer { isRating = false }
                                    await model.rate(detail, value: Double(value))
                                }
                            }
                        }
                    } label: {
                        Label("评分", systemImage: "star")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRating)
                    .accessibilityIdentifier("rate-action")
                }

                if let externalURL = detail.externalURL {
                    ShareLink(item: externalURL) {
                        Label("分享", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("share-action")
                }

                if let similarQuery = similarSearchQuery(for: detail) {
                    NavigationLink(value: AppRoute.search(similarQuery)) {
                        Label("相似画廊", systemImage: "rectangle.on.rectangle.angled")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("similar-gallery-action")
                }
            }
        }
    }

    private var favoriteTitle: String {
        if isFavorite {
            return detail?.favoriteName ?? String(localized: "取消收藏")
        }
        return String(localized: "收藏")
    }

    /// Mirrors the reference client's `showSimilarGalleryList`: title keyword,
    /// then the first artist tag, then the uploader.
    private func similarSearchQuery(for detail: GalleryDetail) -> String? {
        if let keyword = SearchQueryComposer.extractTitleKeyword(from: detail.summary.title) {
            return SearchQueryComposer.exactKeyword(keyword)
        }
        if let artist = detail.tags.first(where: { $0.lowercased().hasPrefix("artist:") }) {
            return SearchQueryComposer.searchSyntax(for: artist)
        }
        if let uploader = detail.summary.uploader {
            return SearchQueryComposer.uploaderSyntax(uploader)
        }
        return nil
    }

    private func loadDetail() async {
        isLoadingDetail = true
        detailError = nil
        let localJob = await model.downloadJob(for: key)
        downloadJob = localJob
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
            if let localJob {
                detail = ReaderView.downloadedDetail(for: localJob, site: model.site)
                comments = []
            } else {
                detailError = error.localizedDescription
            }
        }
        isLoadingDetail = false
    }

    private var readingActionTitle: String {
        guard let downloadJob else { return String(localized: "开始阅读") }
        return downloadJob.completedPageIndexes.isEmpty ? String(localized: "开始阅读（下载中）") : String(localized: "阅读本地内容")
    }

    private func downloadStatusTitle(_ job: DownloadJob) -> String {
        switch job.state {
        case .completed: String(localized: "已下载")
        case .queued, .running: String(localized: "下载中 \(job.completedPageIndexes.count)/\(job.pages.count)")
        case .paused: String(localized: "下载已暂停 \(job.completedPageIndexes.count)/\(job.pages.count)")
        case .failed, .authenticationRequired, .rateLimited, .bandwidthLimited: String(localized: "下载异常，可在下载页重试")
        case .cancelled: String(localized: "下载已取消")
        }
    }

    private func downloadStatusIcon(_ job: DownloadJob) -> String {
        switch job.state {
        case .completed: "checkmark.circle.fill"
        case .queued, .running: "arrow.down.circle"
        case .paused: "pause.circle"
        case .failed, .authenticationRequired, .rateLimited, .bandwidthLimited: "exclamationmark.triangle"
        case .cancelled: "xmark.circle"
        }
    }

    private func applyDownloadEvent(_ event: DownloadEvent) {
        switch event {
        case .reset(let jobs):
            downloadJob = jobs.first { $0.key == key }
        case .changed(let job) where job.key == key:
            downloadJob = job
        case .removed(let removedKey) where removedKey == key:
            downloadJob = nil
        default:
            break
        }
    }
}

/// Language | Pages | File Size on the first row and Favorite count | Posted
/// on the second, mirroring the reference detail info table.
private struct GalleryInfoCard: View {
    let detail: GalleryDetail
    let readingPage: Int?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                infoCell(String(localized: "语言"), detail.language ?? "—", alignment: .leading)
                columnDivider()
                infoCell(String(localized: "页数"), pagesText, alignment: .center)
                columnDivider()
                infoCell(String(localized: "大小"), detail.fileSize ?? "—", alignment: .trailing)
            }
            Divider()
            HStack(spacing: 0) {
                infoCell(String(localized: "收藏次数"), detail.favoriteCount.map { "\($0)" } ?? "—", alignment: .leading)
                columnDivider()
                infoCell(String(localized: "发布于"), postedText, alignment: .trailing)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("语言 \(detail.language ?? String(localized: "未知"))，\(pagesText)，大小 \(detail.fileSize ?? String(localized: "未知"))，收藏 \(detail.favoriteCount.map { "\($0)" } ?? String(localized: "未知")) 次，\(postedText)")
    }

    private func infoCell(_ label: String, _ value: String, alignment: Alignment) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }

    private func columnDivider() -> some View {
        Divider().frame(height: 30)
    }

    private var pagesText: String {
        guard let pageCount = detail.summary.pageCount, pageCount > 0 else { return "—" }
        if let readingPage, readingPage >= 0 {
            return String(localized: "\(min(readingPage + 1, pageCount))/\(pageCount) 页")
        }
        return String(localized: "\(pageCount) 页")
    }

    private var postedText: String {
        guard let postedAt = detail.summary.postedAt else { return "—" }
        return postedAt.formatted(date: .numeric, time: .omitted)
    }
}

private struct GalleryCommentsSection: View {
    let comments: [GalleryComment]
    @Binding var commentText: String
    let canSubmit: Bool
    let isSubmitting: Bool
    let submit: () -> Void
    @State private var showingAllComments = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("评论").font(.headline)
            ForEach(visibleComments) { comment in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(comment.author).font(.subheadline.bold())
                        Spacer()
                        if let postedAt = comment.postedAt {
                            Text(postedAt, format: .relative(presentation: .named))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
            if comments.count > 2 {
                Button(showingAllComments ? "收起评论" : "更多评论（共 \(comments.count) 条）") {
                    showingAllComments.toggle()
                }
                .font(.subheadline)
                .accessibilityIdentifier("more-comments-action")
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

    private var visibleComments: [GalleryComment] {
        showingAllComments ? comments : Array(comments.prefix(2))
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

            VStack(alignment: .leading, spacing: 8) {
                Text(summary.displayTitle(showJapaneseTitle: model.readingSettings.showJapaneseTitle))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
                if let uploader = summary.uploader {
                    NavigationLink(value: AppRoute.search(SearchQueryComposer.uploaderSyntax(uploader))) {
                        Label(uploader, systemImage: "person")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                    .accessibilityLabel("上传者 \(uploader)，点击查看其画廊")
                }
                if let category = summary.category {
                    CategoryBadge(name: category)
                }
                HStack(spacing: 12) {
                    Label("\(pageCount) 页", systemImage: "doc.text")
                    if let rating = summary.rating {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                    }
                    if let ratingCount = summary.ratingCount {
                        Text("\(ratingCount) 人评分")
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
        .accessibilityLabel("\(summary.displayTitle(showJapaneseTitle: model.readingSettings.showJapaneseTitle))，\(pageCount) 页")
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

/// Tags grouped by namespace with a translated group header, mirroring the
/// reference detail scene's `bindTags`: the group header uses the accent
/// color, tags use the primary color, white text, 22 pt tall chips.
private struct GroupedTags: View {
    @Environment(AppModel.self) private var model
    let tags: [String]

    private var groups: [TagGroup] {
        var order: [String] = []
        var grouped: [String: [String]] = [:]
        for tag in tags {
            let namespace: String
            if let separator = tag.firstIndex(of: ":") {
                namespace = String(tag[..<separator])
            } else {
                namespace = "misc"
            }
            if grouped[namespace] == nil { order.append(namespace) }
            grouped[namespace, default: []].append(tag)
        }
        return order.map { TagGroup(namespace: $0, tags: grouped[$0] ?? []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(groupTitle(group))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(AppTheme.tagGroupBackground, in: RoundedRectangle(cornerRadius: 6))
                    TagFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                        ForEach(group.tags, id: \.self) { tag in
                            NavigationLink(value: AppRoute.search(SearchQueryComposer.searchSyntax(for: tag))) {
                                Text(model.displayTag(tag))
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .frame(height: 22)
                            }
                            .buttonStyle(.plain)
                            .background(AppTheme.tagBackground, in: Capsule())
                            .contentShape(Capsule())
                            .accessibilityIdentifier("tag-search-\(tag)")
                            .accessibilityLabel("搜索标签 \(model.displayTag(tag))")
                            .accessibilityHint("在浏览页显示这个标签的结果")
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("detail-tag-groups")
    }

    private func groupTitle(_ group: TagGroup) -> String {
        guard model.readingSettings.showTagTranslations else { return group.namespace }
        let key = "n:\(group.namespace)"
        let translated = model.localizedTag(key)
        return translated == key ? group.namespace : translated
    }
}

private struct TagGroup: Identifiable {
    let namespace: String
    let tags: [String]

    var id: String { namespace }
}

/// Preview thumbnail grid with page numbers, mirroring the reference detail
/// scene's `bindPreviews`: only the first 27 previews render initially and a
/// "more previews" action reveals the rest.
private struct GalleryPreviewGrid: View {
    let key: GalleryKey
    let pages: [GalleryPageDescriptor]
    @State private var showingAll = false

    private static let initialPreviewCount = 27
    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 130), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(visiblePages) { page in
                    NavigationLink(value: AppRoute.reader(key, page: page.index)) {
                        VStack(spacing: 2) {
                            Color.clear
                                .aspectRatio(page.previewClip?.clampedAspect ?? 0.667, contentMode: .fit)
                                .overlay {
                                    GalleryPreviewThumbnail(descriptor: page)
                                }
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text("\(page.index + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("预览第 \(page.index + 1) 页")
                }
            }
            if pages.count > Self.initialPreviewCount {
                Button(showingAll ? "收起预览" : "更多预览（共 \(pages.count)）") {
                    showingAll.toggle()
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("more-previews-action")
            }
        }
        .accessibilityIdentifier("detail-previews-grid")
    }

    private var visiblePages: [GalleryPageDescriptor] {
        showingAll ? pages : Array(pages.prefix(Self.initialPreviewCount))
    }
}

private struct GalleryPreviewThumbnail: View {
    @Environment(AppModel.self) private var model
    let descriptor: GalleryPageDescriptor
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary.opacity(0.5))
                    .overlay {
                        Image(systemName: "photo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .task(id: descriptor.previewURL) {
            image = nil
            guard let url = descriptor.previewURL else { return }
            do {
                let page = GalleryPageImage(galleryKey: descriptor.galleryKey, index: descriptor.index, imageURL: url)
                let data = try await model.imageData(for: page)
                image = Self.decodedPreview(from: data, clip: descriptor.previewClip)
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
        .accessibilityHidden(true)
    }

    /// Loads the large preview image and crops the site's visible window,
    /// mirroring the reference client's clipped `LoadImageView` rendering.
    static func decodedPreview(from data: Data, clip: GalleryPreviewClip?) -> Image? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        if let clip, clip.width > 0, clip.height > 0 {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let pixelWidth = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
            let pixelHeight = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
            if pixelWidth > 0, pixelHeight > 0 {
                var crop = clip.cropRect
                let maxDimension: CGFloat = 2400
                let scale = min(1, maxDimension / max(crop.width, crop.height))
                if scale < 1 {
                    crop = CGRect(
                        x: crop.minX * scale,
                        y: crop.minY * scale,
                        width: crop.width * scale,
                        height: crop.height * scale
                    )
                }
                crop = crop.intersection(CGRect(x: 0, y: 0, width: CGFloat(pixelWidth), height: CGFloat(pixelHeight)))
                if crop.width >= 1, crop.height >= 1,
                   let full = CGImageSourceCreateImageAtIndex(source, 0, nil),
                   let cropped = full.cropping(to: crop.integral) {
                    return Image(decorative: cropped, scale: 1, orientation: .up)
                }
            }
        }
        guard let full = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return Image(decorative: full, scale: 1, orientation: .up)
    }
}

