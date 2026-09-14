import Foundation
import Testing
import EHDomain
@testable import EhViewerPreview

struct ReaderSpreadLayoutTests {
    @Test("Left-to-right spreads pair consecutive pages and leave the trailing side blank")
    func leftToRightPairing() {
        let layout = makeLayout(pageCount: 5, direction: .leftToRight)

        #expect(layout.spreads.map { pageIndexes($0) } == [[0, 1], [2, 3], [4]])
        #expect(layout.spreads[0].leftPage?.index == 0)
        #expect(layout.spreads[0].rightPage?.index == 1)
        #expect(layout.spreads[2].leftPage?.index == 4)
        #expect(layout.spreads[2].rightPage == nil)
    }

    @Test("Right-to-left spreads reverse order and place the even page on the right")
    func rightToLeftPairing() {
        let layout = makeLayout(pageCount: 5, direction: .rightToLeft)

        #expect(layout.displayOrder == [4, 2, 0])
        #expect(layout.spreads[0].leftPage == nil)
        #expect(layout.spreads[0].rightPage?.index == 4)
        #expect(layout.spreads[1].leftPage?.index == 3)
        #expect(layout.spreads[1].rightPage?.index == 2)
        #expect(layout.spreads[2].leftPage?.index == 1)
        #expect(layout.spreads[2].rightPage?.index == 0)
    }

    @Test("Any page resolves to the anchor of its spread")
    func pageResolvesToSpreadAnchor() {
        let layout = makeLayout(pageCount: 6, direction: .leftToRight)

        #expect(layout.anchorPage(for: 0) == 0)
        #expect(layout.anchorPage(for: 1) == 0)
        #expect(layout.anchorPage(for: 2) == 2)
        #expect(layout.anchorPage(for: 3) == 2)
        #expect(layout.pageRange(containing: 3)?.lowerBound == 2)
        #expect(layout.pageRange(containing: 3)?.upperBound == 3)
    }

    @Test("Adjacent spreads honor reading direction and clamp at both edges")
    func adjacentSpreadsClampToEdges() {
        let leftToRight = makeLayout(pageCount: 5, direction: .leftToRight)
        #expect(leftToRight.adjacentAnchor(from: 0, movingForwardInReadingOrder: true) == 2)
        #expect(leftToRight.adjacentAnchor(from: 4, movingForwardInReadingOrder: true) == 4)
        #expect(leftToRight.adjacentAnchor(from: 0, movingForwardInReadingOrder: false) == 0)

        let rightToLeft = makeLayout(pageCount: 5, direction: .rightToLeft)
        #expect(rightToLeft.adjacentAnchor(from: 0, movingForwardInReadingOrder: true) == 2)
        #expect(rightToLeft.adjacentAnchor(from: 4, movingForwardInReadingOrder: false) == 4)
        #expect(rightToLeft.adjacentAnchor(from: 0, movingForwardInReadingOrder: false) == 0)
    }

    @Test("Single-page layout preserves one page per reading unit")
    func singlePageLayoutRemainsUnchanged() {
        let layout = makeLayout(
            pageCount: 3,
            layout: .single,
            direction: .rightToLeft
        )

        #expect(layout.spreads.map { pageIndexes($0) } == [[2], [1], [0]])
        #expect(layout.anchorPage(for: 1) == 1)
    }

    @Test("Older reading settings default to single-page layout")
    func oldSettingsDefaultToSinglePage() throws {
        let data = try #require(
            #"{"readingMode":"paged","readingDirection":"rightToLeft"}"#.data(using: .utf8)
        )
        let settings = try JSONDecoder().decode(ReadingSettings.self, from: data)

        #expect(settings.pageLayout == .single)
    }

    private func makeLayout(
        pageCount: Int,
        layout: ReaderPageLayout = .double,
        direction: ReadingDirection
    ) -> ReaderSpreadLayout {
        let key = GalleryKey(gid: 100, token: "spread-tests")
        let descriptors = (0..<pageCount).map { index in
            GalleryPageDescriptor(
                galleryKey: key,
                index: index,
                pageURL: URL(string: "https://images.example/\(index).jpg")!
            )
        }
        return ReaderSpreadLayout(
            descriptors: descriptors,
            layout: layout,
            readingDirection: direction
        )
    }

    private func pageIndexes(_ spread: ReaderSpread) -> [Int] {
        spread.pageIndexes
    }
}
