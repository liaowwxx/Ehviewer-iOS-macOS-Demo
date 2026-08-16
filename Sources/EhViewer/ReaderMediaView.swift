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

import AVFoundation
import AVKit
import ImageIO
import SwiftUI
import EHDomain
import EHDownloads

struct ReaderMediaView: View {
    let content: Content
    let pageScaling: ReaderPageScaling
    let fitsViewport: Bool

    var body: some View {
        Group {
            switch content {
            case .image(let sequence):
                if sequence.frames.count == 1, let frame = sequence.frames.first {
                    pageImage(frame.image)
                } else {
                    TimelineView(.animation(minimumInterval: sequence.minimumFrameDuration)) { context in
                        pageImage(sequence.frame(at: context.date).image)
                    }
                }
            case .video(let playback):
                VideoPlayer(player: playback.player)
                    .aspectRatio(contentMode: pageScaling == .original ? .fill : .fit)
                    .onAppear(perform: playback.play)
                    .onDisappear(perform: playback.pause)
            }
        }
        .frame(
            maxWidth: pageScaling == .original || pageScaling == .height ? nil : .infinity,
            maxHeight: fitsViewport || pageScaling == .height ? .infinity : nil
        )
    }

    private func pageImage(_ cgImage: CGImage) -> some View {
        Image(decorative: cgImage, scale: 1, orientation: .up)
            .resizable()
            .aspectRatio(content.aspectRatio, contentMode: pageScaling == .original ? .fill : .fit)
    }
}

extension ReaderMediaView {
    enum Content {
        case image(ImageSequence)
        case video(VideoPlayback)

        var aspectRatio: CGFloat {
            switch self {
            case .image(let sequence): sequence.aspectRatio
            case .video: 16 / 9
            }
        }

        var isImage: Bool {
            if case .image = self { return true }
            return false
        }

        @MainActor
        static func decode(_ data: Data) throws -> Self {
            if let source = CGImageSourceCreateWithData(data as CFData, nil),
               CGImageSourceGetCount(source) > 0 {
                return .image(try ImageSequence(source: source))
            }
            guard DownloadMediaValidator.kind(of: data) == .video else {
                throw EHError.parsingFailed(String(localized: "媒体数据无效"))
            }
            let movie = AVMovie(data: data, options: nil)
            return .video(VideoPlayback(item: AVPlayerItem(asset: movie)))
        }
    }

    struct ImageSequence {
        struct Frame {
            let image: CGImage
            let duration: TimeInterval
        }

        let frames: [Frame]
        let aspectRatio: CGFloat
        let totalDuration: TimeInterval
        let minimumFrameDuration: TimeInterval

        init(source: CGImageSource) throws {
            let frameCount = CGImageSourceGetCount(source)
            let decodeAnimatedFrames = frameCount <= 500
            let indexes = decodeAnimatedFrames ? Array(0..<frameCount) : [0]
            let maximumPixelSize = frameCount > 1 ? 1_600 : 2_400
            let options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
            ] as CFDictionary
            let frames = indexes.compactMap { index -> Frame? in
                guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options) else { return nil }
                return Frame(image: image, duration: Self.frameDuration(source: source, index: index))
            }
            guard let first = frames.first, first.image.height > 0 else {
                throw EHError.parsingFailed(String(localized: "媒体图片解码失败"))
            }
            self.frames = frames
            aspectRatio = CGFloat(first.image.width) / CGFloat(first.image.height)
            totalDuration = max(frames.reduce(0) { $0 + $1.duration }, 0.1)
            minimumFrameDuration = max(frames.map(\.duration).min() ?? 0.1, 1.0 / 60.0)
        }

        func frame(at date: Date) -> Frame {
            guard frames.count > 1 else { return frames[0] }
            var elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: totalDuration)
            for frame in frames {
                if elapsed < frame.duration { return frame }
                elapsed -= frame.duration
            }
            return frames[frames.count - 1]
        }

        private static func frameDuration(source: CGImageSource, index: Int) -> TimeInterval {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
                return 0.1
            }
            let candidates: [(CFString, CFString, CFString)] = [
                (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
                (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
                (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
                (kCGImagePropertyHEICSDictionary, kCGImagePropertyHEICSUnclampedDelayTime, kCGImagePropertyHEICSDelayTime)
            ]
            for (dictionaryKey, unclampedKey, delayKey) in candidates {
                guard let dictionary = properties[dictionaryKey] as? [CFString: Any] else { continue }
                let duration = (dictionary[unclampedKey] as? NSNumber)?.doubleValue
                    ?? (dictionary[delayKey] as? NSNumber)?.doubleValue
                if let duration, duration > 0 { return max(duration, 0.02) }
            }
            return 0.1
        }
    }

    @MainActor
    final class VideoPlayback {
        let player: AVQueuePlayer
        private let looper: AVPlayerLooper

        init(item: AVPlayerItem) {
            let player = AVQueuePlayer()
            self.player = player
            looper = AVPlayerLooper(player: player, templateItem: item)
        }

        func play() {
            player.play()
        }

        func pause() {
            player.pause()
        }
    }
}
