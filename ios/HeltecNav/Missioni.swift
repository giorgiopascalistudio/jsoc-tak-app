import SwiftUI
import PhotosUI
import CoreLocation
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Missioni a fasi (fasi E)
// Il Game Master crea la missione; le squadre la giocano dai telefoni. Soluzioni, QR e punti GPS restano sul server.
// Idee prese da In-Evasion (indizi a tempo, console GM), Actionbound (quiz, "trova il punto"), Goosechase (bonus,
// punti del GM), Escape Team (narrazione audio, conto alla rovescia).

struct JIndizio: Codable, Hashable, Identifiable {
    var id = UUID(); var testo = ""; var costo = 0; var dopo_min: Int? = 0
    enum CodingKeys: String, CodingKey { case testo, costo, dopo_min }
}
struct JRamo: Codable, Hashable, Identifiable {
    var id = UUID(); var risposta = ""; var va_a = ""
    enum CodingKeys: String, CodingKey { case risposta, va_a }
}

struct JFase: Codable, Identifiable, Hashable {
    var id = String(UUID().uuidString.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(8))
    var titolo = "Nuova fase"
    var testo = ""
    var prova = "libera"
    var sblocco = "codice"
    var soluzione = ""
    var qr = ""
    var lat: Double? = nil
    var lon: Double? = nil
    var raggio = 15
    var punti = 10
    var tempo_min = 0
    var indizi: [JIndizio] = []
    var rami: [JRamo] = []
    var prossima = ""
    var immagine = false
    var audio: String? = ""
    var opzioni: [String]? = []
    var tolleranza: Double? = 0
    var mostra_direzione: Bool? = false
    var opzionale: Bool? = false
    var richiede: [String]? = []
}

struct JRegole: Codable, Hashable {
    var penalita_errore = 5; var durata_min = 0; var mostra_scelte: Bool? = false; var mostra_classifica: Bool? = false
    var inizio: String? = nil; var codice_avvio: String? = nil
}

struct JMissione: Codable, Identifiable {
    let id: Int
    var titolo: String
    var descrizione: String
    var stato: String
    var regole: JRegole
    var fasi: [JFase]
}

struct JMissioneRiga: Codable, Identifiable { let id: Int; let titolo: String; let descrizione: String; let stato: String; let n_fasi: Int; let gm: Bool; let mia_partita: Int?; let squadre: Int }

struct JFaseVista: Codable, Identifiable {
    let id: String; let titolo: String; let testo: String; let prova: String; let sblocco: String
    let punti: Int; let tempo_min: Int; let immagine: Bool; let raggio: Int
    let indizi_usati: [String]; let prossimo_indizio_costo: Int?; let scelte: [String]; let prova_stato: String?; let inizio: Double?
    var audio: String? = nil; var opzioni: [String]? = nil; var opzionale: Bool? = nil
    var lat: Double? = nil; var lon: Double? = nil; var bloccata_da: [String]? = nil; var prossimo_indizio_auto_min: Double? = nil
}

struct JMsgMissione: Codable, Identifiable, Hashable { let id: Int; let testo: String; let ts: Double; let da_gm: Int?; var squadra: String? = nil; var callsign: String? = nil; var partita: Int? = nil }

struct JPartita: Codable {
    let id: Int; let missione: Int; let titolo: String; let nome: String; let membri: [String]
    let inizio: Double?; let fine: Double?; let punti: Int; let errori: Int; let durata_min: Int; let scaduta: Bool
    let n_fasi: Int; let fatte: [String]; let fase: JFaseVista?
    var bonus: [JFaseVista]? = nil; var messaggi: [JMsgMissione]? = nil; var avvio: String? = nil; var in_attesa: Bool? = nil
    var n_bonus: Int? = nil; var bonus_fatte: [String]? = nil
}

struct JEsito: Codable { let esito: Bool; let messaggio: String; let stato: JPartita }

struct JSquadraDiretta: Codable, Identifiable { let id: Int; let nome: String; let membri: [String]; let punti: Int; let errori: Int; let fatte: Int; let fase: String?; let inizio: Double?; let fine: Double?; let indizi: Int }
struct JProvaDiretta: Codable, Identifiable { let id: Int; let squadra: String; let fase: String; let soluzione: String; let t: Double; let da: String }
struct JDiretta: Codable { let squadre: [JSquadraDiretta]; let prove: [JProvaDiretta]; let n_fasi: Int; var messaggi: [JMsgMissione]? = nil }

private func dizionario<T: Encodable>(_ v: T) -> Any { (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(v))) ?? [:] }

extension JsocClient {
    func missioni() async throws -> [JMissioneRiga] { try await get("/api/missioni") }
    func nuovaMissione(_ titolo: String) async throws -> JMissione { try await send("/api/missioni", "POST", ["titolo": titolo]) }
    func missione(_ id: Int) async throws -> JMissione { try await get("/api/missioni/\(id)") }
    func salvaMissione(_ m: JMissione, stato: String? = nil) async throws -> JMissione {
        var c: [String: Any] = ["titolo": m.titolo, "descrizione": m.descrizione, "regole": dizionario(m.regole), "fasi": dizionario(m.fasi)]
        if let stato { c["stato"] = stato }
        return try await send("/api/missioni/\(m.id)", "PUT", c)
    }
    func cancellaMissione(_ id: Int) async throws { let _: JOk = try await send("/api/missioni/\(id)", "DELETE", [String: String]()) }
    func entraPartita(_ mid: Int, nome: String, codice: String) async throws -> JPartita { try await send("/api/missioni/\(mid)/partite", "POST", ["nome": nome, "codice": codice]) }
    func partita(_ id: Int) async throws -> JPartita { try await get("/api/partite/\(id)") }
    func tenta(_ id: Int, _ corpo: [String: Any]) async throws -> JEsito { try await send("/api/partite/\(id)/tenta", "POST", corpo) }
    func indizio(_ id: Int, fase: String?) async throws -> JPartita { try await send("/api/partite/\(id)/indizio", "POST", ["fase": fase ?? ""]) }
    func aiuto(_ id: Int, _ t: String) async throws -> JPartita { try await send("/api/partite/\(id)/aiuto", "POST", ["testo": t]) }
    func diretta(_ mid: Int) async throws -> JDiretta { try await get("/api/missioni/\(mid)/diretta") }
    func messaggioGM(_ mid: Int, _ t: String, partita: Int?) async throws -> JDiretta { try await send("/api/missioni/\(mid)/messaggi", "POST", ["testo": t, "partita": partita.map { $0 as Any } ?? NSNull()]) }
    func puntiGM(_ pid: Int, _ d: Int, motivo: String) async throws -> JDiretta { try await send("/api/partite/\(pid)/punti", "POST", ["delta": d, "motivo": motivo]) }
    func giudica(_ prova: Int, ok: Bool) async throws { let _: JOk = try await send("/api/prove/\(prova)", "POST", ["ok": ok]) }
}

enum NomiMissione {
    static let prove: [(String, String, String)] = [
        ("libera", "Libera", "text.alignleft"), ("cifrario", "Cifrario", "lock.open.fill"),
        ("orientamento", "Orientamento", "location.north.line.fill"), ("documento", "Documento / intelligence", "doc.text.magnifyingglass"),
        ("campo", "Prova da campo", "figure.run"), ("scelta", "Quiz a scelta", "list.bullet.circle"),
        ("stima", "Stima un numero", "number.circle"), ("ordina", "Metti in ordine", "arrow.up.arrow.down.circle"),
    ]
    static let sblocchi: [(String, String, String)] = [
        ("codice", "Codice o risposta", "number"), ("qr", "QR sul campo", "qrcode"),
        ("gps", "Arrivare in un punto", "location.fill"), ("foto", "Foto approvata dal GM", "camera.fill"),
        ("nessuno", "Nessuno (solo lettura)", "arrow.right"),
    ]
    static func prova(_ k: String) -> (String, String) { let x = prove.first { $0.0 == k } ?? prove[0]; return (x.1, x.2) }
    static func sblocco(_ k: String) -> (String, String) { let x = sblocchi.first { $0.0 == k } ?? sblocchi[0]; return (x.1, x.2) }
}

