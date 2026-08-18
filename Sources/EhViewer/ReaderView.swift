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
import EHDomain
import EHDownloads

#if os(macOS)
enum MacReaderLayoutMetrics {
    /// The macOS window toolbar is transparent over the reader content.
    static let titleBarClearance: CGFloat = 5
}
#endif

enum ReaderContentSource: Hashable, Sendable {
    case remote
    case download
}

struct ReaderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    let key: GalleryKey
    let initialPage: Int
    private let downloadedJob: DownloadJob?
    private let usesSavedProgress: Bool
    @State private var source: ReaderContentSource
    @State private var detail: GalleryDetail?
    @State private var position: ReaderPositionState
    /// 阅读控件显隐：点击页面手动切换。
    @State private var isShowingControls = true
    @State private var zoomResetToken = UUID()
    @State private var detailError: String?
    @State private var detailLoadToken = UUID()
    @State private var progressSaveTask: Task<Void, Never>?
#if os(macOS)
    @FocusState private var readerContentFocused: Bool
#endif
#if os(iOS)
    @State private var volumeMonitor = VolumeButtonMonitor()
#endif

    private var readingMode: ReadingMode { model.readingSettings.readingMode }

    init(key: GalleryKey, initialPage: Int) {
        self.key = key
        self.initialPage = initialPage
        downloadedJob = nil
        usesSavedProgress = false
        _source = State(initialValue: .remote)
        _position = State(initialValue: ReaderPositionState(page: initialPage))
    }

    init(downloaded job: DownloadJob, initialPage: Int) {
        key = job.key
        self.initialPage = initialPage
        downloadedJob = job
        usesSavedProgress = true
        _source = State(initialValue: .download)
        _position = State(initialValue: ReaderPositionState(page: initialPage))
    }

    var body: some View {
        readerRoot
            .task(id: position.page) {
            guard source == .remote, let detail else { return }
            await model.prefetch(
                prefetchDescriptors(in: detail.pages, around: position.page),
                resolution: .preview
            )
        }
        .onKeyPress(.leftArrow) {
            guard let detail else { return .ignored }
            requestPage(position.page + horizontalPageDelta(forLeftDirection: true), pageCount: detail.pages.count)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard let detail else { return .ignored }
            requestPage(position.page + horizontalPageDelta(forLeftDirection: false), pageCount: detail.pages.count)
            return .handled
        }
        .navigationTitle(readerNavigationTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ReaderSettingsMenu()
            }
            ToolbarItem(placement: .primaryAction) {
                if let externalURL = detail?.externalURL {
                    ShareLink(item: externalURL) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .task(id: "\(key.id)-\(source)-\(detailLoadToken)") {
            await loadDetail()
        }
        .onChange(of: model.readingSettings) { oldSettings, newSettings in
            model.persistReadingSettings()
            if oldSettings.readingMode != newSettings.readingMode ||
                oldSettings.readingDirection != newSettings.readingDirection {
                resetZoom()
                if let detail {
                    position.requestPage(position.page, pageCount: detail.pages.count)
                }
            }
        }
#if os(macOS)
        .onChange(of: detail != nil) { _, isReady in
            guard isReady else { return }
            readerContentFocused = true
        }
#endif
        .onChange(of: position.page) { _, _ in
            scheduleProgressSave()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { saveProgressImmediately() }
        }
        .onDisappear {
            saveProgressImmediately()
        }
        .onAppear {
            applyReaderSystemSettings()
            #if os(iOS)
            updateVolumeMonitor()
            #endif
        }
        #if os(iOS)
        .onChange(of: model.readingSettings.screenRotation) { _, _ in
            applyReaderSystemSettings()
        }
        .onChange(of: model.readingSettings.volumePage) { _, _ in
            updateVolumeMonitor()
        }
        .onChange(of: volumeMonitor.direction) { _, direction in
            guard let direction, let detail else { return }
            let multiplier = model.readingSettings.reverseVolumePage ? -1 : 1
            requestPage(position.page + direction * multiplier, pageCount: detail.pages.count)
            volumeMonitor.direction = nil
        }
        .onDisappear {
            restoreReaderSystemSettings()
            volumeMonitor.stop()
        }
        #endif
        #if os(iOS)
        .toolbar(isShowingControls ? .visible : .hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isShowingControls, let detail {
                ReaderProgressControl(
                    page: position.page,
                    pageCount: detail.pages.count,
                    descriptors: detail.pages,
                    source: source,
                    requestPage: { page in
                        requestPage(page, pageCount: detail.pages.count, animated: false)
                    },
                    onSeekEnded: saveProgressImmediately
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        #elseif os(macOS)
        .toolbar(.visible)
        #endif
    }

    private var readerRoot: some View {
#if os(macOS)
        macReaderLayout
            .focusable()
            .focusEffectDisabled()
            .focused($readerContentFocused)
            .onAppear { readerContentFocused = true }
            .onKeyPress(.space) {
                guard let detail else { return .ignored }
                requestPage(position.page + horizontalPageDelta(forLeftDirection: false), pageCount: detail.pages.count)
                return .handled
            }
#else
        readerContent
#endif
    }

    /// 阅读内容：分页/连续两种模式，或加载中/失败状态。
    private var readerContent: some View {
        Group {
            if let detail {
                if readingMode == .verticalPaged {
                    ReaderVerticalPagedView(
                        descriptors: detail.pages,
                        resolution: .preview,
                        resetToken: zoomResetToken,
                        source: source,
                        position: $position
                    )
#if os(iOS)
                    .onTapGesture(perform: toggleControls)
#endif
                } else {
                    ReaderPagedView(
                        descriptors: detail.pages,
                        resolution: .preview,
                        resetToken: zoomResetToken,
                        readingDirection: model.readingSettings.readingDirection,
                        source: source,
                        position: $position
                    )
#if os(iOS)
                    .onTapGesture(perform: toggleControls)
#endif
                }
            } else if let detailError {
                VStack(spacing: 12) {
                    ContentUnavailableView("阅读器加载失败", systemImage: "exclamationmark.triangle", description: Text(detailError))
                    Button("重试", systemImage: "arrow.clockwise") {
                        detailLoadToken = UUID()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                ProgressView("准备阅读器…")
            }
        }
    }

#if os(macOS)
    /// macOS 的窗口工具栏和阅读进度控件会覆盖内容，因此使用真实的
    /// 上下布局区域，而不是依赖窗口 safe area 对分页滚动容器的传播。
    private var macReaderLayout: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: MacReaderLayoutMetrics.titleBarClearance)

            readerContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let detail {
                ReaderProgressControl(
                    page: position.page,
                    pageCount: detail.pages.count,
                    descriptors: detail.pages,
                    source: source,
                    requestPage: { page in
                        requestPage(page, pageCount: detail.pages.count, animated: false)
                    },
                    onSeekEnded: saveProgressImmediately
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
#endif

    private var readerNavigationTitle: String {
        guard let detail else { return String(localized: "阅读") }
        return detail.summary.displayTitle(showJapaneseTitle: model.readingSettings.showJapaneseTitle)
    }

    private func resetZoom() {
        zoomResetToken = UUID()
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isShowingControls.toggle()
        }
    }

    private func loadDetail() async {
        detail = nil
        detailError = nil
        do {
            let loadedDetail: GalleryDetail
            let localJob: DownloadJob?
            if let downloadedJob {
                localJob = downloadedJob
            } else {
                localJob = await model.downloadJob(for: key)
            }
            if let localJob {
                source = .download
                loadedDetail = try await readerDetail(for: localJob)
            } else {
                source = .remote
                loadedDetail = try await model.detail(for: key)
            }
            guard Task.isCancelled == false else { return }
            let savedPage = await model.readingPage(for: key)
            guard Task.isCancelled == false else { return }
            let startPage: Int
            if usesSavedProgress {
                startPage = switch model.readingSettings.startPosition {
                case .lastRead: savedPage ?? initialPage
                case .first: 0
                case .last: loadedDetail.pages.count - 1
                }
            } else {
                startPage = initialPage
            }
            position.prepare(page: startPage, pageCount: loadedDetail.pages.count)
            detail = loadedDetail
        } catch is CancellationError {
            return
        } catch {
            detailError = error.localizedDescription
        }
    }

    /// A download job may have been created from an early preview batch, so
    /// its descriptor list can be shorter than the detail page currently
    /// showing. Keep local pages as the source of truth and fetch only enough
    /// remote preview batches to resolve the requested page.
    private func readerDetail(for job: DownloadJob) async throws -> GalleryDetail {
        let localDetail = await model.localGalleryDetail(for: key, job: job)
            ?? Self.downloadedDetail(for: job, site: model.site)
        guard localDetail.pages.contains(where: { $0.index == initialPage }) == false else {
            return localDetail
        }

        var mergedDetail = localDetail
        do {
            for try await liveDetail in model.detailStream(for: key) {
                mergedDetail = Self.mergingPages(from: liveDetail, with: mergedDetail)
                if mergedDetail.pages.contains(where: { $0.index == initialPage }) {
                    break
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // The local detail is still usable for completed pages.
        }
        return mergedDetail
    }

    private static func mergingPages(from liveDetail: GalleryDetail, with localDetail: GalleryDetail) -> GalleryDetail {
        var pagesByIndex = Dictionary(uniqueKeysWithValues: localDetail.pages.map { ($0.index, $0) })
        for page in liveDetail.pages where pagesByIndex[page.index] == nil {
            pagesByIndex[page.index] = page
        }
        return GalleryDetail(
            summary: liveDetail.summary,
            pages: pagesByIndex.values.sorted { $0.index < $1.index },
            tags: liveDetail.tags.isEmpty ? localDetail.tags : liveDetail.tags,
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

    private func scheduleProgressSave() {
        progressSaveTask?.cancel()
        let page = position.page
        progressSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard Task.isCancelled == false else { return }
            await model.updateProgress(for: key, page: page)
        }
    }

    private func saveProgressImmediately() {
        progressSaveTask?.cancel()
        progressSaveTask = nil
        let page = position.page
        Task { await model.updateProgress(for: key, page: page) }
    }

    private func applyReaderSystemSettings() {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
        let orientationMask: UIInterfaceOrientationMask = switch model.readingSettings.screenRotation {
        case .automatic: .all
        case .portrait: .portrait
        case .landscape: .landscape
        }
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState != .unattached }) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientationMask))
        }
        #endif
    }

    #if os(iOS)
    private func updateVolumeMonitor() {
        if model.readingSettings.volumePage {
            volumeMonitor.start()
        } else {
            volumeMonitor.stop()
        }
    }
    #endif

#if os(iOS)
    private func restoreReaderSystemSettings() {
        UIApplication.shared.isIdleTimerDisabled = false
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState != .unattached }) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .all))
        }
    }
