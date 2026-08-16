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
import UniformTypeIdentifiers
import EHDomain

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showingCookieSheet = false
    @State private var showingWebLogin = false
    @State private var showingPasswordLogin = false
    @State private var showingMigrationExporter = false
    @State private var showingMigrationImporter = false
    @State private var migrationExportDocument: MigrationExportDocument?
    @State private var migrationExportContentTypes: [UTType] = [.json]
    @State private var migrationExportFilename = "ehviewer-migration.json"
    @State private var showingMigrationResult = false
    @State private var migrationMessage = ""

    var body: some View {
        @Bindable var model = model
        Form {
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
                Text("「显示标签翻译」开启时详情页标签显示中文翻译（参考项目默认开启）；关闭时显示英文标签名。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("登录") {
                Button("用户名&密码登录", systemImage: "person.badge.key") { showingPasswordLogin = true }
                Button("网页登录", systemImage: "safari") { showingWebLogin = true }
                Button("Cookie登录", systemImage: "key") { showingCookieSheet = true }
                Button("清除Cookie", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    Task { await model.clearSession() }
                }
                Text("密码仅用于本次登录请求；会话 Cookie 由 Keychain 管理。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("About") {
                LabeledContent("version:", value: "1.0-beta")
                Text("基于https://github.com/xiaojieonly/Ehviewer_CN_SXJ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            FilterRulesSection()
            Section("数据迁移") {
                Button("导出 JSON", systemImage: "doc.badge.gearshape") {
                    Task {
                        guard let data = await model.exportMigrationData() else {
                            migrationMessage = model.errorMessage ?? String(localized: "JSON 导出失败，请稍后重试。")
                            showingMigrationResult = true
                            return
                        }
                        migrationExportContentTypes = [.json]
                        migrationExportFilename = "ehviewer-migration.json"
                        migrationExportDocument = MigrationExportDocument(data: data)
                        showingMigrationExporter = true
                    }
                }
                .disabled(model.isMigrating)
                Button("导出下载压缩包", systemImage: "archivebox") {
                    Task {
                        guard let url = await model.exportDownloadArchive() else {
                            migrationMessage = model.errorMessage ?? String(localized: "下载压缩包导出失败，请稍后重试。")
                            showingMigrationResult = true
                            return
                        }
                        migrationExportContentTypes = [.zip]
                        migrationExportFilename = "ehviewer-downloads.zip"
                        migrationExportDocument = MigrationExportDocument(sourceURL: url)
                        showingMigrationExporter = true
                    }
                }
                .disabled(model.isMigrating)
                Button("导入数据", systemImage: "square.and.arrow.down") {
                    showingMigrationImporter = true
                }
                .disabled(model.isMigrating)
                Text("JSON 包含收藏、阅读进度、下载任务、搜索记录、过滤规则和阅读设置；下载压缩包包含本地已下载文件。导入会与本地数据合并。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings-screen")
        .navigationTitle("settings_title")
        .sheet(isPresented: $showingCookieSheet) { CookieLoginSheet() }
        .sheet(isPresented: $showingWebLogin) { WebLoginSheet() }
        .sheet(isPresented: $showingPasswordLogin) { PasswordLoginSheet() }
        .fileExporter(
            isPresented: $showingMigrationExporter,
            document: migrationExportDocument,
            contentTypes: migrationExportContentTypes,
            defaultFilename: migrationExportFilename
        ) { result in
            if let sourceURL = migrationExportDocument?.sourceURL {
                try? FileManager.default.removeItem(at: sourceURL)
            }
            migrationExportDocument = nil
            if case let .failure(error) = result {
                migrationMessage = error.localizedDescription
                showingMigrationResult = true
            }
        }
        .fileImporter(
            isPresented: $showingMigrationImporter,
            allowedContentTypes: MigrationDocument.readableContentTypes,
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else {
                if case let .failure(error) = result {
                    migrationMessage = error.localizedDescription
                    showingMigrationResult = true
                }
                return
            }
            Task {
                do {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let data = try await Task.detached(priority: .userInitiated) {
                        try Data(contentsOf: url, options: .mappedIfSafe)
                    }.value
                    let imported = await model.importMigrationData(data)
                    migrationMessage = imported ? String(localized: "数据已导入，并已与本地数据合并。") : String(localized: "数据导入失败，请检查迁移文件。")
                } catch {
                    migrationMessage = error.localizedDescription
                }
                showingMigrationResult = true
            }
        }
        .alert("数据迁移", isPresented: $showingMigrationResult) {
            Button("好", role: .cancel) {}
        } message: {
            Text(migrationMessage)
        }
        .overlay {
            if let progress = model.migrationProgress {
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
                }
                .padding()
                .frame(maxWidth: 280)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(progress.status)
            }
        }
        .task { await model.loadFilterRules() }
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
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(AppTheme.accent, in: Capsule())
        }
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
