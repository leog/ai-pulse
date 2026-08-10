import SwiftUI
import AIPulseKit

struct PillSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

/// Icon centers in window coordinates, keyed by agent ID. Collected via a
/// preference so hover handling stays attached to the icon itself — geometry
/// and hover tracking were previously coupled on a background layer that
/// SwiftUI rebuilt on every store update, dropping hover-enter events.
struct IconAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The capsule content. Width derives from content; the hosting controller
/// reads the reported size and resizes/repositions the panel.
struct PillView: View {
    var store: AgentStore
    var appearance: AppearanceSettings
    let coordinator: PillCoordinator

    @Environment(\.colorScheme) private var colorScheme

    /// Agents shown before aggregating into a "+N" overflow chip.
    static let maxVisibleAgents = 6

    var body: some View {
        Group {
            if appearance.indicatorStyle == .lights {
                lightStrip
            } else {
                iconPill
            }
        }
        .padding(8) // breathing room inside the window for the shadow
        .fixedSize()
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: PillSizePreferenceKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(PillSizePreferenceKey.self) { size in
            MainActor.assumeIsolated {
                coordinator.pillContentSizeChanged(size)
            }
        }
        .onPreferenceChange(IconAnchorPreferenceKey.self) { anchors in
            MainActor.assumeIsolated {
                coordinator.updateIconAnchors(anchors)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent status indicator")
    }

    /// Aggregate LED strip: one light bar for all agents.
    private var lightStrip: some View {
        LightStripView(signal: LightAggregator.signal(for: store.pillAgents))
            .contentShape(Capsule())
            .onTapGesture {
                coordinator.showAgentList()
            }
            .contextMenu {
                Button("Open Agent List") { coordinator.showAgentList() }
                Button("Acknowledge All") { coordinator.acknowledgeAll() }
                Divider()
                Button("Settings…") { coordinator.showSettings() }
                Divider()
                Button("Quit") { coordinator.quit() }
            }
    }

    /// Per-agent icon row (the original presentation, kept as an option).
    private var iconPill: some View {
        let slice = store.visibleAgents(maxCount: Self.maxVisibleAgents)
        return HStack(spacing: 8) {
            if slice.visible.isEmpty {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("No agents connected")
            }
            ForEach(slice.visible) { agent in
                AgentIconButton(
                    agent: agent,
                    isStale: store.staleAgentIDs.contains(agent.id),
                    standalone: appearance.pillBackground == .transparent,
                    coordinator: coordinator
                )
            }
            if slice.overflow > 0 {
                OverflowChip(count: slice.overflow) {
                    coordinator.showAgentList()
                }
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 36)
        .background {
            // ultraThin let bright wallpapers wash the pill out; a heavier
            // material plus a scrim keeps icon contrast stable regardless
            // of what's behind the Dock.
            if appearance.pillBackground != .transparent {
                ZStack {
                    Capsule().fill(.regularMaterial)
                    Capsule().fill(scrimColor)
                }
            }
        }
        .overlay {
            if appearance.pillBackground != .transparent {
                Capsule().strokeBorder(Color.primary.opacity(0.15))
            }
        }
        .compositingGroup()
        .shadow(
            color: .black.opacity(appearance.pillBackground == .transparent ? 0 : 0.25),
            radius: 5, y: 2
        )
    }

    private var scrimColor: Color {
        // Darken in both appearances: the pill sits over the wallpaper, and
        // bright wallpapers otherwise wash out the light-mode material too.
        switch appearance.pillBackground {
        case .dark:
            colorScheme == .dark ? .black.opacity(0.45) : .black.opacity(0.32)
        case .translucent:
            colorScheme == .dark ? .black.opacity(0.18) : .black.opacity(0.08)
        case .transparent:
            .clear
        }
    }
}

/// One interactive agent icon: click (typed safe action), hover (detail
/// card), right-click (context menu). The hover card is the sole hover
/// affordance — a `.help` tooltip alongside it made the two race: ordering
/// the card's panel front cancels AppKit's tooltip, so the tooltip appeared
/// only intermittently.
struct AgentIconButton: View {
    let agent: Agent
    var isStale: Bool = false
    /// True when the pill has no capsule background (transparent style), so
    /// each icon needs its own backing to stand out from the wallpaper.
    var standalone: Bool = false
    let coordinator: PillCoordinator

    var body: some View {
        AgentStatusIcon(agent: agent, isStale: isStale, standalone: standalone)
            .contentShape(Circle())
            .onTapGesture {
                coordinator.agentClicked(agent)
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: IconAnchorPreferenceKey.self,
                        value: [agent.id: proxy.frame(in: .global).midX]
                    )
                }
            )
            .contextMenu {
                Button("Open \(agent.displayName)") { coordinator.agentClicked(agent) }
                Button("Acknowledge") { coordinator.acknowledge(agent) }
                Button("Mute This Agent") { coordinator.mute(agent) }
                Button("Remove Stale Entry") { coordinator.removeStaleEntry(agent) }
                Divider()
                Button("Open Full Agent List") { coordinator.showAgentList() }
                Button("Settings…") { coordinator.showSettings() }
                Divider()
                Button("Quit AI Pulse") { coordinator.quit() }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(.isButton)
    }

    private var accessibilityText: String {
        var text = "\(agent.displayName), \(agent.subtitle), \(agent.state.displayLabel)"
        if isStale { text += ", no recent updates" }
        return text
    }
}

struct OverflowChip: View {
    let count: Int
    let onOpen: () -> Void

    var body: some View {
        Text("+\(count)")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            .contentShape(Capsule())
            .onTapGesture(perform: onOpen)
            .help("\(count) more agents. Click to open the full list.")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(count) more agents")
            .accessibilityAddTraits(.isButton)
    }
}
