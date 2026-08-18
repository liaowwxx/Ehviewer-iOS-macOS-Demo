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
import CoreGraphics

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

/// Records whether each transferable gallery metadata field contains usable
/// data. A gallery is complete when tags are known and at least one of the
/// ordinary or Japanese titles is present; some galleries legitimately expose
/// only one title variant.
public struct GalleryMetadataCompleteness: Codable, Hashable, Sendable {
    public var title: Bool
    public var japaneseTitle: Bool
    public var tags: Bool

    public var isComplete: Bool {
        tags && (title || japaneseTitle)
    }

    public static let complete = GalleryMetadataCompleteness(
        title: true,
        japaneseTitle: true,
        tags: true
    )

    public init(
        title: Bool = false,
        japaneseTitle: Bool = false,
        tags: Bool = false
    ) {
        self.title = title
        self.japaneseTitle = japaneseTitle
        self.tags = tags
    }
}

public struct GallerySummary: Identifiable, Hashable, Codable, Sendable {
    public let key: GalleryKey
    public var title: String
    public var japaneseTitle: String?
    public var thumbnailURL: URL?
    public var category: String?
    public var pageCount: Int?
    public var postedAt: Date?
    public var rating: Double?
    public var ratingCount: Int?
    public var favoriteCategory: Int?
    public var uploader: String?
    public var tags: [String]
    /// Nil means the summary predates per-field completeness tracking.
    public var metadataCompleteness: GalleryMetadataCompleteness?

    public init(
        key: GalleryKey,
        title: String,
        japaneseTitle: String? = nil,
        thumbnailURL: URL? = nil,
        category: String? = nil,
        pageCount: Int? = nil,
        postedAt: Date? = nil,
        rating: Double? = nil,
        ratingCount: Int? = nil,
        favoriteCategory: Int? = nil,
        uploader: String? = nil,
        tags: [String] = [],
        metadataCompleteness: GalleryMetadataCompleteness? = nil
    ) {
        self.key = key
        self.title = title
        self.japaneseTitle = japaneseTitle
        self.thumbnailURL = thumbnailURL
        self.category = category
        self.pageCount = pageCount
        self.postedAt = postedAt
        self.rating = rating
        self.ratingCount = ratingCount
        self.favoriteCategory = favoriteCategory
        self.uploader = uploader
        self.tags = tags
        self.metadataCompleteness = metadataCompleteness
    }

    public var id: String { key.id }

    /// Mirrors the reference client's `EhUtils.getSuitableTitle`: when the
    /// Japanese-title preference is on the Japanese title wins (falling back to
    /// the ordinary title), otherwise the ordinary title wins.
    public func displayTitle(showJapaneseTitle: Bool) -> String {
        let japanese = japaneseTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if showJapaneseTitle {
            if let japanese, japanese.isEmpty == false { return japanese }
            return title
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty == false { return title }
        if let japanese, japanese.isEmpty == false { return japanese }
        return title
    }

    /// Mirrors the reference client's `judgeSuitableTitle`: the search key is
    /// matched against the Japanese and the ordinary title concatenated.
    public func containsTitle(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return true }
        let haystack = "\(japaneseTitle ?? "")\(title)"
        return haystack.localizedCaseInsensitiveContains(query)
    }

    /// Mirrors the reference client's `GalleryInfo.generateSLang`: the first
    /// `language:` tag wins, then title patterns, otherwise nil.
    public var simpleLanguage: String? {
        for tag in tags {
            if let code = Self.languageTagCodes[tag.lowercased()] {
                return code
            }
        }
        for entry in Self.languageTitlePatterns {
            guard let regex = try? NSRegularExpression(pattern: entry.pattern, options: [.caseInsensitive]),
                  regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil else { continue }
            return entry.code
        }
        return nil
    }

    /// ISO 639-1-style codes for the reference client's language tag list.
    private static let languageTagCodes: [String: String] = [
        "language:english": "EN",
        "language:chinese": "ZH",
        "language:spanish": "ES",
        "language:korean": "KO",
        "language:russian": "RU",
        "language:french": "FR",
        "language:portuguese": "PT",
        "language:thai": "TH",
        "language:german": "DE",
        "language:italian": "IT",
        "language:vietnamese": "VI",
        "language:polish": "PL",
        "language:hungarian": "HU",
        "language:dutch": "NL",
    ]

