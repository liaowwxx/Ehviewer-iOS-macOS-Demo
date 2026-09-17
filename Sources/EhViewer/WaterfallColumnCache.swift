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

/// Cache indices, rather than item snapshots, so metadata changes are rendered
/// from the latest items without repeating one full-array filter per column.
final class WaterfallColumnCache {
    private var keys: [GalleryKey] = []
    private var placement: [GalleryKey: Int] = [:]
    private var count = 0
    private var columns: [[Int]] = []
    private(set) var rebuildCount = 0

    func indices(keys: [GalleryKey], placement: [GalleryKey: Int], count: Int) -> [[Int]] {
        guard self.keys != keys || self.placement != placement || self.count != count else { return columns }
        self.keys = keys
        self.placement = placement
        self.count = count
        columns = Array(repeating: [], count: max(1, count))
        for (index, key) in keys.enumerated() {
            if let column = placement[key], columns.indices.contains(column) {
                columns[column].append(index)
            }
        }
        rebuildCount += 1
        return columns
    }
}
