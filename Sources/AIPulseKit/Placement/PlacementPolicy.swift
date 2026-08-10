import Foundation
import CoreGraphics

public enum FallbackCorner: String, Codable, CaseIterable, Sendable, Hashable {
    case bottomLeading
    case bottomTrailing
    case topLeading
    case topTrailing
}

public struct PlacementPreferences: Sendable, Hashable {
    /// For a bottom Dock: leading = left end, trailing = right end.
    /// For a left/right Dock: leading = top of the strip, trailing = bottom.
    public enum Side: String, Codable, CaseIterable, Sendable {
        case leading
        case trailing
    }

    public var preferredSide: Side
    /// Gap kept between the pill and the Dock's reserved strip (8–12 pt).
    public var dockGap: CGFloat
    /// Minimum distance kept from any screen edge (≥ 8 pt).
    public var edgeMargin: CGFloat
    public var fallbackCorner: FallbackCorner
    public var preferredDisplayID: String?
    public var followAutoHiddenDock: Bool

    public init(
        preferredSide: Side = .trailing,
        dockGap: CGFloat = 10,
        edgeMargin: CGFloat = 12,
        fallbackCorner: FallbackCorner = .bottomTrailing,
        preferredDisplayID: String? = nil,
        followAutoHiddenDock: Bool = false
    ) {
        self.preferredSide = preferredSide
        self.dockGap = dockGap
        self.edgeMargin = edgeMargin
        self.fallbackCorner = fallbackCorner
        self.preferredDisplayID = preferredDisplayID
        self.followAutoHiddenDock = followAutoHiddenDock
    }
}

public enum PlacementMode: String, Sendable, Hashable {
    /// Inside the Dock's reserved strip, beside the Dock.
    case dockGutter
    /// Immediately above or beside the Dock, inside the visible frame.
    case adjacentToDock
    /// User-selected fixed corner of the visible frame.
    case corner
}

public struct PlacementResult: Sendable, Hashable {
    public var frame: CGRect
    public var mode: PlacementMode
    public var screenID: String
}

/// Best-effort description of an auto-hidden Dock, sourced from the Dock's
/// public preference domain (orientation + tile size). Used only when the
/// user opts into "follow auto-hidden Dock" and no reserved strip exists.
public struct DockHint: Sendable, Hashable {
    public var position: DockPosition
    /// Approximate thickness the Dock occupies when revealed.
    public var estimatedThickness: CGFloat

    public init(position: DockPosition, estimatedThickness: CGFloat) {
        self.position = position
        self.estimatedThickness = estimatedThickness
    }
}

/// Pure placement math. All inputs are value types so every branch is
/// unit-testable without AppKit.
public enum PlacementPolicy {
    /// Screen choice: explicit preference → the screen that shows a Dock →
    /// the first (primary) screen.
    public static func selectScreen(
        _ screens: [ScreenSnapshot],
        preferredDisplayID: String?
    ) -> ScreenSnapshot? {
        guard !screens.isEmpty else { return nil }
        if let preferred = preferredDisplayID,
           let match = screens.first(where: { $0.id == preferred }) {
            return match
        }
        if let withDock = screens.first(where: { DockGeometry.infer(from: $0).position != nil }) {
            return withDock
        }
        return screens.first
    }

    public static func placement(
        pillSize: CGSize,
        screen: ScreenSnapshot,
        preferences: PlacementPreferences,
        dockHint: DockHint? = nil
    ) -> PlacementResult {
        var dock = DockGeometry.infer(from: screen)

        // A real reserved strip always wins. Only when there is none and the
        // user opted in do we synthesize a strip where the auto-hidden Dock
        // would appear.
        if dock.position == nil,
           preferences.followAutoHiddenDock,
           let hint = dockHint {
            dock = synthesizedGeometry(for: hint, screen: screen)
        }

        let raw: PlacementResult
        switch dock.position {
        case .bottom:
            raw = bottomDockPlacement(pillSize: pillSize, screen: screen, strip: dock.reservedStrip, preferences: preferences)
        case .left, .right:
            raw = verticalDockPlacement(pillSize: pillSize, screen: screen, dock: dock, preferences: preferences)
        case nil:
            raw = cornerPlacement(pillSize: pillSize, screen: screen, preferences: preferences)
        }

        return PlacementResult(
            frame: clamp(raw.frame, into: screen.frame),
            mode: raw.mode,
            screenID: screen.id
        )
    }

