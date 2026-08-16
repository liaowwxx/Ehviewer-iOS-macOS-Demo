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
    @State private var source: ReaderContentSource
    @State private var detail: GalleryDetail?
    @State private var position: ReaderPositionState
    /// 视频播放器式控件显隐：点击页面切换，无操作一段时间后自动隐藏。
    @State private var isShowingControls = true
    @State private var controlsInteractionToken = UUID()
    @State private var zoomResetToken = UUID()
    @State private var detailError: String?
    @State private var detailLoadToken = UUID()
    @State private var progressSaveTask: Task<Void, Never>?
    #if os(iOS)
    @State private var volumeMonitor = VolumeButtonMonitor()
    #endif

    private var readingMode: ReadingMode { model.readingSettings.readingMode }

    init(key: GalleryKey, initialPage: Int) {
        self.key = key
        self.initialPage = initialPage
        downloadedJob = nil
        _source = State(initialValue: .remote)
        _position = State(initialValue: ReaderPositionState(page: initialPage))
    }

    init(downloaded job: DownloadJob, initialPage: Int) {
        key = job.key
        self.initialPage = initialPage
        downloadedJob = job
        _source = State(initialValue: .download)
        _position = State(initialValue: ReaderPositionState(page: initialPage))
    }

    var body: some View {
        readerContent
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
        .task(id: controlsInteractionToken) {
            guard isShowingControls else { return }
            try? await Task.sleep(for: .seconds(4))
            guard Task.isCancelled == false else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                isShowingControls = false
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
        .onChange(of: position.page) { _, _ in
            scheduleProgressSave()
            // 翻页/拖动进度条视为交互：仅在控件已显示时重置自动隐藏计时。
            controlsInteractionToken = UUID()
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
        .onChange(of: model.readingSettings.keepScreenOn) { _, _ in
            applyReaderSystemSettings()
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
        .toolbar(isShowingControls ? .visible : .hidden)
        #endif
        .overlay(alignment: .topLeading) {
            if isShowingControls, let detail, showsStatusOverlay {
                ReaderStatusOverlay(
                    settings: model.readingSettings,
                    page: position.page,
                    pageCount: detail.pages.count
                )
                .padding()
                .transition(.opacity)
            }
        }
    }

    private var showsStatusOverlay: Bool {
        model.readingSettings.showClock || model.readingSettings.showProgress || model.readingSettings.showBattery || model.readingSettings.showPageInterval
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
                        pageScaling: model.readingSettings.pageScaling,
                        source: source,
                        position: $position
                    )
                    .onTapGesture(perform: toggleControls)
                } else {
                    ReaderPagedView(
                        descriptors: detail.pages,
                        resolution: .preview,
                        resetToken: zoomResetToken,
                        readingDirection: model.readingSettings.readingDirection,
                        pageScaling: model.readingSettings.pageScaling,
                        source: source,
                        position: $position
                    )
                    .onTapGesture(perform: toggleControls)
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
        controlsInteractionToken = UUID()
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
                loadedDetail = Self.downloadedDetail(for: localJob, site: model.site)
            } else {
                source = .remote
                loadedDetail = try await model.detail(for: key)
            }
            guard Task.isCancelled == false else { return }
            let savedPage = await model.readingPage(for: key)
            guard Task.isCancelled == false else { return }
            let startPage: Int = switch model.readingSettings.startPosition {
            case .lastRead: savedPage ?? initialPage
            case .first: 0
            case .last: loadedDetail.pages.count - 1
            }
            position.prepare(page: startPage, pageCount: loadedDetail.pages.count)
            detail = loadedDetail
        } catch is CancellationError {
            return
        } catch {
            detailError = error.localizedDescription
        }
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
        UIApplication.shared.isIdleTimerDisabled = model.readingSettings.keepScreenOn
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
            pageCount: job.pages.count
        )
        let externalURL = URL(string: "https://\(site.host)/g/\(job.key.gid)/\(job.key.token)/")
        return GalleryDetail(summary: summary, pages: job.pages, externalURL: externalURL)
    }
}

private struct ReaderStatusOverlay: View {
    let settings: ReadingSettings
    let page: Int
    let pageCount: Int

    var body: some View {
        Group {
            if settings.showClock {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    statusContent(date: context.date)
                }
            } else {
                statusContent(date: nil)
            }
        }
        #if os(iOS)
        .onAppear { UIDevice.current.isBatteryMonitoringEnabled = true }
        .onDisappear { UIDevice.current.isBatteryMonitoringEnabled = false }
        #endif
    }

    private func statusContent(date: Date?) -> some View {
        HStack(spacing: 8) {
            if let date {
                Text(date, style: .time)
            }
            if settings.showProgress {
                Text("\(progressPercent)%")
            }
            if settings.showPageInterval {
                Text("\(page + 1)/\(pageCount)")
            }
            #if os(iOS)
            if settings.showBattery {
                Text(batteryText)
            }
            #endif
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
    }

    private var progressPercent: Int {
        guard pageCount > 0 else { return 0 }
        return Int((Double(page + 1) / Double(pageCount) * 100).rounded())
    }

    #if os(iOS)
    private var batteryText: String {
        let level = UIDevice.current.batteryLevel
        guard level >= 0 else { return String(localized: "电量 --") }
        return String(localized: "电量 \(Int((level * 100).rounded()))%")
    }
    #endif
}
