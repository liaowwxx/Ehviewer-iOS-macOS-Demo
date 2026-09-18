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

struct ReaderThumbnailStrip: View {
    let descriptors: [GalleryPageDescriptor]
    let targetPage: Int
    let requestPage: (Int) -> Void
    let onSeekEnded: () -> Void
    @State private var scrollPosition = ScrollPosition(x: 0)
    @State private var visibleRange = 0..<0

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ReaderPageWindow.thumbnailSpacing) {
                    ForEach(descriptors[renderedRange]) { descriptor in
                        Button {
                            requestPage(descriptor.index)
                            onSeekEnded()
                        } label: {
                            ReaderThumbnailView(
                                descriptor: descriptor,
                                isSelected: descriptor.index == targetPage
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("选择后跳转到此页")
                    }
                }
                .padding(.leading, ReaderPageWindow.thumbnailPadding
                    + Double(renderedRange.lowerBound) * ReaderPageWindow.thumbnailStride)
                .frame(
                    width: ReaderPageWindow.thumbnailContentWidth(pageCount: descriptors.count),
                    height: 116,
                    alignment: .leading
                )
            }
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: Range<Int>.self) { scrollGeometry in
                ReaderPageWindow.thumbnailRange(
                    offset: scrollGeometry.contentOffset.x,
                    viewportWidth: scrollGeometry.containerSize.width,
                    pageCount: descriptors.count
                )
            } action: { _, range in
                visibleRange = range
            }
            .onAppear {
                synchronizeScrollPosition(viewportWidth: geometry.size.width)
            }
            .onChange(of: targetPage) { _, _ in
                synchronizeScrollPosition(viewportWidth: geometry.size.width)
            }
            .onChange(of: geometry.size.width) { _, width in
                synchronizeScrollPosition(viewportWidth: width)
            }
            .onChange(of: descriptors.count) { _, _ in
                synchronizeScrollPosition(viewportWidth: geometry.size.width)
            }
        }
        .frame(height: 116)
        .accessibilityLabel("页面预览")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reader-thumbnail-strip")
    }

    private var renderedRange: Range<Int> {
        let lowerBound = min(visibleRange.lowerBound, descriptors.count)
        let upperBound = min(visibleRange.upperBound, descriptors.count)
        return lowerBound..<max(lowerBound, upperBound)
    }

    private func synchronizeScrollPosition(viewportWidth: Double) {
        let target: Int
        if descriptors.indices.contains(targetPage), descriptors[targetPage].index == targetPage {
            target = targetPage
        } else {
            target = descriptors.firstIndex { $0.index == targetPage } ?? 0
        }
        let offset = ReaderPageWindow.thumbnailOffset(
            target: target,
            pageCount: descriptors.count,
            viewportWidth: viewportWidth
        )
        visibleRange = ReaderPageWindow.thumbnailRange(
            offset: offset,
            viewportWidth: viewportWidth,
            pageCount: descriptors.count
        )
        scrollPosition.scrollTo(x: offset)
    }
}
