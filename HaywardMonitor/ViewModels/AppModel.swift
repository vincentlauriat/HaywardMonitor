import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {

    enum Phase: Equatable {
        case loggedOut
        case connecting
        case ready
    }

    @Published var phase: Phase = .loggedOut
    @Published var poolIds: [String] = []
    @Published var selectedPoolId: String?
    @Published var pool: PoolState?
    @Published var lastUpdate: Date?
    @Published var errorMessage: String?
    @Published var isBusy = false

    private let api = HaywardAPI()
    private var pollTask: Task<Void, Never>?
    private static let pollInterval: Duration = .seconds(30)

    // MARK: - Session

    func onLaunch() {
        guard let credentials = KeychainStore.load() else { return }
        Task { await signIn(email: credentials.email, password: credentials.password, savingCredentials: false) }
    }

    func signIn(email: String, password: String, savingCredentials: Bool = true) async {
        phase = .connecting
        errorMessage = nil
        do {
            try await api.signIn(email: email, password: password)
            if savingCredentials {
                KeychainStore.save(.init(email: email, password: password))
            }
            poolIds = try await api.fetchPoolIds()
            guard let first = poolIds.first else {
                errorMessage = "Aucune piscine associée à ce compte."
                phase = .loggedOut
                return
            }
            selectedPoolId = selectedPoolId.flatMap { poolIds.contains($0) ? $0 : nil } ?? first
            try await refresh()
            phase = .ready
            startPolling()
        } catch {
            errorMessage = error.localizedDescription
            phase = .loggedOut
        }
    }

    func signOut() {
        pollTask?.cancel()
        pollTask = nil
        KeychainStore.delete()
        Task { await api.signOut() }
        pool = nil
        poolIds = []
        selectedPoolId = nil
        phase = .loggedOut
    }

    func selectPool(_ poolId: String) {
        selectedPoolId = poolId
        pool = nil
        Task { try? await refresh() }
    }

    // MARK: - Data

    func refresh() async throws {
        guard let poolId = selectedPoolId else { return }
        let raw = try await api.fetchPoolDocument(poolId: poolId)
        pool = PoolState(raw: raw)
        lastUpdate = Date()
    }

    func manualRefresh() {
        Task {
            do { try await refresh() } catch { errorMessage = error.localizedDescription }
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard let self, !Task.isCancelled else { return }
                try? await self.refresh()
            }
        }
    }

    // MARK: - Commands

    /// Send a write. The UI is updated optimistically right away (so
    /// switches respond instantly), then the document is polled every
    /// 3 s for up to ~21 s until the device acknowledges the primary
    /// value — the same reconciliation window the official clients use.
    /// While waiting, the optimistic value is re-applied on top of each
    /// refetch so the switch doesn't flap. If the device never
    /// confirms, the UI reverts and an error is shown.
    private func send(path: String, value: Int, extra: [(String, Int)] = []) {
        guard let poolId = selectedPoolId, let pool else { return }
        let commandData = pool.raw
        let allValues: [(String, Any)] = [(path, value)] + extra.map { ($0.0, $0.1 as Any) }

        applyOptimistic(allValues)

        isBusy = true
        errorMessage = nil
        Task {
            defer { isBusy = false }
            do {
                try await api.setValues(poolId: poolId, poolData: commandData, values: allValues)
                for _ in 0..<7 {
                    try await Task.sleep(for: .seconds(3))
                    try await refresh()
                    if self.pool?.int(path) == value { return }
                    applyOptimistic(allValues)
                }
                errorMessage = "Commande envoyée mais non confirmée par le boîtier."
                try await refresh()
            } catch {
                errorMessage = error.localizedDescription
                try? await refresh()
            }
        }
    }

    private func applyOptimistic(_ values: [(String, Any)]) {
        guard var raw = pool?.raw else { return }
        for (path, value) in values {
            HaywardAPI.setInDict(&raw, path: path.split(separator: ".").map(String.init), value: value)
        }
        pool = PoolState(raw: raw)
    }

    func setFiltration(_ on: Bool) { send(path: "filtration.status", value: on ? 1 : 0) }
    func setPumpMode(_ mode: PumpMode) { send(path: "filtration.mode", value: mode.rawValue) }
    func setPumpSpeed(_ speed: PumpSpeed) { send(path: "filtration.manVel", value: speed.rawValue) }
    /// On NeoPool firmware, `light.status` is ignored while the light is
    /// on a schedule (mode 1), so manual Off/On always forces manual
    /// mode — which is how the official app behaves too.
    func setLightMode(_ selection: LightSelection) {
        switch selection {
        case .off: send(path: "light.status", value: 0, extra: [("light.mode", 0)])
        case .on: send(path: "light.status", value: 1, extra: [("light.mode", 0)])
        case .scheduled: send(path: "light.mode", value: 1)
        }
    }

    /// Schedule bounds in seconds since midnight.
    func setLightSchedule(from: Int, to: Int) {
        send(path: "light.from", value: from, extra: [("light.to", to)])
    }
    func setRelay(_ index: Int, on: Bool) { send(path: "relays.relay\(index).info.onoff", value: on ? 1 : 0) }
    func setBoost(_ on: Bool) { send(path: "hidro.cloration_enabled", value: on ? 1 : 0) }
    func setCover(_ on: Bool) { send(path: "hidro.cover_enabled", value: on ? 1 : 0) }
    func setPHLow(_ value: Double) { send(path: "modules.ph.status.low_value", value: Int(value * 100)) }
    func setPHHigh(_ value: Double) { send(path: "modules.ph.status.high_value", value: Int(value * 100)) }
    func setRedoxSetpoint(_ value: Int) { send(path: "modules.rx.status.value", value: value) }
    func setElectrolysisSetpoint(_ value: Double) { send(path: "hidro.level", value: Int(value * 10)) }
}
