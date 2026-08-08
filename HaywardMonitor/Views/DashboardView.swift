import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(Color.poolAmber)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.poolAmber.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }

                if let pool = model.pool {
                    StatusBar(pool: pool, lastUpdate: model.lastUpdate, isBusy: model.isBusy)

                    measurements(pool)

                    SectionHeader(title: "Équipements")
                    equipment(pool)
                } else {
                    ProgressView("Chargement des données…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                }
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                if model.poolIds.count > 1 {
                    // Pool ids are 20-char device serials; a full-width
                    // picker of them swamps the toolbar.
                    Picker("Piscine", selection: Binding(
                        get: { model.selectedPoolId ?? "" },
                        set: { model.selectPool($0) }
                    )) {
                        ForEach(model.poolIds, id: \.self) { id in
                            Text("…\(id.suffix(6))").tag(id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    .help("Piscine sélectionnée")
                }
                Button {
                    model.manualRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Rafraîchir")
                Menu {
                    Button("Déconnexion") { model.signOut() }
                } label: {
                    Image(systemName: "person.crop.circle")
                }
            }
        }
    }

    // MARK: - Measurements
    //
    // One compact row of gauges. Every gauge that has a setpoint opens it
    // in a popover, so a value is adjusted where it is read.

    private func measurements(_ pool: PoolState) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 4)], spacing: 8) {
            if let temperature = pool.temperature {
                MetricGauge(
                    title: "Eau",
                    displayValue: temperature.formatted(.number.precision(.fractionLength(1))),
                    unit: "°C",
                    value: temperature,
                    scale: 0...40
                )
            }

            if pool.hasPH, let ph = pool.ph {
                MetricGauge(
                    title: "pH",
                    displayValue: ph.formatted(.number.precision(.fractionLength(2))),
                    unit: "",
                    value: ph,
                    scale: 6.4...8.2,
                    target: phTarget(pool),
                    caption: phTarget(pool).map {
                        "\($0.lowerBound.formatted(.number.precision(.fractionLength(1)))) – \($0.upperBound.formatted(.number.precision(.fractionLength(1))))"
                    } ?? "—",
                    isPending: model.isPending("modules.ph.")
                ) {
                    SetpointEditor(
                        label: "pH min", range: 6...8, step: 0.01, format: "%.2f",
                        current: pool.phLow
                    ) { model.setPHLow($0) }

                    Divider()

                    SetpointEditor(
                        label: "pH max", range: 6...8, step: 0.01, format: "%.2f",
                        current: pool.phHigh
                    ) { model.setPHHigh($0) }
                }
            }

            if pool.hasRX, let redox = pool.redox {
                MetricGauge(
                    title: "Redox",
                    displayValue: "\(redox)",
                    unit: "mV",
                    value: Double(redox),
                    scale: 300...900,
                    target: pool.redoxSetpoint.map { Double($0) - 40...Double($0) + 40 },
                    caption: pool.redoxSetpoint.map { "cible \($0) mV" } ?? "—",
                    isPending: model.isPending("modules.rx.")
                ) {
                    SetpointEditor(
                        label: "Consigne redox", range: 500...800, step: 5, format: "%.0f mV",
                        current: pool.redoxSetpoint.map(Double.init)
                    ) { model.setRedoxSetpoint(Int($0)) }
                }
            }

            if pool.hasCL, let chlorine = pool.chlorine {
                MetricGauge(
                    title: "Chlore",
                    displayValue: chlorine.formatted(.number.precision(.fractionLength(2))),
                    unit: "ppm",
                    value: chlorine,
                    scale: 0...3
                )
            }

            if pool.hasHidro, let production = pool.electrolysisProduction {
                MetricGauge(
                    title: pool.isElectrolysis ? "Électrolyse" : "Hydrolyse",
                    displayValue: production.formatted(.number.precision(.fractionLength(1))),
                    unit: "g/h",
                    value: production,
                    scale: 0...pool.electrolysisMax,
                    caption: pool.electrolysisSetpoint.map {
                        "cible \($0.formatted(.number.precision(.fractionLength(1)))) g/h"
                    } ?? "—",
                    isPending: model.isPending("hidro.level")
                ) {
                    SetpointEditor(
                        label: "Production", range: 0...pool.electrolysisMax, step: 0.5, format: "%.1f g/h",
                        current: pool.electrolysisSetpoint
                    ) { model.setElectrolysisSetpoint($0) }
                }
            }
        }
        .card(padding: 6, radius: 14)
    }

    private func phTarget(_ pool: PoolState) -> ClosedRange<Double>? {
        guard let low = pool.phLow, let high = pool.phHigh, low <= high else { return nil }
        return low...high
    }

    // MARK: - Equipment
    //
    // Every device uses the same row: icon, state, an explicit control,
    // and a disclosure when it has settings of its own.

    private func equipment(_ pool: PoolState) -> some View {
        VStack(spacing: 8) {
            // Devices with their own settings keep a full-width row…
            FiltrationRow(pool: pool)
            LightRow(pool: pool)

            // …plain on/off devices pair up so four relays cost two lines
            // instead of four.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 236), spacing: 8)], spacing: 8) {
                if pool.hasHidro {
                    DeviceRow(
                        icon: "bolt.fill",
                        title: "Boost électrolyse",
                        subtitle: pool.boostActive ? "Actif" : "Inactif",
                        isActive: pool.boostActive,
                        isPending: model.isPending("hidro.cloration_enabled"),
                        compact: true
                    ) {
                        DeviceToggle(isOn: pool.boostActive) { model.setBoost($0) }
                    }

                    DeviceRow(
                        icon: "rectangle.tophalf.filled",
                        title: "Mode volet",
                        subtitle: pool.coverActive ? "Actif" : "Inactif",
                        isActive: pool.coverActive,
                        isPending: model.isPending("hidro.cover_enabled"),
                        compact: true
                    ) {
                        DeviceToggle(isOn: pool.coverActive) { model.setCover($0) }
                    }
                }

                if !pool.hideRelays {
                    ForEach(pool.relays) { relay in
                        DeviceRow(
                            icon: "powerplug.fill",
                            // Device names arrive unformatted ("relais1").
                            title: relay.name.localizedCapitalized,
                            subtitle: relay.isOn ? "Allumé" : "Éteint",
                            isActive: relay.isOn,
                            isPending: model.isPending("relays.relay\(relay.index)."),
                            compact: true
                        ) {
                            DeviceToggle(isOn: relay.isOn) { model.setRelay(relay.index, on: $0) }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Filtration

/// Filtration keeps its on/off switch on the row; pump mode and speed
/// live in the disclosure so a 5-segment picker never has to share a
/// line with a toggle at the 720 pt minimum window width.
struct FiltrationRow: View {
    @EnvironmentObject private var model: AppModel
    let pool: PoolState

    var body: some View {
        DeviceRow(
            icon: "wind",
            title: "Filtration",
            subtitle: "\(pool.filtrationOn ? "En marche" : "Arrêtée") · mode \(pool.filtrationMode.label)"
                + (pool.hasPumpSpeed ? (pool.pumpSpeed.map { " · \($0.label)" } ?? "") : ""),
            isActive: pool.filtrationOn,
            isPending: model.isPending("filtration.")
        ) {
            DeviceToggle(isOn: pool.filtrationOn) { model.setFiltration($0) }
        } detail: {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Mode") {
                    Picker("", selection: Binding(
                        get: { pool.filtrationMode },
                        set: { model.setPumpMode($0) }
                    )) {
                        ForEach(PumpMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                if pool.hasPumpSpeed, let speed = pool.pumpSpeed {
                    LabeledContent("Vitesse") {
                        Picker("", selection: Binding(
                            get: { speed },
                            set: { model.setPumpSpeed($0) }
                        )) {
                            ForEach(PumpSpeed.allCases) { s in
                                Text(s.label).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
            }
            .font(.callout)
        }
    }
}
