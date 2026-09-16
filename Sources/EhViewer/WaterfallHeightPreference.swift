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
import EHDomain

struct WaterfallHeightPreference: PreferenceKey {
    static let defaultValue: [GalleryKey: Double] = [:]
    static func reduce(value: inout [GalleryKey: Double], nextValue: () -> [GalleryKey: Double]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
