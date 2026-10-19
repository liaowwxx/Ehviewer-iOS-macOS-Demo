/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai gallery browsing client
 * Copyright (C) 2026 EhViewer Contributors
 */

import Foundation
import LocalAuthentication
import Observation
import SwiftData
import SwiftUI
import EHDomain
import EHDeviceSync
import EHDownloads
import EHNetworking
import EHPersistence
#if os(macOS)
import EHTranslationMac
#endif

struct ProfileDescriptor: Codable, Identifiable, Hashable, Sendable {
    static let currentStorageVersion = 1

    let id: UUID
    var name: String
    let createdAt: Date
    var lastUsedAt: Date
    var storageVersion: Int
    var usesLegacyStorage: Bool
    var isDeleting: Bool

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        lastUsedAt: Date = Date(),
        storageVersion: Int = currentStorageVersion,
        usesLegacyStorage: Bool = false,
        isDeleting: Bool = false
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.storageVersion = storageVersion
        self.usesLegacyStorage = usesLegacyStorage
        self.isDeleting = isDeleting
    }
}

private struct ProfileRegistryDocument: Codable {
    var formatVersion = 1
    var profiles: [ProfileDescriptor]
    var lastUsedProfileID: UUID?
}

struct ProfileStorageLayout: Sendable {
    let profileID: UUID
    let root: URL
    let usesLegacyStorage: Bool

    init(profileID: UUID, root: URL, usesLegacyStorage: Bool = false) {
        self.profileID = profileID
        self.root = root
        self.usesLegacyStorage = usesLegacyStorage
    }

    var storeURL: URL { root.appendingPathComponent("Store.store") }
    var downloadsRoot: URL { usesLegacyStorage ? DownloadFileStore.defaultRootURL : root.appendingPathComponent("Downloads", isDirectory: true) }
    var translationRoot: URL { usesLegacyStorage ? TranslationFileStore.defaultRootURL : root.appendingPathComponent("Translations", isDirectory: true) }
    var galleryCacheRoot: URL { usesLegacyStorage ? GalleryCacheStore.defaultRootURL : root.appendingPathComponent("GalleryCache", isDirectory: true) }
    var imageCacheRoot: URL {
        usesLegacyStorage
            ? (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? root).appendingPathComponent("EhViewer/ImageCache", isDirectory: true)
            : root.appendingPathComponent("ImageCache", isDirectory: true)
    }
    var thumbnailCacheRoot: URL { usesLegacyStorage ? GalleryCoverLoader.defaultRootURL : root.appendingPathComponent("Thumbnails", isDirectory: true) }
    var tagDatabaseURL: URL {
        usesLegacyStorage
            ? root.appendingPathComponent("EhViewer/TagDatabase/tag-translations-zh-rCN")
            : root.appendingPathComponent("TagDatabase/tag-translations-zh-rCN")
    }
    var deviceSyncIndexRoot: URL { usesLegacyStorage ? DeviceSyncIndexStore.defaultRootURL : root.appendingPathComponent("DeviceSync/Index", isDirectory: true) }
    var deviceSyncTransactionRoot: URL { usesLegacyStorage ? root.appendingPathComponent("EhViewer/DeviceSync/Transactions", isDirectory: true) : root.appendingPathComponent("DeviceSync/Transactions", isDirectory: true) }

    static var profilesRoot: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return applicationSupport.appendingPathComponent("EhViewer/Profiles", isDirectory: true)
    }

    static func legacy(for profileID: UUID) -> ProfileStorageLayout {
        // The first profile adopts the old locations rather than copying a
        // SwiftData store. New profiles are always contained below Profiles.
        ProfileStorageLayout(
            profileID: profileID,
            root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory,
            usesLegacyStorage: true
        )
    }

    static func isolated(for profileID: UUID, profilesRoot: URL = ProfileStorageLayout.profilesRoot) -> ProfileStorageLayout {
        ProfileStorageLayout(
            profileID: profileID,
            root: profilesRoot.appendingPathComponent(profileID.uuidString, isDirectory: true)
        )
    }
}

/// Separate macOS reader windows carry their runtime identity. A window from a
/// previously unlocked profile therefore cannot attach itself to a new profile
/// merely because the gallery key happens to be the same.
struct ProfileReaderRoute: Hashable, Codable, Sendable {
    let profileID: UUID
    let key: GalleryKey
    let page: Int
}

@MainActor
protocol ProfileAuthenticating {
    func authenticate(reason: String) async throws -> Bool
}

