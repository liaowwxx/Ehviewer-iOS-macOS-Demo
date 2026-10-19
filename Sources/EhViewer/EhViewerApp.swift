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
#if os(macOS)
import EHTranslationMac
#endif

#if os(iOS)
import UIKit

@MainActor
final class EhViewerAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        DeviceSyncBackgroundTaskRegistry.shared.register()
        DownloadBackgroundTaskRegistry.shared.register()
        return true
    }

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
#if os(macOS)
    @NSApplicationDelegateAdaptor(TranslationApplicationDelegate.self) private var translationDelegate
#endif
#if os(iOS)
    @UIApplicationDelegateAdaptor(EhViewerAppDelegate.self) private var appDelegate
#endif
    @State private var profileSession: ProfileSession

    init() {
        #if DEBUG && os(macOS)
        if ProcessInfo.processInfo.arguments.contains("-UITestTranslationWorkspace"),
           let path = ProcessInfo.processInfo.environment["EH_TRANSLATION_TEST_PROFILES"] {
            _profileSession = State(initialValue: ProfileSession(profilesRoot: URL(fileURLWithPath: path)))
            return
        }
        #endif
        _profileSession = State(initialValue: ProfileSession())
    }

    var body: some Scene {
        WindowGroup {
            ProfileHostView(session: profileSession)
            #if os(macOS)
                .onChange(of: profileSession.runtime?.descriptor.id, initial: true) { _, id in
                    TranslationCoordinator.shared.activate(id)
                }
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 700, height: 700)
        #endif
        #if os(macOS)
        WindowGroup("漫画翻译", id: "translation", for: UUID.self) { profileID in
            if let runtime = profileSession.runtime, profileID.wrappedValue == runtime.descriptor.id {
                NativeTranslationHost(model: runtime.model)
            } else {
                ContentUnavailableView("请切回对应用户以查看翻译任务", systemImage: "person.crop.circle.badge.exclamationmark")
            }
        }
        .defaultSize(width: 1120, height: 740)
        .commands { NativeTranslationCommands(session: profileSession) }
        WindowGroup("阅读器", for: ProfileReaderRoute.self) { route in
            if let runtime = profileSession.runtime,
               let route = route.wrappedValue,
               route.profileID == runtime.descriptor.id {
                ReaderView(key: route.key, initialPage: route.page)
                    .environment(runtime.model)
                    .environment(profileSession)
                    .modelContainer(runtime.container)
                    .tint(AppTheme.accent)
            } else {
                ContentUnavailableView("没有打开的阅读器", systemImage: "book")
            }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("刷新列表") {
                    profileSession.runtime?.model.requestBrowseRefresh()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
            CommandMenu("EhViewer") {
                Button("回到浏览") { profileSession.runtime?.model.selectedRoute = .browse }
                    .keyboardShortcut("1", modifiers: [.command])
            }
        }
        #endif
    }

}

#if os(macOS)
private struct NativeTranslationCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let session: ProfileSession
    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button("漫画翻译") {
                if let runtime = session.runtime { openWindow(id: "translation", value: runtime.descriptor.id) }
            }
            .disabled(session.runtime == nil)
        }
    }
}

private struct NativeTranslationHost: View {
    let model: AppModel
    @State private var jobs: [DownloadJob] = []
    var body: some View {
        TranslationWindow(workspace: model.nativeTranslation, available: jobs, downloads: model.downloadFiles)
            .task {
                jobs = await model.downloads.snapshot()
                await model.nativeTranslation.importReadyResults()
            }
            .onChange(of: model.localLibraryRevision) { _, _ in
                Task { jobs = await model.downloads.snapshot() }
            }
    }
}
#endif

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
