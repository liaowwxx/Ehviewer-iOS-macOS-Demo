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

import Foundation

struct ReaderPositionState: Equatable {
    private(set) var page: Int
    private(set) var scrollTarget: Int?
    private(set) var scrollRequestSequence = 0
    private(set) var scrollRequestAnimated = true

    init(page: Int = 0) {
        self.page = max(page, 0)
    }

    mutating func prepare(page: Int, pageCount: Int) {
        self.page = clamped(page, pageCount: pageCount)
        scrollTarget = nil
        scrollRequestSequence = 0
        scrollRequestAnimated = true
    }

    mutating func markVisiblePage(from visiblePages: [Int], displayOrder: [Int]) {
        guard visiblePages.contains(page) == false,
              let visiblePage = displayOrder.first(where: visiblePages.contains) else { return }
        page = visiblePage
    }

    mutating func requestPage(_ page: Int, pageCount: Int, animated: Bool = true) {
        let target = clamped(page, pageCount: pageCount)
        self.page = target
        scrollTarget = target
        scrollRequestAnimated = animated
        scrollRequestSequence &+= 1
    }

    private func clamped(_ page: Int, pageCount: Int) -> Int {
        min(max(page, 0), max(pageCount - 1, 0))
    }
}
