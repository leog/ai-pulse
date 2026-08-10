import SwiftUI
import AIPulseKit

/// SidePulse-style aggregate indicator: eight virtual LEDs in a dark strip.
/// One strip for everything — no per-agent or per-provider distinction.
///
/// Animation language (after the hardware inspiration):
/// - working:   a cyan comet streaks across the LEDs
/// - success:   all eight settle to solid green
/// - failure:   the strip double-blinks red
/// - attention: the strip breathes orange
/// - idle:      a slow aurora drifts in blues and teals
/// - off:       dark
///
/// Animations step at LED-refresh cadence via TimelineView(.periodic) —
/// deliberately not display-refresh — and Reduce Motion replaces every
/// pattern with a static treatment.
struct LightStripView: View {
    let signal: LightSignal

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let ledCount = 8
    private static let cometTail = 3

    // Palette from the inspiration: #26d8ff comet, #30d158 success, #ff2d20 error.
    private static let cyan = Color(red: 0.15, green: 0.85, blue: 1.0)
    private static let auroraBlue = Color(red: 0.23, green: 0.42, blue: 1.0)
    private static let green = Color(red: 0.19, green: 0.82, blue: 0.35)
    private static let red = Color(red: 1.0, green: 0.18, blue: 0.13)

    var body: some View {
        Group {
            if let tick, !reduceMotion {
                TimelineView(.periodic(from: .now, by: tick)) { context in
                    strip(at: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                strip(at: nil)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    /// LED-strip refresh cadence per state; nil renders statically.
    private var tick: TimeInterval? {
        switch signal {
        case .working: 0.12
        case .idle: 0.4
        case .failure: 0.15
        case .attention: 0.1
        case .success, .off: nil
        }
    }

    private func strip(at time: TimeInterval?) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<Self.ledCount, id: \.self) { index in
                let led = ledStyle(index: index, time: time)
                Circle()
                    .fill(led.color.opacity(led.brightness))
                    .frame(width: 7, height: 7)
                    .shadow(color: led.color.opacity(led.brightness * 0.9), radius: 3)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 20)
        .background(Capsule().fill(Color.black.opacity(0.88)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
        .compositingGroup()
        .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
    }

    private func ledStyle(index: Int, time: TimeInterval?) -> (color: Color, brightness: Double) {
        switch signal {
        case .off:
            return (.white, 0.05)

        case .idle:
            guard let time else { return (Self.cyan, 0.22) }
            let phase = time / 3 + Double(index) * 0.45
            let mix = (sin(phase) + 1) / 2
            let color = Self.blend(Self.cyan, Self.auroraBlue, mix)
            return (color, 0.18 + 0.14 * (sin(phase + 1.3) + 1) / 2)

        case .working:
            guard let time else {
                // Static: a lit center segment.
                return (3...5).contains(index) ? (Self.cyan, 0.9) : (Self.cyan, 0.1)
            }
            // Comet: head wraps past the strip so the tail fully exits.
            let head = Int(time / 0.12) % (Self.ledCount + Self.cometTail + 1)
            let distance = head - index
            let brightness: Double = switch distance {
            case 0: 1.0
            case 1: 0.5
            case 2: 0.25
            case 3: 0.12
            default: 0.06
            }
            return (Self.cyan, brightness)

        case .attention:
            guard let time else { return (.orange, 1) }
            return (.orange, 0.55 + 0.4 * (sin(time * 3) + 1) / 2)

        case .failure:
            guard let time else { return (Self.red, 1) }
            // Double-blink, then a dim hold before repeating.
            let cycle = time.truncatingRemainder(dividingBy: 1.2)
            let on = cycle < 0.15 || (0.3..<0.45).contains(cycle)
            return (Self.red, on ? 1 : 0.18)

        case .success:
            return (Self.green, 0.95)
        }
    }

    private static func blend(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let na = NSColor(a).usingColorSpace(.sRGB) ?? .cyan
        let nb = NSColor(b).usingColorSpace(.sRGB) ?? .blue
        return Color(
            red: Double(na.redComponent) * (1 - t) + Double(nb.redComponent) * t,
            green: Double(na.greenComponent) * (1 - t) + Double(nb.greenComponent) * t,
            blue: Double(na.blueComponent) * (1 - t) + Double(nb.blueComponent) * t
        )
    }

    private var accessibilityText: String {
        switch signal {
        case .off: "AI agents: none connected"
        case .idle: "AI agents: idle"
        case .working: "AI agents: working"
        case .success: "AI agents: finished"
        case .attention: "AI agents: waiting for your input"
        case .failure: "AI agents: a session failed"
        }
    }
}
