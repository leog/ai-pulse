import Foundation
import Observation

/// What the floating indicator shows: the aggregate LED strip (default) or
/// one light per agent. (`icons` is the historical raw value; the style now
/// renders per-agent lights.)
enum IndicatorStyle: String, CaseIterable {
    case lights
    case icons

    var label: String {
        switch self {
        case .lights: "Lights"
        case .icons: "Agent lights"
        }
    }
}

/// Pill surface style, persisted in UserDefaults.
enum PillBackgroundStyle: String, CaseIterable {
    /// Dimmed platter for maximum icon contrast (default).
    case dark
    /// System material, closer to the Dock's own translucency.
    case translucent
    /// No capsule at all; icon disks float directly over the wallpaper.
    case transparent

    var label: String {
        switch self {
        case .dark: "Dark"
        case .translucent: "Translucent"
        case .transparent: "Transparent"
        }
    }
}

@MainActor
@Observable
final class AppearanceSettings {
    private enum Keys {
        static let indicatorStyle = "appearance.indicatorStyle"
        static let pillBackground = "appearance.pillBackground"
        static let showDockIcon = "appearance.showDockIcon"
        static let showPill = "appearance.showPill"
    }

    var indicatorStyle: IndicatorStyle {
        didSet { defaults.set(indicatorStyle.rawValue, forKey: Keys.indicatorStyle) }
    }

    var pillBackground: PillBackgroundStyle {
        didSet { defaults.set(pillBackground.rawValue, forKey: Keys.pillBackground) }
    }

    /// Dock-adjacent pill and application Dock icon are independent modes.
    var showDockIcon: Bool {
        didSet { defaults.set(showDockIcon, forKey: Keys.showDockIcon) }
    }

    var showPill: Bool {
        didSet { defaults.set(showPill, forKey: Keys.showPill) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Keys.indicatorStyle),
           let style = IndicatorStyle(rawValue: raw) {
            indicatorStyle = style
        } else {
            indicatorStyle = .lights
        }
        if let raw = defaults.string(forKey: Keys.pillBackground),
           let style = PillBackgroundStyle(rawValue: raw) {
            pillBackground = style
        } else {
            pillBackground = .dark
        }
        showDockIcon = defaults.bool(forKey: Keys.showDockIcon)
        showPill = defaults.object(forKey: Keys.showPill) == nil
            ? true
            : defaults.bool(forKey: Keys.showPill)
    }
}
