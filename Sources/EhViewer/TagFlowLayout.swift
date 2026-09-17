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

/// Left-aligned flow layout that wraps subviews horizontally and grows
/// vertically, used for tag chips and the filter candidate bar.
struct TagFlowLayout: Layout, Equatable {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    let maximumRows: Int?

    init(horizontalSpacing: CGFloat, verticalSpacing: CGFloat, maximumRows: Int? = nil) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.maximumRows = maximumRows
    }

    func makeCache(subviews: Subviews) -> TagFlowLayoutCache { TagFlowLayoutCache() }

    func updateCache(_ cache: inout TagFlowLayoutCache, subviews: Subviews) {
        cache = TagFlowLayoutCache()
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout TagFlowLayoutCache
    ) -> CGSize {
        resolve(count: subviews.count, width: proposal.width, cache: &cache) { subviews[$0].sizeThatFits(.unspecified) }
        return cache.size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout TagFlowLayoutCache
    ) {
        if !cache.isValid || cache.layout != self || cache.itemCount != subviews.count || cache.size.width != bounds.width {
            cache = measure(count: subviews.count, width: bounds.width) { subviews[$0].sizeThatFits(.unspecified) }
        }
        let sizes = cache.sizes
        let rows = cache.rows
        var y = bounds.minY

        for row in rows {
            let rowHeight = row.map { sizes[$0].height }.max() ?? 0
            var x = bounds.minX

            for index in row {
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(sizes[index])
                )
                x += sizes[index].width + horizontalSpacing
            }

            y += rowHeight + verticalSpacing
        }
        if maximumRows != nil {
            let visibleCount = rows.reduce(0) { $0 + $1.count }
            for index in visibleCount..<subviews.count {
                subviews[index].place(
                    at: CGPoint(x: bounds.minX, y: bounds.maxY + verticalSpacing),
                    anchor: .topLeading,
                    proposal: .zero
                )
            }
        }
    }

    /// Only the first item that would overflow the row budget is measured.
    /// Remaining chips need neither intrinsic measurement nor row calculation.
    func measure(count: Int, width: CGFloat?, itemSize: (Int) -> CGSize) -> TagFlowLayoutCache {
        var sizes: [CGSize] = []
        var rows: [[Int]] = []
        var currentWidth: CGFloat = 0
        for index in 0..<count {
            let size = itemSize(index)
            let spacing = rows.last?.isEmpty == false ? horizontalSpacing : 0
            if !rows.isEmpty, !rows[rows.count - 1].isEmpty,
               currentWidth + spacing + size.width > (width ?? .greatestFiniteMagnitude) {
                if let maximumRows, rows.count >= maximumRows { break }
                rows.append([])
                currentWidth = 0
            }
            if rows.isEmpty { rows.append([]) }
            currentWidth += (rows[rows.count - 1].isEmpty ? 0 : horizontalSpacing) + size.width
            rows[rows.count - 1].append(index)
            sizes.append(size)
        }
        let height = rows.reduce(CGFloat.zero) { $0 + ($1.map { sizes[$0].height }.max() ?? 0) }
            + CGFloat(max(0, rows.count - 1)) * verticalSpacing
        let resultWidth = width ?? rows.map { rowWidth($0, sizes: sizes) }.max() ?? 0
        return TagFlowLayoutCache(
            layout: self, itemCount: count, width: width, sizes: sizes, rows: rows,
            size: CGSize(width: resultWidth, height: height), isValid: true
        )
    }

    func resolve(count: Int, width: CGFloat?, cache: inout TagFlowLayoutCache, itemSize: (Int) -> CGSize) {
        if !cache.isValid || cache.layout != self || cache.itemCount != count || cache.width != width {
            cache = measure(count: count, width: width, itemSize: itemSize)
        }
    }

    func rows(for sizes: [CGSize], in availableWidth: CGFloat) -> [[Int]] {
        measure(count: sizes.count, width: availableWidth) { sizes[$0] }.rows
    }

    private func rowWidth(_ row: [Int], sizes: [CGSize]) -> CGFloat {
        row.reduce(into: CGFloat.zero) { width, index in
            width += sizes[index].width
        } + CGFloat(max(row.count - 1, 0)) * horizontalSpacing
    }

}
