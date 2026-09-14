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
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let descriptors: [GalleryPageDescriptor]
    let resolution: ImageResolution
    let resetToken: UUID
    let readingDirection: ReadingDirection
    let source: ReaderContentSource
    @Binding var position: ReaderPositionState
    @State private var initialScrollPending = true

    var body: some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad,
           model.readingSettings.pageLayout == .double {
            ReaderSpreadPagedControllerRepresentable(
                model: model,
                descriptors: descriptors,
                resolution: resolution,
                resetToken: resetToken,
                readingDirection: readingDirection,
                source: source,
                position: $position
            )
        } else {
            ReaderPagedControllerRepresentable(
                model: model,
                descriptors: descriptors,
                resolution: resolution,
                resetToken: resetToken,
                readingDirection: readingDirection,
                navigationOrientation: .horizontal,
                source: source,
                position: $position
            )
        }
        #else
        macPagedContent
        #endif
    }

    #if os(macOS)
    @State private var scrollPosition: Int?
    #endif

    private var displayDescriptors: [GalleryPageDescriptor] {
        readingDirection == .rightToLeft ? Array(descriptors.reversed()) : descriptors
    }

#if os(macOS)
    @ViewBuilder
    private var macPagedContent: some View {
        if model.readingSettings.pageLayout == .double {
            macDoublePagedContent
        } else {
            macSinglePagedContent
        }
    }

    private var macSinglePagedContent: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(displayDescriptors) { descriptor in
                    ReaderPage(
                        descriptor: descriptor,
                        resolution: resolution,
                        source: source,
                        fitsViewport: true,
                        resetToken: resetToken
                    )
                    .containerRelativeFrame([.horizontal, .vertical])
                    .id(descriptor.index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.visible)
        .scrollPosition(id: $scrollPosition, anchor: .center)
        .task {
            await Task.yield()
            scrollPosition = position.page
        }
        .onChange(of: position.scrollRequestSequence) {
            updateScrollPosition()
        }
        .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.55) { visiblePages in
            if initialScrollPending {
                guard visiblePages.contains(position.page) else {
                    scrollPosition = position.page
                    return
                }
                initialScrollPending = false
            }
            position.markVisiblePage(from: visiblePages, displayOrder: descriptors.map(\.index))
        }
    }

    private var macDoublePagedContent: some View {
        let spreadLayout = ReaderSpreadLayout(
            descriptors: descriptors,
            layout: .double,
            readingDirection: readingDirection
        )
        let reduceMotion = accessibilityReduceMotion

        return ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(spreadLayout.spreads) { spread in
                    ReaderSpreadView(
                        spread: spread,
                        resolution: resolution,
                        source: source,
                        resetToken: resetToken
                    )
                    .containerRelativeFrame([.horizontal, .vertical])
                    .id(spread.id)
                    .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                        let applyTransition = reduceMotion == false && phase.isIdentity == false
                        return content
                            .opacity(applyTransition ? 0.94 : 1)
                            .scaleEffect(applyTransition ? 0.985 : 1)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.visible)
        .scrollPosition(id: $scrollPosition, anchor: .center)
        .task {
            await Task.yield()
            scrollPosition = spreadLayout.anchorPage(for: position.page)
        }
        .onChange(of: position.scrollRequestSequence) {
            updateScrollPosition()
        }
        .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.55) { visibleSpreads in
            if initialScrollPending {
                let target = spreadLayout.anchorPage(for: position.page)
                guard visibleSpreads.contains(target) else {
                    scrollPosition = target
                    return
                }
                initialScrollPending = false
            }
            position.markVisiblePage(
                from: visibleSpreads,
                displayOrder: spreadLayout.displayOrder
            )
        }
    }

    private func updateScrollPosition() {
        guard let target = position.scrollTarget else { return }
        if position.scrollRequestAnimated {
            withAnimation {
                scrollPosition = target
            }
        } else {
            scrollPosition = target
        }
    }
#endif
}

