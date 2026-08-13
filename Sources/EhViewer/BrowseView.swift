import SwiftUI
import Foundation
import ImageIO
import PhotosUI
import UniformTypeIdentifiers
import EHDomain

struct BrowseView: View {
    @Environment(AppModel.self) private var model
    var kind: GalleryListQuery.ListKind = .home
    @State private var showingAdvancedSearch = false
    @State private var advancedSearch: GalleryAdvancedSearch?
    @State private var submittedAdvancedSearch: GalleryAdvancedSearch?
    @State private var searchGalleryKey: GalleryKey?

    var body: some View {
        @Bindable var model = model

        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(model.galleries) { gallery in
                    galleryLink(gallery)
                        .task(id: model.nextPageURL) {
                            await model.loadMoreIfNeeded(after: gallery.key)
                        }
                }
                if model.hasMorePage {
                    BrowsePaginationFooter()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .overlay {
            if model.isLoading && model.galleries.isEmpty { ProgressView("加载中…") }
            else if model.galleries.isEmpty { ContentUnavailableView("没有结果", systemImage: "magnifyingglass") }
        }
        .navigationTitle(navigationTitle)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "搜索画廊或标签")
        .searchSuggestions {
            BrowseSearchSuggestions(searchGalleryKey: $searchGalleryKey)
        }
        .onSubmit(of: .search, submitSearch)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if hasSearchInput {
                    Button("清除搜索", systemImage: "xmark.circle") {
                        clearSearch()
                    }
                    .accessibilityIdentifier("clear-search-action")
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if kind == .home || kind == .search || kind == .subscriptions {
                    Button("高级搜索", systemImage: "slider.horizontal.3") { showingAdvancedSearch = true }
                        .accessibilityIdentifier("advanced-search-action")
                }
                BrowseMoreMenu()
            }
        }
        .refreshable { await model.load(query: listQuery) }
        .sheet(isPresented: $showingAdvancedSearch) {
            AdvancedSearchView(
                initialValue: advancedSearch,
                apply: { advancedSearch = $0 },
                clear: { advancedSearch = nil }
            )
        }
        .task {
            await model.loadQuickSearches()
        }
        .task(id: model.searchText) {
            await model.updateSearchSuggestions(for: model.searchText)
        }
        .task(id: model.site) {
            await model.loadBrowseQuery(listQuery)
        }
        .navigationDestination(item: $searchGalleryKey) { key in
            GalleryDetailView(key: key)
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
        guard isSearchResults else { return Text(titleKey) }
        if model.submittedSearchText.isEmpty {
            return Text("筛选结果")
        }
        return Text("搜索结果：\(model.submittedSearchText)")
    }

    private var isSearchResults: Bool {
        model.submittedSearchText.isEmpty == false || submittedAdvancedSearch != nil
    }

    private var hasSearchInput: Bool {
        model.searchText.isEmpty == false || isSearchResults
    }

    private var listQuery: GalleryListQuery {
        GalleryListQuery(
            site: model.site,
            kind: kind,
            searchText: model.submittedSearchText.isEmpty ? nil : model.submittedSearchText,
            advancedSearch: submittedAdvancedSearch
        )
    }

    private func submitSearch() {
        if let key = SearchQueryComposer.galleryKey(in: model.searchText) {
            searchGalleryKey = key
        } else {
            model.submitSearch()
            submittedAdvancedSearch = advancedSearch
            let query = GalleryListQuery(
                site: model.site,
                kind: kind,
                searchText: model.submittedSearchText.isEmpty ? nil : model.submittedSearchText,
                advancedSearch: submittedAdvancedSearch
            )
            Task { await model.load(query: query) }
        }
    }

    private func clearSearch() {
        model.searchText = ""
        model.submittedSearchText = ""
        submittedAdvancedSearch = nil
        advancedSearch = nil
        Task {
            await model.load(query: GalleryListQuery(site: model.site, kind: kind))
        }
    }

