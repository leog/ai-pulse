import SwiftUI
import AIPulseKit

/// Maps AI providers to recognizable, brand-evocative glyphs and colors.
///
/// The marks are simplified geometric shapes drawn in code — evocative of
/// each brand, not trademarked artwork. Adding a provider is one entry in
/// `styles` (plus optional `aliases`); nothing else changes. Resolution
/// order: provider registry → SF Symbol supplied by the integration event →
/// monogram of the agent's name.
enum ProviderIconCatalog {
    struct Style {
        enum Glyph {
            /// Anthropic-style six-spoke asterisk burst.
            case asterisk
            /// OpenAI-style hexagonal knot ring.
            case hexKnot
            case sfSymbol(String)
            case monogram(String)
        }

        var glyph: Glyph
        /// nil = adaptive primary (for black/white brands).
        var color: Color?
    }

    /// Alternate names → canonical registry key.
    private static let aliases: [String: String] = [
        "claude": "anthropic",
        "claude-code": "anthropic",
        "codex": "openai",
        "chatgpt": "openai",
        "gpt": "openai",
        "gemini": "google",
        "bard": "google",
        "copilot": "github",
        "github-copilot": "github",
        "llama": "meta",
        "grok": "xai",
    ]

    private static let styles: [String: Style] = [
        "anthropic": Style(glyph: .asterisk, color: Color(red: 0.78, green: 0.38, blue: 0.25)),
        "openai": Style(glyph: .hexKnot, color: nil),
        "google": Style(glyph: .sfSymbol("sparkle"), color: Color(red: 0.31, green: 0.48, blue: 0.98)),
        "github": Style(glyph: .monogram("GH"), color: nil),
        "meta": Style(glyph: .sfSymbol("infinity"), color: Color(red: 0.0, green: 0.4, blue: 0.9)),
        "mistral": Style(glyph: .monogram("M"), color: .orange),
        "xai": Style(glyph: .monogram("X"), color: nil),
        "cursor": Style(glyph: .sfSymbol("cursorarrow"), color: nil),
        "openclaw": Style(glyph: .sfSymbol("pawprint.fill"), color: Color(red: 0.72, green: 0.52, blue: 0.30)),
        "pi": Style(glyph: .sfSymbol("terminal"), color: Color(red: 0.42, green: 0.56, blue: 0.70)),
    ]

    static func style(for agent: Agent) -> Style {
        let normalized = agent.provider.lowercased().trimmingCharacters(in: .whitespaces)
        if let style = styles[aliases[normalized] ?? normalized] {
            return style
        }
        // The integration may have supplied an SF Symbol with the event.
        if !agent.iconSystemName.isEmpty, agent.iconSystemName != "cpu" {
            return Style(glyph: .sfSymbol(agent.iconSystemName), color: nil)
        }
        let letter = agent.displayName.first.map { String($0).uppercased() } ?? "?"
        return Style(glyph: .monogram(letter), color: nil)
    }
}

struct ProviderGlyphView: View {
    let style: ProviderIconCatalog.Style
    var size: CGFloat = 14

    var body: some View {
        switch style.glyph {
        case .asterisk:
            AsteriskMark(color: style.color ?? .primary, size: size)
        case .hexKnot:
            HexKnotMark(color: style.color ?? .primary, size: size)
        case .sfSymbol(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.85, weight: .medium))
                .foregroundStyle(style.color ?? Color.primary)
                .frame(width: size, height: size)
        case .monogram(let text):
            Text(text)
                .font(.system(size: text.count > 1 ? size * 0.55 : size * 0.8, weight: .bold, design: .rounded))
                .foregroundStyle(style.color ?? Color.primary)
                .frame(width: size, height: size)
        }
    }
}

/// Six-spoke burst: three crossed capsules.
private struct AsteriskMark: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: size * 0.18, height: size)
                    .rotationEffect(.degrees(Double(index) * 60))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Hexagonal knot: six tangential bars forming a hexagon ring, so it reads
/// as a ring rather than a burst even at pill sizes.
private struct HexKnotMark: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: size * 0.52, height: size * 0.15)
                    .offset(y: -size * 0.34)
                    .rotationEffect(.degrees(Double(index) * 60))
            }
        }
        .frame(width: size, height: size)
    }
}
