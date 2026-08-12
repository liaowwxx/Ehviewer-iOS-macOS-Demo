import SwiftUI
import EHDomain

struct BrowseSearchSuggestions: View {
    @Environment(AppModel.self) private var model
    @Binding var searchGalleryKey: GalleryKey?

    var body: some View {
        if let key = SearchQueryComposer.galleryKey(in: model.searchText) {
            Section("打开链接") {
                Button("打开画廊 \(key.gid)", systemImage: "book") {
                    searchGalleryKey = key
                }
            }
        }

        if model.searchHistorySuggestions.isEmpty == false {
            Section("搜索历史") {
                ForEach(model.searchHistorySuggestions, id: \.self) { query in
                    Button(query, systemImage: "clock.arrow.circlepath") {
                        model.selectSearchHistory(query)
                    }
                    .contextMenu {
                        Button("删除搜索记录", systemImage: "trash", role: .destructive) {
                            Task { await model.deleteSearchHistory(query) }
                        }
                    }
                }
            }
        }

        if model.tagSearchSuggestions.isEmpty == false {
            Section("标签") {
                ForEach(model.tagSearchSuggestions) { suggestion in
                    Button {
                        model.completeTagSuggestion(suggestion.english)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(suggestion.english)
                            if let localizedText = suggestion.localizedText,
                               localizedText.localizedCaseInsensitiveCompare(suggestion.english) != .orderedSame {
                                Text(localizedText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityLabel(suggestion.localizedText.map { "\(suggestion.english)，\($0)" } ?? suggestion.english)
                }
            }
        }
    }
}
