/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai gallery browsing client
 * Copyright (C) 2026 EhViewer Contributors
 */

import Foundation

public enum GallerySnapshotError: Error, LocalizedError, Sendable {
    case keyMismatch

    public var errorDescription: String? {
        switch self {
        case .keyMismatch:
            String(localized: "画廊快照的标识不一致。")
        }
    }
}

/// The comment representation that is safe to persist in a downloaded
/// gallery. Session-scoped edit and vote permissions are deliberately absent.
public struct DownloadedGalleryCommentSnapshot: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let author: String
    public let body: String
    public let postedAt: Date?
    public let score: Int

    public init(
        id: String,
        author: String,
        body: String,
        postedAt: Date? = nil,
        score: Int = 0
    ) {
        self.id = id
        self.author = author
        self.body = body
        self.postedAt = postedAt
        self.score = score
    }

    public init(comment: GalleryComment) {
        self.init(
            id: comment.id,
            author: comment.author,
            body: comment.body,
            postedAt: comment.postedAt,
            score: comment.score
        )
    }

    public var galleryComment: GalleryComment {
        GalleryComment(
            id: id,
            author: author,
            body: body,
            postedAt: postedAt,
            score: score
        )
    }
}

/// Stable gallery content shared by ordinary cache entries, downloads and
/// transfer archives. It contains no ratings, favorites or comments.
public struct StableGalleryMetadataSnapshot: Codable, Hashable, Sendable, Identifiable {
    public let key: GalleryKey
    public var sourceSite: SiteMode
    public var title: String
    public var japaneseTitle: String?
    public var authors: [String]
    public var uploader: String?
    public var tags: [String]
    public var category: String?
    public var language: String?
    public var pageCount: Int?
    public var postedAt: Date?
    public var thumbnailURL: URL?
    public var fileSize: String?
    public var descriptionText: String?
    public var externalURL: URL?
    public var pages: [GalleryPageDescriptor]
    public var capturedAt: Date
    public var completeness: GalleryMetadataCompleteness

    public init(
        key: GalleryKey,
        sourceSite: SiteMode,
        title: String,
        japaneseTitle: String? = nil,
        authors: [String] = [],
        uploader: String? = nil,
        tags: [String] = [],
        category: String? = nil,
        language: String? = nil,
        pageCount: Int? = nil,
        postedAt: Date? = nil,
        thumbnailURL: URL? = nil,
        fileSize: String? = nil,
        descriptionText: String? = nil,
        externalURL: URL? = nil,
        pages: [GalleryPageDescriptor] = [],
        capturedAt: Date = Date(),
        completeness: GalleryMetadataCompleteness? = nil
    ) {
        self.key = key
        self.sourceSite = sourceSite
        self.title = title
        self.japaneseTitle = japaneseTitle
        self.authors = authors
        self.uploader = uploader
        self.tags = tags
        self.category = category
        self.language = language
        self.pageCount = pageCount
        self.postedAt = postedAt
        self.thumbnailURL = thumbnailURL
        self.fileSize = fileSize
        self.descriptionText = descriptionText
        self.externalURL = externalURL
        self.pages = pages
        self.capturedAt = capturedAt
        self.completeness = completeness ?? GalleryMetadataCompleteness(
            title: Self.state(for: title),
            japaneseTitle: Self.state(for: japaneseTitle),
            authors: Self.state(for: authors),
            uploader: Self.state(for: uploader),
            tags: Self.state(for: tags),
            category: Self.state(for: category),
            language: Self.state(for: language),
            pageCount: Self.state(for: pageCount),
            postedAt: Self.state(for: postedAt),
            thumbnailURL: Self.state(for: thumbnailURL),
            fileSize: Self.state(for: fileSize),
            description: Self.state(for: descriptionText),
            externalURL: Self.state(for: externalURL),
            pages: Self.state(for: pages)
        )
    }

