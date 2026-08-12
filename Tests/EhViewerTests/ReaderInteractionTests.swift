import CoreGraphics
import Foundation
import Testing
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

    @Test("Pinch zoom accumulates across gestures and respects limits")
    func zoomAccumulatesAndClamps() {
        var state = ReaderZoomState()
        let size = CGSize(width: 300, height: 500)

        state.magnificationEnded(2, viewportSize: size, fittedContentSize: size)
        state.magnificationEnded(1.5, viewportSize: size, fittedContentSize: size)
        #expect(state.scale == 3)

        state.magnificationEnded(10, viewportSize: size, fittedContentSize: size)
        #expect(state.scale == ReaderZoomState.maximumScale)
    }

    @Test("Zoomed dragging is bounded and reset restores the page")
    func zoomDragBoundsAndReset() {
        var state = ReaderZoomState()
        let size = CGSize(width: 200, height: 400)
        state.magnificationEnded(2, viewportSize: size, fittedContentSize: size)

        _ = state.dragEnded(
            CGSize(width: 1_000, height: -1_000),
            viewportSize: size,
            fittedContentSize: size
        )
        #expect(state.offset == CGSize(width: 100, height: -200))

        state.advanceZoom(candidates: [1], viewportSize: size, fittedContentSize: size)
        #expect(state.scale == 1)
        #expect(state.offset == .zero)
        #expect(state.isZoomed == false)
    }

    @Test("A fitted page does not expose blank-space panning")
    func fittedPageUsesViewportBounds() {
        var state = ReaderZoomState()
        let viewport = CGSize(width: 400, height: 400)
        let fittedPage = CGSize(width: 200, height: 400)

        state.magnificationEnded(2, viewportSize: viewport, fittedContentSize: fittedPage)
        _ = state.dragEnded(
            CGSize(width: 1_000, height: -1_000),
            viewportSize: viewport,
            fittedContentSize: fittedPage
        )

        #expect(state.offset == CGSize(width: 0, height: -200))
        #expect(state.canPanHorizontally(viewportSize: viewport, fittedContentSize: fittedPage) == false)
        #expect(state.canPanVertically(viewportSize: viewport, fittedContentSize: fittedPage))
    }

    @Test("A horizontal drag hands off to paging after the image edge")
    func pageTurnAfterImageEdge() {
        var state = ReaderZoomState()
        let size = CGSize(width: 300, height: 500)
        state.magnificationEnded(2, viewportSize: size, fittedContentSize: size)

        _ = state.dragEnded(
            CGSize(width: -150, height: 0),
            viewportSize: size,
            fittedContentSize: size
        )
        let pageTurn = state.dragEnded(
            CGSize(width: -60, height: 0),
            viewportSize: size,
            fittedContentSize: size
        )

        #expect(pageTurn == 1)
    }

    @Test("Continuous mode zoom stays between reference limits")
    func continuousZoomLimits() {
        var state = ReaderContinuousZoomState()
        state.magnificationEnded(10)
        #expect(state.scale == 2)
        state.toggle()
        #expect(state.scale == 1)
    }

    @Test("Page zoom preserves the gesture focus")
    func pageZoomPreservesFocus() {
        var state = ReaderZoomState()
        let size = CGSize(width: 300, height: 500)

        state.magnificationEnded(
            2,
            viewportSize: size,
            fittedContentSize: size,
            focus: CGPoint(x: 250, y: 250)
        )

        #expect(state.scale == 2)
        #expect(state.offset == CGSize(width: -100, height: 0))
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
}
