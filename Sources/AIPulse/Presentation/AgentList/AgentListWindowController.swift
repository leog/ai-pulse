import AppKit
import SwiftUI
import AIPulseKit

/// Conventional, keyboard-accessible window listing all agents. Unlike the
/// pill panel, this window activates the app and can become key, providing
/// the full keyboard and VoiceOver experience.
@MainActor
final class AgentListWindowController {
    private var window: NSWindow?
    private let store: AgentStore
    private weak var coordinator: PillCoordinator?

    init(store: AgentStore, coordinator: PillCoordinator) {
        self.store = store
        self.coordinator = coordinator
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "AI Pulse — Agents"
        window.isReleasedWhenClosed = false
        if let coordinator {
            let hosting = NSHostingController(
                rootView: AgentListView(store: store, coordinator: coordinator)
            )
            // The window tracks the SwiftUI ideal size, so it fits the row
            // count exactly instead of leaving a fixed frame that scrolls.
            hosting.sizingOptions = .preferredContentSize
            window.contentViewController = hosting
        }
        window.center()
        return window
    }
}

struct AgentListView: View {
    var store: AgentStore
    let coordinator: PillCoordinator

    /// Beyond this the window stops growing and the list scrolls.
    private static let maxRowsWithoutScroll = 10

    var body: some View {
        let agents = store.allSorted
        Group {
            if agents.isEmpty {
                ContentUnavailableView(
                    "No Agents",
                    systemImage: "circle.dashed",
                    description: Text("Agents appear here when local integrations publish status events.")
                )
                .frame(height: 200)
            } else if agents.count <= Self.maxRowsWithoutScroll {
                rows(agents)
            } else {
                ScrollView {
                    rows(agents)
                }
                .frame(height: 520)
            }
        }
        .frame(width: 460)
    }

    private func rows(_ agents: [Agent]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(agents) { agent in
                AgentListRow(
                    agent: agent,
                    isStale: store.staleAgentIDs.contains(agent.id),
                    coordinator: coordinator
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                if agent.id != agents.last?.id {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct AgentListRow: View {
    let agent: Agent
    var isStale: Bool = false
    let coordinator: PillCoordinator

    var body: some View {
        HStack(spacing: 10) {
            AgentStatusIcon(agent: agent, isStale: isStale)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(agent.displayName).font(.system(size: 13, weight: .semibold))
                    Text(agent.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                    if agent.isMuted {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("muted")
                    }
                }
                Text(agent.state.displayLabel.capitalized)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(agent.state.tint)
                if let summary = agent.taskSummary {
                    Text(summary).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            Button("Open") { coordinator.agentClicked(agent) }
                .buttonStyle(.bordered)
                .controlSize(.small)
            if agent.state.requiresAttention && !agent.isAcknowledged {
                Button("Acknowledge") { coordinator.acknowledge(agent) }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(agent.displayName), \(agent.subtitle), \(agent.state.displayLabel)")
    }
}
