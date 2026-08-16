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
import EHDomain

struct HomeBrowseView: View {
    let model: AppModel
    @Binding var navigationPath: [AppRoute]

    var body: some View {
        BrowseView(model: model, kind: .home) { query in
            openSearchResults(query)
        } onOpenGallery: { key in
            navigationPath.removeAll()
            navigationPath.append(.gallery(key))
        }
        .onAppear(perform: consumePendingSearch)
        .onChange(of: model.pendingSearchQuery) { _, _ in
            consumePendingSearch()
        }
    }

    private func openSearchResults(_ query: String) {
        navigationPath.removeAll()
        navigationPath.append(.search(query))
    }

    private func consumePendingSearch() {
        guard let query = model.pendingSearchQuery,
              query.isEmpty == false else { return }
        openSearchResults(query)
        model.pendingSearchQuery = nil
    }
}
