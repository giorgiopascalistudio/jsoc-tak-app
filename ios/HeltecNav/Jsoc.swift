import QuartzCore
import Foundation
import SwiftUI
import CoreLocation
import CoreImage.CIFilterBuiltins

// MARK: - Modelli del server JSOC TAK (protocollo nostro, JSON su HTTPS)

struct JUtente: Codable, Identifiable, Hashable {
    let id: Int
    let nome: String
    let callsign: String
    let ruolo: String
    var attivo: Int? = 1
    var direttivo: Bool { ruolo == "direttivo" }
}

struct JPunto: Codable, Identifiable, Hashable {
    let id: Int
    let evento: Int
    let nome: String
    let tipo: String
    let lat: Double
    let lon: Double
    let note: String?
    let autore: Int?
    var stato: String? = nil
    var resoconto: String? = nil
    var cartella: String? = nil
    var indagine: [JIndagine]? = nil
    var squadra: String? = nil
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    var fatto: Bool { stato == "fatto" }
    var obiettivo: Bool { tipo == "obj" || tipo == "obiettivo" }
}

struct JIndagine: Codable, Identifiable, Hashable {
    let id: Int
    let punto: Int
    let autore: Int?
    let testo: String
    let ipotesi: Int?
    let ts: Double
    let callsign: String?
}

struct JFlusso: Codable, Identifiable, Hashable {
    let nome: String
    let pronto: Bool
    let lettori: Int
    let tracce: [String]
    var id: String { nome }
}

struct JArea: Codable, Identifiable, Hashable {
    let id: Int
    let evento: Int
    let nome: String
    let tipo: String
    let coord: [[Double]]
}

struct JMembro: Codable, Identifiable, Hashable {
    let id: Int
    let nome: String
    let callsign: String
    let ruolo: String
    let squadra: String?
}

struct JEvento: Codable, Identifiable, Hashable {
    let id: Int
    let nome: String
    let tipo: String
    let inizio: String?
    let fine: String?
    let luogo: String?
    let lat: Double?
    let lon: Double?
    let note: String?
    let archiviato: Int?
    let mio_ruolo: String?
    var mia_risposta: String? = nil
    // stile Spond (server 0.7)
    var copertina: String? = nil
    var interno: Int? = nil
    var stato: String? = nil
    var scadenza: String? = nil
    var posti: Int? = nil
    var quota: Double? = nil
    var domande: [String]? = nil
    var host: String? = nil
    var n_si: Int? = nil
    var n_no: Int? = nil
    var n_attesa: Int? = nil
    var nascosto: Int? = nil
    var creato_da: Int? = nil
    var breve: String? = nil          // tavola 37: nota corta nella riga ("solo direttivo", "deleghe aperte")
    var privato: Bool { (nascosto ?? 0) != 0 }
    var annullato: Bool { stato == "annullato" }
    var punti: [JPunto]? = nil
    var aree: [JArea]? = nil
    var disegni: [JDisegno]? = nil
    var membri: [JMembro]? = nil
    var staff: Bool { mio_ruolo == "staff" }
    var membro: Bool { mio_ruolo != nil }
    var dataInizio: Date? { JEvento.data(inizio) }
    var dataFine: Date? { JEvento.data(fine) }

