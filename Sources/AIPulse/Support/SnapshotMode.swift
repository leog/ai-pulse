import AppKit
import SwiftUI
import AIPulseKit

/// Developer utility: `AIPulse --snapshot <directory>` renders the pill and
/// hover card with mock agents into PNG files (light and dark) and exits.
/// Lets the design be reviewed headlessly, with no Screen Recording access.
@MainActor
enum SnapshotMode {
    static func runIfRequested() -> Bool {
        guard let index = CommandLine.arguments.firstIndex(of: "--snapshot"),
              CommandLine.arguments.count > index + 1 else { return false }
        let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        let store = AgentStore()
        MockAgents.seed(into: store)
        let coordinator = PillCoordinator(store: store, placementSettings: PlacementSettings())

        let appearanceSettings = AppearanceSettings()
        for appearance in ["darkAqua", "aqua"] {
            let suffix = appearance == "darkAqua" ? "dark" : "light"
            snapshot(
                PillView(store: store, appearance: appearanceSettings, coordinator: coordinator),
                appearance: appearance,
                to: directory.appendingPathComponent("pill-\(suffix).png")
            )
        }
        if let waiting = store.allSorted.first(where: { $0.state == .waitingForInput }) {
            snapshot(
                HoverCardView(agent: waiting),
                appearance: "darkAqua",
                to: directory.appendingPathComponent("hovercard-dark.png")
            )
        }
        return true
    }

    private static func snapshot(_ view: some View, appearance: String, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 600, height: 200),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = NSColor(calibratedRed: 0.35, green: 0.3, blue: 0.5, alpha: 1)
        let resolved = NSAppearance(named: NSAppearance.Name(rawValue: appearance))
        window.appearance = resolved
        hosting.appearance = resolved
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        window.setContentSize(hosting.fittingSize)
        window.orderBack(nil)

        // Let SwiftUI settle materials, symbols, and async layout.
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
        window.orderOut(nil)
    }
}
