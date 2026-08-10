import Foundation
import AIPulseKit

/// Best-effort, read-only view of the Dock's own preference domain
/// (`com.apple.dock`) via the public UserDefaults API. Used solely to
/// approximate where an auto-hidden Dock would appear; every value is
/// optional and the app degrades gracefully when the domain is unreadable
/// (e.g. under sandboxing). Nothing here touches the Dock process.
enum DockPreferencesReader {
    struct DockPreferences {
        var orientation: DockPosition?
        var autohide: Bool
        var tileSize: CGFloat?
    }

    static func read() -> DockPreferences {
        guard let defaults = UserDefaults(suiteName: "com.apple.dock") else {
            return DockPreferences(orientation: nil, autohide: false, tileSize: nil)
        }
        let orientation: DockPosition? = switch defaults.string(forKey: "orientation") {
        case "left": .left
        case "right": .right
        case "bottom": .bottom
        default: nil
        }
        let tileSize = defaults.object(forKey: "tilesize") as? Double
        return DockPreferences(
            orientation: orientation,
            autohide: defaults.bool(forKey: "autohide"),
            tileSize: tileSize.map { CGFloat($0) }
        )
    }

    /// Hint for placement when the Dock reserves no space. Returns nil when
    /// auto-hide is off (a visible Dock is inferred from screen geometry).
    static func autoHiddenDockHint() -> DockHint? {
        let prefs = read()
        guard prefs.autohide else { return nil }
        // Revealed Dock thickness ≈ tile size + platter padding. 64 is the
        // system default tile size when the key has never been written.
        let thickness = (prefs.tileSize ?? 64) + 16
        return DockHint(position: prefs.orientation ?? .bottom, estimatedThickness: thickness)
    }
}
