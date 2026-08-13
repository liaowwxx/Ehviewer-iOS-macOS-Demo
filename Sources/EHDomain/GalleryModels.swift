import Foundation

public enum SiteMode: String, CaseIterable, Codable, Hashable, Sendable {
    case eHentai = "e-hentai"
    case exHentai = "exhentai"

    public var displayName: String {
        switch self {
        case .eHentai: "E-Hentai"
        case .exHentai: "ExHentai"
        }
    }

    public var host: String {
        switch self {
        case .eHentai: "e-hentai.org"
        case .exHentai: "exhentai.org"
        }
    }

    public var imageSearchURL: URL {
        switch self {
        case .eHentai: URL(string: "https://upld.e-hentai.org/image_lookup.php")!
        case .exHentai: URL(string: "https://upld.exhentai.org/upld/image_lookup.php")!
        }
    }
}

public enum ImageResolution: String, CaseIterable, Codable, Hashable, Sendable {
    case preview
    case original
}

public struct ImageSearchOptions: Hashable, Codable, Sendable {
    public var similar: Bool
    public var covers: Bool
    public var expanded: Bool

    public init(similar: Bool = true, covers: Bool = false, expanded: Bool = false) {
        self.similar = similar
        self.covers = covers
        self.expanded = expanded
    }
}

public struct ImageQuota: Hashable, Codable, Sendable {
    public let used: Int64
    public let total: Int64
    public let resetCost: Int64

    public init(used: Int64, total: Int64, resetCost: Int64) {
        self.used = used
        self.total = total
        self.resetCost = resetCost
    }
}

public struct LoginResult: Hashable, Codable, Sendable {
    public let displayName: String

    public init(displayName: String) {
        self.displayName = displayName
    }
}

public struct GalleryKey: Hashable, Codable, Sendable, Identifiable {
    public let gid: Int64
    public let token: String

    public init(gid: Int64, token: String) {
        self.gid = gid
        self.token = token
    }

    public var id: String { "\(gid)-\(token)" }
}

public struct GallerySummary: Identifiable, Hashable, Codable, Sendable {
    public let key: GalleryKey
    public var title: String
    public var secondaryTitle: String?
    public var thumbnailURL: URL?
    public var category: String?
    public var pageCount: Int?
    public var postedAt: Date?
    public var rating: Double?
    public var ratingCount: Int?
    public var favoriteCategory: Int?
    public var tags: [String]

    public init(
        key: GalleryKey,
        title: String,
        secondaryTitle: String? = nil,
        thumbnailURL: URL? = nil,
        category: String? = nil,
        pageCount: Int? = nil,
        postedAt: Date? = nil,
        rating: Double? = nil,
        ratingCount: Int? = nil,
        favoriteCategory: Int? = nil,
        tags: [String] = []
    ) {
        self.key = key
        self.title = title
        self.secondaryTitle = secondaryTitle
        self.thumbnailURL = thumbnailURL
        self.category = category
        self.pageCount = pageCount
        self.postedAt = postedAt
        self.rating = rating
        self.ratingCount = ratingCount
        self.favoriteCategory = favoriteCategory
        self.tags = tags
    }

    public var id: String { key.id }
}

public struct GalleryPageDescriptor: Identifiable, Hashable, Codable, Sendable {
    public let galleryKey: GalleryKey
    public let index: Int
    public let pageURL: URL
    public let previewURL: URL?

    public init(galleryKey: GalleryKey, index: Int, pageURL: URL, previewURL: URL? = nil) {
        self.galleryKey = galleryKey
        self.index = index
        self.pageURL = pageURL
        self.previewURL = previewURL
    }

    public var id: String { "\(galleryKey.id)-\(index)" }
}

public struct GalleryPageImage: Identifiable, Hashable, Codable, Sendable {
    public let galleryKey: GalleryKey
    public let index: Int
    public let imageURL: URL
    public let originImageURL: URL?
    public let fileName: String?
    public let width: Int?
    public let height: Int?
    public let byteCount: Int64?
    public let skipHathKey: String?
    public let showKey: String?

    public init(
        galleryKey: GalleryKey,
        index: Int,
        imageURL: URL,
        originImageURL: URL? = nil,
        fileName: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        byteCount: Int64? = nil,
        skipHathKey: String? = nil,
        showKey: String? = nil
    ) {
        self.galleryKey = galleryKey
        self.index = index
        self.imageURL = imageURL
        self.originImageURL = originImageURL
        self.fileName = fileName
        self.width = width
        self.height = height
        self.byteCount = byteCount
        self.skipHathKey = skipHathKey
        self.showKey = showKey
    }

