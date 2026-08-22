/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 */

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Shared cover loader for browse, local-library and detail cards. Raw page
/// data is fetched only on a cache miss; the generated thumbnail is reusable
/// across view updates and launches.
actor GalleryCoverLoader {
    static let shared = GalleryCoverLoader()

    private let cache = NSCache<NSString, CGImage>()
    private let diskRoot: URL
    private let decodeLimiter = GalleryImageDecodeLimiter()
    private var inFlight: [String: Task<CGImage?, Error>] = [:]

    static var defaultRootURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("EhViewer/GalleryThumbnails", isDirectory: true)
    }

    init(diskRoot: URL? = nil) {
        self.diskRoot = diskRoot ?? Self.defaultRootURL
        cache.countLimit = 400
        cache.totalCostLimit = 80 * 1_024 * 1_024
    }

    func removeAll() {
        cache.removeAllObjects()
        for task in inFlight.values {
            task.cancel()
        }
        inFlight.removeAll()
        try? FileManager.default.removeItem(at: diskRoot)
    }

    func image(
        for key: String,
        maxPixelSize: Int,
        fetchData: @escaping @Sendable () async throws -> Data
    ) async throws -> CGImage? {
        if let image = cache.object(forKey: key as NSString) {
            return image
        }
        if let task = inFlight[key] {
            return try await task.value
        }

        let diskRoot = self.diskRoot
        let limiter = decodeLimiter
        let task = Task<CGImage?, Error> {
            if let data = try? Data(contentsOf: Self.diskURL(for: key, root: diskRoot)),
               let image = await Self.decode(data: data, maxPixelSize: maxPixelSize, limiter: limiter) {
                return image
            }

            try Task.checkCancellation()
            let data = try await fetchData()
            guard let image = await Self.decode(data: data, maxPixelSize: maxPixelSize, limiter: limiter) else {
                return nil
            }
            Self.write(image: image, to: Self.diskURL(for: key, root: diskRoot))
            return image
        }
        inFlight[key] = task
        do {
            let image = try await task.value
            inFlight[key] = nil
            if let image {
                cache.setObject(
                    image,
                    forKey: key as NSString,
                    cost: image.bytesPerRow * image.height
                )
            }
            return image
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    private static func decode(
        data: Data,
        maxPixelSize: Int,
        limiter: GalleryImageDecodeLimiter
    ) async -> CGImage? {
        await limiter.withPermit {
            await Task.detached(priority: .utility) {
                guard Task.isCancelled == false,
                      let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                    return nil
                }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
                ]
                return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            }.value
        }
    }

    private static func diskURL(for key: String, root: URL) -> URL {
        let encoded = Data(key.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return root.appendingPathComponent("\(encoded).png", isDirectory: false)
    }

    private static func write(image: CGImage, to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            ) else { return }
            CGImageDestinationAddImage(destination, image, nil)
            _ = CGImageDestinationFinalize(destination)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var writableURL = url
            try? writableURL.setResourceValues(values)
        } catch {
            // The cache is intentionally regenerable; a disk write failure
            // must not prevent the current cover from being displayed.
        }
    }
}

private actor GalleryImageDecodeLimiter {
    private let limit = 2
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withPermit<T: Sendable>(_ operation: @Sendable () async -> T) async -> T {
        while active >= limit {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
        active += 1
        let value = await operation()
        active -= 1
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        }
        return value
    }
}
