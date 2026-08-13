import SwiftUI
import UniformTypeIdentifiers
import EHDomain

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showingCookieSheet = false
    @State private var showingWebLogin = false
    @State private var showingPasswordLogin = false
    @State private var newFilter = ""
    @State private var showingMigrationExporter = false
    @State private var showingMigrationImporter = false
    @State private var migrationDocument: MigrationDocument?
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
                        model.isGuestMode ? "游客模式" : "已登录",
                        systemImage: model.isGuestMode ? "person" : "person.crop.circle.badge.checkmark"
                    )
                    Spacer()
                    Text(model.isGuestMode ? "公开内容" : "账户会话")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("session-status")
                .accessibilityLabel("会话状态")
                .accessibilityValue(model.isGuestMode ? "游客模式" : "已登录")
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
            Section("过滤规则") {
                ForEach(model.filterRules.indices, id: \.self) { index in
                    let pattern = model.filterRules[index].pattern
                    Toggle(pattern, isOn: $model.filterRules[index].isEnabled)
                        .onChange(of: model.filterRules[index].isEnabled) { _, enabled in
                            Task { await model.setFilterRule(pattern: pattern, isEnabled: enabled) }
                        }
                }
                HStack {
                    TextField("添加标题或标签关键词", text: $newFilter)
                    Button("添加") {
                        let pattern = newFilter.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard pattern.isEmpty == false else { return }
                        newFilter = ""
                        Task { await model.setFilterRule(pattern: pattern, isEnabled: true) }
                    }
                    .disabled(newFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            Section("数据迁移") {
                Button("导出数据", systemImage: "square.and.arrow.up") {
                    Task {
                        guard let data = await model.exportMigrationData() else { return }
                        migrationDocument = MigrationDocument(data: data)
                        showingMigrationExporter = true
                    }
                }
                Button("导入数据", systemImage: "square.and.arrow.down") {
                    showingMigrationImporter = true
                }
                Text("迁移包包含收藏、阅读进度、下载任务、搜索记录、过滤规则和阅读设置；下载图片文件不会被打包。")
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
            document: migrationDocument,
            contentTypes: MigrationDocument.writableContentTypes,
            defaultFilename: "ehviewer-migration.json"
        ) { result in
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
                    let data = try Data(contentsOf: url)
                    let imported = await model.importMigrationData(data)
                    migrationMessage = imported ? "数据已导入。现有数据会被合并，下载图片文件需要单独复制。" : "数据导入失败，请检查迁移文件。"
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
        .task { await model.loadFilterRules() }
    }
}
