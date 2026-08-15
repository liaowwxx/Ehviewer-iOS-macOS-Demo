#if os(iOS)
import SwiftUI
import EHDomain

struct ReaderProgressControl: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let page: Int
    let pageCount: Int
    let descriptors: [GalleryPageDescriptor]
    let source: ReaderContentSource
    let requestPage: (Int) -> Void
    let onSeekEnded: () -> Void
    @State private var sliderValue: Double
    @State private var isPreviewExpanded = false

    init(
        page: Int,
        pageCount: Int,
        descriptors: [GalleryPageDescriptor],
        source: ReaderContentSource,
        requestPage: @escaping (Int) -> Void,
        onSeekEnded: @escaping () -> Void
    ) {
        self.page = page
        self.pageCount = pageCount
        self.descriptors = descriptors
        self.source = source
        self.requestPage = requestPage
        self.onSeekEnded = onSeekEnded
        let clampedPage = min(max(page, 0), max(pageCount - 1, 0))
        _sliderValue = State(initialValue: Double(clampedPage))
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Text(pageText)
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 76, alignment: .leading)

                Slider(
                    value: $sliderValue,
                    in: sliderRange,
                    step: 1,
                    onEditingChanged: handleEditingChanged
                )
                .accessibilityLabel("阅读进度")
                .accessibilityValue(Text(pageText))
                .disabled(pageCount <= 1)

                if source == .download {
                    Button(
                        isPreviewExpanded ? "收起预览" : "展开预览",
                        systemImage: isPreviewExpanded ? "chevron.down" : "chevron.up",
                        action: togglePreview
                    )
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel(isPreviewExpanded ? "收起预览" : "展开预览")
                    .accessibilityValue(isPreviewExpanded ? "已展开" : "已收起")
                    .accessibilityIdentifier("reader-preview-toggle")
                }
            }

            if isPreviewExpanded, source == .download, pageCount > 0 {
                ReaderThumbnailStrip(
                    descriptors: descriptors,
                    targetPage: currentPage,
                    requestPage: requestPage,
                    onSeekEnded: onSeekEnded
                )
                .transition(
                    accessibilityReduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity)
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .accessibilityIdentifier("reader-progress-control")
        .animation(
            accessibilityReduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.25),
            value: isPreviewExpanded
        )
        .onChange(of: sliderValue) { _, newValue in
            let target = normalizedPage(from: newValue)
            guard target != currentPage else { return }
            requestPage(target)
        }
        .onChange(of: page) { _, newPage in
            synchronizeSlider(to: newPage)
        }
        .onChange(of: pageCount) { _, _ in
            synchronizeSlider(to: page)
        }
    }

    private var currentPage: Int {
        min(max(page, 0), max(pageCount - 1, 0))
    }

    private var pageText: String {
        guard pageCount > 0 else { return "暂无页面" }
        return "第 \(currentPage + 1)/\(pageCount) 页"
    }

    private var sliderRange: ClosedRange<Double> {
        0...Double(max(pageCount - 1, 1))
    }

    private func normalizedPage(from value: Double) -> Int {
        min(max(Int(value.rounded()), 0), max(pageCount - 1, 0))
    }

    private func synchronizeSlider(to page: Int) {
        let clampedPage = min(max(page, 0), max(pageCount - 1, 0))
        let value = Double(clampedPage)
        if sliderValue != value {
            sliderValue = value
        }
    }

    private func handleEditingChanged(_ editing: Bool) {
        if editing == false {
            onSeekEnded()
        }
    }

    private func togglePreview() {
        isPreviewExpanded.toggle()
    }
}
#endif
