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

import SwiftUI
import EHDomain

#if os(iOS)
import UIKit
#endif

struct ReaderPagedView: View {
    @Environment(AppModel.self) private var model
    let descriptors: [GalleryPageDescriptor]
    let resolution: ImageResolution
    let resetToken: UUID
    let readingDirection: ReadingDirection
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
            readingDirection: readingDirection,
            navigationOrientation: .horizontal,
            pageScaling: pageScaling,
            source: source,
            position: $position
        )
        #else
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(displayDescriptors) { descriptor in
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
        #endif
    }

    private var displayDescriptors: [GalleryPageDescriptor] {
        readingDirection == .rightToLeft ? Array(descriptors.reversed()) : descriptors
    }
}

#if os(iOS)
struct ReaderPagedControllerRepresentable: UIViewControllerRepresentable {
    let model: AppModel
    let descriptors: [GalleryPageDescriptor]
    let resolution: ImageResolution
    let resetToken: UUID
    let readingDirection: ReadingDirection
    let navigationOrientation: UIPageViewController.NavigationOrientation
    let pageScaling: ReaderPageScaling
    let source: ReaderContentSource
    @Binding var position: ReaderPositionState

    func makeCoordinator() -> Coordinator {
        Coordinator(position: $position)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        context.coordinator.makeController(
            model: model,
            descriptors: descriptors,
            resolution: resolution,
            resetToken: resetToken,
            readingDirection: readingDirection,
            navigationOrientation: navigationOrientation,
            pageScaling: pageScaling,
            source: source
        )
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.update(
            controller: controller,
            model: model,
            descriptors: descriptors,
            resolution: resolution,
            resetToken: resetToken,
            readingDirection: readingDirection,
            navigationOrientation: navigationOrientation,
            pageScaling: pageScaling,
            source: source,
            position: position
        )
    }

    @MainActor
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        private var position: Binding<ReaderPositionState>
        private weak var controller: UIPageViewController?
        private var model: AppModel?
        private var descriptors: [GalleryPageDescriptor] = []
        private var resolution: ImageResolution = .preview
        private var readingDirection: ReadingDirection = .rightToLeft
        private var navigationOrientation: UIPageViewController.NavigationOrientation = .horizontal
        private var pageScaling: ReaderPageScaling = .fit
        private var source: ReaderContentSource = .remote
        private var resetToken: UUID?
        private var lastScrollRequestSequence = -1
        private var pages: [Int: ReaderNativePageViewController] = [:]

        init(position: Binding<ReaderPositionState>) {
            self.position = position
        }

        func makeController(
            model: AppModel,
            descriptors: [GalleryPageDescriptor],
            resolution: ImageResolution,
            resetToken: UUID,
            readingDirection: ReadingDirection,
            navigationOrientation: UIPageViewController.NavigationOrientation,
            pageScaling: ReaderPageScaling,
            source: ReaderContentSource
        ) -> UIPageViewController {
            self.model = model
            self.descriptors = descriptors
            self.resolution = resolution
            self.resetToken = resetToken
            self.readingDirection = readingDirection
            self.navigationOrientation = navigationOrientation
            self.pageScaling = pageScaling
            self.source = source
            lastScrollRequestSequence = position.wrappedValue.scrollRequestSequence

            let controller = UIPageViewController(
                transitionStyle: .scroll,
                navigationOrientation: navigationOrientation
            )
            controller.dataSource = self
            controller.delegate = self
            self.controller = controller

            let initial = pageController(for: position.wrappedValue.page)
            controller.setViewControllers([initial], direction: .forward, animated: false)
            return controller
        }

