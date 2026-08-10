import AppKit

if SnapshotMode.runIfRequested() {
    exit(0)
}

// AI Pulse runs as an accessory app: no Dock icon, no menu bar takeover.
// (An optional Dock icon mode is planned as Milestone 6.)
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
