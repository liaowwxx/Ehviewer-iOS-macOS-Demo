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

struct GalleryRatingView: View {
    private static let starCount = 5

    let rating: Double

    private var clampedRating: Double {
        min(max(rating, 0), Double(Self.starCount))
    }

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<Self.starCount, id: \.self) { index in
                GalleryRatingStar(fillFraction: min(max(clampedRating - Double(index), 0), 1))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("评分 \(rating.formatted(.number.precision(.fractionLength(0...2))))，共 5 星")
    }
}

private struct GalleryRatingStar: View {
    let fillFraction: Double

    var body: some View {
        Image(systemName: "star")
            .foregroundStyle(.tertiary)
            .overlay(alignment: .leading) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.orange)
                    .mask {
                        Rectangle()
                            .scaleEffect(x: fillFraction, anchor: .leading)
                    }
            }
            .accessibilityHidden(true)
    }
}
