import Foundation
import EHDomain

public enum MigrationError: LocalizedError, Sendable {
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "不支持的数据迁移版本：\(version)"
        }
    }
}

public struct MigrationGallery: Codable, Hashable, Sendable {
    public var summary: GallerySummary
    public var lastReadPage: Int
    public var lastReadAt: Date?
    public var isFavorite: Bool

    public init(summary: GallerySummary, lastReadPage: Int, lastReadAt: Date?, isFavorite: Bool) {
        self.summary = summary
        self.lastReadPage = lastReadPage
        self.lastReadAt = lastReadAt
        self.isFavorite = isFavorite
    }
}

public struct MigrationPage: Codable, Hashable, Sendable {
    public var pageIndex: Int
    public var fileName: String
    public var bytes: Int64
    public var directURLString: String?
    public var previewURLString: String?
    public var stateRaw: String
    public var retryCount: Int

    public init(
        pageIndex: Int,
        fileName: String,
        bytes: Int64,
        directURLString: String?,
        previewURLString: String?,
        stateRaw: String,
        retryCount: Int
    ) {
        self.pageIndex = pageIndex
        self.fileName = fileName
        self.bytes = bytes
        self.directURLString = directURLString
        self.previewURLString = previewURLString
        self.stateRaw = stateRaw
        self.retryCount = retryCount
    }
}

public struct MigrationDownload: Codable, Hashable, Sendable {
    public var key: GalleryKey
    public var title: String
    public var japaneseTitle: String?
    public var stateRaw: String
    public var label: String?
    public var errorMessage: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var pages: [MigrationPage]

    public init(
        key: GalleryKey,
        title: String,
        japaneseTitle: String? = nil,
        stateRaw: String,
        label: String?,
        errorMessage: String?,
        createdAt: Date,
        updatedAt: Date,
        pages: [MigrationPage]
    ) {
        self.key = key
        self.title = title
        self.japaneseTitle = japaneseTitle
        self.stateRaw = stateRaw
        self.label = label
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pages = pages
    }
}

public struct MigrationQuickSearch: Codable, Hashable, Sendable {
    public var query: String
    public var lastUsedAt: Date

    public init(query: String, lastUsedAt: Date) {
        self.query = query
        self.lastUsedAt = lastUsedAt
    }
}

public struct MigrationFilterRule: Codable, Hashable, Sendable {
    public var pattern: String
    public var isEnabled: Bool
    public var mode: GalleryFilterMode

    public init(pattern: String, isEnabled: Bool, mode: GalleryFilterMode = .title) {
        self.pattern = pattern
        self.isEnabled = isEnabled
        self.mode = mode
    }

    private enum CodingKeys: String, CodingKey {
        case pattern
        case isEnabled
        case mode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pattern = try container.decode(String.self, forKey: .pattern)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        mode = try container.decodeIfPresent(GalleryFilterMode.self, forKey: .mode) ?? .title
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pattern, forKey: .pattern)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(mode, forKey: .mode)
    }
}

public struct MigrationTagTranslation: Codable, Hashable, Sendable {
    public var tag: String
    public var locale: String
    public var localizedText: String
    public var updatedAt: Date

    public init(tag: String, locale: String, localizedText: String, updatedAt: Date) {
        self.tag = tag
        self.locale = locale
        self.localizedText = localizedText
        self.updatedAt = updatedAt
    }
}

public struct MigrationSnapshot: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var schemaVersion: Int
    public var exportedAt: Date
    public var siteRaw: String?
    public var readingSettingsData: Data?
    public var galleries: [MigrationGallery]
    public var downloads: [MigrationDownload]
    public var quickSearches: [MigrationQuickSearch]
    public var filterRules: [MigrationFilterRule]
    public var tagTranslations: [MigrationTagTranslation]

    public init(
        schemaVersion: Int = MigrationSnapshot.currentVersion,
        exportedAt: Date = Date(),
        siteRaw: String? = nil,
        readingSettingsData: Data? = nil,
        galleries: [MigrationGallery] = [],
        downloads: [MigrationDownload] = [],
        quickSearches: [MigrationQuickSearch] = [],
        filterRules: [MigrationFilterRule] = [],
        tagTranslations: [MigrationTagTranslation] = []
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.siteRaw = siteRaw
        self.readingSettingsData = readingSettingsData
        self.galleries = galleries
        self.downloads = downloads
        self.quickSearches = quickSearches
        self.filterRules = filterRules
        self.tagTranslations = tagTranslations
    }
}
