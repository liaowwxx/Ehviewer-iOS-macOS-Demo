import EHDomain

/// Ratings and favorite status are needed on cards; comment bodies are not.
struct DownloadedGallerySummaryDynamicProjection: Decodable {
    let rating: Double?
    let ratingCount: Int?
    let favoriteCategory: Int?
    let completeness: GalleryMetadataCompleteness
}
