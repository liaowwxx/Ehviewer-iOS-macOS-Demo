/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import EHDomain

struct ReaderSpread: Identifiable {
    let anchorPage: Int
    let leftPage: GalleryPageDescriptor?
    let rightPage: GalleryPageDescriptor?

    var id: Int { anchorPage }

    var pageIndexes: [Int] {
        [leftPage?.index, rightPage?.index].compactMap { $0 }
    }

    var pageRange: ClosedRange<Int>? {
        guard let first = pageIndexes.min(), let last = pageIndexes.max() else { return nil }
        return first...last
    }
}

struct ReaderSpreadLayout {
    let layout: ReaderPageLayout
    let readingDirection: ReadingDirection
    let spreads: [ReaderSpread]

    init(
        descriptors: [GalleryPageDescriptor],
        layout: ReaderPageLayout,
        readingDirection: ReadingDirection
    ) {
        self.layout = layout
        self.readingDirection = readingDirection

        guard descriptors.isEmpty == false else {
            spreads = []
            return
        }

        var logicalSpreads: [ReaderSpread] = []
        var index = 0
        while index < descriptors.count {
            let first = descriptors[index]
            let second = index + 1 < descriptors.count ? descriptors[index + 1] : nil

            switch layout {
            case .single:
                logicalSpreads.append(
                    ReaderSpread(anchorPage: first.index, leftPage: first, rightPage: nil)
                )
            case .double:
                if readingDirection == .leftToRight {
                    logicalSpreads.append(
                        ReaderSpread(anchorPage: first.index, leftPage: first, rightPage: second)
                    )
                } else {
                    logicalSpreads.append(
                        ReaderSpread(anchorPage: first.index, leftPage: second, rightPage: first)
                    )
                }
            }
            index += layout == .double ? 2 : 1
        }

        spreads = readingDirection == .rightToLeft ? Array(logicalSpreads.reversed()) : logicalSpreads
    }

    var displayOrder: [Int] {
        spreads.map(\.anchorPage)
    }

    func anchorPage(for page: Int) -> Int {
        guard let spread = spreads.first(where: { $0.pageIndexes.contains(page) }) else {
            return spreads.first?.anchorPage ?? 0
        }
        return spread.anchorPage
    }

    func spread(containing page: Int) -> ReaderSpread? {
        spreads.first { $0.pageIndexes.contains(page) }
    }

    func pageRange(containing page: Int) -> ClosedRange<Int>? {
        spread(containing: page)?.pageRange
    }

    func adjacentAnchor(from page: Int, movingForwardInReadingOrder: Bool) -> Int {
        guard spreads.isEmpty == false else { return 0 }
        let currentAnchor = anchorPage(for: page)
        let currentIndex = spreads.firstIndex { $0.anchorPage == currentAnchor } ?? 0
        let offset: Int
        if readingDirection == .rightToLeft {
            offset = movingForwardInReadingOrder ? -1 : 1
        } else {
            offset = movingForwardInReadingOrder ? 1 : -1
        }
        let targetIndex = min(max(currentIndex + offset, 0), spreads.count - 1)
        return spreads[targetIndex].anchorPage
    }
}
