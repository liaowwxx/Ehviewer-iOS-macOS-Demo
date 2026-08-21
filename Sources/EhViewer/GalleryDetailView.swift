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
import CoreGraphics
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
    @State private var comments: [GalleryComment] = []
    @State private var torrents: [TorrentDescriptor] = []
    @State private var archiveOptions: [ArchiveOption] = []
    @State private var readingPage: Int?
    @State private var isLoadingDetail = true
    @State private var isLoadingMorePreviews = false
    @State private var hasCachedDetail = false
    @State private var detailError: String?
    @State private var previewError: String?
    @State private var detailLoadToken = UUID()
    @State private var isEnqueueing = false
    @State private var isUpdatingFavorite = false
    @State private var isRating = false
    @State private var downloadJob: DownloadJob?
    @State private var shouldFullyRefreshDetail = false

    var body: some View {
        Group {
            if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        GalleryDetailHeader(
                            summary: detail.summary,
                            pageCount: detail.summary.pageCount ?? detail.pages.count,
                            localPage: downloadJob?.pages.first(where: { $0.index == 0 })
                        )

                        VStack(alignment: .leading, spacing: 20) {
                            GalleryInfoCard(detail: detail, readingPage: readingPage)

                            actionSection(detail, pageListReady: pageListReady)

                            if detail.tags.isEmpty == false {
                                GroupedTags(tags: detail.tags)
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

                        GalleryCommentsSection(key: key, comments: comments)
                            .padding(.horizontal)
                            .frame(maxWidth: 760, alignment: .leading)
                            .padding(.bottom, 12)

                        if detail.pages.isEmpty == false {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("预览").font(.headline)
                                GalleryPreviewGrid(
                                    key: key,
                                    pages: detail.pages,
                                    prefersLocalMedia: downloadJob != nil
                                )
                                if isLoadingMorePreviews {
                                    ProgressView("加载中…")
                                        .font(.caption)
                                        .frame(maxWidth: .infinity)
                                }
                                if let previewError {
                                    Text(previewError)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(.horizontal)
                            .frame(maxWidth: 760, alignment: .leading)
                            .padding(.bottom, 12)
                        }
                    }
                }
            } else if let detailError {
                VStack(spacing: 12) {
                    ContentUnavailableView("详情加载失败", systemImage: "exclamationmark.triangle", description: Text(detailError))
                    Button("重试", systemImage: "arrow.clockwise") {
                        shouldFullyRefreshDetail = true
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
                Button("刷新", systemImage: "arrow.clockwise") {
                    shouldFullyRefreshDetail = true
                    detailLoadToken = UUID()
                }
                .accessibilityIdentifier("detail-refresh-action")
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    if let externalURL = detail?.externalURL {
                        Link("在站点打开", destination: externalURL)
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
    private func actionSection(_ detail: GalleryDetail, pageListReady: Bool) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                NavigationLink(value: AppRoute.reader(key, page: readerStartPage)) {
                    Label(readingActionTitle, systemImage: downloadJob == nil ? "book" : "internaldrive")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(AppTheme.onAccent)
                }
                .buttonStyle(.borderedProminent)
                .disabled(pageListReady == false)
                .accessibilityIdentifier("start-reading-action")
                #if os(macOS)
                Button {
                    openWindow(value: AppRoute.reader(key, page: readerStartPage))
                } label: {
                    Label("新窗口阅读", systemImage: "rectangle.split.2x1")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(pageListReady == false)
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
                    .disabled(isEnqueueing || pageListReady == false)
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
                    NavigationLink(value: AppRoute.search(similarQuery, advancedSearch: nil)) {
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
        isLoadingMorePreviews = false
        hasCachedDetail = false
        detailError = nil
        previewError = nil
        comments = []
        torrents = []
        archiveOptions = []
        let shouldFullyRefresh = shouldFullyRefreshDetail
        shouldFullyRefreshDetail = false
        let localJob = await model.downloadJob(for: key)
        downloadJob = localJob
        let localDetail = await model.localGalleryDetail(for: key, job: localJob)
        if let localDetail {
            detail = localDetail
            comments = localDetail.comments
            hasCachedDetail = true
            isLoadingDetail = false
            isLoadingMorePreviews = false
            isFavorite = await model.favoriteState(for: key)
            if shouldFullyRefresh == false {
                await model.prepareTagTranslations()
                return
            }
        }
        await model.prepareTagTranslations()
        let cachedDetail = localDetail == nil ? await model.cachedDetail(for: key) : nil
        if let cachedDetail {
            detail = cachedDetail
            hasCachedDetail = true
            isLoadingDetail = false
            isFavorite = await model.favoriteState(for: key)
        }
        let cachedPages = cachedDetail?.pages ?? []
        let cacheGeneration = await model.galleryCacheGeneration()
        var presentedRemoteDetail = false
        do {
            if localDetail == nil {
                isLoadingMorePreviews = true
            }
            for try await loadedDetail in model.detailStream(for: key) {
                guard Task.isCancelled == false else { return }
                detail = if let localDetail {
                    Self.detailByMergingLocal(
                        from: loadedDetail,
                        with: localDetail,
                        fullyRefresh: shouldFullyRefresh
                    )
                } else {
                    Self.detailByMergingPages(from: loadedDetail, with: cachedPages)
                }
                comments = loadedDetail.comments
                await model.cacheDetail(loadedDetail, generation: cacheGeneration)
                let stable = StableGalleryMetadataSnapshot(detail: loadedDetail, sourceSite: model.site)
                if localJob != nil {
                    try? await model.persistence.promoteToDownloadedGallery(
                        stable: stable,
                        dynamic: DownloadedGalleryDynamicSnapshot(detail: loadedDetail)
                    )
                } else {
                    try? await model.persistence.upsertStableSnapshot(stable)
                }
                if presentedRemoteDetail == false {
                    presentedRemoteDetail = true
                    isLoadingDetail = false
                    isFavorite = await model.favoriteState(for: key)
                    async let loadedTorrents = model.torrents(for: key)
                    async let loadedArchives = model.archiveOptions(for: key)
                    torrents = await loadedTorrents
                    archiveOptions = await loadedArchives
                }
                if localDetail != nil, shouldFullyRefresh == false {
                    break
                }
            }
            isLoadingMorePreviews = false
        } catch is CancellationError {
            return
        } catch {
            isLoadingMorePreviews = false
            if presentedRemoteDetail {
                previewError = error.localizedDescription
            } else if cachedDetail != nil {
                previewError = error.localizedDescription
            } else if let localDetail {
                detail = localDetail
                comments = []
            } else if let localJob {
                detail = await model.localGalleryDetail(for: key, job: localJob)
                    ?? ReaderView.downloadedDetail(for: localJob, site: model.site)
            } else {
                detailError = error.localizedDescription
            }
        }
        isLoadingDetail = false
    }

    private static func detailByMergingPages(
        from liveDetail: GalleryDetail,
        with cachedPages: [GalleryPageDescriptor]
    ) -> GalleryDetail {
        guard cachedPages.isEmpty == false else { return liveDetail }
        var merged = liveDetail
        var pagesByIndex = Dictionary(uniqueKeysWithValues: cachedPages.map { ($0.index, $0) })
        for page in liveDetail.pages {
            pagesByIndex[page.index] = page
        }
        merged.pages = pagesByIndex.values.sorted { $0.index < $1.index }
        return merged
    }

    private static func detailByMergingLocal(
        from liveDetail: GalleryDetail,
        with localDetail: GalleryDetail,
        fullyRefresh: Bool
    ) -> GalleryDetail {
        var summary = fullyRefresh ? liveDetail.summary : localDetail.summary
        if fullyRefresh == false {
            summary.rating = liveDetail.summary.rating ?? summary.rating
            summary.ratingCount = liveDetail.summary.ratingCount ?? summary.ratingCount
            summary.favoriteCategory = liveDetail.summary.favoriteCategory ?? summary.favoriteCategory
        }

        let pages: [GalleryPageDescriptor]
        if fullyRefresh {
            pages = detailByMergingPages(from: liveDetail, with: localDetail.pages).pages
        } else {
            var pagesByIndex = Dictionary(uniqueKeysWithValues: localDetail.pages.map { ($0.index, $0) })
            for page in liveDetail.pages where pagesByIndex[page.index] == nil {
                pagesByIndex[page.index] = page
            }
            pages = pagesByIndex.values.sorted { $0.index < $1.index }
        }

        return GalleryDetail(
            summary: summary,
            pages: pages,
            tags: fullyRefresh || localDetail.tags.isEmpty ? liveDetail.tags : localDetail.tags,
            comments: liveDetail.comments,
            descriptionText: liveDetail.descriptionText ?? localDetail.descriptionText,
            externalURL: liveDetail.externalURL ?? localDetail.externalURL,
            apiUID: liveDetail.apiUID ?? localDetail.apiUID,
            apiKey: liveDetail.apiKey ?? localDetail.apiKey,
            favoriteCount: liveDetail.favoriteCount ?? localDetail.favoriteCount,
            favoriteName: liveDetail.favoriteName ?? localDetail.favoriteName,
            ratingCount: liveDetail.ratingCount ?? localDetail.ratingCount,
            language: liveDetail.language ?? localDetail.language,
            fileSize: liveDetail.fileSize ?? localDetail.fileSize,
            torrentURL: liveDetail.torrentURL ?? localDetail.torrentURL,
            torrentCount: liveDetail.torrentCount ?? localDetail.torrentCount,
            archiveURL: liveDetail.archiveURL ?? localDetail.archiveURL
        )
    }

    private var readingActionTitle: String {
        if isLoadingMorePreviews {
            return String(localized: "加载中…")
        }
        if previewError != nil {
            return String(localized: "加载失败")
        }
        guard let downloadJob else { return String(localized: "开始阅读") }
        return downloadJob.completedPageIndexes.isEmpty ? String(localized: "开始阅读（下载中）") : String(localized: "阅读本地内容")
    }

    private var readerStartPage: Int {
        guard let detail else { return 0 }
        switch model.readingSettings.startPosition {
        case .lastRead:
            return readingPage ?? 0
        case .first:
            return 0
        case .last:
            return max(detail.pages.count - 1, 0)
        }
    }

    private var pageListReady: Bool {
        let cachedPageListReady = hasCachedDetail && isLoadingMorePreviews == false && detail.map { cachedDetail in
            guard let pageCount = cachedDetail.summary.pageCount, pageCount > 0 else { return false }
            return cachedDetail.pages.count >= pageCount
        } == true
        return cachedPageListReady || (isLoadingMorePreviews == false && previewError == nil)
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
        case .removedMany(let removedKeys) where removedKeys.contains(key):
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
    let key: GalleryKey
    let comments: [GalleryComment]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("评论").font(.headline)
            ForEach(comments.prefix(2)) { comment in
                GalleryCommentCard(comment: comment)
            }
            if comments.count > 2 {
                NavigationLink(value: AppRoute.comments(key)) {
                    Label("更多评论（共 \(comments.count) 条）", systemImage: "text.bubble")
                }
                .font(.subheadline)
                .accessibilityIdentifier("more-comments-action")
            }
        }
    }
}

private enum GalleryThumbnailDecoder {
    static func thumbnailCGImage(from data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    static func previewCGImage(from data: Data, clip: GalleryPreviewClip?) -> CGImage? {
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
                    return cropped
                }
            }
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func decodeThumbnailCGImage(from data: Data, maxPixelSize: Int) async -> CGImage? {
        let decoding = Task.detached(priority: .utility) {
            thumbnailCGImage(from: data, maxPixelSize: maxPixelSize)
        }
        return await withTaskCancellationHandler {
            guard let image = await decoding.value, Task.isCancelled == false else { return nil }
            return image
        } onCancel: {
            decoding.cancel()
        }
    }

    static func decodePreviewCGImage(from data: Data, clip: GalleryPreviewClip?) async -> CGImage? {
        let decoding = Task.detached(priority: .utility) {
            previewCGImage(from: data, clip: clip)
        }
        return await withTaskCancellationHandler {
            guard let image = await decoding.value, Task.isCancelled == false else { return nil }
            return image
        } onCancel: {
            decoding.cancel()
        }
    }
}

private struct GalleryDetailHeader: View {
    @Environment(AppModel.self) private var model
    let summary: GallerySummary
    let pageCount: Int
    let localPage: GalleryPageDescriptor?
    @State private var image: Image?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Group {
                if let image {
                    image
                        .resizable()
                        .scaledToFit()
                        .transition(.opacity)
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
                    NavigationLink(value: AppRoute.search(SearchQueryComposer.uploaderSyntax(uploader), advancedSearch: nil)) {
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
        .task(id: "\(summary.thumbnailURL?.absoluteString ?? "")-\(localPage?.id ?? "")", priority: .utility) {
            if let localPage,
               let data = await model.downloadedPageDataIfAvailable(for: localPage),
               let localCGImage = await GalleryThumbnailDecoder.decodeThumbnailCGImage(from: data, maxPixelSize: 512) {
                guard Task.isCancelled == false else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    image = Image(decorative: localCGImage, scale: 1, orientation: .up)
                }
                return
            }
            guard let thumbnailURL = summary.thumbnailURL else { return }
            do {
                let page = GalleryPageImage(galleryKey: summary.key, index: 0, imageURL: thumbnailURL)
                let data = try await model.galleryImageData(for: page)
                guard let cgImage = await GalleryThumbnailDecoder.decodeThumbnailCGImage(
                    from: data,
                    maxPixelSize: 512
                ), Task.isCancelled == false else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    image = Image(decorative: cgImage, scale: 1, orientation: .up)
                }
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
                            NavigationLink(value: AppRoute.search(SearchQueryComposer.searchSyntax(for: tag), advancedSearch: nil)) {
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

struct GalleryPreviewRevealState: Hashable, Sendable {
    static let initialCount = 27
    static let batchSize = 20

    private(set) var visibleCount = initialCount

    mutating func revealNext(totalCount: Int, revealAll: Bool = false) {
        visibleCount = revealAll ? totalCount : min(visibleCount + Self.batchSize, totalCount)
    }

    mutating func collapse() {
        visibleCount = Self.initialCount
    }
}

enum GalleryPreviewLoadPolicy {
    static let immediateCount = 12
    static let maximumDelayMilliseconds = 500

    /// Mirrors the reference client's staggered preview loading schedule.
    /// The first twelve tasks start immediately; later tasks are queued on
    /// the event loop and then spread out in 50 ms steps, capped at 500 ms.
    static func delayMilliseconds(for ordinal: Int) -> Int {
        guard ordinal >= immediateCount else { return 0 }
        return min((ordinal - immediateCount) * 50, maximumDelayMilliseconds)
    }
}

/// Preview thumbnail grid with page numbers, mirroring the reference detail
/// scene's `bindPreviews`: only the first 27 previews render initially. Remote
/// galleries reveal the rest in batches of 20; a downloaded gallery reveals
/// all pages at once while the lazy grid still limits view creation to the
/// pages currently on screen.
private struct GalleryPreviewGrid: View {
    let key: GalleryKey
    let pages: [GalleryPageDescriptor]
    let prefersLocalMedia: Bool
    @State private var revealState = GalleryPreviewRevealState()

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 130), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(visiblePages.enumerated()), id: \.element.id) { ordinal, page in
                    NavigationLink {
                        ReaderView(key: key, initialPage: page.index)
                    } label: {
                        VStack(spacing: 2) {
                            Color.clear
                                .aspectRatio(page.previewClip?.clampedAspect ?? 0.667, contentMode: .fit)
                                .overlay {
                                    GalleryPreviewThumbnail(
                                        descriptor: page,
                                        prefersLocalMedia: prefersLocalMedia,
                                        loadOrdinal: ordinal
                                    )
                                }
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .allowsHitTesting(false)
                            Text("\(page.index + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityLabel("预览第 \(page.index + 1) 页")
                }
            }
            if pages.count > GalleryPreviewRevealState.initialCount {
                if revealState.visibleCount < pages.count {
                    Button("更多预览（共 \(pages.count)）") {
                        revealState.revealNext(
                            totalCount: pages.count,
                            revealAll: prefersLocalMedia
                        )
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("more-previews-action")
                } else {
                    Button("收起预览") {
                        revealState.collapse()
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("more-previews-action")
                }
            }
        }
        .accessibilityIdentifier("detail-previews-grid")
    }

    private var visiblePages: [GalleryPageDescriptor] {
        Array(pages.prefix(revealState.visibleCount))
    }
}

private struct GalleryPreviewThumbnail: View {
    @Environment(AppModel.self) private var model
    let descriptor: GalleryPageDescriptor
    let prefersLocalMedia: Bool
    let loadOrdinal: Int
    @State private var image: Image?

    var body: some View {
        Group {
                if let image {
                    image
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
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
        .task(id: "\(descriptor.previewURL?.absoluteString ?? "")-\(prefersLocalMedia)", priority: .utility) {
            image = nil
            if prefersLocalMedia,
               let localData = await model.downloadedPageDataIfAvailable(for: descriptor),
               let localCGImage = await ReaderThumbnailLoader.shared.thumbnail(
                   for: descriptor.id,
                   data: localData
               ) {
                guard Task.isCancelled == false else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    image = Image(decorative: localCGImage, scale: 1, orientation: .up)
                }
                return
            }
            guard let url = descriptor.previewURL else { return }
            let delayMilliseconds = GalleryPreviewLoadPolicy.delayMilliseconds(for: loadOrdinal)
            if loadOrdinal >= GalleryPreviewLoadPolicy.immediateCount {
                if delayMilliseconds > 0 {
                    do {
                        try await Task.sleep(for: .milliseconds(delayMilliseconds))
                    } catch {
                        return
                    }
                } else {
                    await Task.yield()
                }
                guard Task.isCancelled == false else { return }
            }
            do {
                let page = GalleryPageImage(galleryKey: descriptor.galleryKey, index: descriptor.index, imageURL: url)
                let data = try await model.galleryImageData(for: page)
                guard let cgImage = await GalleryThumbnailDecoder.decodePreviewCGImage(
                    from: data,
                    clip: descriptor.previewClip
                ), Task.isCancelled == false else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    image = Image(decorative: cgImage, scale: 1, orientation: .up)
                }
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
        guard let cgImage = GalleryThumbnailDecoder.previewCGImage(from: data, clip: clip) else { return nil }
        return Image(decorative: cgImage, scale: 1, orientation: .up)
    }
}
