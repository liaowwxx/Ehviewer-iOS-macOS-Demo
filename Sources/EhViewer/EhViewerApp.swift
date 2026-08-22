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
    @State private var isResettingStore = false
    @State private var resetError: String?

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
                    retry: retryStore,
                    reset: resetStore,
                    isResetting: isResettingStore,
                    resetError: resetError
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
            resetError = nil
        } catch {
            startupError = error.localizedDescription
        }
    }

    private func resetStore() {
        guard isResettingStore == false else { return }
        isResettingStore = true
        resetError = nil
        Task {
            do {
                try await AppDataResetter.removeAll()
                retryStore()
            } catch {
                resetError = error.localizedDescription
            }
            isResettingStore = false
        }
    }
}

private struct PersistenceRecoveryView: View {
    let errorMessage: String
    let retry: () -> Void
    let reset: () -> Void
    let isResetting: Bool
    let resetError: String?
    @State private var showingResetConfirmation = false

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
            VStack(spacing: 12) {
                Button("重试", systemImage: "arrow.clockwise", action: retry)
                    .buttonStyle(.borderedProminent)
                    .disabled(isResetting)
                Button("清除全部数据", systemImage: "trash", role: .destructive) {
                    showingResetConfirmation = true
                }
                .disabled(isResetting)
                if isResetting {
                    ProgressView("正在清除本地数据…")
                }
                if let resetError {
                    Text(resetError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .padding()
        .confirmationDialog(
            "清除全部本地数据？",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除缓存和已下载画廊", role: .destructive, action: reset)
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除 SwiftData 本地数据库、画廊缓存、缩略图缓存和已下载画廊文件。操作不可撤销；登录 Cookie 和偏好设置会保留。")
        }
    }
}
