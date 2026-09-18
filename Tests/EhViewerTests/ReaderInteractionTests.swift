import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import EHDomain
import EHDownloads
@testable import EhViewerPreview

struct ReaderInteractionTests {
    @Test("Image layout visibility updates do not request automatic scrolling")
    func visiblePageDoesNotRequestScroll() {
        var state = ReaderPositionState(page: 0)
        state.prepare(page: 0, pageCount: 10)

        state.markVisiblePage(from: [1, 2], displayOrder: Array(0..<10))

        #expect(state.page == 1)
        #expect(state.scrollTarget == nil)
        #expect(state.scrollRequestSequence == 0)
    }

    @Test("Explicit page navigation requests scrolling and clamps bounds")
    func explicitNavigationRequestsScroll() {
        var state = ReaderPositionState(page: 0)

        state.requestPage(20, pageCount: 5)

        #expect(state.page == 4)
        #expect(state.scrollTarget == 4)
        #expect(state.scrollRequestSequence == 1)
    }

    @Test("Immediate navigation updates the page without an animation request")
    func immediateNavigationRequestsNoAnimation() {
        var state = ReaderPositionState(page: 0)

        state.requestPage(7, pageCount: 10, animated: false)

        #expect(state.page == 7)
        #expect(state.scrollTarget == 7)
        #expect(state.scrollRequestSequence == 1)
        #expect(state.scrollRequestAnimated == false)
    }

    @Test("Thumbnail windows keep the target near the center and clamp to the edges")
    func thumbnailWindowClampsToEdges() {
        #expect(ReaderPageWindow.indexes(target: 0, pageCount: 20, maximumCount: 5) == Array(0..<5))
        #expect(ReaderPageWindow.indexes(target: 9, pageCount: 20, maximumCount: 5) == Array(7..<12))
        #expect(ReaderPageWindow.indexes(target: 19, pageCount: 20, maximumCount: 5) == Array(15..<20))
        #expect(ReaderPageWindow.indexes(target: 2, pageCount: 4, maximumCount: 10) == Array(0..<4))
        #expect(ReaderPageWindow.indexes(target: 100, pageCount: 0, maximumCount: 10).isEmpty)
    }

    @Test("Thumbnail count adapts to the available width")
    func thumbnailCountAdaptsToWidth() {
        let narrowCount = ReaderPageWindow.maximumCount(forAvailableWidth: 320)
        let wideCount = ReaderPageWindow.maximumCount(forAvailableWidth: 834)

        #expect(narrowCount == 4)
        #expect(wideCount == 12)
        #expect(wideCount > narrowCount)
    }

    @Test("Large gallery seeks render only the viewport and a bounded buffer", arguments: [320.0, 834.0])
    func largeGalleryThumbnailSeeksStayBounded(width: Double) {
        let maximumCount = Int((width / ReaderPageWindow.thumbnailStride).rounded(.up)) + 7
        for target in 0..<1_900 {
            let offset = ReaderPageWindow.thumbnailOffset(target: target, pageCount: 1_900, viewportWidth: width)
            let range = ReaderPageWindow.thumbnailRange(offset: offset, viewportWidth: width, pageCount: 1_900)

            #expect(range.contains(target))
            #expect(range.count <= maximumCount)
            #expect(range.lowerBound >= 0)
            #expect(range.upperBound <= 1_900)
        }
    }

    @Test("Thumbnail scrolling covers the whole gallery and clamps overscroll")
    func thumbnailScrollCoversGallery() {
        let count = 1_900
        let width = 320.0
        let contentWidth = ReaderPageWindow.thumbnailContentWidth(pageCount: count)
        #expect(contentWidth == 174_814)
        #expect(ReaderPageWindow.thumbnailOffset(target: -10, pageCount: count, viewportWidth: width) == 0)
        #expect(ReaderPageWindow.thumbnailOffset(target: 2_000, pageCount: count, viewportWidth: width) == contentWidth - width)

        var covered = Set<Int>()
        for offset in stride(from: 0.0, through: contentWidth, by: 160.0) {
            covered.formUnion(ReaderPageWindow.thumbnailRange(offset: offset, viewportWidth: width, pageCount: count))
        }
        #expect(covered == Set(0..<count))
        #expect(ReaderPageWindow.thumbnailRange(offset: -100, viewportWidth: width, pageCount: count).lowerBound == 0)
        #expect(ReaderPageWindow.thumbnailRange(offset: contentWidth + 100, viewportWidth: width, pageCount: count).upperBound == count)
    }

