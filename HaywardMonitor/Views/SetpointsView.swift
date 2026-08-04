import SwiftUI

/// Setpoint editors. Values are edited locally and sent on "Appliquer"
/// so a slider drag doesn't fire a cloud command per tick.
struct SetpointsView: View {
    @EnvironmentObject private var model: AppModel
    let pool: PoolState

    @State private var phLow: Double = 7.0
    @State private var phHigh: Double = 7.4
    @State private var redox: Double = 700
    @State private var electrolysis: Double = 0

    var body: some View {
        VStack(spacing: 14) {
            content
        }
        .card()
        .onAppear(perform: syncFromPool)
        .onChange(of: model.lastUpdate) { syncFromPool() }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 14) {
                if pool.hasPH {
                    setpointRow(label: "pH min", value: $phLow, range: 6...8, step: 0.01,
                                format: "%.2f", current: pool.phLow) {
                        model.setPHLow(phLow)
                    }
                    setpointRow(label: "pH max", value: $phHigh, range: 6...8, step: 0.01,
                                format: "%.2f", current: pool.phHigh) {
                        model.setPHHigh(phHigh)
                    }
                }
                if pool.hasRX {
                    setpointRow(label: "Redox", value: $redox, range: 500...800, step: 5,
                                format: "%.0f mV", current: pool.redoxSetpoint.map(Double.init)) {
                        model.setRedoxSetpoint(Int(redox))
                    }
                }
                if pool.hasHidro {
                    setpointRow(label: "Production", value: $electrolysis,
                                range: 0...pool.electrolysisMax, step: 0.5,
                                format: "%.1f g/h", current: pool.electrolysisSetpoint) {
                        model.setElectrolysisSetpoint(electrolysis)
                    }
                }
        }
    }

    private func syncFromPool() {
        if let v = pool.phLow { phLow = v }
        if let v = pool.phHigh { phHigh = v }
        if let v = pool.redoxSetpoint { redox = Double(v) }
        if let v = pool.electrolysisSetpoint { electrolysis = v }
    }

    private func setpointRow(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: String,
        current: Double?,
        apply: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .tint(.poolAqua)
            Text(String(format: format, value.wrappedValue))
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .frame(width: 74, alignment: .trailing)
            Button("Appliquer") { apply() }
                .disabled(current.map { abs($0 - value.wrappedValue) < step / 2 } ?? false)
        }
    }
}
