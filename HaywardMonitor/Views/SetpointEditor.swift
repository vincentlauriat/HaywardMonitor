import SwiftUI

/// A single setpoint, edited inside the popover of the gauge it drives.
/// The value is edited locally and sent on "Appliquer" so a slider drag
/// doesn't fire a cloud command per tick.
struct SetpointEditor: View {
    @EnvironmentObject private var model: AppModel

    let label: String
    let range: ClosedRange<Double>
    let step: Double
    let format: String
    /// Value currently held by the device, used to detect a real change.
    let current: Double?
    let apply: (Double) -> Void

    @State private var value: Double = 0
    @State private var loaded = false

    private var isUnchanged: Bool {
        current.map { abs($0 - value) < step / 2 } ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: format, value))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
            }

            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: step)
                    .tint(.poolAqua)
                Stepper("", value: $value, in: range, step: step)
                    .labelsHidden()
            }

            HStack {
                Text("Actuel \(current.map { String(format: format, $0) } ?? "—")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                // No .defaultAction here: the pH popover holds two editors,
                // and two default buttons in one view make Return ambiguous.
                Button("Appliquer") { apply(value) }
                    .disabled(isUnchanged)
            }
        }
        .onAppear(perform: syncFromDevice)
        .onChange(of: model.lastUpdate) { syncFromDevice() }
    }

    private func syncFromDevice() {
        guard let current else { return }
        // Adopt the device value on first load, then only once the user's
        // edit has been applied — never stomp an edit in progress.
        guard !loaded || isUnchanged else { return }
        value = current
        loaded = true
    }
}
