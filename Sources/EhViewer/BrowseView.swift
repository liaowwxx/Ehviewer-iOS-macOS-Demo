import SwiftUI
import Foundation
import ImageIO
import EHDomain

struct BrowseView: View {
    let model: AppModel
    var kind: GalleryListQuery.ListKind = .home
    let onOpenSearchResults: ((String) -> Void)?
    let onOpenGallery: ((GalleryKey) -> Void)?
    @State private var pageModel: BrowsePageModel
    @State private var suppressNextSearchSubmission = false
    @State private var showingAdvancedSearch = false

    init(
        model: AppModel,
        kind: GalleryListQuery.ListKind = .home,
        initialSearchText: String? = nil,
        onOpenSearchResults: ((String) -> Void)? = nil,
        onOpenGallery: ((GalleryKey) -> Void)? = nil
    ) {
        self.model = model
        self.kind = kind
        self.onOpenSearchResults = onOpenSearchResults
        self.onOpenGallery = onOpenGallery
        _pageModel = State(initialValue: BrowsePageModel(
            model: model,
            kind: kind,
            initialSearchText: initialSearchText
        ))
    }

    init(
        model: AppModel,
        pageModel: BrowsePageModel,
        onOpenSearchResults: ((String) -> Void)? = nil,
        onOpenGallery: ((GalleryKey) -> Void)? = nil
    ) {
        self.model = model
        kind = pageModel.kind
        self.onOpenSearchResults = onOpenSearchResults
        self.onOpenGallery = onOpenGallery
        _pageModel = State(initialValue: pageModel)
    }

