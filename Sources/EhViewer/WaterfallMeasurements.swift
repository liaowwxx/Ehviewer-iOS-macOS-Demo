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

/// Measurements are a cache, not view state. Recording a visible card's height
/// must not invalidate or rebuild the lazy columns while scrolling.
@MainActor
final class WaterfallMeasurements {
    var heights: [GalleryKey: Double] = [:]
    private var ratios: [GalleryKey: WaterfallCoverRatio] = [:]

    func ratio(for key: GalleryKey) -> WaterfallCoverRatio {
        if let existing = ratios[key] { return existing }
        let entry = WaterfallCoverRatio()
        ratios[key] = entry
        return entry
    }

    func retain(_ keys: Set<GalleryKey>) {
        heights = heights.filter { keys.contains($0.key) }
        ratios = ratios.filter { keys.contains($0.key) }
    }
}
