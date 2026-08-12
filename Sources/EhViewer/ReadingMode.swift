import Foundation

enum ReadingMode: String, CaseIterable, Identifiable {
    case leftToRight
    case rightToLeft
    case continuous

    var id: Self { self }

    var title: String {
        switch self {
        case .leftToRight: "从左到右"
        case .rightToLeft: "从右到左"
        case .continuous: "从上到下"
        }
    }
}
