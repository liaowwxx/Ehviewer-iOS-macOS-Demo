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

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var presentedRootAlert: RootAlert?
    @State private var compactSelection: AppRoute = .local
    @State private var compactBrowsePath: [AppRoute] = []
    @State private var compactDownloadsPath: [AppRoute] = []
    @State private var compactLocalPath: [AppRoute] = []
    @State private var compactHistoryPath: [AppRoute] = []
    @State private var compactSettingsPath: [AppRoute] = []
    @State private var compactLibraryMode: LibraryView.Mode = .history
    @State private var splitSelection: AppRoute? = .local
    @State private var splitDetailPath: [AppRoute] = []

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                CompactRootView(
                    selection: $compactSelection,
                    browsePath: $compactBrowsePath,
                    downloadsPath: $compactDownloadsPath,
                    localPath: $compactLocalPath,
                    historyPath: $compactHistoryPath,
                    settingsPath: $compactSettingsPath,
                    libraryMode: $compactLibraryMode
                )
            } else {
                SplitRootView(selection: $splitSelection, detailPath: $splitDetailPath)
            }
        }
        .accessibilityIdentifier("ehviewer-root")
        .onAppear { refreshRootAlert() }
        .onChange(of: model.errorMessage) { _, _ in refreshRootAlert() }
        .onChange(of: model.pendingIncomingArchive) { _, _ in refreshRootAlert() }
        .onChange(of: model.pendingIncomingGallerySync) { _, _ in refreshRootAlert() }
        .onChange(of: model.importResultMessage) { _, _ in refreshRootAlert() }
        .alert(item: $presentedRootAlert) { alert in
            switch alert {
            case .error(let message):
                Alert(
                    title: Text("发生错误"),
                    message: Text(message),
                    dismissButton: .default(Text("好")) { model.errorMessage = nil }
                )
            case .incomingArchive(let pending):
                Alert(
                    title: Text("收到 EhViewer 下载包"),
                    message: Text("将导入下载包，并自动跳过已有页面。"),
                    primaryButton: .default(Text("导入")) {
                        model.runFileOperation {
                            await model.confirmIncomingArchive(pending)
                        }
                    },
                    secondaryButton: .cancel(Text("取消")) {
                        model.discardIncomingArchive()
                    }
                )
            case .incomingGallerySync(let pending):
                Alert(
                    title: Text("收到 EhViewer 画廊同步包"),
                    message: Text("将恢复画廊的普通标题、日文标题和标签；保留本机已有的阅读进度、收藏及下载文件。"),
                    primaryButton: .default(Text("导入")) {
                        model.runFileOperation {
                            await model.confirmIncomingGallerySync(pending)
                        }
                    },
                    secondaryButton: .cancel(Text("取消")) {
                        model.discardIncomingGallerySync()
                    }
                )
            case .importResult(let message):
                Alert(
                    title: Text("导入结果"),
                    message: Text(message),
                    dismissButton: .default(Text("好")) { model.importResultMessage = nil }
                )
            }
        }
        .overlay {
            if let progress = model.migrationProgress {
                MigrationProgressOverlay(
                    progress: progress,
                    canCancel: model.canCancelCurrentFileOperation,
                    cancel: model.cancelCurrentFileOperation
                )
            }
            if model.isRestoringDownloads {
                DownloadRestoreProgressOverlay(
                    status: model.downloadRestoreStatus,
                    cancel: model.cancelCurrentFileOperation
                )
            }
        }
    }

    private func refreshRootAlert() {
        if let message = model.importResultMessage {
            presentedRootAlert = .importResult(message)
        } else if let message = model.errorMessage {
            presentedRootAlert = .error(message)
        } else if let pending = model.pendingIncomingGallerySync {
            presentedRootAlert = .incomingGallerySync(pending)
        } else if let pending = model.pendingIncomingArchive {
            presentedRootAlert = .incomingArchive(pending)
        } else {
            presentedRootAlert = nil
        }
    }

}