    /// Title patterns from the reference client's `S_LANG_PATTERNS`, in order.
    /// The Java original writes `[([]` for a class of `(` and `[`; ICU needs
    /// the inner bracket escaped as `\[`.
    private static let languageTitlePatterns: [(code: String, pattern: String)] = [
        ("EN", #"[(\[]eng(?:lish)?[)\]]|英訳"#),
        ("ZH", #"[（(\[]ch(?:inese)?[）)\]]|[汉漢]化|中[国國][语語]|中文|中国翻訳"#),
        ("ES", #"[(\[]spanish[)\]]|[(\[]Español[)\]]|スペイン翻訳"#),
        ("KO", #"[(\[]korean?[)\]]|韓国翻訳"#),
        ("RU", #"[(\[]rus(?:sian)?[)\]]|ロシア翻訳"#),
        ("FR", #"[(\[]fr(?:ench)?[)\]]|フランス翻訳"#),
        ("PT", #"[(\[]portuguese|ポルトガル翻訳"#),
        ("TH", #"[(\[]thai(?: ภาษาไทย)?[)\]]|แปลไทย|タイ翻訳"#),
        ("DE", #"[(\[]german[)\]]|ドイツ翻訳"#),
        ("IT", #"[(\[]italiano?[)\]]|イタリア翻訳"#),
        ("VI", #"[(\[]vietnamese(?: Tiếng Việt)?[)\]]|ベトナム翻訳"#),
        ("PL", #"[(\[]polish[)\]]|ポーランド翻訳"#),
        ("HU", #"[(\[]hun(?:garian)?[)\]]|ハンガリー翻訳"#),
        ("NL", #"[(\[]dutch[)\]]|オランダ翻訳"#),
    ]
}

public struct GalleryPageDescriptor: Identifiable, Hashable, Codable, Sendable {
    public let galleryKey: GalleryKey
    public let index: Int
    public let pageURL: URL
    public let previewURL: URL?
    public let previewClip: GalleryPreviewClip?

    public init(
        galleryKey: GalleryKey,
        index: Int,
        pageURL: URL,
        previewURL: URL? = nil,
        previewClip: GalleryPreviewClip? = nil
    ) {
        self.galleryKey = galleryKey
        self.index = index
        self.pageURL = pageURL
        self.previewURL = previewURL
        self.previewClip = previewClip
    }

    public var id: String { "\(galleryKey.id)-\(index)" }

    /// The site page URL uses `/s/{page-token}/...`; it must be resolved to an
    /// image URL before a download can be started.
    public var requiresPageResolution: Bool {
        pageURL.path.hasPrefix("/s/")
    }
}

/// The visible window of a gallery preview, ported from the reference
/// client's `NormalPreviewSet`: the site stores one large image per preview
/// and shows a zoomed window of it via `background-position`.
public struct GalleryPreviewClip: Hashable, Codable, Sendable {
    public var xOffset: Int
    public var width: Int
    public var height: Int

    public init(xOffset: Int, width: Int, height: Int) {
        self.xOffset = xOffset
        self.width = width
        self.height = height
    }

    /// The crop rectangle inside the large preview image. The reference
    /// regexes capture the magnitude of the site's `background-position`
    /// offset (e.g. `-100px` yields `100`), mirroring the reference client's
    /// `LoadImageView.setClip(x, y, width, height)`.
    public var cropRect: CGRect {
        CGRect(x: xOffset, y: 0, width: width, height: height)
    }

    /// The clipped aspect ratio clamped to the reference item's range.
    public var clampedAspect: Double {
        guard width > 0, height > 0 else { return 0.667 }
        return min(max(Double(width) / Double(height), 0.5), 0.8)
    }
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
    public var language: String?
    public var fileSize: String?
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
        language: String? = nil,
        fileSize: String? = nil,
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
        self.language = language
        self.fileSize = fileSize
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

/// Filter rule modes from the reference client's `EhFilter`.
public enum GalleryFilterMode: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case title
    case uploader
    case tag
    case tagNamespace

    public var id: Self { self }

    public var title: String {
        switch self {
        case .title: String(localized: "标题")
        case .uploader: String(localized: "上传者")
        case .tag: String(localized: "标签")
        case .tagNamespace: String(localized: "标签组")
        }
    }
}

/// Matching semantics ported from the reference client's `EhFilter`.
public enum GalleryFilterMatcher {
    /// Returns true when the gallery is blocked by the enabled rule.
    public static func isBlocked(_ gallery: GallerySummary, mode: GalleryFilterMode, keyword: String) -> Bool {
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyword.isEmpty == false else { return false }
        switch mode {
        case .title:
            return gallery.title.lowercased().contains(keyword.lowercased())
        case .uploader:
            return gallery.uploader == keyword
        case .tag:
            return matchesTag(gallery.tags, keyword: keyword)
        case .tagNamespace:
            return gallery.tags.contains { tag in
                namespace(of: tag) == keyword.lowercased()
            }
        }
    }

    /// `EhFilter.matchTag`: a keyword with a namespace must match both the
    /// namespace and the tag name; without one it matches the name in any
    /// namespace. Name equality is exact, not substring. The reference
    /// lowercases the keyword when the rule is saved; tag names are kept
    /// as-is.
    private static func matchesTag(_ tags: [String], keyword: String) -> Bool {
        let keywordParts = keyword.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        for tag in tags {
            let tagParts = tag.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            if keywordParts.count == 2 {
                guard tagParts.count == 2,
                      tagParts[0].lowercased() == keywordParts[0].lowercased(),
                      tagParts[1] == keywordParts[1].lowercased() else { continue }
            } else {
                guard let name = keywordParts.first,
                      let tagName = tagParts.last,
                      tagName == name.lowercased() else { continue }
            }
            return true
        }
        return false
    }

    private static func namespace(of tag: String) -> String? {
        tag.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map { String($0).lowercased() }
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
    case search(String)
    case subscriptions
    case popular
    case toplist
    case downloads
    case history
    case favorites
    case settings
    case gallery(GalleryKey)
    case comments(GalleryKey)
    case reader(GalleryKey, page: Int)
}