#endif

    private func requestPage(_ page: Int, pageCount: Int, animated: Bool = true) {
        resetZoom()
        position.requestPage(page, pageCount: pageCount, animated: animated)
    }

    private func horizontalPageDelta(forLeftDirection: Bool) -> Int {
        if model.readingSettings.readingDirection == .rightToLeft {
            return forLeftDirection ? 1 : -1
        }
        return forLeftDirection ? -1 : 1
    }

    private func prefetchDescriptors(in pages: [GalleryPageDescriptor], around index: Int) -> [GalleryPageDescriptor] {
        let lowerBound = max(0, index - 3)
        let upperBound = min(pages.count, index + 2)
        guard lowerBound < upperBound else { return [] }
        return Array(pages[lowerBound..<upperBound])
    }

    static func downloadedDetail(for job: DownloadJob, site: SiteMode) -> GalleryDetail {
        let summary = GallerySummary(
            key: job.key,
            title: job.title,
            japaneseTitle: job.japaneseTitle,
            thumbnailURL: job.pages.lazy.compactMap(\.previewURL).first,
            pageCount: job.pages.count,
            tags: job.tags
        )
        let externalURL = URL(string: "https://\(site.host)/g/\(job.key.gid)/\(job.key.token)/")
        return GalleryDetail(summary: summary, pages: job.pages, externalURL: externalURL)
    }
}
