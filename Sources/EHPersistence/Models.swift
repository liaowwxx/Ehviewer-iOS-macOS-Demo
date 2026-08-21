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
import SwiftData
import EHDomain

@Model
public final class GalleryRecord {
    #Index<GalleryRecord>([\.gid], [\.lastReadAt])

    public var gid: Int64
    public var token: String
    public var title: String
    public var japaneseTitle: String?
    public var thumbnailURLString: String?
    public var category: String?
    public var pageCount: Int?
    public var postedAt: Date?
    public var rating: Double?
    public var ratingCount: Int?
    public var favoriteCategory: Int?
    public var uploader: String?
    public var lastReadAt: Date?
    public var lastReadPage: Int
    public var isFavorite: Bool
    public var tags: [String]
    public var metadataTitleComplete: Bool = false
    public var metadataJapaneseTitleComplete: Bool = false
    public var metadataTagsComplete: Bool = false
    public var cacheRetention: Bool = true
    public var downloadRetention: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \StableGalleryMetadataRecord.gallery)
    public var stableMetadata: StableGalleryMetadataRecord?

    @Relationship(deleteRule: .cascade, inverse: \DownloadedGalleryDynamicRecord.gallery)
    public var dynamicSnapshot: DownloadedGalleryDynamicRecord?

    public init(snapshot: GallerySummary, lastReadPage: Int = 0, lastReadAt: Date? = nil, isFavorite: Bool = false) {
        gid = snapshot.key.gid
        token = snapshot.key.token
        title = snapshot.title
        japaneseTitle = snapshot.japaneseTitle
        thumbnailURLString = snapshot.thumbnailURL?.absoluteString
        category = snapshot.category
        pageCount = snapshot.pageCount
        postedAt = snapshot.postedAt
        rating = snapshot.rating
        ratingCount = snapshot.ratingCount
        favoriteCategory = snapshot.favoriteCategory
        uploader = snapshot.uploader
        self.lastReadPage = lastReadPage
        self.lastReadAt = lastReadAt
        self.isFavorite = isFavorite
        tags = snapshot.tags
        metadataTitleComplete = snapshot.metadataCompleteness?.title.isLoaded ?? false
        metadataJapaneseTitleComplete = snapshot.metadataCompleteness?.japaneseTitle.isLoaded ?? false
        metadataTagsComplete = snapshot.metadataCompleteness?.tags.isLoaded ?? false
    }

    public var key: GalleryKey { GalleryKey(gid: gid, token: token) }
    public var thumbnailURL: URL? { thumbnailURLString.flatMap(URL.init(string:)) }

    public func update(from snapshot: GallerySummary) {
        title = snapshot.title
        japaneseTitle = snapshot.japaneseTitle
        thumbnailURLString = snapshot.thumbnailURL?.absoluteString
        category = snapshot.category
        pageCount = snapshot.pageCount
        postedAt = snapshot.postedAt
        rating = snapshot.rating
        ratingCount = snapshot.ratingCount
        favoriteCategory = snapshot.favoriteCategory
        uploader = snapshot.uploader
        tags = snapshot.tags
        if let completeness = snapshot.metadataCompleteness {
            metadataTitleComplete = completeness.title.isLoaded
            metadataJapaneseTitleComplete = completeness.japaneseTitle.isLoaded
            metadataTagsComplete = completeness.tags.isLoaded
        }
    }
}

/// Normalized, field-level stable content. The legacy scalar fields on
/// `GalleryRecord` remain readable for migration compatibility; new code uses
/// this record as the canonical ordinary-cache/download metadata source.
@Model
public final class StableGalleryMetadataRecord {
    #Index<StableGalleryMetadataRecord>([\.gid, \.token], [\.capturedAt])

    public var gid: Int64
    public var token: String
    public var sourceSiteRaw: String
    public var title: String
    public var japaneseTitle: String?
    public var authors: [String]
    public var uploader: String?
    public var tags: [String]
    public var category: String?
    public var language: String?
    public var pageCount: Int?
    public var postedAt: Date?
    public var thumbnailURLString: String?
    public var fileSize: String?
    public var descriptionText: String?
    public var externalURLString: String?
    public var capturedAt: Date

