import SwiftUI
import EHDomain

#if os(iOS)
import UIKit
#endif

struct ReaderVerticalPagedView: View {
    @Environment(AppModel.self) private var model
    let descriptors: [GalleryPageDescriptor]
    let resolution: ImageResolution
    let resetToken: UUID
    let pageScaling: ReaderPageScaling
    let source: ReaderContentSource
    @Binding var position: ReaderPositionState

    var body: some View {
        #if os(iOS)
        ReaderPagedControllerRepresentable(
            model: model,
            descriptors: descriptors,
            resolution: resolution,
            resetToken: resetToken,
            readingDirection: .leftToRight,
            navigationOrientation: .vertical,
            pageScaling: pageScaling,
            source: source,
            position: $position
        )
        .id("reader-vertical-paging")
        #else
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(descriptors) { descriptor in
                        ReaderPage(
                            descriptor: descriptor,
                            resolution: resolution,
                            source: source,
                            pageScaling: pageScaling,
                            fitsViewport: true
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
                proxy.scrollTo(target, anchor: .center)
            }
            .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.55) { visiblePages in
                position.markVisiblePage(from: visiblePages, displayOrder: descriptors.map(\.index))
            }
        }
        .accessibilityHint("上下翻页阅读")
        #endif
    }
}
