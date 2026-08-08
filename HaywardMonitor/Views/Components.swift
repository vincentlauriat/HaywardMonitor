import SwiftUI

// MARK: - Palette

extension Color {
    /// Turquoise piscine — accent principal.
    static let poolAqua = Color(red: 42 / 255, green: 193 / 255, blue: 184 / 255)
    /// Bleu profond du héro.
    static let poolDeep = Color(red: 10 / 255, green: 61 / 255, blue: 92 / 255)
    /// Bleu intermédiaire du dégradé.
    static let poolMid = Color(red: 17 / 255, green: 121 / 255, blue: 168 / 255)
    /// Ambre — valeur hors plage cible.
    static let poolAmber = Color(red: 232 / 255, green: 163 / 255, blue: 61 / 255)
}

// MARK: - Card container

struct CardBackground: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius))
    }
}

extension View {
    func card(padding: CGFloat = 16, radius: CGFloat = 14) -> some View {
        modifier(CardBackground(padding: padding, radius: radius))
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .kerning(1.2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Status bar

/// Single compact line replacing the former 150 pt hero: pool name,
/// online dot, last refresh, and a spinner while a command is in flight.
/// The temperature moved to the gauge row so nothing is stated twice.
struct StatusBar: View {
    let pool: PoolState
    let lastUpdate: Date?
    let isBusy: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(pool.isOnline ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(pool.name)
                .font(.headline)
                .lineLimit(1)

            Text(pool.isOnline ? "En ligne" : "Hors ligne")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                Text("Envoi…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let lastUpdate {
                Text("Mis à jour à \(lastUpdate.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [Color.poolDeep.opacity(0.55), Color.poolMid.opacity(0.30), Color.poolAqua.opacity(0.16)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.poolAqua.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Metric gauge

/// Compact 64 pt ring. The whole tile is a button when a setpoint editor
/// is attached, so a reading is adjusted where it is read instead of in
/// a separate section further down the page.
struct MetricGauge<Settings: View>: View {
    let title: String
    let displayValue: String
    let unit: String
    let value: Double
    let scale: ClosedRange<Double>
    let target: ClosedRange<Double>?
    let caption: String?
    let isPending: Bool
    let settings: () -> Settings

    init(
        title: String,
        displayValue: String,
        unit: String,
        value: Double,
        scale: ClosedRange<Double>,
        target: ClosedRange<Double>? = nil,
        caption: String? = nil,
        isPending: Bool = false,
        @ViewBuilder settings: @escaping () -> Settings
    ) {
        self.title = title
        self.displayValue = displayValue
        self.unit = unit
        self.value = value
        self.scale = scale
        self.target = target
        self.caption = caption
        self.isPending = isPending
        self.settings = settings
    }

    @State private var showSettings = false
    @State private var hovering = false

    private var fraction: Double {
        let span = scale.upperBound - scale.lowerBound
        guard span > 0 else { return 0 }
        let clamped = min(max(value, scale.lowerBound), scale.upperBound)
        return (clamped - scale.lowerBound) / span
    }

    private var inTarget: Bool {
        guard let target else { return true }
        return target.contains(value)
    }

    private var tint: Color { inTarget ? .poolAqua : .poolAmber }
    private var isAdjustable: Bool { Settings.self != EmptyView.self }

    var body: some View {
        Group {
            if isAdjustable {
                Button { showSettings = true } label: { tile }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Consigne · \(title)")
                                .font(.headline)
                            settings()
                        }
                        .padding(18)
                        .frame(width: 340)
                    }
            } else {
                tile
            }
        }
        .onHover { hovering = $0 }
    }

    private var tile: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(.quaternary, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle()
                    .trim(from: 0, to: 0.75 * fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .animation(.easeOut(duration: 0.6), value: fraction)

                // Target band drawn on the track so "am I inside the
                // range?" is answered without reading the caption.
                if let target {
                    Circle()
                        .trim(from: 0.75 * position(of: target.lowerBound),
                              to: 0.75 * position(of: target.upperBound))
                        // Always aqua: this is the band to aim for, not
                        // the current state.
                        .stroke(Color.poolAqua.opacity(0.45), style: StrokeStyle(lineWidth: 3, lineCap: .butt))
                        .rotationEffect(.degrees(135))
                        .padding(7)
                }

                VStack(spacing: -1) {
                    Text(displayValue)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }

                if isPending {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                        .offset(y: 26)
                }
            }
            .frame(width: 68, height: 68)

            HStack(spacing: 4) {
                Text(title)
                    .font(.caption.weight(.medium))
                if isAdjustable && hovering {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            Text(caption ?? " ")
                .font(.system(size: 10))
                .foregroundStyle(inTarget ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.poolAmber))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(hovering && isAdjustable ? Color.primary.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
        .help(isAdjustable ? "Cliquer pour régler la consigne" : "")
    }

    /// Where `bound` sits on the 0…1 track.
    private func position(of bound: Double) -> Double {
        let span = scale.upperBound - scale.lowerBound
        guard span > 0 else { return 0 }
        return min(max((bound - scale.lowerBound) / span, 0), 1)
    }
}

extension MetricGauge where Settings == EmptyView {
    init(
        title: String,
        displayValue: String,
        unit: String,
        value: Double,
        scale: ClosedRange<Double>,
        target: ClosedRange<Double>? = nil,
        caption: String? = nil,
        isPending: Bool = false
    ) {
        self.init(
            title: title, displayValue: displayValue, unit: unit, value: value,
            scale: scale, target: target, caption: caption, isPending: isPending,
            settings: { EmptyView() }
        )
    }
}

// MARK: - Device row

/// One idiom for every controllable device: icon, name, live state, an
/// explicit control on the right, and an optional disclosure holding the
/// settings that would otherwise crowd the row.
struct DeviceRow<Control: View, Detail: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let isActive: Bool
    let tint: Color
    let isPending: Bool
    /// Tighter row used for secondary devices laid out two per line.
    let compact: Bool
    let control: () -> Control
    let detail: () -> Detail

    init(
        icon: String,
        title: String,
        subtitle: String,
        isActive: Bool,
        tint: Color = .poolAqua,
        isPending: Bool = false,
        compact: Bool = false,
        @ViewBuilder control: @escaping () -> Control,
        @ViewBuilder detail: @escaping () -> Detail
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.isActive = isActive
        self.tint = tint
        self.isPending = isPending
        self.compact = compact
        self.control = control
        self.detail = detail
    }

    @State private var expanded = false

    private var hasDetail: Bool { Detail.self != EmptyView.self }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: compact ? 10 : 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isActive ? tint : Color.secondary.opacity(0.22))
                        .frame(width: compact ? 26 : 32, height: compact ? 26 : 32)
                    Image(systemName: icon)
                        .font(.system(size: compact ? 13 : 15, weight: .medium))
                        .foregroundStyle(isActive ? .white : .secondary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isPending {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.65)
                }

                control()

                if hasDetail {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(expanded ? "Masquer les réglages" : "Afficher les réglages")
                }
            }

            if hasDetail && expanded {
                Divider()
                    .padding(.top, 12)
                detail()
                    .padding(.top, 12)
            }
        }
        .padding(compact ? 9 : 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isActive ? tint.opacity(0.35) : .clear, lineWidth: 1)
        )
        .animation(.spring(duration: 0.3), value: isActive)
    }
}

extension DeviceRow where Detail == EmptyView {
    init(
        icon: String,
        title: String,
        subtitle: String,
        isActive: Bool,
        tint: Color = .poolAqua,
        isPending: Bool = false,
        compact: Bool = false,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.init(
            icon: icon, title: title, subtitle: subtitle, isActive: isActive,
            tint: tint, isPending: isPending, compact: compact,
            control: control, detail: { EmptyView() }
        )
    }
}

/// The standard control for an on/off device — a real switch, so every
/// row shows what it does instead of relying on the surface being tappable.
struct DeviceToggle: View {
    let isOn: Bool
    var tint: Color = .poolAqua
    let set: (Bool) -> Void

    var body: some View {
        Toggle("", isOn: Binding(get: { isOn }, set: set))
            .toggleStyle(.switch)
            .tint(tint)
            .labelsHidden()
    }
}
