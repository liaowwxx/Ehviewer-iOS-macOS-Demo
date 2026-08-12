import SwiftUI
import EHDomain

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showingCookieSheet = false
    @State private var showingWebLogin = false
    @State private var showingPasswordLogin = false
    @State private var newFilter = ""

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
                        model.isGuestMode ? "游客浏览" : "已登录",
                        systemImage: model.isGuestMode ? "person" : "person.crop.circle.badge.checkmark"
                    )
                    Spacer()
                    Text(model.isGuestMode ? "公开内容" : "账户会话")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("session-status")
                .accessibilityLabel("会话状态")
                .accessibilityValue(model.isGuestMode ? "游客浏览" : "已登录")
            }
            Section("登录") {
                Button("用户名和密码登录", systemImage: "person.badge.key") { showingPasswordLogin = true }
                Button("通过网页登录", systemImage: "safari") { showingWebLogin = true }
                Button("通过 Cookie 登录", systemImage: "key") { showingCookieSheet = true }
                Button("清除会话 Cookie", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    Task { await model.clearSession() }
                }
                Text("密码仅用于本次登录请求；会话 Cookie 由 Keychain 管理。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("隐私") {
                Button(model.appLockEnabled ? "关闭应用锁" : "启用应用锁", systemImage: model.appLockEnabled ? "lock.open" : "lock") {
                    Task { await model.setAppLockEnabled(model.appLockEnabled == false) }
                }
                Text("启用后，应用进入后台再回来时需要 Face ID、Touch ID 或设备密码。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("关于") {
                LabeledContent("版本", value: "0.1 基线")
                Text("游客模式仅访问站点公开内容；登录会话 Cookie 由 Keychain 管理。")
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
        }
        .formStyle(.grouped)
        .navigationTitle("settings_title")
        .sheet(isPresented: $showingCookieSheet) { CookieLoginSheet() }
        .sheet(isPresented: $showingWebLogin) { WebLoginSheet() }
        .sheet(isPresented: $showingPasswordLogin) { PasswordLoginSheet() }
        .task { await model.loadFilterRules() }
    }
}
