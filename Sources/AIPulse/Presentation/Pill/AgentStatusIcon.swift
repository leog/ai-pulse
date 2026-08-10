import SwiftUI
import AIPulseKit

/// Per-state presentation. Every state differs by glyph and badge, not only
/// color, so status stays readable without color vision.
extension AgentState {
    var tint: Color {
        switch self {
        case .idle: .secondary
        case .working: .indigo
        case .waitingForInput: .orange
        case .approvalRequired: .orange
        case .completed: .green
        case .failed: .red
        case .disconnected: .gray
        case .unknown: .secondary
        }
    }

    /// Small badge glyph overlaid on the agent icon; unique per state.
    var badgeSystemName: String? {
        switch self {
        case .idle: "moon.fill"
        case .working: "arrow.triangle.2.circlepath"
        case .waitingForInput: "questionmark"
        case .approvalRequired: "hand.raised.fill"
        case .completed: "checkmark"
        case .failed: "exclamationmark.triangle.fill"
        case .disconnected: "bolt.slash.fill"
        case .unknown: nil
        }
    }
}

/// One agent's icon inside the pill: agent glyph on a soft tinted disk, a
/// thin attention ring for unresolved waiting/approval/failure, and a solid
/// tinted state badge at the bottom-right corner.
struct AgentStatusIcon: View {
    let agent: Agent
    /// Working-but-silent (per StalenessPolicy); rendered de-emphasized.
    var isStale: Bool = false
    /// True when there is no pill capsule behind the icon (transparent
    /// style): the disk gets a solid material backing and its own shadow.
    var standalone: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    static let diameter: CGFloat = 26

    private var showsAttentionRing: Bool {
        agent.state.requiresAttention && !agent.isAcknowledged
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                if standalone {
                    Circle()
                        .fill(.regularMaterial)
                        .overlay(Circle().fill(Color.black.opacity(0.25)))
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                }
                // The inner disk is inset so the ring reads as a separate,
                // thin outline instead of thickening the disk edge.
                Circle()
                    .fill(agent.state.tint.opacity(agent.state == .disconnected ? 0.14 : 0.28))
                    .padding(2.5)
                if agent.state == .unknown {
                    Circle()
                        .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .padding(2.5)
                }
                if showsAttentionRing {
                    Circle().strokeBorder(agent.state.tint, lineWidth: 1.5)
                }
                ProviderGlyphView(style: ProviderIconCatalog.style(for: agent), size: 14)
                    .saturation(agent.state == .disconnected ? 0 : 1)
                    .opacity(workingPulseOpacity)
            }
            .frame(width: Self.diameter, height: Self.diameter)

            StateBadge(state: agent.state)
                .offset(x: 2, y: 2)
        }
        .opacity(agent.state == .disconnected ? 0.55 : (isStale ? 0.6 : 1))
        .onAppear { startPulseIfNeeded() }
        .onChange(of: agent.state) { startPulseIfNeeded() }
    }

    private var workingPulseOpacity: Double {
        guard agent.state == .working, !reduceMotion else { return 1 }
        return pulsing ? 0.45 : 1
    }

    private func startPulseIfNeeded() {
        guard agent.state == .working, !reduceMotion else {
            pulsing = false
            return
        }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            pulsing = true
        }
    }
}

/// Solid tinted disk with a white glyph — explicit colors so the badge stays
/// legible in both appearances instead of depending on semantic backgrounds.
private struct StateBadge: View {
    let state: AgentState

    var body: some View {
        if let symbol = state.badgeSystemName {
            ZStack {
                Circle().fill(badgeFill)
                Image(systemName: symbol)
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 11, height: 11)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 0.5))
            .accessibilityHidden(true) // state is in the icon's label
        }
    }

    private var badgeFill: Color {
        switch state {
        case .idle, .disconnected: .gray
        default: state.tint
        }
    }
}
