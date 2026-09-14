/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#if os(macOS)
import AppKit
import SwiftUI

/// A native macOS scroll container for reader media.
///
/// `scaleEffect` only changes a SwiftUI view's rendered output. It does not
/// expand the layout region that a surrounding `ScrollView` can scroll. An
/// `NSScrollView` owns the document view's scrollable geometry and provides
/// AppKit's native trackpad magnification and scrolling behavior together.
struct MacReaderMediaScrollView: NSViewRepresentable {
    let content: ReaderMediaView.Content
    let fitsViewport: Bool
    let resetToken: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(resetToken: resetToken)
    }

    func makeNSView(context: Context) -> MacReaderZoomScrollView {
        let scrollView = MacReaderZoomScrollView()
        scrollView.mediaAspectRatio = content.aspectRatio
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 1
        scrollView.maxMagnification = 4
        scrollView.magnification = 1
        scrollView.usesPredominantAxisScrolling = false
        scrollView.scrollsDynamically = true
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none

        let clipView = MacReaderClipView(frame: scrollView.contentView.frame)
        clipView.drawsBackground = false
        scrollView.contentView = clipView

        let documentView = MacReaderDocumentView(frame: .zero)

        let hostingView = NSHostingView(rootView: AnyView(mediaView))
        hostingView.frame = documentView.bounds
        hostingView.autoresizingMask = [.width, .height]
        documentView.addSubview(hostingView)
        scrollView.documentView = documentView

        context.coordinator.hostingView = hostingView
        context.coordinator.documentView = documentView
        return scrollView
    }

    func updateNSView(_ scrollView: MacReaderZoomScrollView, context: Context) {
        scrollView.mediaAspectRatio = content.aspectRatio
        context.coordinator.hostingView?.rootView = AnyView(mediaView)

        if context.coordinator.resetToken != resetToken {
            context.coordinator.resetToken = resetToken
            context.coordinator.reset(scrollView)
        }

        scrollView.needsLayout = true
    }

    private var mediaView: some View {
        ReaderMediaView(content: content, fitsViewport: fitsViewport)
    }

    @MainActor
    final class Coordinator {
        var resetToken: UUID
        weak var documentView: NSView?
        weak var hostingView: NSHostingView<AnyView>?

        init(resetToken: UUID) {
            self.resetToken = resetToken
        }

        func reset(_ scrollView: MacReaderZoomScrollView) {
            guard let documentView else { return }

            let center = NSPoint(x: documentView.bounds.midX, y: documentView.bounds.midY)
            scrollView.setMagnification(1, centeredAt: center)
            scrollView.centerDocumentIfNeeded()
        }
    }
}

/// Keeps the unscaled document view equal to the actual fitted media size.
/// Once magnified, `NSScrollView` owns the larger scrollable region.
final class MacReaderZoomScrollView: NSScrollView, NSGestureRecognizerDelegate {
    var mediaAspectRatio: CGFloat = 1

    private lazy var panGestureRecognizer = NSPanGestureRecognizer(
        target: self,
        action: #selector(handlePan(_:))
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configurePanGesture()
        observeMagnificationEnd()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configurePanGesture()
        observeMagnificationEnd()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layout() {
        super.layout()

        guard magnification <= minMagnification + 0.001,
              let documentView = documentView as? MacReaderDocumentView,
              contentView.bounds.width > 0,
              contentView.bounds.height > 0 else {
            return
        }

        let fittedSize = fittedMediaSize(for: contentView.bounds.size)
        if documentView.frame.size != fittedSize {
            documentView.setFrameSize(fittedSize)
        }

        centerDocumentIfNeeded()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
        gestureRecognizer === panGestureRecognizer && magnification > minMagnification + 0.001
    }

    @objc
    private func handlePan(_ gestureRecognizer: NSPanGestureRecognizer) {
        guard magnification > minMagnification + 0.001 else { return }

        let translation = gestureRecognizer.translation(in: self)
        guard translation != .zero else { return }

        let scale = max(magnification, 1)
        let proposedBounds = contentView.bounds.offsetBy(
            dx: -translation.x / scale,
            dy: -translation.y / scale
        )
        let constrainedBounds = contentView.constrainBoundsRect(proposedBounds)
        contentView.scroll(to: constrainedBounds.origin)
        reflectScrolledClipView(contentView)
        gestureRecognizer.setTranslation(.zero, in: self)
    }

    override func scrollWheel(with event: NSEvent) {
        guard magnification > minMagnification + 0.001 else {
            if let ancestorScrollView {
                ancestorScrollView.scrollWheel(with: event)
            } else {
                super.scrollWheel(with: event)
            }
            return
        }

        // Consume scroll events while zoomed. If we call super at an edge,
        // AppKit can transfer the remaining event to the outer paging scroll
        // view, exposing or switching to the adjacent page.
        let horizontalDelta = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaX
            : event.scrollingDeltaX * horizontalLineScroll
        let verticalDelta = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY
            : event.scrollingDeltaY * verticalLineScroll
        let scale = max(magnification, 1)
        let proposedBounds = contentView.bounds.offsetBy(
            dx: -horizontalDelta / scale,
            dy: -verticalDelta / scale
        )
        let constrainedBounds = contentView.constrainBoundsRect(proposedBounds)
        contentView.scroll(to: constrainedBounds.origin)
        reflectScrolledClipView(contentView)
    }

    func centerDocumentIfNeeded() {
        let constrainedBounds = contentView.constrainBoundsRect(contentView.bounds)
        guard constrainedBounds.origin != contentView.bounds.origin else { return }
        contentView.scroll(to: constrainedBounds.origin)
        reflectScrolledClipView(contentView)
    }

    @objc
    private func handleMagnificationEnd(_ notification: Notification) {
        guard notification.object as AnyObject? === self else { return }
        guard magnification <= minMagnification + 0.001 else { return }

        if magnification != minMagnification {
            magnification = minMagnification
        }
        centerDocumentIfNeeded()
    }

    private var ancestorScrollView: NSScrollView? {
        var ancestor = superview
        while let view = ancestor {
            if let scrollView = view as? NSScrollView, scrollView !== self {
                return scrollView
            }
            ancestor = view.superview
        }
        return nil
    }

    private func fittedMediaSize(for viewportSize: NSSize) -> NSSize {
        let aspectRatio = max(mediaAspectRatio, .leastNonzeroMagnitude)
        let width = min(viewportSize.width, viewportSize.height * aspectRatio)
        return NSSize(width: width, height: width / aspectRatio)
    }

    private func configurePanGesture() {
        panGestureRecognizer.delegate = self
        panGestureRecognizer.buttonMask = 1
        addGestureRecognizer(panGestureRecognizer)
    }

    private func observeMagnificationEnd() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMagnificationEnd(_:)),
            name: NSScrollView.didEndLiveMagnifyNotification,
            object: self
        )
    }
}

final class MacReaderDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class MacReaderClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrainedBounds = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return constrainedBounds }

        if documentView.frame.width < constrainedBounds.width {
            constrainedBounds.origin.x = documentView.frame.midX - constrainedBounds.width / 2
        }
        if documentView.frame.height < constrainedBounds.height {
            constrainedBounds.origin.y = documentView.frame.midY - constrainedBounds.height / 2
        }
        return constrainedBounds
    }
}
#endif
