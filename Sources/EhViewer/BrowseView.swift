import SwiftUI
import Foundation
import ImageIO
import PhotosUI
import UniformTypeIdentifiers
import EHDomain

struct BrowseView: View {
    @Environment(AppModel.self) private var model
    var kind: GalleryListQuery.ListKind = .home
    @State private var isGrid = true
    @State private var showingImageSearch = false
    @State private var showingAdvancedSearch = false
    @State private var advancedSearch: GalleryAdvancedSearch?
    @State private var submittedAdvancedSearch: GalleryAdvancedSearch?
    @State private var searchGalleryKey: GalleryKey?

    var body: some View {
        @Bindable var model = model
        Group {
            if isGrid {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 16)], spacing: 16) {
                        Section {
                            ForEach(model.galleries) { gallery in
                                galleryLink(gallery)
                                    .task(id: model.nextPageURL) {
                                        await model.loadMoreIfNeeded(after: gallery.key)
                                    }
                            }
                        } footer: {
                            if model.hasMorePage {
                                BrowsePaginationFooter()
                            }
                        }
                    }
                    .padding()
                }
            } else {
                List {
                    ForEach(model.galleries) { gallery in
                        galleryLink(gallery)
                            .task(id: model.nextPageURL) {
                                await model.loadMoreIfNeeded(after: gallery.key)
                            }
                    }
                    if model.hasMorePage {
                        BrowsePaginationFooter()
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(title)
        .searchable(text: $model.searchText, prompt: "搜索画廊或标签")
        .searchSuggestions {
            BrowseSearchSuggestions(searchGalleryKey: $searchGalleryKey)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("搜索", systemImage: "magnifyingglass", action: submitSearch)
                    .accessibilityIdentifier("submit-search")
                Button("刷新", systemImage: "arrow.clockwise") { Task { await model.load(query: listQuery) } }
                if kind == .home || kind == .search {
                    Button("按图片搜索", systemImage: "camera") { showingImageSearch = true }
                }
                if kind == .home || kind == .search || kind == .subscriptions {
                    Button("高级搜索", systemImage: "slider.horizontal.3") { showingAdvancedSearch = true }
                        .accessibilityIdentifier("advanced-search-action")
                }
                Button(isGrid ? "列表视图" : "网格视图", systemImage: isGrid ? "list.bullet" : "square.grid.2x2") {
                    isGrid.toggle()
                }
                .accessibilityLabel(isGrid ? "切换到列表视图" : "切换到网格视图")
            }
        }
        .refreshable { await model.load(query: listQuery) }
        .sheet(isPresented: $showingImageSearch) { ImageSearchSheet() }
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
        .overlay {
            if model.isLoading && model.galleries.isEmpty { ProgressView("加载中…") }
            else if model.galleries.isEmpty { ContentUnavailableView("没有结果", systemImage: "magnifyingglass") }
        }
    }

    private var title: LocalizedStringKey {
        switch kind {
        case .home: "browse_title"
        case .subscriptions: "subscriptions_title"
        case .popular: "popular_title"
        case .toplist: "toplist_title"
        case .favorites: "favorites_title"
        case .search: "browse_title"
        }
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

    @ViewBuilder
    private func galleryLink(_ gallery: GallerySummary) -> some View {
        NavigationLink(value: AppRoute.gallery(gallery.key)) {
            GalleryCard(gallery: gallery, compact: isGrid == false)
        }
        .buttonStyle(.plain)
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
    @Environment(AppModel.self) private var model
    let gallery: GallerySummary
    let compact: Bool

    var body: some View {
        Group {
            if compact {
                HStack(spacing: 12) {
                    GalleryThumbnail(url: gallery.thumbnailURL, key: gallery.key, compact: true)
                    textContent
                    Spacer(minLength: 0)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    GalleryThumbnail(url: gallery.thumbnailURL, key: gallery.key, compact: false)
                    textContent
                }
            }
        }
        .padding(compact ? 8 : 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(gallery.title)，\(gallery.pageCount ?? 0) 页")
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(gallery.title)
                .font(.headline)
                .lineLimit(3)
            if let secondaryTitle = gallery.secondaryTitle {
                Text(secondaryTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack {
                if let category = gallery.category { Text(category) }
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
    let compact: Bool
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
        .frame(minWidth: 72, maxWidth: compact ? 96 : .infinity, minHeight: 112, maxHeight: 150)
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
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(LinearGradient(colors: [.indigo.opacity(0.65), .purple.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay { Image(systemName: "photo").font(.title2).foregroundStyle(.white.opacity(0.85)) }
            .accessibilityHidden(true)
    }
}