@MainActor
struct SystemProfileAuthenticator: ProfileAuthenticating {
    func authenticate(reason: String) async throws -> Bool {
        // UI tests deliberately avoid real biometric prompts. Production never
        // stores a PIN or password and always uses the system policy.
        if ProcessInfo.processInfo.arguments.contains("-UITestAutoAuthenticate") {
            return true
        }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw error ?? ProfileSessionError.authenticationUnavailable
        }
        return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }
}

enum ProfileSessionError: LocalizedError {
    case invalidName
    case profileNotFound
    case authenticationUnavailable
    case authenticationCancelled
    case lastProfile
    case runtimeUnavailable
    case cleanupFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidName: "空间名称不能为空，且不能超过 40 个字符。"
        case .profileNotFound: "找不到所选空间。"
        case .authenticationUnavailable: "此设备无法使用系统认证。"
        case .authenticationCancelled: "系统认证已取消。"
        case .lastProfile: "至少需要保留一个空间。"
        case .runtimeUnavailable: "空间尚未登录。"
        case let .cleanupFailed(detail): "无法完成空间清理：\(detail)"
        }
    }
}

@MainActor
final class ProfileRuntime {
    let descriptor: ProfileDescriptor
    let layout: ProfileStorageLayout
    let container: ModelContainer
    let model: AppModel

    init(
        descriptor: ProfileDescriptor, profilesRoot: URL,
        beforeLocalRestore: (@Sendable () async throws -> Void)? = nil
    ) async throws {
        self.descriptor = descriptor
        layout = descriptor.usesLegacyStorage
            ? .legacy(for: descriptor.id)
            : .isolated(for: descriptor.id, profilesRoot: profilesRoot)

        if descriptor.usesLegacyStorage == false {
            try FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        }
        let container = try ModelContainerFactory.make(
            storeURL: descriptor.usesLegacyStorage ? nil : layout.storeURL
        )
        self.container = container

        let defaults = UserDefaults(suiteName: Self.defaultsSuiteName(for: descriptor.id)) ?? .standard
        let index = DeviceSyncIndexStore(root: layout.deviceSyncIndexRoot)
        let files = DownloadFileStore(root: layout.downloadsRoot, indexSink: index)
        let cache = GalleryCacheStore(root: layout.galleryCacheRoot)
        let tagProvider = TagSuggestionProvider(cacheURL: layout.tagDatabaseURL)
        let store = await Task.detached(priority: .utility) {
            PersistenceStore(modelContainer: container)
        }.value
        model = AppModel(
            container: container,
            persistenceStore: store,
            beforeLocalRestore: beforeLocalRestore,
            sessionVault: SessionVault(service: Self.keychainServiceName(for: descriptor.id)),
            defaults: defaults,
            downloadFiles: files,
            translationRoot: layout.translationRoot,
            galleryCache: cache,
            tagSuggestionProvider: tagProvider,
            imagePipeline: ImagePipeline(diskRoot: layout.imageCacheRoot),
            galleryCoverLoader: GalleryCoverLoader(diskRoot: layout.thumbnailCacheRoot),
            deviceSyncIndex: index,
            deviceSyncTransactionRoot: layout.deviceSyncTransactionRoot,
            backgroundDownloadIdentifier: "com.liao.ehviewer.background-downloads.\(descriptor.id.uuidString)",
            profileID: descriptor.id
        )
    }

    static func defaultsSuiteName(for id: UUID) -> String {
        "com.liao.ehviewer.profile.\(id.uuidString)"
    }

    static func keychainServiceName(for id: UUID) -> String {
        "com.liao.ehviewer.profile.\(id.uuidString)"
    }
}

@MainActor
@Observable
final class ProfileSession {
    private let profilesRoot: URL
    private let registryURL: URL
    private let beforeLocalRestore: (@Sendable () async throws -> Void)?
    private var activationID = UUID()
    private let authenticator: any ProfileAuthenticating
    private var lastUsedProfileID: UUID?

    private(set) var profiles: [ProfileDescriptor] = []
    private(set) var selectedProfileID: UUID?
    private(set) var runtime: ProfileRuntime?
    private(set) var startupError: String?
    private(set) var isAuthenticating = false
    private(set) var isActivatingProfile = false
    private(set) var isPrepared = false

