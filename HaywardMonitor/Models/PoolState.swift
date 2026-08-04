import Foundation

/// Typed view over the raw pool document.
///
/// The cloud encodes numbers inconsistently across firmware revisions
/// (`"747"` vs `747`), so every accessor coerces defensively. Scale
/// factors mirror the official clients: pH ×100, electrolysis ×10,
/// redox in raw millivolts.
struct PoolState {
    let raw: [String: Any]

    init(raw: [String: Any]) {
        self.raw = raw
    }

    // MARK: - Raw access

    func value(at path: String) -> Any? {
        var current: Any? = raw
        for key in path.split(separator: ".") {
            current = (current as? [String: Any])?[String(key)]
        }
        return current
    }

    func int(_ path: String) -> Int? {
        switch value(at: path) {
        case let n as Int: return n
        case let n as Double: return Int(n)
        case let b as Bool: return b ? 1 : 0
        case let s as String: return Int(s) ?? Double(s).map(Int.init)
        default: return nil
        }
    }

    func double(_ path: String) -> Double? {
        switch value(at: path) {
        case let n as Double: return n
        case let n as Int: return Double(n)
        case let s as String: return Double(s)
        default: return nil
        }
    }

    func bool(_ path: String) -> Bool? {
        switch value(at: path) {
        case let b as Bool: return b
        case let n as Int: return n != 0
        case let s as String: return s == "1" || s.lowercased() == "true"
        default: return nil
        }
    }

    func string(_ path: String) -> String? {
        value(at: path) as? String
    }

    // MARK: - Identity & status

    var name: String {
        if let names = value(at: "form.names") as? [[String: Any]],
           let first = names.first?["name"] as? String {
            return first
        }
        return string("form.name") ?? "Piscine"
    }

    var isOnline: Bool { bool("present") ?? false }
    var gateway: String? { string("wifi") }
    var rssi: Int? { int("main.RSSI") }

    // MARK: - Capabilities

    var hasPH: Bool { bool("main.hasPH") ?? false }
    var hasRX: Bool { bool("main.hasRX") ?? false }
    var hasCL: Bool { bool("main.hasCL") ?? false }
    var hasCD: Bool { bool("main.hasCD") ?? false }
    var hasUV: Bool { bool("main.hasUV") ?? false }
    var hasHidro: Bool { bool("main.hasHidro") ?? false }
    var isElectrolysis: Bool { bool("hidro.is_electrolysis") ?? true }
    var hideTemperature: Bool { bool("main.hideTemperature") ?? false }
    var hideLighting: Bool { bool("main.hideLighting") ?? false }
    var hideRelays: Bool { bool("main.hideRelays") ?? false }
    var hideFiltration: Bool { bool("main.hideFiltration") ?? false }

    // MARK: - Measurements

    var temperature: Double? { hideTemperature ? nil : double("main.temperature") }
    var ph: Double? { int("modules.ph.current").map { Double($0) / 100 } }
    var phLow: Double? { int("modules.ph.status.low_value").map { Double($0) / 100 } }
    var phHigh: Double? { int("modules.ph.status.high_value").map { Double($0) / 100 } }
    var redox: Int? { int("modules.rx.current") }
    var redoxSetpoint: Int? { int("modules.rx.status.value") }
    var chlorine: Double? { int("modules.cl.current").map { Double($0) / 100 } }
    var conductivity: Double? { int("modules.cd.current").map { Double($0) / 100 } }

    /// Current production in g/h.
    var electrolysisProduction: Double? { int("hidro.current").map { Double($0) / 10 } }
    /// Production setpoint in g/h.
    var electrolysisSetpoint: Double? { int("hidro.level").map { Double($0) / 10 } }
    var electrolysisMax: Double {
        int("hidro.maxAllowedValue").map { Double($0) / 10 } ?? 50
    }
    var boostActive: Bool { bool("hidro.cloration_enabled") ?? false }
    var coverActive: Bool { bool("hidro.cover_enabled") ?? false }
    var cellPartialHours: Double? { int("hidro.cellPartialTime").map { Double($0) / 3600 } }
    var cellTotalHours: Double? { int("hidro.cellTotalTime").map { Double($0) / 3600 } }

    // MARK: - Filtration, light, relays

    var filtrationOn: Bool { bool("filtration.status") ?? false }
    var filtrationMode: PumpMode { PumpMode(rawValue: int("filtration.mode") ?? 0) ?? .manual }
    var pumpSpeed: PumpSpeed? { int("filtration.manVel").flatMap(PumpSpeed.init(rawValue:)) }
    var hasPumpSpeed: Bool { (int("filtration.pumpType") ?? 0) > 0 }
    var lightOn: Bool { bool("light.status") ?? false }
    /// 0 = manual, 1 = scheduled.
    var lightScheduled: Bool { (int("light.mode") ?? 0) == 1 }
    /// Schedule bounds in seconds since midnight.
    var lightFrom: Int { int("light.from") ?? 72000 }
    var lightTo: Int { int("light.to") ?? 86340 }

    var lightSelection: LightSelection {
        if lightScheduled { return .scheduled }
        return lightOn ? .on : .off
    }

    var relays: [RelayState] {
        (1...4).compactMap { index in
            guard let relay = value(at: "relays.relay\(index)") as? [String: Any] else { return nil }
            let name = (relay["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let info = relay["info"] as? [String: Any]
            let onoff = Self.truthy(info?["onoff"])
            let status = Self.truthy(info?["status"])
            return RelayState(index: index, name: name ?? "Relais \(index)", isOn: onoff || status)
        }
    }

    private static func truthy(_ value: Any?) -> Bool {
        switch value {
        case let b as Bool: return b
        case let n as Int: return n != 0
        case let s as String: return s == "1" || s.lowercased() == "true"
        default: return false
        }
    }
}

struct RelayState: Identifiable {
    let index: Int
    let name: String
    let isOn: Bool
    var id: Int { index }
}

enum LightSelection: Int, CaseIterable, Identifiable {
    case off, on, scheduled
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .on: return "On"
        case .scheduled: return "Programmé"
        }
    }
}

enum PumpMode: Int, CaseIterable, Identifiable {
    case manual = 0, auto, heat, smart, intel
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .manual: return "Manuel"
        case .auto: return "Auto"
        case .heat: return "Chauffage"
        case .smart: return "Smart"
        case .intel: return "Intel"
        }
    }
}

enum PumpSpeed: Int, CaseIterable, Identifiable {
    case slow = 0, medium, high
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .slow: return "Lente"
        case .medium: return "Moyenne"
        case .high: return "Rapide"
        }
    }
}
