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
