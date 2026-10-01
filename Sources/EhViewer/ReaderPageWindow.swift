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

struct ReaderPageWindow {
    static let thumbnailWidth: Double = 96
    static let thumbnailImageWidth: Double = 88
    static let thumbnailImageHeight: Double = 112
    static let thumbnailHeight: Double = 136
    static let thumbnailSpacing: Double = 10
    static let thumbnailPadding: Double = 12
    static let thumbnailStride = thumbnailWidth + thumbnailSpacing
    static let gridSpacing: Double = 8
    static let gridPadding: Double = 4
    static let gridMinimumCellWidth: Double = 100
    static let gridRowStride = thumbnailHeight + gridSpacing

    static func thumbnailContentWidth(pageCount: Int) -> Double {
        Double(max(pageCount, 0)) * thumbnailStride
            - (pageCount > 0 ? thumbnailSpacing : 0) + thumbnailPadding * 2
    }

    /// Fixed-size cells allow distant seeks without measuring preceding pages.
    static func thumbnailOffset(target: Int, pageCount: Int, viewportWidth: Double) -> Double {
        guard pageCount > 0 else { return 0 }
        let target = min(max(target, 0), pageCount - 1)
        let centeredOffset = thumbnailPadding + Double(target) * thumbnailStride
            + thumbnailWidth / 2 - viewportWidth / 2
        let maximumOffset = max(thumbnailContentWidth(pageCount: pageCount) - viewportWidth, 0)
        return min(max(centeredOffset, 0), maximumOffset)
    }

    /// Only instantiate visible cells plus three cells on each side for scrolling.
    static func thumbnailRange(offset: Double, viewportWidth: Double, pageCount: Int) -> Range<Int> {
        guard pageCount > 0, viewportWidth > 0 else { return 0..<0 }
        let maximumOffset = max(thumbnailContentWidth(pageCount: pageCount) - viewportWidth, 0)
        let offset = min(max(offset, 0), maximumOffset)
        let first = Int(((offset - thumbnailPadding) / thumbnailStride).rounded(.down))
        let end = Int(((offset + viewportWidth - thumbnailPadding) / thumbnailStride).rounded(.up))
        return max(first - 3, 0)..<min(end + 3, pageCount)
    }

    static func gridColumnCount(viewportWidth: Double) -> Int {
        let availableWidth = max(viewportWidth - gridPadding * 2, gridMinimumCellWidth)
        return max(Int(((availableWidth + gridSpacing) / (gridMinimumCellWidth + gridSpacing)).rounded(.down)), 1)
    }

    static func gridContentHeight(pageCount: Int, viewportWidth: Double) -> Double {
        let columns = gridColumnCount(viewportWidth: viewportWidth)
        let rows = (max(pageCount, 0) + columns - 1) / columns
        guard rows > 0 else { return 0 }
        return gridPadding * 2 + Double(rows) * thumbnailHeight + Double(rows - 1) * gridSpacing
    }

    static func gridOffset(
        target: Int,
        pageCount: Int,
        viewportWidth: Double,
        viewportHeight: Double
    ) -> Double {
        guard pageCount > 0, viewportHeight > 0 else { return 0 }
        let columns = gridColumnCount(viewportWidth: viewportWidth)
        let row = min(max(target, 0), pageCount - 1) / columns
        let centeredOffset = gridPadding + Double(row) * gridRowStride
            + thumbnailHeight / 2 - viewportHeight / 2
        let maximumOffset = max(gridContentHeight(pageCount: pageCount, viewportWidth: viewportWidth) - viewportHeight, 0)
        return min(max(centeredOffset, 0), maximumOffset)
    }

    /// Render complete rows around the viewport, including two buffer rows on each side.
    static func gridRange(
        offset: Double,
        viewportWidth: Double,
        viewportHeight: Double,
        pageCount: Int
    ) -> Range<Int> {
        guard pageCount > 0, viewportWidth > 0, viewportHeight > 0 else { return 0..<0 }
        let columns = gridColumnCount(viewportWidth: viewportWidth)
        let rowCount = (pageCount + columns - 1) / columns
        let maximumOffset = max(gridContentHeight(pageCount: pageCount, viewportWidth: viewportWidth) - viewportHeight, 0)
        let offset = min(max(offset, 0), maximumOffset)
        let firstRow = Int(((offset - gridPadding) / gridRowStride).rounded(.down))
        let lastRow = Int(((offset + viewportHeight - gridPadding) / gridRowStride).rounded(.up))
        let lowerRow = max(firstRow - 2, 0)
        let upperRow = min(lastRow + 2, rowCount)
        return (lowerRow * columns)..<min(upperRow * columns, pageCount)
    }

    static func indexes(target: Int, pageCount: Int, maximumCount: Int) -> [Int] {
        guard pageCount > 0, maximumCount > 0 else { return [] }

        let count = min(pageCount, maximumCount)
        let clampedTarget = min(max(target, 0), pageCount - 1)
        let maximumStart = pageCount - count
        let centeredStart = clampedTarget - count / 2
        let start = min(max(centeredStart, 0), maximumStart)
        return Array(start..<(start + count))
    }

    static func maximumCount(
        forAvailableWidth width: Double,
        thumbnailWidth: Double = 60,
        spacing: Double = 8,
        horizontalPadding: Double = 24
    ) -> Int {
        guard width > 0, thumbnailWidth > 0 else { return 1 }
        let contentWidth = max(width - horizontalPadding, thumbnailWidth)
        let count = Int(((contentWidth + spacing) / (thumbnailWidth + spacing)).rounded(.down))
        return max(count, 1)
    }
}