    init(
        profilesRoot: URL = ProfileStorageLayout.profilesRoot,
        authenticator: any ProfileAuthenticating = SystemProfileAuthenticator(),
        beforeLocalRestore: (@Sendable () async throws -> Void)? = nil
    ) {
        self.profilesRoot = profilesRoot
        registryURL = profilesRoot.appendingPathComponent("registry.json")
        self.authenticator = authenticator
        self.beforeLocalRestore = beforeLocalRestore
    }

    var selectedProfile: ProfileDescriptor? {
        profiles.first { $0.id == selectedProfileID }
    }

    func prepare() async {
        guard isPrepared == false else { return }
        isPrepared = true
        do {
            try FileManager.default.createDirectory(at: profilesRoot, withIntermediateDirectories: true)
            let registry = try loadRegistry()
            profiles = registry.profiles
            lastUsedProfileID = registry.lastUsedProfileID
            try resumePendingDeletion()
            await finishPendingDeletions()
            if profiles.isEmpty {
                let first = ProfileDescriptor(name: "个人", usesLegacyStorage: legacyStorageExists())
                profiles = [first]
                lastUsedProfileID = first.id
                try persistRegistry()
            }
            let availableProfiles = profiles.filter { $0.isDeleting == false }
            selectedProfileID = availableProfiles.contains(where: { $0.id == lastUsedProfileID })
                ? lastUsedProfileID
                : availableProfiles.first?.id

            if let selectedProfileID {
                // The application launch itself is not a profile-switch action.
                // Keep the existing runtime readiness barrier, but do not ask
                // for system authentication before restoring the last profile.
                await activate(profileID: selectedProfileID, reason: nil)
            }
        } catch {
            startupError = error.localizedDescription
        }
    }

    func unlockSelectedProfile() async {
        guard let selectedProfileID else { return }
        await activate(profileID: selectedProfileID, reason: "登录 EhViewer 空间")
    }

    func selectProfile(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        selectedProfileID = id
        runtime = nil
    }

    func switchProfile(to id: UUID) async {
        guard profiles.contains(where: { $0.id == id }) else {
            startupError = ProfileSessionError.profileNotFound.localizedDescription
            return
        }
        await closeRuntime()
        selectedProfileID = id
        await activate(profileID: id, reason: "切换 EhViewer 空间")
    }

    func createProfile(named rawName: String) async {
        do {
            let name = try normalizedName(rawName)
            let profile = ProfileDescriptor(name: name)
            profiles.append(profile)
            try persistRegistry()
            await closeRuntime()
            selectedProfileID = profile.id
            await activate(profileID: profile.id, reason: "进入新的 EhViewer 空间")
        } catch {
            startupError = error.localizedDescription
        }
    }

    func renameProfile(id: UUID, to rawName: String) {
        do {
            let name = try normalizedName(rawName)
            guard let index = profiles.firstIndex(where: { $0.id == id }) else {
                throw ProfileSessionError.profileNotFound
            }
            profiles[index].name = name
            if runtime?.descriptor.id == id {
                // The runtime's identity remains stable; the registry is the
                // display-name source for this session and subsequent starts.
            }
            try persistRegistry()
        } catch {
            startupError = error.localizedDescription
        }
    }

    /// This is called only after the UI's explicit second confirmation. It
    /// re-authenticates immediately before the destructive cleanup begins.
    func deleteProfile(id: UUID) async {
        do {
            #if os(macOS)
            guard !TranslationCoordinator.shared.hasActiveWork(profileID: id) else {
                throw EHError.storageFailed("请先停止该用户的翻译任务或环境准备，再删除用户。")
            }
            #endif
            guard profiles.count > 1 else { throw ProfileSessionError.lastProfile }
            guard let index = profiles.firstIndex(where: { $0.id == id }) else {
                throw ProfileSessionError.profileNotFound
            }
            guard try await authenticate(reason: "删除 EhViewer 空间及其本地数据") else {
                throw ProfileSessionError.authenticationCancelled
            }
            profiles[index].isDeleting = true
            try persistRegistry()
            if runtime?.descriptor.id == id { await closeRuntime() }
            try await cleanup(profile: profiles[index])
            profiles.remove(at: index)
            if selectedProfileID == id {
                selectedProfileID = profiles.sorted { $0.lastUsedAt > $1.lastUsedAt }.first?.id
            }
            if lastUsedProfileID == id { lastUsedProfileID = selectedProfileID }
            try persistRegistry()
        } catch {
            startupError = error.localizedDescription
        }
    }

