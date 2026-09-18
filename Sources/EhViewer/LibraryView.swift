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
import EHDomain
import EHDownloads

struct LibraryView: View {
    enum Mode: String, CaseIterable, Identifiable, Hashable {
        case history
        case favorites

        var id: Self { self }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let mode: Mode
    @State private var isSelectionMode = false
    @State private var selectedKeys: Set<GalleryKey> = []
    @State private var deletionConfirmation: LibraryDeletionConfirmation?
    @State private var readingPages: [GalleryKey: Int] = [:]
    @State private var downloadedJobs: [GalleryKey: DownloadJob] = [:]
    @State private var downloadedJobsReady = false
    @State private var libraryKeys: Set<GalleryKey> = []
    @State private var bulkDownloadProgress: GalleryDownloadEnqueueProgress?
    @State private var bulkDownloadFailureCount = 0

    init(mode: Mode = .history) {
        self.mode = mode
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                HStack {
                    Text(mode == .history ? "最近阅读" : "本地收藏")
                        .font(.headline)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)

                if model.readingSettings.galleryCard.layoutMode == .waterfall {
                    WaterfallGrid(
                        items: items, key: \.key, scale: model.readingSettings.galleryCard.cardScale,
                        spacing: horizontalSizeClass == .regular ? 16 : 12,
                        estimatedInformationHeight: model.readingSettings.galleryCard.estimatedInformationHeight
                    ) { gallery in
                        libraryRow(for: gallery).equatable()
                    }
                } else if model.readingSettings.galleryCard.layoutMode == .grid {
                    StableCardGrid(
                        items: items, key: \.key,
                        scale: model.readingSettings.galleryCard.cardScale,
                        spacing: horizontalSizeClass == .regular ? 16 : 12,
                        isRegularWidth: horizontalSizeClass == .regular
                    ) { gallery in
                        libraryRow(for: gallery).equatable()
                    }
                } else {
                    LazyVGrid(
                        columns: model.readingSettings.galleryCard.columns(isRegularWidth: horizontalSizeClass == .regular),
                        spacing: model.readingSettings.galleryCard.layoutMode == .grid
                            ? (horizontalSizeClass == .regular ? 16 : 12) : 8
                    ) {
                        ForEach(items) { gallery in
                            libraryRow(for: gallery)
                                .equatable()
                        }
                    }
                }
            }
            .padding(.horizontal, model.readingSettings.galleryCard.layoutMode == .waterfall ? (horizontalSizeClass == .regular ? 16 : 12) : 10)
            .padding(.vertical, model.readingSettings.galleryCard.layoutMode == .waterfall ? (horizontalSizeClass == .regular ? 16 : 12) : 4)
        }
        .navigationTitle(mode == .history ? "history_title" : "favorites_title")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                GalleryLayoutMenu()
            }
            if isSelectionMode {
#if os(macOS)
                ToolbarItem(placement: .navigation) {
                    Button("完成") { exitSelectionMode() }
                }
#else
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { exitSelectionMode() }
                }
