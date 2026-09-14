/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

#if os(macOS)
import SwiftUI
import EHDomain

struct ReaderSpreadView: View {
    @Environment(AppModel.self) private var model
    let spread: ReaderSpread
    let resolution: ImageResolution
    let source: ReaderContentSource
    let resetToken: UUID

    @State private var leftMedia: ReaderMediaView.Content?
    @State private var rightMedia: ReaderMediaView.Content?
    @State private var leftAspectRatio: CGFloat?
    @State private var rightAspectRatio: CGFloat?
    @State private var leftFailed = false
    @State private var rightFailed = false
    @State private var leftErrorMessage: String?
    @State private var rightErrorMessage: String?
    @State private var leftLoadToken = UUID()
    @State private var rightLoadToken = UUID()
    @State private var isSaving = false
    @State private var showingSaveConfirmation = false
    @State private var showingSaveError = false
    @State private var saveErrorMessage: String?

    private static let placeholderAspectRatio: CGFloat = 0.72

    var body: some View {
        MacReaderSpreadMediaScrollView(
            leftAspectRatio: leftAspectRatio ?? Self.placeholderAspectRatio,
            rightAspectRatio: rightAspectRatio ?? Self.placeholderAspectRatio,
            resetToken: resetToken
        ) {
            MacReaderSpreadCanvas(
                leftAspectRatio: leftAspectRatio ?? Self.placeholderAspectRatio,
                rightAspectRatio: rightAspectRatio ?? Self.placeholderAspectRatio,
                left: { leftSide },
                right: { rightSide }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: leftTaskID) {
            await loadLeftPage()
        }
        .task(id: rightTaskID) {
            await loadRightPage()
        }
        .alert("媒体已保存", isPresented: $showingSaveConfirmation) {
            Button("好", role: .cancel) {}
        } message: {
            Text("媒体已保存到系统下载文件夹。")
        }
        .alert("无法保存媒体", isPresented: $showingSaveError) {
            Button("好", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? String(localized: "请稍后重试。"))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(spreadAccessibilityLabel)
    }

    private var leftTaskID: String {
        "\(spread.id)-left-\(spread.leftPage?.id ?? "blank")-\(resolution.rawValue)-\(source)"
    }

    private var rightTaskID: String {
        "\(spread.id)-right-\(spread.rightPage?.id ?? "blank")-\(resolution.rawValue)-\(source)"
    }

    private var spreadAccessibilityLabel: String {
        let indexes = spread.pageIndexes.map { String($0 + 1) }.joined(separator: "、")
        return String(localized: "第 \(indexes) 页双页阅读单元")
    }

    @ViewBuilder
    private var leftSide: some View {
        sideView(
            descriptor: spread.leftPage,
            media: leftMedia,
            failed: leftFailed,
            errorMessage: leftErrorMessage,
            retry: { leftLoadToken = UUID() }
        )
    }

    @ViewBuilder
    private var rightSide: some View {
        sideView(
            descriptor: spread.rightPage,
            media: rightMedia,
            failed: rightFailed,
            errorMessage: rightErrorMessage,
            retry: { rightLoadToken = UUID() }
        )
    }

    @ViewBuilder
    private func sideView(
        descriptor: GalleryPageDescriptor?,
        media: ReaderMediaView.Content?,
        failed: Bool,
        errorMessage: String?,
        retry: @escaping () -> Void
    ) -> some View {
        if let descriptor {
            Group {
                if let media {
                    ReaderMediaView(content: media, fitsViewport: true)
                        .transition(.opacity)
                } else if failed {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                        Text("页面加载失败")
                            .font(.headline)
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                        }
                        Button("重试", systemImage: "arrow.clockwise", action: retry)
                            .buttonStyle(.bordered)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    .padding(8)
                } else {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("正在加载第 \(descriptor.index + 1) 页…")
                            .font(.headline)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .contextMenu {
                Button("保存媒体", systemImage: "square.and.arrow.down") {
                    saveMedia(descriptor)
                }
                .disabled(media == nil || isSaving)
            }
            .accessibilityLabel("第 \(descriptor.index + 1) 页")
            .accessibilityIdentifier("reader-page-\(descriptor.index)")
        } else {
            Color.clear
                .accessibilityHidden(true)
        }
    }

    private func loadLeftPage() async {
        guard let descriptor = spread.leftPage else { return }
        leftFailed = false
        leftErrorMessage = nil
        leftMedia = nil
        do {
            let loadedMedia = try await ReaderPage.loadMedia(
                model: model,
                descriptor: descriptor,
                resolution: resolution,
                source: source
            )
            leftAspectRatio = loadedMedia.aspectRatio
            withAnimation(.easeOut(duration: 0.25)) {
                leftMedia = loadedMedia.content
                leftFailed = false
            }
        } catch is CancellationError {
            return
        } catch {
            leftErrorMessage = error.localizedDescription
            leftFailed = true
        }
    }

    private func loadRightPage() async {
        guard let descriptor = spread.rightPage else { return }
        rightFailed = false
        rightErrorMessage = nil
        rightMedia = nil
        do {
            let loadedMedia = try await ReaderPage.loadMedia(
                model: model,
                descriptor: descriptor,
                resolution: resolution,
                source: source
            )
            rightAspectRatio = loadedMedia.aspectRatio
            withAnimation(.easeOut(duration: 0.25)) {
                rightMedia = loadedMedia.content
                rightFailed = false
            }
        } catch is CancellationError {
            return
        } catch {
            rightErrorMessage = error.localizedDescription
            rightFailed = true
        }
    }

    private func saveMedia(_ descriptor: GalleryPageDescriptor) {
        guard isSaving == false else { return }
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
}

private struct MacReaderSpreadCanvas: View {
    let leftAspectRatio: CGFloat
    let rightAspectRatio: CGFloat
    let left: AnyView
    let right: AnyView

    init<Left: View, Right: View>(
        leftAspectRatio: CGFloat,
        rightAspectRatio: CGFloat,
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
    ) {
        self.leftAspectRatio = leftAspectRatio
        self.rightAspectRatio = rightAspectRatio
        self.left = AnyView(left())
        self.right = AnyView(right())
    }

    var body: some View {
        GeometryReader { proxy in
            let spineWidth: CGFloat = 1
            let availableWidth = max(proxy.size.width - spineWidth, 0)
            let totalAspectRatio = max(leftAspectRatio + rightAspectRatio, .leastNonzeroMagnitude)
            let leftWidth = availableWidth * leftAspectRatio / totalAspectRatio
            let rightWidth = availableWidth - leftWidth

            HStack(spacing: 0) {
                left
                    .frame(width: leftWidth, height: proxy.size.height)

                Rectangle()
                    .fill(.black.opacity(0.18))
                    .frame(width: spineWidth, height: proxy.size.height)
                    .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 0)

                right
                    .frame(width: rightWidth, height: proxy.size.height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
#endif

#if os(iOS)
import SwiftUI
import UIKit
import EHDomain

struct ReaderIOSSpreadView: View {
    let spread: ReaderSpread
    let resolution: ImageResolution
    let source: ReaderContentSource
    let resetToken: UUID

    var body: some View {
        HStack(spacing: 0) {
            pageView(spread.leftPage)

            Rectangle()
                .fill(Color.secondary.opacity(0.24))
                .frame(width: 1)
                .accessibilityHidden(true)

            pageView(spread.rightPage)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(spreadAccessibilityLabel)
    }

    @ViewBuilder
    private func pageView(_ descriptor: GalleryPageDescriptor?) -> some View {
        if let descriptor {
            ReaderPage(
                descriptor: descriptor,
                resolution: resolution,
                source: source,
                fitsViewport: true,
                resetToken: resetToken
            )
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        }
    }

    private var spreadAccessibilityLabel: String {
        let indexes = spread.pageIndexes.map { String($0 + 1) }.joined(separator: "、")
        return String(localized: "第 \(indexes) 页双页阅读单元")
    }
}
#endif
