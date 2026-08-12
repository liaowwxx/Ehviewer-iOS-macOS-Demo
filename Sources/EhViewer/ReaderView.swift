import SwiftUI
import EHDomain

struct ReaderView: View {
    @Environment(AppModel.self) private var model
    let key: GalleryKey
    let initialPage: Int
    @State private var detail: GalleryDetail?
    @State private var position: ReaderPositionState
    @AppStorage("readerReadingMode") private var readingMode: ReadingMode = .rightToLeft
    @State private var resolution: ImageResolution = .preview
    @State private var showingJumpSheet = false
    @State private var jumpText = ""
    @State private var isFullscreen = false
    @State private var zoomResetToken = UUID()

    init(key: GalleryKey, initialPage: Int) {
        self.key = key
        self.initialPage = initialPage
        _position = State(initialValue: ReaderPositionState(page: initialPage))
    }

    var body: some View {
        Group {
            if let detail {
                if readingMode == .continuous {
                    ReaderContinuousView(
                        descriptors: detail.pages,
                        resolution: resolution,
                        resetToken: zoomResetToken,
                        position: $position
                    )
                } else {
                    ReaderPagedView(
                        descriptors: detail.pages,
                        resolution: resolution,
                        resetToken: zoomResetToken,
                        readingMode: readingMode,
                        position: $position
                    )
                }
            } else {
                ProgressView("准备阅读器…")
            }
        }
        .task(id: position.page) {
            guard let detail else { return }
            await model.prefetch(
                prefetchDescriptors(in: detail.pages, around: position.page),
                resolution: resolution
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
        .navigationTitle("阅读 · \(position.page + 1)")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("阅读选项", systemImage: "ellipsis.circle") {
                    Picker("阅读方向", selection: $readingMode) {
                        ForEach(ReadingMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    Picker("图片清晰度", selection: $resolution) {
                        Text("预览图").tag(ImageResolution.preview)
                        Text("原图").tag(ImageResolution.original)
                    }
                    Button("保存当前页", systemImage: "bookmark") {
                        Task { await model.updateProgress(for: key, page: position.page) }
                    }
                    Button("保存图片", systemImage: "square.and.arrow.down") {
                        if let descriptor = detail?.pages.first(where: { $0.index == position.page }) {
                            Task { await model.savePage(descriptor, resolution: resolution) }
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
        .task(id: key) {
            guard let loadedDetail = await model.detail(for: key), Task.isCancelled == false else { return }
            let savedPage = await model.readingPage(for: key)
            guard Task.isCancelled == false else { return }
            position.prepare(page: savedPage ?? initialPage, pageCount: loadedDetail.pages.count)
            detail = loadedDetail
        }
        .onChange(of: readingMode) {
            resetZoom()
            if let detail {
                position.requestPage(position.page, pageCount: detail.pages.count)
            }
        }
        .onChange(of: resolution) { resetZoom() }
        .onDisappear { Task { await model.updateProgress(for: key, page: position.page) } }
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
    }

    private func resetZoom() {
        zoomResetToken = UUID()
    }

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
}
