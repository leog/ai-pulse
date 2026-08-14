import AppKit
import AIPulseKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = AgentStore()
    private let placementSettings = PlacementSettings()
    private let behaviorSettings = BehaviorSettings()
    private let appearanceSettings = AppearanceSettings()
    private let persistence = PersistenceStore(fileURL: PersistenceStore.defaultFileURL())
    private var coordinator: PillCoordinator?
    private var pillController: PillWindowController?
    private var placementController: DockPlacementController?
    private var maintenanceController: StoreMaintenanceController?
    private var serverController: ServerController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.statePriority = behaviorSettings.statePriorityOrder
        // Restore unresolved states from the previous run; live-only states
        // come back as disconnected until their source reports again.
        let restored = RestorePolicy.rehydrate(persistence.load(), at: Date())
        restored.forEach { store.upsert($0) }
        // Real integrations exist now; demo agents are opt-in.
        if store.allSorted.isEmpty,
           ProcessInfo.processInfo.environment["AIPULSE_DEMO_AGENTS"] == "1" {
            MockAgents.seed(into: store)
        }

        let coordinator = PillCoordinator(store: store, placementSettings: placementSettings)
        let pillController = PillWindowController(store: store, appearance: appearanceSettings, coordinator: coordinator)
        let placementController = DockPlacementController(panel: pillController.panel, settings: placementSettings)
        let maintenanceController = StoreMaintenanceController(
            store: store,
            persistence: persistence,
            behavior: behaviorSettings
        )

        let serverController = ServerController(store: store)
        let dockTileController = DockTileController(store: store)

        coordinator.appearanceSettings = appearanceSettings
        coordinator.pillController = pillController
        coordinator.dockTileController = dockTileController
        coordinator.placementController = placementController
        coordinator.maintenanceController = maintenanceController
        coordinator.agentListController = AgentListWindowController(store: store, coordinator: coordinator)
        coordinator.settingsController = SettingsWindowController(
            settings: placementSettings,
            behavior: behaviorSettings,
            appearance: appearanceSettings,
            server: serverController,
            coordinator: coordinator
        )

        self.coordinator = coordinator
        self.pillController = pillController
        self.placementController = placementController
        self.maintenanceController = maintenanceController
        self.serverController = serverController

        maintenanceController.start()
        serverController.start()
        placementController.start()
        dockTileController.start()
        dockTileController.setEnabled(appearanceSettings.showDockIcon)
        if appearanceSettings.showPill {
            pillController.show()
        }

        // Debug hook: AIPULSE_DEBUG_HOVER_X=<x> simulates a pointer at that
        // view x-coordinate shortly after launch, so hover-card rendering
        // and placement can be verified headlessly (screenshots) without
        // synthesizing real mouse events.
        if let raw = ProcessInfo.processInfo.environment["AIPULSE_DEBUG_HOVER_X"],
           let x = Double(raw) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak coordinator] in
                coordinator?.pointerMoved(NSPoint(x: x, y: 26))
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        maintenanceController?.saveNow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