#endif
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(selectAllTitle) {
                        toggleSelectAll()
                    }
                    Button(action: downloadSelectedItems) {
                        if let bulkDownloadProgress {
                            Label(
                                "加入下载 \(bulkDownloadProgress.completed)/\(bulkDownloadProgress.total)",
                                systemImage: "arrow.down.circle"
                            )
                        } else {
                            Label("下载(\(undownloadedSelectedCount))", systemImage: "arrow.down.circle")
                        }
                    }
                    .disabled(
                        downloadedJobsReady == false
                            || undownloadedSelectedCount == 0
                            || bulkDownloadProgress != nil
                    )
                    .accessibilityIdentifier("download-selected-library-items-action")
                    .accessibilityLabel("下载选中的未下载漫画")
                    .accessibilityValue(
                        bulkDownloadProgress.map { "\($0.completed)/\($0.total)" } ?? ""
                    )
                    Button(role: .destructive) {
                        deletionConfirmation = LibraryDeletionConfirmation(
                            mode: mode,
                            count: selectedKeys.count
                        )
                    } label: {
                        Label("删除(\(selectedKeys.count))", systemImage: "trash")
                    }
                    .disabled(selectedKeys.isEmpty)
                }
            } else {
                if mode == .favorites {
                    ToolbarItem(placement: .primaryAction) {
                        favoriteDownloadToolbarButton
                    }
                }
#if os(macOS)
                ToolbarItem(placement: .navigation) {
                    selectionToolbarButton
                }
#else
                if horizontalSizeClass == .regular {
                    ToolbarItem(placement: .navigation) {
                        selectionToolbarButton
                    }
                } else {
                    ToolbarItem(placement: .primaryAction) {
                        selectionToolbarButton
                    }
                }
#endif
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(
                    "暂无记录",
                    systemImage: mode == .history ? "clock" : "heart"
                )
            }
        }
        .alert(item: $deletionConfirmation) { confirmation in
            Alert(
                title: Text("移除选中的 \(confirmation.count) 项\(confirmation.itemName)？"),
                message: Text(confirmation.message),
                primaryButton: .destructive(Text("删除")) {
                    deleteSelectedItems(mode: confirmation.mode)
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .alert("部分画廊未能加入下载", isPresented: bulkDownloadFailureAlertPresented) {
            Button("好") {
                bulkDownloadFailureCount = 0
            }
        } message: {
            Text("有 \(bulkDownloadFailureCount) 项无法加载下载所需的画廊信息，可稍后再次尝试。")
        }
        .task(id: mode) {
            await model.loadLibrary(mode: mode)
        }
        .task(id: libraryMetadataTaskID) {
            let libraryKeys = Set(items.map(\.key))
            self.libraryKeys = libraryKeys
            let jobs = await model.downloads.snapshot()
            guard Task.isCancelled == false else { return }
            downloadedJobs = Dictionary(
                uniqueKeysWithValues: jobs
                    .filter { libraryKeys.contains($0.key) }
                    .map { ($0.key, $0) }
            )
            downloadedJobsReady = true

            guard mode == .history else {
                readingPages = [:]
                return
            }
            let loadedPages = (try? await model.persistence.readingPages(for: libraryKeys)) ?? [:]
            guard Task.isCancelled == false else { return }
            readingPages = loadedPages
        }
        .task {
            for await event in await model.downloads.events() {
                applyDownloadEvent(event)
            }
        }
    }

    private var items: [GallerySummary] {
        mode == .history ? model.historyGalleries : model.favoriteGalleries
    }

    private var libraryMetadataTaskID: String {
        "\(mode.rawValue)|\(items.map { $0.key.id }.joined(separator: "|"))"
    }

    private var selectAllTitle: String {
        selectedKeys.count == items.count && items.isEmpty == false ? "取消全选" : "全选"
    }

    private var selectionToolbarButton: some View {
        Button("选择", systemImage: "checkmark.circle") {
            enterSelectionMode()
        }
        .accessibilityHint("选择要操作的项目")
        .labelStyle(.titleAndIcon)
        .disabled(items.isEmpty)
    }

    private var favoriteDownloadToolbarButton: some View {
        Button {
            downloadUndownloadedFavorites()
        } label: {
            if let bulkDownloadProgress {
                Label(
                    "加入下载 \(bulkDownloadProgress.completed)/\(bulkDownloadProgress.total)",
                    systemImage: "arrow.down.circle"
                )
            } else {
                Label("下载全部未下载", systemImage: "arrow.down.circle")
            }
        }
        .accessibilityIdentifier("download-all-undownloaded-favorites-action")
        .accessibilityLabel("下载全部未下载")
        .accessibilityValue(
            bulkDownloadProgress.map { "\($0.completed)/\($0.total)" } ?? ""
        )
        .disabled(
            downloadedJobsReady == false
                || undownloadedFavoriteCount == 0
                || bulkDownloadProgress != nil
        )
    }

    private var undownloadedFavoriteCount: Int {
        guard mode == .favorites else { return 0 }
        return undownloadedCount(in: items)
    }

    private var selectedItems: [GallerySummary] {
        items.filter { selectedKeys.contains($0.key) }
    }

    private var undownloadedSelectedCount: Int {
        undownloadedCount(in: selectedItems)
    }

    private var bulkDownloadFailureAlertPresented: Binding<Bool> {
        Binding(
            get: { bulkDownloadFailureCount > 0 },
            set: { isPresented in
                if isPresented == false {
                    bulkDownloadFailureCount = 0
                }
            }
        )
    }

    private func libraryRow(for gallery: GallerySummary) -> LibraryGalleryRow {
        LibraryGalleryRow(
            gallery: gallery,
            supplementalText: mode == .history ? progressText(for: gallery) : nil,
            localJob: downloadedJobs[gallery.key],
            localMediaResolved: downloadedJobsReady,
            downloadStatus: downloadedJobsReady
                ? GalleryCardDownloadStatus(job: downloadedJobs[gallery.key])
                : nil,
            displaySettings: model.readingSettings.galleryCard,
            isCompactWidth: horizontalSizeClass == .compact,
            isSelectionMode: isSelectionMode,
            isSelected: selectedKeys.contains(gallery.key),
            select: { toggleSelection(gallery.key) },
            requestSelection: { enterSelectionMode(selecting: gallery.key) }
        )
    }

    private func downloadUndownloadedFavorites() {
        guard mode == .favorites,
              bulkDownloadProgress == nil,
              downloadedJobsReady,
              undownloadedFavoriteCount > 0 else {
            return
        }

        downloadUndownloadedItems(items)
    }

    private func downloadSelectedItems() {
        guard selectedItems.isEmpty == false else { return }
        downloadUndownloadedItems(selectedItems)
    }

    private func downloadUndownloadedItems(_ galleries: [GallerySummary]) {
        let total = undownloadedCount(in: galleries)
        guard bulkDownloadProgress == nil,
              downloadedJobsReady,
              total > 0 else {
            return
        }

        bulkDownloadProgress = GalleryDownloadEnqueueProgress(
            completed: 0,
            total: total,
            enqueued: 0,
            failed: 0
        )
        Task { @MainActor in
            let result = await model.enqueueUndownloadedGalleries(galleries) { progress in
                bulkDownloadProgress = progress
            }
            guard Task.isCancelled == false else { return }
            bulkDownloadProgress = nil
            if result.failed > 0 {
                bulkDownloadFailureCount = result.failed
            }
        }
    }

    private func undownloadedCount(in galleries: [GallerySummary]) -> Int {
        galleries.reduce(into: 0) { count, gallery in
            if downloadedJobs[gallery.key] == nil {
                count += 1
            }
        }
    }

    private func applyDownloadEvent(_ event: DownloadEvent) {
        switch event {
        case .reset(let jobs):
            downloadedJobs = Dictionary(
                uniqueKeysWithValues: jobs
                    .filter { libraryKeys.contains($0.key) }
                    .map { ($0.key, $0) }
            )
            downloadedJobsReady = true
        case .changed(let job) where libraryKeys.contains(job.key):
            downloadedJobs[job.key] = job
            downloadedJobsReady = true
        case .removed(let key) where libraryKeys.contains(key):
            downloadedJobs.removeValue(forKey: key)
        case .removedMany(let keys):
            for key in keys where libraryKeys.contains(key) {
                downloadedJobs.removeValue(forKey: key)
            }
        default:
            break
        }
    }

    private func progressText(for gallery: GallerySummary) -> String {
        guard let page = readingPages[gallery.key] else { return String(localized: "未记录进度") }
        if let pageCount = gallery.pageCount, pageCount > 0 {
            return String(localized: "阅读到 \(min(page + 1, pageCount))/\(pageCount) 页")
        }
        return String(localized: "阅读到第 \(page + 1) 页")
    }

    private func enterSelectionMode(selecting key: GalleryKey? = nil) {
        isSelectionMode = true
        if let key {
            selectedKeys.insert(key)
        }
    }

    private func exitSelectionMode() {
        isSelectionMode = false
        selectedKeys.removeAll()
    }

    private func toggleSelection(_ key: GalleryKey) {
        if selectedKeys.contains(key) {
            selectedKeys.remove(key)
        } else {
            selectedKeys.insert(key)
        }
    }

    private func toggleSelectAll() {
        if selectedKeys.count == items.count && items.isEmpty == false {
            selectedKeys.removeAll()
        } else {
            selectedKeys = Set(items.map(\.key))
        }
    }

    private func deleteSelectedItems(mode: Mode) {
        let keys = selectedKeys
        guard keys.isEmpty == false else { return }
        exitSelectionMode()
        Task {
            await model.removeLibraryItems(keys, mode: mode)
        }
    }
}

private struct LibraryDeletionConfirmation: Identifiable {
    let mode: LibraryView.Mode
    let count: Int

    var id: String { "\(mode.rawValue)-\(count)" }

    var itemName: String {
        mode == .history ? "历史记录" : "收藏"
    }

    var message: String {
        switch mode {
        case .history:
            "只会移除历史记录，不会删除漫画、收藏或下载文件。"
        case .favorites:
            "只会取消本地收藏，不会删除漫画、历史记录或下载文件。"
        }
    }
}

private struct LibraryGalleryRow: View, Equatable {
    @Environment(AppModel.self) private var model
    let gallery: GallerySummary
    let supplementalText: String?
    let localJob: DownloadJob?
    let localMediaResolved: Bool
    let downloadStatus: GalleryCardDownloadStatus?
    let displaySettings: GalleryCardDisplaySettings
    let isCompactWidth: Bool
    let isSelectionMode: Bool
    let isSelected: Bool
    let select: () -> Void
    let requestSelection: () -> Void

    nonisolated static func == (lhs: LibraryGalleryRow, rhs: LibraryGalleryRow) -> Bool {
        lhs.gallery == rhs.gallery
            && lhs.supplementalText == rhs.supplementalText
            && lhs.localJob == rhs.localJob
            && lhs.localMediaResolved == rhs.localMediaResolved
            && lhs.downloadStatus == rhs.downloadStatus
            && lhs.displaySettings == rhs.displaySettings
            && lhs.isCompactWidth == rhs.isCompactWidth
            && lhs.isSelectionMode == rhs.isSelectionMode
            && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        Group {
            if isSelectionMode {
                Button(action: select) {
                    if displaySettings.layoutMode != .list {
                        galleryCard
                            .overlay(alignment: .topLeading) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                                    .padding(8)
                                    .background(.black.opacity(0.45), in: Circle())
                                    .padding(8)
                            }
                    } else {
                        HStack(alignment: .top, spacing: 10) {
                            selectionIndicator
                            galleryCard
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    isSelected
                        ? String(localized: "取消选择《\(displayTitle)》")
                        : String(localized: "选择《\(displayTitle)》")
                )
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            } else {
                NavigationLink(value: AppRoute.gallery(gallery.key)) {
                    galleryCard
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .buttonStyle(.plain)
                .contextMenu {
                    Button("选择", systemImage: "checkmark.circle", action: requestSelection)
                }
            }
        }
        .id(gallery.key)
    }

    private var galleryCard: some View {
        GalleryCard(
            gallery: gallery,
            displaySettings: displaySettings,
            isCompactWidth: isCompactWidth,
            supplementalText: supplementalText,
            localJob: localJob,
            localMediaResolved: localMediaResolved,
            prefersGalleryCache: true,
            downloadStatus: downloadStatus
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectionIndicator: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(minWidth: 28, minHeight: 44, alignment: .top)
            .accessibilityLabel(isSelected ? String(localized: "已选择") : String(localized: "未选择"))
    }

    private var displayTitle: String {
        gallery.displayTitle(showJapaneseTitle: model.readingSettings.showJapaneseTitle)
    }
}