    private func galleryLink(_ gallery: GallerySummary) -> some View {
        NavigationLink(value: AppRoute.gallery(gallery.key)) {
            GalleryCard(gallery: gallery)
        }
        .buttonStyle(.plain)
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
            Section("个人") {
                NavigationLink(value: AppRoute.history) {
                    Label("history_title", systemImage: "clock")
                }
                NavigationLink(value: AppRoute.favorites) {
                    Label("favorites_title", systemImage: "heart")
                }
            }
        }
        .accessibilityIdentifier("more-menu")
    }
}

private struct ImageSearchSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var importedData: Data?
    @State private var importedName = "upload.jpg"
    @State private var similar = true
    @State private var covers = false
    @State private var expanded = false
    @State private var showingImporter = false
    @State private var isLoadingPhoto = false

    var body: some View {
        NavigationStack {
            Form {
                Section("图片") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("从照片选择", systemImage: "photo.on.rectangle")
                    }
                    Button("从文件选择", systemImage: "folder") { showingImporter = true }
                    if let importedData {
                        Label("已选择 \(importedName)（\(ByteCountFormatter.string(fromByteCount: Int64(importedData.count), countStyle: .file))）", systemImage: "checkmark.circle")
                            .font(.caption)
                    }
                }
                Section("搜索选项") {
                    Toggle("相似图片", isOn: $similar)
                    Toggle("包含封面结果", isOn: $covers)
                    Toggle("扩展结果", isOn: $expanded)
                }
                Section("图片配额") {
                    if let quota = model.imageQuota {
                        LabeledContent("已使用", value: "\(quota.used.formatted()) / \(quota.total.formatted())")
                        LabeledContent("重置费用", value: "\(quota.resetCost.formatted()) GP")
                    }
                    HStack {
                        Button("查看配额") { Task { await model.loadImageQuota() } }
                        if model.imageQuota != nil {
                            Button("重置配额", role: .destructive) { Task { await model.resetImageQuota() } }
                        }
                    }
                }
            }
            .navigationTitle("图片搜索")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isLoadingPhoto {
                        ProgressView()
                    } else {
                        Button("搜索") {
                            guard let importedData else { return }
                            Task {
                                await model.searchByImage(
                                    data: importedData,
                                    fileName: importedName,
                                    options: ImageSearchOptions(similar: similar, covers: covers, expanded: expanded)
                                )
                                dismiss()
                            }
                        }
                        .disabled(importedData == nil)
                    }
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.image]) { result in
                guard case .success(let url) = result else { return }
                do {
                    importedData = try Data(contentsOf: url)
                    importedName = url.lastPathComponent
                } catch {
                    model.errorMessage = error.localizedDescription
                }
            }
            .task(id: selectedPhoto) {
                guard let selectedPhoto else { return }
                isLoadingPhoto = true
                defer { isLoadingPhoto = false }
                do {
                    importedData = try await selectedPhoto.loadTransferable(type: Data.self)
                    importedName = "photo.jpg"
                } catch is CancellationError {
                    return
                } catch {
                    model.errorMessage = error.localizedDescription
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct GalleryCard: View {
    let gallery: GallerySummary

    var body: some View {
        HStack(spacing: 10) {
            GalleryThumbnail(url: gallery.thumbnailURL, key: gallery.key)
            textContent
            Spacer(minLength: 0)
        }
        .padding(6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(gallery.preferredTitle)，\(gallery.pageCount ?? 0) 页")
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(gallery.preferredTitle)
                .font(.headline)
                .lineLimit(2)
            if let alternateTitle = gallery.alternateTitle {
                Text(alternateTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack {
                if let pageCount = gallery.pageCount { Text("· \(pageCount) 页") }
                Spacer()
                if let rating = gallery.rating { Label(String(format: "%.1f", rating), systemImage: "star.fill") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
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
