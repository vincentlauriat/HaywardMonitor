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
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
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

// MARK: - Hero banner

struct HeroBanner: View {
    let pool: PoolState
    let lastUpdate: Date?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [.poolDeep, .poolMid, .poolAqua.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: "water.waves")
                .font(.system(size: 130, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.08))
                .offset(x: -10, y: 14)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(pool.name)
                        .font(.title.bold())
                        .foregroundStyle(.white)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(pool.isOnline ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(pool.isOnline ? "En ligne" : "Hors ligne")
                    }
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.15), in: Capsule())

                    if let lastUpdate {
                        Text("Mis à jour à \(lastUpdate.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                Spacer()
                if let temperature = pool.temperature {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(temperature.formatted(.number.precision(.fractionLength(1))))
                            .font(.system(size: 58, weight: .semibold, design: .rounded))
                        Text("°C")
                            .font(.title2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .foregroundStyle(.white)
                }
            }
            .padding(24)
        }
        .frame(height: 150)
    }
}

// MARK: - Ring gauge

/// Circular gauge showing where a measurement sits inside its displayed
/// scale, tinted aqua when inside the target band and amber when out.
struct RingGauge: View {
    let title: String
    let value: Double
    let displayValue: String
    let unit: String
    let scale: ClosedRange<Double>
    var target: ClosedRange<Double>? = nil
    var caption: String? = nil

    private var fraction: Double {
        let clamped = min(max(value, scale.lowerBound), scale.upperBound)
        return (clamped - scale.lowerBound) / (scale.upperBound - scale.lowerBound)
    }

    private var inTarget: Bool {
        guard let target else { return true }
        return target.contains(value)
    }

    private var tint: Color { inTarget ? .poolAqua : .poolAmber }

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(.quaternary, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle()
                    .trim(from: 0, to: 0.75 * fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .animation(.easeOut(duration: 0.6), value: fraction)

                VStack(spacing: 0) {
                    Text(displayValue)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 96, height: 96)

            Text(caption ?? " ")
                .font(.caption)
                .foregroundStyle(inTarget ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.poolAmber))
        }
        .frame(maxWidth: .infinity)
        .card()
    }
}

// MARK: - Control tile

/// HomeKit-style tile: the whole surface toggles the device; tinted
/// when active.
struct ControlTile: View {
    let title: String
    let icon: String
    let isActive: Bool
    var subtitle: String? = nil
    var activeColor: Color = .poolAqua
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isActive ? activeColor : Color.secondary.opacity(0.25))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(isActive ? .white : .secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle ?? (isActive ? "Activé" : "Désactivé"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isActive ? activeColor.opacity(0.16) : Color.secondary.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isActive ? activeColor.opacity(0.45) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.3), value: isActive)
    }
}
