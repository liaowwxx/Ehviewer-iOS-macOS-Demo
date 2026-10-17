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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("漫画翻译").font(.headline)
            Button("导入译件目录", systemImage: "square.and.arrow.down") { showingImporter = true }
            if let versions = model.translationLibrary.versions[key], !versions.isEmpty {
                Picker("阅读版本", selection: $edition) {
                    Text("原件").tag(ReadingEdition.original)
                    ForEach(versions) { version in
                        Text("译件 · \(version.targetLanguage) · \(Date(timeIntervalSince1970: version.createdAt).formatted(date: .numeric, time: .shortened))")
                            .tag(ReadingEdition.translated(versionID: version.versionID))
                    }
                }
                .accessibilityIdentifier("translation-edition-picker")
                if case .translated(let id) = edition,
                   let version = versions.first(where: { $0.versionID == id }) {
                    Text("\(version.pages.count) 页 · \(version.versionID.uuidString.prefix(8))")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("移除译件", systemImage: "archivebox", role: .destructive) { archiving = version }
                        .disabled(model.deviceSync.hasActiveSession)
                }
            }
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
}
