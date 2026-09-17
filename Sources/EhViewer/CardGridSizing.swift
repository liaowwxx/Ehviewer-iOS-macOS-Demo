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

/// Sidebar changes affect the detail width, whereas window changes affect
/// both widths. Keep a reference layout for the former and rebase for the latter.
struct CardGridSizing {
    private(set) var referenceWidth = 0.0
    private(set) var currentWidth = 0.0
    private var windowWidth = 0.0
    private(set) var columns = 1

    mutating func update(width: Double, windowWidth: Double, target: Double, spacing: Double, force: Bool = false) {
        guard width.isFinite, width > 1 else { return }
        let previousReference = referenceWidth
        if referenceWidth == 0 || force || (windowWidth == 0 && self.windowWidth == 0) {
            referenceWidth = width
        } else if windowWidth > 0, self.windowWidth > 0, abs(windowWidth - self.windowWidth) > 1 {
            referenceWidth = max(1, referenceWidth + windowWidth - self.windowWidth)
        }
        currentWidth = width
        if windowWidth > 0 { self.windowWidth = windowWidth }
        if force || previousReference == 0 || abs(referenceWidth - previousReference) > 1 {
            columns = max(1, Int((referenceWidth + spacing) / (max(1, target) + spacing)))
        }
    }

    func referenceColumnWidth(spacing: Double) -> Double {
        max(1, (referenceWidth - Double(columns - 1) * spacing) / Double(columns))
    }

    func currentColumnWidth(spacing: Double) -> Double {
        max(1, (currentWidth - Double(columns - 1) * spacing) / Double(columns))
    }

    func scale(spacing: Double) -> Double {
        currentColumnWidth(spacing: spacing) / referenceColumnWidth(spacing: spacing)
    }
}