    public init(summary: GallerySummary, sourceSite: SiteMode, capturedAt: Date = Date()) {
        let completeness = summary.metadataCompleteness ?? GalleryMetadataCompleteness(
            // A summary without explicit completeness predates field-level
            // tracking. Values present in it are known, but absent optional
            // values must remain unresolved so gdata can fill them later.
            title: Self.legacyState(for: summary.title),
            japaneseTitle: Self.legacyState(for: summary.japaneseTitle),
            authors: Self.legacyState(for: Self.authors(from: summary.tags)),
            uploader: Self.legacyState(for: summary.uploader),
            tags: Self.legacyState(for: summary.tags),
            category: Self.legacyState(for: summary.category),
            pageCount: Self.legacyState(for: summary.pageCount),
            postedAt: Self.legacyState(for: summary.postedAt),
            thumbnailURL: Self.legacyState(for: summary.thumbnailURL)
        )
        // A list summary cannot prove that detail-only fields are empty. Keep
        // explicit states (for example a complete transfer record), while
        // legacy summaries naturally retain their `.notLoaded` defaults.
        self.init(
            key: summary.key,
            sourceSite: sourceSite,
            title: summary.title,
            japaneseTitle: summary.japaneseTitle,
            authors: Self.authors(from: summary.tags),
            uploader: summary.uploader,
            tags: summary.tags,
            category: summary.category,
            pageCount: summary.pageCount,
            postedAt: summary.postedAt,
            thumbnailURL: summary.thumbnailURL,
            capturedAt: capturedAt,
            completeness: completeness
        )
    }

    public init(
        detail: GalleryDetail,
        sourceSite: SiteMode,
        capturedAt: Date = Date(),
        includesPreviewPages: Bool = true
    ) {
        var completeness = detail.summary.metadataCompleteness ?? GalleryMetadataCompleteness()
        completeness.title = Self.state(for: detail.summary.title)
        completeness.japaneseTitle = Self.state(for: detail.summary.japaneseTitle)
        completeness.authors = Self.state(for: Self.authors(from: detail.tags))
        completeness.uploader = Self.state(for: detail.summary.uploader)
        completeness.tags = Self.state(for: detail.tags)
        completeness.category = Self.state(for: detail.summary.category)
        completeness.language = Self.state(for: detail.language)
        completeness.pageCount = Self.state(for: detail.summary.pageCount ?? (includesPreviewPages ? detail.pages.count : nil))
        completeness.postedAt = Self.state(for: detail.summary.postedAt)
        completeness.thumbnailURL = Self.state(for: detail.summary.thumbnailURL)
        completeness.fileSize = Self.state(for: detail.fileSize)
        completeness.description = Self.state(for: detail.descriptionText)
        completeness.externalURL = Self.state(for: detail.externalURL)
        completeness.pages = includesPreviewPages ? Self.state(for: detail.pages) : .notLoaded
        if includesPreviewPages == false {
            // The metadata-only endpoint deliberately does not resolve these
            // detail payloads. Keeping them unresolved prevents a lightweight
            // response from masquerading as a complete full-detail snapshot.
            completeness.description = .notLoaded
            completeness.externalURL = .notLoaded
        }
        self.init(
            key: detail.summary.key,
            sourceSite: sourceSite,
            title: detail.summary.title,
            japaneseTitle: detail.summary.japaneseTitle,
            authors: Self.authors(from: detail.tags),
            uploader: detail.summary.uploader,
            tags: detail.tags,
            category: detail.summary.category,
            language: detail.language,
            pageCount: detail.summary.pageCount ?? (includesPreviewPages ? detail.pages.count : nil),
            postedAt: detail.summary.postedAt,
            thumbnailURL: detail.summary.thumbnailURL,
            fileSize: detail.fileSize,
            descriptionText: detail.descriptionText,
            externalURL: detail.externalURL,
            pages: detail.pages,
            capturedAt: capturedAt,
            completeness: completeness
        )
    }

    public var id: String { key.id }

