import Foundation
import Observation
import AIPulseKit

/// User-configurable stale/expiration behavior, persisted in UserDefaults.
@MainActor
@Observable
final class BehaviorSettings {
    private enum Keys {
        static let workingStaleAfter = "behavior.workingStaleAfter"
        // Stored as seconds; -1 encodes "never remove".
        static let completedRemovalDelay = "behavior.completedRemovalDelay"
    }

    var staleness: StalenessConfiguration {
        didSet { save() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var config = StalenessConfiguration.default
        if defaults.object(forKey: Keys.workingStaleAfter) != nil {
            config.workingStaleAfter = defaults.double(forKey: Keys.workingStaleAfter)
        }
        if defaults.object(forKey: Keys.completedRemovalDelay) != nil {
            let stored = defaults.double(forKey: Keys.completedRemovalDelay)
            config.completedRemovalDelay = stored < 0 ? nil : stored
        }
        staleness = config
    }

    private func save() {
        defaults.set(staleness.workingStaleAfter, forKey: Keys.workingStaleAfter)
        defaults.set(staleness.completedRemovalDelay ?? -1, forKey: Keys.completedRemovalDelay)
    }
}
