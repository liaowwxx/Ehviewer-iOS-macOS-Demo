/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

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
