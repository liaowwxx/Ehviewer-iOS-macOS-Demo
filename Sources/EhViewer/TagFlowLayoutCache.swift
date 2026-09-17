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

struct TagFlowLayoutCache {
    var layout: TagFlowLayout?
    var itemCount = 0
    var width: CGFloat?
    var sizes: [CGSize] = []
    var rows: [[Int]] = []
    var size: CGSize = .zero
    var isValid = false
}
