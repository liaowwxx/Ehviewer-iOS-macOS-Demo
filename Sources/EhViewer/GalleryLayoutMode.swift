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

enum GalleryLayoutMode: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case list
    case grid
    case waterfall

    var next: Self {
        switch self {
        case .list: .grid
        case .grid: .waterfall
        case .waterfall: .list
        }
    }

    var id: Self { self }
    var title: String {
        switch self {
        case .list: String(localized: "列表")
        case .grid: String(localized: "卡片")
        case .waterfall: String(localized: "瀑布流")
        }
    }
    var systemImage: String {
        switch self {
        case .list: "list.bullet"
        case .grid: "square.grid.2x2"
        case .waterfall: "rectangle.grid.2x2"
        }
    }
}

extension GalleryCardDisplaySettings {
    var estimatedInformationHeight: Double {
        let rows = 2 + (showsAuthor ? 1 : 0) + (showsOrdinaryTags ? 2 : 0)
            + (showsCategoryBadge || showsLanguage || showsPageCount ? 1 : 0)
            + (showsPostedAt || showsAddedAt || showsRating ? 1 : 0)
        return Double(rows) * 20 * Self.clampedScale(cardScale) + 20
    }

    func columns(isRegularWidth: Bool) -> [GridItem] {
        let scale = Self.clampedScale(cardScale)
        return layoutMode == .grid
            ? [GridItem(
                .adaptive(minimum: (isRegularWidth ? 140 : 104) * scale, maximum: (isRegularWidth ? 190 : 140) * scale),
                spacing: isRegularWidth ? 16 : 12,
                alignment: .top
            )]
            : [GridItem(.flexible(), spacing: 4)]
    }
}
