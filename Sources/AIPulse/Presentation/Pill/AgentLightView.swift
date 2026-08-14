import SwiftUI
import AIPulseKit

/// One agent rendered as a single LED — the per-agent counterpart of the
/// aggregate strip, sharing its palette and animation language. No provider
/// glyph or state badge: color and motion carry the state, VoiceOver carries
/// the words.
///
/// - working:            the LED pulses cyan
/// - waiting / approval: breathes orange until acknowledged, then dims solid
/// - failed:             double-blinks red until acknowledged, then dims solid
/// - completed:          solid green
/// - idle / others:      dim static treatments
struct AgentLightView: View {
    let agent: Agent
    var isStale: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let diameter: CGFloat = 10
    /// The LED stays small; the frame keeps a comfortable click target.
    static let hitSize: CGFloat = 20

    var body: some View {
        Group {
            if let tick, !reduceMotion {
                TimelineView(.periodic(from: .now, by: tick)) { context in
                    led(at: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                led(at: nil)
            }
        }
        .frame(width: Self.hitSize, height: Self.hitSize)
        .opacity(isStale ? 0.6 : 1)
    }

    private var isUnresolvedAttention: Bool {
        agent.state.requiresAttention && !agent.isAcknowledged
    }

    /// Refresh cadence per state; nil renders statically.
    private var tick: TimeInterval? {
        switch agent.state {
        case .working: 0.12
        case .waitingForInput, .approvalRequired: isUnresolvedAttention ? 0.1 : nil
        case .failed: isUnresolvedAttention ? 0.15 : nil
        default: nil
        }
    }

    private func led(at time: TimeInterval?) -> some View {
        let style = ledStyle(at: time)
        return Circle()
            .fill(style.color.opacity(style.brightness))
            .frame(width: Self.diameter, height: Self.diameter)
            .shadow(color: style.color.opacity(style.brightness * 0.9), radius: 3)
    }

    private func ledStyle(at time: TimeInterval?) -> (color: Color, brightness: Double) {
        switch agent.state {
        case .working:
            guard let time else { return (LEDPalette.cyan, 0.9) }
            return (LEDPalette.cyan, 0.45 + 0.55 * (sin(time * 2.4) + 1) / 2)

        case .waitingForInput, .approvalRequired:
            guard isUnresolvedAttention else { return (.orange, 0.55) }
            guard let time else { return (.orange, 1) }
            return (.orange, 0.55 + 0.4 * (sin(time * 3) + 1) / 2)

        case .failed:
            guard isUnresolvedAttention else { return (LEDPalette.red, 0.5) }
            guard let time else { return (LEDPalette.red, 1) }
            // Double-blink, then a dim hold before repeating (matches the strip).
            let cycle = time.truncatingRemainder(dividingBy: 1.2)
            let on = cycle < 0.15 || (0.3..<0.45).contains(cycle)
            return (LEDPalette.red, on ? 1 : 0.18)

        case .completed:
            return (LEDPalette.green, 0.95)

        case .idle:
            return (LEDPalette.cyan, 0.22)

        case .disconnected:
            return (.gray, 0.3)

        case .unknown:
            return (.white, 0.12)
        }
    }
}
