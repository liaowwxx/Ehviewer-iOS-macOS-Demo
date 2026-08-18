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

struct ReaderPage: View {
    @Environment(AppModel.self) private var model
    let descriptor: GalleryPageDescriptor
    let resolution: ImageResolution
    let source: ReaderContentSource
    let fitsViewport: Bool
    @State private var media: ReaderMediaView.Content?
    @State private var aspectRatio: CGFloat?
    @State private var failed = false
    @State private var loadToken = UUID()
    @State private var loadErrorMessage: String?
    @State private var isSaving = false
    @State private var showingSaveConfirmation = false
    @State private var showingSaveError = false
    @State private var saveErrorMessage: String?
#if os(macOS)
    @State private var zoomScale: CGFloat = 1
    @GestureState private var pinchScale: CGFloat = 1
#endif

    var body: some View {
        Group {
            if let media {
#if os(macOS)
                ReaderMediaView(content: media, fitsViewport: fitsViewport)
                    .scaleEffect(min(max(zoomScale * pinchScale, 1), 4))
                    .gesture(
                        MagnificationGesture()
                            .updating($pinchScale) { value, state, _ in
                                state = value
                            }
                            .onEnded { value in
                                zoomScale = min(max(zoomScale * value, 1), 4)
                            }
                    )
                    .transition(.opacity)
#else
                ReaderMediaView(content: media, fitsViewport: fitsViewport)
                    .transition(.opacity)
#endif
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
            Button("保存媒体", systemImage: "square.and.arrow.down", action: saveMedia)
                .disabled(media == nil || isSaving)
        }
        .task(id: "\(descriptor.id)-\(resolution.rawValue)-\(source)-\(loadToken)") {
            await loadImage()
        }
        .alert("媒体已保存", isPresented: $showingSaveConfirmation) {
            Button("好", role: .cancel) {}
        } message: {
#if os(iOS)
            Text("媒体已保存到系统照片。")
#else
            Text("媒体已保存到系统下载文件夹。")
#endif
        }
        .alert("无法保存媒体", isPresented: $showingSaveError) {
            Button("好", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? String(localized: "请稍后重试。"))
        }
        .accessibilityLabel("第 \(descriptor.index + 1) 页")
        .accessibilityIdentifier("reader-page-\(descriptor.index)")
        .accessibilityHint("长按媒体可保存；缩放和移动由系统滚动容器处理")
    }

    private func saveMedia() {
        guard media != nil, isSaving == false else { return }
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
        media = nil
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
                if let localData = await model.downloadedPageDataIfAvailable(for: descriptor) {
                    data = localData
                } else {
                    let metadata = try await model.pageImage(for: descriptor)
                    if let width = metadata.width, let height = metadata.height, height > 0 {
                        aspectRatio = CGFloat(width) / CGFloat(height)
                    }
                    data = try await model.imageData(for: metadata, resolution: resolution)
                }
            }
            try Task.checkCancellation()
            let decodedMedia = try ReaderMediaView.Content.decode(data)
            aspectRatio = decodedMedia.aspectRatio
            withAnimation(.easeOut(duration: 0.25)) {
                media = decodedMedia
                failed = false
            }
        } catch is CancellationError {
            return
        } catch {
            loadErrorMessage = error.localizedDescription
            failed = true
        }
    }
}
