import Foundation

public struct SearchTagSuggestion: Identifiable, Hashable, Sendable {
    public let english: String
    public let localizedText: String?

    public init(english: String, localizedText: String? = nil) {
        self.english = english
        self.localizedText = localizedText
    }

    public var id: String { english }
}
