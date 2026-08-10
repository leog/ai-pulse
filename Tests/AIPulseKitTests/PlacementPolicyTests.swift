import XCTest
@testable import AIPulseKit

final class PlacementPolicyTests: XCTestCase {
    private let pill = CGSize(width: 180, height: 34)

    // 1920x1080 display, menu bar 24pt, Dock reserving 80pt at the bottom.
    private var bottomDockScreen: ScreenSnapshot {
        ScreenSnapshot(
            id: "main",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 80, width: 1920, height: 976)
        )
    }

    private var leftDockScreen: ScreenSnapshot {
        ScreenSnapshot(
            id: "main",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 90, y: 0, width: 1830, height: 1056)
        )
    }

    private var rightDockScreen: ScreenSnapshot {
        ScreenSnapshot(
            id: "main",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1830, height: 1056)
        )
    }

    // Auto-hidden Dock reserves no space; only the menu bar insets the frame.
    private var noDockScreen: ScreenSnapshot {
        ScreenSnapshot(
            id: "main",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1056)
        )
    }

    // MARK: - Dock inference

    func testInfersBottomDock() {
        let dock = DockGeometry.infer(from: bottomDockScreen)
        XCTAssertEqual(dock.position, .bottom)
        XCTAssertEqual(dock.reservedStrip, CGRect(x: 0, y: 0, width: 1920, height: 80))
    }

    func testInfersLeftDock() {
        let dock = DockGeometry.infer(from: leftDockScreen)
        XCTAssertEqual(dock.position, .left)
        XCTAssertEqual(dock.reservedStrip.width, 90)
    }

    func testInfersRightDock() {
        let dock = DockGeometry.infer(from: rightDockScreen)
        XCTAssertEqual(dock.position, .right)
        XCTAssertEqual(dock.reservedStrip.minX, 1830)
        XCTAssertEqual(dock.reservedStrip.width, 90)
    }

    func testMenuBarAloneIsNotADock() {
        XCTAssertNil(DockGeometry.infer(from: noDockScreen).position)
    }

    // MARK: - Bottom Dock placement

    func testBottomDockTrailingGutterPlacement() {
        let prefs = PlacementPreferences(preferredSide: .trailing, edgeMargin: 12)
        let result = PlacementPolicy.placement(pillSize: pill, screen: bottomDockScreen, preferences: prefs)
        XCTAssertEqual(result.mode, .dockGutter)
        XCTAssertEqual(result.frame.maxX, 1920 - 12)
        // Vertically centered inside the 80pt Dock strip.
        XCTAssertEqual(result.frame.minY, (80 - 34) / 2, accuracy: 0.5)
    }

    func testBottomDockLeadingGutterPlacement() {
        let prefs = PlacementPreferences(preferredSide: .leading, edgeMargin: 12)
        let result = PlacementPolicy.placement(pillSize: pill, screen: bottomDockScreen, preferences: prefs)
        XCTAssertEqual(result.mode, .dockGutter)
        XCTAssertEqual(result.frame.minX, 12)
    }

    func testBottomDockTooShortFallsBackAboveDock() {
        // A pill taller than the Dock strip cannot sit in the gutter.
        let tallPill = CGSize(width: 180, height: 120)
        let prefs = PlacementPreferences(preferredSide: .trailing)
        let result = PlacementPolicy.placement(pillSize: tallPill, screen: bottomDockScreen, preferences: prefs)
        XCTAssertEqual(result.mode, .adjacentToDock)
        XCTAssertGreaterThanOrEqual(result.frame.minY, bottomDockScreen.visibleFrame.minY)
    }

    // MARK: - Left / right Dock placement

    func testLeftDockNarrowPillCentersInStrip() {
        let narrowPill = CGSize(width: 40, height: 34)
        let prefs = PlacementPreferences(preferredSide: .leading)
        let result = PlacementPolicy.placement(pillSize: narrowPill, screen: leftDockScreen, preferences: prefs)
        XCTAssertEqual(result.mode, .dockGutter)
        XCTAssertEqual(result.frame.midX, 45, accuracy: 0.5) // centered in 90pt strip
        XCTAssertGreaterThan(result.frame.minY, leftDockScreen.frame.midY, "leading = top of strip")
    }

    func testLeftDockWidePillFallsBackAdjacent() {
        let prefs = PlacementPreferences(preferredSide: .trailing, dockGap: 10)
        let result = PlacementPolicy.placement(pillSize: pill, screen: leftDockScreen, preferences: prefs)
        XCTAssertEqual(result.mode, .adjacentToDock)
        XCTAssertEqual(result.frame.minX, leftDockScreen.visibleFrame.minX + 10)
    }

    func testRightDockWidePillFallsBackAdjacent() {
        let prefs = PlacementPreferences(preferredSide: .trailing, dockGap: 10)
        let result = PlacementPolicy.placement(pillSize: pill, screen: rightDockScreen, preferences: prefs)
        XCTAssertEqual(result.mode, .adjacentToDock)
        XCTAssertEqual(result.frame.maxX, rightDockScreen.visibleFrame.maxX - 10)
    }

    // MARK: - Corner fallback

    func testNoDockUsesFallbackCorner() {
        let prefs = PlacementPreferences(edgeMargin: 12, fallbackCorner: .bottomTrailing)
        let result = PlacementPolicy.placement(pillSize: pill, screen: noDockScreen, preferences: prefs)
        XCTAssertEqual(result.mode, .corner)
        XCTAssertEqual(result.frame.maxX, noDockScreen.visibleFrame.maxX - 12)
        XCTAssertEqual(result.frame.minY, noDockScreen.visibleFrame.minY + 12)
    }

    func testTopLeadingCorner() {
        let prefs = PlacementPreferences(edgeMargin: 12, fallbackCorner: .topLeading)
        let result = PlacementPolicy.placement(pillSize: pill, screen: noDockScreen, preferences: prefs)
        XCTAssertEqual(result.frame.minX, 12)
        XCTAssertEqual(result.frame.maxY, noDockScreen.visibleFrame.maxY - 12)
    }

    // MARK: - Off-screen prevention

    func testResultNeverLeavesScreenFrame() {
        let hugePill = CGSize(width: 4000, height: 34)
        for screen in [bottomDockScreen, leftDockScreen, rightDockScreen, noDockScreen] {
            for side in PlacementPreferences.Side.allCases {
                let prefs = PlacementPreferences(preferredSide: side)
                let result = PlacementPolicy.placement(pillSize: hugePill, screen: screen, preferences: prefs)
                XCTAssertTrue(
                    screen.frame.contains(result.frame),
                    "frame \(result.frame) escapes screen \(screen.frame) side=\(side)"
                )
            }
        }
    }

    func testClampShiftsRectInsideBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let offscreen = CGRect(x: 990, y: -50, width: 100, height: 40)
        let clamped = PlacementPolicy.clamp(offscreen, into: bounds, margin: 8)
        XCTAssertTrue(bounds.insetBy(dx: 7, dy: 7).contains(clamped))
        XCTAssertEqual(clamped.size, offscreen.size)
    }

    // MARK: - Auto-hidden Dock hints

    func testAutoHiddenDockHintSynthesizesBottomGutter() {
        let prefs = PlacementPreferences(preferredSide: .trailing, edgeMargin: 12, followAutoHiddenDock: true)
        let hint = DockHint(position: .bottom, estimatedThickness: 80)
        let result = PlacementPolicy.placement(pillSize: pill, screen: noDockScreen, preferences: prefs, dockHint: hint)
        XCTAssertEqual(result.mode, .dockGutter)
        XCTAssertEqual(result.frame.minY, (80 - 34) / 2, accuracy: 0.5)
        XCTAssertEqual(result.frame.maxX, 1920 - 12)
    }

    func testAutoHiddenDockHintSynthesizesLeftGutter() {
        let prefs = PlacementPreferences(preferredSide: .leading, followAutoHiddenDock: true)
        let hint = DockHint(position: .left, estimatedThickness: 80)
        let narrowPill = CGSize(width: 40, height: 34)
        let result = PlacementPolicy.placement(pillSize: narrowPill, screen: noDockScreen, preferences: prefs, dockHint: hint)
        XCTAssertEqual(result.mode, .dockGutter)
        XCTAssertEqual(result.frame.midX, 40, accuracy: 0.5) // centered in 80pt synthesized strip
    }

    func testDockHintIgnoredWithoutOptIn() {
        let prefs = PlacementPreferences(followAutoHiddenDock: false)
        let hint = DockHint(position: .bottom, estimatedThickness: 80)
        let result = PlacementPolicy.placement(pillSize: pill, screen: noDockScreen, preferences: prefs, dockHint: hint)
        XCTAssertEqual(result.mode, .corner)
    }

    func testRealDockStripBeatsHint() {
        // If geometry shows a real bottom Dock, a stale left-Dock hint loses.
        let prefs = PlacementPreferences(preferredSide: .trailing, edgeMargin: 12, followAutoHiddenDock: true)
        let hint = DockHint(position: .left, estimatedThickness: 80)
        let result = PlacementPolicy.placement(pillSize: pill, screen: bottomDockScreen, preferences: prefs, dockHint: hint)
        XCTAssertEqual(result.mode, .dockGutter)
        XCTAssertEqual(result.frame.minY, (80 - 34) / 2, accuracy: 0.5)
        XCTAssertEqual(result.frame.maxX, 1920 - 12)
    }

    // MARK: - Multi-display selection

    func testSelectScreenHonorsPreference() {
        let secondary = ScreenSnapshot(
            id: "secondary",
            frame: CGRect(x: 1920, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 1920, y: 0, width: 1440, height: 876)
        )
        let screens = [bottomDockScreen, secondary]
        XCTAssertEqual(PlacementPolicy.selectScreen(screens, preferredDisplayID: "secondary")?.id, "secondary")
    }

    func testSelectScreenPrefersDockScreenWithoutPreference() {
        let noDockPrimary = ScreenSnapshot(
            id: "primary",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 876)
        )
        var dockSecondary = bottomDockScreen
        dockSecondary.id = "secondary"
        let selected = PlacementPolicy.selectScreen([noDockPrimary, dockSecondary], preferredDisplayID: nil)
        XCTAssertEqual(selected?.id, "secondary")
    }

    func testSelectScreenFallsBackToFirstScreen() {
        let screens = [noDockScreen]
        XCTAssertEqual(PlacementPolicy.selectScreen(screens, preferredDisplayID: "missing")?.id, "main")
        XCTAssertNil(PlacementPolicy.selectScreen([], preferredDisplayID: nil))
    }
}
