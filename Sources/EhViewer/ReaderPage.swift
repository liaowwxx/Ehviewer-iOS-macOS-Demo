import SwiftUI
import ImageIO
import EHDomain

struct ReaderPage: View {
    @Environment(AppModel.self) private var model
    let descriptor: GalleryPageDescriptor
    let resolution: ImageResolution
    let source: ReaderContentSource
    let pageScaling: ReaderPageScaling
    let fitsViewport: Bool
    @State private var image: Image?
    @State private var aspectRatio: CGFloat?
    @State private var failed = false
    @State private var loadToken = UUID()
    @State private var loadErrorMessage: String?
    @State private var isSaving = false
    @State private var showingSaveConfirmation = false
    @State private var showingSaveError = false
    @State private var saveErrorMessage: String?

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .aspectRatio(aspectRatio, contentMode: pageScaling == .original ? .fill : .fit)
                    .frame(
                        maxWidth: pageScaling == .original || pageScaling == .height ? nil : .infinity,
                        maxHeight: fitsViewport || pageScaling == .height ? .infinity : nil
                    )
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .aspectRatio(aspectRatio ?? 0.72, contentMode: .fit)
                    .frame(maxHeight: fitsViewport || pageScaling == .height ? .infinity : nil)
                    .overlay {
                        VStack(spacing: 8) {
                            if failed {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.largeTitle)
                                Text("页面加载失败")
                                    .font(.headline)
                                if let loadErrorMessage {
                                    Text(loadErrorMessage)
                                        .font(.caption)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(3)
                                }
                                Button("重试", systemImage: "arrow.clockwise") {
                                    loadToken = UUID()
                                }
                                .buttonStyle(.bordered)
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
        .contextMenu {
            Button("保存图片", systemImage: "square.and.arrow.down", action: saveImage)
                .disabled(image == nil || isSaving)
        }
        .task(id: "\(descriptor.id)-\(resolution.rawValue)-\(source)-\(pageScaling.rawValue)-\(loadToken)") {
            await loadImage()
        }
        .alert("图片已保存", isPresented: $showingSaveConfirmation) {
            Button("好", role: .cancel) {}
        } message: {
#if os(iOS)
            Text("图片已保存到系统照片。")
#else
            Text("图片已保存到系统下载文件夹。")
#endif
        }
        .alert("无法保存图片", isPresented: $showingSaveError) {
            Button("好", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "请稍后重试。")
        }
        .accessibilityLabel("第 \(descriptor.index + 1) 页")
        .accessibilityIdentifier("reader-page-\(descriptor.index)")
        .accessibilityHint("长按图片可保存；缩放和移动由系统滚动容器处理")
    }

    private func saveImage() {
        guard image != nil, isSaving == false else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await model.savePage(descriptor, resolution: resolution)
                showingSaveConfirmation = true
            } catch is CancellationError {
                return
            } catch {
                saveErrorMessage = error.localizedDescription
                showingSaveError = true
            }
        }
    }

    private func loadImage() async {
        failed = false
        loadErrorMessage = nil
        do {
            let data: Data
            switch source {
            case .remote:
                let metadata = try await model.pageImage(for: descriptor)
                if let width = metadata.width, let height = metadata.height, height > 0 {
                    aspectRatio = CGFloat(width) / CGFloat(height)
                }
                data = try await model.imageData(for: metadata, resolution: resolution)
            case .download:
                data = try await model.downloadedPageData(for: descriptor, resolution: resolution)
            }
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
            image = Image(decorative: cgImage, scale: 1, orientation: .up)
            failed = false
        } catch is CancellationError {
            return
        } catch {
            loadErrorMessage = error.localizedDescription
            failed = true
        }
    }
}
