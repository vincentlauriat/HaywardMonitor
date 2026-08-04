import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(Color.poolAmber)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.poolAmber.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }

                if let pool = model.pool {
                    HeroBanner(pool: pool, lastUpdate: model.lastUpdate)

                    SectionHeader(title: "Qualité de l'eau")
                    waterQuality(pool)

                    SectionHeader(title: "Équipements")
                    FiltrationCard(pool: pool)
                    LightCard(pool: pool)
                    equipmentTiles(pool)

                    SectionHeader(title: "Consignes")
                    SetpointsView(pool: pool)
                } else {
                    ProgressView("Chargement des données…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                }
            }
            .padding(24)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                if model.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
                if model.poolIds.count > 1 {
                    Picker("Piscine", selection: Binding(
                        get: { model.selectedPoolId ?? "" },
                        set: { model.selectPool($0) }
                    )) {
                        ForEach(model.poolIds, id: \.self) { Text($0).tag($0) }
                    }
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

    // MARK: - Water quality rings

    private func waterQuality(_ pool: PoolState) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
            if pool.hasPH, let ph = pool.ph {
                RingGauge(
                    title: "pH",
                    value: ph,
                    displayValue: ph.formatted(.number.precision(.fractionLength(2))),
                    unit: "",
                    scale: 6.4...8.2,
                    target: phTarget(pool),
                    caption: phTarget(pool).map {
                        "Cible \($0.lowerBound.formatted(.number.precision(.fractionLength(1)))) – \($0.upperBound.formatted(.number.precision(.fractionLength(1))))"
                    }
                )
            }
            if pool.hasRX, let redox = pool.redox {
                RingGauge(
                    title: "Redox",
                    value: Double(redox),
                    displayValue: "\(redox)",
                    unit: "mV",
                    scale: 300...900,
                    target: pool.redoxSetpoint.map { Double($0) - 40...Double($0) + 40 },
                    caption: pool.redoxSetpoint.map { "Consigne \($0) mV" }
                )
            }
            if pool.hasCL, let chlorine = pool.chlorine {
                RingGauge(
                    title: "Chlore",
                    value: chlorine,
                    displayValue: chlorine.formatted(.number.precision(.fractionLength(2))),
                    unit: "ppm",
                    scale: 0...3
                )
            }
            if pool.hasHidro, let production = pool.electrolysisProduction {
                RingGauge(
                    title: pool.isElectrolysis ? "Électrolyse" : "Hydrolyse",
                    value: production,
                    displayValue: production.formatted(.number.precision(.fractionLength(1))),
                    unit: "g/h",
                    scale: 0...pool.electrolysisMax,
                    caption: pool.electrolysisSetpoint.map {
                        "Consigne \($0.formatted(.number.precision(.fractionLength(1)))) g/h"
                    }
                )
            }
        }
    }

    private func phTarget(_ pool: PoolState) -> ClosedRange<Double>? {
        guard let low = pool.phLow, let high = pool.phHigh, low <= high else { return nil }
        return low...high
    }

    // MARK: - Equipment tiles

    private func equipmentTiles(_ pool: PoolState) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
            if pool.hasHidro {
                ControlTile(
                    title: "Boost électrolyse",
                    icon: "bolt.fill",
                    isActive: pool.boostActive,
                    activeColor: .poolMid
                ) {
                    model.setBoost(!pool.boostActive)
                }
                ControlTile(
                    title: "Mode volet",
                    icon: "rectangle.tophalf.filled",
                    isActive: pool.coverActive,
                    activeColor: .poolMid
                ) {
                    model.setCover(!pool.coverActive)
                }
            }
            if !pool.hideRelays {
                ForEach(pool.relays) { relay in
                    ControlTile(
                        title: relay.name,
                        icon: "powerplug.fill",
                        isActive: relay.isOn
                    ) {
                        model.setRelay(relay.index, on: !relay.isOn)
                    }
                }
            }
        }
    }
}

// MARK: - Filtration

struct FiltrationCard: View {
    @EnvironmentObject private var model: AppModel
    let pool: PoolState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(pool.filtrationOn ? Color.poolAqua : Color.secondary.opacity(0.25))
                        .frame(width: 38, height: 38)
                    Image(systemName: "wind")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(pool.filtrationOn ? .white : .secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Filtration")
                        .font(.callout.weight(.semibold))
                    Text(pool.filtrationOn ? "En marche · mode \(pool.filtrationMode.label)" : "Arrêtée · mode \(pool.filtrationMode.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { pool.filtrationOn },
                    set: { model.setFiltration($0) }
                ))
                .toggleStyle(.switch)
                .tint(.poolAqua)
                .labelsHidden()
            }

            HStack(spacing: 16) {
                Picker("Mode", selection: Binding(
                    get: { pool.filtrationMode },
                    set: { model.setPumpMode($0) }
                )) {
                    ForEach(PumpMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if pool.hasPumpSpeed, let speed = pool.pumpSpeed {
                    Picker("Vitesse", selection: Binding(
                        get: { speed },
                        set: { model.setPumpSpeed($0) }
                    )) {
                        ForEach(PumpSpeed.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .frame(width: 130)
                }
            }
        }
        .card()
    }
}
