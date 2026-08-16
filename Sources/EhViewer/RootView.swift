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
    @State private var presentedError: PresentedError?
    @State private var compactSelection: AppRoute = .browse
    @State private var compactBrowsePath: [AppRoute] = []
    @State private var compactDownloadsPath: [AppRoute] = []
    @State private var compactHistoryPath: [AppRoute] = []
    @State private var compactSettingsPath: [AppRoute] = []
    @State private var compactLibraryMode: LibraryView.Mode = .history
    @State private var splitSelection: AppRoute? = .browse
    @State private var splitDetailPath: [AppRoute] = []

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                CompactRootView(
                    selection: $compactSelection,
                    browsePath: $compactBrowsePath,
                    downloadsPath: $compactDownloadsPath,
                    historyPath: $compactHistoryPath,
                    settingsPath: $compactSettingsPath,
                    libraryMode: $compactLibraryMode
                )
            } else {
                SplitRootView(selection: $splitSelection, detailPath: $splitDetailPath)
            }
        }
        .accessibilityIdentifier("ehviewer-root")
        .onChange(of: model.errorMessage) { _, newMessage in
            presentedError = newMessage.map(PresentedError.init)
        }
        .alert(item: $presentedError) { error in
            Alert(
                title: Text("发生错误"),
                message: Text(error.message),
                dismissButton: .default(Text("好")) { model.errorMessage = nil }
            )
        }
    }
}

private struct PresentedError: Identifiable {
    let id = UUID()
    let message: String
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
    @Binding var historyPath: [AppRoute]
    @Binding var settingsPath: [AppRoute]
    @Binding var libraryMode: LibraryView.Mode

    var body: some View {
        TabView(selection: $selection) {
            RootNavigationStack(path: $browsePath) { path in
                HomeBrowseView(model: model, navigationPath: path)
            }
            .tabItem { Label("browse_title", systemImage: "list.bullet.rectangle") }
            .tag(AppRoute.browse)

            RootNavigationStack(path: $downloadsPath) { _ in
                DownloadsView()
            }
            .tabItem { Label("downloads_title", systemImage: "arrow.down.circle") }
            .tag(AppRoute.downloads)

            RootNavigationStack(path: $historyPath) { _ in
                LibraryView(mode: libraryMode)
            }
            .tabItem { Label("history_title", systemImage: "clock") }
            .tag(AppRoute.history)

            RootNavigationStack(path: $settingsPath) { _ in
                SettingsView()
            }
            .tabItem { Label("settings_title", systemImage: "gearshape").accessibilityIdentifier("settings-tab") }
            .tag(AppRoute.settings)
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
        case .history:
            libraryMode = .history
            selection = .history
        case .favorites:
            libraryMode = .favorites
            selection = .history
        case .settings:
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
                    NavigationLink(value: AppRoute.browse) { Label("home_title", systemImage: "house") }
                    NavigationLink(value: AppRoute.subscriptions) { Label("subscriptions_title", systemImage: "tag") }
                    NavigationLink(value: AppRoute.popular) { Label("popular_title", systemImage: "chart.line.uptrend.xyaxis") }
                    NavigationLink(value: AppRoute.toplist) { Label("toplist_title", systemImage: "list.number") }
                }
                Section("个人") {
                    NavigationLink(value: AppRoute.downloads) { Label("downloads_title", systemImage: "arrow.down.circle") }
                    NavigationLink(value: AppRoute.history) { Label("history_title", systemImage: "clock") }
                    NavigationLink(value: AppRoute.favorites) { Label("favorites_title", systemImage: "heart") }
                }
                Section {
                    NavigationLink(value: AppRoute.settings) { Label("settings_title", systemImage: "gearshape") }
                        .accessibilityIdentifier("settings-sidebar")
                }
            }
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
        case .search(let query):
            BrowseView(model: model, pageModel: model.searchPageModel(for: query))
        case .subscriptions:
            BrowseView(model: model, kind: .subscriptions)
        case .popular:
            BrowseView(model: model, kind: .popular)
        case .toplist:
            BrowseView(model: model, kind: .toplist)
        case .downloads:
            DownloadsView()
        case .history:
            LibraryView(mode: .history)
        case .favorites:
            LibraryView(mode: .favorites)
        case .settings:
            SettingsView()
        case .gallery(let key):
            GalleryDetailView(key: key)
        case .reader(let key, let page):
            ReaderView(key: key, initialPage: page)
        }
    }
}