    private static func synthesizedGeometry(for hint: DockHint, screen: ScreenSnapshot) -> DockGeometry {
        let frame = screen.frame
        let visible = screen.visibleFrame
        let thickness = hint.estimatedThickness
        let strip: CGRect = switch hint.position {
        case .bottom:
            CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: thickness)
        case .left:
            CGRect(x: frame.minX, y: visible.minY, width: thickness, height: visible.height)
        case .right:
            CGRect(x: frame.maxX - thickness, y: visible.minY, width: thickness, height: visible.height)
        }
        return DockGeometry(position: hint.position, reservedStrip: strip)
    }

    // MARK: - Bottom Dock

    private static func bottomDockPlacement(
        pillSize: CGSize,
        screen: ScreenSnapshot,
        strip: CGRect,
        preferences: PlacementPreferences
    ) -> PlacementResult {
        // The Dock's horizontal extent is not knowable through public API,
        // so the gutter anchors to the screen-edge end of the reserved strip.
        if strip.height >= pillSize.height + 2 {
            let y = strip.minY + (strip.height - pillSize.height) / 2
            let x: CGFloat = switch preferences.preferredSide {
            case .leading: screen.frame.minX + preferences.edgeMargin
            case .trailing: screen.frame.maxX - preferences.edgeMargin - pillSize.width
            }
            return PlacementResult(
                frame: CGRect(x: x, y: y, width: pillSize.width, height: pillSize.height),
                mode: .dockGutter,
                screenID: screen.id
            )
        }

        // Strip too short for the pill: sit immediately above the Dock,
        // inside the visible frame, on the preferred side.
        let y = screen.visibleFrame.minY + preferences.dockGap
        let x: CGFloat = switch preferences.preferredSide {
        case .leading: screen.visibleFrame.minX + preferences.edgeMargin
        case .trailing: screen.visibleFrame.maxX - preferences.edgeMargin - pillSize.width
        }
        return PlacementResult(
            frame: CGRect(x: x, y: y, width: pillSize.width, height: pillSize.height),
            mode: .adjacentToDock,
            screenID: screen.id
        )
    }

    // MARK: - Left / right Dock

    private static func verticalDockPlacement(
        pillSize: CGSize,
        screen: ScreenSnapshot,
        dock: DockGeometry,
        preferences: PlacementPreferences
    ) -> PlacementResult {
        let strip = dock.reservedStrip

        // Preferred: above or below the Dock, horizontally centered in the
        // reserved strip — only if the pill actually fits in the strip width.
        if pillSize.width + 2 * 4 <= strip.width {
            let x = strip.midX - pillSize.width / 2
            let y: CGFloat = switch preferences.preferredSide {
            case .leading: strip.maxY - preferences.edgeMargin - pillSize.height
            case .trailing: strip.minY + preferences.edgeMargin
            }
            return PlacementResult(
                frame: CGRect(x: x, y: y, width: pillSize.width, height: pillSize.height),
                mode: .dockGutter,
                screenID: screen.id
            )
        }

        // Fallback: just inside the visible frame, adjacent to the Dock edge.
        let x: CGFloat = switch dock.position {
        case .left: screen.visibleFrame.minX + preferences.dockGap
        default: screen.visibleFrame.maxX - preferences.dockGap - pillSize.width
        }
        let y: CGFloat = switch preferences.preferredSide {
        case .leading: screen.visibleFrame.maxY - preferences.edgeMargin - pillSize.height
        case .trailing: screen.visibleFrame.minY + preferences.edgeMargin
        }
        return PlacementResult(
            frame: CGRect(x: x, y: y, width: pillSize.width, height: pillSize.height),
            mode: .adjacentToDock,
            screenID: screen.id
        )
    }

    // MARK: - Corner fallback

    private static func cornerPlacement(
        pillSize: CGSize,
        screen: ScreenSnapshot,
        preferences: PlacementPreferences
    ) -> PlacementResult {
        let visible = screen.visibleFrame
        let margin = preferences.edgeMargin
        let x: CGFloat
        let y: CGFloat
        switch preferences.fallbackCorner {
        case .bottomLeading:
            x = visible.minX + margin
            y = visible.minY + margin
        case .bottomTrailing:
            x = visible.maxX - margin - pillSize.width
            y = visible.minY + margin
        case .topLeading:
            x = visible.minX + margin
            y = visible.maxY - margin - pillSize.height
        case .topTrailing:
            x = visible.maxX - margin - pillSize.width
            y = visible.maxY - margin - pillSize.height
        }
        return PlacementResult(
            frame: CGRect(x: x, y: y, width: pillSize.width, height: pillSize.height),
            mode: .corner,
            screenID: screen.id
        )
    }

    // MARK: - Off-screen prevention

    /// Shifts (and if necessary shrinks) a frame so it lies fully inside
    /// `bounds` with at least `margin` points to every edge.
    static func clamp(_ rect: CGRect, into bounds: CGRect, margin: CGFloat = 8) -> CGRect {
        var r = rect
        let allowed = bounds.insetBy(dx: margin, dy: margin)
        r.size.width = min(r.width, allowed.width)
        r.size.height = min(r.height, allowed.height)
        r.origin.x = min(max(r.minX, allowed.minX), allowed.maxX - r.width)
        r.origin.y = min(max(r.minY, allowed.minY), allowed.maxY - r.height)
        return r
    }
}
