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

struct LibraryView: View {
    enum Mode: String, CaseIterable, Identifiable, Hashable {
        case history
        case favorites

        var id: Self { self }
    }
    @Environment(AppModel.self) private var model
    @State private var selectedMode: Mode
    @State private var readingPages: [GalleryKey: Int] = [:]

    init(mode: Mode = .history) {
        _selectedMode = State(initialValue: mode)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                HStack {
                    Text(selectedMode == .history ? "最近阅读" : "本地收藏")
                        .font(.headline)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)

                ForEach(items) { gallery in
                    NavigationLink(value: AppRoute.gallery(gallery.key)) {
                        GalleryCard(
                            gallery: gallery,
                            supplementalText: selectedMode == .history ? progressText(for: gallery) : nil,
                            showsTags: true
                        )
                    }
                    .buttonStyle(.plain)
                    .id(gallery.key)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .navigationTitle(selectedMode == .history ? "history_title" : "favorites_title")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("资料库", selection: $selectedMode) {
                    Text("history_title").tag(Mode.history)
                    Text("favorites_title").tag(Mode.favorites)
                }
                .pickerStyle(.segmented)
                .frame(minWidth: 220, maxWidth: .infinity)
            }
        }
        .overlay {
            if items.isEmpty { ContentUnavailableView("暂无记录", systemImage: selectedMode == .history ? "clock" : "heart") }
        }
        .task(id: selectedMode) {
            await model.loadLibrary(mode: selectedMode)
            guard selectedMode == .history else {
                readingPages = [:]
                return
            }
            var loadedPages: [GalleryKey: Int] = [:]
            for gallery in model.historyGalleries {
                if let page = await model.readingPage(for: gallery.key) {
                    loadedPages[gallery.key] = page
                }
            }
            readingPages = loadedPages
        }
    }

    private var items: [GallerySummary] {
        selectedMode == .history ? model.historyGalleries : model.favoriteGalleries
    }

    private func progressText(for gallery: GallerySummary) -> String {
        guard let page = readingPages[gallery.key] else { return String(localized: "未记录进度") }
        if let pageCount = gallery.pageCount, pageCount > 0 {
            return String(localized: "阅读到 \(min(page + 1, pageCount))/\(pageCount) 页")
        }
        return String(localized: "阅读到第 \(page + 1) 页")
    }
}
