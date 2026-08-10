import Foundation
import CoreGraphics

/// AppKit-free snapshot of one display's geometry, in the global AppKit
/// coordinate space (origin bottom-left of the primary display, y up).
public struct ScreenSnapshot: Sendable, Hashable {
    public var id: String
    public var frame: CGRect
    public var visibleFrame: CGRect

    public init(id: String = "", frame: CGRect, visibleFrame: CGRect) {
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

public enum DockPosition: String, Sendable, Hashable {
    case bottom
    case left
    case right
}

/// Best-effort Dock geometry inferred from the difference between a screen's
/// full frame and its visible frame. macOS exposes no stable public API for
/// the exact rendered Dock bounds, and an auto-hidden Dock reserves no space,
/// so `position == nil` means "hidden, auto-hidden, or on another display".
public struct DockGeometry: Sendable, Hashable {
    public var position: DockPosition?
    /// The reserved strip the Dock occupies, in global coordinates.
    /// Empty when `position` is nil.
    public var reservedStrip: CGRect

    /// Insets smaller than this are treated as noise, not a Dock. The
    /// smallest configurable Dock reserves well over 20 points.
    public static let minimumDockInset: CGFloat = 20

    public static func infer(from screen: ScreenSnapshot) -> DockGeometry {
        let frame = screen.frame
        let visible = screen.visibleFrame

        // The menu bar only ever insets the top, so top deltas are ignored.
        let bottomInset = visible.minY - frame.minY
        let leftInset = visible.minX - frame.minX
        let rightInset = frame.maxX - visible.maxX

        let largest = max(bottomInset, leftInset, rightInset)
        guard largest >= minimumDockInset else {
            return DockGeometry(position: nil, reservedStrip: .zero)
        }

        if largest == bottomInset {
            let strip = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: bottomInset)
            return DockGeometry(position: .bottom, reservedStrip: strip)
        }
        if largest == leftInset {
            let strip = CGRect(x: frame.minX, y: visible.minY, width: leftInset, height: visible.height)
            return DockGeometry(position: .left, reservedStrip: strip)
        }
        let strip = CGRect(x: visible.maxX, y: visible.minY, width: rightInset, height: visible.height)
        return DockGeometry(position: .right, reservedStrip: strip)
    }
}
