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

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showingCookieSheet = false
    @State private var showingWebLogin = false
    @State private var showingPasswordLogin = false
    @State private var showingArchiveShareSheet = false
    @State private var showingGallerySyncExporter = false
    @State private var showingGallerySyncShareSheet = false
    @State private var showingGallerySyncImporter = false
    @State private var gallerySyncExportDocument: GallerySyncExportDocument?
    @State private var gallerySyncExportFilename = "EhViewer-Galleries.ehgallery"
    @State private var showingDownloadRestoreImporter = false
    @State private var showingDownloadRestoreResult = false
    @State private var downloadRestoreMessage = ""
    @State private var showingGalleryCacheClearConfirmation = false
    @State private var showingDownloadReadingProgressResetConfirmation = false

    private var settingsForm: some View {
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
                HStack {
                    Label(
                        model.isGuestMode ? String(localized: "游客模式") : String(localized: "已登录"),
                        systemImage: model.isGuestMode ? "person" : "person.crop.circle.badge.checkmark"
                    )
                    Spacer()
                    Text(model.isGuestMode ? String(localized: "公开内容") : String(localized: "账户会话"))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("session-status")
                .accessibilityLabel("会话状态")
                .accessibilityValue(model.isGuestMode ? String(localized: "游客模式") : String(localized: "已登录"))
            }
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
                Button("重置下载内容的阅读进度", systemImage: "arrow.counterclockwise", role: .destructive) {
                    showingDownloadReadingProgressResetConfirmation = true
                }
                .accessibilityIdentifier("reset-download-reading-progress-action")
                LabeledContent("缓存占用", value: galleryCacheSize)
                Button("清除缓存", systemImage: "trash", role: .destructive) {
                    showingGalleryCacheClearConfirmation = true
                }
                .accessibilityIdentifier("clear-gallery-cache-action")
            }
            Section("登录") {
                Button("用户名&密码登录", systemImage: "person.badge.key") { showingPasswordLogin = true }
                Button("网页登录", systemImage: "safari") { showingWebLogin = true }
                Button("Cookie登录", systemImage: "key") { showingCookieSheet = true }
                Button("清除Cookie", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    Task { await model.clearSession() }
                }
            }
            Section("About") {
                LabeledContent("version:", value: appVersion)
            }
            Section("帮助") {
                if let documentationURL = DocumentationWebsite.url {
                    Link(destination: documentationURL) {
                        Label("使用说明", systemImage: "book.closed")
                    }
                    .accessibilityIdentifier("usage-documentation-link")
                }
            }
            FilterRulesSection()
            Section("数据迁移/备份") {
                Button("更新已下载画廊信息", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await model.refreshDownloadedGalleryMetadata() }
                }
                .disabled(model.isMigrating || model.isRestoringDownloads || model.isLoadingDownloads)
                .accessibilityIdentifier("refresh-downloaded-gallery-metadata-action")
                Label("导入", systemImage: "square.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
                Button("导入元数据(.ehgallery)", systemImage: "square.and.arrow.down") {
                    showingGallerySyncImporter = true
                }
                .disabled(model.isMigrating || model.isRestoringDownloads)
                Button("导入归档(.eharchive)", systemImage: "arrow.counterclockwise.circle") {
                    showingDownloadRestoreImporter = true
                }
                .disabled(model.isMigrating || model.isRestoringDownloads)
                Label("导出", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                Button("导出元数据(.ehgallery)", systemImage: "square.and.arrow.up") {
                    Task {
                        guard let url = await model.exportGallerySync() else { return }
#if os(iOS)
                        showingGallerySyncShareSheet = true
#else
                        gallerySyncExportFilename = url.lastPathComponent
                        gallerySyncExportDocument = GallerySyncExportDocument(sourceURL: url)
                        showingGallerySyncExporter = true
#endif
                    }
                }
                .disabled(model.isMigrating || model.isRestoringDownloads)
                Button("导出归档(.eharchive)", systemImage: "square.and.arrow.up") {
                    Task {
                        guard let url = await model.exportDownloadArchive() else { return }
#if os(iOS)
                        showingArchiveShareSheet = true
#else
                        await saveDownloadArchive(url)
#endif
                    }
                }
                .disabled(model.isMigrating || model.isRestoringDownloads)
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings-screen")
        .navigationTitle("settings_title")
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
        .confirmationDialog(
            "重置所有下载内容的阅读进度？",
            isPresented: $showingDownloadReadingProgressResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("重置进度", role: .destructive) {
                Task { await model.resetAllDownloadReadingProgress() }
            }
            Button("取消", role: .cancel) {}
        }
    }

    var body: some View {
        settingsForm
            .sheet(isPresented: $showingCookieSheet) { CookieLoginSheet() }
        .sheet(isPresented: $showingWebLogin) { WebLoginSheet() }
        .sheet(isPresented: $showingPasswordLogin) { PasswordLoginSheet() }
        .sheet(isPresented: $showingArchiveShareSheet, onDismiss: discardPendingSharedFileIfAny) {
#if os(iOS)
            if let url = model.pendingSharedFileURL {
                ShareSheet(items: [url])
            }
#endif
        }
        .sheet(isPresented: $showingGallerySyncShareSheet, onDismiss: discardPendingSharedFileIfAny) {
#if os(iOS)
            if let url = model.pendingSharedFileURL {
                ShareSheet(items: [url])
            }
#endif
        }
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
            isPresented: $showingGallerySyncImporter,
            allowedContentTypes: BackupFileFormat.gallerySyncImportTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    model.stageGallerySyncImport(from: url)
                }
            case .failure(let error):
                model.errorMessage = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $showingDownloadRestoreImporter,
            allowedContentTypes: BackupFileFormat.downloadImportTypes,
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else {
                if case let .failure(error) = result {
                    downloadRestoreMessage = error.localizedDescription
                    showingDownloadRestoreResult = true
                }
                return
            }
            Task {
                downloadRestoreMessage = await model.restoreDownloads(from: url).message
                showingDownloadRestoreResult = true
                // iOS 文件选择器会在 tmp/Inbox 留下副本，导入后清理。
                model.discardTemporaryImportCopy(url)
            }
        }
        .alert("恢复下载项", isPresented: $showingDownloadRestoreResult) {
            Button("好", role: .cancel) {}
        } message: {
            Text(downloadRestoreMessage)
        }
        .task {
            await model.refreshGalleryCacheUsage()
            await model.loadFilterRules()
        }
    }

    /// 分享面板关闭后删除临时导出的数据包，避免残留占用存储。
    private func discardPendingSharedFileIfAny() {
        if let url = model.pendingSharedFileURL {
            model.discardPendingSharedFile(url)
        }
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