    public var titleStateRaw: String
    public var japaneseTitleStateRaw: String
    public var authorsStateRaw: String
    public var uploaderStateRaw: String
    public var tagsStateRaw: String
    public var categoryStateRaw: String
    public var languageStateRaw: String
    public var pageCountStateRaw: String
    public var postedAtStateRaw: String
    public var thumbnailURLStateRaw: String
    public var fileSizeStateRaw: String
    public var descriptionStateRaw: String
    public var externalURLStateRaw: String
    public var pagesStateRaw: String

    @Relationship(deleteRule: .cascade, inverse: \GalleryPreviewPageRecord.metadata)
    public var pages: [GalleryPreviewPageRecord] = []
    public var gallery: GalleryRecord?

    public init(snapshot: StableGalleryMetadataSnapshot) {
        gid = snapshot.key.gid
        token = snapshot.key.token
        sourceSiteRaw = snapshot.sourceSite.rawValue
        title = snapshot.title
        japaneseTitle = snapshot.japaneseTitle
        authors = snapshot.authors
        uploader = snapshot.uploader
        tags = snapshot.tags
        category = snapshot.category
        language = snapshot.language
        pageCount = snapshot.pageCount
        postedAt = snapshot.postedAt
        thumbnailURLString = snapshot.thumbnailURL?.absoluteString
        fileSize = snapshot.fileSize
        descriptionText = snapshot.descriptionText
        externalURLString = snapshot.externalURL?.absoluteString
        capturedAt = snapshot.capturedAt
        titleStateRaw = snapshot.completeness.title.rawValue
        japaneseTitleStateRaw = snapshot.completeness.japaneseTitle.rawValue
        authorsStateRaw = snapshot.completeness.authors.rawValue
        uploaderStateRaw = snapshot.completeness.uploader.rawValue
        tagsStateRaw = snapshot.completeness.tags.rawValue
        categoryStateRaw = snapshot.completeness.category.rawValue
        languageStateRaw = snapshot.completeness.language.rawValue
        pageCountStateRaw = snapshot.completeness.pageCount.rawValue
        postedAtStateRaw = snapshot.completeness.postedAt.rawValue
        thumbnailURLStateRaw = snapshot.completeness.thumbnailURL.rawValue
        fileSizeStateRaw = snapshot.completeness.fileSize.rawValue
        descriptionStateRaw = snapshot.completeness.description.rawValue
        externalURLStateRaw = snapshot.completeness.externalURL.rawValue
        pagesStateRaw = snapshot.completeness.pages.rawValue
    }

    public var key: GalleryKey { GalleryKey(gid: gid, token: token) }

    public func update(from snapshot: StableGalleryMetadataSnapshot) {
        sourceSiteRaw = snapshot.sourceSite.rawValue
        title = snapshot.title
        japaneseTitle = snapshot.japaneseTitle
        authors = snapshot.authors
        uploader = snapshot.uploader
        tags = snapshot.tags
        category = snapshot.category
        language = snapshot.language
        pageCount = snapshot.pageCount
        postedAt = snapshot.postedAt
        thumbnailURLString = snapshot.thumbnailURL?.absoluteString
        fileSize = snapshot.fileSize
        descriptionText = snapshot.descriptionText
        externalURLString = snapshot.externalURL?.absoluteString
        capturedAt = snapshot.capturedAt
        let completeness = snapshot.completeness
        titleStateRaw = completeness.title.rawValue
        japaneseTitleStateRaw = completeness.japaneseTitle.rawValue
        authorsStateRaw = completeness.authors.rawValue
        uploaderStateRaw = completeness.uploader.rawValue
        tagsStateRaw = completeness.tags.rawValue
        categoryStateRaw = completeness.category.rawValue
        languageStateRaw = completeness.language.rawValue
        pageCountStateRaw = completeness.pageCount.rawValue
        postedAtStateRaw = completeness.postedAt.rawValue
        thumbnailURLStateRaw = completeness.thumbnailURL.rawValue
        fileSizeStateRaw = completeness.fileSize.rawValue
        descriptionStateRaw = completeness.description.rawValue
        externalURLStateRaw = completeness.externalURL.rawValue
        pagesStateRaw = completeness.pages.rawValue
    }
}

