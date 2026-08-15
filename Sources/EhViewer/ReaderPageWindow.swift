struct ReaderPageWindow {
    static func indexes(target: Int, pageCount: Int, maximumCount: Int) -> [Int] {
        guard pageCount > 0, maximumCount > 0 else { return [] }

        let count = min(pageCount, maximumCount)
        let clampedTarget = min(max(target, 0), pageCount - 1)
        let maximumStart = pageCount - count
        let centeredStart = clampedTarget - count / 2
        let start = min(max(centeredStart, 0), maximumStart)
        return Array(start..<(start + count))
    }

    static func maximumCount(
        forAvailableWidth width: Double,
        thumbnailWidth: Double = 60,
        spacing: Double = 8,
        horizontalPadding: Double = 24
    ) -> Int {
        guard width > 0, thumbnailWidth > 0 else { return 1 }
        let contentWidth = max(width - horizontalPadding, thumbnailWidth)
        let count = Int(((contentWidth + spacing) / (thumbnailWidth + spacing)).rounded(.down))
        return max(count, 1)
    }
}
