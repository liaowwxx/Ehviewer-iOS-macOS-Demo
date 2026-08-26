import Foundation
import Testing
import EHDomain
import EHDownloads
@testable import EhViewerPreview

struct GalleryCardDisplaySettingsTests {
    @Test("旧阅读设置缺少漫画卡片配置时采用当前列表默认值")
    func legacyReadingSettingsUseCardDefaults() throws {
        let data = Data(#"{"readingMode":"rightToLeft","showTagTranslations":false}"#.utf8)

        let decoded = try JSONDecoder().decode(ReadingSettings.self, from: data)

        #expect(decoded.galleryCard == .defaults)
        #expect(decoded.showTagTranslations == false)
        #expect(decoded.readingDirection == .rightToLeft)
    }

    @Test("regular 宽度允许普通标签与五星评分并存")
    func regularWidthKeepsTagsAndStars() {
        let previous = GalleryCardDisplaySettings()
        var updated = previous
        updated.ratingDisplayStyle = .stars

        let resolved = GalleryCardDisplaySettings.resolving(
            previous: previous,
            updated: updated,
            isCompactWidth: false
        )

        #expect(resolved.showsOrdinaryTags)
        #expect(resolved.ratingDisplayStyle == .stars)
    }

    @Test("compact 宽度开启五星评分时五星优先")
    func compactStarsHideOrdinaryTags() {
        let previous = GalleryCardDisplaySettings()
        var updated = previous
        updated.ratingDisplayStyle = .stars

        let resolved = GalleryCardDisplaySettings.resolving(
            previous: previous,
            updated: updated,
            isCompactWidth: true
        )

        #expect(resolved.showsOrdinaryTags == false)
        #expect(resolved.showsRating)
        #expect(resolved.ratingDisplayStyle == .stars)
    }

    @Test("compact 宽度重新开启普通标签时切回数字评分")
    func compactTagsSwitchStarsToNumeric() {
        var previous = GalleryCardDisplaySettings()
        previous.showsOrdinaryTags = false
        previous.ratingDisplayStyle = .stars
        var updated = previous
        updated.showsOrdinaryTags = true

        let resolved = GalleryCardDisplaySettings.resolving(
            previous: previous,
            updated: updated,
            isCompactWidth: true
        )

        #expect(resolved.showsOrdinaryTags)
        #expect(resolved.showsRating)
        #expect(resolved.ratingDisplayStyle == .numeric)
    }

    @Test("隐藏评分时保留五星选择，重新显示后五星优先")
    func hiddenRatingPreservesStyleAndRestoresStarPriority() {
        var hidden = GalleryCardDisplaySettings()
        hidden.showsRating = false
        hidden.ratingDisplayStyle = .stars
        hidden.showsOrdinaryTags = true

        let whileHidden = GalleryCardDisplaySettings.resolving(
            previous: hidden,
            updated: hidden,
            isCompactWidth: true
        )
        var restored = whileHidden
        restored.showsRating = true
        let resolved = GalleryCardDisplaySettings.resolving(
            previous: whileHidden,
            updated: restored,
            isCompactWidth: true
        )

        #expect(whileHidden.ratingDisplayStyle == .stars)
        #expect(whileHidden.showsOrdinaryTags)
        #expect(resolved.showsOrdinaryTags == false)
        #expect(resolved.ratingDisplayStyle == .stars)
    }

    @Test("compact 显示层会解决 regular 宽度留下的冲突")
    func compactDisplayNormalizesExistingConflict() {
        var settings = GalleryCardDisplaySettings()
        settings.ratingDisplayStyle = .stars

        let effective = settings.effectiveForDisplay(isCompactWidth: true)

        #expect(effective.showsOrdinaryTags == false)
        #expect(effective.ratingDisplayStyle == .stars)
    }

    @Test("卡片下载状态将完整任务与进行中任务区分开")
    func galleryCardDownloadStatusUsesThreeStatePresentation() {
        let key = GalleryKey(gid: 100, token: "card-download-status")
        var job = DownloadJob(key: key, title: "Test", pages: [])

        #expect(GalleryCardDownloadStatus(job: nil) == .notDownloaded)
        #expect(GalleryCardDownloadStatus(job: job) == .downloading)

        job.state = .completed
        #expect(GalleryCardDownloadStatus(job: job) == .downloaded)
    }
}
