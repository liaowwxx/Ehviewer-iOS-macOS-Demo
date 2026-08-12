import SwiftUI
import EHDomain

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var presentedError: PresentedError?

    var body: some View {
        Group {
            if model.isLocked {
                AppLockedView()
            } else if horizontalSizeClass == .compact {
                CompactRootView()
            } else {
                SplitRootView()
            }
        }
        .accessibilityIdentifier("ehviewer-root")
        .onChange(of: model.errorMessage) { _, newMessage in
            presentedError = newMessage.map(PresentedError.init)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                model.lockForBackground()
            } else if phase == .active {
                Task { await model.unlockIfNeeded() }
            }
        }
        .task { await model.unlockIfNeeded() }
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

private struct AppLockedView: View {
    @Environment(AppModel.self) private var model
    @State private var isAuthenticating = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("EhViewer 已锁定")
                .font(.title2.weight(.semibold))
            Button("解锁", systemImage: "faceid") {
                guard isAuthenticating == false else { return }
                isAuthenticating = true
                Task {
                    await model.unlockIfNeeded()
                    isAuthenticating = false
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAuthenticating)
            .accessibilityHint("使用 Face ID、Touch ID 或设备密码解锁")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await model.unlockIfNeeded() }
    }
}

private struct PresentedError: Identifiable {
    let id = UUID()
    let message: String
}

private struct CompactRootView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: AppRoute = .browse

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                BrowseView()
                    .navigationDestination(for: AppRoute.self) { route in
                        DestinationView(route: route)
                    }
            }
            .tabItem { Label("browse_title", systemImage: "square.grid.2x2") }
            .tag(AppRoute.browse)

            NavigationStack {
                DownloadsView()
                    .navigationDestination(for: AppRoute.self) { route in
                        DestinationView(route: route)
                    }
            }
            .tabItem { Label("downloads_title", systemImage: "arrow.down.circle") }
            .tag(AppRoute.downloads)

            NavigationStack {
                LibraryView()
                    .navigationDestination(for: AppRoute.self) { route in
                        DestinationView(route: route)
                    }
            }
            .tabItem { Label("history_title", systemImage: "clock") }
            .tag(AppRoute.history)

            NavigationStack {
                SettingsView()
                    .navigationDestination(for: AppRoute.self) { route in
                        DestinationView(route: route)
                    }
            }
            .tabItem { Label("settings_title", systemImage: "gearshape").accessibilityIdentifier("settings-tab") }
            .tag(AppRoute.settings)
        }
        .tint(.accentColor)
        .onChange(of: selection) { _, route in
            model.selectedRoute = route
        }
        .onChange(of: model.selectedRoute) { _, route in
            guard let route else { return }
            switch route {
            case .downloads:
                selection = .downloads
            case .history, .favorites:
                selection = .history
            case .settings:
                selection = .settings
            default:
                selection = .browse
            }
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
