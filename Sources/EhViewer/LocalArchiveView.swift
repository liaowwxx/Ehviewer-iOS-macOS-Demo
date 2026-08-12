import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import EHDomain
import EHDownloads

struct LocalArchiveView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let document: LocalArchiveDocument
    @State private var selectedEntry: LocalArchiveEntry?

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
                    Button {
                        selectedEntry = entry
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
                    .buttonStyle(.plain)
                    .accessibilityLabel("打开 (entry.path)")
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
        .sheet(item: $selectedEntry) { entry in
            NavigationStack {
                LocalArchiveImageView(document: document, entry: entry)
                    .navigationTitle(entry.path)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { selectedEntry = nil }
                        }
                    }
            }
        }
    }
}

struct LocalArchiveImageView: View {
    @Environment(AppModel.self) private var model
    let document: LocalArchiveDocument
    let entry: LocalArchiveEntry
    @State private var image: Image?
    @State private var errorMessage: String?
    @State private var scale: CGFloat = 1

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
                ContentUnavailableView("图片无法打开", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                ProgressView("正在读取归档…")
            }
        }
        .task(id: entry.id) {
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
