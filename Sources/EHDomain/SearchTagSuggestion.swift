import Foundation

public struct SearchTagSuggestion: Identifiable, Hashable, Sendable {
    public let english: String
    public let localizedText: String?
    /// The key as written in the reference tag database before namespace
    /// expansion (e.g. `a:some artist`), used for detail-page tag lookups.
    public let rawKey: String?

    public init(english: String, localizedText: String? = nil, rawKey: String? = nil) {
        self.english = english
        self.localizedText = localizedText
        self.rawKey = rawKey
    }

    public var id: String { english }
}
