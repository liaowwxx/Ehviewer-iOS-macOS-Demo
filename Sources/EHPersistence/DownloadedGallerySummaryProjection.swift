import Foundation
import EHDomain

/// Decodes card metadata without constructing the full page descriptor array.
struct DownloadedGallerySummaryProjection: Decodable {
    let key: GalleryKey
    let sourceSite: SiteMode
    let title: String
    let japaneseTitle: String?
    let uploader: String?
    let tags: [String]
    let category: String?
    let pageCount: Int?
    let postedAt: Date?
    let thumbnailURL: URL?
    let completeness: GalleryMetadataCompleteness

    var summary: GallerySummary {
        StableGalleryMetadataSnapshot(
            key: key,
            sourceSite: sourceSite,
            title: title,
            japaneseTitle: japaneseTitle,
            uploader: uploader,
            tags: tags,
            category: category,
            pageCount: pageCount,
            postedAt: postedAt,
            thumbnailURL: thumbnailURL,
            completeness: completeness
        ).summary
    }
}
