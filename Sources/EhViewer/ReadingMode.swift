import Foundation

enum ReadingMode: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case paged
    case verticalPaged

    var id: Self { self }

    var title: String {
        switch self {
        case .paged: "左右翻页"
        case .verticalPaged: "上下翻页"
        }
    }
}

enum ReadingDirection: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case leftToRight
    case rightToLeft

    var id: Self { self }

    var title: String {
        switch self {
        case .leftToRight: "从左到右"
        case .rightToLeft: "从右到左"
        }
    }
}
