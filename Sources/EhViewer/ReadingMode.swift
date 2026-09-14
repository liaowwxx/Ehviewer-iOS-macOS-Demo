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

enum ReadingMode: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case paged
    case verticalPaged

    var id: Self { self }

    var title: String {
        switch self {
        case .paged: String(localized: "左右翻页")
        case .verticalPaged: String(localized: "上下翻页")
        }
    }
}

enum ReaderPageLayout: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case single
    case double

    var id: Self { self }

    var title: String {
        switch self {
        case .single: String(localized: "单页")
        case .double: String(localized: "双页")
        }
    }

    var systemImageName: String {
        switch self {
        case .single: "rectangle.portrait"
        case .double: "book.pages"
        }
    }

    var toggleHint: String {
        switch self {
        case .single: String(localized: "切换到单页")
        case .double: String(localized: "切换到双页")
        }
    }
}

enum ReadingDirection: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case leftToRight
    case rightToLeft

    var id: Self { self }

    var title: String {
        switch self {
        case .leftToRight: String(localized: "从左到右")
        case .rightToLeft: String(localized: "从右到左")
        }
    }
}
