import XCTest
@testable import AIPulseKit

final class ActionSafetyTests: XCTestCase {
    func testUnsafeSchemesRejected() {
        for unsafe in ["javascript:alert(1)", "file:///etc/passwd", "data:text/html,x",
                       "ftp://example.com", "ssh://host", "smb://host/share"] {
            let url = URL(string: unsafe)!
            XCTAssertFalse(URLSafety.isSafe(url), "\(unsafe) must be rejected")
        }
    }

    func testAllowedSchemesAccepted() {
        for safe in ["https://example.com", "aipulse://agent/x", "vscode://file/x", "cursor://open"] {
            XCTAssertTrue(URLSafety.isSafe(URL(string: safe)!), "\(safe) must be allowed")
        }
    }

    func testClickResolutionPrefersValidatedDeepLink() {
        let agent = Agent(
            id: "a", displayName: "A", provider: "test",
            sourceApplicationBundleID: "com.apple.Terminal",
            deepLink: URL(string: "aipulse://agent/a")
        )
        guard case let .openURL(url, _) = ClickActionResolver.resolve(for: agent) else {
            return XCTFail("expected openURL")
        }
        XCTAssertEqual(url.absoluteString, "aipulse://agent/a")
    }

    func testClickResolutionSkipsUnsafeDeepLink() {
        let agent = Agent(
            id: "a", displayName: "A", provider: "test",
            sourceApplicationBundleID: "com.apple.Terminal",
            deepLink: URL(string: "file:///etc/passwd")
        )
        guard case let .activateApplication(bundleID) = ClickActionResolver.resolve(for: agent) else {
            return XCTFail("expected activateApplication")
        }
        XCTAssertEqual(bundleID, "com.apple.Terminal")
    }

    func testClickResolutionFallsBackToProjectThenDetails() {
        let withProject = Agent(id: "a", displayName: "A", provider: "test", projectPath: "/tmp/proj")
        guard case .openProject = ClickActionResolver.resolve(for: withProject) else {
            return XCTFail("expected openProject")
        }

        let bare = Agent(id: "b", displayName: "B", provider: "test")
        XCTAssertEqual(ClickActionResolver.resolve(for: bare), .showDetails)
    }
}