    /// Le date arrivano come testo. Prima ogni lettura creava 2-3 formattatori nuovi (costosi): il calendario della Home
    /// ne faceva centinaia a ogni ridisegno ed era la causa dei blocchi di 0,2-0,3 s. Ora formattatori fissi + cache.
    private static let lockDate = NSLock()
    private static var cacheDate: [String: Date?] = [:]
    private static let iso1 = ISO8601DateFormatter()
    private static let iso2: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    private static let formati: [DateFormatter] = ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"].map { fmt in
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = fmt; return f
    }

    static func data(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        lockDate.lock(); defer { lockDate.unlock() }
        if let c = cacheDate[s] { return c }
        var d = iso1.date(from: s) ?? iso2.date(from: s)
        if d == nil { for f in formati { if let x = f.date(from: s) { d = x; break } } }
        if cacheDate.count > 5000 { cacheDate.removeAll() }
        cacheDate[s] = d
        return d
    }

    /// in corso, prossimo o passato rispetto ad adesso
    var fase: Int {
        let ora = Date()
        let i = dataInizio ?? .distantFuture
        let f = dataFine ?? i.addingTimeInterval(6 * 3600)
        if archiviato == 1 || f < ora { return 2 }
        return i <= ora ? 0 : 1
    }

    var icona: String {
        switch tipo {
        case "allenamento": return "figure.run"
        case "riunione": return "person.3.fill"
        case "gara": return "flag.checkered"
        default: return "calendar"
        }
    }
}

struct JCompagno: Codable, Identifiable, Hashable {
    let id: Int
    let callsign: String
    let nome: String?
    let squadra: String?
    let lat: Double
    let lon: Double
    let acc: Double?
    let rotta: Double?
    let vel: Double?
    let batt: Double?
    let dir: Double?
    let ts: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    var eta: TimeInterval { Date().timeIntervalSince1970 - ts }
}

struct JMessaggio: Codable, Identifiable, Hashable {
    let id: Int
    let evento: Int
    let autore: Int?
    let testo: String
    let lat: Double?
    let lon: Double?
    let ts: Double
    let callsign: String?
    var dest: Int? = nil
    var allegato: String? = nil
}

struct JFile: Codable, Hashable {
    let percorso: String
    let dim: Int
    let agg: Double
}

struct JInvito: Codable { let codice: String; let link: String; let ruolo: String }

private struct JErrore: Decodable { let errore: String }

enum JsocErrore: LocalizedError {
    case nonCollegato, server(String), rete(String)
    var errorDescription: String? {
        switch self {
        case .nonCollegato: return "Non sei ancora entrato: inquadra il QR dell'invito."
        case .server(let s): return s
        case .rete(let s): return "Il server non risponde (\(s))."
        }
    }
}

// MARK: - Client

/// Collegamento al server JSOC TAK. Indirizzo e gettone arrivano dal QR dell'invito: niente IP da scrivere.
@MainActor
final class JsocClient: ObservableObject {
    static let shared = JsocClient()

    @Published private(set) var indirizzo: String = UserDefaults.standard.string(forKey: "jsoc.url") ?? ""
    @Published private(set) var utente: JUtente?
    @Published private(set) var online = false
    @Published var ultimoErrore: String?
    private var gettone: String = Keychain.get("jsoc.gettone") ?? ""

    var collegato: Bool { Anteprima.attiva || (!gettone.isEmpty && URL(string: indirizzo) != nil) }

    /// Seconda strada verso il server, dentro Tailscale ma per indirizzo numerico: serve ai dispositivi
    /// su cui il nome del server non si risolve (DNS di Tailscale spento) e danno errore TLS.
    var alternativo: String { UserDefaults.standard.string(forKey: "jsoc.url2") ?? "" }

    static func erroreDiStrada(_ e: Error) -> Bool {
        guard let u = e as? URLError else { return false }
        return [.secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid,
                .serverCertificateHasUnknownRoot, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .clientCertificateRejected].contains(u.code)
    }

