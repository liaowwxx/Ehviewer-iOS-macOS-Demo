#if os(iOS)
import SwiftUI
import EHDomain

struct ReaderThumbnailStrip: View {
    let descriptors: [GalleryPageDescriptor]
    let targetPage: Int
    let requestPage: (Int) -> Void
    let onSeekEnded: () -> Void
    @State private var scrollPosition: Int?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(descriptors) { descriptor in
                    Button {
                        requestPage(descriptor.index)
                        onSeekEnded()
                    } label: {
                        ReaderThumbnailView(
                            descriptor: descriptor,
                            isSelected: descriptor.index == targetPage
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("选择后跳转到此页")
                    .id(descriptor.index)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 12)
        }
        .scrollPosition(id: $scrollPosition, anchor: .center)
        .onAppear {
            synchronizeScrollPosition()
        }
        .onChange(of: targetPage) { _, _ in
            synchronizeScrollPosition()
        }
        .frame(height: 116)
        .accessibilityLabel("页面预览")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reader-thumbnail-strip")
    }

    private func synchronizeScrollPosition() {
        scrollPosition = targetPage
    }
}
#endif
