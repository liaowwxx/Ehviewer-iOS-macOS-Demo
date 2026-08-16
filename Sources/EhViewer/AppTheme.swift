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

import SwiftUI

enum AppTheme {
    /// RGB 0.259, 0.581, 0.533 from the supplied reference.
    static let accent = Color(red: 0.259, green: 0.581, blue: 0.533)
    static let onAccent = Color.white

    /// The reference client's `colorAccent` (#e040fb), used for tag group
    /// headers in the light theme.
    static let secondaryAccent = Color(red: 0.878, green: 0.251, blue: 0.984)

    /// Reference `tagBackgroundColor`: the primary teal. Kept the same in both
    /// color schemes so tags stay distinguishable from group headers in dark
    /// mode instead of both turning gray.
    static let tagBackground = accent

    /// Reference `tagGroupBackgroundColor`: the accent purple, kept distinct
    /// from tag chips in every color scheme.
    static let tagGroupBackground = secondaryAccent
}