    public var summary: GallerySummary {
        GallerySummary(
            key: key,
            title: title,
            japaneseTitle: japaneseTitle,
            thumbnailURL: thumbnailURL,
            category: category,
            pageCount: pageCount,
            postedAt: postedAt,
            uploader: uploader,
            tags: tags,
            metadataCompleteness: completeness
        )
    }

    public func detail(with dynamic: DownloadedGalleryDynamicSnapshot? = nil) -> GalleryDetail {
        GalleryDetail(
            summary: summaryWithDynamic(dynamic),
            pages: pages,
            tags: tags,
            comments: dynamic?.comments.map(\.galleryComment) ?? [],
            descriptionText: descriptionText,
            externalURL: externalURL,
            favoriteCount: dynamic?.favoriteCount,
            favoriteName: dynamic?.favoriteName,
            ratingCount: dynamic?.ratingCount,
            language: language,
            fileSize: fileSize
        )
    }

    private func summaryWithDynamic(_ dynamic: DownloadedGalleryDynamicSnapshot?) -> GallerySummary {
        var value = summary
        value.rating = dynamic?.rating
        value.ratingCount = dynamic?.ratingCount
        value.favoriteCategory = dynamic?.favoriteCategory
        return value
    }

    public static func authors(from tags: [String]) -> [String] {
        GallerySummary.preferredAuthorTags(from: tags).compactMap { tag in
            guard let separator = tag.firstIndex(of: ":") else { return nil }
            let author = tag[tag.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return author.isEmpty ? nil : author
        }
    }

    private static func state<T>(for value: T?) -> GalleryFieldState {
        value == nil ? .loadedEmpty : .loadedWithValue
    }

    private static func state<T>(for value: [T]) -> GalleryFieldState {
        value.isEmpty ? .loadedEmpty : .loadedWithValue
    }

    private static func state(for value: String) -> GalleryFieldState {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .loadedEmpty
            : .loadedWithValue
    }

    private static func state(for value: Int?) -> GalleryFieldState {
        value == nil ? .loadedEmpty : .loadedWithValue
    }

    private static func legacyState<T>(for value: T?) -> GalleryFieldState {
        value == nil ? .notLoaded : .loadedWithValue
    }

    private static func legacyState<T>(for value: [T]) -> GalleryFieldState {
        value.isEmpty ? .notLoaded : .loadedWithValue
    }

    private static func legacyState(for value: String) -> GalleryFieldState {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .loadedEmpty
            : .loadedWithValue
    }
}

public struct DownloadedGalleryDynamicSnapshot: Codable, Hashable, Sendable, Identifiable {
    public let key: GalleryKey
    public var rating: Double?
    public var ratingCount: Int?
    public var favoriteCount: Int?
    public var favoriteName: String?
    public var favoriteCategory: Int?
    public var comments: [DownloadedGalleryCommentSnapshot]
    public var capturedAt: Date
    public var completeness: GalleryMetadataCompleteness

    public init(
        key: GalleryKey,
        rating: Double? = nil,
        ratingCount: Int? = nil,
        favoriteCount: Int? = nil,
        favoriteName: String? = nil,
        favoriteCategory: Int? = nil,
        comments: [DownloadedGalleryCommentSnapshot] = [],
        capturedAt: Date = Date(),
        completeness: GalleryMetadataCompleteness? = nil
    ) {
        self.key = key
        self.rating = rating
        self.ratingCount = ratingCount
        self.favoriteCount = favoriteCount
        self.favoriteName = favoriteName
        self.favoriteCategory = favoriteCategory
        self.comments = comments
        self.capturedAt = capturedAt
        self.completeness = completeness ?? GalleryMetadataCompleteness(
            rating: rating == nil ? .loadedEmpty : .loadedWithValue,
            ratingCount: ratingCount == nil ? .loadedEmpty : .loadedWithValue,
            favorite: favoriteCount == nil && favoriteName == nil && favoriteCategory == nil
                ? .loadedEmpty
                : .loadedWithValue,
            comments: comments.isEmpty ? .loadedEmpty : .loadedWithValue
        )
    }

