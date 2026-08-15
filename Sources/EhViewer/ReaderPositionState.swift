import Foundation

struct ReaderPositionState: Equatable {
    private(set) var page: Int
    private(set) var scrollTarget: Int?
    private(set) var scrollRequestSequence = 0
    private(set) var scrollRequestAnimated = true

    init(page: Int = 0) {
        self.page = max(page, 0)
    }

    mutating func prepare(page: Int, pageCount: Int) {
        self.page = clamped(page, pageCount: pageCount)
        scrollTarget = nil
        scrollRequestSequence = 0
        scrollRequestAnimated = true
    }

    mutating func markVisiblePage(from visiblePages: [Int], displayOrder: [Int]) {
        guard visiblePages.contains(page) == false,
              let visiblePage = displayOrder.first(where: visiblePages.contains) else { return }
        page = visiblePage
    }

    mutating func requestPage(_ page: Int, pageCount: Int, animated: Bool = true) {
        let target = clamped(page, pageCount: pageCount)
        self.page = target
        scrollTarget = target
        scrollRequestAnimated = animated
        scrollRequestSequence &+= 1
    }

    private func clamped(_ page: Int, pageCount: Int) -> Int {
        min(max(page, 0), max(pageCount - 1, 0))
    }
}
