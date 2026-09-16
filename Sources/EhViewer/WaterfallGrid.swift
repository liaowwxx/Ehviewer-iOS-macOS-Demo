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

struct WaterfallGrid<Item, Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let items: [Item]
    let key: KeyPath<Item, GalleryKey>
    let scale: Double
    let spacing: Double
    let estimatedInformationHeight: Double
    let content: (Item) -> Content
    @State private var width = 0.0
    @State private var heights: [GalleryKey: Double] = [:]
    @State private var placement: [GalleryKey: Int] = [:]
    @State private var coverRatios: [GalleryKey: Double] = [:]

    private var keys: [GalleryKey] { items.map { $0[keyPath: key] } }
    private var count: Int {
        WaterfallLayout.columnCount(width: width, spacing: spacing, scale: scale, accessibility: dynamicTypeSize.isAccessibilitySize)
    }
    private var columnWidth: Double { max(1, (width - Double(count - 1) * spacing) / Double(count)) }

    var body: some View {
        let resolved = placement.isEmpty ? assignments() : placement
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<count, id: \.self) { column in
                LazyVStack(spacing: spacing) {
                    ForEach(items.filter { resolved[$0[keyPath: key]] == column }, id: key) { item in
                        content(item)
                            .frame(maxWidth: .infinity)
                            .background {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: WaterfallHeightPreference.self,
                                        value: [item[keyPath: key]: proxy.size.height]
                                    )
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .environment(\.waterfallCoverRatios, $coverRatios)
        .onGeometryChange(for: Double.self) { $0.size.width } action: { newWidth in
            guard abs(width - newWidth) > 1 else { return }
            width = newWidth
            heights = [:]
            placement = assignments()
        }
        .onPreferenceChange(WaterfallHeightPreference.self) { measured in
            var changed = false
            for (key, height) in measured where height > 0 {
                if abs((heights[key] ?? 0) - height) > 1 {
                    heights[key] = height
                    changed = true
                }
            }
            if changed { placement = assignments() }
        }
        .onChange(of: keys) { previous, updated in
            let appending = updated.count >= previous.count && Array(updated.prefix(previous.count)) == previous
            let retained = Set(updated)
            heights = heights.filter { retained.contains($0.key) }
            coverRatios = coverRatios.filter { retained.contains($0.key) }
            placement = assignments(preserving: appending ? placement : [:])
        }
        .onChange(of: scale) { placement = assignments() }
        .onChange(of: dynamicTypeSize) { _ , _ in
            heights = [:]
            placement = assignments()
        }
        .transaction { $0.animation = nil }
    }

    private func assignments(preserving: [GalleryKey: Int] = [:]) -> [GalleryKey: Int] {
        WaterfallLayout.assignments(
            keys: keys, heights: heights, count: count, spacing: spacing,
            estimatedHeight: columnWidth * 4 / 3 + estimatedInformationHeight,
            preserving: preserving
        )
    }
}
