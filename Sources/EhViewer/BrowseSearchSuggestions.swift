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
                            Text(query.isEmpty ? "正在读取搜索历史…" : "正在更新“\(query)”的建议…")
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        Label(
                            query.isEmpty ? "暂无搜索历史" : "没有匹配的建议",
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
                        .accessibilityLabel(suggestion.localizedText.map { "\(suggestion.english)，\($0)" } ?? suggestion.english)
                    }
                }
            }
        }
    }

    private var hasSuggestions: Bool {
        searchHistory.isEmpty == false || tags.isEmpty == false
    }
}
