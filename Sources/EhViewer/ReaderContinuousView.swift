import SwiftUI
import EHDomain

struct ReaderContinuousView: View {
    let descriptors: [GalleryPageDescriptor]
    let resolution: ImageResolution
    let resetToken: UUID
    let source: ReaderContentSource
    @Binding var position: ReaderPositionState
    @State private var zoom = ReaderContinuousZoomState()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(spacing: 10) {
                    ForEach(descriptors) { descriptor in
                        ReaderPage(
                            descriptor: descriptor,
                            resolution: resolution,
                            resetToken: resetToken,
                            source: source,
                            fitsViewport: false,
                            allowsZoom: false,
                            parentScrollAxis: .vertical,
                            pageTurnRequested: { _ in }
                        )
                        .id(descriptor.index)
                    }
                }
                .scrollTargetLayout()
                .containerRelativeFrame(.horizontal) { availableWidth, _ in
                    availableWidth * zoom.scale
                }
            }
            .scrollIndicators(.visible)
            .simultaneousGesture(magnificationGesture)
            .highPriorityGesture(doubleTapGesture)
            .overlay(alignment: .bottomTrailing) {
                if zoom.scale > ReaderContinuousZoomState.minimumScale + 0.001 {
                    Text("缩放 \(Int(zoom.scale * 100))%")
                        .font(.caption.monospacedDigit())
                        .padding(6)
                        .background(.thinMaterial, in: Capsule())
                        .padding(8)
                        .accessibilityHidden(true)
                }
            }
            .task {
                await Task.yield()
                proxy.scrollTo(position.page, anchor: .top)
            }
            .onChange(of: position.scrollRequestSequence) {
                guard let target = position.scrollTarget else { return }
                proxy.scrollTo(target, anchor: .top)
            }
            .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.15) { visiblePages in
                position.markVisiblePage(from: visiblePages, displayOrder: descriptors.map(\.index))
            }
            .onChange(of: resetToken) { zoom.reset() }
            .accessibilityHint("上下滚动连续阅读；双击或双指缩放整组页面")
        }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { zoom.magnificationChanged($0.magnification) }
            .onEnded { zoom.magnificationEnded($0.magnification) }
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation(.smooth(duration: 0.3)) { zoom.toggle() }
            }
    }
}