// MARK: - Modelli pronti (milsim e escape)

enum ModelliMissione {
    static let elenco: [(String, String, String)] = [
        ("vuota", "Vuota", "parti da zero"),
        ("escape", "Escape a 5 codici", "cinque lucchetti da 5 cifre con indizi a tempo, stile Escape Team"),
        ("intel", "Recupero intel", "raggiungi il punto, trova il documento, decifra, consegna"),
        ("sd", "Search & Destroy", "trova l'obiettivo, disinnesca con il codice, esfiltra"),
        ("ostaggio", "Salvataggio ostaggio", "localizza, libera con prova foto, scorta all'estrazione"),
        ("vip", "Scorta VIP", "tappe GPS in ordine con tempo per tappa e bonus"),
        ("caccia", "Caccia al tesoro", "QR nascosti, quiz a scelta e stima, bonus facoltativi"),
    ]

    static func fasi(_ k: String) -> [JFase] {
        func f(_ t: String, _ testo: String, prova: String = "libera", sblocco: String = "codice", sol: String = "", punti: Int = 10,
               min: Int = 0, indizi: [JIndizio] = [], opz: [String] = [], bonus: Bool = false) -> JFase {
            var x = JFase(); x.titolo = t; x.testo = testo; x.prova = prova; x.sblocco = sblocco; x.soluzione = sol
            x.punti = punti; x.tempo_min = min; x.indizi = indizi; x.opzioni = opz; x.opzionale = bonus; return x
        }
        let auto = { (t: String, m: Int) in JIndizio(testo: t, costo: 0, dopo_min: m) }
        switch k {
        case "escape":
            return (1...5).map { i in
                f("Lucchetto \(i)", "[Scrivi l'enigma del lucchetto \(i): il risultato è un codice di 5 cifre]", prova: "cifrario",
                  sol: "[CODICE \(i)]", punti: 20, min: 12, indizi: [auto("[primo aiuto]", 5), auto("[secondo aiuto]", 9), JIndizio(testo: "[soluzione quasi completa]", costo: 10)])
            }
        case "intel":
            return [
                f("Infiltrazione", "Raggiungi il punto di raccolta senza farti vedere.", prova: "orientamento", sblocco: "gps", punti: 15),
                f("Il documento", "Nel punto c'è un documento con un QR: trovalo e scansionalo.", prova: "documento", sblocco: "qr", punti: 15),
                f("Decifra il messaggio", "[testo cifrato trovato nel documento]", prova: "cifrario", sol: "[PAROLA]", punti: 25,
                  indizi: [JIndizio(testo: "È un cifrario di Cesare", costo: 5)]),
                f("Consegna", "Porta la prova all'HQ: foto del documento davanti al responsabile.", prova: "campo", sblocco: "foto", punti: 20),
            ]
        case "sd":
            return [
                f("Ricognizione", "Individua la posizione dell'obiettivo e raggiungila.", prova: "orientamento", sblocco: "gps", punti: 15),
                f("Disinnesco", "Sull'obiettivo c'è un QR: scansionalo per avere il codice. Usa il gioco Bomba se c'è il telefono-bomba.", prova: "campo", sblocco: "qr", punti: 25, min: 10),
                f("Esfiltrazione", "Torna al punto di estrazione entro il tempo.", prova: "orientamento", sblocco: "gps", punti: 20, min: 15),
                f("Bonus: nessun ferito", "Foto di tutta la squadra all'estrazione.", prova: "campo", sblocco: "foto", punti: 15, bonus: true),
            ]
        case "ostaggio":
            return [
                f("Localizza l'ostaggio", "Segui le indicazioni radio e raggiungi l'edificio.", prova: "orientamento", sblocco: "gps", punti: 15),
                f("Libera l'ostaggio", "Foto dell'ostaggio liberato con la squadra.", prova: "campo", sblocco: "foto", punti: 25),
                f("Estrazione", "Porta l'ostaggio al punto di estrazione.", prova: "orientamento", sblocco: "gps", punti: 25, min: 20),
            ]
        case "vip":
            return (1...4).map { i in f("Tappa \(i)", "Scorta il VIP fino alla tappa \(i).", prova: "orientamento", sblocco: "gps", punti: 15, min: 10) }
                + [f("Bonus: VIP illeso", "Il GM conferma con una foto.", prova: "campo", sblocco: "foto", punti: 20, bonus: true)]
        case "caccia":
            return [
                f("Primo indizio", "Trova il primo QR vicino al punto di ritrovo.", sblocco: "qr", punti: 10),
                f("Quiz", "Qual è il raggio d'azione di una radio PMR446 in campo aperto?", prova: "scelta", sol: "Fino a qualche km",
                  punti: 10, opz: ["Qualche metro", "Fino a qualche km", "100 km"]),
                f("Stima", "Quanti metri ci sono tra il ritrovo e il bunker?", prova: "stima", sol: "[METRI]", punti: 15),
                f("Ordina", "Metti in ordine l'alfabeto NATO", prova: "ordina", punti: 10, opz: ["Alfa", "Bravo", "Charlie", "Delta"]),
                f("Bonus: QR nascosto", "C'è un QR extra nascosto sul campo.", sblocco: "qr", punti: 20, bonus: true),
            ]
        default: return []
        }
    }
}

// MARK: - Elenco