    /// Il server dice qual è il suo indirizzo pubblico (raggiungibile anche senza Tailscale):
    /// se è diverso da quello con cui siamo entrati, ci passo e tengo il vecchio come strada di riserva.
    func aggiornaIndirizzo() async {
        guard collegato, let u = URL(string: indirizzo + "/api/stato") else { return }
        struct Stato: Decodable { let indirizzo: String?; var config: [String: Bool]? = nil }
        var r = URLRequest(url: u, timeoutInterval: 10)
        r.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (d, _) = try? await URLSession.shared.data(for: r),
              let s = try? JSONDecoder().decode(Stato.self, from: d) else { return }
        for (k, v) in s.config ?? [:] { UserDefaults.standard.set(v, forKey: "cfg." + k) }
        guard var nuovo = s.indirizzo, !nuovo.isEmpty else { return }
        if nuovo.hasSuffix("/") { nuovo.removeLast() }
        guard nuovo != indirizzo, let prova = URL(string: nuovo + "/api/stato"),
              let (_, resp) = try? await URLSession.shared.data(for: URLRequest(url: prova, timeoutInterval: 10)),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
        if alternativo.isEmpty { UserDefaults.standard.set(indirizzo, forKey: "jsoc.url2") }
        indirizzo = nuovo
        UserDefaults.standard.set(nuovo, forKey: "jsoc.url")
        Diagnostica.passo("indirizzo pubblico")
    }

    /// passa all'altra strada (e ci resta) se quella attuale non funziona
    private func cambiaStrada(_ r: URLRequest) -> URLRequest? {
        let alt = alternativo
        guard !alt.isEmpty, alt != indirizzo, let u = r.url?.absoluteString, u.hasPrefix(indirizzo),
              let nuovo = URL(string: alt + u.dropFirst(indirizzo.count)) else { return nil }
        indirizzo = alt
        UserDefaults.standard.set(alt, forKey: "jsoc.url")
        var x = r; x.url = nuovo
        return x
    }

    private let sessione: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    init() {
        if let d = UserDefaults.standard.data(forKey: "jsoc.utente") { utente = try? JSONDecoder().decode(JUtente.self, from: d) }
        if Anteprima.attiva { utente = Anteprima.utente }
    }

    /// Legge il link dell'invito: jsoctak://entra?u=<indirizzo>&c=<codice>. Restituisce (indirizzo, codice).
    static func leggiInvito(_ s: String) -> (String, String)? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = URLComponents(string: t), c.scheme == "jsoctak" else { return nil }
        let q = Dictionary((c.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        guard let u = q["u"], !u.isEmpty, let cod = q["c"], !cod.isEmpty else { return nil }
        return (u, cod)
    }

    /// salva l'indirizzo di riserva dell'invito. NON va chiamata dentro `body`: scrivere le impostazioni
    /// mentre si disegna la schermata la fa ridisegnare all'infinito (era il blocco su iPad)
    static func salvaAlternativo(_ s: String) {
        guard let c = URLComponents(string: s.trimmingCharacters(in: .whitespacesAndNewlines)), c.scheme == "jsoctak",
              let a = c.queryItems?.first(where: { $0.name == "a" })?.value, !a.isEmpty else { return }
        let v = a.hasSuffix("/") ? String(a.dropLast()) : a
        if UserDefaults.standard.string(forKey: "jsoc.url2") != v { UserDefaults.standard.set(v, forKey: "jsoc.url2") }
    }

    func entra(indirizzo u: String, codice: String, nome: String, callsign: String) async throws {
        struct Risposta: Decodable { let gettone: String; let utente: JUtente }
        let base = u.hasSuffix("/") ? String(u.dropLast()) : u
        guard let url = URL(string: base + "/api/entra") else { throw JsocErrore.server("Indirizzo non valido") }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: ["codice": codice, "nome": nome, "callsign": callsign, "dispositivo": UIDevice.current.model])
        var dove = base
        let ris: Risposta
        do { ris = try await esegui(r, riprova: false) }
        catch JsocErrore.rete(_) where !alternativo.isEmpty && alternativo != base {
            // il nome del server non funziona su questo dispositivo: provo l'indirizzo Tailscale numerico
            dove = alternativo
            r.url = URL(string: dove + "/api/entra")
            ris = try await esegui(r, riprova: false)
        }
        indirizzo = dove
        gettone = ris.gettone
        UserDefaults.standard.set(base, forKey: "jsoc.url")
        Keychain.set(ris.gettone, for: "jsoc.gettone")
        salvaUtente(ris.utente)
        if !online { online = true }
    }

