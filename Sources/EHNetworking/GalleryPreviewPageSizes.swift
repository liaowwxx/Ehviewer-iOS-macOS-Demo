import EHDomain

/// Pagination capacity is learned from the first page, rather than assuming
/// the site's configurable preview count is always twenty.
actor GalleryPreviewPageSizes {
    private var sizes: [String: Int] = [:]

    func value(key: GalleryKey, site: SiteMode) -> Int? {
        sizes["\(site.host)|\(key.id)"]
    }

    func set(_ size: Int, key: GalleryKey, site: SiteMode) {
        sizes["\(site.host)|\(key.id)"] = size
    }
}
