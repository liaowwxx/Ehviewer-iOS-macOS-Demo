/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation
import EHDomain

enum WaterfallLayout {
    static func heightToWidth(width: Double, height: Double) -> Double {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return 4.0 / 3.0 }
        return min(4.0 / 3.0, max(1, height / width))
    }

    static func columnCount(width: Double, spacing: Double, scale: Double, accessibility: Bool) -> Int {
        guard width.isFinite, width > 0, accessibility == false else { return 1 }
        let target = 170 * GalleryCardDisplaySettings.clampedScale(scale)
        return max(1, Int((width + spacing) / (target + spacing)))
    }

    static func assignments(
        keys: [GalleryKey], heights: [GalleryKey: Double], count: Int,
        spacing: Double, estimatedHeight: Double,
        preserving: [GalleryKey: Int] = [:]
    ) -> [GalleryKey: Int] {
        let count = max(1, count)
        var totals = Array(repeating: 0.0, count: count)
        var result: [GalleryKey: Int] = [:]
        for key in keys {
            let column: Int
            if let previous = preserving[key], (0..<count).contains(previous) {
                column = previous
            } else {
                column = totals.indices.min { totals[$0] < totals[$1] } ?? 0
            }
            result[key] = column
            let measured = heights[key] ?? estimatedHeight
            totals[column] += (measured.isFinite && measured > 0 ? measured : estimatedHeight) + spacing
        }
        return result
    }
}
