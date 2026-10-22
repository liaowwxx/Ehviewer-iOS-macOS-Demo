#if os(macOS)
import ImageIO
import SwiftUI

struct TranslationPagePreview: View {
    let url: URL?
    let pageIndex: Int?
    @State private var image: CGImage?
    @State private var loading = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("最新译图", systemImage: "photo")
                Spacer()
                if let pageIndex { Text("第 \(pageIndex + 1) 页").foregroundStyle(.secondary) }
            }
            .font(.headline).padding()
            Divider()
            GeometryReader { geometry in
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable().scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .accessibilityLabel("第 \((pageIndex ?? 0) + 1) 页译图")
                } else if loading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(url == nil ? "等待首张译图" : "暂时无法显示译图", systemImage: "photo",
                                           description: Text(url == nil ? "页面处理完成后会显示在这里。" : "可在诊断目录中查看结果文件。"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(12)
            .background(.black.opacity(0.12))
        }
        .task(id: url) {
            image = nil
            loading = false
            guard let url else { return }
            loading = true
            let loaded = await Self.thumbnail(url)
            guard !Task.isCancelled else { return }
            image = loaded
            loading = false
        }
    }

    @concurrent private static func thumbnail(_ url: URL) async -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1800,
            kCGImageSourceCreateThumbnailWithTransform: true
        ] as CFDictionary)
    }
}
#endif
