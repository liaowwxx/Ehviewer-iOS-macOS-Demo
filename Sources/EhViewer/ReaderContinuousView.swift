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

#if os(iOS)
import UIKit
#endif

struct ReaderVerticalPagedView: View {
    @Environment(AppModel.self) private var model
    let descriptors: [GalleryPageDescriptor]
    let resolution: ImageResolution
    let resetToken: UUID
    let source: ReaderContentSource
    @Binding var position: ReaderPositionState
    @State private var initialScrollPending = true

    var body: some View {
        #if os(iOS)
        ReaderPagedControllerRepresentable(
            model: model,
            descriptors: descriptors,
            resolution: resolution,
            resetToken: resetToken,
            readingDirection: .leftToRight,
            navigationOrientation: .vertical,
            source: source,
            position: $position
        )
        .id("reader-vertical-paging")
        #else
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(descriptors) { descriptor in
                    ReaderPage(
                        descriptor: descriptor,
                        resolution: resolution,
                        source: source,
                        fitsViewport: true
                    )
                    .containerRelativeFrame([.horizontal, .vertical])
                    .id(descriptor.index)
                }
                .scrollTargetLayout()
            }
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.visible)
        .scrollPosition(id: $scrollPosition, anchor: .center)
        .task {
            await Task.yield()
            scrollPosition = position.page
        }
        .onChange(of: position.scrollRequestSequence) {
            guard let target = position.scrollTarget else { return }
            if position.scrollRequestAnimated {
                withAnimation {
                    scrollPosition = target
                }
            } else {
                scrollPosition = target
            }
        }
        .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.55) { visiblePages in
            if initialScrollPending {
                guard visiblePages.contains(position.page) else {
                    scrollPosition = position.page
                    return
                }
                initialScrollPending = false
            }
            position.markVisiblePage(from: visiblePages, displayOrder: descriptors.map(\.index))
        }
        .accessibilityHint("上下翻页阅读")
        #endif
    }

    #if os(macOS)
    @State private var scrollPosition: Int?
    #endif
}
