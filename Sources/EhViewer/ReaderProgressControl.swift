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

struct ReaderProgressControl: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let page: Int
    let pageCount: Int
    let descriptors: [GalleryPageDescriptor]
    let source: ReaderContentSource
    let pageRange: ClosedRange<Int>?
    let requestPage: (Int) -> Void
    let onSeekEnded: () -> Void
    @State private var sliderValue: Double
    @State private var isPreviewExpanded = false
    @State private var isGridExpanded = false
    @State private var panelWidth = 0.0

    init(
        page: Int,
        pageCount: Int,
        descriptors: [GalleryPageDescriptor],
        source: ReaderContentSource,
        pageRange: ClosedRange<Int>? = nil,
        requestPage: @escaping (Int) -> Void,
        onSeekEnded: @escaping () -> Void
    ) {
        self.page = page
        self.pageCount = pageCount
        self.descriptors = descriptors
        self.source = source
        self.pageRange = pageRange
        self.requestPage = requestPage
        self.onSeekEnded = onSeekEnded
        let clampedPage = min(max(page, 0), max(pageCount - 1, 0))
        _sliderValue = State(initialValue: Double(clampedPage))
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Text(pageText)
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 76, alignment: .leading)

                Slider(
                    value: $sliderValue,
                    in: sliderRange,
                    step: 1,
                    onEditingChanged: handleEditingChanged
                )
                .accessibilityLabel("阅读进度")
                .accessibilityValue(Text(pageText))
                .disabled(pageCount <= 1)

                if source == .download {
                    Button(action: togglePreview) {
                        Image(systemName: isPreviewExpanded ? "chevron.down" : "chevron.up")
                            .foregroundStyle(.tint)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPreviewExpanded ? "收起预览" : "展开预览")
                    .accessibilityValue(isPreviewExpanded ? "已展开" : "已收起")
                    .accessibilityIdentifier("reader-preview-toggle")
                }
            }

            if isPreviewExpanded, source == .download, pageCount > 0 {
                VStack(spacing: 4) {
                    Button {
                        isGridExpanded.toggle()
                    } label: {
                        Label(
                            isGridExpanded ? "收起网格预览" : "展开网格预览",
                            systemImage: isGridExpanded ? "chevron.down" : "chevron.up"
                        )
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("reader-preview-grid-toggle")

                    if isGridExpanded {
                        ReaderThumbnailGrid(
                            descriptors: descriptors,
                            targetPage: currentPage,
                            height: verticalSizeClass == .compact ? 190 : 390,
                            viewportWidth: max(panelWidth - 24, 1),
                            requestPage: requestPage,
                            onSeekEnded: onSeekEnded
                        )
                        .transition(.identity)
                    } else {
                        ReaderThumbnailStrip(
                            descriptors: descriptors,
                            targetPage: currentPage,
                            requestPage: requestPage,
                            onSeekEnded: onSeekEnded
                        )
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 25)
                                .onEnded { value in
                                    let vertical = value.translation.height
                                    guard vertical < -55,
                                          abs(vertical) > abs(value.translation.width) else { return }
                                    isGridExpanded = true
                                }
                        )
                        .transition(.identity)
                    }
                }
                .transition(
                    accessibilityReduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity)
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .onGeometryChange(for: Double.self) { $0.size.width } action: { width in
            if abs(panelWidth - width) > 1 { panelWidth = width }
        }
        .accessibilityIdentifier("reader-progress-control")
        .animation(
            accessibilityReduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.25),
            value: isPreviewExpanded
        )
        .animation(
            .easeInOut(duration: accessibilityReduceMotion ? 0.15 : 0.22),
            value: isGridExpanded
        )
        .onChange(of: sliderValue) { _, newValue in
            let target = normalizedPage(from: newValue)
            guard target != currentPage else { return }
            requestPage(target)
        }
        .onChange(of: page) { _, newPage in
            synchronizeSlider(to: newPage)
        }
        .onChange(of: pageCount) { _, _ in
            synchronizeSlider(to: page)
        }
    }

    private var currentPage: Int {
        min(max(page, 0), max(pageCount - 1, 0))
    }

    private var pageText: String {
        guard pageCount > 0 else { return String(localized: "暂无页面") }
        if let pageRange {
            let firstPage = pageRange.lowerBound + 1
            let lastPage = pageRange.upperBound + 1
            if firstPage != lastPage {
                return String(localized: "第 \(firstPage)–\(lastPage)/\(pageCount) 页")
            }
        }
        return String(localized: "第 \(currentPage + 1)/\(pageCount) 页")
    }

    private var sliderRange: ClosedRange<Double> {
        0...Double(max(pageCount - 1, 1))
    }

    private func normalizedPage(from value: Double) -> Int {
        min(max(Int(value.rounded()), 0), max(pageCount - 1, 0))
    }

    private func synchronizeSlider(to page: Int) {
        let clampedPage = min(max(page, 0), max(pageCount - 1, 0))
        let value = Double(clampedPage)
        if sliderValue != value {
            sliderValue = value
        }
    }

    private func handleEditingChanged(_ editing: Bool) {
        if editing == false {
            onSeekEnded()
        }
    }

    private func togglePreview() {
        isPreviewExpanded.toggle()
        if isPreviewExpanded == false {
            isGridExpanded = false
        }
    }
}
