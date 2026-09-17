/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import SwiftUI

/// Reserve the scaled height as well as scaling the drawing, so the lazy
/// container has correct scroll geometry without relaying out card contents.
struct ProportionalCard<Content: View>: View {
    let referenceWidth: Double
    let width: Double
    @ViewBuilder let content: () -> Content
    private var factor: Double { width / max(1, referenceWidth) }

    var body: some View {
        ProportionalCardLayout(referenceWidth: referenceWidth, width: width) {
            content().scaleEffect(factor, anchor: .topLeading)
        }
    }
}
