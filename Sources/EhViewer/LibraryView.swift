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

    init(mode: Mode = .history) {
        _selectedMode = State(initialValue: mode)
    }

    var body: some View {
        List {
            Section(selectedMode == .history ? "最近阅读" : "本地收藏") {
                ForEach(items) { gallery in
                    NavigationLink(value: AppRoute.gallery(gallery.key)) {
                        VStack(alignment: .leading) {
                            Text(gallery.preferredTitle).font(.headline)
                            Text(gallery.alternateTitle ?? "未记录进度").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(selectedMode == .history ? "history_title" : "favorites_title")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("资料库", selection: $selectedMode) {
                    Text("history_title").tag(Mode.history)
                    Text("favorites_title").tag(Mode.favorites)
                }
                .pickerStyle(.segmented)
            }
        }
        .overlay {
            if items.isEmpty { ContentUnavailableView("暂无记录", systemImage: selectedMode == .history ? "clock" : "heart") }
        }
        .task(id: selectedMode) { await model.loadLibrary(mode: selectedMode) }
    }

    private var items: [GallerySummary] {
        selectedMode == .history ? model.historyGalleries : model.favoriteGalleries
    }
}
