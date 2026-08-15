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
}
