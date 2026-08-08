import SwiftUI

/// Light control: Off / On / Programmé, with the schedule tucked behind
/// the row's disclosure. Hours are edited locally and pushed with
/// "Appliquer les heures" (`light.from` / `light.to`, seconds since
/// midnight).
struct LightRow: View {
    @EnvironmentObject private var model: AppModel
    let pool: PoolState

    @State private var scheduleFrom = Date()
    @State private var scheduleTo = Date()

    var body: some View {
        DeviceRow(
            icon: pool.lightOn ? "lightbulb.fill" : "lightbulb",
            title: "Éclairage",
            subtitle: stateLabel,
            isActive: pool.lightOn,
            tint: .yellow,
            isPending: model.isPending("light.")
        ) {
            Picker("", selection: Binding(
                get: { pool.lightSelection },
                set: { model.setLightMode($0) }
            )) {
                ForEach(LightSelection.allCases) { selection in
                    Text(selection.label).tag(selection)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 212)
        } detail: {
            HStack(spacing: 12) {
                DatePicker("De", selection: $scheduleFrom, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.field)
                DatePicker("à", selection: $scheduleTo, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.field)
                Spacer(minLength: 0)
                Button("Appliquer les heures") {
                    model.setLightSchedule(
                        from: Self.seconds(from: scheduleFrom),
                        to: Self.seconds(from: scheduleTo)
                    )
                }
                .disabled(!scheduleChanged)
            }
            .font(.callout)
        }
        .onAppear(perform: syncFromPool)
        .onChange(of: model.lastUpdate) {
            // A poll every 30 s must not wipe hours being typed.
            if !scheduleChanged { syncFromPool() }
        }
    }

    private var stateLabel: String {
        switch pool.lightSelection {
        case .off: return "Éteint"
        case .on: return "Allumé"
        case .scheduled:
            let state = pool.lightOn ? "allumé" : "éteint"
            return "Programmé \(Self.timeLabel(pool.lightFrom)) – \(Self.timeLabel(pool.lightTo)) · \(state)"
        }
    }

    private var scheduleChanged: Bool {
        Self.seconds(from: scheduleFrom) != pool.lightFrom
            || Self.seconds(from: scheduleTo) != pool.lightTo
    }

    private func syncFromPool() {
        scheduleFrom = Self.date(fromSeconds: pool.lightFrom)
        scheduleTo = Self.date(fromSeconds: pool.lightTo)
    }

    // MARK: - Seconds-since-midnight helpers

    static func date(fromSeconds seconds: Int) -> Date {
        Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(seconds))
    }

    static func seconds(from date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60
    }

    static func timeLabel(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 3600, (seconds % 3600) / 60)
    }
}
