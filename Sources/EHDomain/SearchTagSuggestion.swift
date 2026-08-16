/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation

public struct SearchTagSuggestion: Identifiable, Hashable, Sendable {
    public let english: String
    public let localizedText: String?
    /// The key as written in the reference tag database before namespace
    /// expansion (e.g. `a:some artist`), used for detail-page tag lookups.
    public let rawKey: String?

    public init(english: String, localizedText: String? = nil, rawKey: String? = nil) {
        self.english = english
        self.localizedText = localizedText
        self.rawKey = rawKey
    }

    public var id: String { english }
}
