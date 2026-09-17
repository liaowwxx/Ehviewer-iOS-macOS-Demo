import Foundation
import Testing
import EHDomain
import EHDownloads
import Observation
import Synchronization
@testable import EhViewerPreview

struct WaterfallLayoutTests {
    @Test("两行标签填满后不再测量其余标签")
    func tagMeasurementIsBounded() {
        let layout = TagFlowLayout(horizontalSpacing: 5, verticalSpacing: 4, maximumRows: 2)
        var measured = 0
        let result = layout.measure(count: 200, width: 70) { _ in
            measured += 1
            return CGSize(width: 30, height: 22)
        }
        #expect(measured == 5)
        #expect(result.rows == [[0, 1], [2, 3]])
        #expect(result.size == CGSize(width: 70, height: 48))
        let unconstrained = layout.measure(count: 3, width: nil) { _ in CGSize(width: 30, height: 22) }
        #expect(unconstrained.size == CGSize(width: 100, height: 22))
        #expect(layout.measure(count: 0, width: 70) { _ in .zero }.size.height == 0)
    }

    @Test("分列缓存复用并在分页、排序和列数变化时失效")
    func columnCacheInvalidation() {
        let a = GalleryKey(gid: 1, token: "a")
        let b = GalleryKey(gid: 2, token: "b")
        let c = GalleryKey(gid: 3, token: "c")
        let cache = WaterfallColumnCache()
        let placement = [a: 0, b: 1, c: 0]
        #expect(cache.indices(keys: [a, b], placement: placement, count: 2) == [[0], [1]])
        for _ in 0..<100 {
            #expect(cache.indices(keys: [a, b], placement: placement, count: 2) == [[0], [1]])
        }
        #expect(cache.rebuildCount == 1)
        #expect(cache.indices(keys: [a, b, c], placement: placement, count: 2) == [[0, 2], [1]])
        #expect(cache.indices(keys: [c, a, b], placement: placement, count: 2) == [[0, 1], [2]])
        #expect(cache.indices(keys: [a], placement: [a: 0], count: 1) == [[0]])
        #expect(cache.rebuildCount == 4)
    }

    @Test("标签布局复用测量结果，宽度、间距和内容变化后重新测量")
    func tagLayoutCacheInvalidation() {
        let layout = TagFlowLayout(horizontalSpacing: 5, verticalSpacing: 4, maximumRows: 2)
        var cache = TagFlowLayoutCache()
        var measured = 0
        let measure: (Int) -> CGSize = { _ in
            measured += 1
            return CGSize(width: 30, height: 22)
        }
        for _ in 0..<100 {
            layout.resolve(count: 200, width: 70, cache: &cache, itemSize: measure)
        }
        #expect(measured == 5)
        layout.resolve(count: 200, width: 35, cache: &cache, itemSize: measure)
        #expect(measured == 8)
        let changed = TagFlowLayout(horizontalSpacing: 10, verticalSpacing: 8, maximumRows: 2)
        changed.resolve(count: 200, width: 35, cache: &cache, itemSize: measure)
        #expect(measured == 11)
        changed.resolve(count: 2, width: 35, cache: &cache, itemSize: measure)
        #expect(measured == 13)
        // SwiftUI's updateCache resets the cache when chip contents change.
        cache = TagFlowLayoutCache()
        changed.resolve(count: 2, width: 35, cache: &cache, itemSize: measure)
        #expect(measured == 15)
    }

    @Test("缩放布局同步提供最终高度，不依赖下一轮状态更新")
    func proportionalHeightIsSynchronous() {
        let layout = ProportionalCardLayout(referenceWidth: 170, width: 255)
        #expect(layout.scaledSize(CGSize(width: 170, height: 300)) == CGSize(width: 255, height: 450))
        let smaller = ProportionalCardLayout(referenceWidth: 170, width: 85)
        #expect(smaller.scaledSize(CGSize(width: 170, height: 300)) == CGSize(width: 85, height: 150))
    }

    @Test("瀑布流标签只排两行，缩放间距后仍不绘制第三行")
    func tagsHaveTwoRows() {
        let sizes = Array(repeating: CGSize(width: 30, height: 22), count: 7)
        let limited = TagFlowLayout(horizontalSpacing: 5, verticalSpacing: 4, maximumRows: 2)
        #expect(limited.rows(for: sizes, in: 70) == [[0, 1], [2, 3]])
        let scaled = TagFlowLayout(horizontalSpacing: 7, verticalSpacing: 5.6, maximumRows: 2)
        let enlarged = sizes.map { CGSize(width: $0.width * 1.4, height: $0.height * 1.4) }
        #expect(scaled.rows(for: enlarged, in: 70) == [[0], [1]])
        let unlimited = TagFlowLayout(horizontalSpacing: 5, verticalSpacing: 4)
        #expect(unlimited.rows(for: sizes, in: 70).count == 4)
        #expect(limited.rows(for: [], in: 70).isEmpty)
    }

    @MainActor
    @Test("单张封面比例和高度更新不会通知其他卡片")
    func measurementsAreIsolatedPerCover() {
        let firstKey = GalleryKey(gid: 101, token: "first")
        let secondKey = GalleryKey(gid: 102, token: "second")
        let measurements = WaterfallMeasurements()
        let first = measurements.ratio(for: firstKey)
        let second = measurements.ratio(for: secondKey)
        #expect(first === measurements.ratio(for: firstKey))
        #expect(first !== second)
        let invalidations = Mutex(0)
        withObservationTracking {
            _ = measurements.ratio(for: firstKey).value
        } onChange: {
            invalidations.withLock { $0 += 1 }
        }
        second.value = 1
        measurements.heights[secondKey] = 400
        #expect(invalidations.withLock { $0 } == 0)
        first.value = 1
        #expect(invalidations.withLock { $0 } == 1)
        measurements.retain([firstKey])
        #expect(measurements.heights[secondKey] == nil)
        #expect(measurements.ratio(for: firstKey) === first)
    }

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
