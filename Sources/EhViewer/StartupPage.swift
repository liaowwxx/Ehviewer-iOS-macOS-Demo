import Foundation
import EHDomain

enum StartupPage: String, CaseIterable, Sendable {
    case browse, local, history, favorites, settings

    var route: AppRoute {
        switch self {
        case .browse: .browse
        case .local: .local
        case .history: .history
        case .favorites: .favorites
        case .settings: .settings
        }
    }

    var title: String {
        switch self {
        case .browse: String(localized: "browse_title")
        case .local: String(localized: "本地")
        case .history: String(localized: "history_title")
        case .favorites: String(localized: "favorites_title")
        case .settings: String(localized: "settings_title")
        }
    }

    static func load(from defaults: UserDefaults) -> Self {
        Self(rawValue: defaults.string(forKey: "startupPage") ?? "") ?? .local
    }
}
