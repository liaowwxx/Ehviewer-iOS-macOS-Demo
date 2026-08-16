import Foundation

enum ReaderPageScaling: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case fit
    case width
    case height
    case original

    var id: Self { self }

    var title: String {
        switch self {
        case .fit: "适应屏幕"
        case .width: "适应宽度"
        case .height: "适应高度"
        case .original: "原始尺寸"
        }
    }
}

enum ReaderStartPosition: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case lastRead
    case first
    case last

    var id: Self { self }

    var title: String {
        switch self {
        case .lastRead: "上次阅读位置"
        case .first: "总是从第一页"
        case .last: "总是从最后一页"
        }
    }
}

enum ReaderScreenRotation: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case automatic
    case portrait
    case landscape

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "跟随系统"
        case .portrait: "竖屏"
        case .landscape: "横屏"
        }
    }
}

struct ReadingSettings: Codable, Hashable, Sendable {
    var readingMode: ReadingMode = .paged
    var readingDirection: ReadingDirection = .rightToLeft
    var pageScaling: ReaderPageScaling = .fit
    var startPosition: ReaderStartPosition = .lastRead
    var screenRotation: ReaderScreenRotation = .automatic
    var keepScreenOn = false
    var showClock = false
    var showProgress = true
    var showBattery = false
    var showPageInterval = true
    var volumePage = false
    var reverseVolumePage = false
    var fullscreen = false
    var showJapaneseTitle = false
    var showTagTranslations = true

    static let defaults = ReadingSettings()
    private static let storageKey = "readingSettings"

    private enum CodingKeys: String, CodingKey {
        case readingMode
        case readingDirection
        case pageScaling
        case startPosition
        case screenRotation
        case keepScreenOn
        case showClock
        case showProgress
        case showBattery
        case showPageInterval
        case volumePage
        case reverseVolumePage
        case fullscreen
        case showJapaneseTitle
        case showTagTranslations
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedMode = try container.decodeIfPresent(String.self, forKey: .readingMode)
        switch storedMode {
        case "continuous":
            readingMode = .verticalPaged
        case "leftToRight":
            readingMode = .paged
            readingDirection = .leftToRight
        case "rightToLeft":
            readingMode = .paged
            readingDirection = .rightToLeft
        default:
            readingMode = .paged
        }

        if let direction = try container.decodeIfPresent(ReadingDirection.self, forKey: .readingDirection) {
            readingDirection = direction
        }
        pageScaling = try container.decodeIfPresent(ReaderPageScaling.self, forKey: .pageScaling) ?? .fit
        startPosition = try container.decodeIfPresent(ReaderStartPosition.self, forKey: .startPosition) ?? .lastRead
        screenRotation = try container.decodeIfPresent(ReaderScreenRotation.self, forKey: .screenRotation) ?? .automatic
        keepScreenOn = try container.decodeIfPresent(Bool.self, forKey: .keepScreenOn) ?? false
        showClock = try container.decodeIfPresent(Bool.self, forKey: .showClock) ?? false
        showProgress = try container.decodeIfPresent(Bool.self, forKey: .showProgress) ?? true
        showBattery = try container.decodeIfPresent(Bool.self, forKey: .showBattery) ?? false
        showPageInterval = try container.decodeIfPresent(Bool.self, forKey: .showPageInterval) ?? true
        volumePage = try container.decodeIfPresent(Bool.self, forKey: .volumePage) ?? false
        reverseVolumePage = try container.decodeIfPresent(Bool.self, forKey: .reverseVolumePage) ?? false
        fullscreen = try container.decodeIfPresent(Bool.self, forKey: .fullscreen) ?? false
        showJapaneseTitle = try container.decodeIfPresent(Bool.self, forKey: .showJapaneseTitle) ?? false
        showTagTranslations = try container.decodeIfPresent(Bool.self, forKey: .showTagTranslations) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(readingMode, forKey: .readingMode)
        try container.encode(readingDirection, forKey: .readingDirection)
        try container.encode(pageScaling, forKey: .pageScaling)
        try container.encode(startPosition, forKey: .startPosition)
        try container.encode(screenRotation, forKey: .screenRotation)
        try container.encode(keepScreenOn, forKey: .keepScreenOn)
        try container.encode(showClock, forKey: .showClock)
        try container.encode(showProgress, forKey: .showProgress)
        try container.encode(showBattery, forKey: .showBattery)
        try container.encode(showPageInterval, forKey: .showPageInterval)
        try container.encode(volumePage, forKey: .volumePage)
        try container.encode(reverseVolumePage, forKey: .reverseVolumePage)
        try container.encode(fullscreen, forKey: .fullscreen)
        try container.encode(showJapaneseTitle, forKey: .showJapaneseTitle)
        try container.encode(showTagTranslations, forKey: .showTagTranslations)
    }

    static func load(from defaults: UserDefaults) -> ReadingSettings {
        var settings: ReadingSettings
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(ReadingSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .defaults
            switch defaults.string(forKey: "readerReadingMode") {
            case "continuous":
                settings.readingMode = .verticalPaged
            case "leftToRight":
                settings.readingDirection = .leftToRight
            case "rightToLeft":
                settings.readingDirection = .rightToLeft
            default:
                break
            }
        }
        return settings
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
