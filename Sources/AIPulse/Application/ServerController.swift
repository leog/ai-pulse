import Foundation
import Observation
import AIPulseKit
import os

/// Owns the loopback event service: token, listener lifecycle, and the
/// handshake file the `aipulse` CLI reads.
@MainActor
@Observable
final class ServerController {
    private enum Keys {
        static let port = "transport.port"
    }

    static let defaultPort = 7455

    private let store: AgentStore
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "me.leog.aipulse", category: "server")
    private var server: LocalHTTPServer?

    private(set) var statusText = "Starting…"

    var port: Int {
        didSet {
            defaults.set(port, forKey: Keys.port)
            restart()
        }
    }

    init(store: AgentStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        let stored = defaults.integer(forKey: Keys.port)
        port = (1...65_535).contains(stored) ? stored : Self.defaultPort
    }

    func start() {
        Task {
            let token: String
            if ProcessInfo.processInfo.environment["AIPULSE_DEV_EPHEMERAL_TOKEN"] == "1" {
                // Dev escape hatch: every rebuilt binary has a new ad-hoc
                // signature, so Keychain reads re-prompt on each build.
                // Clients follow along through the handshake file.
                token = KeychainTokenStore.generateToken()
            } else {
                // Keychain access can block on a user consent dialog —
                // never on the main thread, and never before the pill is
                // on screen.
                token = await Task.detached(priority: .userInitiated) {
                    KeychainTokenStore().loadOrCreate()
                }.value
            }
            startServer(token: token)
        }
    }

    private func startServer(token: String) {
        let store = self.store
        let handlers = LocalHTTPServer.Handlers(
            applyEvent: { payload in
                await MainActor.run { store.apply(payload) }
            },
            removeAgent: { id in
                await MainActor.run {
                    guard store.agent(id: id) != nil else { return false }
                    store.remove(id: id)
                    return true
                }
            },
            listAgents: {
                await MainActor.run { store.allSorted }
            }
        )
        let server = LocalHTTPServer(
            configuration: .init(port: UInt16(port), token: token),
            handlers: handlers
        )
        self.server = server

        Task {
            do {
                let boundPort = try await server.start()
                statusText = "Listening on 127.0.0.1:\(boundPort)"
                logger.info("local API listening on port \(boundPort)")
                try CLIHandshakeFile.write(
                    CLIHandshake(port: Int(boundPort), token: token),
                    to: CLIHandshakeFile.defaultURL()
                )
            } catch {
                statusText = "Failed to start on port \(port): \(error.localizedDescription)"
                logger.error("local API failed to start: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func stop() {
        server?.stop()
        server = nil
        statusText = "Stopped"
    }

    private func restart() {
        stop()
        start()
    }
}
