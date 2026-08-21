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

struct SearchSuggestionPanel: View {
    let query: String
    let isLoading: Bool
    let searchHistory: [String]
    let tags: [SearchTagSuggestion]
    let onSelectHistory: (String) -> Void
    let onDeleteHistory: (String) -> Void
    let onSelectTag: (String) -> Void

    private var headerTitle: String {
        query.isEmpty ? "搜索历史" : "标签建议"
    }

    private var headerIcon: String {
        query.isEmpty ? "clock" : "tag"
    }

    private var hasSuggestions: Bool {
        searchHistory.isEmpty == false || tags.isEmpty == false
    }

    private var emptyStateTitle: String {
        if isLoading {
            return query.isEmpty ? "正在读取搜索历史…" : "正在更新标签建议…"
        }
        return query.isEmpty ? "暂无搜索历史" : "没有匹配的建议"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: headerIcon)
                Text(headerTitle)
                Spacer(minLength: 0)
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if hasSuggestions {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        ForEach(searchHistory, id: \.self) { history in
                            Button {
                                onSelectHistory(history)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundStyle(.secondary)
                                    Text(history)
                                        .lineLimit(2)
                                    Spacer(minLength: 0)
                                }
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("删除历史", systemImage: "trash", role: .destructive) {
                                    onDeleteHistory(history)
                                }
                            }
                        }

                        ForEach(tags) { suggestion in
                            Button {
                                onSelectTag(suggestion.english)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "tag")
                                        .foregroundStyle(AppTheme.accent)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(suggestion.english)
                                        if let localizedText = suggestion.localizedText,
                                           localizedText.localizedCaseInsensitiveCompare(suggestion.english) != .orderedSame {
                                            Text(localizedText)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(suggestion.localizedText.map { String(localized: "\(suggestion.english)，\($0)") } ?? suggestion.english)
                        }
                    }
                }
                .frame(maxHeight: 240)
            } else {
                Label(
                    emptyStateTitle,
                    systemImage: isLoading ? "ellipsis" : (query.isEmpty ? "clock" : "magnifyingglass")
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }
}
