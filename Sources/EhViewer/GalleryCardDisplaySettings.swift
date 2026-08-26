/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation

enum GalleryDateDisplayStyle: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case relative
    case absolute

    var id: Self { self }

    var title: String {
        switch self {
        case .relative: String(localized: "相对时间")
        case .absolute: String(localized: "绝对日期")
        }
    }
}

enum GalleryRatingDisplayStyle: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case numeric
    case stars

    var id: Self { self }

    var title: String {
        switch self {
        case .numeric: String(localized: "数字评分")
        case .stars: String(localized: "五星评分")
        }
    }
}

struct GalleryCardDisplaySettings: Codable, Hashable, Sendable {
    var showsAuthor = true
    var showsOrdinaryTags = true
    var showsCategoryBadge = true
    var showsLanguage = true
    var showsPageCount = true
    var showsPostedAt = true
    var dateDisplayStyle: GalleryDateDisplayStyle = .relative
    var showsRating = true
    var ratingDisplayStyle: GalleryRatingDisplayStyle = .numeric

    static let defaults = GalleryCardDisplaySettings()

    /// Resolves the compact-width collision between tag chips and the visual
    /// star row. This deliberately receives both values so it remains pure and
    /// is independently testable from SwiftUI's binding lifecycle.
    static func resolving(
        previous: Self,
        updated: Self,
        isCompactWidth: Bool
    ) -> Self {
        guard isCompactWidth else { return updated }
        guard updated.showsRating, updated.ratingDisplayStyle == .stars else { return updated }

        var resolved = updated
        if previous.showsOrdinaryTags == false, updated.showsOrdinaryTags {
            // Re-enabling tags deliberately changes only the presentation of
            // rating. The rating itself stays available and enabled.
            resolved.ratingDisplayStyle = .numeric
        } else {
            // Enabling stars, re-enabling a star preference, or normalizing a
            // legacy conflicting value all give the visual score priority.
            resolved.showsOrdinaryTags = false
        }
        return resolved
    }

    /// Applies compact-width rendering rules without changing the persisted
    /// preference. A split-view resize can therefore never leave both visual
    /// tag rows visible, even when the setting was chosen in regular width.
    func effectiveForDisplay(isCompactWidth: Bool) -> Self {
        Self.resolving(previous: self, updated: self, isCompactWidth: isCompactWidth)
    }
}
