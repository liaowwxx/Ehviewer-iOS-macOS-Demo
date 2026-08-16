import SwiftUI

/// Left-aligned flow layout that wraps subviews horizontally and grows
/// vertically, used for tag chips and the filter candidate bar.
struct TagFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let availableWidth = proposal.width ?? intrinsicWidth(for: sizes)
        let rows = rows(for: sizes, in: availableWidth)
        let contentHeight = rows.reduce(into: CGFloat.zero) { height, row in
            height += row.map { sizes[$0].height }.max() ?? 0
        }
        let rowSpacing = CGFloat(max(rows.count - 1, 0)) * verticalSpacing

        return CGSize(
            width: proposal.width ?? rows.map { rowWidth($0, sizes: sizes) }.max() ?? 0,
            height: contentHeight + rowSpacing
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = rows(for: sizes, in: bounds.width)
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
    }

    private func rows(for sizes: [CGSize], in availableWidth: CGFloat) -> [[Int]] {
        guard sizes.isEmpty == false else { return [] }

        var rows: [[Int]] = [[]]
        var currentWidth: CGFloat = 0

        for index in sizes.indices {
            let itemWidth = sizes[index].width
            let spacing = rows[rows.count - 1].isEmpty ? 0 : horizontalSpacing

            if rows[rows.count - 1].isEmpty == false,
               currentWidth + spacing + itemWidth > availableWidth {
                rows.append([])
                currentWidth = 0
            }

            let rowSpacing = rows[rows.count - 1].isEmpty ? 0 : horizontalSpacing
            rows[rows.count - 1].append(index)
            currentWidth += rowSpacing + itemWidth
        }

        return rows
    }

    private func rowWidth(_ row: [Int], sizes: [CGSize]) -> CGFloat {
        row.reduce(into: CGFloat.zero) { width, index in
            width += sizes[index].width
        } + CGFloat(max(row.count - 1, 0)) * horizontalSpacing
    }

    private func intrinsicWidth(for sizes: [CGSize]) -> CGFloat {
        sizes.reduce(into: CGFloat.zero) { width, size in
            width += size.width
        } + CGFloat(max(sizes.count - 1, 0)) * horizontalSpacing
    }
}
