import SwiftUI
import ImageIO
import EHDomain

struct ReaderPage: View {
    @Environment(AppModel.self) private var model
    let descriptor: GalleryPageDescriptor
    let resolution: ImageResolution
    let resetToken: UUID
    let fitsViewport: Bool
    let allowsZoom: Bool
    let parentScrollAxis: Axis
    let pageTurnRequested: (Int) -> Void
    @State private var image: Image?
    @State private var aspectRatio: CGFloat?
    @State private var imagePixelSize: CGSize?
    @State private var zoom = ReaderZoomState()
    @State private var contentSize: CGSize = .zero
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: fitsViewport ? .infinity : nil)
                    .scaleEffect(zoom.scale)
                    .offset(zoom.offset)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .aspectRatio(aspectRatio ?? 0.72, contentMode: .fit)
                    .frame(maxHeight: fitsViewport ? .infinity : nil)
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
        .frame(maxWidth: .infinity, maxHeight: fitsViewport ? .infinity : nil)
        .contentShape(Rectangle())
        .clipped()
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            contentSize = newSize
            updateZoom {
                $0.contentSizeChanged(
                    viewportSize: newSize,
                    fittedContentSize: fittedContentSize(in: newSize)
                )
            }
        }
        .simultaneousGesture(magnificationGesture, including: allowsZoom ? .all : .none)
        .highPriorityGesture(dragGesture, including: capturesParentScroll ? .all : .none)
        .highPriorityGesture(doubleTapGesture, including: allowsZoom ? .all : .none)
        .overlay(alignment: .bottomTrailing) {
            if image != nil, zoom.isZoomed {
                Text("缩放 \(Int(zoom.scale * 100))%")
                    .font(.caption.monospacedDigit())
                    .padding(6)
                    .background(.thinMaterial, in: Capsule())
                    .padding(8)
                    .accessibilityHidden(true)
            }
        }
        .task(id: "\(descriptor.id)-\(resolution.rawValue)") { await loadImage() }
        .onChange(of: aspectRatio) {
            updateZoom {
                $0.contentSizeChanged(
                    viewportSize: contentSize,
                    fittedContentSize: fittedContentSize(in: contentSize)
                )
            }
        }
        .onChange(of: resetToken) { resetZoom() }
        .onDisappear { resetZoom() }
        .accessibilityLabel("第 \(descriptor.index + 1) 页")
        .accessibilityIdentifier("reader-page-\(descriptor.index)")
        .accessibilityHint(allowsZoom ? "双击切换缩放；放大后拖动查看，拖到边缘继续翻页" : "随连续阅读区域一起缩放")
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard image != nil else { return }
                updateZoom {
                    $0.magnificationChanged(
                        value.magnification,
                        viewportSize: contentSize,
                        fittedContentSize: fittedContentSize(in: contentSize),
                        focus: value.startLocation
                    )
                }
            }
            .onEnded { value in
                guard image != nil else { return }
                updateZoom {
                    $0.magnificationEnded(
                        value.magnification,
                        viewportSize: contentSize,
                        fittedContentSize: fittedContentSize(in: contentSize),
                        focus: value.startLocation
                    )
                }
            }
    }

    private var doubleTapGesture: some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                guard image != nil else { return }
                withAnimation(.smooth(duration: 0.3)) {
                    updateZoom {
                        $0.advanceZoom(
                            candidates: defaultZoomScales,
                            viewportSize: contentSize,
                            fittedContentSize: fittedContentSize(in: contentSize),
                            focus: value.location
                        )
                    }
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard zoom.isZoomed else { return }
                updateZoom {
                    $0.dragChanged(
                        value.translation,
                        viewportSize: contentSize,
                        fittedContentSize: fittedContentSize(in: contentSize)
                    )
                }
            }
            .onEnded { value in
                guard zoom.isZoomed else { return }
                let displayDelta = zoom.dragEnded(
                    value.translation,
                    viewportSize: contentSize,
                    fittedContentSize: fittedContentSize(in: contentSize)
                )
                if let displayDelta {
                    resetZoom()
                    pageTurnRequested(displayDelta)
                }
            }
    }

    private func updateZoom(_ change: (inout ReaderZoomState) -> Void) {
        change(&zoom)
    }

    private func resetZoom() {
        zoom.reset()
    }

    private var capturesParentScroll: Bool {
        guard allowsZoom, zoom.isZoomed else { return false }
        let fittedSize = fittedContentSize(in: contentSize)
        switch parentScrollAxis {
        case .horizontal:
            return zoom.canPanHorizontally(viewportSize: contentSize, fittedContentSize: fittedSize)
        case .vertical:
            return zoom.canPanVertically(viewportSize: contentSize, fittedContentSize: fittedSize)
        }
    }

    private var defaultZoomScales: [CGFloat] {
        let fittedSize = fittedContentSize(in: contentSize)
        guard fittedSize.width > 0, fittedSize.height > 0 else { return [1, 2] }
        let fitWidth = contentSize.width / fittedSize.width
        let fitHeight = contentSize.height / fittedSize.height
        let actualSize = imagePixelSize.map {
            max($0.width / fittedSize.width, $0.height / fittedSize.height)
        } ?? 1
        let rawValues = [1, actualSize, fitWidth, fitHeight, max(fitWidth, fitHeight) * 2]
        return rawValues
            .map { min(max($0, ReaderZoomState.minimumScale), ReaderZoomState.maximumScale) }
            .sorted()
            .reduce(into: [CGFloat]()) { values, value in
                if values.last.map({ abs($0 - value) > 0.01 }) ?? true {
                    values.append(value)
                }
            }
    }

    private func fittedContentSize(in viewportSize: CGSize) -> CGSize {
        guard viewportSize.width > 0, viewportSize.height > 0,
              let aspectRatio, aspectRatio.isFinite, aspectRatio > 0 else { return viewportSize }
        let viewportAspectRatio = viewportSize.width / viewportSize.height
        if aspectRatio > viewportAspectRatio {
            return CGSize(width: viewportSize.width, height: viewportSize.width / aspectRatio)
        }
        return CGSize(width: viewportSize.height * aspectRatio, height: viewportSize.height)
    }

    private func loadImage() async {
        failed = false
        do {
            let metadata = try await model.pageImage(for: descriptor)
            if let width = metadata.width, let height = metadata.height, height > 0 {
                aspectRatio = CGFloat(width) / CGFloat(height)
                imagePixelSize = CGSize(width: CGFloat(width), height: CGFloat(height))
            }
            let data = try await model.imageData(for: metadata, resolution: resolution)
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 2_400
                  ] as CFDictionary) else {
                throw EHError.parsingFailed("图片数据无效")
            }
            if aspectRatio == nil, cgImage.height > 0 {
                aspectRatio = CGFloat(cgImage.width) / CGFloat(cgImage.height)
            }
            if imagePixelSize == nil {
                imagePixelSize = CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
            }
            image = Image(decorative: cgImage, scale: 1, orientation: .up)
            failed = false
        } catch is CancellationError {
            return
        } catch {
            failed = true
        }
    }
}
