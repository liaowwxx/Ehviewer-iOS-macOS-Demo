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
import EHDeviceSync
import UniformTypeIdentifiers

private enum FileImportKind {
    case gallerySync
    case downloadArchive

    var allowedContentTypes: [UTType] {
        switch self {
        case .gallerySync:
            BackupFileFormat.gallerySyncImportTypes
        case .downloadArchive:
            BackupFileFormat.downloadImportTypes
        }
    }
}

enum SettingsPage: Equatable {
    case overview
    case siteAndLogin
    case browsingAndFiltering
    case reading
    case storageManagement
    case dataBackupAndSync
    case site
    case login
    case browsing
    case filters
    case storageAndProgress
    case dataAndBackup
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(ProfileSession.self) private var profileSession
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let page: SettingsPage
    @State private var showingCookieSheet = false
    @State private var showingWebLogin = false
    @State private var showingPasswordLogin = false
    @State private var showingGallerySyncExporter = false
    @State private var gallerySyncExportDocument: GallerySyncExportDocument?
    @State private var gallerySyncExportFilename = "EhViewer-Galleries.ehgallery"
    @State private var showingFileImporter = false
    @State private var fileImporterKind: FileImportKind = .gallerySync
#if os(iOS)
    @State private var pendingShareFile: PendingSharedFile?
#else
    @State private var pendingArchiveSaveFile: PendingSharedFile?
#endif
    @State private var showingDownloadRestoreResult = false
    @State private var downloadRestoreMessage = ""
    @State private var showingGalleryCacheClearConfirmation = false
    @State private var showingAllLocalMangaDeletionConfirmation = false
    @State private var showingDownloadedMetadataRefreshDialog = false
    @State private var profileNameEditor: ProfileNameEditorRequest?
    @State private var profilePendingDeletion: ProfileDescriptor?

    init(page: SettingsPage = .overview) {
        self.page = page
    }

