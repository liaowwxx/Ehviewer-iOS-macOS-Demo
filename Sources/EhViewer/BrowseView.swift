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
import EHDomain
import EHDownloads

struct BrowseView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let model: AppModel
    var kind: GalleryListQuery.ListKind = .home
    let onOpenSearchResults: ((String, GalleryAdvancedSearch?) -> Void)?
    let onOpenGallery: ((GalleryKey) -> Void)?
    @State private var pageModel: BrowsePageModel
    @State private var suppressNextSearchSubmission = false
    @State private var suppressSearchSuggestions = false
    @State private var showingAdvancedSearch = false
    @State private var downloadStatuses: [GalleryKey: GalleryCardDownloadStatus] = [:]
    @State private var hasResolvedDownloadStatuses = false

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
                if model.readingSettings.galleryCard.layoutMode == .waterfall {
                    WaterfallGrid(
                        items: pageModel.galleries, key: \.key,
                        scale: model.readingSettings.galleryCard.cardScale,
                        spacing: horizontalSizeClass == .regular ? 16 : 12,
                        estimatedInformationHeight: model.readingSettings.galleryCard.estimatedInformationHeight
                    ) { gallery in
                        galleryLink(gallery)
                    }
                } else if model.readingSettings.galleryCard.layoutMode == .grid {
                    StableCardGrid(
                        items: pageModel.galleries, key: \.key,
                        scale: model.readingSettings.galleryCard.cardScale,
                        spacing: horizontalSizeClass == .regular ? 16 : 12,
                        isRegularWidth: horizontalSizeClass == .regular
                    ) { gallery in
                        galleryLink(gallery)
                    }
                } else {
                    LazyVGrid(
                        columns: model.readingSettings.galleryCard.columns(isRegularWidth: horizontalSizeClass == .regular),
                        spacing: model.readingSettings.galleryCard.layoutMode == .grid
                            ? (horizontalSizeClass == .regular ? 16 : 12) : 8
                    ) {
                        ForEach(pageModel.galleries) { gallery in
                            galleryLink(gallery)
                        }
                    }
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
            .padding(.horizontal, model.readingSettings.galleryCard.layoutMode == .waterfall ? (horizontalSizeClass == .regular ? 16 : 12) : 10)
            .padding(.vertical, model.readingSettings.galleryCard.layoutMode == .waterfall ? (horizontalSizeClass == .regular ? 16 : 12) : 4)
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
#if os(iOS)
        .searchable(
            text: $pageModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜索画廊或标签"
        )
#else
        .searchable(text: $pageModel.searchText, placement: .toolbar, prompt: "搜索画廊或标签")
#endif
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
                GalleryLayoutMenu()
                if kind == .home || kind == .search {
                    Button("高级搜索", systemImage: "slider.horizontal.3") {
                        showingAdvancedSearch = true
                    }
                    .accessibilityIdentifier("advanced-search-action")
                    if horizontalSizeClass == .compact {
                        BrowseMoreMenu()
                    }
                }
            }
        }
        .refreshable { await pageModel.load(query: pageModel.listQuery) }
        .task(id: BrowseLoadID(query: pageModel.listQuery, configurationID: pageModel.configurationID, refreshToken: model.browseRefreshToken)) {
            await pageModel.loadIfNeeded(query: pageModel.listQuery)
        }
        .task {
            let events = await model.downloads.events()
            await refreshDownloadStatuses()
            for await event in events {
                applyDownloadEvent(event)
            }
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
            GalleryCard(
                gallery: gallery,
                displaySettings: model.readingSettings.galleryCard,
                isCompactWidth: horizontalSizeClass == .compact,
                downloadStatus: hasResolvedDownloadStatuses
                    ? downloadStatuses[gallery.key] ?? .notDownloaded
                    : nil
            )
        }
        .id(gallery.key)
        .buttonStyle(.plain)
    }

    private func refreshDownloadStatuses() async {
        let jobs = await model.downloads.snapshot()
        guard Task.isCancelled == false else { return }
        downloadStatuses = Dictionary(
            uniqueKeysWithValues: jobs.map { ($0.key, GalleryCardDownloadStatus(job: $0)) }
        )
        hasResolvedDownloadStatuses = true
    }

    private func applyDownloadEvent(_ event: DownloadEvent) {
        switch event {
        case .reset(let jobs):
            downloadStatuses = Dictionary(
                uniqueKeysWithValues: jobs.map { ($0.key, GalleryCardDownloadStatus(job: $0)) }
            )
            hasResolvedDownloadStatuses = true
        case .changed(let job):
            let status = GalleryCardDownloadStatus(job: job)
            if downloadStatuses[job.key] != status {
                downloadStatuses[job.key] = status
            }
            hasResolvedDownloadStatuses = true
        case .removed(let key):
            if downloadStatuses.removeValue(forKey: key) != nil {
                hasResolvedDownloadStatuses = true
            }
        case .removedMany(let keys):
            var didChange = false
            for key in keys {
                didChange = downloadStatuses.removeValue(forKey: key) != nil || didChange
            }
            if didChange {
                hasResolvedDownloadStatuses = true
            }
        }
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
    var body: some View {
        Menu("更多", systemImage: "ellipsis.circle") {
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
    @Environment(\.waterfallCoverRatios) private var cachedCoverRatios
    let gallery: GallerySummary
    let displaySettings: GalleryCardDisplaySettings
    let isCompactWidth: Bool
    var supplementalText: String?
    var localJob: DownloadJob?
    var localMediaResolved = true
    var prefersGalleryCache = false
    var showsBackground = true
    var downloadStatus: GalleryCardDownloadStatus?
    var usesPreferredLayout = true
    @State private var coverHeightToWidth = 4.0 / 3.0
    @ScaledMetric(relativeTo: .caption2) private var tagChipHeight = 22.0

    private var isWaterfall: Bool {
        usesPreferredLayout && displaySettings.layoutMode == .waterfall
    }

    private var isGrid: Bool {
        usesPreferredLayout && displaySettings.layoutMode == .grid
    }

    private var displayScale: Double {
        GalleryCardDisplaySettings.clampedScale(isGrid || isWaterfall ? displaySettings.cardScale : displaySettings.listScale)
    }

    private var coverSize: CGSize {
        CGSize(width: 78 * displayScale, height: 108 * displayScale)
    }

    var body: some View {
        Group {
            if isGrid {
                Color.clear
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay { cover }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .contentShape(Rectangle())
            } else if isWaterfall {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .aspectRatio(1 / (cachedCoverRatios?.ratio(for: gallery.key).value ?? coverHeightToWidth), contentMode: .fit)
                        .overlay { cover }
                        .clipped()
                        .overlay(alignment: .topTrailing) {
                            if let downloadStatus {
                                GalleryCardDownloadStatusBadge(status: downloadStatus)
                                    .padding(8)
                            }
                        }
                    informationContent
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
            } else {
                listContent
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isGrid ? displayTitle : accessibilityTitle)
    }

    @ViewBuilder
    private var listContent: some View {
        HStack(spacing: 10) {
            cover
            informationContent
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background {
            if showsBackground {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.12))
            }
        }
    }

    @ViewBuilder
    private var informationContent: some View {
        let settings = effectiveDisplaySettings
        let rating = settings.showsRating ? gallery.rating : nil
        let showsCompactStarRating = isCompactWidth
            && settings.ratingDisplayStyle == .stars
            && rating != nil
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Text(displayTitle)
                    .font(.headline.scaled(by: displayScale))
                    .lineLimit(2)
                Spacer(minLength: 0)
                if isWaterfall == false, let downloadStatus {
                    GalleryCardDownloadStatusBadge(status: downloadStatus)
                }
            }
            if settings.showsAuthor, let authorText {
                Label(authorText, systemImage: "person")
                    .font(.caption.scaled(by: displayScale))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if showsCompactStarRating, let rating {
                GalleryRatingView(rating: rating)
                    .font(.caption)
            }
            if let supplementalText {
                Text(supplementalText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if isWaterfall, let localJob, localJob.state != .completed, localJob.state != .cancelled {
                ProgressView(value: localJob.progress)
                Text("\(Int((localJob.progress * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if settings.showsOrdinaryTags {
                Group {
                    if gallery.tags.isEmpty == false {
                        TagFlowLayout(
                            horizontalSpacing: 5 * (isWaterfall ? displayScale : 1),
                            verticalSpacing: 4 * (isWaterfall ? displayScale : 1),
                            maximumRows: isWaterfall ? 2 : nil
                        ) {
                            ForEach(Array(gallery.tags.enumerated()), id: \.offset) { item in
                                GalleryTagChip(title: model.displayTag(item.element), scale: isWaterfall ? displayScale : 1)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: isWaterfall ? (2 * tagChipHeight + 4) * displayScale : 48, alignment: .topLeading)
                .clipped()
            }
            let metadataLayout = isWaterfall
                ? AnyLayout(TagFlowLayout(horizontalSpacing: 6, verticalSpacing: 4))
                : AnyLayout(HStackLayout(spacing: 6))
            metadataLayout {
                if settings.showsCategoryBadge, let category = gallery.category {
                    CategoryBadge(name: category)
                }
                if settings.showsLanguage, let language = gallery.simpleLanguage {
                    Text(language)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                        .accessibilityLabel("语言 \(language)")
                }
                if settings.showsPageCount, let pageCount = gallery.pageCount { Text("\(pageCount) 页") }
                if let favoriteCategory = gallery.favoriteCategory, favoriteCategory != 0 {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink)
                        .accessibilityLabel("已收藏")
                }
                if isWaterfall == false { Spacer(minLength: 0) }
                if let displayedDate {
                    dateText(displayedDate.date)
                }
                if showsCompactStarRating == false, let rating {
                    switch settings.ratingDisplayStyle {
                    case .numeric:
                        Text(String(format: "%.1f", rating))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    case .stars:
                        GalleryRatingView(rating: rating)
                    }
                }
            }
            .font(.caption.scaled(by: displayScale))
            .foregroundStyle(.secondary)
        }
    }

    private var displayTitle: String {
        gallery.displayTitle(showJapaneseTitle: model.readingSettings.showJapaneseTitle)
    }

    @ViewBuilder
    private var cover: some View {
        if let localJob {
            DownloadCover(
                job: localJob,
                title: displayTitle,
                size: isGrid || isWaterfall ? nil : coverSize,
                cornerRadius: isGrid || isWaterfall ? 14 : 10,
                onImageSize: coverSizeHandler
            )
        } else {
            GalleryThumbnail(
                url: gallery.thumbnailURL,
                key: gallery.key,
                isLocalMediaResolved: localMediaResolved,
                prefersGalleryCache: prefersGalleryCache,
                size: isGrid || isWaterfall ? nil : coverSize,
                cornerRadius: isGrid || isWaterfall ? 14 : 10,
                onImageSize: coverSizeHandler
            )
        }
    }

    private var effectiveDisplaySettings: GalleryCardDisplaySettings {
        displaySettings.effectiveForDisplay(isCompactWidth: isCompactWidth)
    }

    private var coverSizeHandler: ((CGSize) -> Void)? {
        guard isWaterfall else { return nil }
        return { size in updateCoverRatio(size) }
    }

    private func updateCoverRatio(_ size: CGSize) {
        let ratio = WaterfallLayout.heightToWidth(width: size.width, height: size.height)
        if isWaterfall, let cachedCoverRatios {
            let cached = cachedCoverRatios.ratio(for: gallery.key)
            if cached.value != ratio { cached.value = ratio }
        } else if coverHeightToWidth != ratio {
            coverHeightToWidth = ratio
        }
    }

    private var authorText: String? {
        let tags = gallery.preferredAuthorTags
        guard tags.isEmpty == false else { return nil }
        return tags.map(model.displayTag).joined(separator: ", ")
    }

    private var accessibilityTitle: String {
        let settings = effectiveDisplaySettings
        var details = [String]()
        if settings.showsPageCount, let pageCount = gallery.pageCount {
            details.append(String(localized: "\(pageCount) 页"))
        } else if settings.showsPageCount {
            details.append(String(localized: "页数未知"))
        }
        if let supplementalText {
            details.append(supplementalText)
        }
        if settings.showsAuthor, let authorText {
            details.append(String(localized: "作者：\(authorText)"))
        }
        if settings.showsOrdinaryTags, gallery.tags.isEmpty == false {
            let tags = gallery.tags.prefix(3).map(model.displayTag).joined(separator: "、")
            details.append(String(localized: "标签：\(tags)"))
        }
        if settings.showsCategoryBadge, let category = gallery.category {
            details.append(String(localized: "分类：\(category)"))
        }
        if settings.showsLanguage, let language = gallery.simpleLanguage {
            details.append(String(localized: "语言：\(language)"))
        }
        if let displayedDate {
            details.append(
                String(
                    localized: "\(displayedDate.title)：\(displayedDate.date.accessibilityDescription(style: settings.dateDisplayStyle))"
                )
            )
        }
        if settings.showsRating, let rating = gallery.rating {
            details.append(String(localized: "评分 \(rating.formatted(.number.precision(.fractionLength(0...2))))，共 5 星"))
        }
        if let downloadStatus {
            details.append(String(localized: "下载状态：\(downloadStatus.title)"))
        }
        return "\(displayTitle)，" + details.joined(separator: "，")
    }

    @ViewBuilder
    private func dateText(_ postedAt: Date) -> some View {
        switch effectiveDisplaySettings.dateDisplayStyle {
        case .relative:
            Text(postedAt, format: .relative(presentation: .named))
                .lineLimit(1)
        case .absolute:
            Text(postedAt, format: .iso8601.year().month().day().dateSeparator(.dash))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var displayedDate: (title: String, date: Date)? {
        let settings = effectiveDisplaySettings
        if settings.showsPostedAt, let postedAt = gallery.postedAt {
            return (String(localized: "上传日期"), postedAt)
        }
        if settings.showsAddedAt, let addedAt = localJob?.addedAt {
            return (String(localized: "添加时间"), addedAt)
        }
        return nil
    }
}

private extension Date {
    func accessibilityDescription(style: GalleryDateDisplayStyle) -> String {
        switch style {
        case .relative:
            formatted(.relative(presentation: .named))
        case .absolute:
            formatted(.iso8601.year().month().day().dateSeparator(.dash))
        }
    }
}

private struct GalleryTagChip: View {
    let title: String
    var scale = 1.0
    @ScaledMetric(relativeTo: .caption2) private var chipHeight = 22.0

    var body: some View {
        Text(title)
            .font(.caption2.scaled(by: scale))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 7 * scale)
            .frame(height: chipHeight * scale)
            .frame(maxWidth: 160 * scale, alignment: .leading)
            .background(Color.secondary.opacity(0.14), in: Capsule())
            .accessibilityLabel("标签 \(title)")
    }
}

private struct GalleryThumbnail: View {
    @Environment(AppModel.self) private var model
    let url: URL?
    let key: GalleryKey
    var isLocalMediaResolved = true
    var prefersGalleryCache = false
    var size: CGSize? = CGSize(width: 78, height: 108)
    var cornerRadius: CGFloat = 10
    var onImageSize: ((CGSize) -> Void)?
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFill()
            } else {
                PlaceholderThumbnail()
            }
        }
        .frame(width: size?.width, height: size?.height)
        .frame(maxWidth: size == nil ? .infinity : nil, maxHeight: size == nil ? .infinity : nil)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: thumbnailTaskID, priority: .utility) {
            guard isLocalMediaResolved else { return }
            guard let url else { return }
            do {
                let decoded = try await model.coverImage(
                    for: key,
                    previewURL: url,
                    prefersGalleryCache: prefersGalleryCache,
                    maxPixelSize: 500
                )
                guard Task.isCancelled == false, let decoded else { return }
                image = decoded
                onImageSize?(CGSize(width: decoded.width, height: decoded.height))
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
        .accessibilityHidden(true)
    }

    private var thumbnailTaskID: String {
        "\(url?.absoluteString ?? "none")-\(isLocalMediaResolved)"
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
