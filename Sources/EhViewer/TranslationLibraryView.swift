import SwiftUI
import EHDomain

struct TranslationLibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            ForEach(galleries) { version in
                NavigationLink {
                    GalleryDetailView(key: version.gallery.key)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(version.gallery.title)
                        Text("\(model.translationLibrary.versions[version.gallery.key]?.count ?? 0) 个译件版本")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay {
            if galleries.isEmpty { ContentUnavailableView("暂无译件", systemImage: "character.book.closed") }
        }
        .navigationTitle("译件资料库")
        .task { await model.translationLibrary.refresh() }
    }

    private var galleries: [GalleryTranslationManifest] {
        model.translationLibrary.versions.values.compactMap { $0.first }.sorted { $0.createdAt > $1.createdAt }
    }
}