    private func activate(profileID: UUID, reason: String?) async {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        let operationID = UUID()
        activationID = operationID
        let descriptor = profiles[index]
        isActivatingProfile = true
        defer {
            if activationID == operationID { isActivatingProfile = false }
        }
        do {
            if let reason {
                guard try await authenticate(reason: reason) else {
                    throw ProfileSessionError.authenticationCancelled
                }
            }
            guard activationID == operationID else { return }
            await migrateLegacySessionIfNeeded(for: descriptor)
            let newRuntime = try await ProfileRuntime(
                descriptor: descriptor, profilesRoot: profilesRoot, beforeLocalRestore: beforeLocalRestore
            )
            guard activationID == operationID,
                  let currentIndex = profiles.firstIndex(where: { $0.id == profileID }) else {
                await newRuntime.model.shutdown()
                return
            }
            // Publish the runtime as soon as construction has completed. Download restoration has its own loading state and
            // must not delay the first root view transaction.
            runtime = newRuntime
            profiles[currentIndex].lastUsedAt = Date()
            lastUsedProfileID = profileID
            try persistRegistry()
            selectedProfileID = profileID
            startupError = nil
        } catch {
            guard activationID == operationID else { return }
            await runtime?.model.shutdown()
            runtime = nil
            startupError = error.localizedDescription
        }
    }

    private func closeRuntime() async {
        activationID = UUID()
        guard let runtime else { return }
        await runtime.model.shutdown()
        self.runtime = nil
    }

    private func authenticate(reason: String) async throws -> Bool {
        isAuthenticating = true
        defer { isAuthenticating = false }
        return try await authenticator.authenticate(reason: reason)
    }

    private func loadRegistry() throws -> ProfileRegistryDocument {
        guard FileManager.default.fileExists(atPath: registryURL.path) else {
            return ProfileRegistryDocument(profiles: [], lastUsedProfileID: nil)
        }
        return try JSONDecoder().decode(ProfileRegistryDocument.self, from: Data(contentsOf: registryURL))
    }

    private func persistRegistry() throws {
        let document = ProfileRegistryDocument(profiles: profiles, lastUsedProfileID: lastUsedProfileID)
        let data = try JSONEncoder().encode(document)
        // `.atomic` writes a sibling temporary file and atomically replaces the
        // previous registry, so a crash retains one complete JSON document.
        try data.write(to: registryURL, options: .atomic)
    }

    private func resumePendingDeletion() throws {
        for profile in profiles where profile.isDeleting {
            do {
                try cleanupSynchronously(profile: profile)
            } catch {
                // Keep the marker; this profile must not masquerade as deleted.
                startupError = ProfileSessionError.cleanupFailed(error.localizedDescription).localizedDescription
            }
        }
        try persistRegistry()
    }

    private func finishPendingDeletions() async {
        for profile in profiles where profile.isDeleting {
            do {
                try cleanupSynchronously(profile: profile)
                try await SessionVault(service: ProfileRuntime.keychainServiceName(for: profile.id)).clear()
                profiles.removeAll { $0.id == profile.id }
                if lastUsedProfileID == profile.id { lastUsedProfileID = profiles.first?.id }
                if selectedProfileID == profile.id { selectedProfileID = profiles.first?.id }
                try persistRegistry()
            } catch {
                startupError = ProfileSessionError.cleanupFailed(error.localizedDescription).localizedDescription
            }
        }
    }

    private func cleanup(profile: ProfileDescriptor) async throws {
        try cleanupSynchronously(profile: profile)
        let vault = SessionVault(service: ProfileRuntime.keychainServiceName(for: profile.id))
        try await vault.clear()
    }

    private func cleanupSynchronously(profile: ProfileDescriptor) throws {
        let layout = profile.usesLegacyStorage
            ? ProfileStorageLayout.legacy(for: profile.id)
            : ProfileStorageLayout.isolated(for: profile.id, profilesRoot: profilesRoot)
        let fileManager = FileManager.default
        let targets: [URL]
        if profile.usesLegacyStorage {
            // These are the exact legacy locations adopted by the first
            // profile. Never recurse from Application Support or Caches.
            targets = [
                ModelContainerFactory.persistentStoreURL,
                DownloadFileStore.defaultRootURL,
                GalleryCacheStore.defaultRootURL,
                layout.imageCacheRoot,
                GalleryCoverLoader.defaultRootURL,
                layout.tagDatabaseURL,
                DeviceSyncIndexStore.defaultRootURL,
                layout.deviceSyncTransactionRoot
            ]
        } else {
            guard layout.root.path.hasPrefix(profilesRoot.path + "/") else {
                throw ProfileSessionError.cleanupFailed("空间路径不在受管理目录内。")
            }
            targets = [layout.root]
        }
        for target in targets where fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
        for target in targets where fileManager.fileExists(atPath: target.path) {
            throw ProfileSessionError.cleanupFailed("文件系统仍保留 \(target.lastPathComponent)。")
        }
        UserDefaults.standard.removePersistentDomain(forName: ProfileRuntime.defaultsSuiteName(for: profile.id))
    }

