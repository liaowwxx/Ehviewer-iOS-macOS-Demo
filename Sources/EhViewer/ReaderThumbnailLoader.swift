#if os(iOS)
import CoreGraphics
import Foundation
import ImageIO

actor ReaderThumbnailLoader {
    static let shared = ReaderThumbnailLoader()

    private let cache = NSCache<NSString, CGImage>()

    private init() {
        cache.countLimit = 48
        cache.totalCostLimit = 24 * 1_024 * 1_024
    }

    func cachedThumbnail(for key: String) -> CGImage? {
        cache.object(forKey: key as NSString)
    }

    func thumbnail(for key: String, data: Data) async -> CGImage? {
        if let cached = cachedThumbnail(for: key) {
            return cached
        }
        guard let image = await Self.decode(data), Task.isCancelled == false else {
            return nil
        }
        cache.setObject(
            image,
            forKey: key as NSString,
            cost: image.bytesPerRow * image.height
        )
        return image
    }

    @concurrent
    private static func decode(_ data: Data) async -> CGImage? {
        guard Task.isCancelled == false,
              let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 320
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            imageSource,
            0,
            options as CFDictionary
        ), Task.isCancelled == false else {
            return nil
        }
        return image
    }
}
#endif
