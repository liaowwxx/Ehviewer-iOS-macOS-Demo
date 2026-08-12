import CoreGraphics

struct ReaderContinuousZoomState: Equatable {
    static let minimumScale: CGFloat = 1
    static let maximumScale: CGFloat = 2

    private(set) var scale: CGFloat = minimumScale
    private var gestureStartScale: CGFloat?

    mutating func magnificationChanged(_ magnification: CGFloat) {
        if gestureStartScale == nil { gestureStartScale = scale }
        scale = min(
            max((gestureStartScale ?? scale) * magnification, Self.minimumScale),
            Self.maximumScale
        )
    }

    mutating func magnificationEnded(_ magnification: CGFloat) {
        magnificationChanged(magnification)
        gestureStartScale = nil
    }

    mutating func toggle() {
        scale = scale < Self.maximumScale - 0.01 ? Self.maximumScale : Self.minimumScale
        gestureStartScale = nil
    }

    mutating func reset() {
        scale = Self.minimumScale
        gestureStartScale = nil
    }
}
