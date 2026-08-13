import SwiftUI
import EHDomain

struct BrowseSearchSuggestions: View {
    @Environment(AppModel.self) private var model
    @Binding var searchGalleryKey: GalleryKey?

    var body: some View {
        if let key = SearchQueryComposer.galleryKey(in: model.searchText) {
            Section("打开链接") {
                Button {
                    searchGalleryKey = key
                } label: {
                    Label("打开画廊 \(key.gid)", systemImage: "book")
                }
            }
        }

        if model.searchHistorySuggestions.isEmpty == false {
            Section("搜索历史") {
                ForEach(model.searchHistorySuggestions, id: \.self) { query in
                    Button {
                        model.selectSearchHistory(query)
                    } label: {
                        Label(query, systemImage: "clock.arrow.circlepath")
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