        func update(
            controller: UIPageViewController,
            model: AppModel,
            descriptors: [GalleryPageDescriptor],
            resolution: ImageResolution,
            resetToken: UUID,
            readingDirection: ReadingDirection,
            navigationOrientation: UIPageViewController.NavigationOrientation,
            pageScaling: ReaderPageScaling,
            source: ReaderContentSource,
            position: ReaderPositionState
        ) {
            let descriptorsChanged = self.descriptors.map(\.id) != descriptors.map(\.id)
            let directionChanged = self.readingDirection != readingDirection
            let orientationChanged = self.navigationOrientation != navigationOrientation
            self.model = model
            self.descriptors = descriptors
            self.resolution = resolution
            self.readingDirection = readingDirection
            self.navigationOrientation = navigationOrientation
            self.pageScaling = pageScaling
            self.source = source

            if descriptorsChanged || directionChanged || orientationChanged {
                pages = [:]
                let current = pageController(for: position.page)
                controller.setViewControllers([current], direction: .forward, animated: false)
            }

            if self.resetToken != resetToken {
                self.resetToken = resetToken
                pages.values.forEach { $0.resetZoom(animated: false) }
            }

            if lastScrollRequestSequence != position.scrollRequestSequence {
                lastScrollRequestSequence = position.scrollRequestSequence
                let target = position.scrollTarget ?? position.page
                let direction = navigationDirection(to: target, from: currentPageIndex ?? position.page)
                let targetController = pageController(for: target)
                controller.setViewControllers(
                    [targetController],
                    direction: direction,
                    animated: position.scrollRequestAnimated
                )
            }
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            adjacentPage(from: viewController, offset: -1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            adjacentPage(from: viewController, offset: 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard finished, completed, let currentPageIndex else { return }
            position.wrappedValue.markVisiblePage(
                from: [currentPageIndex],
                displayOrder: descriptors.map(\.index)
            )
            prunePages(around: currentPageIndex)
        }

        private var orderedDescriptors: [GalleryPageDescriptor] {
            navigationOrientation == .horizontal && readingDirection == .rightToLeft
                ? Array(descriptors.reversed())
                : descriptors
        }

        private var currentPageIndex: Int? {
            controller?.viewControllers?.first
                .flatMap { ($0 as? ReaderNativePageViewController)?.pageIndex }
        }

        private func adjacentPage(from viewController: UIViewController, offset: Int) -> UIViewController? {
            guard let page = (viewController as? ReaderNativePageViewController)?.pageIndex,
                  let currentOffset = orderedDescriptors.firstIndex(where: { $0.index == page }) else {
                return nil
            }
            let targetOffset = currentOffset + offset
            guard orderedDescriptors.indices.contains(targetOffset) else { return nil }
            return pageController(for: orderedDescriptors[targetOffset].index)
        }

        private func pageController(for pageIndex: Int) -> ReaderNativePageViewController {
            if let existing = pages[pageIndex] {
                return existing
            }
            guard let descriptor = descriptors.first(where: { $0.index == pageIndex }),
                  let model else { preconditionFailure("Reader page is unavailable") }
            let page = ReaderNativePageViewController(
                descriptor: descriptor,
                resolution: resolution,
                source: source,
                pageScaling: pageScaling,
                navigationOrientation: navigationOrientation,
                model: model
            )
            pages[pageIndex] = page
            prunePages(around: pageIndex)
            return page
        }

        private func prunePages(around pageIndex: Int) {
            let retainedIndexes = Set(
                [pageIndex - 1, pageIndex, pageIndex + 1]
                    .filter { candidate in descriptors.contains(where: { descriptor in descriptor.index == candidate }) }
            )
            pages = pages.filter { retainedIndexes.contains($0.key) }
        }

        private func navigationDirection(
            to target: Int,
            from current: Int
        ) -> UIPageViewController.NavigationDirection {
            guard let targetOffset = orderedDescriptors.firstIndex(where: { $0.index == target }),
                  let currentOffset = orderedDescriptors.firstIndex(where: { $0.index == current }) else {
                return .forward
            }
            return targetOffset >= currentOffset ? .forward : .reverse
        }
    }
}

@MainActor
private final class ReaderNativePageViewController: UIViewController, UIScrollViewDelegate {
    let pageIndex: Int
    private let descriptor: GalleryPageDescriptor
    private let resolution: ImageResolution
    private let source: ReaderContentSource
    private let pageScaling: ReaderPageScaling
    private let navigationOrientation: UIPageViewController.NavigationOrientation
    private let model: AppModel
    private let scrollView = UIScrollView()
    private var hostingController: UIHostingController<AnyView>?

    init(
        descriptor: GalleryPageDescriptor,
        resolution: ImageResolution,
        source: ReaderContentSource,
        pageScaling: ReaderPageScaling,
        navigationOrientation: UIPageViewController.NavigationOrientation,
        model: AppModel
    ) {
        pageIndex = descriptor.index
        self.descriptor = descriptor
        self.resolution = resolution
        self.source = source
        self.pageScaling = pageScaling
        self.navigationOrientation = navigationOrientation
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 10
        scrollView.zoomScale = 1
        scrollView.bounces = true
        scrollView.bouncesZoom = true
        scrollView.decelerationRate = .normal
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = true
        if navigationOrientation == .horizontal {
            scrollView.transfersHorizontalScrollingToParent = true
        } else {
            scrollView.transfersVerticalScrollingToParent = true
        }
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let page = ReaderPage(
            descriptor: descriptor,
            resolution: resolution,
            source: source,
            pageScaling: pageScaling,
            fitsViewport: true
        )
        let hostingController = UIHostingController(rootView: AnyView(page.environment(model)))
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hostingController.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            hostingController.view.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])
        self.hostingController = hostingController
    }

    func resetZoom(animated: Bool) {
        scrollView.setZoomScale(1, animated: animated)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        hostingController?.view
    }
}
#endif
