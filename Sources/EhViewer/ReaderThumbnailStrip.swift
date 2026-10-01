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
                    height: ReaderPageWindow.thumbnailHeight,
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
        .frame(height: ReaderPageWindow.thumbnailHeight)
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

struct ReaderThumbnailGrid: View {
    let descriptors: [GalleryPageDescriptor]
    let targetPage: Int
    let height: Double
    let requestPage: (Int) -> Void
    let onSeekEnded: () -> Void
    @State private var scrollPosition: ScrollPosition
    @State private var visibleRange: Range<Int>

    init(
        descriptors: [GalleryPageDescriptor],
        targetPage: Int,
        height: Double,
        viewportWidth: Double,
        requestPage: @escaping (Int) -> Void,
        onSeekEnded: @escaping () -> Void
    ) {
        self.descriptors = descriptors
        self.targetPage = targetPage
        self.height = height
        self.requestPage = requestPage
        self.onSeekEnded = onSeekEnded
        let target: Int
        if descriptors.indices.contains(targetPage), descriptors[targetPage].index == targetPage {
            target = targetPage
        } else {
            target = descriptors.firstIndex { $0.index == targetPage } ?? 0
        }
        let offset = ReaderPageWindow.gridOffset(
            target: target,
            pageCount: descriptors.count,
            viewportWidth: viewportWidth,
            viewportHeight: height
        )
        _scrollPosition = State(initialValue: ScrollPosition(y: offset))
        _visibleRange = State(initialValue: ReaderPageWindow.gridRange(
            offset: offset,
            viewportWidth: viewportWidth,
            viewportHeight: height,
            pageCount: descriptors.count
        ))
    }

    var body: some View {
        GeometryReader { geometry in
            let width = Double(geometry.size.width)
            let columnCount = ReaderPageWindow.gridColumnCount(viewportWidth: width)
            let cellWidth = (width - ReaderPageWindow.gridPadding * 2
                - Double(columnCount - 1) * ReaderPageWindow.gridSpacing) / Double(columnCount)
            let firstRow = renderedRange.lowerBound / columnCount
            let lastRow = (renderedRange.upperBound + columnCount - 1) / columnCount

            ScrollView(.vertical) {
                Color.clear
                    .frame(
                        width: width,
                        height: ReaderPageWindow.gridContentHeight(
                            pageCount: descriptors.count,
                            viewportWidth: width
                        )
                    )
                    .contentShape(Rectangle())
                    .overlay(alignment: .topLeading) {
                        VStack(spacing: ReaderPageWindow.gridSpacing) {
                            ForEach(firstRow..<lastRow, id: \.self) { row in
                                HStack(spacing: ReaderPageWindow.gridSpacing) {
                                    ForEach(0..<columnCount, id: \.self) { column in
                                        let index = row * columnCount + column
                                        if descriptors.indices.contains(index) {
                                            let descriptor = descriptors[index]
                                            Button {
                                                requestPage(descriptor.index)
                                                onSeekEnded()
                                            } label: {
                                                ReaderThumbnailView(
                                                    descriptor: descriptor,
                                                    isSelected: descriptor.index == targetPage
                                                )
                                                .frame(width: cellWidth)
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityHint("选择后跳转到此页")
                                        } else {
                                            Color.clear
                                                .frame(width: cellWidth, height: ReaderPageWindow.thumbnailHeight)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.leading, ReaderPageWindow.gridPadding)
                        .offset(y: ReaderPageWindow.gridPadding
                            + Double(firstRow) * ReaderPageWindow.gridRowStride)
                    }
            }
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: Range<Int>.self) { scrollGeometry in
                ReaderPageWindow.gridRange(
                    offset: scrollGeometry.contentOffset.y,
                    viewportWidth: scrollGeometry.containerSize.width,
                    viewportHeight: height,
                    pageCount: descriptors.count
                )
            } action: { _, range in
                visibleRange = range
            }
            .onAppear {
                synchronizeScrollPosition(viewportWidth: width)
            }
            .onChange(of: targetPage) { _, _ in
                synchronizeScrollPosition(viewportWidth: width)
            }
            .onChange(of: geometry.size.width) { _, width in
                synchronizeScrollPosition(viewportWidth: width)
            }
            .onChange(of: descriptors.count) { _, _ in
                synchronizeScrollPosition(viewportWidth: width)
            }
        }
        .frame(height: height)
        .accessibilityLabel("网格页面预览")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reader-thumbnail-grid")
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
        let offset = ReaderPageWindow.gridOffset(
            target: target,
            pageCount: descriptors.count,
            viewportWidth: viewportWidth,
            viewportHeight: height
        )
        let range = ReaderPageWindow.gridRange(
            offset: offset,
            viewportWidth: viewportWidth,
            viewportHeight: height,
            pageCount: descriptors.count
        )
        guard range != visibleRange || abs((scrollPosition.y ?? offset) - offset) > 1 else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            visibleRange = range
            scrollPosition.scrollTo(y: offset)
        }
    }
}
