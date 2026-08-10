import AppKit
import AIPulseKit

/// Observes screen/Dock geometry changes and keeps the pill panel positioned
/// in the Dock gutter. Updates are debounced — geometry is never polled.
@MainActor
final class DockPlacementController {
    private let panel: NSPanel
    private let settings: PlacementSettings

    private var pillSize = CGSize(width: 120, height: 50)
    private var debounceTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    /// Debounce interval for screen-parameter storms (display wake,
    /// resolution changes, Dock resizing all fire bursts of notifications).
    private let debounce: Duration = .milliseconds(300)

    init(panel: NSPanel, settings: PlacementSettings) {
        self.panel = panel
        self.settings = settings
    }

    func start() {
        let screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleUpdate() }
        }
        observers.append(screenToken)

        // The hosting view resizes the panel as agents come and go; the
        // panel must then re-anchor (e.g. keep its trailing edge fixed)
        // or it grows straight off the screen edge.
        let resizeToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPlacement() }
        }
        observers.append(resizeToken)

        // Dock position/size changes on the current display also surface as
        // visibleFrame changes when switching Spaces on multi-display setups.
        let spaceToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleUpdate() }
        }
        workspaceObservers.append(spaceToken)

        applyPlacement()
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        workspaceObservers.removeAll()
        debounceTask?.cancel()
    }

    /// Called by the SwiftUI content when its fitted size changes.
    func pillSizeChanged(_ size: CGSize) {
        guard size != .zero, size != pillSize else { return }
        pillSize = size
        applyPlacement()
    }

    private func scheduleUpdate() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            self?.applyPlacement()
        }
    }

    func applyPlacement() {
        // The panel's live frame is the authoritative pill size — the
        // hosting view drives it; SwiftUI size preferences proved
        // unreliable in a borderless panel.
        if panel.frame.width > 1, panel.frame.height > 1 {
            pillSize = panel.frame.size
        }
        let snapshots = NSScreen.screens.map { screen in
            ScreenSnapshot(
                id: screen.displayIDString,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame
            )
        }
        guard let target = PlacementPolicy.selectScreen(
            snapshots,
            preferredDisplayID: settings.preferences.preferredDisplayID
        ) else { return }

        let dockHint = settings.preferences.followAutoHiddenDock
            ? DockPreferencesReader.autoHiddenDockHint()
            : nil
        let result = PlacementPolicy.placement(
            pillSize: pillSize,
            screen: target,
            preferences: settings.preferences,
            dockHint: dockHint
        )
        // Skip no-op updates so Dock auto-hide flapping can't cause jitter.
        guard panel.frame != result.frame else { return }
        panel.setFrame(result.frame, display: true)
    }
}

extension NSScreen {
    /// Stable-ish public identifier for user display preferences.
    var displayIDString: String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = deviceDescription[key] as? NSNumber {
            return number.stringValue
        }
        return localizedName
    }
}
