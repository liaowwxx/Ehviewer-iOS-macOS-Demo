import SwiftUI
import ImageIO
import EHDomain

struct ReaderView: View {
    @Environment(AppModel.self) private var model
    let key: GalleryKey
    let initialPage: Int
    @State private var detail: GalleryDetail?
    @State private var page = 0
    @State private var readingMode: ReadingMode = .continuous
    @State private var resolution: ImageResolution = .preview
    @State private var showingJumpSheet = false
    @State private var jumpText = ""
    @State private var isFullscreen = false

    var body: some View {
        Group {
            if let detail {
                ScrollViewReader { proxy in
                    ScrollView(readingMode == .continuous ? .vertical : .horizontal) {
                        if readingMode == .continuous {
                            LazyVStack(spacing: 10) {
                                readerPages(detail.pages)
                            }
                            .padding(.horizontal)
                        } else {
                            LazyHStack(spacing: 10) {
                                readerPages(detail.pages)
                            }
                            .padding(.vertical)
                        }
                    }
                    .task {
                        page = min(max(initialPage, 0), max(detail.pages.count - 1, 0))
                        proxy.scrollTo(page, anchor: .top)
                        await model.prefetch(prefetchDescriptors(in: detail.pages, around: page), resolution: resolution)
                    }
                    .onChange(of: page) { _, newPage in
                        withAnimation { proxy.scrollTo(newPage, anchor: .top) }
                    }
                    .onKeyPress(.leftArrow) {
                        page = max(page - 1, 0)
                        return .handled
                    }
                    .onKeyPress(.rightArrow) {
                        page = min(page + 1, max(detail.pages.count - 1, 0))
                        return .handled
                    }
                }
            } else {
                ProgressView("准备阅读器…")
            }
        }
        .navigationTitle("阅读 · \(page + 1)")
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
                        Task { await model.updateProgress(for: key, page: page) }
                    }
                    Button("保存图片", systemImage: "square.and.arrow.down") {
                        if let descriptor = detail?.pages.first(where: { $0.index == page }) {
                            Task { await model.savePage(descriptor, resolution: resolution) }
                        }
                    }
                    Button("跳转到页面", systemImage: "arrow.right.to.line") {
                        jumpText = String(page + 1)
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
            detail = await model.detail(for: key)
            page = await model.readingPage(for: key) ?? initialPage
        }
        .onDisappear { Task { await model.updateProgress(for: key, page: page) } }
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
                            page = min(max(requested - 1, 0), max(count - 1, 0))
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

    @ViewBuilder
    private func readerPages(_ descriptors: [GalleryPageDescriptor]) -> some View {
        let displayDescriptors = readingMode == .rightToLeft ? Array(descriptors.reversed()) : descriptors
        ForEach(displayDescriptors) { descriptor in
            ReaderPage(descriptor: descriptor, resolution: resolution)
                .id(descriptor.index)
                .onAppear {
                    if descriptor.index > page { page = descriptor.index }
                }
        }
    }

    private func prefetchDescriptors(in pages: [GalleryPageDescriptor], around index: Int) -> [GalleryPageDescriptor] {
        let lowerBound = max(0, index - 3)
        let upperBound = min(pages.count, index + 2)
        guard lowerBound < upperBound else { return [] }
        return Array(pages[lowerBound..<upperBound])
    }
}

private enum ReadingMode: String, CaseIterable, Identifiable {
    case continuous
    case leftToRight
    case rightToLeft

    var id: Self { self }
    var title: String {
        switch self {
        case .continuous: "纵向连续"
        case .leftToRight: "从左到右"
        case .rightToLeft: "从右到左"
        }
    }
}

private struct ReaderPage: View {
    @Environment(AppModel.self) private var model
    let descriptor: GalleryPageDescriptor
    let resolution: ImageResolution
    @State private var image: Image?
    @State private var aspectRatio: CGFloat?
    @State private var scale: CGFloat = 1
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 1_200)
                    .scaleEffect(scale)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                scale = min(max(value.magnification, 1), 4)
                            }
                            .onEnded { _ in
                                if scale < 1.05 { scale = 1 }
                            }
                    )
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .aspectRatio(aspectRatio ?? 0.72, contentMode: .fit)
                    .overlay {
                        VStack(spacing: 8) {
                            if failed {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.largeTitle)
                                Text("页面加载失败")
                                    .font(.headline)
                            } else {
                                ProgressView()
                                Text("正在加载第 \(descriptor.index + 1) 页…")
                                    .font(.headline)
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .overlay(alignment: .bottomTrailing) {
            if image != nil, scale > 1 {
                Text("缩放 \(Int(scale * 100))%")
                    .font(.caption2.monospacedDigit())
                    .padding(6)
                    .background(.thinMaterial, in: Capsule())
                    .padding(8)
            }
        }
        .task(id: "\(descriptor.id)-\(resolution.rawValue)") {
            do {
                let metadata = try await model.pageImage(for: descriptor)
                if let width = metadata.width, let height = metadata.height, height > 0 {
                    aspectRatio = CGFloat(width) / CGFloat(height)
                }
                let data = try await model.imageData(for: metadata, resolution: resolution)
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                          kCGImageSourceCreateThumbnailFromImageAlways: true,
                          kCGImageSourceCreateThumbnailWithTransform: true,
                          kCGImageSourceThumbnailMaxPixelSize: 2_400
                      ] as CFDictionary) else {
                    throw EHError.parsingFailed("图片数据无效")
                }
                image = Image(decorative: cgImage, scale: 1, orientation: .up)
                failed = false
            } catch is CancellationError {
                return
            } catch {
                failed = true
            }
        }
        .accessibilityLabel("第 \(descriptor.index + 1) 页")
    }
}