    func esci() {
        gettone = ""
        Keychain.set("", for: "jsoc.gettone")
        utente = nil
        UserDefaults.standard.removeObject(forKey: "jsoc.utente")
    }

    private func salvaUtente(_ u: JUtente) {
        guard utente != u else { return }
        utente = u
        if let d = try? JSONEncoder().encode(u) { UserDefaults.standard.set(d, forKey: "jsoc.utente") }
    }

    // MARK: richieste

    func richiestaPubblica(_ path: String, _ metodo: String) throws -> URLRequest { try richiesta(path, metodo) }

    private func richiesta(_ path: String, _ metodo: String = "GET", corpo: Any? = nil) throws -> URLRequest {
        guard collegato, let url = URL(string: indirizzo + path) else { throw JsocErrore.nonCollegato }
        var r = URLRequest(url: url)
        r.httpMethod = metodo
        r.setValue("Bearer \(gettone)", forHTTPHeaderField: "Authorization")
        if let corpo {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: corpo)
        }
        return r
    }

    private func esegui<T: Decodable>(_ r: URLRequest, riprova: Bool = true) async throws -> T {
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await sessione.data(for: r) } catch {
            if riprova, Self.erroreDiStrada(error), let altra = cambiaStrada(r) {
                return try await esegui(altra, riprova: false)
            }
            if online { online = false }
            throw JsocErrore.rete(error.localizedDescription)
        }
        if !online { online = true }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let msg = (try? JSONDecoder().decode(JErrore.self, from: data))?.errore ?? "errore \(code)"
            throw JsocErrore.server(msg)
        }
        let t0 = CACurrentMediaTime()
        let v = try JSONDecoder().decode(T.self, from: data)
        let ms = (CACurrentMediaTime() - t0) * 1000
        if ms > 15 { Prestazioni.shared.attivita("decodifica \(r.url?.path ?? "") \(Int(ms)) ms (\(data.count / 1024) KB)") }
        return v
    }

    func get<T: Decodable>(_ path: String) async throws -> T { try await esegui(try richiesta(path)) }
    func send<T: Decodable>(_ path: String, _ metodo: String = "POST", _ corpo: Any) async throws -> T {
        try await esegui(try richiesta(path, metodo, corpo: corpo))
    }

    // MARK: API

    func io() async throws -> JUtente { let u: JUtente = try await get("/api/io"); salvaUtente(u); return u }
    func utenti() async throws -> [JUtente] { try await get("/api/utenti") }
    func eventi() async throws -> [JEvento] { try await get("/api/eventi") }
    func evento(_ id: Int) async throws -> JEvento { try await get("/api/eventi/\(id)") }
    func squadra(_ id: Int) async throws -> [JCompagno] { try await get("/api/eventi/\(id)/squadra") }
    func messaggi(_ id: Int, dopo: Int) async throws -> [JMessaggio] { try await get("/api/eventi/\(id)/messaggi?dopo=\(dopo)") }
    func documenti(_ id: Int) async throws -> [JFile] { try await get("/api/eventi/\(id)/documenti") }

    func creaEvento(_ campi: [String: Any]) async throws -> JEvento { try await send("/api/eventi", "POST", campi) }
    func membro(_ ev: Int, utente: Int, ruolo: String?, squadra: String = "") async throws -> JEvento {
        try await send("/api/eventi/\(ev)/membri", "POST", ["utente": utente, "ruolo": ruolo.map { $0 as Any } ?? NSNull(), "squadra": squadra])
    }
    func creaPunto(_ ev: Int, nome: String, tipo: String, _ c: CLLocationCoordinate2D, note: String = "") async throws -> JPunto {
        var b: [String: Any] = ["nome": nome, "tipo": tipo, "lat": c.latitude, "lon": c.longitude, "note": note]
        // organizzatore che guarda la mappa di una squadra: il punto è di quella squadra
        if let v = EventoStore.shared.vistaSquadra { b["squadra"] = v }
        return try await send("/api/eventi/\(ev)/punti", "POST", b)
    }
    func scrivi(_ ev: Int, _ testo: String, _ c: CLLocationCoordinate2D?, dest: Int? = nil, allegato: String? = nil) async throws -> JMessaggio {
        var b: [String: Any] = ["testo": testo]
        if let allegato { b["allegato"] = allegato }
        if let c { b["lat"] = c.latitude; b["lon"] = c.longitude }
        if let dest { b["dest"] = dest }
        return try await send("/api/eventi/\(ev)/messaggi", "POST", b)
    }
    func indagine(_ punto: Int, _ testo: String, ipotesi: Bool) async throws -> [JIndagine] {
        try await send("/api/punti/\(punto)/indagine", "POST", ["testo": testo, "ipotesi": ipotesi])
    }
    func aggiornaPunto(_ punto: Int, _ campi: [String: Any]) async throws -> JPunto { try await send("/api/punti/\(punto)", "PATCH", campi) }
    func flussiVideo() async throws -> [JFlusso] { try await get("/api/video/flussi") }
    /// Indirizzo HLS della diretta (il gettone va nell'indirizzo: il lettore video non manda intestazioni).
    func videoURL(_ nome: String) -> URL? {
        let p = nome.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? nome
        let g = gettone.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? gettone
        return URL(string: "\(indirizzo)/api/video/hls/\(p)/index.m3u8?g=\(g)")
    }

    struct VideoConfig: Decodable { let srt_host: String; let srt_porta: Int; let percorso: String; var rtmp: String? = nil }
    /// Indirizzo per trasmettere: utente = callsign, password = il proprio gettone (niente da configurare).
    /// RTMPS (TCP, cifrato) passa da internet senza Tailscale; SRT (UDP) solo dentro Tailscale, come riserva.
    func videoPubblica() async throws -> URL {
        let c: VideoConfig = try await get("/api/video/config")
        if let r = c.rtmp, !r.isEmpty, !UserDefaults.standard.bool(forKey: "video.srt"),
           var u = URLComponents(string: "\(r)/\(c.percorso)/cam") {
            u.queryItems = [.init(name: "user", value: c.percorso), .init(name: "pass", value: gettone)]
            if let url = u.url { return url }
        }
        var u = URLComponents()
        u.scheme = "srt"; u.host = c.srt_host; u.port = c.srt_porta
        u.queryItems = [.init(name: "streamid", value: "publish:\(c.percorso):\(c.percorso):\(gettone)"), .init(name: "latency", value: "2000")]
        guard let url = u.url else { throw JsocErrore.server("indirizzo video non valido") }
        return url
    }

    /// Indirizzo con il gettone nella richiesta (per MapLibre, lettori video, condivisione file).
    func conGettone(_ path: String) -> URL? {
        let g = gettone.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? gettone
        return URL(string: indirizzo + path + (path.contains("?") ? "&" : "?") + "g=" + g)
    }

    /// Invia un file grezzo (PUT/POST) e legge la risposta JSON.
    func inviaFile<T: Decodable>(_ path: String, _ metodo: String, _ dati: Data) async throws -> T {
        var r = try richiesta(path, metodo)
        r.timeoutInterval = 600
        r.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await URLSession.shared.upload(for: r, from: dati) } catch { throw JsocErrore.rete(error.localizedDescription) }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let msg = (try? JSONDecoder().decode(JErrore.self, from: data))?.errore ?? "errore \(code)"
            throw JsocErrore.server(msg)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func invito(ruolo: String) async throws -> JInvito { try await send("/api/inviti", "POST", ["ruolo": ruolo]) }
    /// Codice da 10 minuti per aprire lo stesso profilo su un altro iPhone/iPad.
    func collegaDispositivo() async throws -> JInvito { try await send("/api/dispositivi", "POST", [String: String]()) }

    struct Salvate: Decodable { let salvate: Int }
    func inviaPosizioni(_ ev: Int, _ lista: [[String: Double]]) async throws -> Int {
        let r: Salvate = try await send("/api/eventi/\(ev)/posizione", "POST", ["posizioni": lista])
        return r.salvate
    }

    func scaricaFile(_ ev: Int, _ rel: String) async throws -> URL {
        let enc = rel.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        let r = try richiesta("/api/eventi/\(ev)/file/\(enc)")
        let (tmp, resp) = try await sessione.download(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw JsocErrore.server("file non scaricato") }
        return tmp
    }

    func caricaFile(_ ev: Int, _ rel: String, dati: Data) async throws {
        let enc = rel.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        let r = try richiesta("/api/eventi/\(ev)/file/\(enc)", "PUT")
        let (_, resp) = try await sessione.upload(for: r, from: dati)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw JsocErrore.server("caricamento non riuscito") }
    }
}

