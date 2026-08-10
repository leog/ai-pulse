import AppKit
import SwiftUI
import AIPulseKit

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: PlacementSettings
    private let behavior: BehaviorSettings
    private let appearance: AppearanceSettings
    private let server: ServerController
    private weak var coordinator: PillCoordinator?

    init(
        settings: PlacementSettings,
        behavior: BehaviorSettings,
        appearance: AppearanceSettings,
        server: ServerController,
        coordinator: PillCoordinator
    ) {
        self.settings = settings
        self.behavior = behavior
        self.appearance = appearance
        self.server = server
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
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "AI Pulse Settings"
        window.isReleasedWhenClosed = false
        window.center()
        if let coordinator {
            window.contentViewController = NSHostingController(
                rootView: SettingsView(
                    settings: settings,
                    behavior: behavior,
                    appearance: appearance,
                    server: server,
                    coordinator: coordinator
                )
            )
        }
        return window
    }
}

struct SettingsView: View {
    @Bindable var settings: PlacementSettings
    @Bindable var behavior: BehaviorSettings
    @Bindable var appearance: AppearanceSettings
    var server: ServerController
    let coordinator: PillCoordinator

    @State private var displays: [(id: String, name: String)] = []
    @State private var portText = ""

    /// -1 encodes "never remove" for the completed-removal picker.
    private var completedDelaySelection: Binding<Double> {
        Binding(
            get: { behavior.staleness.completedRemovalDelay ?? -1 },
            set: { behavior.staleness.completedRemovalDelay = $0 < 0 ? nil : $0 }
        )
    }

    /// -1 encodes "never disconnect" for the silent-working picker.
    private var disconnectDelaySelection: Binding<Double> {
        Binding(
            get: { behavior.staleness.workingDisconnectAfter ?? -1 },
            set: { behavior.staleness.workingDisconnectAfter = $0 < 0 ? nil : $0 }
        )
    }

    private var displaySelection: Binding<String> {
        Binding(
            get: { settings.preferences.preferredDisplayID ?? "automatic" },
            set: { settings.preferences.preferredDisplayID = $0 == "automatic" ? nil : $0 }
        )
    }

    var body: some View {
        Form {
            Section("Placement") {
                Picker("Pill side", selection: $settings.preferences.preferredSide) {
                    Text("Left of Dock").tag(PlacementPreferences.Side.leading)
                    Text("Right of Dock").tag(PlacementPreferences.Side.trailing)
                }
                Picker("Display", selection: displaySelection) {
                    Text("Automatic (Dock display)").tag("automatic")
                    ForEach(displays, id: \.id) { display in
                        Text(display.name).tag(display.id)
                    }
                }
                Picker("Fallback corner", selection: $settings.preferences.fallbackCorner) {
                    Text("Bottom Left").tag(FallbackCorner.bottomLeading)
                    Text("Bottom Right").tag(FallbackCorner.bottomTrailing)
                    Text("Top Left").tag(FallbackCorner.topLeading)
                    Text("Top Right").tag(FallbackCorner.topTrailing)
                }
                Toggle("Follow auto-hidden Dock", isOn: $settings.preferences.followAutoHiddenDock)
            }
            Section("Appearance") {
                Picker("Indicator style", selection: $appearance.indicatorStyle) {
                    ForEach(IndicatorStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                Text("Lights shows one aggregate LED strip for all agents; Agent icons shows one icon per session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Pill background", selection: $appearance.pillBackground) {
                    ForEach(PillBackgroundStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                Text("Transparent removes the capsule so only the agent icons float beside the Dock.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Show floating pill", isOn: $appearance.showPill)
                Toggle("Show Dock icon with agent status", isOn: $appearance.showDockIcon)
                Text("The Dock icon shows aggregate status with a numeric badge for agents needing attention. If both surfaces are off, reopen AI Pulse to reach Settings again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Behavior") {
                Picker("Remove completed agents after", selection: completedDelaySelection) {
                    Text("15 seconds").tag(15.0)
                    Text("1 minute").tag(60.0)
                    Text("5 minutes").tag(300.0)
                    Text("Never").tag(-1.0)
                }
                Picker("Mark working agents stale after", selection: $behavior.staleness.workingStaleAfter) {
                    Text("5 minutes").tag(300.0)
                    Text("10 minutes").tag(600.0)
                    Text("20 minutes").tag(1200.0)
                }
                Picker("Disconnect silent working agents after", selection: disconnectDelaySelection) {
                    Text("15 minutes").tag(900.0)
                    Text("30 minutes").tag(1800.0)
                    Text("1 hour").tag(3600.0)
                    Text("Never").tag(-1.0)
                }
                Text("A working agent whose process has exited is disconnected immediately; silence alone disconnects it after this delay. Waiting, approval, and failed states stay visible until resolved or acknowledged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Local API") {
                LabeledContent("Status", value: server.statusText)
                HStack {
                    TextField("Port", text: $portText)
                        .frame(width: 90)
                        .onSubmit(applyPort)
                    Button("Apply", action: applyPort)
                }
                Text("Integrations publish events with the `aipulse` command. Credentials are stored in your Keychain and shared with the CLI via a private config file — no tokens in shell commands.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Privacy") {
                Text("AI Pulse displays status sent by local agent integrations. It does not read prompts, terminal contents, editor contents, or application windows.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onAppear {
            displays = NSScreen.screens.map { ($0.displayIDString, $0.localizedName) }
            portText = String(server.port)
        }
        .onChange(of: settings.preferences) {
            coordinator.placementPreferencesChanged()
        }
        .onChange(of: behavior.staleness) {
            coordinator.behaviorSettingsChanged()
        }
        .onChange(of: appearance.showDockIcon) {
            coordinator.presentationChanged(showDockIcon: appearance.showDockIcon, showPill: appearance.showPill)
        }
        .onChange(of: appearance.showPill) {
            coordinator.presentationChanged(showDockIcon: appearance.showDockIcon, showPill: appearance.showPill)
        }
    }

    private func applyPort() {
        guard let newPort = Int(portText), (1...65_535).contains(newPort) else {
            portText = String(server.port)
            return
        }
        guard newPort != server.port else { return }
        server.port = newPort
    }
}
