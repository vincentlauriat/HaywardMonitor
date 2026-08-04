import Foundation
import os

enum HaywardAPIError: LocalizedError {
    case authenticationFailed(String)
    case notAuthenticated
    case httpError(Int, String)
    case malformedResponse(String)

    var errorDescription: String? {
        switch self {
        case .authenticationFailed(let message):
            return "Échec de connexion : \(message)"
        case .notAuthenticated:
            return "Non authentifié."
        case .httpError(let status, let context):
            return "Erreur HTTP \(status) (\(context))"
        case .malformedResponse(let context):
            return "Réponse inattendue du serveur (\(context))"
        }
    }
}

/// Client for the Hayward Europe (PoolWatch / Vistapool) cloud.
///
/// The backend is the `hayward-europe` Firebase project:
/// - auth: Google Identity Toolkit, email/password of the PoolWatch account
/// - reads: Firestore REST (`users/{uid}` for pool ids, `pools/{id}` for state)
/// - writes: `sendPoolCommand` Cloud Function with a partial document branch
actor HaywardAPI {
    private static let apiKey = "AIzaSyBLaxiyZ2nS1KgRBqWe-NY4EG7OzG5fKpE"
    private static let identityBase = "https://identitytoolkit.googleapis.com/v1/accounts"
    private static let secureTokenURL = "https://securetoken.googleapis.com/v1/token"
    private static let referrer = "https://hayward-europe.web.app/"
    private static let commandURL = "https://europe-west1-hayward-europe.cloudfunctions.net/sendPoolCommand"
    private static let firestoreBase = "https://firestore.googleapis.com/v1/projects/hayward-europe/databases/(default)/documents"
    private static let refreshBuffer: TimeInterval = 300

    private static let log = Logger(subsystem: "com.vincentlauriat.haywardmonitor", category: "api")

    private let session = URLSession.shared
    private var idToken: String?
    private var refreshToken: String?
    private(set) var localId: String?
    private var expiry: Date?

    var isAuthenticated: Bool { idToken != nil }

    // MARK: - Authentication

    func signIn(email: String, password: String) async throws {
        var request = URLRequest(url: URL(string: "\(Self.identityBase):signInWithPassword?key=\(Self.apiKey)")!)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        applyWebHeaders(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password,
            "returnSecureToken": true,
        ])

        let (data, response) = try await session.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let message = ((json["error"] as? [String: Any])?["message"] as? String) ?? "erreur inconnue"
            throw HaywardAPIError.authenticationFailed(message)
        }
        try storeTokens(json)
    }

    private func storeTokens(_ json: [String: Any]) throws {
        guard let id = (json["idToken"] ?? json["id_token"] ?? json["access_token"]) as? String,
              let refresh = (json["refreshToken"] ?? json["refresh_token"]) as? String
        else {
            throw HaywardAPIError.malformedResponse("jetons manquants")
        }
        idToken = id
        refreshToken = refresh
        if let local = (json["localId"] ?? json["local_id"] ?? json["user_id"]) as? String {
            localId = local
        }
        let expiresIn = (json["expiresIn"] ?? json["expires_in"]).flatMap { value -> TimeInterval? in
            if let s = value as? String { return TimeInterval(s) }
            if let n = value as? NSNumber { return n.doubleValue }
            return nil
        } ?? 3600
        expiry = Date().addingTimeInterval(expiresIn)
    }

    private func refreshIfNeeded() async throws {
        guard let refreshToken else { throw HaywardAPIError.notAuthenticated }
        if let expiry, Date() < expiry.addingTimeInterval(-Self.refreshBuffer) { return }

        var request = URLRequest(url: URL(string: "\(Self.secureTokenURL)?key=\(Self.apiKey)")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        applyWebHeaders(&request)
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let message = ((json["error"] as? [String: Any])?["message"] as? String) ?? "erreur inconnue"
            throw HaywardAPIError.authenticationFailed(message)
        }
        try storeTokens(json)
    }

    private func applyWebHeaders(_ request: inout URLRequest) {
        request.setValue(Self.referrer, forHTTPHeaderField: "Referer")
        request.setValue("https://hayward-europe.web.app", forHTTPHeaderField: "Origin")
    }

    func signOut() {
        idToken = nil
        refreshToken = nil
        localId = nil
        expiry = nil
    }

    // MARK: - Firestore reads

    private func fetchDocument(path: String) async throws -> [String: Any] {
        try await refreshIfNeeded()
        guard let idToken else { throw HaywardAPIError.notAuthenticated }
        var request = URLRequest(url: URL(string: "\(Self.firestoreBase)/\(path)")!)
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw HaywardAPIError.httpError(status, "Firestore \(path)")
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw HaywardAPIError.malformedResponse("Firestore \(path)")
        }
        return FirestoreDecoder.decodeDocument(json)
    }

    /// Pool ids registered on the signed-in account.
    func fetchPoolIds() async throws -> [String] {
        guard let localId else { throw HaywardAPIError.notAuthenticated }
        let user = try await fetchDocument(path: "users/\(localId)")
        return user["pools"] as? [String] ?? []
    }

    /// Full raw pool document (already unwrapped from Firestore envelopes).
    func fetchPoolDocument(poolId: String) async throws -> [String: Any] {
        try await fetchDocument(path: "pools/\(poolId)")
    }

    // MARK: - Commands

    /// Set a value on the device, mirroring the official web app: the
    /// containing branch of the current document is cloned, mutated, and
    /// sent as the `changes` payload of a WRP operation.
    func setValue(poolId: String, poolData: [String: Any], path: String, value: Any) async throws {
        try await setValues(poolId: poolId, poolData: poolData, values: [(path, value)])
    }

    /// Set several values living in the same branch in a single command
    /// (e.g. `light.status` + `light.mode`). The branch is derived from
    /// the first path.
    func setValues(poolId: String, poolData: [String: Any], values: [(path: String, value: Any)]) async throws {
        guard let primary = values.first else { return }
        var branch = Self.extractBranch(from: poolData, path: primary.path)
        for (path, value) in values {
            Self.setInDict(&branch, path: path.split(separator: ".").map(String.init), value: value)
        }

        // Electrolysis boost needs companion flags, like the official client.
        if let boost = values.first(where: { $0.path == "hidro.cloration_enabled" }) {
            var hidro = branch["hidro"] as? [String: Any] ?? [:]
            let enabled = (boost.value as? Int ?? 0) != 0
            hidro["cloration_enabled"] = enabled ? 1 : 0
            hidro["reduction"] = enabled ? 1 : 0
            hidro["disable"] = 1
            branch["hidro"] = hidro
        }
        let path = primary.path
        let value = primary.value

        let changesData = try JSONSerialization.data(withJSONObject: branch)
        let changes = String(data: changesData, encoding: .utf8) ?? "{}"
        let payload: [String: Any] = [
            "gateway": poolData["wifi"] as? String ?? "",
            "poolId": poolId,
            "operation": "WRP",
            "changes": changes,
            "source": "web",
        ]
        let gateway = poolData["wifi"] as? String ?? "<absent>"
        Self.log.warning("setValue \(path, privacy: .public) = \(String(describing: value), privacy: .public) gateway=\(gateway, privacy: .public) changes=\(changes, privacy: .public)")
        try await sendCommand(payload)
    }

    private func sendCommand(_ payload: [String: Any]) async throws {
        try await refreshIfNeeded()
        guard let idToken else { throw HaywardAPIError.notAuthenticated }
        var request = URLRequest(url: URL(string: Self.commandURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let body = String(data: data, encoding: .utf8) ?? ""
        Self.log.warning("sendPoolCommand status=\(status) body=\(body, privacy: .public)")
        guard status >= 200, status < 400 else {
            let detail = body.isEmpty ? "sendPoolCommand" : "sendPoolCommand : \(body.prefix(300))"
            throw HaywardAPIError.httpError(status, detail)
        }
    }

    // MARK: - Branch helpers

    /// Clone the branch of the document containing `path`. Deep paths
    /// (4+ segments, e.g. `relays.relay1.info.onoff`) are narrowed to two
    /// levels so only the target sub-branch is sent.
    static func extractBranch(from data: [String: Any], path: String) -> [String: Any] {
        let keys = path.split(separator: ".").map(String.init)
        guard let root = keys.first else { return [:] }
        if keys.count >= 4, keys.count > 1 {
            let second = keys[1]
            let rootData = data[root] as? [String: Any] ?? [:]
            return [root: [second: rootData[second] ?? [:]]]
        }
        return [root: data[root] ?? [:]]
    }

    static func setInDict(_ dict: inout [String: Any], path: [String], value: Any) {
        guard let first = path.first else { return }
        if path.count == 1 {
            dict[first] = value
            return
        }
        var child = dict[first] as? [String: Any] ?? [:]
        setInDict(&child, path: Array(path.dropFirst()), value: value)
        dict[first] = child
    }
}