    @Test("Thumbnail geometry handles empty galleries and viewports wider than the content")
    func thumbnailGeometryHandlesSmallContent() {
        #expect(ReaderPageWindow.thumbnailRange(offset: 0, viewportWidth: 320, pageCount: 0).isEmpty)
        #expect(ReaderPageWindow.thumbnailRange(offset: 0, viewportWidth: 0, pageCount: 10).isEmpty)
        #expect(ReaderPageWindow.thumbnailOffset(target: 10, pageCount: 0, viewportWidth: 320) == 0)
        #expect(ReaderPageWindow.thumbnailOffset(target: 2, pageCount: 3, viewportWidth: 834) == 0)
        #expect(ReaderPageWindow.thumbnailRange(offset: 0, viewportWidth: 834, pageCount: 3) == 0..<3)
    }

    @Test("Downloaded galleries reuse the normal reader detail model")
    @MainActor
    func downloadedGalleryBuildsReaderDetail() throws {
        let key = GalleryKey(gid: 42, token: "downloaded")
        let pages = (0..<3).map { index in
            GalleryPageDescriptor(
                galleryKey: key,
                index: index,
                pageURL: URL(string: "https://images.example/\(index).jpg")!,
                previewURL: index == 0 ? URL(string: "https://images.example/cover.jpg")! : nil
            )
        }
        let job = DownloadJob(key: key, title: "Offline gallery", pages: pages)

        let detail = ReaderView.downloadedDetail(for: job, site: .eHentai)

        #expect(detail.summary.key == key)
        #expect(detail.summary.title == "Offline gallery")
        #expect(detail.summary.pageCount == 3)
        #expect(detail.summary.thumbnailURL == pages[0].previewURL)
        #expect(detail.pages == pages)
        #expect(detail.externalURL?.absoluteString == "https://e-hentai.org/g/42/downloaded/")
    }

    @MainActor
    @Test("Animated GIF pages retain all frames and their timing")
    func animatedGIFRetainsFrames() throws {
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            data,
            UTType.gif.identifier as CFString,
            2,
            nil
        ))
        let properties = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.05]
        ] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        CGImageDestinationAddImage(destination, image, properties)
        #expect(CGImageDestinationFinalize(destination))

        let content = try ReaderMediaView.Content.decode(data as Data)
        guard case .image(let sequence) = content else {
            Issue.record("GIF should decode as an image sequence")
            return
        }
        #expect(sequence.frames.count == 2)
        #expect(sequence.totalDuration >= 0.1)
    }

    @Test("Gallery thumbnail cache bounds disk filenames for long cache keys")
    func galleryThumbnailCacheBoundsDiskFilenames() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehviewer-thumbnail-cache-\(UUID().uuidString)")
        let loader = GalleryCoverLoader(diskRoot: root)
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        let key = "remote|\(String(repeating: "x", count: 16_384))"

        let image = try await loader.image(for: key, maxPixelSize: 64) { png }
        #expect(image != nil)

        let files = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let cacheFile = try #require(files.first)
        #expect(cacheFile.lastPathComponent.hasSuffix(".png"))
        #expect(cacheFile.lastPathComponent.utf8.count < 255)

        let reloadedLoader = GalleryCoverLoader(diskRoot: root)
        let reloadedImage = try await reloadedLoader.image(for: key, maxPixelSize: 64) {
            throw GalleryThumbnailCacheTestError.unexpectedFetch
        }
        #expect(reloadedImage != nil)
    }
}

private enum GalleryThumbnailCacheTestError: Error {
    case unexpectedFetch
}
