import Foundation
import Observation
import AIPulseKit

/// User-configurable placement preferences, persisted in UserDefaults.
@MainActor
@Observable
final class PlacementSettings {
    private enum Keys {
        static let side = "placement.preferredSide"
        static let corner = "placement.fallbackCorner"
        static let display = "placement.preferredDisplayID"
        static let followAutoHidden = "placement.followAutoHiddenDock"
    }

    var preferences: PlacementPreferences {
        didSet { save() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var prefs = PlacementPreferences()
        if let raw = defaults.string(forKey: Keys.side),
           let side = PlacementPreferences.Side(rawValue: raw) {
            prefs.preferredSide = side
        }
        if let raw = defaults.string(forKey: Keys.corner),
           let corner = FallbackCorner(rawValue: raw) {
            prefs.fallbackCorner = corner
        }
        prefs.preferredDisplayID = defaults.string(forKey: Keys.display)
        prefs.followAutoHiddenDock = defaults.bool(forKey: Keys.followAutoHidden)
        preferences = prefs
    }

    private func save() {
        defaults.set(preferences.preferredSide.rawValue, forKey: Keys.side)
        defaults.set(preferences.fallbackCorner.rawValue, forKey: Keys.corner)
        defaults.set(preferences.preferredDisplayID, forKey: Keys.display)
        defaults.set(preferences.followAutoHiddenDock, forKey: Keys.followAutoHidden)
    }
}
