import AppKit
import SwiftUI
import os

private let hoverLogger = Logger(subsystem: "me.leog.aipulse", category: "hover")

/// Borderless, nonactivating floating panel that hosts the pill.
///
/// Behavior notes (verified against AppKit semantics):
/// - `.nonactivatingPanel` keeps clicks from activating AI Pulse, so the
///   user's frontmost app keeps focus.
/// - `canBecomeKey`/`canBecomeMain` are hard-false: nothing in the pill needs
///   keyboard focus. Keyboard users get the conventional agent-list window.
/// - `hasShadow` is false because a clear window's AppKit shadow is computed
///   from the opaque content outline and leaves artifacts when the capsule
///   resizes; the SwiftUI capsule draws its own shadow instead.
/// - `.canJoinAllSpaces` + `.fullScreenAuxiliary` keep the pill available on
///   normal Spaces and allow it over full-screen apps; `.ignoresCycle` keeps
///   it out of window cycling.
/// - `level = .floating` stays above ordinary app windows but below menus,
///   modal panels, and the Dock itself.
final class AIPulsePanel: NSPanel {
    init(contentRect: NSRect = NSRect(x: 0, y: 0, width: 120, height: 46)) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovableByWindowBackground = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that accepts the first mouse click so interactions work
/// without the panel (or app) ever being activated, and reports pointer
/// position through an always-active tracking area.
///
/// SwiftUI's `.onHover` cannot be used here: its tracking area is only
/// active while the app is active, and AI Pulse is a nonactivating
/// background app — hover would fire only in the rare moments AI Pulse
/// happened to be frontmost, which read as "tooltips work inconsistently".
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    /// Pointer location in view coordinates, or nil when the pointer exits.
    var onPointerEvent: (@MainActor (NSPoint?) -> Void)?

    private var pointerTrackingArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        pointerTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hoverLogger.debug("mouseEntered")
        super.mouseEntered(with: event)
        report(event)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        report(event)
    }

    override func mouseExited(with event: NSEvent) {
        hoverLogger.debug("mouseExited")
        super.mouseExited(with: event)
        onPointerEvent?(nil)
    }

    private func report(_ event: NSEvent) {
        onPointerEvent?(convert(event.locationInWindow, from: nil))
    }
}