private enum RootAlert: Identifiable {
    case error(String)
    case incomingArchive(PendingIncomingArchive)
    case incomingGallerySync(PendingIncomingGallerySync)
    case importResult(String)

    var id: String {
        switch self {
        case .error(let message): "error-\(message)"
        case .incomingArchive(let pending): "incoming-\(pending.id)"
        case .incomingGallerySync(let pending): "incoming-gallery-sync-\(pending.id)"
        case .importResult(let message): "import-result-\(message)"
        }
    }
}

private struct MigrationProgressOverlay: View {
    let progress: MigrationProgress
    let canCancel: Bool
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if let fraction = progress.fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
            } else {
                ProgressView()
            }
            Text(progress.status)
                .font(.callout)
                .multilineTextAlignment(.center)
            if canCancel {
                Button("取消", role: .cancel, action: cancel)
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(progress.status)
    }
}

private struct DownloadRestoreProgressOverlay: View {
    let status: String
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ProgressView(status.isEmpty ? String(localized: "正在恢复下载项…") : status)
            Button("取消", role: .cancel, action: cancel)
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(status)
    }
}

private struct RootNavigationStack<Content: View>: View {
    @Binding var path: [AppRoute]
    let content: Content

    init(path: Binding<[AppRoute]>, @ViewBuilder content: (Binding<[AppRoute]>) -> Content) {
        _path = path
        self.content = content(path)
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationDestination(for: AppRoute.self) { route in
                    DestinationView(route: route)
                }
        }
    }
}

private struct CompactRootView: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: AppRoute
    @Binding var browsePath: [AppRoute]
    @Binding var downloadsPath: [AppRoute]
    @Binding var localPath: [AppRoute]
    @Binding var historyPath: [AppRoute]
    @Binding var settingsPath: [AppRoute]
    @Binding var libraryMode: LibraryView.Mode

    var body: some View {
        TabView(selection: $selection) {
            Tab(value: AppRoute.browse) {
                RootNavigationStack(path: $browsePath) { path in
                    HomeBrowseView(model: model, navigationPath: path)
                }
            } label: {
                Label("browse_title", systemImage: "list.bullet.rectangle")
            }

            Tab(value: AppRoute.downloads) {
                RootNavigationStack(path: $downloadsPath) { _ in
                    DownloadsView()
                }
            } label: {
                Label("downloads_title", systemImage: "arrow.down.circle")
            }

            Tab(value: AppRoute.local) {
                RootNavigationStack(path: $localPath) { _ in
                    DownloadsView(page: .local)
                }
            } label: {
                Label("本地", systemImage: "books.vertical")
            }

            Tab(value: AppRoute.history) {
                RootNavigationStack(path: $historyPath) { _ in
                    LibraryView(mode: libraryMode)
                }
            } label: {
                Label("history_title", systemImage: "clock")
            }

            Tab(value: AppRoute.settings) {
                RootNavigationStack(path: $settingsPath) { _ in
                    SettingsView()
                }
            } label: {
                Label("settings_title", systemImage: "gearshape")
                    .accessibilityIdentifier("settings-tab")
            }
        }
        .onChange(of: selection) { _, route in
            model.selectedRoute = route
        }
        .onChange(of: model.selectedRoute) { _, route in
            syncSelectedRoute(route)
        }
        .onAppear { syncSelectedRoute(model.selectedRoute) }
    }

    private func syncSelectedRoute(_ route: AppRoute?) {
        guard let route else { return }
        switch route {
        case .downloads:
            selection = .downloads
        case .local:
            selection = .local
        case .history:
            libraryMode = .history
            selection = .history
        case .favorites:
            libraryMode = .favorites
            selection = .history
        case .settings,
             .settingsSite,
             .settingsLogin,
             .settingsBrowsing,
             .settingsFilters,
             .settingsStorageAndProgress,
             .settingsDataAndBackup,
             .settingsDeviceSync:
            selection = .settings
        case .gallery, .reader:
            browsePath = [route]
            selection = .browse
        default:
            selection = .browse
        }
    }
}