@Model
public final class GalleryPreviewPageRecord {
    #Index<GalleryPreviewPageRecord>([\.gid, \.token], [\.pageIndex])

    public var gid: Int64
    public var token: String
    public var pageIndex: Int
    public var pageURLString: String
    public var previewURLString: String?
    public var clipXOffset: Int?
    public var clipWidth: Int?
    public var clipHeight: Int?
    public var metadata: StableGalleryMetadataRecord?

    public init(page: GalleryPageDescriptor) {
        gid = page.galleryKey.gid
        token = page.galleryKey.token
        pageIndex = page.index
        pageURLString = page.pageURL.absoluteString
        previewURLString = page.previewURL?.absoluteString
        clipXOffset = page.previewClip?.xOffset
        clipWidth = page.previewClip?.width
        clipHeight = page.previewClip?.height
    }

    public var descriptor: GalleryPageDescriptor? {
        guard let pageURL = URL(string: pageURLString) else { return nil }
        let clip: GalleryPreviewClip?
        if let clipXOffset, let clipWidth, let clipHeight {
            clip = GalleryPreviewClip(xOffset: clipXOffset, width: clipWidth, height: clipHeight)
        } else {
            clip = nil
        }
        return GalleryPageDescriptor(
            galleryKey: GalleryKey(gid: gid, token: token),
            index: pageIndex,
            pageURL: pageURL,
            previewURL: previewURLString.flatMap(URL.init(string:)),
            previewClip: clip
        )
    }
}

@Model
public final class DownloadedGalleryDynamicRecord {
    #Index<DownloadedGalleryDynamicRecord>([\.gid, \.token], [\.capturedAt])

    public var gid: Int64
    public var token: String
    public var rating: Double?
    public var ratingCount: Int?
    public var favoriteCount: Int?
    public var favoriteName: String?
    public var favoriteCategory: Int?
    public var commentsData: Data
    public var capturedAt: Date
    public var ratingStateRaw: String
    public var ratingCountStateRaw: String
    public var favoriteStateRaw: String
    public var commentsStateRaw: String
    public var gallery: GalleryRecord?

    public init(snapshot: DownloadedGalleryDynamicSnapshot) {
        gid = snapshot.key.gid
        token = snapshot.key.token
        rating = snapshot.rating
        ratingCount = snapshot.ratingCount
        favoriteCount = snapshot.favoriteCount
        favoriteName = snapshot.favoriteName
        favoriteCategory = snapshot.favoriteCategory
        commentsData = (try? JSONEncoder().encode(snapshot.comments)) ?? Data()
        capturedAt = snapshot.capturedAt
        ratingStateRaw = snapshot.completeness.rating.rawValue
        ratingCountStateRaw = snapshot.completeness.ratingCount.rawValue
        favoriteStateRaw = snapshot.completeness.favorite.rawValue
        commentsStateRaw = snapshot.completeness.comments.rawValue
    }

    public var key: GalleryKey { GalleryKey(gid: gid, token: token) }

    public func update(from snapshot: DownloadedGalleryDynamicSnapshot) {
        rating = snapshot.rating
        ratingCount = snapshot.ratingCount
        favoriteCount = snapshot.favoriteCount
        favoriteName = snapshot.favoriteName
        favoriteCategory = snapshot.favoriteCategory
        commentsData = (try? JSONEncoder().encode(snapshot.comments)) ?? Data()
        capturedAt = snapshot.capturedAt
        ratingStateRaw = snapshot.completeness.rating.rawValue
        ratingCountStateRaw = snapshot.completeness.ratingCount.rawValue
        favoriteStateRaw = snapshot.completeness.favorite.rawValue
        commentsStateRaw = snapshot.completeness.comments.rawValue
    }
}