    var body: some View {
        @Bindable var pageModel = pageModel

        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(pageModel.galleries) { gallery in
                    galleryLink(gallery)
                }
                if pageModel.nextPageURL != nil {
                    if pageModel.shouldAutomaticallyLoadMore {
                        BrowsePaginationFooter()
                            .task(id: pageModel.nextPageURL) {
                                await pageModel.loadMore()
                            }
                    } else {
                        Button("继续查找未屏蔽内容", systemImage: "arrow.down") {
                            Task { await pageModel.continueAfterFilteredPages() }
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .scrollPosition(id: $pageModel.scrollPosition, anchor: .top)
        .overlay {
            if pageModel.isLoading && pageModel.galleries.isEmpty { ProgressView("加载中…") }
            else if pageModel.galleries.isEmpty, let message = pageModel.errorMessage {
                VStack(spacing: 12) {
                    ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(message))
                    Button("重试", systemImage: "arrow.clockwise") {
                        pageModel.errorMessage = nil
                        Task { await pageModel.load(query: pageModel.listQuery) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            else if pageModel.galleries.isEmpty { ContentUnavailableView("没有结果", systemImage: "magnifyingglass") }
        }
        .navigationTitle(navigationTitle)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .searchable(text: $pageModel.searchText, placement: .toolbar, prompt: "搜索画廊或标签")
        .searchSuggestions {
            BrowseSearchSuggestions(
                query: pageModel.suggestionQuery,
                isUpdating: pageModel.isUpdatingSearchSuggestions,
                searchHistory: pageModel.searchHistorySuggestions,
                tags: pageModel.tagSearchSuggestions,
                onSelectHistory: { query in
                    pageModel.selectSearchHistory(query)
                },
                onDeleteHistory: { query in
                    Task { await pageModel.deleteSearchHistory(query) }
                },
                onSelectTag: { tag in
                    suppressNextSearchSubmission = true
                    pageModel.completeTagSuggestion(tag)
                    Task { @MainActor in
                        await Task.yield()
                        suppressNextSearchSubmission = false
                    }
                }
            )
        }
        .onSubmit(of: .search, submitSearch)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if kind != .search, hasSearchInput {
                    Button("清除搜索", systemImage: "xmark.circle") {
                        clearSearch()
                    }
                    .accessibilityIdentifier("clear-search-action")
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if kind == .home {
                    BrowseMoreMenu {
                        showingAdvancedSearch = true
                    }
                }
            }
        }
        .refreshable { await pageModel.load(query: pageModel.listQuery) }
        .task(id: BrowseLoadID(query: pageModel.listQuery, configurationID: pageModel.configurationID, refreshToken: model.browseRefreshToken)) {
            await pageModel.loadIfNeeded(query: pageModel.listQuery)
        }
        .task(id: pageModel.searchText) {
            let query = pageModel.searchText
            await pageModel.refreshSearchSuggestions(for: query)
        }
        .sheet(isPresented: $showingAdvancedSearch) {
            AdvancedSearchView(
                initialValue: pageModel.advancedSearch,
                apply: { value in pageModel.advancedSearch = value },
                clear: { pageModel.advancedSearch = nil }
            )
        }
    }

    private var titleKey: LocalizedStringKey {
        switch kind {
        case .home: "browse_title"
        case .subscriptions: "subscriptions_title"
        case .popular: "popular_title"
        case .toplist: "toplist_title"
        case .favorites: "favorites_title"
        case .search: "browse_title"
        }
    }

    private var navigationTitle: Text {
        kind == .search ? Text("搜索结果") : Text(titleKey)
    }

    private var hasSearchInput: Bool {
        pageModel.searchText.isEmpty == false
    }

    private func submitSearch() {
        guard suppressNextSearchSubmission == false else {
            suppressNextSearchSubmission = false
            return
        }
        let query = SearchQueryComposer.normalized(pageModel.searchText)
        guard query.isEmpty == false else {
            pageModel.clearSearch()
            return
        }
        if kind == .home, let onOpenSearchResults {
            if let url = URL(string: query), let key = AppModel.galleryKey(from: url) {
                onOpenGallery?(key)
            } else {
                onOpenSearchResults(query)
            }
            pageModel.clearSearch()
        } else {
            pageModel.submitSearch()
        }
    }

    private func clearSearch() {
        pageModel.clearSearch()
    }

    private func galleryLink(_ gallery: GallerySummary) -> some View {
        NavigationLink(value: AppRoute.gallery(gallery.key)) {
            GalleryCard(gallery: gallery)
        }
        .id(gallery.key)
        .buttonStyle(.plain)
    }
}

private struct BrowseMoreMenu: View {
    let showAdvancedSearch: () -> Void

    var body: some View {
        Menu("更多", systemImage: "ellipsis.circle") {
            Button("高级搜索", systemImage: "slider.horizontal.3", action: showAdvancedSearch)
            Section("浏览") {
                NavigationLink(value: AppRoute.subscriptions) {
                    Label("subscriptions_title", systemImage: "tag")
                }
                NavigationLink(value: AppRoute.popular) {
                    Label("popular_title", systemImage: "chart.line.uptrend.xyaxis")
                }
                NavigationLink(value: AppRoute.toplist) {
                    Label("toplist_title", systemImage: "list.number")
                }
            }
        }
        .accessibilityIdentifier("more-menu")
    }
}

private struct BrowseLoadID: Hashable {
    let query: GalleryListQuery
    let configurationID: String
    let refreshToken: Int
}

private struct GalleryCard: View {
    @Environment(AppModel.self) private var model
    let gallery: GallerySummary

    var body: some View {
        HStack(spacing: 10) {
            GalleryThumbnail(url: gallery.thumbnailURL, key: gallery.key)
            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                if let uploader = gallery.uploader {
                    Label(uploader, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    if let category = gallery.category {
                        CategoryBadge(name: category)
                    }
                    if let language = gallery.simpleLanguage {
                        Text(language)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                            .accessibilityLabel("语言 \(language)")
                    }
                    if let pageCount = gallery.pageCount { Text("\(pageCount) 页") }
                    if let favoriteCategory = gallery.favoriteCategory, favoriteCategory != 0 {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.pink)
                            .accessibilityLabel("已收藏")
                    }
                    Spacer(minLength: 0)
                    if let postedAt = gallery.postedAt {
                        Text(postedAt, format: .relative(presentation: .named))
                            .lineLimit(1)
                    }
                    if let rating = gallery.rating {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityTitle)
    }

    private var displayTitle: String {
        gallery.displayTitle(showJapaneseTitle: model.readingSettings.showJapaneseTitle)
    }

    private var accessibilityTitle: String {
        if let pageCount = gallery.pageCount {
            return "\(displayTitle)，\(pageCount) 页"
        }
        return "\(displayTitle)，页数未知"
    }
}

private struct GalleryThumbnail: View {
    @Environment(AppModel.self) private var model
    let url: URL?
    let key: GalleryKey
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                PlaceholderThumbnail()
            }
        }
        .frame(width: 78, height: 108)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: url) {
            guard let url else { return }
            do {
                let page = GalleryPageImage(galleryKey: key, index: 0, imageURL: url)
                let data = try await model.imageData(for: page)
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                          kCGImageSourceCreateThumbnailFromImageAlways: true,
                          kCGImageSourceCreateThumbnailWithTransform: true,
                          kCGImageSourceThumbnailMaxPixelSize: 500
                      ] as CFDictionary) else { return }
                image = Image(decorative: cgImage, scale: 1, orientation: .up)
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
        .accessibilityHidden(true)
    }
}

private struct PlaceholderThumbnail: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(colorScheme == .dark ? Color(white: 0.18) : Color(white: 0.88))
            .overlay { Image(systemName: "photo").font(.title2).foregroundStyle(.secondary) }
            .accessibilityHidden(true)
    }
}
