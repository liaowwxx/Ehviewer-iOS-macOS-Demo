import SwiftUI
import EHDomain

struct ReaderPagedView: View {
    let descriptors: [GalleryPageDescriptor]
    let resolution: ImageResolution
    let resetToken: UUID
    let readingMode: ReadingMode
    let source: ReaderContentSource
    @Binding var position: ReaderPositionState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(displayDescriptors) { descriptor in
                        ReaderPage(
                            descriptor: descriptor,
                            resolution: resolution,
                            resetToken: resetToken,
                            source: source,
                            fitsViewport: true,
                            allowsZoom: true,
                            parentScrollAxis: .horizontal,
                            pageTurnRequested: { displayDelta in
                                requestAdjacentPage(from: descriptor, displayDelta: displayDelta)
                            }
                        )
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(descriptor.index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.visible)
            .task {
                await Task.yield()
                proxy.scrollTo(position.page, anchor: .center)
            }
            .onChange(of: position.scrollRequestSequence) {
                guard let target = position.scrollTarget else { return }
                withAnimation(.smooth(duration: 0.25)) {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
            .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.55) { visiblePages in
                position.markVisiblePage(from: visiblePages, displayOrder: displayDescriptors.map(\.index))
            }
            .accessibilityHint("左右滑动逐页阅读；双击或双指缩放当前页")
        }
    }

    private var displayDescriptors: [GalleryPageDescriptor] {
        readingMode == .rightToLeft ? Array(descriptors.reversed()) : descriptors
    }

    private func requestAdjacentPage(from descriptor: GalleryPageDescriptor, displayDelta: Int) {
        guard let currentOffset = displayDescriptors.firstIndex(where: { $0.index == descriptor.index }) else { return }
        let targetOffset = currentOffset + displayDelta
        guard displayDescriptors.indices.contains(targetOffset) else { return }
        position.requestPage(displayDescriptors[targetOffset].index, pageCount: descriptors.count)
    }
}
