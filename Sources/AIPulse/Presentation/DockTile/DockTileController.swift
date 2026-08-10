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
        let summary = DockTileAggregator.summarize(store.allSorted)
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
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.refresh()
                self.observeStore()
            }
        }
    }
}

/// Static aggregate rendering: a dark rounded tile with a pill motif and a
/// status indicator. Rendered on demand by NSDockTile.display(), so state
/// is conveyed by color + glyph, not animation.
struct DockTileView: View {
    let summary: DockTileSummary

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.22)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.22), Color(white: 0.10)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(side * 0.05)

                Capsule()
                    .fill(Color.white.opacity(0.14))
                    .overlay(
                        HStack(spacing: side * 0.045) {
                            ForEach(0..<3, id: \.self) { _ in
                                Circle()
                                    .fill(Color.white.opacity(0.55))
                                    .frame(width: side * 0.09, height: side * 0.09)
                            }
                        }
                    )
                    .frame(width: side * 0.56, height: side * 0.26)

                if summary.emphasis != .neutral {
                    ZStack {
                        Circle().fill(indicatorColor)
                        if let glyph = indicatorGlyph {
                            Image(systemName: glyph)
                                .font(.system(size: side * 0.12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: side * 0.24, height: side * 0.24)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.3), lineWidth: 1))
                    .offset(x: side * 0.22, y: side * 0.22)
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

    private var indicatorGlyph: String? {
        switch summary.emphasis {
        case .neutral: nil
        case .working: "arrow.triangle.2.circlepath"
        case .attention: "questionmark"
        case .failure: "exclamationmark"
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