@Model
public final class GalleryImageIndexRecord {
    #Index<GalleryImageIndexRecord>([\.gid, \.token], [\.lastAccessedAt])

    public var gid: Int64
    public var token: String
    public var siteRaw: String
    public var kindRaw: String
    public var pageIndex: Int?
    public var originalURLString: String
    public var localPath: String
    public var byteCount: Int64
    public var lastAccessedAt: Date

    public init(
        key: GalleryKey,
        site: SiteMode,
        kind: String,
        pageIndex: Int? = nil,
        originalURL: URL,
        localPath: String,
        byteCount: Int64,
        lastAccessedAt: Date = Date()
    ) {
        gid = key.gid
        token = key.token
        siteRaw = site.rawValue
        kindRaw = kind
        self.pageIndex = pageIndex
        originalURLString = originalURL.absoluteString
        self.localPath = localPath
        self.byteCount = max(0, byteCount)
        self.lastAccessedAt = lastAccessedAt
    }
}

@Model
public final class DownloadJobRecord {
    #Index<DownloadJobRecord>([\.gid], [\.stateRaw], [\.updatedAt])

    public var gid: Int64
    public var token: String
    public var title: String
    public var japaneseTitle: String?
    public var totalPages: Int
    public var completedPages: Int
    public var stateRaw: String
    public var label: String?
    public var errorMessage: String?
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \DownloadPageRecord.job)
    public var pages: [DownloadPageRecord] = []

    public init(key: GalleryKey, title: String, japaneseTitle: String? = nil, totalPages: Int) {
        gid = key.gid
        token = key.token
        self.title = title
        self.japaneseTitle = japaneseTitle
        self.totalPages = totalPages
        completedPages = 0
        stateRaw = "queued"
        createdAt = Date()
        updatedAt = Date()
    }

    public var key: GalleryKey { GalleryKey(gid: gid, token: token) }
}

@Model
public final class DownloadPageRecord {
    public var pageIndex: Int
    public var fileName: String
    public var bytes: Int64
    public var directURLString: String?
    public var previewURLString: String?
    public var stateRaw: String
    public var retryCount: Int
    public var backgroundTaskIdentifier: Int?
    public var job: DownloadJobRecord?

    public init(pageIndex: Int, fileName: String) {
        self.pageIndex = pageIndex
        self.fileName = fileName
        bytes = 0
        stateRaw = "queued"
        retryCount = 0
        backgroundTaskIdentifier = nil
    }
}

@Model
public final class DownloadLabelRecord {
    #Index<DownloadLabelRecord>([\.name])
    public var name: String
    public var createdAt: Date

    public init(name: String) {
        self.name = name
        createdAt = Date()
    }
}

@Model
public final class QuickSearchRecord {
    #Index<QuickSearchRecord>([\.query], [\.lastUsedAt])
    public var query: String
    public var lastUsedAt: Date

    public init(query: String) {
        self.query = query
        lastUsedAt = Date()
    }
}

@Model
public final class FilterRuleRecord {
    #Index<FilterRuleRecord>([\.pattern])
    public var pattern: String
    public var isEnabled: Bool
    public var modeRaw: String

    public init(pattern: String, isEnabled: Bool = true, mode: GalleryFilterMode = .title) {
        self.pattern = pattern
        self.isEnabled = isEnabled
        modeRaw = mode.rawValue
    }
}

@Model
public final class TagTranslationRecord {
    #Index<TagTranslationRecord>([\.tag], [\.locale])
    public var tag: String
    public var locale: String
    public var localizedText: String
    public var updatedAt: Date

    public init(tag: String, locale: String, localizedText: String) {
        self.tag = tag
        self.locale = locale
        self.localizedText = localizedText
        updatedAt = Date()
    }
}
