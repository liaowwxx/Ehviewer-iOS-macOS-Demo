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
@MainActor
struct EhViewerApp: App {
#if os(iOS)
    @UIApplicationDelegateAdaptor(EhViewerAppDelegate.self) private var appDelegate
#endif
    @State private var modelContainer: ModelContainer?
    @State private var model: AppModel?
    @State private var startupError: String?

    init() {
        let container: ModelContainer?
        let appModel: AppModel?
        let errorMessage: String?
        do {
            let createdContainer = try ModelContainerFactory.make()
            container = createdContainer
            appModel = AppModel(container: createdContainer)
            errorMessage = nil
        } catch {
            container = nil
            appModel = nil
            errorMessage = error.localizedDescription
        }
        _modelContainer = State(initialValue: container)
        _model = State(initialValue: appModel)
        _startupError = State(initialValue: errorMessage)
    }

    var body: some Scene {
        WindowGroup {
            if let model, let modelContainer {
                RootView()
                    .environment(model)
                    .modelContainer(modelContainer)
                    .tint(AppTheme.accent)
                    .onOpenURL { url in model.handleIncomingURL(url) }
            } else {
                PersistenceRecoveryView(
                    errorMessage: startupError ?? String(localized: "未知的本地数据存储错误。"),
                    retry: retryStore
                )
            }
        }
        #if os(macOS)
        .defaultSize(width: 700, height: 700)
        #endif
        #if os(macOS)
        WindowGroup("阅读器", for: AppRoute.self) { route in
            if let model, let modelContainer,
               let route = route.wrappedValue,
               case let .reader(key, page) = route {
                ReaderView(key: key, initialPage: page)
                    .environment(model)
                    .modelContainer(modelContainer)
                    .tint(AppTheme.accent)
            } else {
                ContentUnavailableView("没有打开的阅读器", systemImage: "book")
            }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("刷新列表") {
                    model?.requestBrowseRefresh()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
            CommandMenu("EhViewer") {
                Button("回到浏览") { model?.selectedRoute = .browse }
                    .keyboardShortcut("1", modifiers: [.command])
            }
        }
        #endif
    }

    private func retryStore() {
        do {
            let container = try ModelContainerFactory.make()
            modelContainer = container
            model = AppModel(container: container)
            startupError = nil
        } catch {
            startupError = error.localizedDescription
        }
    }
}

private struct PersistenceRecoveryView: View {
    let errorMessage: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("无法打开本地数据", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            VStack(spacing: 12) {
                Text("应用没有删除或重建你的数据。请先重试；如果问题持续，请保留下面的诊断信息。")
                Text(errorMessage)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            }
        } actions: {
            Button("重试", systemImage: "arrow.clockwise", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
