import SwiftUI
import SwiftData
import EHDomain
import EHPersistence
import EHDownloads

#if os(iOS)
import UIKit

@MainActor
final class EhViewerAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundDownloadEvents.register(completionHandler)
    }
}
#endif

@main
struct EhViewerApp: App {
#if os(iOS)
    @UIApplicationDelegateAdaptor(EhViewerAppDelegate.self) private var appDelegate
#endif
    private let modelContainer: ModelContainer
    @State private var model: AppModel

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainerFactory.make()
        } catch {
            fatalError("Unable to create the local data store: \(error)")
        }
        modelContainer = container
        _model = State(initialValue: AppModel(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .modelContainer(modelContainer)
                .onOpenURL { url in model.handleIncomingURL(url) }
        }
        #if os(macOS)
        WindowGroup("阅读器", for: AppRoute.self) { route in
            if let route = route.wrappedValue,
               case let .reader(key, page) = route {
                ReaderView(key: key, initialPage: page)
                    .environment(model)
                    .modelContainer(modelContainer)
            } else {
                ContentUnavailableView("没有打开的阅读器", systemImage: "book")
                    .environment(model)
            }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("刷新列表") {
                    Task { await model.load() }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
            CommandMenu("EhViewer") {
                Button("回到浏览") { model.selectedRoute = .browse }
                    .keyboardShortcut("1", modifiers: [.command])
            }
        }
        #endif
    }
}