    public var id: String { "\(galleryKey.id)-\(index)" }
}

public struct GalleryDetail: Identifiable, Hashable, Codable, Sendable {
    public let summary: GallerySummary
    public var pages: [GalleryPageDescriptor]
    public var tags: [String]
    public var comments: [GalleryComment]
    public var descriptionText: String?
    public var externalURL: URL?
    public var apiUID: Int64?
    public var apiKey: String?
    public var favoriteCount: Int?
    public var favoriteName: String?
    public var ratingCount: Int?
    public var torrentURL: URL?
    public var torrentCount: Int?
    public var archiveURL: URL?

    public init(
        summary: GallerySummary,
        pages: [GalleryPageDescriptor] = [],
        tags: [String] = [],
        comments: [GalleryComment] = [],
        descriptionText: String? = nil,
        externalURL: URL? = nil,
        apiUID: Int64? = nil,
        apiKey: String? = nil,
        favoriteCount: Int? = nil,
        favoriteName: String? = nil,
        ratingCount: Int? = nil,
        torrentURL: URL? = nil,
        torrentCount: Int? = nil,
        archiveURL: URL? = nil
    ) {
        self.summary = summary
        self.pages = pages
        self.tags = tags
        self.comments = comments
        self.descriptionText = descriptionText
        self.externalURL = externalURL
        self.apiUID = apiUID
        self.apiKey = apiKey
        self.favoriteCount = favoriteCount
        self.favoriteName = favoriteName
        self.ratingCount = ratingCount
        self.torrentURL = torrentURL
        self.torrentCount = torrentCount
        self.archiveURL = archiveURL
    }

    public var id: String { summary.id }
}

public struct GalleryComment: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let author: String
    public let body: String
    public let postedAt: Date?
    public var score: Int
    public var voteState: String?
    public var isEditable: Bool
    public var canVoteUp: Bool
    public var canVoteDown: Bool

    public init(
        id: String,
        author: String,
        body: String,
        postedAt: Date? = nil,
        score: Int = 0,
        voteState: String? = nil,
        isEditable: Bool = false,
        canVoteUp: Bool = false,
        canVoteDown: Bool = false
    ) {
        self.id = id
        self.author = author
        self.body = body
        self.postedAt = postedAt
        self.score = score
        self.voteState = voteState
        self.isEditable = isEditable
        self.canVoteUp = canVoteUp
        self.canVoteDown = canVoteDown
    }
}

public struct GalleryRating: Hashable, Codable, Sendable {
    public let average: Double
    public let count: Int

    public init(average: Double, count: Int) {
        self.average = average
        self.count = count
    }
}

public struct CommentVoteResult: Hashable, Codable, Sendable {
    public let commentID: String
    public let score: Int
    public let vote: Int
    public let expectedVote: Int

    public init(commentID: String, score: Int, vote: Int, expectedVote: Int) {
        self.commentID = commentID
        self.score = score
        self.vote = vote
        self.expectedVote = expectedVote
    }
}

public struct TorrentDescriptor: Identifiable, Hashable, Codable, Sendable {
    public let url: URL
    public let name: String
    public let postedAt: String?

    public init(url: URL, name: String, postedAt: String? = nil) {
        self.url = url
        self.name = name
        self.postedAt = postedAt
    }

    public var id: String { url.absoluteString }
}

public struct ArchiveOption: Identifiable, Hashable, Codable, Sendable {
    public let resolution: String
    public let name: String

    public init(resolution: String, name: String) {
        self.resolution = resolution
        self.name = name
    }

    public var id: String { resolution }
}

public struct WatchedTag: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var name: String
    public var isWatched: Bool
    public var isHidden: Bool
    public var color: String?
    public var weight: Int

    public init(id: String, name: String, isWatched: Bool, isHidden: Bool, color: String? = nil, weight: Int = 0) {
        self.id = id
        self.name = name
        self.isWatched = isWatched
        self.isHidden = isHidden
        self.color = color
        self.weight = weight
    }
}

public struct GalleryListQuery: Hashable, Codable, Sendable {
    public var site: SiteMode
    public var kind: ListKind
    public var searchText: String?
    public var page: Int
    public var sort: SortOrder
    public var category: String?
    public var favoriteCategory: Int?
    public var advancedSearch: GalleryAdvancedSearch?

