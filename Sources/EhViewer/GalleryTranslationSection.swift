import SwiftUI
import EHDomain
import EHDownloads

struct GalleryTranslationSection: View {
    @Environment(AppModel.self) private var model
    let detail: GalleryDetail
    let job: DownloadJob?
    private var key: GalleryKey { detail.summary.key }
    @State private var archiving: GalleryTranslationManifest?
    @State private var isArchiving = false
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif
    private var versions: [GalleryTranslationManifest] { model.translationLibrary.versions[key] ?? [] }
    private var edition: ReadingEdition { model.translationLibrary.edition(for: key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !versions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("阅读版本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                    editionRow(.original)
                    ForEach(versions) { version in
                        Divider().padding(.leading, 14)
                        editionRow(.translated(versionID: version.versionID), version: version)
                    }
                }
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
#if os(macOS)
            if job?.state == .completed {
                HStack {
                    Button("在翻译工作台中打开", systemImage: "character.book.closed") {
                        guard let job else { return }
                        openWindow(id: "translation", value: model.nativeTranslationProfileID)
                        Task { await model.nativeTranslation.add([job], downloads: model.downloadFiles) }
                    }
                    .disabled(job?.state != .completed || model.nativeTranslation.isAdding)
                    .accessibilityIdentifier("send-to-translation-companion")
                }
                Text("仅添加完整下载的原图；在独立翻译窗口中配置并手动开始。")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = model.nativeTranslation.error {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }
#endif
            if let error = model.translationLibrary.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .task {
            await model.translationLibrary.refresh()
        }
        .confirmationDialog("移除译件？原件和其他译件不受影响，文件将归档保存。", isPresented: Binding(
            get: { archiving != nil }, set: { if !$0 { archiving = nil } }
        )) {
            Button("移除译件", role: .destructive) {
                guard let version = archiving else { return }
                archiving = nil
                isArchiving = true
                Task {
                    defer { isArchiving = false }
                    await model.translationLibrary.archive(version)
                }
            }
        }
    }

    private func editionRow(_ value: ReadingEdition, version: GalleryTranslationManifest? = nil) -> some View {
        let isSelected = edition == value
        let identifier = version?.id.uuidString.lowercased() ?? "original"
        return HStack(spacing: 0) {
            Button {
                model.translationLibrary.select(value, for: key)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? AppTheme.accent : .secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        if let version {
                            Text("译件 · \(version.targetLanguage)")
                            Text(Date(timeIntervalSince1970: version.createdAt).formatted(date: .numeric, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("原件")
                        }
                    }
                    .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("translation-edition-\(identifier)")

            if let version {
                Button(role: .destructive) { archiving = version } label: {
                    Label("移除译件", systemImage: "trash")
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(model.deviceSync.hasActiveSession || isArchiving)
                .accessibilityValue(version.targetLanguage)
                .accessibilityIdentifier("translation-delete-\(identifier)")
                .padding(.trailing, 6)
            }
        }
        .background(isSelected ? AppTheme.accent.opacity(0.08) : .clear)
    }
}
