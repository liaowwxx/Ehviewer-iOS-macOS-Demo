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

struct BrowseSearchSuggestions: View {
    let query: String
    let isUpdating: Bool
    let searchHistory: [String]
    let tags: [SearchTagSuggestion]
    let onSelectHistory: (String) -> Void
    let onDeleteHistory: (String) -> Void
    let onSelectTag: (String) -> Void

    var body: some View {
        Group {
            if isUpdating || hasSuggestions == false {
                Section {
                    if isUpdating {
                        HStack {
                            ProgressView()
                            Text(query.isEmpty ? String(localized: "正在读取搜索历史…") : String(localized: "正在更新“\(query)”的建议…"))
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        Label(
                            query.isEmpty ? String(localized: "暂无搜索历史") : String(localized: "没有匹配的建议"),
                            systemImage: query.isEmpty ? "clock" : "magnifyingglass"
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            }
            if searchHistory.isEmpty == false {
                Section("搜索历史") {
                    ForEach(searchHistory, id: \.self) { query in
                        Button {
                            onSelectHistory(query)
                        } label: {
                            Label(query, systemImage: "clock.arrow.circlepath")
                        }
                        .contextMenu {
                            Button("删除历史", systemImage: "trash", role: .destructive) {
                                onDeleteHistory(query)
                            }
                        }
                    }
                }
            }
            if tags.isEmpty == false {
                Section("标签") {
                    ForEach(tags) { suggestion in
                        Button {
                            onSelectTag(suggestion.english)
                        } label: {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(suggestion.english)
                                    if let localizedText = suggestion.localizedText,
                                       localizedText.localizedCaseInsensitiveCompare(suggestion.english) != .orderedSame {
                                        Text(localizedText)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            } icon: {
                                Image(systemName: "tag")
                            }
                        }
                        .accessibilityLabel(suggestion.localizedText.map { String(localized: "\(suggestion.english)，\($0)") } ?? suggestion.english)
                    }
                }
            }
        }
    }

    private var hasSuggestions: Bool {
        searchHistory.isEmpty == false || tags.isEmpty == false
    }
}
