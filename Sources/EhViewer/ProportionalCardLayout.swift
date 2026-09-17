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

/// Measure at the reference width and report the scaled extent in the same
/// layout pass. No geometry-to-state feedback is needed by the lazy stack.
struct ProportionalCardLayout: Layout {
    let referenceWidth: Double
    let width: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(ProposedViewSize(width: referenceWidth, height: nil)) ?? .zero
        return scaledSize(size)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin, anchor: .topLeading,
            proposal: ProposedViewSize(width: referenceWidth, height: nil)
        )
    }

    func scaledSize(_ size: CGSize) -> CGSize {
        CGSize(width: width, height: size.height * width / max(1, referenceWidth))
    }
}
