#if os(iOS)
import SwiftUI
import EHDomain

struct ReaderThumbnailView: View {
    @Environment(AppModel.self) private var model
    let descriptor: GalleryPageDescriptor
    let isSelected: Bool
    @State private var thumbnail: Image?
    @State private var isUnavailable = false

    var body: some View {
        VStack(spacing: 2) {
            Group {
                if let thumbnail {
                    thumbnail
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: isUnavailable ? "photo.badge.exclamationmark" : "photo")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 76, height: 96)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            }

            Text("\(descriptor.index + 1)")
                .font(.caption2.monospacedDigit())
                .fontWeight(isSelected ? .bold : .regular)
        }
        .frame(width: 82)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(descriptor.index + 1) 页")
        .accessibilityValue(isSelected ? "当前页" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .task(id: descriptor.id) {
            await loadThumbnail()
        }
        .onDisappear {
            thumbnail = nil
        }
    }

    private func loadThumbnail() async {
        thumbnail = nil
        isUnavailable = false

        if let image = await ReaderThumbnailLoader.shared.cachedThumbnail(for: descriptor.id) {
            guard Task.isCancelled == false else { return }
            thumbnail = Image(decorative: image, scale: 1, orientation: .up)
            return
        }
        guard let data = await model.downloadedPageDataIfAvailable(for: descriptor) else {
            isUnavailable = true
            return
        }
        guard let image = await ReaderThumbnailLoader.shared.thumbnail(
            for: descriptor.id,
            data: data
        ) else {
            isUnavailable = true
            return
        }
        guard Task.isCancelled == false else { return }
        thumbnail = Image(decorative: image, scale: 1, orientation: .up)
    }
}
#endif
