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
    @State private var scrollPosition: Int?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(descriptors) { descriptor in
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
                    .id(descriptor.index)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 12)
        }
        .scrollPosition(id: $scrollPosition, anchor: .center)
        .onAppear {
            synchronizeScrollPosition()
        }
        .onChange(of: targetPage) { _, _ in
            synchronizeScrollPosition()
        }
        .frame(height: 116)
        .accessibilityLabel("页面预览")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reader-thumbnail-strip")
    }

    private func synchronizeScrollPosition() {
        scrollPosition = targetPage
    }
}
