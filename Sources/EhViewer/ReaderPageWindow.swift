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
