import Foundation
import Testing
import EHDomain
import EHDownloads
@testable import EhViewerPreview

struct WaterfallLayoutTests {
    @Test("两种布局偏好采用一致的三态循环和目标文字")
    func layoutCycle() {
        #expect(GalleryLayoutMode.list.next == .grid)
        #expect(GalleryLayoutMode.grid.next == .waterfall)
        #expect(GalleryLayoutMode.waterfall.next == .list)
        #expect(DownloadsLayoutMode.list.next == .grid)
        #expect(DownloadsLayoutMode.grid.next == .waterfall)
        #expect(DownloadsLayoutMode.waterfall.next == .list)
        #expect(GalleryLayoutMode.grid.next.title == DownloadsLayoutMode.grid.next.title)
        #expect(GalleryLayoutMode.list.next.title == String(localized: "卡片"))
        #expect(GalleryLayoutMode.grid.next.title == String(localized: "瀑布流"))
        #expect(GalleryLayoutMode.waterfall.next.title == String(localized: "列表"))
    }

    @Test("瀑布流偏好保存恢复且旧配置仍采用列表")
    func preferencesRoundTrip() throws {
        var settings = GalleryCardDisplaySettings()
        settings.layoutMode = .waterfall
        settings.cardScale = 1.2
        let restored = try JSONDecoder().decode(GalleryCardDisplaySettings.self, from: JSONEncoder().encode(settings))
        #expect(restored == settings)
        #expect(DownloadsLayoutMode(rawValue: "waterfall") == .waterfall)
        #expect(try JSONDecoder().decode(GalleryCardDisplaySettings.self, from: Data("{}".utf8)).layoutMode == .list)
    }

    static let ratioSamples: [(Double, Double, Double)] = [
        (400.0, 300.0, 1.0), (400, 400, 1), (400, 480, 1.2),
        (300, 400, 4.0 / 3.0), (300, 900, 4.0 / 3.0),
        (0, 100, 4.0 / 3.0), (100, -1, 4.0 / 3.0),
        (Double.infinity, 100, 4.0 / 3.0), (100, Double.nan, 4.0 / 3.0)
    ]

    @Test("封面比例限制为正方形至竖向三比四", arguments: ratioSamples)
    func coverRatio(_ sample: (Double, Double, Double)) {
        #expect(abs(WaterfallLayout.heightToWidth(width: sample.0, height: sample.1) - sample.2) < 0.0001)
    }

    @Test("列数响应可用宽度缩放与辅助功能字号")
    func columnCount() {
        #expect(WaterfallLayout.columnCount(width: 366, spacing: 12, scale: 1, accessibility: false) == 2)
        #expect(WaterfallLayout.columnCount(width: 800, spacing: 16, scale: 1, accessibility: false) == 4)
        #expect(WaterfallLayout.columnCount(width: 366, spacing: 12, scale: 1.4, accessibility: false) == 1)
        #expect(WaterfallLayout.columnCount(width: 100, spacing: 12, scale: 1, accessibility: false) == 1)
        #expect(WaterfallLayout.columnCount(width: 800, spacing: 16, scale: 1, accessibility: true) == 1)
        #expect(WaterfallLayout.columnCount(width: .nan, spacing: 12, scale: 1, accessibility: false) == 1)
    }

    @Test("按累计高度选择最短列同高优先左列")
    func shortestColumn() {
        let keys = (1...4).map { GalleryKey(gid: Int64($0), token: "test") }
        let result = WaterfallLayout.assignments(
            keys: keys, heights: [keys[0]: 100, keys[1]: 50, keys[2]: 50],
            count: 2, spacing: 10, estimatedHeight: 120
        )
        #expect(keys.map { result[$0] } == [0, 1, 1, 0])
        let tied = WaterfallLayout.assignments(keys: keys, heights: [:], count: 2, spacing: 12, estimatedHeight: 100)
        #expect(keys.map { tied[$0] } == [0, 1, 0, 1])
    }

    @Test("追加分页时保留原列并按已有累计高度分配新卡片")
    func appendPreservesColumns() {
        let keys = (1...4).map { GalleryKey(gid: Int64($0), token: "test") }
        let original = [keys[0]: 0, keys[1]: 1, keys[2]: 0]
        let appended = WaterfallLayout.assignments(
            keys: keys, heights: [keys[0]: 200, keys[1]: 50, keys[2]: 200],
            count: 2, spacing: 12, estimatedHeight: 100, preserving: original
        )
        for key in keys.prefix(3) { #expect(appended[key] == original[key]) }
        #expect(appended[keys[3]] == 1)
    }

    @Test("本地与下载摘要保留缓存信息并为缺失字段采用任务数据")
    func downloadSummaryFallback() {
        let key = GalleryKey(gid: 10, token: "test")
        let job = DownloadJob(key: key, title: "Task title", tags: ["artist:test"], pages: [])
        let fallback = DownloadGallerySummary.resolve(job: job, cached: nil)
        #expect(fallback.title == job.title)
        #expect(fallback.tags == job.tags)
        #expect(fallback.pageCount == nil)

        var cached = GallerySummary(key: key, title: "Cached title", rating: 4.5, tags: ["artist:cached"])
        #expect(DownloadGallerySummary.resolve(job: job, cached: cached) == cached)
        cached.metadataCompleteness = GalleryMetadataCompleteness(title: false, japaneseTitle: false, tags: false)
        cached.tags = []
        let merged = DownloadGallerySummary.resolve(job: job, cached: cached)
        #expect(merged.title == job.title)
        #expect(merged.tags == job.tags)
        #expect(merged.rating == 4.5)
    }
}