    public init(
        site: SiteMode = .eHentai,
        kind: ListKind = .home,
        searchText: String? = nil,
        page: Int = 0,
        sort: SortOrder = .newest,
        category: String? = nil,
        favoriteCategory: Int? = nil,
        advancedSearch: GalleryAdvancedSearch? = nil
    ) {
        self.site = site
        self.kind = kind
        self.searchText = searchText
        self.page = page
        self.sort = sort
        self.category = category
        self.favoriteCategory = favoriteCategory
        self.advancedSearch = advancedSearch
    }

    public enum ListKind: String, Codable, CaseIterable, Hashable, Sendable {
        case home
        case subscriptions
        case popular
        case toplist
        case search
        case favorites
    }

    public enum SortOrder: String, Codable, CaseIterable, Hashable, Sendable {
        case newest
        case popular
        case rating
    }
}

public enum GalleryCategory: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case doujinshi = "Doujinshi"
    case manga = "Manga"
    case artistCG = "Artist CG"
    case gameCG = "Game CG"
    case western = "Western"
    case nonH = "Non-H"
    case imageSet = "Image Set"
    case cosplay = "Cosplay"
    case asianPorn = "Asian Porn"
    case misc = "Misc"

    public var id: Self { self }

    public var bitMask: Int {
        switch self {
        case .misc: 0x001
        case .doujinshi: 0x002
        case .manga: 0x004
        case .artistCG: 0x008
        case .gameCG: 0x010
        case .imageSet: 0x020
        case .cosplay: 0x040
        case .asianPorn: 0x080
        case .nonH: 0x100
        case .western: 0x200
        }
    }
}

public struct GalleryAdvancedSearch: Hashable, Codable, Sendable {
    public static let allCategoryMask = 0x3ff

    public var categories: Set<GalleryCategory>
    public var onlyWithTorrents: Bool
    public var onlyShowExpunged: Bool
    public var minimumRating: Int
    public var minimumPageCount: Int
    public var maximumPageCount: Int
    public var disableLanguageFilter: Bool
    public var disableUploaderFilter: Bool
    public var disableTagFilter: Bool

    public init(
        categories: Set<GalleryCategory> = Set(GalleryCategory.allCases),
        onlyWithTorrents: Bool = false,
        onlyShowExpunged: Bool = false,
        minimumRating: Int = 0,
        minimumPageCount: Int = 0,
        maximumPageCount: Int = 0,
        disableLanguageFilter: Bool = false,
        disableUploaderFilter: Bool = false,
        disableTagFilter: Bool = false
    ) {
        self.categories = categories
        self.onlyWithTorrents = onlyWithTorrents
        self.onlyShowExpunged = onlyShowExpunged
        self.minimumRating = minimumRating
        self.minimumPageCount = minimumPageCount
        self.maximumPageCount = maximumPageCount
        self.disableLanguageFilter = disableLanguageFilter
        self.disableUploaderFilter = disableUploaderFilter
        self.disableTagFilter = disableTagFilter
    }

    public var excludedCategoryMask: Int? {
        let includedMask = categories.reduce(0) { $0 | $1.bitMask }
        let excludedMask = Self.allCategoryMask & ~includedMask
        return excludedMask == 0 ? nil : excludedMask
    }

    public var hasValidPageRange: Bool {
        minimumPageCount >= 0 && maximumPageCount >= 0
            && (minimumPageCount == 0 || maximumPageCount == 0 || minimumPageCount <= maximumPageCount)
    }

    public mutating func toggle(_ category: GalleryCategory) {
        if categories.contains(category) {
            categories.remove(category)
        } else {
            categories.insert(category)
        }
    }
}

public struct GalleryCursor: Hashable, Codable, Sendable {
    public let page: Int
    public let nextPageURL: URL?

    public init(page: Int, nextPageURL: URL? = nil) {
        self.page = page
        self.nextPageURL = nextPageURL
    }
}

public struct GalleryListPage: Hashable, Codable, Sendable {
    public let items: [GallerySummary]
    public let cursor: GalleryCursor?

    public init(items: [GallerySummary], cursor: GalleryCursor? = nil) {
        self.items = items
        self.cursor = cursor
    }
}

public enum AppRoute: Hashable, Codable, Sendable {
    case browse
    case subscriptions
    case popular
    case toplist
    case downloads
    case history
    case favorites
    case settings
    case gallery(GalleryKey)
    case reader(GalleryKey, page: Int)
}
