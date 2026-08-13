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
    var readingMode: ReadingMode = .rightToLeft
    var pageScaling: ReaderPageScaling = .fit
    var startPosition: ReaderStartPosition = .lastRead
    var autoAdvanceSeconds = 0
    var screenRotation: ReaderScreenRotation = .automatic
    var keepScreenOn = false
    var showClock = false
    var showProgress = true
    var showBattery = false
    var showPageInterval = true
    var volumePage = false
    var reverseVolumePage = false
    var fullscreen = false
    var customBrightness = false
    var brightness = 0.5

    static let defaults = ReadingSettings()
    private static let storageKey = "readingSettings"

    static func load(from defaults: UserDefaults) -> ReadingSettings {
        var settings: ReadingSettings
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(ReadingSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .defaults
            if let rawMode = defaults.string(forKey: "readerReadingMode"),
               let legacyMode = ReadingMode(rawValue: rawMode) {
                settings.readingMode = legacyMode
            }
        }
        settings.autoAdvanceSeconds = min(max(settings.autoAdvanceSeconds, 0), 60)
        settings.brightness = min(max(settings.brightness, 0.05), 1)
        return settings
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
