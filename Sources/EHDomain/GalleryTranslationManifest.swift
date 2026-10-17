import Foundation

public enum ReadingEdition: Codable, Hashable, Sendable {
    case original
    case translated(versionID: UUID)
}

/// An immutable whole-book version. SHA-256 values are lowercase hexadecimal
/// on disk and on the companion wire protocol; source hashes bind page order.
public struct GalleryTranslationManifest: Codable, Hashable, Sendable, Identifiable {
    public struct Gallery: Codable, Hashable, Sendable {
        public let gid: Int64
        public let token: String
        public let title: String
        public var key: GalleryKey { GalleryKey(gid: gid, token: token) }

        public init(key: GalleryKey, title: String) {
            gid = key.gid
            token = key.token
            self.title = title
        }
    }

    public struct Page: Codable, Hashable, Sendable {
        public let index: Int
        public let fileName: String
        public let byteCount: Int64
        public let sha256: String
        public let sourceSHA256: String

        public init(index: Int, fileName: String, byteCount: Int64, sha256: String, sourceSHA256: String) {
            self.index = index
            self.fileName = fileName
            self.byteCount = byteCount
            self.sha256 = sha256
            self.sourceSHA256 = sourceSHA256
        }
    }

    public let formatVersion: Int
    public let versionID: UUID
    public let gallery: Gallery
    public let createdAt: Double
    public let targetLanguage: String
    public let presetFingerprint: String
    public let pages: [Page]
    public var id: UUID { versionID }

    public init(versionID: UUID, gallery: Gallery, createdAt: Double, targetLanguage: String, presetFingerprint: String, pages: [Page]) {
        formatVersion = 1
        self.versionID = versionID
        self.gallery = gallery
        self.createdAt = createdAt
        self.targetLanguage = targetLanguage
        self.presetFingerprint = presetFingerprint
        self.pages = pages
    }

    public func validate() throws {
        guard formatVersion == 1, gallery.gid > 0, !gallery.token.isEmpty, gallery.token.count <= 512,
              gallery.title.count <= 10_000, targetLanguage.count <= 200,
              createdAt.isFinite, Self.isSHA256(presetFingerprint), (1...10_000).contains(pages.count) else {
            throw EHError.parsingFailed(String(localized: "译件清单无效。"))
        }
        var names = Set<String>()
        for (index, page) in pages.enumerated() {
            guard page.index == index, page.fileName.count <= 100,
                  page.fileName.range(of: #"^[A-Za-z0-9_-]+\.(png|jpg|jpeg|webp|bmp|tif|tiff)$"#, options: .regularExpression) != nil,
                  names.insert(page.fileName).inserted,
                  (1...DeviceSyncPageEntry.maximumByteCount).contains(page.byteCount),
                  Self.isSHA256(page.sha256), Self.isSHA256(page.sourceSHA256) else {
                throw EHError.parsingFailed(String(localized: "译件页面映射或校验信息无效。"))
            }
        }
    }

    public static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
