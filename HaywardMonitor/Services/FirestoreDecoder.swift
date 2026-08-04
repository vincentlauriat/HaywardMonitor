import Foundation

/// Decodes Firestore REST API typed documents into plain Swift dictionaries.
///
/// The Firestore REST API wraps every value in a type envelope, e.g.
/// `{"integerValue": "5"}` or `{"mapValue": {"fields": {...}}}`. This
/// decoder unwraps them recursively so the rest of the app works with
/// `[String: Any]` mirroring the raw pool document.
enum FirestoreDecoder {

    /// Decode a full document response (the object containing `fields`).
    static func decodeDocument(_ json: [String: Any]) -> [String: Any] {
        guard let fields = json["fields"] as? [String: Any] else { return [:] }
        return decodeFields(fields)
    }

    static func decodeFields(_ fields: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in fields {
            guard let envelope = value as? [String: Any] else { continue }
            if let decoded = decodeValue(envelope) {
                result[key] = decoded
            }
        }
        return result
    }

    static func decodeValue(_ envelope: [String: Any]) -> Any? {
        if let s = envelope["stringValue"] as? String { return s }
        if let i = envelope["integerValue"] {
            if let str = i as? String, let n = Int(str) { return n }
            if let n = i as? Int { return n }
        }
        if let d = envelope["doubleValue"] {
            if let n = d as? Double { return n }
            if let str = d as? String, let n = Double(str) { return n }
        }
        if let b = envelope["booleanValue"] as? Bool { return b }
        if envelope.keys.contains("nullValue") { return NSNull() }
        if let t = envelope["timestampValue"] as? String { return t }
        if let m = envelope["mapValue"] as? [String: Any] {
            let fields = m["fields"] as? [String: Any] ?? [:]
            return decodeFields(fields)
        }
        if let a = envelope["arrayValue"] as? [String: Any] {
            let values = a["values"] as? [[String: Any]] ?? []
            return values.compactMap { decodeValue($0) }
        }
        return nil
    }
}
