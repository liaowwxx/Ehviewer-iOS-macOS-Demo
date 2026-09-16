import Foundation
import Testing
import EHDomain
import EHDownloads
@testable import EhViewerPreview

struct GalleryCardDisplaySettingsTests {
    @Test("卡片布局和两种大小设置保存后可以恢复")
    func layoutPreferencesRoundTrip() throws {
        var settings = GalleryCardDisplaySettings()
        settings.layoutMode = .grid
        settings.cardScale = 1.25
        settings.listScale = 0.85
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(GalleryCardDisplaySettings.self, from: data) == settings)
    }

    @Test("旧设置保留列表布局和默认大小")
    func legacyLayoutDefaults() throws {
        let settings = try JSONDecoder().decode(GalleryCardDisplaySettings.self, from: Data("{}".utf8))
        #expect(settings.layoutMode == .list)
        #expect(settings.cardScale == 1)
        #expect(settings.listScale == 1)
    }

    @Test("导入越界缩放值时限制到支持范围")
    func importedScaleIsClamped() throws {
        let data = Data(#"{"cardScale":10,"listScale":-2}"#.utf8)
        let settings = try JSONDecoder().decode(GalleryCardDisplaySettings.self, from: data)
        #expect(settings.cardScale == 1.4)
        #expect(settings.listScale == 0.8)
        #expect(GalleryCardDisplaySettings.clampedScale(.infinity) == 1)
    }

    @Test("旧阅读设置缺少漫画卡片配置时采用当前列表默认值")
    func legacyReadingSettingsUseCardDefaults() throws {
        let data = Data(#"{"readingMode":"rightToLeft","showTagTranslations":false}"#.utf8)

        let decoded = try JSONDecoder().decode(ReadingSettings.self, from: data)

        #expect(decoded.galleryCard == .defaults)
        #expect(decoded.showTagTranslations == false)
        #expect(decoded.readingDirection == .rightToLeft)
    }

    @Test("旧漫画卡片配置缺少添加时间时保留既有选项")
    func legacyGalleryCardSettingsKeepExistingValues() throws {
        let data = Data(#"{"showsAuthor":false,"showsPostedAt":false,"dateDisplayStyle":"absolute"}"#.utf8)

        let decoded = try JSONDecoder().decode(GalleryCardDisplaySettings.self, from: data)

        #expect(decoded.showsAuthor == false)
        #expect(decoded.showsPostedAt == false)
        #expect(decoded.showsAddedAt == false)
        #expect(decoded.dateDisplayStyle == .absolute)
        #expect(decoded.showsRating)
    }

    @Test("添加时间与上传日期互斥，后开启的选项优先")
    func dateDisplayOptionsAreMutuallyExclusive() {
        var showingUploadDate = GalleryCardDisplaySettings()
        var showingAddedTime = showingUploadDate
        showingAddedTime.showsAddedAt = true

        let addedTimeResolved = GalleryCardDisplaySettings.resolving(
            previous: showingUploadDate,
            updated: showingAddedTime,
            isCompactWidth: false
        )
        #expect(addedTimeResolved.showsPostedAt == false)
        #expect(addedTimeResolved.showsAddedAt)

        showingUploadDate = addedTimeResolved
        showingAddedTime = addedTimeResolved
        showingAddedTime.showsPostedAt = true
        let uploadDateResolved = GalleryCardDisplaySettings.resolving(
            previous: showingUploadDate,
            updated: showingAddedTime,
            isCompactWidth: false
        )
        #expect(uploadDateResolved.showsPostedAt)
        #expect(uploadDateResolved.showsAddedAt == false)
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
