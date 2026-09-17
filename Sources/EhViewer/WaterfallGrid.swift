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
    @Environment(\.cardLayoutWindowWidth) private var windowWidth
    let items: [Item]
    let key: KeyPath<Item, GalleryKey>
    let scale: Double
    let spacing: Double
    let estimatedInformationHeight: Double
    let content: (Item) -> Content
    @State private var sizing = CardGridSizing()
    @State private var placement: [GalleryKey: Int] = [:]
    @State private var measurements = WaterfallMeasurements()
    @State private var columnCache = WaterfallColumnCache()

    private var keys: [GalleryKey] { items.map { $0[keyPath: key] } }
    private var count: Int {
        dynamicTypeSize.isAccessibilitySize ? 1 : sizing.columns
    }
    private var columnWidth: Double { max(1, (sizing.referenceWidth - Double(count - 1) * spacing) / Double(count)) }
    private var currentColumnWidth: Double { max(1, (sizing.currentWidth - Double(count - 1) * spacing) / Double(count)) }
    private var contentScale: Double { currentColumnWidth / columnWidth }

    var body: some View {
        let resolved = placement.isEmpty ? assignments() : placement
        let columns = columnCache.indices(keys: keys, placement: resolved, count: count)
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<count, id: \.self) { column in
                LazyVStack(spacing: spacing * contentScale) {
                    ForEach(columns[column].map { items[$0] }, id: key) { item in
                        card(item)
                            .frame(maxWidth: .infinity)
                            .onGeometryChange(for: Double.self) { $0.size.height } action: { height in
                                // Non-observable cache: measuring a visible card must not
                                // invalidate the grid or reassign existing cards.
                                if height > 0 {
                                    measurements.heights[item[keyPath: key]] = height / contentScale
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .environment(\.waterfallCoverRatios, measurements)
        .onGeometryChange(for: Double.self) { $0.size.width } action: { newWidth in
            updateSizing(width: newWidth)
        }
        .onChange(of: keys) { previous, updated in
            let appending = updated.count >= previous.count && Array(updated.prefix(previous.count)) == previous
            measurements.retain(Set(updated))
            placement = assignments(preserving: appending ? placement : [:])
        }
        .onChange(of: scale) {
            updateSizing(width: sizing.currentWidth, force: true)
        }
        .onChange(of: dynamicTypeSize) { _ , _ in
            updateSizing(width: sizing.currentWidth, force: true)
        }
        .onChange(of: windowWidth) { updateSizing(width: sizing.currentWidth) }
        .transaction { $0.animation = nil }
    }

    private func assignments(preserving: [GalleryKey: Int] = [:]) -> [GalleryKey: Int] {
        WaterfallLayout.assignments(
            keys: keys, heights: measurements.heights, count: count, spacing: spacing,
            estimatedHeight: columnWidth * 4 / 3 + estimatedInformationHeight,
            preserving: preserving
        )
    }

    @ViewBuilder
    private func card(_ item: Item) -> some View {
        if sizing.referenceWidth > 0 {
            ProportionalCard(referenceWidth: columnWidth, width: currentColumnWidth) {
                content(item)
            }
        } else {
            content(item)
        }
    }

    private func updateSizing(width: Double, force: Bool = false) {
        let previousReference = sizing.referenceWidth
        let previousCount = count
        sizing.update(
            width: width, windowWidth: windowWidth,
            target: 170 * GalleryCardDisplaySettings.clampedScale(scale),
            spacing: spacing, force: force
        )
        if force || abs(previousReference - sizing.referenceWidth) > 1 || previousCount != count {
            measurements.heights = [:]
            placement = assignments()
        }
    }
}