struct MissioniView: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @State private var righe: [JMissioneRiga] = []
    @State private var errore: String?
    @State private var nuova = false
    @State private var titoloNuova = ""
    @State private var modello = "vuota"

    var body: some View {
        Group {
            if !jsoc.collegato {
                Card { Text("Serve l'accesso al server JSOC per le missioni.").foregroundStyle(Theme.dim) }.padding()
            } else {
                List {
                    if let errore { Text(errore).foregroundStyle(Theme.red) }
                    let gioca = righe.filter { $0.stato == "attiva" }
                    Section("Da giocare") {
                        if gioca.isEmpty { Text("Nessuna missione attiva").foregroundStyle(Theme.dim) }
                        ForEach(Array(gioca.enumerated()), id: \.element.id) { i, r in
                            NavigationLink { GiocaMissioneView(riga: r) } label: { riga(r) }.comparsa(i)
                        }
                    }
                    let mie = righe.filter { $0.gm }
                    if !mie.isEmpty {
                        Section("Game Master") {
                            ForEach(Array(mie.enumerated()), id: \.element.id) { i, r in
                                NavigationLink { MissioneGMView(id: r.id) } label: { riga(r) }.comparsa(i + 2)
                            }
                        }
                    }
                    let chiuse = righe.filter { $0.stato == "chiusa" && !$0.gm }
                    if !chiuse.isEmpty {
                        Section("Concluse") { ForEach(chiuse) { r in riga(r) } }
                    }
                }
                .listaJSOC()
                .refreshable { await carica() }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { titoloNuova = ""; modello = "vuota"; nuova = true } label: { Label("Nuova missione", systemImage: "plus") }
            }
        }
        .task { await carica() }
        .sheet(isPresented: $nuova) {
            NavigationStack {
                Form {
                    Section { TextField("Titolo (es. Fase E · Operazione Lupo)", text: $titoloNuova) }
                    footer: { Text("Diventi il Game Master: prepari le fasi e la attivi quando è pronta.") }
                    Section("Parti da un modello") {
                        ForEach(ModelliMissione.elenco, id: \.0) { k, t, d in
                            Button { modello = k; if titoloNuova.isEmpty && k != "vuota" { titoloNuova = t } } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) { Text(t).font(.headline).foregroundStyle(.white); Text(d).font(.caption).foregroundStyle(Theme.dim) }
                                    Spacer()
                                    if modello == k { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.olive) }
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Nuova missione").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annulla") { nuova = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Crea") {
                            Task {
                                do {
                                    var m = try await jsoc.nuovaMissione(titoloNuova)
                                    let f = ModelliMissione.fasi(modello)
                                    if !f.isEmpty { m.fasi = f; _ = try await jsoc.salvaMissione(m) }
                                    nuova = false; await carica()
                                } catch { errore = error.localizedDescription }
                            }
                        }
                        .disabled(titoloNuova.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    func riga(_ r: JMissioneRiga) -> some View {
        HStack(spacing: 12) {
            Image(systemName: r.stato == "attiva" ? "flag.checkered" : r.stato == "bozza" ? "pencil.and.outline" : "checkmark.seal")
                .font(.title3).foregroundStyle(r.stato == "attiva" ? Theme.olive : Theme.dim).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.titolo).font(.headline)
                Text("\(r.n_fasi) fasi · \(r.squadre) squadre · \(r.stato)\(r.mia_partita != nil ? " · stai giocando" : "")")
                    .font(.caption).foregroundStyle(Theme.dim)
            }
        }
    }

    func carica() async {
        do { righe = try await jsoc.missioni(); errore = nil } catch { errore = error.localizedDescription }
    }
}

// MARK: - Game Master

struct MissioneGMView: View {
    let id: Int
    @ObservedObject private var jsoc = JsocClient.shared
    @EnvironmentObject var location: LocationService
    @Environment(\.dismiss) private var dismiss
    @State private var m: JMissione?
    @State private var scheda = 0
    @State private var errore: String?
    @State private var salvato = false
    @State private var modifica: JFase?
    @State private var elimina = false
    @State private var conAvvio = false
    @State private var avvio = Date().addingTimeInterval(3600)

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $scheda) {
                Text("Fasi").tag(0); Text("Diretta").tag(1); Text("QR da stampare").tag(2)
            }
            .pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 8)
            if let errore { Text(errore).font(.footnote).foregroundStyle(Theme.red).padding(.horizontal) }
            if m != nil {
                switch scheda {
                case 0: fasi
                case 1: DirettaView(id: id)
                default: qr
                }
            } else {
                Spacer(); ProgressView(); Spacer()
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: scheda)
        .navigationTitle(m?.titolo ?? "Missione")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { Task { await salva(nil) } } label: { Label("Salva", systemImage: "square.and.arrow.down") }
                    Button { Task { await salva("attiva") } } label: { Label("Salva e attiva", systemImage: "play.fill") }
                    Button { Task { await salva("bozza") } } label: { Label("Rimetti in bozza", systemImage: "pause.fill") }
                    Button { Task { await salva("chiusa") } } label: { Label("Chiudi la missione", systemImage: "stop.fill") }
                    Button(role: .destructive) { elimina = true } label: { Label("Elimina", systemImage: "trash") }
                } label: { Image(systemName: salvato ? "checkmark.circle.fill" : "ellipsis.circle") }
            }
        }
        .task { await carica() }
        .sheet(item: $modifica) { f in
            EditorFaseView(missione: id, fase: f, altre: m?.fasi ?? []) { nuova in
                if let i = m?.fasi.firstIndex(where: { $0.id == nuova.id }) { m?.fasi[i] = nuova } else { m?.fasi.append(nuova) }
                Task { await salva(nil) }
            }
            .environmentObject(location)
        }
        .confirmationDialog("Eliminare la missione con tutte le partite?", isPresented: $elimina, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) { Task { try? await jsoc.cancellaMissione(id); dismiss() } }
        }
    }

    var fasi: some View {
        Form {
            if let mm = m {
                Section {
                    TextField("Titolo", text: Binding(get: { m?.titolo ?? "" }, set: { m?.titolo = $0 }))
                    TextField("Briefing per le squadre", text: Binding(get: { m?.descrizione ?? "" }, set: { m?.descrizione = $0 }), axis: .vertical)
                        .lineLimit(2...6)
                    LabeledContent("Stato", value: mm.stato.capitalized)
                }
                Section("Regole") {
                    Stepper("Penalità codice sbagliato: \(mm.regole.penalita_errore)", value: Binding(get: { m?.regole.penalita_errore ?? 0 }, set: { m?.regole.penalita_errore = $0 }), in: 0...100)
                    Stepper(mm.regole.durata_min == 0 ? "Durata: senza limite" : "Durata: \(mm.regole.durata_min) min",
                            value: Binding(get: { m?.regole.durata_min ?? 0 }, set: { m?.regole.durata_min = $0 }), in: 0...600, step: 5)
                    Toggle("Mostra le scelte dei rami come pulsanti", isOn: Binding(get: { m?.regole.mostra_scelte ?? false }, set: { m?.regole.mostra_scelte = $0 }))
                    Toggle("Avvio programmato", isOn: $conAvvio)
                    if conAvvio { DatePicker("Parte alle", selection: $avvio) }
                    TextField("Codice di avvio (lo dai tu alle squadre)", text: Binding(get: { m?.regole.codice_avvio ?? "" }, set: { m?.regole.codice_avvio = $0.isEmpty ? nil : $0.uppercased() }))
                        .textInputAutocapitalization(.characters).font(Theme.mono(14))
                }
                .onChange(of: conAvvio) { _ in aggiornaAvvio() }
                .onChange(of: avvio) { _ in aggiornaAvvio() }
                Section {
                    ForEach(Array(mm.fasi.enumerated()), id: \.element.id) { i, f in
                        Button { modifica = f } label: {
                            HStack(spacing: 12) {
                                Text(f.opzionale == true ? "★" : "\(mm.fasi.prefix(i).filter { $0.opzionale != true }.count + 1)")
                                    .font(Theme.mono(15, .heavy)).foregroundStyle(f.opzionale == true ? Theme.amber : Theme.olive).frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.titolo).font(.headline).foregroundStyle(.white)
                                    HStack(spacing: 8) {
                                        Label(NomiMissione.prova(f.prova).0, systemImage: NomiMissione.prova(f.prova).1)
                                        Label(NomiMissione.sblocco(f.sblocco).0, systemImage: NomiMissione.sblocco(f.sblocco).1)
                                    }
                                    .font(.caption2).foregroundStyle(Theme.dim).lineLimit(1)
                                    HStack(spacing: 8) {
                                        if !f.rami.isEmpty { Text("\(f.rami.count) rami").foregroundStyle(Theme.amber) }
                                        if !(f.richiede ?? []).isEmpty { Text("con prerequisiti").foregroundStyle(Theme.cyan) }
                                        if !(f.audio ?? "").isEmpty { Image(systemName: "speaker.wave.2.fill").foregroundStyle(Theme.dim) }
                                        if f.immagine { Image(systemName: "photo").foregroundStyle(Theme.dim) }
                                    }
                                    .font(.caption2)
                                }
                                Spacer()
                                Text("\(f.punti) pt").font(Theme.mono(12, .bold)).foregroundStyle(Theme.dim)
                            }
                        }
                    }
                    .onMove { m?.fasi.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { m?.fasi.remove(atOffsets: $0) }
                    Button { modifica = JFase(titolo: "Fase \((m?.fasi.count ?? 0) + 1)") } label: { Label("Aggiungi fase", systemImage: "plus.circle.fill") }
                    Button { var x = JFase(titolo: "Bonus"); x.opzionale = true; x.punti = 15; modifica = x } label: { Label("Aggiungi missione bonus (facoltativa)", systemImage: "star.circle.fill") }
                } header: { Text("Fasi") } footer: { Text("L'ordine è quello di gioco; un ramo può saltare a un'altra fase. ★ = bonus facoltativa, giocabile in parallelo.") }
            }
        }
        .scrollContentBackground(.hidden)
    }

    func aggiornaAvvio() {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        m?.regole.inizio = conAvvio ? f.string(from: avvio) : nil
    }

    var qr: some View {
        ScrollView {
            VStack(spacing: 14) {
                let conQR = (m?.fasi ?? []).filter { $0.sblocco == "qr" }
                if conQR.isEmpty {
                    Card { Text("Nessuna fase si sblocca con un QR.").foregroundStyle(Theme.dim) }
                }
                ForEach(conQR) { f in
                    let testo = "jsoctak-fase:\(id):\(f.id):\(f.qr)"
                    Card(title: f.titolo, icon: "qrcode") {
                        if f.qr.isEmpty {
                            Text("Salva la missione per generare il QR.").foregroundStyle(Theme.dim)
                        } else if let img = QR.immagine(testo) {
                            Image(uiImage: img).interpolation(.none).resizable().scaledToFit()
                                .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 12)).frame(maxWidth: 260)
                                .frame(maxWidth: .infinity)
                            ShareLink(item: Image(uiImage: img), preview: SharePreview(f.titolo, image: Image(uiImage: img))) {
                                Label("Condividi / stampa", systemImage: "printer")
                            }
                            .buttonStyle(.bordered).tint(Theme.olive)
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    func carica() async {
        do {
            m = try await jsoc.missione(id); errore = nil
            if let s = m?.regole.inizio, !s.isEmpty {
                let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm"
                if let d = f.date(from: s) { avvio = d; conAvvio = true }
            }
        } catch { errore = error.localizedDescription }
    }

    func salva(_ stato: String?) async {
        guard let mm = m else { return }
        do {
            m = try await jsoc.salvaMissione(mm, stato: stato)
            errore = nil
            salvato = true; haptic(.medium)
            try? await Task.sleep(nanoseconds: 1_500_000_000); salvato = false
        } catch { errore = error.localizedDescription }
    }
}

// MARK: - Editor di una fase

struct EditorFaseView: View {
    let missione: Int
    @State var fase: JFase
    let altre: [JFase]
    let salva: (JFase) -> Void
    @EnvironmentObject var location: LocationService
    @Environment(\.dismiss) private var dismiss
    @State private var foto: PhotosPickerItem?
    @State private var caricando = false
    @State private var errore: String?
    @State private var scegliAudio = false
    @State private var nuovaOpzione = ""

    var opzioni: Binding<[String]> { Binding(get: { fase.opzioni ?? [] }, set: { fase.opzioni = $0 }) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Fase") {
                    TextField("Titolo", text: $fase.titolo)
                    TextField("Testo per la squadra: briefing, cifrato, indovinello…", text: $fase.testo, axis: .vertical).lineLimit(3...12)
                    Picker("Tipo di prova", selection: $fase.prova) {
                        ForEach(NomiMissione.prove, id: \.0) { Label($0.1, systemImage: $0.2).tag($0.0) }
                    }
                    Toggle(isOn: Binding(get: { fase.opzionale ?? false }, set: { fase.opzionale = $0 })) {
                        Label("Missione bonus (facoltativa)", systemImage: "star.fill")
                    }
                    PhotosPicker(selection: $foto, matching: .images) {
                        Label(caricando ? "Carico…" : fase.immagine ? "Immagine allegata · cambia" : "Allega immagine o documento",
                              systemImage: fase.immagine ? "photo.fill" : "photo.badge.plus")
                    }
                    if fase.immagine { Button("Togli l'immagine", role: .destructive) { fase.immagine = false } }
                    Button { scegliAudio = true } label: {
                        Label((fase.audio ?? "").isEmpty ? "Allega narrazione audio" : "Audio allegato · cambia", systemImage: "speaker.wave.2.fill")
                    }
                    if !(fase.audio ?? "").isEmpty { Button("Togli l'audio", role: .destructive) { fase.audio = "" } }
                }
                if ["scelta", "ordina"].contains(fase.prova) {
                    Section {
                        ForEach(Array(opzioni.wrappedValue.enumerated()), id: \.offset) { i, o in
                            HStack {
                                Text(o)
                                Spacer()
                                if fase.prova == "scelta" {
                                    Image(systemName: fase.soluzione == o ? "checkmark.circle.fill" : "circle").foregroundStyle(fase.soluzione == o ? Theme.olive : Theme.dim)
                                        .onTapGesture { fase.soluzione = o }
                                }
                            }
                        }
                        .onDelete { opzioni.wrappedValue.remove(atOffsets: $0) }
                        .onMove { opzioni.wrappedValue.move(fromOffsets: $0, toOffset: $1) }
                        HStack {
                            TextField(fase.prova == "scelta" ? "Nuova risposta" : "Nuovo elemento", text: $nuovaOpzione)
                            Button { opzioni.wrappedValue.append(nuovaOpzione); nuovaOpzione = "" } label: { Image(systemName: "plus.circle.fill") }
                                .disabled(nuovaOpzione.isEmpty)
                        }
                    } header: { Text(fase.prova == "scelta" ? "Risposte (tocca il cerchio di quella giusta)" : "Elementi nell'ordine giusto") }
                    footer: { Text(fase.prova == "ordina" ? "Le squadre li vedono mescolati e devono rimetterli in quest'ordine. Tieni premuto per spostare." : "") }
                }
                Section {
                    Picker("Si sblocca con", selection: $fase.sblocco) {
                        ForEach(NomiMissione.sblocchi, id: \.0) { Label($0.1, systemImage: $0.2).tag($0.0) }
                    }
                    switch fase.sblocco {
                    case "codice":
                        if fase.prova == "stima" {
                            TextField("Valore giusto", text: $fase.soluzione).keyboardType(.decimalPad).font(Theme.mono(14))
                            Stepper("Tolleranza: ± \(Int(fase.tolleranza ?? 0))", value: Binding(get: { fase.tolleranza ?? 0 }, set: { fase.tolleranza = $0 }), in: 0...10000, step: 1)
                        } else if fase.prova == "scelta" {
                            LabeledContent("Risposta giusta", value: fase.soluzione.isEmpty ? "scegli sopra" : fase.soluzione)
                        } else if fase.prova == "ordina" {
                            Text("Si sblocca rimettendo in ordine gli elementi qui sopra.").font(.footnote).foregroundStyle(Theme.dim)
                        } else {
                            TextField("Risposte giuste, separate da |", text: $fase.soluzione)
                                .textInputAutocapitalization(.characters).autocorrectionDisabled().font(Theme.mono(14))
                        }
                    case "gps":
                        HStack {
                            TextField("Lat", value: $fase.lat, format: .number.precision(.fractionLength(6))).keyboardType(.decimalPad)
                            TextField("Lon", value: $fase.lon, format: .number.precision(.fractionLength(6))).keyboardType(.decimalPad)
                        }
                        .font(Theme.mono(13))
                        Button { if let l = location.location { fase.lat = l.coordinate.latitude; fase.lon = l.coordinate.longitude } } label: {
                            Label("Usa la mia posizione attuale", systemImage: "location.fill")
                        }
                        Stepper("Raggio: \(fase.raggio) m", value: $fase.raggio, in: 3...500, step: fase.raggio < 30 ? 1 : 10)
                        Toggle("Mostra direzione e distanza alla squadra", isOn: Binding(get: { fase.mostra_direzione ?? false }, set: { fase.mostra_direzione = $0 }))
                    case "foto":
                        TextField("Cosa deve mostrare la foto (lo vedi tu)", text: $fase.soluzione)
                    case "qr":
                        Text("Il QR si genera al salvataggio: lo stampi da “QR da stampare” e lo nascondi sul campo.")
                            .font(.footnote).foregroundStyle(Theme.dim)
                    default: EmptyView()
                    }
                } header: { Text("Sblocco") } footer: {
                    if fase.sblocco == "codice" && !["stima", "scelta", "ordina"].contains(fase.prova) { Text("Maiuscole e spazi non contano. Anche le risposte dei rami sbloccano la fase.") }
                }
                Section("Punteggio e tempo") {
                    Stepper("Punti: \(fase.punti)", value: $fase.punti, in: 0...1000, step: 5)
                    Stepper(fase.tempo_min == 0 ? "Tempo della fase: libero" : "Tempo della fase: \(fase.tempo_min) min", value: $fase.tempo_min, in: 0...240, step: 5)
                }
                Section {
                    ForEach($fase.indizi) { $i in
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Indizio", text: $i.testo)
                            Stepper((i.dopo_min ?? 0) > 0 ? "Arriva da solo dopo \(i.dopo_min ?? 0) min" : "A richiesta: costa \(i.costo) punti",
                                    value: Binding(get: { (i.dopo_min ?? 0) > 0 ? -(i.dopo_min ?? 0) : i.costo },
                                                   set: { v in if v < 0 { i.dopo_min = -v; i.costo = 0 } else { i.dopo_min = 0; i.costo = v } }),
                                    in: -120...100)
                                .font(.caption)
                        }
                    }
                    .onDelete { fase.indizi.remove(atOffsets: $0) }
                    Button { fase.indizi.append(JIndizio(testo: "", costo: 2)) } label: { Label("Aggiungi indizio", systemImage: "lightbulb") }
                } header: { Text("Indizi") } footer: { Text("Con − sotto lo zero l'indizio diventa automatico: arriva da solo dopo quei minuti, gratis (come In-Evasion ed Escape Team).") }
                Section {
                    ForEach($fase.rami) { $r in
                        VStack(alignment: .leading) {
                            TextField("Se rispondono…", text: $r.risposta).textInputAutocapitalization(.characters)
                            Picker("vai a", selection: $r.va_a) {
                                Text("—").tag("")
                                ForEach(altre.filter { $0.id != fase.id }) { Text($0.titolo).tag($0.id) }
                            }
                        }
                    }
                    .onDelete { fase.rami.remove(atOffsets: $0) }
                    Button { fase.rami.append(JRamo()) } label: { Label("Aggiungi ramo", systemImage: "arrow.triangle.branch") }
                    Picker("Altrimenti vai a", selection: $fase.prossima) {
                        Text("la fase successiva").tag("")
                        ForEach(altre.filter { $0.id != fase.id }) { Text($0.titolo).tag($0.id) }
                    }
                } header: { Text("Rami") } footer: { Text("Con i rami una risposta diversa porta a una fase diversa (scelte con conseguenze).") }
                if altre.contains(where: { $0.id != fase.id }) {
                    Section {
                        ForEach(altre.filter { $0.id != fase.id }) { a in
                            Toggle(a.titolo, isOn: Binding(get: { (fase.richiede ?? []).contains(a.id) },
                                                           set: { v in var r = fase.richiede ?? []; if v { r.append(a.id) } else { r.removeAll { $0 == a.id } }; fase.richiede = r }))
                        }
                    } header: { Text("Prerequisiti") } footer: { Text("La fase si apre solo dopo aver completato quelle scelte.") }
                }
                if let errore { Text(errore).foregroundStyle(Theme.red) }
            }
            .navigationTitle(fase.titolo).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fatto") {
                        fase.indizi.removeAll { $0.testo.trimmingCharacters(in: .whitespaces).isEmpty }
                        fase.rami.removeAll { $0.risposta.trimmingCharacters(in: .whitespaces).isEmpty }
                        salva(fase); dismiss()
                    }
                }
            }
            .onChange(of: foto) { item in
                guard let item else { return }
                caricando = true
                Task {
                    if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d),
                       let jpg = img.ridotta(lato: 1600).jpegData(compressionQuality: 0.8) {
                        do { try await JsocClient.shared.caricaDati("/api/missioni/\(missione)/fasi/\(fase.id)/immagine", dati: jpg); fase.immagine = true }
                        catch { errore = error.localizedDescription }
                    }
                    caricando = false; foto = nil
                }
            }
            .fileImporter(isPresented: $scegliAudio, allowedContentTypes: [.audio]) { esito in
                guard case .success(let u) = esito else { return }
                Task {
                    let ok = u.startAccessingSecurityScopedResource()
                    defer { if ok { u.stopAccessingSecurityScopedResource() } }
                    guard let d = try? Data(contentsOf: u) else { errore = "Audio non leggibile"; return }
                    do {
                        try await JsocClient.shared.caricaDati("/api/missioni/\(missione)/fasi/\(fase.id)/audio", dati: d)
                        fase.audio = u.pathExtension.lowercased().isEmpty ? "m4a" : u.pathExtension.lowercased()
                    } catch { errore = error.localizedDescription }
                }
            }
        }
    }
}

