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

struct BrowsePaginationFooter: View {
    var errorMessage: String?
    var retry: () -> Void = {}

    var body: some View {
        Group {
            if let errorMessage {
                VStack(spacing: 8) {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("重试加载更多", systemImage: "arrow.clockwise", action: retry)
                        .buttonStyle(.bordered)
                }
            } else {
                ProgressView("正在加载更多…")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .accessibilityIdentifier("browse-pagination-footer")
    }
}
