import SwiftUI
import EHDomain
import EHDownloads
import UniformTypeIdentifiers

struct GalleryTranslationSection: View {
    @Environment(AppModel.self) private var model
    let detail: GalleryDetail
    let job: DownloadJob?
    private var key: GalleryKey { detail.summary.key }
    @State private var edition = ReadingEdition.original
    @State private var archiving: GalleryTranslationManifest?
    @State private var showingImporter = false
    private var versions: [GalleryTranslationManifest] { model.translationLibrary.versions[key] ?? [] }
    private var selectedVersion: GalleryTranslationManifest? {
        guard case .translated(let id) = edition else { return nil }
        return versions.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if versions.isEmpty {
                    versionLabel
                } else {
                    Menu {
                        Picker("阅读版本", selection: $edition) {
                            Text("原件").tag(ReadingEdition.original)
                            ForEach(versions) { version in
                                Text("译件 · \(version.targetLanguage) · \(Date(timeIntervalSince1970: version.createdAt).formatted(date: .numeric, time: .shortened))")
                                    .tag(ReadingEdition.translated(versionID: version.versionID))
                            }
                        }
                    } label: {
                        versionLabel
                    }
                    .accessibilityIdentifier("translation-edition-picker")
                }

                Divider().frame(height: 28)
                Menu("译件管理", systemImage: "ellipsis") {
                    Button("导入译件目录", systemImage: "square.and.arrow.down") { showingImporter = true }
                    if let selectedVersion {
                        Divider()
                        Button("移除译件", systemImage: "archivebox", role: .destructive) { archiving = selectedVersion }
                            .disabled(model.deviceSync.hasActiveSession)
                    }
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(AppTheme.accent)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("translation-management-menu")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
#if os(macOS)
            HStack {
                Button("发送到翻译应用", systemImage: "character.book.closed") {
                    guard let job else { return }
                    model.localTranslation.submit(job: job, downloads: model.downloadFiles)
                }
                .disabled(job?.state != .completed || model.localTranslation.isSubmitting || !model.localTranslation.isConnected)
                .accessibilityIdentifier("send-to-translation-companion")
                if model.localTranslation.isConnected {
                    Label("已自动连接翻译应用", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("translation-companion-connected")
                } else {
                    Text("打开本机翻译应用后会自动连接。")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("translation-companion-waiting")
                }
            }
            Text(model.localTranslation.statuses[key] ?? String(localized: "仅发送完整下载的原图；配置和开始翻译由独立应用控制。"))
                .font(.caption).foregroundStyle(.secondary)
            if let error = model.localTranslation.error {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
#endif
            if let error = model.translationLibrary.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .task {
            await model.translationLibrary.refresh()
            edition = model.translationLibrary.edition(for: key)
        }
        .onChange(of: model.translationLibrary.edition(for: key)) { _, value in edition = value }
        .onChange(of: edition) { _, value in model.translationLibrary.select(value, for: key) }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.folder]) { result in
            Task {
                do {
                    let directory = try result.get()
                    let scoped = directory.startAccessingSecurityScopedResource()
                    defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
                    let manifestURL = directory.appendingPathComponent("manifest.json")
                    guard let size = try manifestURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 4 * 1024 * 1024 else { throw EHError.invalidResponse }
                    let manifest = try JSONDecoder().decode(GalleryTranslationManifest.self, from: Data(contentsOf: manifestURL))
                    guard manifest.gallery.key == key else { throw EHError.parsingFailed(String(localized: "译件与当前画廊不匹配。")) }
                    try await model.translationLibrary.files.importVersion(manifest, pagesDirectory: directory.appendingPathComponent("pages"))
                    if let record = try await model.persistence.downloadedTransferRecord(for: key) {
                        try await model.translationLibrary.files.storeGalleryMetadata(record)
                    } else {
                        let record = try GalleryTransferRecord(stable: StableGalleryMetadataSnapshot(detail: detail, sourceSite: model.site),
                                                               dynamic: DownloadedGalleryDynamicSnapshot(detail: detail))
                        try await model.translationLibrary.files.storeGalleryMetadata(record)
                    }
                    await model.translationLibrary.refresh()
                } catch { model.translationLibrary.error = error.localizedDescription }
            }
        }
        .confirmationDialog("移除译件？原件和其他译件不受影响，文件将归档保存。", isPresented: Binding(
            get: { archiving != nil }, set: { if !$0 { archiving = nil } }
        )) {
            Button("移除译件", role: .destructive) {
                guard let version = archiving else { return }
                archiving = nil
                Task { await model.translationLibrary.archive(version); edition = model.translationLibrary.edition(for: key) }
            }
        }
    }

    private var versionLabel: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("阅读版本").font(.caption).foregroundStyle(.secondary)
                if let selectedVersion {
                    Text("译件 · \(selectedVersion.targetLanguage)")
                } else {
                    Text("原件")
                }
            }
            .foregroundStyle(.primary)
            Spacer(minLength: 0)
            if !versions.isEmpty {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}
