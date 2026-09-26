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
    private var activeReaderLoads = 0
    private var readerLoadWaiters: [(UUID, CheckedContinuation<Bool, Never>)] = []

    private init() {
        cache.countLimit = 48
        cache.totalCostLimit = 24 * 1_024 * 1_024
    }

    func cachedThumbnail(for key: String) -> CGImage? {
        cache.object(forKey: key as NSString)
    }

    /// Bounds original-image reads and thumbnail decodes while scrolling the reader grid.
    func readerThumbnail(
        for key: String,
        loadData: @MainActor @Sendable () async -> Data?
    ) async -> CGImage? {
        if let cached = cachedThumbnail(for: key) { return cached }
        guard await acquireReaderLoadSlot() else { return nil }
        defer { releaseReaderLoadSlot() }
        if let cached = cachedThumbnail(for: key) { return cached }
        guard Task.isCancelled == false,
              let data = await loadData(),
              Task.isCancelled == false else { return nil }
        return await thumbnail(for: key, data: data)
    }

    func thumbnail(for key: String, data: Data) async -> CGImage? {
        guard Task.isCancelled == false else { return nil }
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

    private func acquireReaderLoadSlot() async -> Bool {
        guard Task.isCancelled == false else { return false }
        if activeReaderLoads < 4 {
            activeReaderLoads += 1
            return true
        }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                } else {
                    readerLoadWaiters.append((id, continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelReaderLoadWaiter(id) }
        }
    }

    private func cancelReaderLoadWaiter(_ id: UUID) {
        guard let index = readerLoadWaiters.firstIndex(where: { $0.0 == id }) else { return }
        let (_, continuation) = readerLoadWaiters.remove(at: index)
        continuation.resume(returning: false)
    }

    private func releaseReaderLoadSlot() {
        if readerLoadWaiters.isEmpty {
            activeReaderLoads -= 1
        } else {
            readerLoadWaiters.removeFirst().1.resume(returning: true)
        }
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