    private var settingsForm: some View {
        @Bindable var model = model
        return Form {
            ProfileManagementSection(
                nameEditor: $profileNameEditor,
                profilePendingDeletion: $profilePendingDeletion
            )

            Section("设置") {
                NavigationLink(value: AppRoute.settingsSiteAndLogin) {
                    SettingsNavigationLabel("站点&登录", systemImage: "globe")
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("session-status")
                .accessibilityLabel("站点与登录")
                .accessibilityValue(model.isGuestMode ? String(localized: "游客模式") : String(localized: "已登录"))

                NavigationLink(value: AppRoute.settingsBrowsingAndFiltering) {
                    SettingsNavigationLabel("浏览&过滤", systemImage: "book.pages")
                }
                .accessibilityIdentifier("settings-browsing-link")

                NavigationLink(value: AppRoute.settingsReading) {
                    SettingsNavigationLabel("阅读设置", systemImage: "book")
                }
                .accessibilityIdentifier("settings-reading-link")

                NavigationLink(value: AppRoute.settingsStorageManagement) {
                    SettingsNavigationLabel("存储管理", systemImage: "externaldrive")
                }
                .accessibilityIdentifier("settings-storage-and-progress-link")

                NavigationLink(value: AppRoute.settingsDataBackupAndSync) {
                    SettingsNavigationLabel("数据备份&同步", systemImage: "externaldrive.badge.icloud")
                }
                .accessibilityIdentifier("settings-data-and-backup-link")
            }

            Section {
                Picker("启动页面", selection: $model.startupPage) {
                    ForEach(StartupPage.allCases, id: \.self) { page in
                        Text(page.title).tag(page)
                    }
                }
                .accessibilityIdentifier("startup-page-picker")
            } footer: {
                Text("下次启动或进入此空间时生效")
            }

            Section("关于") {
                NavigationLink(value: AppRoute.documentation) {
                    Label("使用说明", systemImage: "book.closed")
                        .foregroundStyle(AppTheme.accent)
                }
                .accessibilityIdentifier("usage-documentation-link")
                LabeledContent("版本", value: appVersion)
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings-screen")
        .navigationTitle("settings_title")
    }

    private var siteAndLoginForm: some View {
        @Bindable var model = model
        return Form {
            Section("站点") {
                Picker("画廊站点", selection: $model.site) {
                    ForEach(SiteMode.allCases, id: \.self) { site in
                        Text(site.displayName)
                            .tag(site)
                            .disabled(model.isGuestMode && site == .exHentai)
                    }
                }
                .onChange(of: model.site) { _, _ in model.persistSettings() }
            }
            Section("会话") {
                LabeledContent {
                    Text(model.isGuestMode ? String(localized: "公开内容") : String(localized: "账户会话"))
                        .foregroundStyle(.secondary)
                } label: {
                    Label(
                        model.isGuestMode ? String(localized: "游客模式") : String(localized: "已登录"),
                        systemImage: model.isGuestMode ? "person" : "person.crop.circle.badge.checkmark"
                    )
                }
            }
            Section("登录") {
                Button("用户名&密码登录") { showingPasswordLogin = true }
                    .foregroundStyle(.primary)
                Button("网页登录") { showingWebLogin = true }
                    .foregroundStyle(.primary)
                Button("Cookie登录") { showingCookieSheet = true }
                    .foregroundStyle(.primary)
                Button("清除Cookie") {
                    Task { await model.clearSession() }
                }
                .foregroundStyle(.primary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("站点&登录")
    }

    private var browsingAndFilteringForm: some View {
        @Bindable var model = model
        return Form {
            Section("浏览") {
                Toggle("显示日文标题", isOn: $model.readingSettings.showJapaneseTitle)
                    .onChange(of: model.readingSettings.showJapaneseTitle) { _, _ in
                        model.persistReadingSettings()
                    }
                    .accessibilityIdentifier("show-japanese-title-toggle")
                Toggle("显示标签翻译", isOn: $model.readingSettings.showTagTranslations)
                    .onChange(of: model.readingSettings.showTagTranslations) { _, _ in
                        model.persistReadingSettings()
                    }
                    .accessibilityIdentifier("show-tag-translations-toggle")
            }
            GalleryCardSettingsSection(isCompactWidth: horizontalSizeClass == .compact)
            TagDatabaseSettingsSection()
            FilterRulesSection()
        }
        .formStyle(.grouped)
        .navigationTitle("浏览&过滤")
    }

    private var siteForm: some View {
        @Bindable var model = model
        return Form {
            Section("站点") {
                Picker("画廊站点", selection: $model.site) {
                    ForEach(SiteMode.allCases, id: \.self) { site in
                        Text(site.displayName)
                            .tag(site)
                            .disabled(model.isGuestMode && site == .exHentai)
                    }
                }
                .onChange(of: model.site) { _, _ in model.persistSettings() }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("站点")
    }

    private var browsingForm: some View {
        @Bindable var model = model
        return Form {
            Section("浏览") {
                Toggle("显示日文标题", isOn: $model.readingSettings.showJapaneseTitle)
                    .onChange(of: model.readingSettings.showJapaneseTitle) { _, _ in
                        model.persistReadingSettings()
                    }
                    .accessibilityIdentifier("show-japanese-title-toggle")
                Toggle("显示标签翻译", isOn: $model.readingSettings.showTagTranslations)
                    .onChange(of: model.readingSettings.showTagTranslations) { _, _ in
                        model.persistReadingSettings()
                    }
                    .accessibilityIdentifier("show-tag-translations-toggle")
            }
            GalleryCardSettingsSection(isCompactWidth: horizontalSizeClass == .compact)
            TagDatabaseSettingsSection()
        }
        .formStyle(.grouped)
        .navigationTitle("浏览")
    }

    private var storageAndProgressForm: some View {
        Form {
            Section("本地漫画") {
                if model.hasLoadedLocalDownloadUsage == false || model.isRefreshingLocalDownloadUsage {
                    ProgressView("正在计算本地漫画占用…")
                } else {
                    LabeledContent("本数", value: "\(model.localDownloadGalleryCount) 本")
                    LabeledContent("空间占用", value: localDownloadSize)
                }
                if let progress = model.localMangaDeletionProgress {
                    VStack(alignment: .leading) {
                        ProgressView(value: progress.fraction) {
                            Text("正在删除本地漫画")
                        } currentValueLabel: {
                            Text("已处理 \(progress.completed)/\(progress.total) 本")
                        }
                        if progress.failed > 0 {
                            Text("已有 \(progress.failed) 本删除失败")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("delete-all-local-manga-progress")
                }
                Button("删除所有本地漫画", role: .destructive) {
                    showingAllLocalMangaDeletionConfirmation = true
                }
                .foregroundStyle(.red)
                .disabled(model.localDownloadGalleryCount == 0 || model.isDeletingAllLocalManga || model.isLoadingDownloads || model.localDownloadLoadError != nil)
                .accessibilityIdentifier("delete-all-local-manga-action")
                .confirmationDialog(
                    "删除所有本地漫画？",
                    isPresented: $showingAllLocalMangaDeletionConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("删除全部漫画", role: .destructive) {
                        Task {
                            await model.deleteAllLocalManga()
                        }
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("将删除所有本地漫画文件，并从下载列表中移除对应任务。此操作无法撤销。")
                }
            }

            Section("缓存") {
                LabeledContent("缓存占用", value: galleryCacheSize)
                Button("清除缓存", role: .destructive) {
                    showingGalleryCacheClearConfirmation = true
                }
                .foregroundStyle(.red)
                .accessibilityIdentifier("clear-gallery-cache-action")
                .confirmationDialog(
                    "清除缓存？",
                    isPresented: $showingGalleryCacheClearConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("清除缓存", role: .destructive) {
                        Task { await model.clearGalleryCache() }
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("不会删除下载文件或下载任务，但会清除收藏和历史记录。")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("存储管理")
    }

    private var loginForm: some View {
        Form {
            Section("会话") {
                LabeledContent {
                    Text(model.isGuestMode ? String(localized: "公开内容") : String(localized: "账户会话"))
                        .foregroundStyle(.secondary)
                } label: {
                    Label(
                        model.isGuestMode ? String(localized: "游客模式") : String(localized: "已登录"),
                        systemImage: model.isGuestMode ? "person" : "person.crop.circle.badge.checkmark"
                    )
                }
            }
            Section("登录") {
                Button("用户名&密码登录") { showingPasswordLogin = true }
                    .foregroundStyle(.primary)
                Button("网页登录") { showingWebLogin = true }
                    .foregroundStyle(.primary)
                Button("Cookie登录") { showingCookieSheet = true }
                    .foregroundStyle(.primary)
                Button("清除Cookie") {
                    Task { await model.clearSession() }
                }
                .foregroundStyle(.primary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("登录")
    }

    private var filterRulesForm: some View {
        Form {
            FilterRulesSection()
        }
        .formStyle(.grouped)
        .navigationTitle("过滤")
    }

    private var dataAndBackupForm: some View {
        Form {
            Section("数据与备份") {
                SettingsActionRow(
                    title: "更新已下载画廊信息",
                    subtitle: "更新本地已下载漫画列表"
                ) {
                    Button("更新…") {
                        showingDownloadedMetadataRefreshDialog = true
                    }
                    .disabled(model.isMigrating || model.isRestoringDownloads || model.isLoadingDownloads || model.localDownloadLoadError != nil)
                    .accessibilityIdentifier("refresh-downloaded-gallery-metadata-action")
                    .confirmationDialog(
                        "更新已下载画廊信息",
                        isPresented: $showingDownloadedMetadataRefreshDialog,
                        titleVisibility: .visible
                    ) {
                        Button("更新全部") {
                            model.runFileOperation {
                                await model.refreshDownloadedGalleryMetadata(mode: .all)
                            }
                        }
                        Button("仅更新缺失信息") {
                            model.runFileOperation {
                                await model.refreshDownloadedGalleryMetadata(mode: .missingOnly)
                            }
                        }
                        Button("取消", role: .cancel) {}
                    } message: {
                        Text("缺失信息包括标题、作者、分类、页数、上传日期、缩略图和评分。")
                    }
                }
            }
            Section("导入与导出") {
                SettingsActionRow(
                    title: "导入漫画列表",
                    subtitle: "从 .ehgallery 文件导入"
                ) {
                    Button("导入…") {
                        startFileImport(.gallerySync)
                    }
                    .disabled(model.isMigrating || model.isRestoringDownloads || model.isLoadingDownloads || model.localDownloadLoadError != nil)
                    .accessibilityIdentifier("import-gallery-metadata-action")
                }
                SettingsActionRow(
                    title: "导入完整备份",
                    subtitle: "从 .eharchive 或兼容 ZIP 文件恢复下载内容"
                ) {
                    Button("导入…") {
                        startFileImport(.downloadArchive)
                    }
                    .disabled(model.isMigrating || model.isRestoringDownloads || model.isLoadingDownloads || model.localDownloadLoadError != nil)
                    .accessibilityIdentifier("import-download-archive-action")
                }
                SettingsActionRow(
                    title: "导出漫画列表",
                    subtitle: "导出为 .ehgallery 文件"
                ) {
                    Button("导出…") {
                        model.runFileOperation {
                            guard let url = await model.exportGallerySync() else { return }
#if os(iOS)
                            pendingShareFile = PendingSharedFile(url: url)
#else
                            gallerySyncExportFilename = url.lastPathComponent
                            gallerySyncExportDocument = GallerySyncExportDocument(sourceURL: url)
                            showingGallerySyncExporter = true
#endif
                        }
                    }
                    .disabled(model.isMigrating || model.isRestoringDownloads || model.isLoadingDownloads || model.localDownloadLoadError != nil)
                    .accessibilityIdentifier("export-gallery-metadata-action")
                }
                SettingsActionRow(
                    title: "导出完整备份",
                    subtitle: "导出为 .eharchive 文件"
                ) {
                    Button("导出…") {
                        model.runFileOperation {
                            guard let url = await model.exportDownloadArchive() else { return }
#if os(iOS)
                            pendingShareFile = PendingSharedFile(url: url)
#else
                            pendingArchiveSaveFile = PendingSharedFile(url: url)
#endif
                        }
                    }
                    .disabled(model.isMigrating || model.isRestoringDownloads || model.isLoadingDownloads || model.localDownloadLoadError != nil)
                    .accessibilityIdentifier("export-download-archive-action")
                }
            }
            Section("设备间同步") {
                NavigationLink(value: AppRoute.settingsDeviceSync) {
                    SettingsDetailLabel(
                        title: "设备间同步",
                        subtitle: "在附近设备之间同步漫画和阅读进度"
                    )
                }
                .accessibilityIdentifier("device-sync-link")
                .disabled(model.isMigrating || model.isRestoringDownloads || model.isLoadingDownloads || model.localDownloadLoadError != nil)

                SettingsActionRow(
                    title: "重建同步索引",
                    subtitle: "完整扫描下载记录和本地页面文件，替换现有同步索引"
                ) {
                    Button("重建…") {
                        model.runFileOperation {
                            await model.buildDeviceSyncIndex()
                        }
                    }
                    .disabled(model.isMigrating || model.isRestoringDownloads || model.isLoadingDownloads || model.localDownloadLoadError != nil)
                    .accessibilityIdentifier("rebuild-device-sync-index-action")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("数据备份&同步")
    }

    var body: some View {
        settingsContent
            .sheet(isPresented: $showingCookieSheet) { CookieLoginSheet() }
        .sheet(isPresented: $showingWebLogin) { WebLoginSheet() }
        .sheet(isPresented: $showingPasswordLogin) { PasswordLoginSheet() }
        .sheet(item: $profileNameEditor) { request in
            ProfileNameEditor(request: request) { name in
                switch request.action {
                case .create:
                    Task { await profileSession.createProfile(named: name) }
                case let .rename(id):
                    profileSession.renameProfile(id: id, to: name)
                }
            }
        }
        .confirmationDialog(
            "删除 \(profilePendingDeletion?.name ?? "空间")？",
            isPresented: Binding(
                get: { profilePendingDeletion != nil },
                set: { if $0 == false { profilePendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除下载、数据库、缓存、会话和偏好设置", role: .destructive) {
                if let profile = profilePendingDeletion {
                    profilePendingDeletion = nil
                    Task { await profileSession.deleteProfile(id: profile.id) }
                }
            }
            Button("取消", role: .cancel) { profilePendingDeletion = nil }
        } message: {
            Text("删除前将再次请求系统认证。此操作仅清理该空间在应用沙盒中的下载、SwiftData、缓存、同步索引、会话和偏好设置；不会影响导出的备份或照片图库。")
        }
#if os(iOS)
        .sheet(item: $pendingShareFile, onDismiss: discardPendingSharedFileIfAny) { file in
            ShareSheet(items: [file.url])
        }
#endif
        .fileExporter(
            isPresented: $showingGallerySyncExporter,
            document: gallerySyncExportDocument,
            contentTypes: [.ehViewerGallerySync],
            defaultFilename: gallerySyncExportFilename
        ) { result in
            if let sourceURL = gallerySyncExportDocument?.sourceURL {
                model.discardPendingSharedFile(sourceURL)
            }
            gallerySyncExportDocument = nil
            if case let .failure(error) = result {
                model.errorMessage = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: fileImporterKind.allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            let importKind = fileImporterKind
            showingFileImporter = false
            switch importKind {
            case .gallerySync:
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        model.stageGallerySyncImport(from: url)
                    }
                case .failure(let error):
                    model.errorMessage = error.localizedDescription
                }
            case .downloadArchive:
                guard case let .success(urls) = result, let url = urls.first else {
                    if case let .failure(error) = result {
                        downloadRestoreMessage = error.localizedDescription
                        showingDownloadRestoreResult = true
                    }
                    return
                }
                model.runFileOperation {
                    downloadRestoreMessage = await model.restoreDownloads(from: url).message
                    showingDownloadRestoreResult = true
                    // iOS 文件选择器会在 tmp/Inbox 留下副本，导入后清理。
                    model.discardTemporaryImportCopy(url)
                }
            }
        }
        .alert("恢复下载项", isPresented: $showingDownloadRestoreResult) {
            Button("好", role: .cancel) {}
        } message: {
            Text(downloadRestoreMessage)
        }
#if os(macOS)
        .task(id: pendingArchiveSaveFile?.id) {
            guard let file = pendingArchiveSaveFile else { return }
            await saveDownloadArchive(file.url)
            pendingArchiveSaveFile = nil
        }
#endif
        .task(id: "\(page)-\(model.isLoadingDownloads)") {
            if !model.isLoadingDownloads, model.localDownloadLoadError == nil,
               (page == .storageAndProgress || page == .storageManagement) {
                await model.refreshGalleryCacheUsage()
                await model.refreshLocalDownloadUsage()
            }
            if page == .filters || page == .browsingAndFiltering {
                await model.loadFilterRules()
            }
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch page {
        case .overview:
            settingsForm
        case .siteAndLogin:
            siteAndLoginForm
        case .browsingAndFiltering:
            browsingAndFilteringForm
        case .reading:
            ReadingSettingsForm()
        case .storageManagement:
            storageAndProgressForm
        case .dataBackupAndSync:
            dataAndBackupForm
        case .site:
            siteForm
        case .login:
            loginForm
        case .browsing:
            browsingForm
        case .filters:
            filterRulesForm
        case .storageAndProgress:
            storageAndProgressForm
        case .dataAndBackup:
            dataAndBackupForm
        }
    }

    /// 分享面板关闭后删除临时导出的数据包，避免残留占用存储。
    private func discardPendingSharedFileIfAny() {
        if let url = model.pendingSharedFileURL {
            model.discardPendingSharedFile(url)
        }
    }

    private func startFileImport(_ kind: FileImportKind) {
        fileImporterKind = kind
        showingFileImporter = true
    }

#if os(macOS)
    private func saveDownloadArchive(_ sourceURL: URL) async {
        defer { model.discardPendingSharedFile(sourceURL) }
        do {
            _ = try await DownloadArchiveSavePanel.save(sourceURL)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
#endif

    private var appVersion: String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return String(localized: "未知")
        }
        return version
    }

    private var galleryCacheSize: String {
        ByteCountFormatter.string(fromByteCount: model.galleryCacheByteCount, countStyle: .file)
    }

    private var localDownloadSize: String {
        ByteCountFormatter.string(fromByteCount: model.localDownloadByteCount, countStyle: .file)
    }
}

private struct SettingsActionRow<Action: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let action: () -> Action

    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        @ViewBuilder action: @escaping () -> Action
    ) {
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }

    var body: some View {
        if horizontalSizeClass == .compact {
            VStack(alignment: .leading, spacing: 8) {
                SettingsDetailLabel(title: title, subtitle: subtitle)
                HStack {
                    Spacer(minLength: 0)
                    action()
                }
            }
        } else {
            LabeledContent {
                action()
            } label: {
                SettingsDetailLabel(title: title, subtitle: subtitle)
            }
        }
    }
}

private struct SettingsDetailLabel: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TagDatabaseSettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            LabeledContent("更新状态") {
                HStack(spacing: 6) {
                    if model.isCheckingTagDatabaseUpdate || model.isUpdatingTagDatabase {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(statusTitle)
                        .foregroundStyle(statusColor)
                }
            }
            if let error = model.tagDatabaseUpdateError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button(actionTitle, action: performPrimaryAction)
                .foregroundStyle(.primary)
                .disabled(model.isCheckingTagDatabaseUpdate || model.isUpdatingTagDatabase)
                .accessibilityIdentifier("tag-database-update-action")
        } header: {
            Text("标签数据库")
        } footer: {
            Text("标签翻译和标签联想已随应用内置。不会在启动时联网；检查更新会下载并校验候选文件，安装失败时会保留并恢复原有数据库。")
        }
    }

    private var statusTitle: String {
        if model.isCheckingTagDatabaseUpdate { return "正在检查更新…" }
        if model.isUpdatingTagDatabase { return "正在更新…" }
        switch model.tagDatabaseUpdateStatus {
        case .latest: return "已是最新"
        case .updateAvailable: return "有更新可用"
        case .unknown: return model.tagDatabaseUpdateError == nil ? "未知（尚未检查）" : "检查失败"
        }
    }

    private var statusColor: Color {
        model.tagDatabaseUpdateStatus == .updateAvailable ? AppTheme.accent : .secondary
    }

    private var actionTitle: String {
        if model.isUpdatingTagDatabase { return "正在更新" }
        if model.isCheckingTagDatabaseUpdate { return "正在检查" }
        return model.tagDatabaseUpdateStatus == .updateAvailable ? "更新标签数据库" : "检查更新"
    }

    private func performPrimaryAction() {
        Task {
            if model.tagDatabaseUpdateStatus == .updateAvailable {
                await model.updateTagDatabase()
            } else {
                await model.checkTagDatabaseForUpdate()
            }
        }
    }
}

/// Filter rules list with mode pickers and a tag candidate bar under the
/// keyword field, mirroring the browse search suggestions.
private struct FilterRulesSection: View {
    @Environment(AppModel.self) private var model
    @State private var newFilter = ""
    @State private var newFilterMode: GalleryFilterMode = .title
    @State private var filterSuggestions: [SearchTagSuggestion] = []
    @State private var isUpdatingFilterSuggestions = false

    var body: some View {
        @Bindable var model = model
        Section {
            ForEach(model.filterRules.indices, id: \.self) { index in
                let rule = model.filterRules[index]
                HStack(spacing: 10) {
                    modeMenu(for: rule.mode) { mode in
                        Task {
                            await model.setFilterRule(
                                pattern: rule.pattern,
                                isEnabled: rule.isEnabled,
                                mode: mode
                            )
                        }
                    }
                    if rule.mode == .tag {
                        Toggle(isOn: $model.filterRules[index].isEnabled) {
                            FilterTagChip(keyword: rule.pattern)
                        }
                        .toggleStyle(.switch)
                        .onChange(of: model.filterRules[index].isEnabled) { _, enabled in
                            Task {
                                await model.setFilterRule(
                                    pattern: rule.pattern,
                                    isEnabled: enabled,
                                    mode: rule.mode
                                )
                            }
                        }
                    } else {
                        Toggle(rule.pattern, isOn: $model.filterRules[index].isEnabled)
                            .onChange(of: model.filterRules[index].isEnabled) { _, enabled in
                                Task {
                                    await model.setFilterRule(
                                        pattern: rule.pattern,
                                        isEnabled: enabled,
                                        mode: rule.mode
                                    )
                                }
                            }
                    }
                    Button("删除规则", systemImage: "trash", role: .destructive) {
                        Task { await model.deleteFilterRule(pattern: rule.pattern, mode: rule.mode) }
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("删除过滤规则 \(rule.pattern)")
                }
            }
            HStack(spacing: 10) {
                modeMenu(for: newFilterMode) { mode in
                    newFilterMode = mode
                }
                TextField("关键词，如 ai generated", text: $newFilter)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                Button("添加") {
                    let pattern = newFilter.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard pattern.isEmpty == false else { return }
                    let mode = newFilterMode
                    newFilter = ""
                    Task { await model.setFilterRule(pattern: pattern, isEnabled: true, mode: mode) }
                }
                .disabled(newFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if newFilterMode == .tag,
               newFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                HStack(spacing: 6) {
                    Text("将添加标签")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    FilterTagChip(keyword: newFilter)
                }
                .accessibilityIdentifier("filter-keyword-preview")
            }
            if filterSuggestions.isEmpty == false {
                ScrollView(.vertical, showsIndicators: false) {
                    TagFlowLayout(horizontalSpacing: 8, verticalSpacing: 6) {
                        ForEach(filterSuggestions) { suggestion in
                            Button {
                                newFilter = filterKeyword(for: suggestion)
                                newFilterMode = .tag
                            } label: {
                                Label(
                                    candidateLabel(for: suggestion),
                                    systemImage: "tag"
                                )
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .frame(height: 22)
                                .foregroundStyle(.white)
                                .background(AppTheme.accent, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("按标签 \(suggestion.english) 过滤")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 170)
                .accessibilityIdentifier("filter-suggestion-bar")
            } else if isUpdatingFilterSuggestions {
                HStack(spacing: 6) {
                    ProgressView()
                    Text("正在读取标签候选…")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        } header: {
            Text("过滤规则")
        } footer: {
            Text("标题=标题包含关键词；上传者=完全相等；标签=精确匹配（如 ai generated 或 misc:ai generated）；标签组=屏蔽整个命名空间（如 male）。")
        }
        .task(id: newFilter) {
            let query = newFilter.trimmingCharacters(in: .whitespacesAndNewlines)
            guard query.isEmpty == false else {
                filterSuggestions = []
                isUpdatingFilterSuggestions = false
                return
            }
            isUpdatingFilterSuggestions = true
            try? await Task.sleep(for: .milliseconds(250))
            guard Task.isCancelled == false else { return }
            filterSuggestions = await model.filterTagSuggestions(for: query)
            isUpdatingFilterSuggestions = false
        }
    }

    private func modeMenu(for mode: GalleryFilterMode, action: @escaping (GalleryFilterMode) -> Void) -> some View {
        Menu {
            ForEach(GalleryFilterMode.allCases) { candidate in
                Button(candidate.title) { action(candidate) }
            }
        } label: {
            Text(mode.title)
                .font(.caption.weight(.semibold))
#if os(macOS)
                .foregroundStyle(AppTheme.accent)
#else
                .foregroundStyle(.white)
#endif
                .padding(.horizontal, 9)
                .frame(height: 24)
#if os(macOS)
                .background(AppTheme.accent.opacity(0.16), in: Capsule())
#else
                .background(AppTheme.accent, in: Capsule())
#endif
        }
#if os(macOS)
        .tint(AppTheme.accent)
#endif
        .accessibilityLabel("规则模式 \(mode.title)")
    }

    private func filterKeyword(for suggestion: SearchTagSuggestion) -> String {
        let english = suggestion.english
        if let separator = english.firstIndex(of: ":") {
            return String(english[english.index(after: separator)...])
        }
        return english
    }

    /// Candidate chips follow the tag-translation setting: translated names
    /// when it is on, the original English tag names when it is off. The
    /// inserted keyword stays English either way because rules match against
    /// the original tag names.
    private func candidateLabel(for suggestion: SearchTagSuggestion) -> String {
        guard model.readingSettings.showTagTranslations else {
            return filterKeyword(for: suggestion)
        }
        return suggestion.localizedText ?? filterKeyword(for: suggestion)
    }
}

/// A filter-rule tag keyword rendered as a capsule chip; the label follows
/// the tag-translation setting through `displayTag`.
private struct FilterTagChip: View {
    @Environment(AppModel.self) private var model
    let keyword: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "tag")
                .font(.caption2)
            Text(model.displayTag(keyword))
                .lineLimit(1)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .frame(height: 22)
        .foregroundStyle(.white)
        .background(AppTheme.accent, in: Capsule())
        .accessibilityLabel("标签 \(model.displayTag(keyword))")
    }
}

private struct SettingsNavigationLabel: View {
    let title: LocalizedStringKey
    let systemImage: String

    init(
        _ title: LocalizedStringKey,
        systemImage: String
    ) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 24, alignment: .leading)
        }
    }
}
