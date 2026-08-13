import SwiftUI
import EHDomain
import EHDownloads

enum ReaderContentSource: Hashable, Sendable {
    case remote
    case download
}

struct ReaderView: View {
    @Environment(AppModel.self) private var model
    let key: GalleryKey
    let initialPage: Int
    private let source: ReaderContentSource
    private let downloadedJob: DownloadJob?
    @State private var detail: GalleryDetail?
    @State private var position: ReaderPositionState
    @State private var resolution: ImageResolution = .preview
    @State private var showingJumpSheet = false
    @State private var jumpText = ""
    @State private var isFullscreen = false
    @State private var zoomResetToken = UUID()
    @State private var showingSaveConfirmation = false
    #if os(iOS)
    @State private var originalBrightness: CGFloat?
    @State private var volumeMonitor = VolumeButtonMonitor()
    #endif

    private var readingMode: ReadingMode { model.readingSettings.readingMode }

    init(key: GalleryKey, initialPage: Int) {
        self.key = key
        self.initialPage = initialPage
        source = .remote
        downloadedJob = nil
        _position = State(initialValue: ReaderPositionState(page: initialPage))
    }

    init(downloaded job: DownloadJob, initialPage: Int) {
        key = job.key
        self.initialPage = initialPage
        source = .download
        downloadedJob = job
        _position = State(initialValue: ReaderPositionState(page: initialPage))
    }