// MARK: - Diretta del GM

struct DirettaView: View {
    let id: Int
    @State private var d: JDiretta?
    @State private var foto: [Int: UIImage] = [:]
    @State private var errore: String?
    @State private var messaggio = ""
    @State private var a: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let errore { ErrorCard(text: errore) }
                if let d {
                    Card(title: "Messaggi", icon: "bubble.left.and.bubble.right.fill") {
                        HStack {
                            TextField(a == nil ? "Scrivi a tutte le squadre" : "Scrivi a \(d.squadre.first { $0.id == a }?.nome ?? "")", text: $messaggio)
                                .padding(10).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                            Button { Task { await scrivi() } } label: { Image(systemName: "paperplane.fill") }.disabled(messaggio.isEmpty).tint(Theme.olive)
                        }
                        if a != nil { Button("Scrivi a tutte") { a = nil }.font(.caption) }
                        ForEach((d.messaggi ?? []).prefix(10)) { x in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: x.da_gm == 1 ? "person.badge.shield.checkmark.fill" : "hand.raised.fill")
                                    .foregroundStyle(x.da_gm == 1 ? Theme.olive : Theme.amber)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(x.testo).font(.subheadline)
                                    Text("\(x.squadra ?? "tutti") · \(x.callsign ?? "") · \(Date(timeIntervalSince1970: x.ts).formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(Theme.dim)
                                }
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    if !d.prove.isEmpty {
                        Card(title: "Foto da giudicare", icon: "camera.fill", trailing: "\(d.prove.count)") {
                            ForEach(d.prove) { p in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("\(p.squadra) · \(p.fase)").font(.headline)
                                    if !p.soluzione.isEmpty { Text("Atteso: \(p.soluzione)").font(.caption).foregroundStyle(Theme.dim) }
                                    if let img = foto[p.id] {
                                        Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 260).clipShape(RoundedRectangle(cornerRadius: 12))
                                    } else {
                                        ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                                            .task { if let dd = try? await JsocClient.shared.scaricaDati("/api/prove/\(p.id)/foto") { foto[p.id] = UIImage(data: dd) } }
                                    }
                                    HStack {
                                        Button { Task { try? await JsocClient.shared.giudica(p.id, ok: false); await carica() } } label: { Label("Rifiuta", systemImage: "xmark") }
                                            .buttonStyle(.bordered).tint(Theme.red)
                                        Button { Task { try? await JsocClient.shared.giudica(p.id, ok: true); await carica() } } label: { Label("Approva", systemImage: "checkmark") }
                                            .buttonStyle(.borderedProminent).tint(Theme.olive)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    Card(title: "Classifica", icon: "trophy.fill", trailing: "\(d.squadre.count) squadre") {
                        if d.squadre.isEmpty { Text("Nessuna squadra è ancora entrata.").foregroundStyle(Theme.dim) }
                        ForEach(Array(d.squadre.enumerated()), id: \.element.id) { i, s in
                            HStack(spacing: 12) {
                                Text("\(i + 1)").font(Theme.mono(18, .heavy)).foregroundStyle(i == 0 ? Theme.amber : Theme.dim).frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.nome).font(.headline)
                                    Text(s.fine != nil ? "completata · \(tempo(s))" : "fase \(min(s.fatte + 1, d.n_fasi))/\(d.n_fasi): \(s.fase ?? "—")")
                                        .font(.caption).foregroundStyle(s.fine != nil ? Theme.olive : Theme.dim)
                                    Text("\(s.membri.joined(separator: ", ")) · errori \(s.errori) · indizi \(s.indizi)").font(.caption2).foregroundStyle(Theme.dim)
                                }
                                Spacer()
                                Text("\(s.punti)").font(Theme.mono(20, .heavy)).contentTransition(.numericText())
                            }
                            .contextMenu {
                                Button { a = s.id } label: { Label("Scrivi a \(s.nome)", systemImage: "bubble.left") }
                                Button { Task { await punti(s.id, 5) } } label: { Label("+5 punti", systemImage: "plus") }
                                Button { Task { await punti(s.id, 10) } } label: { Label("+10 punti", systemImage: "plus.circle") }
                                Button(role: .destructive) { Task { await punti(s.id, -5) } } label: { Label("−5 punti", systemImage: "minus") }
                            }
                            .comparsa(i)
                        }
                        Text("Tieni premuta una squadra per scriverle o darle punti.").font(.caption2).foregroundStyle(Theme.dim)
                    }
                } else { ProgressView().padding(40) }
            }
            .padding(14)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: d?.messaggi?.first?.id)
        }
        .task {
            while !Task.isCancelled {
                await carica()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    func tempo(_ s: JSquadraDiretta) -> String {
        guard let a = s.inizio, let b = s.fine else { return "" }
        let m = Int(b - a) / 60
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m) min"
    }

    func carica() async {
        do { d = try await JsocClient.shared.diretta(id); errore = nil } catch { errore = error.localizedDescription }
    }
    func scrivi() async {
        let t = messaggio; messaggio = ""
        do { d = try await JsocClient.shared.messaggioGM(id, t, partita: a) } catch { errore = error.localizedDescription }
    }
    func punti(_ pid: Int, _ delta: Int) async {
        haptic(.medium)
        do { d = try await JsocClient.shared.puntiGM(pid, delta, motivo: delta > 0 ? "bonus" : "penalità") } catch { errore = error.localizedDescription }
    }
}

