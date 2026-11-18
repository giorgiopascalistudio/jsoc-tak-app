import Foundation
import Security

// MARK: - Modelli (risposte di console_server.py, uguale su PC e server)

struct ServerStatus: Decodable {
    struct Service: Decodable, Identifiable { let nome: String; let attivo: Bool; var id: String { nome } }
    var macchina: String? = nil
    let ora: String
    let uptime_ore: Double
    let carico: [String]
    let temperatura: Double?
    let throttled: String
    let memoria_pct: Int
    let disco_pct: Int
    let disco_libero_gb: Double
    let wifi: String
    let lan: Bool
    let tailscale: String
    let funnel: Int
    var batteria: Int? = nil
    var alimentato: Bool? = nil
    var sync: String? = nil
    let servizi: [Service]

    var tuttoOk: Bool { servizi.allSatisfy(\.attivo) && tailscale == "Running" && throttled == "0x0" }
}

struct Operator: Decodable, Identifiable {
    let callsign: String
    let utente: String
    let app: String
    let collegato: Bool
    let ultimo: String
    let lat: Double?
    let lon: Double?
    let batteria: Double?
    let pos_ora: String
    var id: String { callsign }
    var isBot: Bool { callsign.hasPrefix("HQI") }
}

struct ClaudeEvent: Codable, Hashable {
    let t: String          // sessione | testo | strumento | esito | fine | log
    let s: String
    var errore: Bool? = nil
    var sessione: String? = nil
    var secondi: Int? = nil
}

struct ClaudeSession: Decodable, Identifiable { let id: String; let titolo: String; let ora: String }

struct JobPage<T: Decodable>: Decodable {
    let righe: [T]
    let totale: Int
    let fine: Bool
    let codice: Int?
    let cartella: String
}

struct DocIndex: Decodable {
    struct File: Codable, Hashable { let p: String; let s: Int; let m: Int }
    let macchina: String
    let rev: String
    let file: [File]
}

struct SendResult: Decodable { let percorso: String; let job: String? }

private struct JobStart: Decodable { let job: String }
private struct ServerError: Decodable { let errore: String }
private struct Ping: Decodable { let macchina: String }

// MARK: - Macchine

/// Le due macchine con la console: il PC di casa (più potente, Claude principale) e il server (Raspberry, TAK).
enum Target: String, Codable, CaseIterable, Identifiable {
    case pc, server
    var id: String { rawValue }
    var label: String { self == .pc ? "PC" : "Server" }
    var icon: String { self == .pc ? "desktopcomputer" : "server.rack" }
    var defaultURL: String { self == .pc ? "" : "" }
    var tokenKey: String { self == .pc ? "pc.token" : "server.token" }
    var urlKey: String { self == .pc ? "pc.url" : "server.url" }
}

enum ServerFailure: LocalizedError {
    case notConfigured(Target), unauthorized, http(Int, String), unreachable(String)
    var errorDescription: String? {
        switch self {
        case .notConfigured(let t): return "\(t.label) non collegato: tocca l'ingranaggio e scansiona il QR."
        case .unauthorized: return "Codice di accesso errato."
        case .http(let c, let m): return "Errore \(c): \(m)"
        case .unreachable(let m): return "Non raggiungibile. Tailscale è acceso sul telefono?\n\(m)"
        }
    }
}

// MARK: - Client

@MainActor
final class ServerClient: ObservableObject {
    static let defaultURL = Target.server.defaultURL

    @Published var urls: [Target: String] = [:]
    @Published var tokens: [Target: String] = [:]
    /// Dove vanno Claude, biblioteca e invii: il PC se risponde, altrimenti il server.
    @Published private(set) var brain: Target = .pc
    @Published private(set) var online: [Target: Bool] = [:]
    @Published private(set) var lastProbe: Date?

    init() {
        for t in Target.allCases {
            urls[t] = UserDefaults.standard.string(forKey: t.urlKey) ?? t.defaultURL
            tokens[t] = Keychain.get(t.tokenKey) ?? ""
        }
        brain = configured(.pc) ? .pc : .server
    }

    // compatibilità con le schermate del server TAK
    var baseURL: String {
        get { urls[.server] ?? Target.server.defaultURL }
        set { setURL(newValue, for: .server) }
    }
    var token: String {
        get { tokens[.server] ?? "" }
        set { setToken(newValue, for: .server) }
    }
    var configured: Bool { configured(.server) }

    /// Nessuna macchina risponde: quasi sempre Tailscale spento sul telefono.
    var nessunoRisponde: Bool {
        lastProbe != nil && Target.allCases.contains(where: configured) && !Target.allCases.contains { online[$0] == true }
    }

    func configured(_ t: Target) -> Bool { !(tokens[t] ?? "").isEmpty && URL(string: urls[t] ?? "") != nil }

    func setURL(_ u: String, for t: Target) {
        urls[t] = u
        UserDefaults.standard.set(u, forKey: t.urlKey)
    }

    func setToken(_ s: String, for t: Target) {
        tokens[t] = s
        Keychain.set(s, for: t.tokenKey)
    }

