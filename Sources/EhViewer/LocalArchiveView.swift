import SwiftUI
import ImageIO
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
                    "归档中没有图片",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("支持 ZIP、7z、RAR 中的常见图片格式。")
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
    }
}

struct LocalArchiveImageView: View {
    @Environment(AppModel.self) private var model
    let document: LocalArchiveDocument
    let entry: LocalArchiveEntry
    @State private var image: Image?
    @State private var errorMessage: String?
    @State private var scale: CGFloat = 1
    @State private var loadToken = UUID()

    var body: some View {
        Group {
            if let image {
                ScrollView([.vertical, .horizontal]) {
                    image
                        .resizable()
                        .scaledToFit()
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
                    ContentUnavailableView("图片无法打开", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
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
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    throw EHError.parsingFailed("图片数据无效")
                }
                image = Image(decorative: cgImage, scale: 1, orientation: .up)
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
