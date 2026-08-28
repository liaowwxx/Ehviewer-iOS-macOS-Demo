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
    var showsAddedAt = false
    var dateDisplayStyle: GalleryDateDisplayStyle = .relative
    var showsRating = true
    var ratingDisplayStyle: GalleryRatingDisplayStyle = .numeric

    static let defaults = GalleryCardDisplaySettings()

    private enum CodingKeys: String, CodingKey {
        case showsAuthor
        case showsOrdinaryTags
        case showsCategoryBadge
        case showsLanguage
        case showsPageCount
        case showsPostedAt
        case showsAddedAt
        case dateDisplayStyle
        case showsRating
        case ratingDisplayStyle
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showsAuthor = try container.decodeIfPresent(Bool.self, forKey: .showsAuthor) ?? true
        showsOrdinaryTags = try container.decodeIfPresent(Bool.self, forKey: .showsOrdinaryTags) ?? true
        showsCategoryBadge = try container.decodeIfPresent(Bool.self, forKey: .showsCategoryBadge) ?? true
        showsLanguage = try container.decodeIfPresent(Bool.self, forKey: .showsLanguage) ?? true
        showsPageCount = try container.decodeIfPresent(Bool.self, forKey: .showsPageCount) ?? true
        showsPostedAt = try container.decodeIfPresent(Bool.self, forKey: .showsPostedAt) ?? true
        showsAddedAt = try container.decodeIfPresent(Bool.self, forKey: .showsAddedAt) ?? false
        dateDisplayStyle = try container.decodeIfPresent(GalleryDateDisplayStyle.self, forKey: .dateDisplayStyle) ?? .relative
        showsRating = try container.decodeIfPresent(Bool.self, forKey: .showsRating) ?? true
        ratingDisplayStyle = try container.decodeIfPresent(GalleryRatingDisplayStyle.self, forKey: .ratingDisplayStyle) ?? .numeric
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(showsAuthor, forKey: .showsAuthor)
        try container.encode(showsOrdinaryTags, forKey: .showsOrdinaryTags)
        try container.encode(showsCategoryBadge, forKey: .showsCategoryBadge)
        try container.encode(showsLanguage, forKey: .showsLanguage)
        try container.encode(showsPageCount, forKey: .showsPageCount)
        try container.encode(showsPostedAt, forKey: .showsPostedAt)
        try container.encode(showsAddedAt, forKey: .showsAddedAt)
        try container.encode(dateDisplayStyle, forKey: .dateDisplayStyle)
        try container.encode(showsRating, forKey: .showsRating)
        try container.encode(ratingDisplayStyle, forKey: .ratingDisplayStyle)
    }

    /// Resolves the compact-width collision between tag chips and the visual
    /// star row. This deliberately receives both values so it remains pure and
    /// is independently testable from SwiftUI's binding lifecycle.
    static func resolving(
        previous: Self,
        updated: Self,
        isCompactWidth: Bool
    ) -> Self {
        var resolved = updated
        if resolved.showsPostedAt, resolved.showsAddedAt {
            if previous.showsPostedAt == false, updated.showsPostedAt {
                resolved.showsAddedAt = false
            } else if previous.showsAddedAt == false, updated.showsAddedAt {
                resolved.showsPostedAt = false
            } else {
                // A legacy or programmatic conflict has no user interaction
                // to disambiguate it, so keep the established upload date.
                resolved.showsAddedAt = false
            }
        }

        guard isCompactWidth else { return resolved }
        guard resolved.showsRating, resolved.ratingDisplayStyle == .stars else { return resolved }
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
