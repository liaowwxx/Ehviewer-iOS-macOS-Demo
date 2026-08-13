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
                ForEach(model.filterRules, id: \.pattern) { rule in
                    Toggle(rule.pattern, isOn: Binding(
                        get: { rule.isEnabled },
                        set: { enabled in Task { await model.setFilterRule(pattern: rule.pattern, isEnabled: enabled) } }
                    ))
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
            Section("阅读设置") {
                Picker("阅读方向", selection: $model.readingSettings.readingMode) {
                    ForEach(ReadingMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Picker("页面缩放", selection: $model.readingSettings.pageScaling) {
                    ForEach(ReaderPageScaling.allCases) { scaling in
                        Text(scaling.title).tag(scaling)
                    }
                }
                Picker("开始位置", selection: $model.readingSettings.startPosition) {
                    ForEach(ReaderStartPosition.allCases) { position in
                        Text(position.title).tag(position)
                    }
                }
                Picker("屏幕旋转", selection: $model.readingSettings.screenRotation) {
                    ForEach(ReaderScreenRotation.allCases) { rotation in
                        Text(rotation.title).tag(rotation)
                    }
                }
                Picker("自动翻页", selection: $model.readingSettings.autoAdvanceSeconds) {
                    Text("关闭").tag(0)
                    ForEach([3, 5, 10, 15, 30, 60], id: \.self) { seconds in
                        Text("每 " + String(seconds) + " 秒").tag(seconds)
                    }
                }
                Toggle("阅读时保持屏幕常亮", isOn: $model.readingSettings.keepScreenOn)
                Toggle("显示时钟", isOn: $model.readingSettings.showClock)
                Toggle("显示阅读进度", isOn: $model.readingSettings.showProgress)
                Toggle("显示电量", isOn: $model.readingSettings.showBattery)
                Toggle("显示页码", isOn: $model.readingSettings.showPageInterval)
                Toggle("音量键翻页", isOn: $model.readingSettings.volumePage)
                Toggle("反转音量键方向", isOn: $model.readingSettings.reverseVolumePage)
                Toggle("进入阅读器时全屏", isOn: $model.readingSettings.fullscreen)
                Toggle("自定义屏幕亮度", isOn: $model.readingSettings.customBrightness)
                if model.readingSettings.customBrightness {
                    Slider(value: $model.readingSettings.brightness, in: 0.05...1) {
                        Text("屏幕亮度")
                    } minimumValueLabel: {
                        Image(systemName: "sun.min")
                    } maximumValueLabel: {
                        Image(systemName: "sun.max")
                    }
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
        .onChange(of: model.readingSettings) { _, _ in
            model.persistReadingSettings()
        }
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
