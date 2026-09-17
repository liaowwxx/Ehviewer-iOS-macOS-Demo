/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import SwiftUI
import EHDomain

struct StableCardGrid<Item, Content: View>: View {
    @Environment(\.cardLayoutWindowWidth) private var windowWidth
    let items: [Item]
    let key: KeyPath<Item, GalleryKey>
    let scale: Double
    let spacing: Double
    let isRegularWidth: Bool
    let content: (Item) -> Content
    @State private var sizing = CardGridSizing()

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: spacing, alignment: .top), count: sizing.columns),
            spacing: spacing * sizing.scale(spacing: spacing)
        ) {
            ForEach(items, id: key) { item in
                if sizing.referenceWidth > 0 {
                    ProportionalCard(
                        referenceWidth: sizing.referenceColumnWidth(spacing: spacing),
                        width: sizing.currentColumnWidth(spacing: spacing)
                    ) { content(item) }
                } else {
                    content(item)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: Double.self) { $0.size.width } action: { width in
            update(width: width)
        }
        .onChange(of: windowWidth) { update(width: sizing.currentWidth) }
        .onChange(of: scale) { update(width: sizing.currentWidth, force: true) }
        .onChange(of: isRegularWidth) {
            if windowWidth == 0 { update(width: sizing.currentWidth, force: true) }
        }
    }

    private func update(width: Double, force: Bool = false) {
        sizing.update(
            width: width, windowWidth: windowWidth,
            target: (isRegularWidth ? 140 : 104) * GalleryCardDisplaySettings.clampedScale(scale),
            spacing: spacing, force: force
        )
    }
}