    private func normalizedName(_ rawName: String) throws -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false, name.count <= 40 else { throw ProfileSessionError.invalidName }
        return name
    }

    private func legacyStorageExists() -> Bool {
        FileManager.default.fileExists(atPath: ModelContainerFactory.persistentStoreURL.path)
            || FileManager.default.fileExists(atPath: DownloadFileStore.defaultRootURL.path)
            || FileManager.default.fileExists(atPath: GalleryCacheStore.defaultRootURL.path)
    }

    private func migrateLegacySessionIfNeeded(for profile: ProfileDescriptor) async {
        guard profile.usesLegacyStorage else { return }
        let legacy = SessionVault()
        let destination = SessionVault(service: ProfileRuntime.keychainServiceName(for: profile.id))
        do {
            let destinationDefaults = UserDefaults(suiteName: ProfileRuntime.defaultsSuiteName(for: profile.id))
            let legacyDefaults = UserDefaults.standard
            let keys = [
                "site", "readingSettings", "readerReadingMode", "downloadSortOrder",
                "downloadStatusFilter", "downloadLayoutMode", "downloadCategoryFilter",
                "tagTranslationImportLocale"
            ]
            for key in keys {
                if let value = legacyDefaults.object(forKey: key) {
                    destinationDefaults?.set(value, forKey: key)
                }
            }
            destinationDefaults?.set(true, forKey: "legacyMigrationComplete")
            for key in keys { legacyDefaults.removeObject(forKey: key) }
            if let cookie = try await legacy.loadCookieHeader() {
                try await destination.saveCookieHeader(cookie)
                try await legacy.clear()
            }
        } catch {
            startupError = "旧会话迁移未完成：\(error.localizedDescription)"
        }
    }
}

struct ProfileHostView: View {
    @Bindable var session: ProfileSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let runtime = session.runtime {
                RootView(initialRoute: runtime.model.selectedRoute ?? .local)
                    .id(runtime.descriptor.id)
                    .environment(runtime.model)
                    .environment(session)
                    .modelContainer(runtime.container)
                    .tint(AppTheme.accent)
                    .onOpenURL { runtime.model.handleIncomingURL($0) }
                    .transition(.opacity)
            } else {
                ProfileUnlockView(session: session)
                    .transition(.opacity)
            }
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.2),
            value: session.runtime != nil
        )
        .task { await session.prepare() }
    }
}

private struct ProfileUnlockView: View {
    @Bindable var session: ProfileSession
    @State private var showingProfiles = false

    var body: some View {
        VStack(spacing: 18) {
            if session.isPrepared {
                if session.isActivatingProfile {
                    ProgressView(session.isAuthenticating ? "正在验证…" : "正在加载空间…")
                        .accessibilityIdentifier("profile-activation-loading")
                } else {
                    Text(session.selectedProfile?.name ?? "EhViewer")
                        .font(.title2.weight(.semibold))
                    Text("使用 Face ID、Touch ID 或设备密码登录空间。")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("登录") { Task { await session.unlockSelectedProfile() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(session.isAuthenticating)
                        .accessibilityIdentifier("profile-unlock-action")
                    Button("切换空间") { showingProfiles = true }
                        .accessibilityIdentifier("profile-switch-action")
                }
            } else {
                ProgressView("正在加载空间…")
                    .accessibilityIdentifier("profile-loading")
            }
            if let error = session.startupError {
                Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
        }
        .padding()
        .sheet(isPresented: $showingProfiles) {
            ProfilePickerView(session: session, dismiss: { showingProfiles = false })
        }
    }
}

private struct ProfilePickerView: View {
    @Bindable var session: ProfileSession
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(session.profiles) { profile in
                        ProfilePickerRow(
                            profile: profile,
                            isCurrent: profile.id == session.runtime?.descriptor.id,
                            action: { select(profile) }
                        )
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("空间")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: dismiss)
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 440, idealWidth: 500, minHeight: 250, idealHeight: 340, maxHeight: 520)
#endif
    }

    private func select(_ profile: ProfileDescriptor) {
        Task {
            await session.switchProfile(to: profile.id)
            if session.runtime != nil {
                dismiss()
            }
        }
    }
}

private struct ProfilePickerRow: View {
    let profile: ProfileDescriptor
    let isCurrent: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var rowBackground: Color {
        if isCurrent {
            return AppTheme.accent.opacity(0.12)
        }
        if isHovered {
            return Color.primary.opacity(0.09)
        }
        return Color.primary.opacity(0.045)
    }