// MARK: - Gioco della squadra

final class LettoreAudio: ObservableObject {
    @Published var suona = false
    private var p: AVAudioPlayer?
    func suona(_ u: URL) {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        p = try? AVAudioPlayer(contentsOf: u); p?.play(); suona = p?.isPlaying ?? false
    }
    func ferma() { p?.stop(); suona = false }
}

struct GiocaMissioneView: View {
    let riga: JMissioneRiga
    @ObservedObject private var jsoc = JsocClient.shared
    @EnvironmentObject var location: LocationService
    @AppStorage("missioni.squadra") private var nomeSquadra = ""
    @StateObject private var lettore = LettoreAudio()
    @State private var codiceAvvio = ""
    @State private var p: JPartita?
    @State private var risposte: [String: String] = [:]
    @State private var ordine: [String: [String]] = [:]
    @State private var messaggio: (String, Bool)?
    @State private var lavoro = false
    @State private var scanner: String?
    @State private var foto: PhotosPickerItem?
    @State private var immagini: [String: UIImage] = [:]
    @State private var errore: String?
    @State private var chiediAiuto = false
    @State private var testoAiuto = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let errore { ErrorCard(text: errore) }
                if let p { gioco(p) } else { entra }
            }
            .padding(14)
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: p?.fase?.id)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: messaggio?.0)
        }
        .navigationTitle(riga.titolo).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if p != nil {
                Button { chiediAiuto = true } label: { Label("Aiuto GM", systemImage: "hand.raised.fill") }
            }
        }
        .alert("Chiedi aiuto al GM", isPresented: $chiediAiuto) {
            TextField("Cosa vi serve?", text: $testoAiuto)
            Button("Manda") { let t = testoAiuto; testoAiuto = ""; Task { if let pid = p?.id, let n = try? await jsoc.aiuto(pid, t.isEmpty ? "Chiediamo aiuto" : t) { p = n; messaggio = ("Richiesta mandata al GM", true) } } }
            Button("Annulla", role: .cancel) {}
        }
        .task(id: p?.id) {
            if p == nil, let pid = riga.mia_partita { p = try? await jsoc.partita(pid) }
            while !Task.isCancelled, let pid = p?.id {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if let n = try? await jsoc.partita(pid) { aggiorna(n) }
            }
        }
        .sheet(isPresented: Binding(get: { scanner != nil }, set: { if !$0 { scanner = nil } })) {
            ZStack(alignment: .bottom) {
                CodeScanner { s, _ in
                    guard s.hasPrefix("jsoctak-fase:") else { return }
                    let fid = scanner
                    scanner = nil
                    Task { await tenta(["qr": s], fase: fid) }
                }
                .ignoresSafeArea()
                Text("Inquadra il QR della fase").font(.subheadline.weight(.semibold))
                    .padding(12).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 40)
            }
        }
        .onChange(of: foto) { item in
            guard let item, let pid = p?.id else { return }
            Task {
                lavoro = true
                if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d),
                   let jpg = img.ridotta(lato: 1600).jpegData(compressionQuality: 0.75) {
                    do { try await jsoc.caricaDati("/api/partite/\(pid)/prova", dati: jpg); if let n = try? await jsoc.partita(pid) { aggiorna(n) } }
                    catch { errore = error.localizedDescription }
                }
                foto = nil; lavoro = false
            }
        }
        .onDisappear { lettore.ferma() }
    }

    var entra: some View {
        Card(title: "Entra con la tua squadra", icon: "person.3.fill") {
            if !riga.descrizione.isEmpty { Text(riga.descrizione).font(.subheadline) }
            TextField("Nome della squadra (es. ALFA)", text: $nomeSquadra)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .font(Theme.mono(16, .bold)).padding(10).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
            TextField("Codice di avvio (se il GM l'ha dato)", text: $codiceAvvio)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .font(Theme.mono(14)).padding(10).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
            Text("Chi usa lo stesso nome entra nella stessa squadra e vede le stesse fasi.").font(.caption).foregroundStyle(Theme.dim)
            Button {
                Task {
                    do { p = try await jsoc.entraPartita(riga.id, nome: nomeSquadra, codice: codiceAvvio) } catch { errore = error.localizedDescription }
                }
            } label: { Label("Inizia la missione", systemImage: "flag.checkered") }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(nomeSquadra.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .comparsa(0)
    }

    @ViewBuilder func gioco(_ p: JPartita) -> some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.nome).font(.title3.weight(.heavy))
                    Text(p.membri.joined(separator: " · ")).font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(p.punti)").font(Theme.mono(26, .heavy)).foregroundStyle(Theme.olive).contentTransition(.numericText())
                    Text("punti").font(.caption2).foregroundStyle(Theme.dim)
                }
            }
            ProgressView(value: Double(p.fatte.count), total: Double(max(1, p.n_fasi))).tint(Theme.olive)
            HStack {
                Text("Fasi \(p.fatte.count)/\(p.n_fasi)\((p.n_bonus ?? 0) > 0 ? " · bonus \(p.bonus_fatte?.count ?? 0)/\(p.n_bonus ?? 0)" : "")").font(.caption).foregroundStyle(Theme.dim)
                Spacer()
                if p.durata_min > 0, let i = p.inizio, p.fine == nil {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        let resta = max(0, i + Double(p.durata_min * 60) - Date().timeIntervalSince1970)
                        Text(String(format: "%02d:%02d", Int(resta) / 60, Int(resta) % 60))
                            .font(Theme.mono(14, .heavy)).foregroundStyle(resta < 300 ? Theme.red : .white)
                    }
                }
            }
        }
        .comparsa(0)
        if let gm = p.messaggi?.first(where: { $0.da_gm == 1 }) {
            Label(gm.testo, systemImage: "person.badge.shield.checkmark.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.cyan)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12).background(Theme.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .transition(.move(edge: .top).combined(with: .opacity))
        }
        if let m = messaggio {
            Label(m.0, systemImage: m.1 ? "checkmark.seal.fill" : "xmark.octagon.fill")
                .font(.subheadline.weight(.bold)).foregroundStyle(m.1 ? Theme.olive : Theme.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12).background((m.1 ? Theme.olive : Theme.red).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
        if p.in_attesa == true {
            Card(title: "In attesa del via", icon: "hourglass") {
                Text("La missione parte alle \(p.avvio?.replacingOccurrences(of: "T", with: " ") ?? "").").font(.headline)
                Text("Le fasi si aprono da sole all'orario stabilito dal GM.").font(.caption).foregroundStyle(Theme.dim)
            }
        } else if p.fine != nil {
            Card(title: "Missione completata", icon: "trophy.fill") {
                Text("\(p.punti) punti · \(p.errori) errori").font(.title3.weight(.bold))
                ForEach(p.fatte, id: \.self) { Label($0, systemImage: "checkmark").font(.subheadline) }
                ForEach(p.bonus_fatte ?? [], id: \.self) { Label($0, systemImage: "star.fill").font(.subheadline).foregroundStyle(Theme.amber) }
            }
            .comparsa(1)
        } else if p.scaduta {
            Card(title: "Tempo scaduto", icon: "timer") { Text("La missione è finita con \(p.punti) punti.").foregroundStyle(Theme.dim) }
        } else if let f = p.fase {
            faseCard(p, f, bonus: false).id(f.id).transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
        }
        if p.in_attesa != true && p.fine == nil && !p.scaduta, let b = p.bonus, !b.isEmpty {
            Text("MISSIONI BONUS").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.amber).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
            ForEach(Array(b.enumerated()), id: \.element.id) { i, f in faseCard(p, f, bonus: true).comparsa(i + 2) }
        }
    }

    @ViewBuilder func faseCard(_ p: JPartita, _ f: JFaseVista, bonus: Bool) -> some View {
        Card(title: bonus ? "Bonus · \(NomiMissione.prova(f.prova).0)" : "Fase \(p.fatte.count + 1) · \(NomiMissione.prova(f.prova).0)",
             icon: bonus ? "star.fill" : NomiMissione.prova(f.prova).1, trailing: "\(f.punti) pt") {
            Text(f.titolo).font(.title2.weight(.heavy))
            if let b = f.bloccata_da, !b.isEmpty {
                Label("Prima completate: " + b.joined(separator: ", "), systemImage: "lock.fill").font(.subheadline.weight(.bold)).foregroundStyle(Theme.amber)
            }
            if f.tempo_min > 0, let i = f.inizio, !bonus {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let resta = i + Double(f.tempo_min * 60) - Date().timeIntervalSince1970
                    Label(resta > 0 ? String(format: "Tempo della fase %02d:%02d", Int(resta) / 60, Int(resta) % 60) : "Tempo della fase finito",
                          systemImage: "hourglass").font(Theme.mono(13, .bold)).foregroundStyle(resta < 60 ? Theme.red : Theme.amber)
                }
            }
            if !f.testo.isEmpty {
                Text(f.testo).font(f.prova == "cifrario" ? Theme.mono(16, .bold) : .body).textSelection(.enabled)
            }
            if !(f.audio ?? "").isEmpty {
                Button { Task { await suonaAudio(p, f) } } label: {
                    Label(lettore.suona ? "Ferma la narrazione" : "Ascolta la narrazione", systemImage: lettore.suona ? "stop.circle.fill" : "play.circle.fill")
                }
                .buttonStyle(.bordered).tint(Theme.cyan)
            }
            if f.immagine {
                if let img = immagini[f.id] { Image(uiImage: img).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12)) }
                else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 60)
                        .task { if let d = try? await jsoc.scaricaDati("/api/missioni/\(p.missione)/fasi/\(f.id)/immagine") { immagini[f.id] = UIImage(data: d) } }
                }
            }
            strumentiUtili(f)
            if f.sblocco == "gps", let la = f.lat, let lo = f.lon { DirezionePunto(lat: la, lon: lo, raggio: f.raggio) }
            if !f.indizi_usati.isEmpty || f.prossimo_indizio_costo != nil || f.prossimo_indizio_auto_min != nil {
                Divider().overlay(Theme.stroke)
                ForEach(Array(f.indizi_usati.enumerated()), id: \.offset) { _, t in Label(t, systemImage: "lightbulb.fill").font(.subheadline).foregroundStyle(Theme.amber) }
                if let m = f.prossimo_indizio_auto_min, m > 0 {
                    Label("Prossimo indizio gratis tra \(Int(m.rounded(.up))) min", systemImage: "clock").font(.caption).foregroundStyle(Theme.dim)
                }
                if let costo = f.prossimo_indizio_costo {
                    Button { Task { if let n = try? await jsoc.indizio(p.id, fase: f.id) { aggiorna(n) } } } label: { Label("Chiedi un indizio (−\(costo) punti)", systemImage: "questionmark.circle") }
                        .buttonStyle(.bordered).tint(Theme.amber)
                }
            }
            Divider().overlay(Theme.stroke)
            sblocco(p, f, bonus: bonus)
        }
    }

    @ViewBuilder func sblocco(_ p: JPartita, _ f: JFaseVista, bonus: Bool) -> some View {
        let fid = bonus ? f.id : nil
        switch f.sblocco {
        case "codice":
            if f.prova == "scelta", let o = f.opzioni, !o.isEmpty {
                ForEach(o, id: \.self) { s in
                    Button { Task { await tenta(["valore": s], fase: fid) } } label: { Text(s).frame(maxWidth: .infinity) }.buttonStyle(.bordered).tint(Theme.olive)
                }
            } else if f.prova == "ordina", let o = f.opzioni, !o.isEmpty {
                let lista = ordine[f.id] ?? o
                VStack(spacing: 6) {
                    ForEach(Array(lista.enumerated()), id: \.element) { i, x in
                        HStack {
                            Text("\(i + 1)").font(Theme.mono(14, .heavy)).foregroundStyle(Theme.olive).frame(width: 22)
                            Text(x).frame(maxWidth: .infinity, alignment: .leading)
                            Button { sposta(f.id, lista, i, -1) } label: { Image(systemName: "chevron.up") }.disabled(i == 0)
                            Button { sposta(f.id, lista, i, 1) } label: { Image(systemName: "chevron.down") }.disabled(i == lista.count - 1)
                        }
                        .padding(10).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: lista)
                Button { Task { await tenta(["valore": lista.joined(separator: "|")], fase: fid) } } label: { Text("Conferma l'ordine") }.buttonStyle(PrimaryButtonStyle())
            } else {
                if !f.scelte.isEmpty {
                    ForEach(f.scelte, id: \.self) { s in
                        Button { Task { await tenta(["valore": s], fase: fid) } } label: { Text(s).frame(maxWidth: .infinity) }.buttonStyle(.bordered).tint(Theme.olive)
                    }
                }
                let b = Binding(get: { risposte[f.id] ?? "" }, set: { risposte[f.id] = $0 })
                TextField(f.prova == "stima" ? "Il tuo numero" : "Codice o risposta", text: b)
                    .keyboardType(f.prova == "stima" ? .decimalPad : .default)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .font(Theme.mono(20, .heavy)).multilineTextAlignment(.center)
                    .padding(12).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                    .onSubmit { Task { await tenta(["valore": b.wrappedValue], fase: fid) } }
                Button { Task { await tenta(["valore": b.wrappedValue], fase: fid) } } label: {
                    HStack { if lavoro { ProgressView().tint(.black) }; Text(f.prova == "stima" ? "Prova il numero" : "Prova il codice") }
                }
                .buttonStyle(PrimaryButtonStyle()).disabled(b.wrappedValue.isEmpty || lavoro)
            }
        case "qr":
            Button { scanner = fid ?? "" } label: { Label("Scansiona il QR trovato", systemImage: "qrcode.viewfinder") }.buttonStyle(PrimaryButtonStyle())
        case "gps":
            Text("Raggiungi il punto (entro \(f.raggio) m) e poi conferma.").font(.footnote).foregroundStyle(Theme.dim)
            Button {
                guard let l = location.location else { messaggio = ("Posizione GPS non ancora disponibile", false); return }
                Task { await tenta(["lat": l.coordinate.latitude, "lon": l.coordinate.longitude], fase: fid) }
            } label: { Label("Sono arrivato", systemImage: "location.fill") }.buttonStyle(PrimaryButtonStyle())
        case "foto":
            if bonus {
                Text("La foto si manda al GM dalla fase in corso; per i bonus chiedete conferma al GM.").font(.caption).foregroundStyle(Theme.dim)
            } else if f.prova_stato == "attesa" {
                Label("Foto mandata: il GM la sta guardando", systemImage: "hourglass").foregroundStyle(Theme.amber)
            } else {
                if f.prova_stato == "no" { Label("Il GM ha rifiutato la foto: riprova", systemImage: "xmark").foregroundStyle(Theme.red) }
                PhotosPicker(selection: $foto, matching: .images) {
                    Label(lavoro ? "Invio…" : "Manda la foto al GM", systemImage: "camera.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        default:
            Button { Task { await tenta([:], fase: fid) } } label: { Label("Avanti", systemImage: "arrow.right") }.buttonStyle(PrimaryButtonStyle())
        }
    }

    func sposta(_ fid: String, _ lista: [String], _ i: Int, _ d: Int) {
        var l = lista
        let j = i + d
        guard l.indices.contains(j) else { return }
        l.swapAt(i, j); haptic()
        ordine[fid] = l
    }

    /// scorciatoie agli strumenti adatti alla prova
    @ViewBuilder func strumentiUtili(_ f: JFaseVista) -> some View {
        switch f.prova {
        case "cifrario":
            NavigationLink { CipherTab().background(Theme.bg.ignoresSafeArea()) } label: { Label("Apri il decifratore", systemImage: "lock.open.fill") }
                .buttonStyle(.bordered).tint(Theme.cyan)
        case "orientamento":
            HStack {
                NavigationLink { MirinoView() } label: { Label("Mirino", systemImage: "scope") }.buttonStyle(.bordered).tint(Theme.cyan)
                NavigationLink { TriangView().background(Theme.bg.ignoresSafeArea()) } label: { Label("Triangolazione", systemImage: "triangle") }.buttonStyle(.bordered).tint(Theme.cyan)
                NavigationLink { CampoView().background(Theme.bg.ignoresSafeArea()) } label: { Label("Coordinate", systemImage: "map") }.buttonStyle(.bordered).tint(Theme.cyan)
            }
            .font(.caption)
        default: EmptyView()
        }
    }

    func suonaAudio(_ p: JPartita, _ f: JFaseVista) async {
        if lettore.suona { lettore.ferma(); return }
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("narrazione_\(p.missione)_\(f.id).\(f.audio ?? "m4a")")
        if !FileManager.default.fileExists(atPath: u.path) {
            guard let d = try? await jsoc.scaricaDati("/api/missioni/\(p.missione)/fasi/\(f.id)/audio") else { messaggio = ("Audio non disponibile", false); return }
            try? d.write(to: u, options: .atomic)
        }
        lettore.suona(u)
    }

    func aggiorna(_ n: JPartita) {
        if let vecchia = p, vecchia.fatte.count < n.fatte.count, messaggio == nil || messaggio?.1 == false {
            messaggio = ("Fase superata", true); UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        if let nuovo = n.messaggi?.first(where: { $0.da_gm == 1 }), nuovo.id != p?.messaggi?.first(where: { $0.da_gm == 1 })?.id, p != nil {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        p = n
    }

    func tenta(_ corpo: [String: Any], fase: String?) async {
        guard let pid = p?.id else { return }
        var c = corpo
        if let fase, !fase.isEmpty { c["fase"] = fase }
        lavoro = true
        do {
            let e = try await jsoc.tenta(pid, c)
            messaggio = (e.messaggio, e.esito)
            UINotificationFeedbackGenerator().notificationOccurred(e.esito ? .success : .error)
            if e.esito { if let f = fase ?? p?.fase?.id { risposte[f] = nil } }
            p = e.stato
        } catch { messaggio = (error.localizedDescription, false) }
        lavoro = false
    }
}

/// Freccia e distanza verso il punto della fase (se il GM ha scelto di mostrarla).
struct DirezionePunto: View {
    let lat: Double; let lon: Double; let raggio: Int
    @EnvironmentObject var location: LocationService
    var body: some View {
        let dove = location.location
        let d = dove.map { CLLocation(latitude: lat, longitude: lon).distance(from: $0) }
        let az = dove.map { Self.azimut($0.coordinate, CLLocationCoordinate2D(latitude: lat, longitude: lon)) } ?? 0
        HStack(spacing: 14) {
            Image(systemName: "location.north.fill").font(.system(size: 34)).foregroundStyle((d ?? 999) <= Double(raggio) ? Theme.olive : Theme.cyan)
                .rotationEffect(.degrees(az - (location.heading ?? 0)))
                .animation(.spring(response: 0.4), value: location.heading)
            VStack(alignment: .leading, spacing: 2) {
                Text(d.map { $0 >= 1000 ? String(format: "%.1f km", $0 / 1000) : "\(Int($0)) m" } ?? "attendo il GPS").font(Theme.mono(22, .heavy))
                Text((d ?? 999) <= Double(raggio) ? "Ci sei: conferma l'arrivo" : String(format: "direzione %03.0f°", az)).font(.caption).foregroundStyle(Theme.dim)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
    static func azimut(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let f1 = a.latitude * .pi / 180, f2 = b.latitude * .pi / 180, dl = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dl) * cos(f2), x = cos(f1) * sin(f2) - sin(f1) * cos(f2) * cos(dl)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}