#if os(iOS)
struct ReaderPagedControllerRepresentable: UIViewControllerRepresentable {
    let model: AppModel
    let descriptors: [GalleryPageDescriptor]
    let resolution: ImageResolution
    let resetToken: UUID
    let readingDirection: ReadingDirection
    let navigationOrientation: UIPageViewController.NavigationOrientation
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
            source: ReaderContentSource
        ) -> UIPageViewController {
            self.model = model
            self.descriptors = descriptors
            self.resolution = resolution
            self.resetToken = resetToken
            self.readingDirection = readingDirection
            self.navigationOrientation = navigationOrientation
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
    private let navigationOrientation: UIPageViewController.NavigationOrientation
    private let model: AppModel
    private let scrollView = UIScrollView()
    private var hostingController: UIHostingController<AnyView>?

    init(
        descriptor: GalleryPageDescriptor,
        resolution: ImageResolution,
        source: ReaderContentSource,
        navigationOrientation: UIPageViewController.NavigationOrientation,
        model: AppModel
    ) {
        pageIndex = descriptor.index
        self.descriptor = descriptor
        self.resolution = resolution
        self.source = source
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
            fitsViewport: true,
            resetToken: UUID()
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

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        let canTransferToParent = scrollView.zoomScale <= scrollView.minimumZoomScale + 0.001
        if navigationOrientation == .horizontal {
            scrollView.transfersHorizontalScrollingToParent = canTransferToParent
        } else {
            scrollView.transfersVerticalScrollingToParent = canTransferToParent
        }
    }
}

struct ReaderSpreadPagedControllerRepresentable: UIViewControllerRepresentable {
    let model: AppModel
    let descriptors: [GalleryPageDescriptor]
    let resolution: ImageResolution
    let resetToken: UUID
    let readingDirection: ReadingDirection
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
        private var source: ReaderContentSource = .remote
        private var resetToken: UUID?
        private var lastScrollRequestSequence = -1
        private var layout = ReaderSpreadLayout(
            descriptors: [],
            layout: .double,
            readingDirection: .rightToLeft
        )
        private var pages: [Int: ReaderNativeSpreadViewController] = [:]

        init(position: Binding<ReaderPositionState>) {
            self.position = position
        }

        func makeController(
            model: AppModel,
            descriptors: [GalleryPageDescriptor],
            resolution: ImageResolution,
            resetToken: UUID,
            readingDirection: ReadingDirection,
            source: ReaderContentSource
        ) -> UIPageViewController {
            self.model = model
            self.descriptors = descriptors
            self.resolution = resolution
            self.resetToken = resetToken
            self.readingDirection = readingDirection
            self.source = source
            layout = makeLayout(descriptors: descriptors, readingDirection: readingDirection)
            lastScrollRequestSequence = position.wrappedValue.scrollRequestSequence

            let controller = UIPageViewController(
                transitionStyle: .scroll,
                navigationOrientation: .horizontal
            )
            controller.dataSource = self
            controller.delegate = self
            self.controller = controller

            let initialAnchor = layout.anchorPage(for: position.wrappedValue.page)
            controller.setViewControllers(
                [pageController(for: initialAnchor)],
                direction: .forward,
                animated: false
            )
            return controller
        }

