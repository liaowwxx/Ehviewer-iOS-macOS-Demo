import Foundation
import SwiftData
import EHDomain

@Model
public final class GalleryRecord {
    #Index<GalleryRecord>([\.gid], [\.lastReadAt])

    public var gid: Int64
    public var token: String
    public var title: String
    public var secondaryTitle: String?
    public var thumbnailURLString: String?
    public var category: String?
    public var pageCount: Int?
    public var postedAt: Date?
    public var rating: Double?
    public var ratingCount: Int?
    public var favoriteCategory: Int?
    public var lastReadAt: Date?
    public var lastReadPage: Int
    public var isFavorite: Bool
    public var tags: [String]

    public init(snapshot: GallerySummary, lastReadPage: Int = 0, lastReadAt: Date? = nil, isFavorite: Bool = false) {
        gid = snapshot.key.gid
        token = snapshot.key.token
        title = snapshot.title
        secondaryTitle = snapshot.secondaryTitle
        thumbnailURLString = snapshot.thumbnailURL?.absoluteString
        category = snapshot.category
        pageCount = snapshot.pageCount
        postedAt = snapshot.postedAt
        rating = snapshot.rating
        ratingCount = snapshot.ratingCount
        favoriteCategory = snapshot.favoriteCategory
        self.lastReadPage = lastReadPage
        self.lastReadAt = lastReadAt
        self.isFavorite = isFavorite
        tags = snapshot.tags
    }

    public var key: GalleryKey { GalleryKey(gid: gid, token: token) }
    public var thumbnailURL: URL? { thumbnailURLString.flatMap(URL.init(string:)) }

    public func update(from snapshot: GallerySummary) {
        title = snapshot.title
        secondaryTitle = snapshot.secondaryTitle
        thumbnailURLString = snapshot.thumbnailURL?.absoluteString
        category = snapshot.category
        pageCount = snapshot.pageCount
        postedAt = snapshot.postedAt
        rating = snapshot.rating
        ratingCount = snapshot.ratingCount
        favoriteCategory = snapshot.favoriteCategory
        tags = snapshot.tags
    }
}

@Model
public final class DownloadJobRecord {
    #Index<DownloadJobRecord>([\.gid], [\.stateRaw], [\.updatedAt])

    public var gid: Int64
    public var token: String
    public var title: String
    public var totalPages: Int
    public var completedPages: Int
    public var stateRaw: String
    public var label: String?
    public var errorMessage: String?
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \DownloadPageRecord.job)
    public var pages: [DownloadPageRecord] = []

    public init(key: GalleryKey, title: String, totalPages: Int) {
        gid = key.gid
        token = key.token
        self.title = title
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

    public init(pattern: String, isEnabled: Bool = true) {
        self.pattern = pattern
        self.isEnabled = isEnabled
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
