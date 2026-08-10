import Foundation
import Observation
import AIPulseKit

/// Periodic sweep (staleness + expiration) and debounced persistence.
/// Observes the store via the Observation framework, so every mutation path
/// funnels into one save mechanism without the store knowing about disk.
@MainActor
final class StoreMaintenanceController {
    private let store: AgentStore
    private let persistence: PersistenceStore
    private let behavior: BehaviorSettings

    private var sweepTimer: Timer?
    private var saveTask: Task<Void, Never>?

    private let sweepInterval: TimeInterval = 30
    private let saveDebounce: Duration = .seconds(1)

    init(store: AgentStore, persistence: PersistenceStore, behavior: BehaviorSettings) {
        self.store = store
        self.persistence = persistence
        self.behavior = behavior
    }

    func start() {
        observeStore()
        let timer = Timer.scheduledTimer(withTimeInterval: sweepInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sweepNow() }
        }
        timer.tolerance = 5
        sweepTimer = timer
        sweepNow()
        // Agents restored or seeded before start() predate the observation
        // registration, so persist the initial state explicitly.
        saveNow()
    }

    func stop() {
        sweepTimer?.invalidate()
        sweepTimer = nil
        saveTask?.cancel()
    }

    func sweepNow() {
        store.sweep(configuration: behavior.staleness)
    }

    func saveNow() {
        saveTask?.cancel()
        persistence.save(store.allSorted)
    }

    private func observeStore() {
        withObservationTracking {
            _ = store.agentsByID
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.scheduleSave()
                self.observeStore()
            }
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self, saveDebounce] in
            try? await Task.sleep(for: saveDebounce)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }
}
