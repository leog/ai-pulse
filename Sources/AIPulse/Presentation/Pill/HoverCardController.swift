import AppKit
import SwiftUI
import AIPulseKit

/// Lightweight detail card shown while hovering an agent icon. Hosted in its
/// own nonactivating panel so hovering never focuses or activates AI Pulse.
@MainActor
final class HoverCardController {
    private var panel: AIPulsePanel?
    private var hideTask: Task<Void, Never>?

    func show(agent: Agent, isStale: Bool, above pillPanel: NSPanel, anchorScreenX: CGFloat) {
        present(HoverCardView(agent: agent, isStale: isStale), above: pillPanel, anchorScreenX: anchorScreenX)
    }

    /// Aggregate card for the lights indicator: counts, not identities.
    func showSummary(of agents: [Agent], above pillPanel: NSPanel, anchorScreenX: CGFloat) {
        present(AggregateCardView(agents: agents), above: pillPanel, anchorScreenX: anchorScreenX)
    }

    private func present(_ view: some View, above pillPanel: NSPanel, anchorScreenX: CGFloat) {
        hideTask?.cancel()
        hideTask = nil

        let hosting = FirstMouseHostingView(rootView: AnyView(view))
        // Hovering the card itself keeps it open, so the pointer can travel
        // from the indicator onto the card without it vanishing mid-read.
        hosting.onPointerEvent = { [weak self] point in
            if point != nil {
                self?.hideTask?.cancel()
            } else {
                self?.scheduleHide()
            }
        }
        let size = hosting.fittingSize

        let panel = self.panel ?? AIPulsePanel()
        panel.contentView = hosting
        self.panel = panel

        let pillFrame = pillPanel.frame
        var origin = NSPoint(
            x: anchorScreenX - size.width / 2,
            y: pillFrame.maxY + 4
        )
        if let screen = pillPanel.screen {
            let bounds = screen.frame.insetBy(dx: 8, dy: 8)
            origin.x = min(max(origin.x, bounds.minX), bounds.maxX - size.width)
            origin.y = min(max(origin.y, bounds.minY), bounds.maxY - size.height)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
        }
    }
}

/// Hover card for the lights indicator: aggregate counts by state bucket,
/// deliberately without naming individual agents.
struct AggregateCardView: View {
    let agents: [Agent]

    var body: some View {
        let working = agents.filter { $0.state == .working }.count
        let waiting = agents.filter {
            ($0.state == .waitingForInput || $0.state == .approvalRequired) && !$0.isAcknowledged
        }.count
        let failed = agents.filter { $0.state == .failed && !$0.isAcknowledged }.count

        VStack(alignment: .leading, spacing: 5) {
            Text(agents.count == 1 ? "1 agent session" : "\(agents.count) agent sessions")
                .font(.system(size: 12, weight: .semibold))
            if agents.isEmpty {
                Text("Waiting for local integrations to report.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            countRow(count: working, color: .indigo, label: "working")
            countRow(count: waiting, color: .orange, label: "waiting for you")
            countRow(count: failed, color: .red, label: "failed")
            Text("Click to open the agent list")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(minWidth: 150, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
        .compositingGroup()
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        .padding(8)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func countRow(count: Int, color: Color, label: String) -> some View {
        if count > 0 {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text("\(count) \(label)").font(.system(size: 11, weight: .medium))
            }
        }
    }
}

struct HoverCardView: View {
    let agent: Agent
    var isStale: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ProviderGlyphView(style: ProviderIconCatalog.style(for: agent), size: 12)
                Text(agent.displayName).font(.system(size: 12, weight: .semibold))
                Text(agent.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Circle().fill(agent.state.tint).frame(width: 7, height: 7)
                Text(agent.state.displayLabel.capitalized).font(.system(size: 11, weight: .medium))
                Text("for \(durationText)").font(.system(size: 11)).foregroundStyle(.secondary)
                if isStale {
                    Text("· no recent updates")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
            if let summary = agent.taskSummary {
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Text("\(sourceText) · updated \(relativeUpdateText)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: 260, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
        .compositingGroup()
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        .padding(8)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private var durationText: String {
        let seconds = max(0, Date().timeIntervalSince(agent.stateChangedAt))
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        return String(format: "%.1fh", seconds / 3600)
    }

    private var relativeUpdateText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: agent.lastUpdatedAt, relativeTo: Date())
    }

    private var sourceText: String {
        agent.sourceApplicationBundleID ?? agent.provider
    }
}
