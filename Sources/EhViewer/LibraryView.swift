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
    @State private var selectedMode: Mode
    @State private var isSelectionMode = false
    @State private var selectedKeys: Set<GalleryKey> = []
    @State private var deletionConfirmation: LibraryDeletionConfirmation?
    @State private var readingPages: [GalleryKey: Int] = [:]
    @State private var downloadedJobs: [GalleryKey: DownloadJob] = [:]
    @State private var downloadedJobsReady = false

    init(mode: Mode = .history) {
        _selectedMode = State(initialValue: mode)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                HStack {
                    Text(selectedMode == .history ? "最近阅读" : "本地收藏")
                        .font(.headline)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)

                ForEach(items) { gallery in
                    libraryRow(for: gallery)
                        .equatable()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .navigationTitle(selectedMode == .history ? "history_title" : "favorites_title")
        .toolbar {
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
                    Button(role: .destructive) {
                        deletionConfirmation = LibraryDeletionConfirmation(
                            mode: selectedMode,
                            count: selectedKeys.count
                        )
                    } label: {
                        Label("删除(\(selectedKeys.count))", systemImage: "trash")
                    }
                    .disabled(selectedKeys.isEmpty)
                }
            } else {
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

                    ToolbarItem(placement: .automatic) {
                        libraryModePicker
                    }
                }
#endif
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(
                    "暂无记录",
                    systemImage: selectedMode == .history ? "clock" : "heart"
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
        .onChange(of: selectedMode) { _, _ in
            exitSelectionMode()
        }
        .task(id: selectedMode) {
            downloadedJobs = [:]
            downloadedJobsReady = false
            await model.loadLibrary(mode: selectedMode)
            guard Task.isCancelled == false else { return }

            let libraryKeys = Set(items.map(\.key))
            let jobs = await model.downloads.snapshot()
            downloadedJobs = Dictionary(
                uniqueKeysWithValues: jobs
                    .filter { libraryKeys.contains($0.key) }
                    .map { ($0.key, $0) }
            )
            downloadedJobsReady = true

            guard selectedMode == .history else {
                readingPages = [:]
                return
            }
            var loadedPages: [GalleryKey: Int] = [:]
            for gallery in model.historyGalleries {
                if let page = await model.readingPage(for: gallery.key) {
                    loadedPages[gallery.key] = page
                }
            }
            readingPages = loadedPages
        }
    }

    private var items: [GallerySummary] {
        selectedMode == .history ? model.historyGalleries : model.favoriteGalleries
    }

    private var selectAllTitle: String {
        selectedKeys.count == items.count && items.isEmpty == false ? "取消全选" : "全选"
    }

    private var libraryModePicker: some View {
        Picker("资料库", selection: $selectedMode) {
            Text("history_title").tag(Mode.history)
            Text("favorites_title").tag(Mode.favorites)
        }
        .pickerStyle(.segmented)
        .frame(minWidth: 220, maxWidth: .infinity)
    }

    private var selectionToolbarButton: some View {
        Button("选择", systemImage: "checkmark.circle") {
            enterSelectionMode()
        }
        .accessibilityHint("选择要操作的项目")
        .labelStyle(.titleAndIcon)
        .disabled(items.isEmpty)
    }

    private func libraryRow(for gallery: GallerySummary) -> LibraryGalleryRow {
        LibraryGalleryRow(
            gallery: gallery,
            supplementalText: selectedMode == .history ? progressText(for: gallery) : nil,
            localJob: downloadedJobs[gallery.key],
            localMediaResolved: downloadedJobsReady,
            isSelectionMode: isSelectionMode,
            isSelected: selectedKeys.contains(gallery.key),
            select: { toggleSelection(gallery.key) },
            requestSelection: { enterSelectionMode(selecting: gallery.key) }
        )
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
    let isSelectionMode: Bool
    let isSelected: Bool
    let select: () -> Void
    let requestSelection: () -> Void

    nonisolated static func == (lhs: LibraryGalleryRow, rhs: LibraryGalleryRow) -> Bool {
        lhs.gallery == rhs.gallery
            && lhs.supplementalText == rhs.supplementalText
            && lhs.localJob == rhs.localJob
            && lhs.localMediaResolved == rhs.localMediaResolved
            && lhs.isSelectionMode == rhs.isSelectionMode
            && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        Group {
            if isSelectionMode {
                Button(action: select) {
                    HStack(alignment: .top, spacing: 10) {
                        selectionIndicator
                        galleryCard
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
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
            supplementalText: supplementalText,
            showsTags: true,
            localJob: localJob,
            localMediaResolved: localMediaResolved,
            prefersGalleryCache: true
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
