import CoreGraphics

struct ReaderZoomState: Equatable {
    static let minimumScale: CGFloat = 1
    static let maximumScale: CGFloat = 10

    private(set) var scale: CGFloat = minimumScale
    private(set) var offset: CGSize = .zero
    private var magnificationStartScale: CGFloat?
    private var magnificationStartOffset: CGSize?
    private var dragStartOffset: CGSize?

    var isZoomed: Bool { scale > Self.minimumScale + 0.001 }

    mutating func magnificationChanged(
        _ magnification: CGFloat,
        viewportSize: CGSize,
        fittedContentSize: CGSize,
        focus: CGPoint? = nil
    ) {
        if magnificationStartScale == nil {
            magnificationStartScale = scale
            magnificationStartOffset = offset
            dragStartOffset = nil
        }
        let startScale = magnificationStartScale ?? scale
        let newScale = min(max(startScale * magnification, Self.minimumScale), Self.maximumScale)
        let startOffset = magnificationStartOffset ?? offset
        offset = focusPreservingOffset(
            from: startScale,
            to: newScale,
            currentOffset: startOffset,
            focus: focus,
            viewportSize: viewportSize
        )
        scale = newScale
        offset = clamped(offset, viewportSize: viewportSize, fittedContentSize: fittedContentSize)
    }

    mutating func magnificationEnded(
        _ magnification: CGFloat,
        viewportSize: CGSize,
        fittedContentSize: CGSize,
        focus: CGPoint? = nil
    ) {
        magnificationChanged(
            magnification,
            viewportSize: viewportSize,
            fittedContentSize: fittedContentSize,
            focus: focus
        )
        magnificationStartScale = nil
        magnificationStartOffset = nil
        if scale < 1.05 {
            reset()
        } else {
            offset = clamped(offset, viewportSize: viewportSize, fittedContentSize: fittedContentSize)
        }
    }

    mutating func dragChanged(
        _ translation: CGSize,
        viewportSize: CGSize,
        fittedContentSize: CGSize
    ) {
        guard isZoomed else { return }
        if dragStartOffset == nil { dragStartOffset = offset }
        let startOffset = dragStartOffset ?? offset
        offset = clamped(
            CGSize(width: startOffset.width + translation.width, height: startOffset.height + translation.height),
            viewportSize: viewportSize,
            fittedContentSize: fittedContentSize
        )
    }

    mutating func dragEnded(
        _ translation: CGSize,
        viewportSize: CGSize,
        fittedContentSize: CGSize
    ) -> Int? {
        let startOffset = dragStartOffset ?? offset
        let proposedOffset = CGSize(
            width: startOffset.width + translation.width,
            height: startOffset.height + translation.height
        )
        let maximum = maximumOffset(viewportSize: viewportSize, fittedContentSize: fittedContentSize)
        offset = clamped(proposedOffset, viewportSize: viewportSize, fittedContentSize: fittedContentSize)
        dragStartOffset = nil
        guard abs(translation.width) > abs(translation.height) * 1.5 else { return nil }
        let pageTurnThreshold: CGFloat = 44
        if proposedOffset.width < -maximum.width - pageTurnThreshold { return 1 }
        if proposedOffset.width > maximum.width + pageTurnThreshold { return -1 }
        return nil
    }

    mutating func advanceZoom(
        candidates: [CGFloat],
        viewportSize: CGSize,
        fittedContentSize: CGSize,
        focus: CGPoint? = nil
    ) {
        let normalizedCandidates = candidates
            .map { min(max($0, Self.minimumScale), Self.maximumScale) }
            .sorted()
        let oldScale = scale
        let newScale = normalizedCandidates.first(where: { scale < $0 - 0.01 }) ?? Self.minimumScale
        offset = focusPreservingOffset(
            from: oldScale,
            to: newScale,
            currentOffset: offset,
            focus: focus,
            viewportSize: viewportSize
        )
        scale = newScale
        offset = clamped(offset, viewportSize: viewportSize, fittedContentSize: fittedContentSize)
        if isZoomed == false { offset = .zero }
        magnificationStartScale = nil
        magnificationStartOffset = nil
        dragStartOffset = nil
    }

    mutating func contentSizeChanged(viewportSize: CGSize, fittedContentSize: CGSize) {
        offset = clamped(offset, viewportSize: viewportSize, fittedContentSize: fittedContentSize)
    }

    func canPanHorizontally(viewportSize: CGSize, fittedContentSize: CGSize) -> Bool {
        maximumOffset(viewportSize: viewportSize, fittedContentSize: fittedContentSize).width > 0.5
    }

    func canPanVertically(viewportSize: CGSize, fittedContentSize: CGSize) -> Bool {
        maximumOffset(viewportSize: viewportSize, fittedContentSize: fittedContentSize).height > 0.5
    }

    mutating func reset() {
        scale = Self.minimumScale
        offset = .zero
        magnificationStartScale = nil
        magnificationStartOffset = nil
        dragStartOffset = nil
    }

    private func clamped(_ candidate: CGSize, viewportSize: CGSize, fittedContentSize: CGSize) -> CGSize {
        let maximum = maximumOffset(viewportSize: viewportSize, fittedContentSize: fittedContentSize)
        return CGSize(
            width: min(max(candidate.width, -maximum.width), maximum.width),
            height: min(max(candidate.height, -maximum.height), maximum.height)
        )
    }

    private func maximumOffset(viewportSize: CGSize, fittedContentSize: CGSize) -> CGSize {
        guard viewportSize.width.isFinite, viewportSize.height.isFinite,
              fittedContentSize.width.isFinite, fittedContentSize.height.isFinite,
              viewportSize.width > 0, viewportSize.height > 0,
              fittedContentSize.width > 0, fittedContentSize.height > 0 else { return .zero }
        return CGSize(
            width: max((fittedContentSize.width * scale - viewportSize.width) / 2, 0),
            height: max((fittedContentSize.height * scale - viewportSize.height) / 2, 0)
        )
    }

    private func focusPreservingOffset(
        from oldScale: CGFloat,
        to newScale: CGFloat,
        currentOffset: CGSize,
        focus: CGPoint?,
        viewportSize: CGSize
    ) -> CGSize {
        guard oldScale > 0 else { return currentOffset }
        let resolvedFocus = focus ?? CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        let focusFromCenter = CGSize(
            width: resolvedFocus.x - viewportSize.width / 2,
            height: resolvedFocus.y - viewportSize.height / 2
        )
        let ratio = newScale / oldScale
        return CGSize(
            width: focusFromCenter.width - (focusFromCenter.width - currentOffset.width) * ratio,
            height: focusFromCenter.height - (focusFromCenter.height - currentOffset.height) * ratio
        )
    }
}
