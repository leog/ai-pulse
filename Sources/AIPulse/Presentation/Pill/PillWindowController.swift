import AppKit
import SwiftUI
import AIPulseKit

/// Owns the nonactivating panel and its SwiftUI content.
@MainActor
final class PillWindowController {
    let panel: AIPulsePanel

    init(store: AgentStore, appearance: AppearanceSettings, coordinator: PillCoordinator) {
        panel = AIPulsePanel()
        let root = PillView(store: store, appearance: appearance, coordinator: coordinator)
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.onPointerEvent = { [weak coordinator] point in
            coordinator?.pointerMoved(point)
        }
        panel.contentView = hosting
    }

    /// Shows the panel without activating the application.
    func show() {
        panel.orderFrontRegardless()
    }
}