        func update(
            controller: UIPageViewController,
            model: AppModel,
            descriptors: [GalleryPageDescriptor],
            resolution: ImageResolution,
            resetToken: UUID,
            readingDirection: ReadingDirection,
            source: ReaderContentSource,
            position: ReaderPositionState
        ) {
            let descriptorsChanged = self.descriptors.map(\.id) != descriptors.map(\.id)
            let directionChanged = self.readingDirection != readingDirection
            self.model = model
            self.descriptors = descriptors
            self.resolution = resolution
            self.readingDirection = readingDirection
            self.source = source
            layout = makeLayout(descriptors: descriptors, readingDirection: readingDirection)

            if descriptorsChanged || directionChanged {
                pages = [:]
                let currentAnchor = layout.anchorPage(for: position.page)
                controller.setViewControllers(
                    [pageController(for: currentAnchor)],
                    direction: .forward,
                    animated: false
                )
            }

            if self.resetToken != resetToken {
                self.resetToken = resetToken
                pages.values.forEach { $0.resetZoom(animated: false) }
            }

            if lastScrollRequestSequence != position.scrollRequestSequence {
                lastScrollRequestSequence = position.scrollRequestSequence
                let target = layout.anchorPage(for: position.scrollTarget ?? position.page)
                let current = currentAnchorPage ?? layout.anchorPage(for: position.page)
                let direction = navigationDirection(to: target, from: current)
                controller.setViewControllers(
                    [pageController(for: target)],
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
            guard finished, completed, let currentAnchorPage else { return }
            position.wrappedValue.markVisiblePage(
                from: [currentAnchorPage],
                displayOrder: layout.displayOrder
            )
            prunePages(around: currentAnchorPage)
        }

        private var currentAnchorPage: Int? {
            controller?.viewControllers?.first
                .flatMap { ($0 as? ReaderNativeSpreadViewController)?.anchorPage }
        }

        private func adjacentPage(from viewController: UIViewController, offset: Int) -> UIViewController? {
            guard let anchorPage = (viewController as? ReaderNativeSpreadViewController)?.anchorPage,
                  let currentOffset = layout.spreads.firstIndex(where: { $0.id == anchorPage }) else {
                return nil
            }
            let targetOffset = currentOffset + offset
            guard layout.spreads.indices.contains(targetOffset) else { return nil }
            return pageController(for: layout.spreads[targetOffset].id)
        }

        private func pageController(for anchorPage: Int) -> ReaderNativeSpreadViewController {
            if let existing = pages[anchorPage] {
                return existing
            }
            guard let spread = layout.spreads.first(where: { $0.id == anchorPage }),
                  let model else { preconditionFailure("Reader spread is unavailable") }
            let page = ReaderNativeSpreadViewController(
                spread: spread,
                resolution: resolution,
                source: source,
                model: model,
                resetToken: resetToken ?? UUID()
            )
            pages[anchorPage] = page
            prunePages(around: anchorPage)
            return page
        }

        private func prunePages(around anchorPage: Int) {
            guard let currentOffset = layout.spreads.firstIndex(where: { $0.id == anchorPage }) else { return }
            let retainedIndexes = Set(
                [currentOffset - 1, currentOffset, currentOffset + 1]
                    .filter { layout.spreads.indices.contains($0) }
                    .map { layout.spreads[$0].id }
            )
            pages = pages.filter { retainedIndexes.contains($0.key) }
        }

        private func navigationDirection(
            to target: Int,
            from current: Int
        ) -> UIPageViewController.NavigationDirection {
            guard let targetOffset = layout.spreads.firstIndex(where: { $0.id == target }),
                  let currentOffset = layout.spreads.firstIndex(where: { $0.id == current }) else {
                return .forward
            }
            return targetOffset >= currentOffset ? .forward : .reverse
        }

        private func makeLayout(
            descriptors: [GalleryPageDescriptor],
            readingDirection: ReadingDirection
        ) -> ReaderSpreadLayout {
            ReaderSpreadLayout(
                descriptors: descriptors,
                layout: .double,
                readingDirection: readingDirection
            )
        }
    }
}

@MainActor
private final class ReaderNativeSpreadViewController: UIViewController, UIScrollViewDelegate {
    let anchorPage: Int
    private let spread: ReaderSpread
    private let resolution: ImageResolution
    private let source: ReaderContentSource
    private let model: AppModel
    private let resetToken: UUID
    private let scrollView = UIScrollView()
    private var hostingController: UIHostingController<AnyView>?

    init(
        spread: ReaderSpread,
        resolution: ImageResolution,
        source: ReaderContentSource,
        model: AppModel,
        resetToken: UUID
    ) {
        anchorPage = spread.anchorPage
        self.spread = spread
        self.resolution = resolution
        self.source = source
        self.model = model
        self.resetToken = resetToken
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
        scrollView.transfersHorizontalScrollingToParent = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let spreadView = ReaderIOSSpreadView(
            spread: spread,
            resolution: resolution,
            source: source,
            resetToken: resetToken
        )
        let hostingController = UIHostingController(rootView: AnyView(spreadView.environment(model)))
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

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        scrollView.transfersHorizontalScrollingToParent =
            scrollView.zoomScale <= scrollView.minimumZoomScale + 0.001
    }
}
#endif