    public init(detail: GalleryDetail, capturedAt: Date = Date()) {
        var completeness = detail.summary.metadataCompleteness ?? GalleryMetadataCompleteness()
        completeness.rating = Self.state(for: detail.summary.rating)
        completeness.ratingCount = Self.state(for: detail.summary.ratingCount ?? detail.ratingCount)
        completeness.favorite = Self.state(for: detail.favoriteCount)
        completeness.comments = Self.state(for: detail.comments)
        self.init(
            key: detail.summary.key,
            rating: detail.summary.rating,
            ratingCount: detail.ratingCount ?? detail.summary.ratingCount,
            favoriteCount: detail.favoriteCount,
            favoriteName: detail.favoriteName,
            favoriteCategory: detail.summary.favoriteCategory,
            comments: detail.comments.map(DownloadedGalleryCommentSnapshot.init),
            capturedAt: capturedAt,
            completeness: completeness
        )
    }

    public var id: String { key.id }

    private static func state<T>(for value: T?) -> GalleryFieldState {
        value == nil ? .loadedEmpty : .loadedWithValue
    }

    private static func state<T>(for value: [T]) -> GalleryFieldState {
        value.isEmpty ? .loadedEmpty : .loadedWithValue
    }
}

public struct GalleryTransferRecord: Codable, Hashable, Sendable, Identifiable {
    public static let currentFormatVersion = 2

    public let formatVersion: Int
    public let stable: StableGalleryMetadataSnapshot
    public let dynamic: DownloadedGalleryDynamicSnapshot?
    public let exportedAt: Date
    public let sourceSite: SiteMode

    public init(
        stable: StableGalleryMetadataSnapshot,
        dynamic: DownloadedGalleryDynamicSnapshot? = nil,
        exportedAt: Date = Date(),
        sourceSite: SiteMode? = nil,
        formatVersion: Int = GalleryTransferRecord.currentFormatVersion
    ) throws {
        if let dynamic, dynamic.key != stable.key {
            throw GallerySnapshotError.keyMismatch
        }
        self.formatVersion = formatVersion
        self.stable = stable
        self.dynamic = dynamic
        self.exportedAt = exportedAt
        self.sourceSite = sourceSite ?? stable.sourceSite
    }

    public var id: String { stable.id }