// MARK: - Dati dell'evento per la mappa (letti anche fuori dal main actor)

enum DatiEvento {
    static var punti: [GaraPoint] = []
    static var aree: [GaraArea] = []
    static var disegni: [JDisegno] = []
    static var firma = ""

    static func kind(_ tipo: String) -> GaraPoint.Kind {
        switch tipo {
        case "obj", "obiettivo": return .obj
        case "ipotesi", "contatto", "pericolo": return .ipotesi
        case "acqua": return .acqua
        case "recon", "waypoint": return .recon
        case "hotel", "base", "parcheggio", "raduno": return .hotel
        case "apo", "ingresso": return .logistica
        default: return .logistica
        }
    }
}

// MARK: - Evento attivo, squadra, chat, posizioni (con coda offline)

@MainActor
final class EventoStore: ObservableObject {
    static let shared = EventoStore()

    @Published private(set) var eventi: [JEvento] = []
    @Published private(set) var corrente: JEvento?
    @Published private(set) var squadra: [JCompagno] = []
    @Published private(set) var messaggi: [JMessaggio] = []
    @Published private(set) var nonLetti = 0
    @Published private(set) var stato = ""
    @Published private(set) var inCoda = 0
    /// organizzatore di un evento interno: mappa di una sola squadra (attacco/difesa); nil = tutte
    @Published var vistaSquadra: String?
    var idCorrente: Int {
        get { UserDefaults.standard.integer(forKey: "jsoc.evento") }
        set { UserDefaults.standard.set(newValue, forKey: "jsoc.evento") }
    }
    @Published var condividiPosizione = UserDefaults.standard.object(forKey: "jsoc.condividi") as? Bool ?? true {
        didSet { UserDefaults.standard.set(condividiPosizione, forKey: "jsoc.condividi") }
    }

