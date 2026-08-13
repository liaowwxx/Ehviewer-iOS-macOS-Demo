import SwiftUI
import EHDomain

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var presentedError: PresentedError?

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                CompactRootView()
            } else {
                SplitRootView()
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
                primaryButton: .default(Text("重试")) {
                    model.errorMessage = nil
                    Task { await model.retryLastListRequest() }
                },
                secondaryButton: .cancel(Text("好")) { model.errorMessage = nil }
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

    init(path: Binding<[AppRoute]>, @ViewBuilder content: () -> Content) {
        _path = path
        self.content = content()
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
    @State private var selection: AppRoute = .browse
    @State private var browsePath: [AppRoute] = []
    @State private var downloadsPath: [AppRoute] = []
    @State private var historyPath: [AppRoute] = []
    @State private var settingsPath: [AppRoute] = []

    var body: some View {
        TabView(selection: $selection) {
            RootNavigationStack(path: $browsePath) {
                BrowseView()
            }
            .tabItem { Label("browse_title", systemImage: "list.bullet.rectangle") }
            .tag(AppRoute.browse)

            RootNavigationStack(path: $downloadsPath) {
                DownloadsView()
            }
            .tabItem { Label("downloads_title", systemImage: "arrow.down.circle") }
            .tag(AppRoute.downloads)

            RootNavigationStack(path: $historyPath) {
                LibraryView()
            }
            .tabItem { Label("history_title", systemImage: "clock") }
            .tag(AppRoute.history)

            RootNavigationStack(path: $settingsPath) {
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
        case .history, .favorites:
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
    @State private var selection: AppRoute? = .browse

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
            NavigationStack {
                DestinationView(route: selection ?? .browse)
                    .navigationDestination(for: AppRoute.self) { route in
                        DestinationView(route: route)
                    }
            }
        }
        .onChange(of: selection) { _, route in model.selectedRoute = route }
        .onChange(of: model.selectedRoute) { _, route in
            if let route { selection = route }
        }
    }
}

struct DestinationView: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .browse:
            BrowseView(kind: .home)
        case .subscriptions:
            BrowseView(kind: .subscriptions)
        case .popular:
            BrowseView(kind: .popular)
        case .toplist:
            BrowseView(kind: .toplist)
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
