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
