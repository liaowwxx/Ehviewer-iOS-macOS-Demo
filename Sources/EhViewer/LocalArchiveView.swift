import SwiftUI
import UniformTypeIdentifiers
import EHDomain
import EHDownloads

struct LocalArchiveView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let document: LocalArchiveDocument

    var body: some View {
        Group {
            if document.imageEntries.isEmpty {
                ContentUnavailableView(
                    "归档中没有媒体文件",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("支持 ZIP、7z、RAR 中的常见图片、动图和视频格式。")
                )
            } else {
                List(document.imageEntries) { entry in
                    NavigationLink {
                        LocalArchiveReaderView(document: document, initialEntryID: entry.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "photo")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.path)
                                    .lineLimit(2)
                                    .foregroundStyle(.primary)
                                Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityLabel("打开 \(entry.path)")
                }
            }
        }
        .navigationTitle(document.url.lastPathComponent)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") {
                    model.closeLocalArchive()
                    dismiss()
                }
            }
        }
    }
}

private struct LocalArchiveReaderView: View {
    let document: LocalArchiveDocument
    let initialEntryID: String
    @State private var selectedEntryID: String

    init(document: LocalArchiveDocument, initialEntryID: String) {
        self.document = document
        self.initialEntryID = initialEntryID
        _selectedEntryID = State(initialValue: initialEntryID)
    }

    var body: some View {
        TabView(selection: $selectedEntryID) {
            ForEach(document.imageEntries) { entry in
                LocalArchiveImageView(document: document, entry: entry)
                    .tag(entry.id)
                    .accessibilityLabel("第 \((document.imageEntries.firstIndex(of: entry) ?? 0) + 1)/\(document.imageEntries.count) 页")
            }
        }
#if os(iOS)
        .tabViewStyle(.page(indexDisplayMode: .automatic))
#else
        .tabViewStyle(.automatic)
#endif
        .navigationTitle(document.url.lastPathComponent)
#if os(iOS)
        .toolbar(.hidden, for: .tabBar)
#endif
    }
}

struct LocalArchiveImageView: View {
    @Environment(AppModel.self) private var model
    let document: LocalArchiveDocument
    let entry: LocalArchiveEntry
    @State private var media: ReaderMediaView.Content?
    @State private var errorMessage: String?
    @State private var scale: CGFloat = 1
    @State private var loadToken = UUID()

    var body: some View {
        Group {
            if let media {
                ScrollView([.vertical, .horizontal]) {
                    ReaderMediaView(content: media, pageScaling: .fit, fitsViewport: false)
                        .scaleEffect(scale)
                        .gesture(
                            MagnifyGesture()
                                .onChanged { value in scale = min(max(value.magnification, 1), 4) }
                                .onEnded { _ in if scale < 1.05 { scale = 1 } }
                        )
                        .padding()
                }
            } else if let errorMessage {
                VStack(spacing: 12) {
                    ContentUnavailableView("媒体无法打开", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                    Button("重试", systemImage: "arrow.clockwise") { loadToken = UUID() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView("正在读取归档…")
            }
        }
        .task(id: "\(entry.id)-\(loadToken)") {
            do {
                let data = try await model.data(for: entry, in: document)
                media = try ReaderMediaView.Content.decode(data)
                errorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

extension LocalArchiveView {
    static var supportedContentTypes: [UTType] {
        ["public.zip-archive", "org.7-zip.7-zip", "com.rarlab.rar", "com.rarlab.cbr"].compactMap(UTType.init)
    }
}