    public init(summary: GallerySummary, sourceSite: SiteMode, exportedAt: Date = Date()) {
        self.formatVersion = Self.currentFormatVersion
        self.stable = StableGalleryMetadataSnapshot(summary: summary, sourceSite: sourceSite, capturedAt: exportedAt)
        self.dynamic = if summary.rating != nil
            || summary.ratingCount != nil
            || summary.favoriteCategory != nil {
            DownloadedGalleryDynamicSnapshot(
                key: summary.key,
                rating: summary.rating,
                ratingCount: summary.ratingCount,
                favoriteCategory: summary.favoriteCategory,
                capturedAt: exportedAt
            )
        } else {
            nil
        }
        self.exportedAt = exportedAt
        self.sourceSite = sourceSite
    }
}

/// Field-level merge used by persistence, cache migration and imports.
public enum GallerySnapshotMerger {
    public static func merge(
        existing: StableGalleryMetadataSnapshot,
        incoming: StableGalleryMetadataSnapshot
    ) -> StableGalleryMetadataSnapshot {
        guard existing.key == incoming.key else { return existing }
        let incomingIsNewer = incoming.capturedAt >= existing.capturedAt
        var merged = existing
        merged.sourceSite = incomingIsNewer ? incoming.sourceSite : existing.sourceSite
        merged.capturedAt = max(existing.capturedAt, incoming.capturedAt)
        mergeField(&merged.title, &merged.completeness.title, incoming.title, incoming.completeness.title, existing.completeness.title, incomingIsNewer)
        mergeField(&merged.japaneseTitle, &merged.completeness.japaneseTitle, incoming.japaneseTitle, incoming.completeness.japaneseTitle, existing.completeness.japaneseTitle, incomingIsNewer)
        mergeField(&merged.authors, &merged.completeness.authors, incoming.authors, incoming.completeness.authors, existing.completeness.authors, incomingIsNewer)
        mergeField(&merged.uploader, &merged.completeness.uploader, incoming.uploader, incoming.completeness.uploader, existing.completeness.uploader, incomingIsNewer)
        mergeField(&merged.tags, &merged.completeness.tags, incoming.tags, incoming.completeness.tags, existing.completeness.tags, incomingIsNewer)
        mergeField(&merged.category, &merged.completeness.category, incoming.category, incoming.completeness.category, existing.completeness.category, incomingIsNewer)
        mergeField(&merged.language, &merged.completeness.language, incoming.language, incoming.completeness.language, existing.completeness.language, incomingIsNewer)
        mergeField(&merged.pageCount, &merged.completeness.pageCount, incoming.pageCount, incoming.completeness.pageCount, existing.completeness.pageCount, incomingIsNewer)
        mergeField(&merged.postedAt, &merged.completeness.postedAt, incoming.postedAt, incoming.completeness.postedAt, existing.completeness.postedAt, incomingIsNewer)
        mergeField(&merged.thumbnailURL, &merged.completeness.thumbnailURL, incoming.thumbnailURL, incoming.completeness.thumbnailURL, existing.completeness.thumbnailURL, incomingIsNewer)
        mergeField(&merged.fileSize, &merged.completeness.fileSize, incoming.fileSize, incoming.completeness.fileSize, existing.completeness.fileSize, incomingIsNewer)
        mergeField(&merged.descriptionText, &merged.completeness.description, incoming.descriptionText, incoming.completeness.description, existing.completeness.description, incomingIsNewer)
        mergeField(&merged.externalURL, &merged.completeness.externalURL, incoming.externalURL, incoming.completeness.externalURL, existing.completeness.externalURL, incomingIsNewer)
        mergeField(&merged.pages, &merged.completeness.pages, incoming.pages, incoming.completeness.pages, existing.completeness.pages, incomingIsNewer)
        return merged
    }

    public static func merge(
        existing: DownloadedGalleryDynamicSnapshot?,
        incoming: DownloadedGalleryDynamicSnapshot
    ) -> DownloadedGalleryDynamicSnapshot {
        guard let existing, existing.key == incoming.key else { return incoming }
        let incomingIsNewer = incoming.capturedAt >= existing.capturedAt
        var merged = existing
        merged.capturedAt = max(existing.capturedAt, incoming.capturedAt)
        mergeField(&merged.rating, &merged.completeness.rating, incoming.rating, incoming.completeness.rating, existing.completeness.rating, incomingIsNewer)
        mergeField(&merged.ratingCount, &merged.completeness.ratingCount, incoming.ratingCount, incoming.completeness.ratingCount, existing.completeness.ratingCount, incomingIsNewer)
        mergeField(&merged.favoriteCount, &merged.completeness.favorite, incoming.favoriteCount, incoming.completeness.favorite, existing.completeness.favorite, incomingIsNewer)
        if incoming.completeness.favorite.isLoaded && incomingIsNewer {
            merged.favoriteName = incoming.favoriteName
            merged.favoriteCategory = incoming.favoriteCategory
        }
        mergeField(&merged.comments, &merged.completeness.comments, incoming.comments, incoming.completeness.comments, existing.completeness.comments, incomingIsNewer)
        return merged
    }

    private static func mergeField<T>(
        _ value: inout T,
        _ state: inout GalleryFieldState,
        _ incomingValue: T,
        _ incomingState: GalleryFieldState,
        _ existingState: GalleryFieldState,
        _ incomingIsNewer: Bool
    ) {
        guard incomingState.isLoaded else { return }
        if existingState.isLoaded == false || incomingIsNewer {
            value = incomingValue
            state = incomingState
        }
    }
}
