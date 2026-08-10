import AppKit
import AIPulseKit
import os

/// Routes typed UI intents (click, acknowledge, hover, menu items) from the
/// SwiftUI views to AppKit controllers and the store. Owned by AppDelegate.
@MainActor
final class PillCoordinator {
    private let logger = Logger(subsystem: "me.leog.aipulse", category: "actions")

    let store: AgentStore
    let placementSettings: PlacementSettings
    /// Set by the app delegate; determines hover behavior (per-icon card
    /// for icon style, one aggregate card for lights).
    weak var appearanceSettings: AppearanceSettings?

    var pillController: PillWindowController?
    var agentListController: AgentListWindowController?
    var settingsController: SettingsWindowController?
    var maintenanceController: StoreMaintenanceController?
    var dockTileController: DockTileController?

    /// The pill reports its size during hosting-view setup, before the
    /// placement controller is wired; replay the last size on attach so the
    /// initial placement never runs with a stale default.
    var placementController: DockPlacementController? {
        didSet {
            if let lastPillSize {
                placementController?.pillSizeChanged(lastPillSize)
            }
        }
    }
    private var lastPillSize: CGSize?
    private let hoverCardController = HoverCardController()

    init(store: AgentStore, placementSettings: PlacementSettings) {
        self.store = store
        self.placementSettings = placementSettings
    }

    // MARK: - Click

    func agentClicked(_ agent: Agent) {
        let action = ClickActionResolver.resolve(for: agent)
        store.acknowledge(id: agent.id)
        perform(action, for: agent)
    }

    /// Executes a typed action. Only validated URLs, known applications, and
    /// known project locations are ever opened — never a command string.
    private func perform(_ action: AgentAction, for agent: Agent) {
        switch action {
        case let .openURL(url, label):
            logger.info("action openURL agent=\(agent.id, privacy: .public) label=\(label, privacy: .public) scheme=\(url.scheme ?? "?", privacy: .public)")
            guard URLSafety.isSafe(url) else { return }
            NSWorkspace.shared.open(url)
        case let .activateApplication(bundleIdentifier):
            logger.info("action activateApplication agent=\(agent.id, privacy: .public) bundle=\(bundleIdentifier, privacy: .public)")
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            if let app = apps.first {
                app.activate()
            } else {
                logger.info("owning application not running; showing details instead")
                showAgentList()
            }
        case let .openProject(path):
            logger.info("action openProject agent=\(agent.id, privacy: .public)")
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        case .showDetails:
            logger.info("action showDetails agent=\(agent.id, privacy: .public)")
            showAgentList()
        }
    }

    // MARK: - Context menu

    func acknowledge(_ agent: Agent) {
        logger.info("acknowledge agent=\(agent.id, privacy: .public)")
        store.acknowledge(id: agent.id)
    }

    func mute(_ agent: Agent) {
        logger.info("mute agent=\(agent.id, privacy: .public)")
        store.setMuted(id: agent.id, muted: true)
    }

    func removeStaleEntry(_ agent: Agent) {
        logger.info("remove agent=\(agent.id, privacy: .public)")
        store.remove(id: agent.id)
    }

    func showAgentList() {
        agentListController?.show()
    }

    func acknowledgeAll() {
        logger.info("acknowledge all")
        store.acknowledgeAll()
    }

    func showSettings() {
        settingsController?.show()
    }

    func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Hover

    /// Icon centers in window coordinates, reported by the pill layout.
    private var iconAnchors: [String: CGFloat] = [:]
    private var hoveredAgentID: String?

    /// Half an icon plus half the inter-icon spacing.
    private static let hoverHitRadius: CGFloat = 17

    func updateIconAnchors(_ anchors: [String: CGFloat]) {
        iconAnchors = anchors
    }

    /// Driven by the panel's always-active AppKit tracking area (SwiftUI
    /// hover is inert while the app is inactive). `point` is in the pill
    /// view's coordinates; nil means the pointer left the panel.
    private var summaryCardVisible = false

    func pointerMoved(_ point: NSPoint?) {
        logger.debug("pointerMoved x=\(point?.x ?? -1) anchors=\(self.iconAnchors.count)")
        guard let pillPanel = pillController?.panel else { return }

        // Lights style has no per-agent geometry: one aggregate card.
        if appearanceSettings?.indicatorStyle == .lights {
            if point != nil {
                guard !summaryCardVisible else { return }
                summaryCardVisible = true
                hoverCardController.showSummary(
                    of: store.pillAgents,
                    above: pillPanel,
                    anchorScreenX: pillPanel.frame.midX
                )
            } else {
                summaryCardVisible = false
                hoverCardController.scheduleHide()
            }
            return
        }

        guard let point,
              let hit = iconAnchors.min(by: { abs($0.value - point.x) < abs($1.value - point.x) }),
              abs(hit.value - point.x) <= Self.hoverHitRadius,
              let agent = store.agent(id: hit.key) else {
            hoveredAgentID = nil
            hoverCardController.scheduleHide()
            return
        }
        guard hit.key != hoveredAgentID else { return }
        hoveredAgentID = hit.key
        hoverCardController.show(
            agent: agent,
            isStale: store.staleAgentIDs.contains(agent.id),
            above: pillPanel,
            anchorScreenX: pillPanel.frame.minX + hit.value
        )
    }

    // MARK: - Layout

    func pillContentSizeChanged(_ size: CGSize) {
        logger.debug("pillContentSizeChanged \(size.width)x\(size.height) placement=\(self.placementController != nil)")
        lastPillSize = size
        placementController?.pillSizeChanged(size)
    }

    func placementPreferencesChanged() {
        placementController?.applyPlacement()
    }

    /// Re-sweeps immediately so new staleness thresholds take effect without
    /// waiting for the next timer tick.
    func behaviorSettingsChanged() {
        maintenanceController?.sweepNow()
    }

    /// Dock icon and floating pill are independently toggleable surfaces.
    func presentationChanged(showDockIcon: Bool, showPill: Bool) {
        dockTileController?.setEnabled(showDockIcon)
        if showPill {
            pillController?.show()
            placementController?.applyPlacement()
        } else {
            pillController?.panel.orderOut(nil)
        }
    }
}
