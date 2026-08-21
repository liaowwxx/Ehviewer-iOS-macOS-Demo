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
import Foundation
import ImageIO
import EHDomain
import EHDownloads

struct BrowseView: View {
    let model: AppModel
    var kind: GalleryListQuery.ListKind = .home
    let onOpenSearchResults: ((String, GalleryAdvancedSearch?) -> Void)?
    let onOpenGallery: ((GalleryKey) -> Void)?
    @State private var pageModel: BrowsePageModel
    @State private var suppressNextSearchSubmission = false
    @State private var suppressSearchSuggestions = false
    @State private var showingAdvancedSearch = false

    init(
        model: AppModel,
        kind: GalleryListQuery.ListKind = .home,
        initialSearchText: String? = nil,
        onOpenSearchResults: ((String, GalleryAdvancedSearch?) -> Void)? = nil,
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
        onOpenSearchResults: ((String, GalleryAdvancedSearch?) -> Void)? = nil,
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
            if pageModel.searchText.isEmpty == false {
                SearchTagChipBar(query: pageModel.searchText) { updatedQuery in
                    pageModel.searchText = updatedQuery
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
            }
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
        .overlay(alignment: .topTrailing) {
            GeometryReader { proxy in
                BrowseSearchSuggestionOverlay(
                    query: pageModel.searchText,
                    isLoading: pageModel.isUpdatingSearchSuggestions,
                    searchHistory: pageModel.searchHistorySuggestions,
                    tags: pageModel.tagSearchSuggestions,
                    isSuppressed: suppressSearchSuggestions,
                    onSelectHistory: { query in
                        suppressSearchSuggestions = false
                        pageModel.selectSearchHistory(query)
                    },
                    onDeleteHistory: { query in
                        Task { await pageModel.deleteSearchHistory(query) }
                    },
                    onSelectTag: { tag in
                        suppressNextSearchSubmission = true
                        suppressSearchSuggestions = false
                        pageModel.completeTagSuggestion(tag)
                        Task { @MainActor in
                            await Task.yield()
                            suppressNextSearchSubmission = false
                        }
                    }
                )
                    .frame(width: min(560, max(0, proxy.size.width - 24)))
                    .padding(.top, 8)
                    .padding(.trailing, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            .zIndex(100)
        }
        .navigationTitle(navigationTitle)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .searchable(text: $pageModel.searchText, placement: .toolbar, prompt: "搜索画廊或标签")
        .onSubmit(of: .search, submitSearch)
        .onChange(of: pageModel.searchText) { _, newValue in
            let normalized = SearchQueryComposer.normalized(newValue)
            if normalized.isEmpty {
                suppressNextSearchSubmission = false
                suppressSearchSuggestions = false
            } else if normalized != pageModel.submittedSearchText {
                suppressSearchSuggestions = false
            }
        }
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
                if kind == .home || kind == .search {
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
        suppressSearchSuggestions = true
        let query = SearchQueryComposer.normalized(pageModel.searchText)
        guard query.isEmpty == false else {
            pageModel.clearSearch()
            return
        }
        if kind == .home, let onOpenSearchResults {
            if let url = URL(string: query), let key = AppModel.galleryKey(from: url) {
                onOpenGallery?(key)
            } else {
                onOpenSearchResults(query, pageModel.advancedSearch)
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
            GalleryCard(gallery: gallery, showsTags: true)
        }
        .id(gallery.key)
        .buttonStyle(.plain)
    }
}

private struct BrowseSearchSuggestionOverlay: View {
    @Environment(\.isSearching) private var isSearching
    let query: String
    let isLoading: Bool
    let searchHistory: [String]
    let tags: [SearchTagSuggestion]
    let isSuppressed: Bool
    let onSelectHistory: (String) -> Void
    let onDeleteHistory: (String) -> Void
    let onSelectTag: (String) -> Void

    var body: some View {
        if isSearching, isSuppressed == false {
            SearchSuggestionPanel(
                query: query,
                isLoading: isLoading,
                searchHistory: searchHistory,
                tags: tags,
                onSelectHistory: onSelectHistory,
                onDeleteHistory: onDeleteHistory,
                onSelectTag: onSelectTag
            )
        }
    }
}

/// Renders the tag tokens of the search query as removable capsules, styled
/// like the filter-rule candidate bar. Tapping a capsule removes that tag
/// token from the query, so several tags can be composed and adjusted freely.
struct SearchTagChipBar: View {
    @Environment(AppModel.self) private var model
    let query: String
    let onUpdate: (String) -> Void

    var body: some View {
        let tokens = SearchQueryComposer.tagTokens(in: query)
        if tokens.isEmpty == false {
            TagFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                    Button {
                        onUpdate(SearchQueryComposer.removing(token, from: query))
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "tag")
                                .font(.caption2)
                            Text(model.displayTag(token.fullTag))
                                .lineLimit(1)
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.semibold))
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .foregroundStyle(.white)
                        .background(AppTheme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("移除标签 \(token.fullTag)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

struct GalleryCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let gallery: GallerySummary
    var supplementalText: String?
    var showsTags = false
    var localJob: DownloadJob?
    var metadataIsLoading = false
    @State private var titleHeight: CGFloat = 0

    var body: some View {
        HStack(spacing: 10) {
            if let localJob {
                DownloadCover(
                    job: localJob,
                    title: displayTitle,
                    fallbackPreviewURL: gallery.thumbnailURL,
                    size: CGSize(width: 78, height: 108),
                    cornerRadius: 10
                )
            } else {
                GalleryThumbnail(url: gallery.thumbnailURL, key: gallery.key)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { newHeight in
                        guard abs(titleHeight - newHeight) > 0.5 else { return }
                        titleHeight = newHeight
                    }
                Group {
                    if metadataIsLoading {
                        metadataPlaceholder(width: 112)
                    } else if let authorText {
                        Label(authorText, systemImage: "person")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .transition(.opacity)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: metadataIsLoading)
                if let supplementalText {
                    Text(supplementalText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if showsTags {
                    Group {
                        if metadataIsLoading {
                            HStack(spacing: 5) {
                                metadataPlaceholder(width: 58)
                                metadataPlaceholder(width: 76)
                                metadataPlaceholder(width: 46)
                            }
                        } else if gallery.tags.isEmpty == false {
                            TagFlowLayout(horizontalSpacing: 5, verticalSpacing: 4) {
                                ForEach(Array(gallery.tags.enumerated()), id: \.offset) { item in
                                    GalleryTagChip(title: model.displayTag(item.element))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: tagHeight, alignment: .topLeading)
                    .clipped()
                    .transition(.opacity)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: metadataIsLoading)
                }
                Group {
                    if metadataIsLoading {
                        HStack(spacing: 6) {
                            metadataPlaceholder(width: 76)
                            metadataPlaceholder(width: 54)
                            Spacer(minLength: 0)
                            metadataPlaceholder(width: 66)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
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
                                Text(String(format: "%.1f", rating))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .transition(.opacity)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: metadataIsLoading)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityTitle)
    }

    private var displayTitle: String {
        gallery.displayTitle(showJapaneseTitle: model.readingSettings.showJapaneseTitle)
    }

    private var authorText: String? {
        let tags = gallery.preferredAuthorTags
        guard tags.isEmpty == false else { return nil }
        return tags.map(model.displayTag).joined(separator: ", ")
    }

    private var tagHeight: CGFloat {
        titleHeight > 30 ? 22 : 48
    }

    private func metadataPlaceholder(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.secondary.opacity(0.2))
            .frame(width: width, height: 13)
            .accessibilityHidden(true)
    }

    private var accessibilityTitle: String {
        var details = [String]()
        if let pageCount = gallery.pageCount {
            details.append(String(localized: "\(pageCount) 页"))
        } else {
            details.append(String(localized: "页数未知"))
        }
        if let supplementalText {
            details.append(supplementalText)
        }
        if let authorText {
            details.append(String(localized: "作者：\(authorText)"))
        }
        if showsTags, gallery.tags.isEmpty == false {
            let tags = gallery.tags.prefix(3).map(model.displayTag).joined(separator: "、")
            details.append(String(localized: "标签：\(tags)"))
        }
        return "\(displayTitle)，" + details.joined(separator: "，")
    }
}

private struct GalleryTagChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .frame(maxWidth: 160, alignment: .leading)
            .background(Color.secondary.opacity(0.14), in: Capsule())
            .accessibilityLabel("标签 \(title)")
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
