import Foundation

// MARK: - Associazione, profilo, home (stile Spond)

struct JProfilo: Codable, Hashable, Identifiable {
    let id: Int
    var nome: String
    let callsign: String
    var ruolo: String
    var email: String?
    var telefono: String?
    var nascita: String?
    var luogo_nascita: String?
    var cf: String?
    var indirizzo: String?
    var gruppo_sanguigno: String?
    var emergenza: String?
    var note_profilo: String?
    var tessera: String?
    var tessera_scadenza: String?
    var certificato_scadenza: String?
    var foto: Bool?
    var attivo: Int?
    var gruppi: [Int]?
    var quota_pagata: Int?
    var quote: [JQuotaMia]?

    var direttivo: Bool { ruolo == "direttivo" }
    /// giorni alla scadenza del certificato (negativo = scaduto, nil = non inserito)
    var giorniCertificato: Int? { giorniA(certificato_scadenza) }
    var giorniTessera: Int? { giorniA(tessera_scadenza) }
}

func giorniA(_ s: String?) -> Int? {
    guard let s, s.count >= 10 else { return nil }
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
    guard let d = f.date(from: String(s.prefix(10))) else { return nil }
    return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: d).day
}

func dataIT(_ s: String?) -> String {
    guard let s, s.count >= 10 else { return "—" }
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
    guard let d = f.date(from: String(s.prefix(10))) else { return s }
    return d.formatted(.dateTime.day().month(.twoDigits).year())
}

func isoGiorno(_ d: Date) -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
    return f.string(from: d)
}

func euro(_ v: Double?) -> String { (v ?? 0).formatted(.currency(code: "EUR").locale(Locale(identifier: "it_IT"))) }

struct JQuotaMia: Codable, Hashable { let anno: Int; let importo: Double?; let pagata: Int?; let data: String? }

/// Il server manda il numero di membri (elenco gruppi) o la lista degli id (dopo una modifica).
enum JMembriGruppo: Codable, Hashable {
    case numero(Int), lista([Int])
    init(from d: Decoder) throws {
        let c = try d.singleValueContainer()
        if let n = try? c.decode(Int.self) { self = .numero(n) } else { self = .lista(try c.decode([Int].self)) }
    }
    func encode(to e: Encoder) throws {
        var c = e.singleValueContainer()
        switch self { case .numero(let n): try c.encode(n); case .lista(let l): try c.encode(l) }
    }
}

struct JGruppo: Codable, Identifiable, Hashable { let id: Int; let nome: String; let colore: String?; var membri: JMembriGruppo? }

struct JSoci: Codable { let soci: [JProfilo]; let gruppi: [JGruppo]; let anno: Int }

struct JQuota: Codable, Identifiable, Hashable {
    var id: Int { utente }
    let utente: Int
    let callsign: String?
    let nome: String?
    let importo: Double?
    let pagata: Int?
    let data: String?
}
struct JQuote: Codable { let anno: Int; let quote: [JQuota] }

struct JMovimento: Codable, Identifiable, Hashable {
    let id: Int
    let data: String
    let tipo: String
    let categoria: String?
    let importo: Double
    let descrizione: String?
    let callsign: String?
}
struct JCassa: Codable {
    struct Cat: Codable, Hashable { let tipo: String; let categoria: String; let totale: Double }
    let anno: Int; let movimenti: [JMovimento]; let entrate: Double; let uscite: Double; let saldo_totale: Double; let categorie: [Cat]
}

struct JMateriale: Codable, Identifiable, Hashable {
    let id: Int
    let nome: String
    let categoria: String?
    let quantita: Double?
    let unita: String?
    let stato: String?
    let assegnato: Int?
    let assegnato_a: String?
    let note: String?
}

struct JPresenza: Codable, Identifiable, Hashable {
    var id: Int { utente }
    let utente: Int
    let callsign: String
    let nome: String?
    let risposta: String?
    let presente: Int?
}
struct JPresenze: Codable {
    struct Conta: Codable, Hashable { let si: Int; let no: Int; let forse: Int; let senza_risposta: Int }
    let presenze: [JPresenza]; let conta: Conta
}

struct JCommento: Codable, Identifiable, Hashable { let id: Int; let autore: Int?; let testo: String; let ts: Double; let callsign: String? }
struct JPost: Codable, Identifiable, Hashable {
    let id: Int
    let autore: Int?
    let titolo: String?
    let testo: String
    let gruppo: Int?
    let fissato: Int?
    let ts: Double
    let callsign: String?
    let commenti: [JCommento]
    let letto_da: Int
    let letto: Bool
    let destinatari: Int
}

struct JSondaggio: Codable, Identifiable, Hashable {
    struct Opzione: Codable, Hashable { let testo: String; let voti: Int; let chi: [String?] }
    let id: Int
    let domanda: String
    let opzioni: [Opzione]
    let multipla: Int
    let anonimo: Int
    let miei: [Int]
    let votanti: Int
    let chiuso: Bool
    let callsign: String?
    let ts: Double
}