    private var coda: [[String: Double]] = []
    private var ultimaPosizione: CLLocation?
    private var ultimaDirezione: Double?
    private var ultimoInvio = Date.distantPast

    static var cartella: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("JSOC", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private var fileEventi: URL { Self.cartella.appendingPathComponent("eventi.json") }
    private var fileCoda: URL { Self.cartella.appendingPathComponent("coda_posizioni.json") }
    private func fileEvento(_ id: Int) -> URL { Self.cartella.appendingPathComponent("evento_\(id).json") }
    private func fileChat(_ id: Int) -> URL { Self.cartella.appendingPathComponent("chat_\(id).json") }

    init() {
        if let d = try? Data(contentsOf: fileEventi), let e = try? JSONDecoder().decode([JEvento].self, from: d) { eventi = e }
        if Anteprima.attiva { eventi = Anteprima.eventi() }
        if let d = try? Data(contentsOf: fileCoda), let c = try? JSONDecoder().decode([[String: Double]].self, from: d) { coda = c; inCoda = c.count }
        if idCorrente > 0 { caricaLocale(idCorrente) }
        Livelli.shared.contesto(idCorrente > 0 ? "e\(idCorrente)" : "p")
        if idCorrente == -1 { DatiEvento.aree = CampiStore.shared.aree }
    }

    /// Mappa personale: niente evento, si vedono i campi dell'associazione e i propri livelli.
    var inPersonale: Bool { idCorrente <= 0 }
    func apriPersonale() {
        idCorrente = -1
        corrente = nil; squadra = []; messaggi = []; nonLetti = 0; vistaSquadra = nil
        DatiEvento.punti = []; DatiEvento.disegni = []
        DatiEvento.aree = CampiStore.shared.aree
        DatiEvento.firma = "personale-\(DatiEvento.aree.count)"
        Livelli.shared.contesto("p")
        NavStore.shared.objectWillChange.send()
    }

    /// Cartella dei documenti dell'evento attivo sul telefono.
    static func documenti(_ id: Int) -> URL {
        cartella.appendingPathComponent("eventi/\(id)/documenti", isDirectory: true)
    }

    private func caricaLocale(_ id: Int) {
        if let d = try? Data(contentsOf: fileEvento(id)), let e = try? JSONDecoder().decode(JEvento.self, from: d) { applica(e) }
        if let d = try? Data(contentsOf: fileChat(id)), let m = try? JSONDecoder().decode([JMessaggio].self, from: d) { messaggi = m }
    }

    private func applica(_ e: JEvento) {
        corrente = e
        DatiEvento.punti = (e.punti ?? []).map {
            GaraPoint(id: $0.nome, lat: $0.lat, lon: $0.lon, kind: DatiEvento.kind($0.tipo), note: $0.note ?? "")
        }
        DatiEvento.aree = (e.aree ?? []).map { GaraArea(nome: $0.nome, tipo: $0.tipo, punti: $0.coord) }
        DatiEvento.disegni = e.disegni ?? []
        DatiEvento.firma = "\(e.id)-\(DatiEvento.punti.count)-" + (e.aree ?? []).map { "\($0.id)" }.joined(separator: ",")
        NavStore.shared.objectWillChange.send()
    }

    func scegli(_ e: JEvento) {
        idCorrente = e.id
        vistaSquadra = nil
        Livelli.shared.contesto("e\(e.id)")
        squadra = []
        messaggi = []
        nonLetti = 0
        caricaLocale(e.id)
        if corrente?.id != e.id { applica(e) }
        Task { await aggiorna(JsocClient.shared) }
    }

    /// Scarica elenco eventi, evento attivo, squadra e messaggi nuovi. Senza rete resta tutto com'era (copia locale).
    func aggiorna(_ j: JsocClient) async {
        guard j.collegato, !Anteprima.attiva else { return }
        do {
            let e = try await j.eventi()
            // si riassegna solo se cambia: ogni assegnazione fa ridisegnare tutte le schermate che osservano gli eventi
            if eventi != e {
                eventi = e
                try? JSONEncoder().encode(e).write(to: fileEventi, options: .atomic)
            }
            // evento attivo = uno di cui faccio parte: prima quello in corso, poi il prossimo, poi l'ultimo passato
            let miei = e.filter(\.membro)
            if idCorrente == -1 { if corrente != nil || DatiEvento.aree.isEmpty { apriPersonale() }; return }
            if idCorrente == 0 || !miei.contains(where: { $0.id == idCorrente }) {
                let scelta = miei.filter { $0.fase == 0 }.first
                    ?? miei.filter { $0.fase == 1 }.min { ($0.dataInizio ?? .distantFuture) < ($1.dataInizio ?? .distantFuture) }
                    ?? miei.first
                idCorrente = scelta?.id ?? 0
            }
            guard idCorrente > 0 else { apriPersonale(); return }
            let ev = try await j.evento(idCorrente)
            if ev != corrente {
                let t0 = CACurrentMediaTime()
                defer { let ms = (CACurrentMediaTime() - t0) * 1000; if ms > 15 { Prestazioni.shared.attivita("applica evento \(Int(ms)) ms") } }
                applica(ev)
                try? JSONEncoder().encode(ev).write(to: fileEvento(ev.id), options: .atomic)
            }
            if let sq = try? await j.squadra(ev.id), sq != squadra { squadra = sq }
            let nuovi = try await j.messaggi(ev.id, dopo: messaggi.last?.id ?? 0)
            if !nuovi.isEmpty {
                messaggi += nuovi
                nonLetti += nuovi.filter { $0.autore != j.utente?.id }.count
                try? JSONEncoder().encode(messaggi).write(to: fileChat(ev.id), options: .atomic)
            }
            await svuotaCoda(j)
            let st = "Aggiornato alle " + Date().formatted(date: .omitted, time: .shortened)
            if stato != st { stato = st }
        } catch {
            if stato != "Senza rete: dati salvati sul telefono" { stato = "Senza rete: dati salvati sul telefono" }
        }
    }

    func letti() { nonLetti = 0 }

    func scrivi(_ testo: String, _ j: JsocClient, posizione: CLLocationCoordinate2D?, dest: Int? = nil, allegato: String? = nil) async throws {
        guard let ev = corrente else { return }
        let m = try await j.scrivi(ev.id, testo, posizione, dest: dest, allegato: allegato)
        if !messaggi.contains(where: { $0.id == m.id }) { messaggi.append(m) }
        try? JSONEncoder().encode(messaggi).write(to: fileChat(ev.id), options: .atomic)
    }

    /// Posizione: una ogni 10 m o 30 s, in coda finché il server non la riceve.
    /// Posizione e direzione (bussola): una ogni 10 m, 30 s o quando ti giri di più di 25°.
    func registra(_ l: CLLocation, direzione: Double? = nil) {
        guard condividiPosizione, corrente?.membro == true, l.horizontalAccuracy >= 0, l.horizontalAccuracy < 100 else { return }
        let girato = direzione.map { d in ultimaDirezione.map { abs(angoloDiff(d, $0)) > 25 } ?? true } ?? false
        if let u = ultimaPosizione, l.distance(from: u) < 10, Date().timeIntervalSince(ultimoInvio) < 30,
           !(girato && Date().timeIntervalSince(ultimoInvio) > 3) { return }
        ultimaPosizione = l
        ultimaDirezione = direzione
        ultimoInvio = Date()
        var p: [String: Double] = ["lat": l.coordinate.latitude, "lon": l.coordinate.longitude,
                                   "acc": l.horizontalAccuracy, "ts": l.timestamp.timeIntervalSince1970]
        if l.course >= 0 { p["rotta"] = l.course }
        if l.speed >= 0 { p["vel"] = l.speed }
        if let direzione { p["dir"] = direzione }
        UIDevice.current.isBatteryMonitoringEnabled = true
        if UIDevice.current.batteryLevel >= 0 { p["batt"] = Double(UIDevice.current.batteryLevel) }
        coda.append(p)
        if coda.count > 20000 { coda.removeFirst(coda.count - 20000) }
        inCoda = coda.count
        salvaCoda()
    }

    func svuotaCoda(_ j: JsocClient) async {
        guard let ev = corrente, !coda.isEmpty else { return }
        let blocco = Array(coda.prefix(2000))
        do {
            _ = try await j.inviaPosizioni(ev.id, blocco)
            coda.removeFirst(min(blocco.count, coda.count))
            inCoda = coda.count
            salvaCoda()
        } catch {}
    }

    private func salvaCoda() {
        let t0 = CACurrentMediaTime()
        try? JSONEncoder().encode(coda).write(to: fileCoda, options: .atomic)
        let ms = (CACurrentMediaTime() - t0) * 1000
        if ms > 15 { Prestazioni.shared.attivita("salva coda posizioni (\(coda.count)) \(Int(ms)) ms") }
    }
}

// MARK: - QR

enum QR {
    static func immagine(_ testo: String, scala: CGFloat = 10) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(testo.utf8)
        f.correctionLevel = "L"   // meno fitto: si legge meglio da uno schermo
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: scala, y: scala)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