    var body: some View {
        @Bindable var model = model
        Group {
            if let detail {
                if readingMode == .continuous {
                    ReaderContinuousView(
                        descriptors: detail.pages,
                        resolution: resolution,
                        resetToken: zoomResetToken,
                        pageScaling: model.readingSettings.pageScaling,
                        source: source,
                        position: $position
                    )
                } else {
                    ReaderPagedView(
                        descriptors: detail.pages,
                        resolution: resolution,
                        resetToken: zoomResetToken,
                        readingMode: readingMode,
                        pageScaling: model.readingSettings.pageScaling,
                        source: source,
                        position: $position
                    )
                }
            } else {
                ProgressView("准备阅读器…")
            }
        }
        .task(id: position.page) {
            guard source == .remote, let detail else { return }
            await model.prefetch(
                prefetchDescriptors(in: detail.pages, around: position.page),
                resolution: resolution
            )
        }
        .task(id: model.readingSettings.autoAdvanceSeconds) {
            let seconds = model.readingSettings.autoAdvanceSeconds
            guard seconds > 0 else { return }
            while Task.isCancelled == false {
                do {
                    try await Task.sleep(for: .seconds(seconds))
                } catch {
                    return
                }
                guard Task.isCancelled == false, let detail, position.page < detail.pages.count - 1 else { return }
                requestPage(position.page + 1, pageCount: detail.pages.count)
            }
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
        .navigationTitle("阅读 · \(position.page + 1)")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("阅读选项", systemImage: "ellipsis.circle") {
                    Picker("阅读方向", selection: $model.readingSettings.readingMode) {
                        ForEach(ReadingMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    Picker("图片清晰度", selection: $resolution) {
                        Text("预览图").tag(ImageResolution.preview)
                        Text("原图").tag(ImageResolution.original)
                    }
                    .disabled(source == .download)
                    Button("保存当前页", systemImage: "bookmark") {
                        Task { await model.updateProgress(for: key, page: position.page) }
                    }
                    Button("保存图片", systemImage: "square.and.arrow.down") {
                        if let descriptor = detail?.pages.first(where: { $0.index == position.page }) {
                            Task {
                                showingSaveConfirmation = await model.savePage(descriptor, resolution: resolution)
                            }
                        }
                    }
                    Button("跳转到页面", systemImage: "arrow.right.to.line") {
                        jumpText = String(position.page + 1)
                        showingJumpSheet = true
                    }
                    Button(isFullscreen ? "退出全屏" : "全屏", systemImage: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
                        isFullscreen.toggle()
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if let externalURL = detail?.externalURL {
                    ShareLink(item: externalURL) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .task(id: "\(key.id)-\(source)") {
            let loadedDetail: GalleryDetail?
            if let downloadedJob {
                loadedDetail = Self.downloadedDetail(for: downloadedJob, site: model.site)
            } else {
                loadedDetail = await model.detail(for: key)
            }
            guard let loadedDetail, Task.isCancelled == false else { return }
            let savedPage = await model.readingPage(for: key)
            guard Task.isCancelled == false else { return }
            let startPage: Int = switch model.readingSettings.startPosition {
            case .lastRead: savedPage ?? initialPage
            case .first: 0
            case .last: loadedDetail.pages.count - 1
            }
            position.prepare(page: startPage, pageCount: loadedDetail.pages.count)
            isFullscreen = model.readingSettings.fullscreen
            detail = loadedDetail
        }
        .onChange(of: model.readingSettings.readingMode) {
            model.persistReadingSettings()
            resetZoom()
            if let detail {
                position.requestPage(position.page, pageCount: detail.pages.count)
            }
        }
        .onChange(of: model.readingSettings) { _, _ in
            model.persistReadingSettings()
        }
        .onChange(of: resolution) { resetZoom() }
        .onDisappear { Task { await model.updateProgress(for: key, page: position.page) } }
        .onAppear {
            applyReaderSystemSettings()
            #if os(iOS)
            updateVolumeMonitor()
            #endif
        }
        .onChange(of: model.readingSettings.keepScreenOn) { _, _ in
            applyReaderSystemSettings()
        }
        .onChange(of: model.readingSettings.customBrightness) { _, _ in
            applyReaderSystemSettings()
        }
        .onChange(of: model.readingSettings.brightness) { _, _ in
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
        .toolbar(isFullscreen ? .hidden : .visible, for: .navigationBar)
        #elseif os(macOS)
        .toolbar(isFullscreen ? .hidden : .visible)
        #endif
        .overlay(alignment: .topTrailing) {
            if isFullscreen {
                Button("退出全屏", systemImage: "xmark.circle.fill") { isFullscreen = false }
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .padding()
                    .accessibilityLabel("退出全屏")
            }
        }
        .overlay(alignment: .topLeading) {
            if let detail, model.readingSettings.showClock || model.readingSettings.showProgress || model.readingSettings.showBattery || model.readingSettings.showPageInterval {
                ReaderStatusOverlay(
                    settings: model.readingSettings,
                    page: position.page,
                    pageCount: detail.pages.count
                )
                .padding()
            }
        }
        .sheet(isPresented: $showingJumpSheet) {
            NavigationStack {
                Form {
                    TextField("页码", text: $jumpText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    Button("跳转") {
                        if let requested = Int(jumpText), let count = detail?.pages.count {
                            requestPage(requested - 1, pageCount: count)
                            showingJumpSheet = false
                        }
                    }
                }
                .navigationTitle("跳转")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showingJumpSheet = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .alert("图片已保存", isPresented: $showingSaveConfirmation) {
            Button("好", role: .cancel) {}
        } message: {
            Text("图片已保存到系统照片。")
        }
    }

    private func resetZoom() {
        zoomResetToken = UUID()
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
            let screen = scene.screen
            if model.readingSettings.customBrightness {
                if originalBrightness == nil {
                    originalBrightness = screen.brightness
                }
                screen.brightness = model.readingSettings.brightness
            } else if let originalBrightness {
                screen.brightness = originalBrightness
                self.originalBrightness = nil
            }
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
        if let originalBrightness,
           let screen = UIApplication.shared.connectedScenes
               .compactMap({ ($0 as? UIWindowScene)?.screen })
               .first {
            screen.brightness = originalBrightness
            self.originalBrightness = nil
        }
    }
    #endif

    private func requestPage(_ page: Int, pageCount: Int) {
        resetZoom()
        position.requestPage(page, pageCount: pageCount)
    }

    private func horizontalPageDelta(forLeftDirection: Bool) -> Int {
        if readingMode == .rightToLeft {
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
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 8) {
                if settings.showClock {
                    Text(context.date, style: .time)
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
        #if os(iOS)
        .onAppear { UIDevice.current.isBatteryMonitoringEnabled = true }
        .onDisappear { UIDevice.current.isBatteryMonitoringEnabled = false }
        #endif
    }

    private var progressPercent: Int {
        guard pageCount > 0 else { return 0 }
        return Int((Double(page + 1) / Double(pageCount) * 100).rounded())
    }

    #if os(iOS)
    private var batteryText: String {
        let level = UIDevice.current.batteryLevel
        guard level >= 0 else { return "电量 --" }
        return "电量 \(Int((level * 100).rounded()))%"
    }
    #endif
}
