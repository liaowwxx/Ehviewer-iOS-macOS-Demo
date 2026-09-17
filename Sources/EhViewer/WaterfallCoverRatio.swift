/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Observation

/// Each cover observes its own ratio, without invalidating the other columns.
@MainActor
@Observable
final class WaterfallCoverRatio {
    var value = 4.0 / 3.0
}