private struct SplitRootView: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: AppRoute?
    @Binding var detailPath: [AppRoute]

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("浏览") {
                    NavigationLink(value: AppRoute.browse) { SidebarLabel("home_title", systemImage: "house") }
                    NavigationLink(value: AppRoute.subscriptions) { SidebarLabel("subscriptions_title", systemImage: "tag") }
                    NavigationLink(value: AppRoute.popular) { SidebarLabel("popular_title", systemImage: "chart.line.uptrend.xyaxis") }
                    NavigationLink(value: AppRoute.toplist) { SidebarLabel("toplist_title", systemImage: "list.number") }
                }
                Section("个人") {
                    NavigationLink(value: AppRoute.downloads) { SidebarLabel("downloads_title", systemImage: "arrow.down.circle") }
                    NavigationLink(value: AppRoute.local) { SidebarLabel("本地", systemImage: "books.vertical") }
                    NavigationLink(value: AppRoute.history) { SidebarLabel("history_title", systemImage: "clock") }
                    NavigationLink(value: AppRoute.favorites) { SidebarLabel("favorites_title", systemImage: "heart") }
                }
                Section {
                    NavigationLink(value: AppRoute.settings) { SidebarLabel("settings_title", systemImage: "gearshape") }
                        .accessibilityIdentifier("settings-sidebar")
                }
            }
            .tint(AppTheme.accent)
            .navigationTitle("EhViewer")
        } detail: {
            RootNavigationStack(path: $detailPath) { path in
                DestinationView(route: selection ?? .browse, navigationPath: path)
            }
        }
        .onChange(of: selection) { _, route in
            model.selectedRoute = route
            detailPath.removeAll()
        }
        .onChange(of: model.selectedRoute) { _, route in
            if let route { selection = route }
        }
    }
}

private struct SidebarLabel: View {
    let title: LocalizedStringKey
    let systemImage: String

    init(_ title: LocalizedStringKey, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.accent)
        }
    }
}

struct DestinationView: View {
    @Environment(AppModel.self) private var model
    let route: AppRoute
    let navigationPath: Binding<[AppRoute]>?

    init(route: AppRoute, navigationPath: Binding<[AppRoute]>? = nil) {
        self.route = route
        self.navigationPath = navigationPath
    }

    var body: some View {
        switch route {
        case .browse:
            HomeBrowseView(model: model, navigationPath: navigationPath ?? .constant([]))
        case .search(let query, let advancedSearch):
            BrowseView(
                model: model,
                pageModel: model.searchPageModel(for: query, advancedSearch: advancedSearch)
            )
        case .subscriptions:
            BrowseView(model: model, kind: .subscriptions)
        case .popular:
            BrowseView(model: model, kind: .popular)
        case .toplist:
            BrowseView(model: model, kind: .toplist)
        case .downloads:
            DownloadsView()
        case .local:
            DownloadsView(page: .local)
        case .history:
            LibraryView(mode: .history)
        case .favorites:
            LibraryView(mode: .favorites)
        case .settings:
            SettingsView()
        case .settingsSite:
            SettingsView(page: .site)
        case .settingsLogin:
            SettingsView(page: .login)
        case .settingsBrowsing:
            SettingsView(page: .browsing)
        case .settingsFilters:
            SettingsView(page: .filters)
        case .settingsStorageAndProgress:
            SettingsView(page: .storageAndProgress)
        case .settingsDataAndBackup:
            SettingsView(page: .dataAndBackup)
        case .settingsDeviceSync:
            DeviceSyncView()
        case .gallery(let key):
            GalleryDetailView(key: key)
        case .comments(let key):
            GalleryCommentsView(key: key)
        case .reader(let key, let page):
            ReaderView(key: key, initialPage: page)
        }
    }
}