struct JHome: Codable {
    struct Prossimo: Codable, Identifiable, Hashable {
        let id: Int; let nome: String; let tipo: String; let inizio: String?; let fine: String?; let luogo: String?
        let mio_ruolo: String?; let mia_risposta: String?; let si: Int
    }
    struct Avviso: Codable, Hashable { let tipo: String; let testo: String; let evento: Int? }
    struct Direttivo: Codable { let quote_da_incassare: Int?; let saldo: Double?; let certificati_scaduti: Int? }
    let prossimi: [Prossimo]
    let avvisi: [Avviso]
    let post_nuovi: Int
    let sondaggi_aperti: Int
    let soci_attivi: Int
    let direttivo: Direttivo?
}

struct JOk: Codable { let ok: Bool? }

extension JsocClient {
    func home() async throws -> JHome { try await get("/api/home") }
    func profilo() async throws -> JProfilo { try await get("/api/profilo") }
    func salvaProfilo(_ campi: [String: Any]) async throws -> JProfilo { try await send("/api/profilo", "PATCH", campi) }
    func soci() async throws -> JSoci { try await get("/api/soci") }
    func salvaSocio(_ id: Int, _ campi: [String: Any]) async throws -> JProfilo { try await send("/api/soci/\(id)", "PATCH", campi) }
    func salvaGruppo(_ id: Int?, _ campi: [String: Any]) async throws -> JGruppo {
        try await send(id.map { "/api/gruppi/\($0)" } ?? "/api/gruppi", id == nil ? "POST" : "PATCH", campi)
    }
    func quote(anno: Int) async throws -> JQuote { try await get("/api/quote?anno=\(anno)") }
    func salvaQuota(_ campi: [String: Any]) async throws -> JQuote { try await send("/api/quote", "POST", campi) }
    func cassa(anno: Int) async throws -> JCassa { try await get("/api/cassa?anno=\(anno)") }
    func nuovoMovimento(_ campi: [String: Any]) async throws -> JMovimento { try await send("/api/cassa", "POST", campi) }
    func cancellaMovimento(_ id: Int) async throws { let _: JOk = try await send("/api/cassa/\(id)", "DELETE", [String: Any]()) }
    func materiale() async throws -> [JMateriale] { try await get("/api/materiale") }
    func salvaMateriale(_ id: Int?, _ campi: [String: Any]) async throws -> JMateriale {
        try await send(id.map { "/api/materiale/\($0)" } ?? "/api/materiale", id == nil ? "POST" : "PATCH", campi)
    }
    func cancellaMateriale(_ id: Int) async throws { let _: JOk = try await send("/api/materiale/\(id)", "DELETE", [String: Any]()) }
    func presenze(_ ev: Int) async throws -> JPresenze { try await get("/api/eventi/\(ev)/presenze") }
    func rispondi(_ ev: Int, _ r: String) async throws -> JPresenze { try await send("/api/eventi/\(ev)/presenza", "POST", ["risposta": r]) }
    func appello(_ ev: Int, utente: Int, presente: Bool) async throws -> JPresenze {
        try await send("/api/eventi/\(ev)/presenze", "POST", ["utente": utente, "presente": presente])
    }
    func bacheca() async throws -> [JPost] { try await get("/api/bacheca") }
    func nuovoPost(titolo: String, testo: String, fissato: Bool) async throws -> [JPost] {
        try await send("/api/bacheca", "POST", ["titolo": titolo, "testo": testo, "fissato": fissato])
    }
    func commenta(_ post: Int, _ testo: String) async throws -> [JPost] { try await send("/api/bacheca/\(post)/commenti", "POST", ["testo": testo]) }
    func letto(_ post: Int) async { let _: JOk? = try? await send("/api/bacheca/\(post)/letto", "POST", [String: Any]()) }
    func sondaggi() async throws -> [JSondaggio] { try await get("/api/sondaggi") }
    func nuovoSondaggio(_ domanda: String, _ opzioni: [String], multipla: Bool, anonimo: Bool) async throws -> [JSondaggio] {
        try await send("/api/sondaggi", "POST", ["domanda": domanda, "opzioni": opzioni, "multipla": multipla, "anonimo": anonimo])
    }
    func vota(_ s: Int, _ opzioni: [Int]) async throws -> [JSondaggio] { try await send("/api/sondaggi/\(s)/voto", "POST", ["opzioni": opzioni]) }
    func documentiAssociazione() async throws -> [JFile] { try await get("/api/associazione/documenti") }

    /// Scarica dati grezzi dal server (foto profilo, documenti dell'associazione).
    func scaricaDati(_ path: String) async throws -> Data {
        let r = try richiestaPubblica(path, "GET")
        let (d, resp) = try await URLSession.shared.data(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw JsocErrore.server("non trovato") }
        return d
    }
    func caricaDati(_ path: String, dati: Data) async throws {
        let r = try richiestaPubblica(path, "PUT")
        let (_, resp) = try await URLSession.shared.upload(for: r, from: dati)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw JsocErrore.server("caricamento non riuscito") }
    }
}

/// Percorso con le parti codificate (spazi, accenti) per le richieste di file.
func percorsoURL(_ rel: String) -> String {
    rel.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
}

/// Differenza tra due angoli in gradi, tra -180 e 180.
func angoloDiff(_ a: Double, _ b: Double) -> Double {
    var d = (a - b).truncatingRemainder(dividingBy: 360)
    if d > 180 { d -= 360 }
    if d < -180 { d += 360 }
    return d
}
