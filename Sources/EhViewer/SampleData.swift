import Foundation
import EHDomain

enum SampleData {
    static let galleries: [GallerySummary] = [
        GallerySummary(
            key: GalleryKey(gid: 17769001, token: "sample-a"),
            title: "Sample Gallery · Browse baseline",
            secondaryTitle: "首版演示数据（不会访问真实站点）",
            category: "Manga",
            pageCount: 18,
            postedAt: Date().addingTimeInterval(-86_400),
            rating: 4.6,
            tags: ["language:chinese", "artist:sample"]
        ),
        GallerySummary(
            key: GalleryKey(gid: 17769002, token: "sample-b"),
            title: "Reader and download state machine",
            secondaryTitle: "阅读进度与下载队列纵切片",
            category: "Doujinshi",
            pageCount: 12,
            postedAt: Date().addingTimeInterval(-172_800),
            rating: 4.2,
            tags: ["language:english", "parody:sample"]
        ),
        GallerySummary(
            key: GalleryKey(gid: 17769003, token: "sample-c"),
            title: "Adaptive navigation on iPhone, iPad and Mac",
            secondaryTitle: "统一 AppRoute 导航示例",
            category: "Imageset",
            pageCount: 24,
            postedAt: Date().addingTimeInterval(-259_200),
            rating: 4.8,
            tags: ["type:imageset", "site:e-hentai"]
        )
    ]

    static func detail(for summary: GallerySummary) -> GalleryDetail {
        let pages = (0..<(summary.pageCount ?? 0)).map { index in
            GalleryPageDescriptor(
                galleryKey: summary.key,
                index: index,
                pageURL: URL(string: "https://\(summary.key.id).invalid/page/\(index)")!
            )
        }
        return GalleryDetail(summary: summary, pages: pages, tags: summary.tags, descriptionText: summary.secondaryTitle)
    }
}