    /// QR: remida-server://?u=<url>&t=<token>&n=pc|server  (senza n si deduce dall'indirizzo), oppure solo il token.
    @discardableResult
    func pair(with code: String, default target: Target = .server) -> Target? {
        let s = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if let c = URLComponents(string: s), c.scheme == "remida-server" {
            let items = Dictionary((c.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
            guard let tok = items["t"], !tok.isEmpty else { return nil }
            let u = items["u"] ?? ""
            let t: Target = Target(rawValue: items["n"] ?? "") ?? (u.contains("0.0.0.0") ? .pc : .server)
            if !u.isEmpty { setURL(u, for: t) }
            setToken(tok, for: t)
            Task { await probe() }
            return t
        }
        guard s.count >= 20, !s.contains(" ") else { return nil }
        setToken(s, for: target)
        Task { await probe() }
        return target
    }

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    private let quick: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 6
        cfg.timeoutIntervalForResource = 8
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    private let bulk: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 120
        cfg.timeoutIntervalForResource = 3600
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    private func makeRequest(_ path: String, _ t: Target) throws -> URLRequest {
        guard configured(t), let url = URL(string: (urls[t] ?? "") + path) else { throw ServerFailure.notConfigured(t) }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(tokens[t] ?? "")", forHTTPHeaderField: "Authorization")
        return req
    }

    private func check(_ data: Data, _ resp: URLResponse) throws {
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw ServerFailure.unauthorized }
        guard code == 200 else {
            throw ServerFailure.http(code, (try? JSONDecoder().decode(ServerError.self, from: data).errore) ?? "")
        }
    }

    private func request<T: Decodable>(_ path: String, body: [String: Any]? = nil, on t: Target = .server,
                                       using s: URLSession? = nil) async throws -> T {
        var req = try makeRequest(path, t)
        if let body {
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data, resp: URLResponse
        do { (data, resp) = try await (s ?? session).data(for: req) } catch { throw ServerFailure.unreachable(error.localizedDescription) }
        try check(data, resp)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Controlla chi risponde e sceglie il "cervello": PC se acceso, altrimenti server.
    private var probing = false

    /// Controlla PC e server insieme; entro 10 s riusa l'ultimo esito (con il relè ogni giro costa ~1 s).
    func probe(force: Bool = false) async {
        if !force, let l = lastProbe, Date().timeIntervalSince(l) < 10 { return }
        if probing { return }
        probing = true
        defer { probing = false }
        async let a = ping(.pc)
        async let b = ping(.server)
        let (pc, srv) = await (a, b)
        online[.pc] = pc
        online[.server] = srv
        lastProbe = Date()
        brain = online[.pc] == true ? .pc : (online[.server] == true ? .server : (configured(.pc) ? .pc : .server))
    }

    private func ping(_ t: Target) async -> Bool {
        guard configured(t) else { return false }
        let p: Ping? = try? await request("/ping", on: t, using: quick)
        return p != nil
    }

    // server TAK (o la macchina indicata)
    func status(on t: Target = .server) async throws -> ServerStatus { try await request("/stato", on: t) }
    func operators() async throws -> [Operator] { try await request("/operatori") }
    func sessions(on t: Target) async throws -> [ClaudeSession] { try await request("/claude/sessioni", on: t) }

    func runCommand(_ cmd: String, on t: Target = .server) async throws -> String {
        let r: JobStart = try await request("/terminale", body: ["cmd": cmd], on: t); return r.job
    }

    func askClaude(_ prompt: String, session: String?, on t: Target) async throws -> String {
        var body: [String: Any] = ["prompt": prompt]
        if let session { body["sessione"] = session }
        let r: JobStart = try await request("/claude", body: body, on: t); return r.job
    }

    func page<T: Decodable>(_ job: String, from: Int, on t: Target = .server) async throws -> JobPage<T> {
        try await request("/job/\(job)?da=\(from)", on: t)
    }

    func stop(_ job: String, on t: Target = .server) async {
        struct Ok: Decodable { let ok: Bool }
        let _: Ok? = try? await request("/job/\(job)/stop", body: [:], on: t)
    }

    // biblioteca
    func docIndex(on t: Target) async throws -> DocIndex { try await request("/docs/indice", on: t) }

    func downloadDoc(_ path: String, on t: Target) async throws -> URL {
        let q = path.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? path
        let req = try makeRequest("/docs/file?p=\(q)", t)
        let tmp: URL, resp: URLResponse
        do { (tmp, resp) = try await bulk.download(for: req) } catch { throw ServerFailure.unreachable(error.localizedDescription) }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ServerFailure.http(code, path) }
        return tmp
    }

    /// Manda un file alla macchina: finisce in Inviati/ della biblioteca e (se analizza) parte Claude.
    func send(file: URL, name: String, fascicolo: String?, note: String, analyze: Bool, session: String?,
              on t: Target) async throws -> SendResult {
        var q = URLComponents()
        q.queryItems = [.init(name: "nome", value: name), .init(name: "fascicolo", value: fascicolo ?? ""),
                        .init(name: "nota", value: note), .init(name: "analizza", value: analyze ? "1" : "0"),
                        .init(name: "sessione", value: session ?? "")]
        var req = try makeRequest("/invia?" + (q.percentEncodedQuery ?? ""), t)
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let data: Data, resp: URLResponse
        do { (data, resp) = try await bulk.upload(for: req, fromFile: file) } catch { throw ServerFailure.unreachable(error.localizedDescription) }
        try check(data, resp)
        return try JSONDecoder().decode(SendResult.self, from: data)
    }
}

extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var c = CharacterSet.urlQueryAllowed
        c.remove(charactersIn: "&=+?#")
        return c
    }()
}

// MARK: - Portachiavi (il codice d'accesso vale come una password della macchina)

enum Keychain {
    static func set(_ value: String, for key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
        guard !value.isEmpty else { return }
        var add = q
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}
