import SwiftUI
import EHDomain

struct BrowseSearchSuggestions: View {
    let pageModel: BrowsePageModel
    let onSelectTag: (String) -> Void

    var body: some View {
        if pageModel.tagSearchSuggestions.isEmpty == false {
            Section("标签") {
                ForEach(pageModel.tagSearchSuggestions) { suggestion in
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
