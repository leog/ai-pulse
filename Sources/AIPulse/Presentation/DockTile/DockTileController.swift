import AppKit
import SwiftUI
import Observation
import AIPulseKit

/// Optional Dock icon mode. When enabled the app switches to a regular
/// activation policy and renders an aggregate status tile via NSDockTile:
/// custom contentView for the state treatment, badgeLabel for the urgent
/// count. Never bounces the icon.
@MainActor
final class DockTileController {
    private let store: AgentStore
    private var hostingView: NSHostingView<DockTileView>?
    private var lastSummary: DockTileSummary?
    private(set) var enabled = false

    init(store: AgentStore) {
        self.store = store
    }

    func start() {
        observeStore()
    }

    func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        NSApp.setActivationPolicy(enabled ? .regular : .accessory)
        if enabled {
            lastSummary = nil
            refresh()
        } else {
            NSApp.dockTile.contentView = nil
            NSApp.dockTile.badgeLabel = nil
            hostingView = nil
        }
    }

    private func refresh() {
        guard enabled else { return }
        let summary = DockTileAggregator.summarize(store.allSorted, order: store.statePriority)
        guard summary != lastSummary else { return }
        lastSummary = summary

        let tile = NSApp.dockTile
        let view = DockTileView(summary: summary)
        if let hostingView {
            hostingView.rootView = view
        } else {
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(origin: .zero, size: tile.size)
            tile.contentView = hosting
            hostingView = hosting
        }
        tile.badgeLabel = summary.urgentCount > 0 ? "\(summary.urgentCount)" : nil
        tile.display()
    }

    private func observeStore() {
        withObservationTracking {
            _ = store.agentsByID
            _ = store.statePriority
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.refresh()
                self.observeStore()
            }
        }
    }
}

/// Static aggregate rendering: the app icon with a status indicator in the
/// corner. Rendered on demand by NSDockTile.display(), so state is conveyed
/// by color, not animation. (Setting a contentView replaces the Dock's own
/// icon rendering, so the view draws the icon itself.)
struct DockTileView: View {
    let summary: DockTileSummary

    /// The bundled icon art, loaded straight from the icns: the system's
    /// legacy-icon treatment (NSApp.applicationIconImage on macOS 26+) wraps
    /// non-squircle icons in a gray rounded-square backdrop. Unbundled
    /// `swift run` builds fall back to the generic application icon.
    private static let iconImage: NSImage = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSApp.applicationIconImage
    }()

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Image(nsImage: Self.iconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: side, height: side)

                // Only working gets a corner dot: attention and failure are
                // already counted by the numeric badge, so a second marker
                // for them would be redundant.
                if summary.emphasis == .working {
                    Circle()
                        .fill(indicatorColor)
                        .frame(width: side * 0.2, height: side * 0.2)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.3), lineWidth: 1))
                        .shadow(color: indicatorColor.opacity(0.7), radius: side * 0.03)
                        .offset(x: side * 0.26, y: side * 0.26)
                }
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var indicatorColor: Color {
        switch summary.emphasis {
        case .neutral: .gray
        case .working: .indigo
        case .attention: .orange
        case .failure: .red
        }
    }

    private var accessibilityText: String {
        switch summary.emphasis {
        case .neutral: "AI Pulse, no active agents"
        case .working: "AI Pulse, agents working"
        case .attention: "AI Pulse, \(summary.urgentCount) agents need attention"
        case .failure: "AI Pulse, agent failed"
        }
    }
}