    private var rowBorder: Color {
        isCurrent ? AppTheme.accent.opacity(0.45) : Color.primary.opacity(0.08)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)

                    Label(
                        isCurrent ? "当前使用中" : "已锁定",
                        systemImage: isCurrent ? "checkmark.circle.fill" : "lock.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(isCurrent ? AppTheme.accent : Color.secondary)
                }

                Spacer(minLength: 12)

                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(rowBorder, lineWidth: 1)
        }
        .onHover { isHovered = $0 }
        .accessibilityValue(isCurrent ? "当前使用中" : "已锁定")
        .accessibilityHint("点击切换到此空间")
        .accessibilityIdentifier("profile-row-\(profile.id.uuidString)")
    }
}

private struct ProfileSummary: View {
    let profile: ProfileDescriptor
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(profile.name)
                .font(.body.weight(.medium))
            Text(isCurrent ? "已登录" : "已锁定")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct ProfileNameEditorRequest: Identifiable {
    enum Action {
        case create
        case rename(UUID)
    }

    let id = UUID()
    let title: String
    let initialName: String
    let action: Action
}

struct ProfileNameEditor: View {
    let request: ProfileNameEditorRequest
    let save: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(request: ProfileNameEditorRequest, save: @escaping (String) -> Void) {
        self.request = request
        self.save = save
        _name = State(initialValue: request.initialName)
    }

    var body: some View {
#if os(macOS)
        VStack(alignment: .leading, spacing: 16) {
            Text(request.title)
                .font(.headline)

            TextField("空间名称", text: $name)
                .accessibilityIdentifier("profile-name-field")

            HStack {
                Spacer()
                Button("取消", role: .cancel, action: dismiss.callAsFunction)
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    save(name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("profile-name-save-action")
            }
        }
        .padding(20)
        .frame(minWidth: 400, idealWidth: 420, minHeight: 160, idealHeight: 180)
#else
        NavigationStack {
            Form {
                TextField("空间名称", text: $name)
                    .accessibilityIdentifier("profile-name-field")
            }
            .navigationTitle(request.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save(name)
                        dismiss()
                    }
                    .accessibilityIdentifier("profile-name-save-action")
                }
            }
        }
#endif
    }
}

struct ProfileManagementSection: View {
    @Environment(ProfileSession.self) private var session
    @Binding var nameEditor: ProfileNameEditorRequest?
    @Binding var profilePendingDeletion: ProfileDescriptor?

    var body: some View {
        Section("空间") {
            ForEach(session.profiles) { profile in
                HStack(alignment: .center, spacing: 12) {
                    ProfileSummary(
                        profile: profile,
                        isCurrent: profile.id == session.runtime?.descriptor.id
                    )
                    Spacer(minLength: 4)
                    HStack(spacing: 6) {
                        Button("切换") {
                            Task { await session.switchProfile(to: profile.id) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(profile.id == session.runtime?.descriptor.id)
                        .accessibilityIdentifier("profile-switch-\(profile.id.uuidString)")

                        Button("重命名") {
                            nameEditor = ProfileNameEditorRequest(
                                title: "重命名空间",
                                initialName: profile.name,
                                action: .rename(profile.id)
                            )
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("profile-rename-\(profile.id.uuidString)")

                        Button("删除", role: .destructive) {
                            profilePendingDeletion = profile
                        }
                        .buttonStyle(.bordered)
                        .disabled(session.profiles.count <= 1)
                        .accessibilityIdentifier("profile-delete-\(profile.id.uuidString)")
                    }
                }
            }
            Button("新建空间", systemImage: "plus") {
                nameEditor = ProfileNameEditorRequest(
                    title: "新建空间",
                    initialName: "",
                    action: .create
                )
            }
            .accessibilityIdentifier("profile-create-action")
        }
    }
}
