import SwiftUI
import PhotosUI
import CoreLocation

// MARK: - Missioni a fasi (fasi E)
// Il Game Master crea la missione (fasi, sblocchi, indizi, rami, punti); le squadre la giocano dai telefoni.
// Le soluzioni, i QR e i punti GPS restano sul server: la squadra vede solo la fase a cui è arrivata.

struct JIndizio: Codable, Hashable, Identifiable {
    var id = UUID(); var testo = ""; var costo = 0
    enum CodingKeys: String, CodingKey { case testo, costo }
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
}

struct JRegole: Codable, Hashable { var penalita_errore = 5; var durata_min = 0; var mostra_scelte: Bool? = false; var mostra_classifica: Bool? = false }

struct JMissione: Codable, Identifiable {
    let id: Int
    var titolo: String
    var descrizione: String
    var stato: String
    var regole: JRegole
    var fasi: [JFase]
}

struct JMissioneRiga: Codable, Identifiable { let id: Int; let titolo: String; let descrizione: String; let stato: String; let n_fasi: Int; let gm: Bool; let mia_partita: Int?; let squadre: Int }

struct JFaseVista: Codable {
    let id: String; let titolo: String; let testo: String; let prova: String; let sblocco: String
    let punti: Int; let tempo_min: Int; let immagine: Bool; let raggio: Int
    let indizi_usati: [String]; let prossimo_indizio_costo: Int?; let scelte: [String]; let prova_stato: String?; let inizio: Double?
}

struct JPartita: Codable {
    let id: Int; let missione: Int; let titolo: String; let nome: String; let membri: [String]
    let inizio: Double?; let fine: Double?; let punti: Int; let errori: Int; let durata_min: Int; let scaduta: Bool
    let n_fasi: Int; let fatte: [String]; let fase: JFaseVista?
}

struct JEsito: Codable { let esito: Bool; let messaggio: String; let stato: JPartita }

struct JSquadraDiretta: Codable, Identifiable { let id: Int; let nome: String; let membri: [String]; let punti: Int; let errori: Int; let fatte: Int; let fase: String?; let inizio: Double?; let fine: Double?; let indizi: Int }
struct JProvaDiretta: Codable, Identifiable { let id: Int; let squadra: String; let fase: String; let soluzione: String; let t: Double; let da: String }
struct JDiretta: Codable { let squadre: [JSquadraDiretta]; let prove: [JProvaDiretta]; let n_fasi: Int }

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
    func entraPartita(_ mid: Int, nome: String) async throws -> JPartita { try await send("/api/missioni/\(mid)/partite", "POST", ["nome": nome]) }
    func partita(_ id: Int) async throws -> JPartita { try await get("/api/partite/\(id)") }
    func tenta(_ id: Int, _ corpo: [String: Any]) async throws -> JEsito { try await send("/api/partite/\(id)/tenta", "POST", corpo) }
    func indizio(_ id: Int) async throws -> JPartita { try await send("/api/partite/\(id)/indizio", "POST", [String: String]()) }
    func diretta(_ mid: Int) async throws -> JDiretta { try await get("/api/missioni/\(mid)/diretta") }
    func giudica(_ prova: Int, ok: Bool) async throws { let _: JOk = try await send("/api/prove/\(prova)", "POST", ["ok": ok]) }
}


enum NomiMissione {
    static let prove: [(String, String, String)] = [
        ("libera", "Libera", "text.alignleft"), ("cifrario", "Cifrario", "lock.open.fill"),
        ("orientamento", "Orientamento", "location.north.line.fill"), ("documento", "Documento / intelligence", "doc.text.magnifyingglass"),
        ("campo", "Prova da campo", "figure.run"),
    ]
    static let sblocchi: [(String, String, String)] = [
        ("codice", "Codice o risposta", "number"), ("qr", "QR sul campo", "qrcode"),
        ("gps", "Arrivare in un punto", "location.fill"), ("foto", "Foto approvata dal GM", "camera.fill"),
        ("nessuno", "Nessuno (solo lettura)", "arrow.right"),
    ]
    static func prova(_ k: String) -> (String, String) { let x = prove.first { $0.0 == k } ?? prove[0]; return (x.1, x.2) }
    static func sblocco(_ k: String) -> (String, String) { let x = sblocchi.first { $0.0 == k } ?? sblocchi[0]; return (x.1, x.2) }
}

// MARK: - Elenco

struct MissioniView: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @State private var righe: [JMissioneRiga] = []
    @State private var errore: String?
    @State private var nuova = false
    @State private var titoloNuova = ""

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
                        ForEach(gioca) { r in
                            NavigationLink { GiocaMissioneView(riga: r) } label: { riga(r) }
                        }
                    }
                    let mie = righe.filter { $0.gm }
                    if !mie.isEmpty {
                        Section("Game Master") {
                            ForEach(mie) { r in
                                NavigationLink { MissioneGMView(id: r.id) } label: { riga(r) }
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
                Button { titoloNuova = ""; nuova = true } label: { Label("Nuova missione", systemImage: "plus") }
            }
        }
        .task { await carica() }
        .sheet(isPresented: $nuova) {
            NavigationStack {
                Form {
                    Section { TextField("Titolo (es. Fase E · Operazione Lupo)", text: $titoloNuova) }
                    footer: { Text("Diventi il Game Master: prepari le fasi e la attivi quando è pronta.") }
                }
                .navigationTitle("Nuova missione").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annulla") { nuova = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Crea") {
                            Task {
                                do { _ = try await jsoc.nuovaMissione(titoloNuova); nuova = false; await carica() }
                                catch { errore = error.localizedDescription }
                            }
                        }
                        .disabled(titoloNuova.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
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
            Button("Elimina", role: .destructive) {
                Task { try? await jsoc.cancellaMissione(id); dismiss() }
            }
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
                }
                Section {
                    ForEach(Array(mm.fasi.enumerated()), id: \.element.id) { i, f in
                        Button { modifica = f } label: {
                            HStack(spacing: 12) {
                                Text("\(i + 1)").font(Theme.mono(15, .heavy)).foregroundStyle(Theme.olive).frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.titolo).font(.headline).foregroundStyle(.white)
                                    HStack(spacing: 8) {
                                        Label(NomiMissione.prova(f.prova).0, systemImage: NomiMissione.prova(f.prova).1)
                                        Label(NomiMissione.sblocco(f.sblocco).0, systemImage: NomiMissione.sblocco(f.sblocco).1)
                                    }
                                    .font(.caption2).foregroundStyle(Theme.dim).lineLimit(1)
                                    if !f.rami.isEmpty { Text("\(f.rami.count) rami").font(.caption2).foregroundStyle(Theme.amber) }
                                }
                                Spacer()
                                Text("\(f.punti) pt").font(Theme.mono(12, .bold)).foregroundStyle(Theme.dim)
                            }
                        }
                    }
                    .onMove { m?.fasi.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { m?.fasi.remove(atOffsets: $0) }
                    Button { modifica = JFase(titolo: "Fase \((m?.fasi.count ?? 0) + 1)") } label: { Label("Aggiungi fase", systemImage: "plus.circle.fill") }
                } header: { Text("Fasi") } footer: { Text("L'ordine è quello di gioco; un ramo può saltare a un'altra fase. Tieni premuto per spostare.") }
            }
        }
        .scrollContentBackground(.hidden)
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
        do { m = try await jsoc.missione(id); errore = nil } catch { errore = error.localizedDescription }
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Fase") {
                    TextField("Titolo", text: $fase.titolo)
                    TextField("Testo per la squadra: briefing, cifrato, indovinello…", text: $fase.testo, axis: .vertical).lineLimit(3...12)
                    Picker("Tipo di prova", selection: $fase.prova) {
                        ForEach(NomiMissione.prove, id: \.0) { Label($0.1, systemImage: $0.2).tag($0.0) }
                    }
                    PhotosPicker(selection: $foto, matching: .images) {
                        Label(caricando ? "Carico…" : fase.immagine ? "Immagine allegata · cambia" : "Allega immagine o documento",
                              systemImage: fase.immagine ? "photo.fill" : "photo.badge.plus")
                    }
                    if fase.immagine { Button("Togli l'immagine", role: .destructive) { fase.immagine = false } }
                }
                Section {
                    Picker("Si sblocca con", selection: $fase.sblocco) {
                        ForEach(NomiMissione.sblocchi, id: \.0) { Label($0.1, systemImage: $0.2).tag($0.0) }
                    }
                    switch fase.sblocco {
                    case "codice":
                        TextField("Risposte giuste, separate da |", text: $fase.soluzione)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled().font(Theme.mono(14))
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
                    case "foto":
                        TextField("Cosa deve mostrare la foto (lo vedi tu)", text: $fase.soluzione)
                    case "qr":
                        Text("Il QR si genera al salvataggio: lo stampi da “QR da stampare” e lo nascondi sul campo.")
                            .font(.footnote).foregroundStyle(Theme.dim)
                    default: EmptyView()
                    }
                } header: { Text("Sblocco") } footer: {
                    if fase.sblocco == "codice" { Text("Maiuscole e spazi non contano. Anche le risposte dei rami sbloccano la fase.") }
                }
                Section("Punteggio e tempo") {
                    Stepper("Punti: \(fase.punti)", value: $fase.punti, in: 0...1000, step: 5)
                    Stepper(fase.tempo_min == 0 ? "Tempo della fase: libero" : "Tempo della fase: \(fase.tempo_min) min", value: $fase.tempo_min, in: 0...240, step: 5)
                }
                Section {
                    ForEach($fase.indizi) { $i in
                        HStack {
                            TextField("Indizio", text: $i.testo)
                            Stepper("−\(i.costo)", value: $i.costo, in: 0...100).fixedSize()
                        }
                    }
                    .onDelete { fase.indizi.remove(atOffsets: $0) }
                    Button { fase.indizi.append(JIndizio(testo: "", costo: 2)) } label: { Label("Aggiungi indizio", systemImage: "lightbulb") }
                } header: { Text("Indizi (in ordine, costano punti)") }
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
        }
    }
}

// MARK: - Diretta del GM

struct DirettaView: View {
    let id: Int
    @State private var d: JDiretta?
    @State private var foto: [Int: UIImage] = [:]
    @State private var errore: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let errore { ErrorCard(text: errore) }
                if let d {
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
                                    Text(s.fine != nil ? "completata · \(tempo(s))" : "fase \(s.fatte + 1)/\(d.n_fasi): \(s.fase ?? "—")")
                                        .font(.caption).foregroundStyle(s.fine != nil ? Theme.olive : Theme.dim)
                                    Text("\(s.membri.joined(separator: ", ")) · errori \(s.errori) · indizi \(s.indizi)").font(.caption2).foregroundStyle(Theme.dim)
                                }
                                Spacer()
                                Text("\(s.punti)").font(Theme.mono(20, .heavy))
                            }
                        }
                    }
                } else { ProgressView().padding(40) }
            }
            .padding(14)
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
}

// MARK: - Gioco della squadra

struct GiocaMissioneView: View {
    let riga: JMissioneRiga
    @ObservedObject private var jsoc = JsocClient.shared
    @EnvironmentObject var location: LocationService
    @AppStorage("missioni.squadra") private var nomeSquadra = ""
    @State private var p: JPartita?
    @State private var risposta = ""
    @State private var messaggio: (String, Bool)?
    @State private var lavoro = false
    @State private var scanner = false
    @State private var foto: PhotosPickerItem?
    @State private var immagine: UIImage?
    @State private var errore: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let errore { ErrorCard(text: errore) }
                if let p { gioco(p) } else { entra }
            }
            .padding(14)
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .navigationTitle(riga.titolo).navigationBarTitleDisplayMode(.inline)
        .task(id: p?.id) {
            if p == nil, let pid = riga.mia_partita { p = try? await jsoc.partita(pid) }
            while !Task.isCancelled, let pid = p?.id {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if let n = try? await jsoc.partita(pid) { aggiorna(n) }
            }
        }
        .sheet(isPresented: $scanner) {
            ZStack(alignment: .bottom) {
                CodeScanner { s, _ in
                    guard s.hasPrefix("jsoctak-fase:") else { return }
                    scanner = false
                    Task { await tenta(["qr": s]) }
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
    }

    var entra: some View {
        Card(title: "Entra con la tua squadra", icon: "person.3.fill") {
            if !riga.descrizione.isEmpty { Text(riga.descrizione).font(.subheadline) }
            TextField("Nome della squadra (es. ALFA)", text: $nomeSquadra)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .font(Theme.mono(16, .bold)).padding(10).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
            Text("Chi usa lo stesso nome entra nella stessa squadra e vede le stesse fasi.").font(.caption).foregroundStyle(Theme.dim)
            Button {
                Task {
                    do { p = try await jsoc.entraPartita(riga.id, nome: nomeSquadra) } catch { errore = error.localizedDescription }
                }
            } label: { Label("Inizia la missione", systemImage: "flag.checkered") }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(nomeSquadra.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @ViewBuilder func gioco(_ p: JPartita) -> some View {
        // testata: squadra, punti, avanzamento, tempo
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.nome).font(.title3.weight(.heavy))
                    Text(p.membri.joined(separator: " · ")).font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(p.punti)").font(Theme.mono(26, .heavy)).foregroundStyle(Theme.olive)
                    Text("punti").font(.caption2).foregroundStyle(Theme.dim)
                }
            }
            ProgressView(value: Double(p.fatte.count), total: Double(max(1, p.n_fasi))).tint(Theme.olive)
            HStack {
                Text("Fasi superate \(p.fatte.count)/\(p.n_fasi)").font(.caption).foregroundStyle(Theme.dim)
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
        if let m = messaggio {
            Label(m.0, systemImage: m.1 ? "checkmark.seal.fill" : "xmark.octagon.fill")
                .font(.subheadline.weight(.bold)).foregroundStyle(m.1 ? Theme.olive : Theme.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12).background((m.1 ? Theme.olive : Theme.red).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
        if p.fine != nil {
            Card(title: "Missione completata", icon: "trophy.fill") {
                Text("\(p.punti) punti · \(p.errori) errori").font(.title3.weight(.bold))
                ForEach(p.fatte, id: \.self) { Label($0, systemImage: "checkmark").font(.subheadline) }
            }
        } else if p.scaduta {
            Card(title: "Tempo scaduto", icon: "timer") { Text("La missione è finita con \(p.punti) punti.").foregroundStyle(Theme.dim) }
        } else if let f = p.fase {
            faseCorrente(p, f)
        }
    }

    @ViewBuilder func faseCorrente(_ p: JPartita, _ f: JFaseVista) -> some View {
        Card(title: "Fase \(p.fatte.count + 1) · \(NomiMissione.prova(f.prova).0)", icon: NomiMissione.prova(f.prova).1, trailing: "\(f.punti) pt") {
            Text(f.titolo).font(.title2.weight(.heavy))
            if f.tempo_min > 0, let i = f.inizio {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let resta = i + Double(f.tempo_min * 60) - Date().timeIntervalSince1970
                    Label(resta > 0 ? String(format: "Tempo della fase %02d:%02d", Int(resta) / 60, Int(resta) % 60) : "Tempo della fase finito",
                          systemImage: "hourglass").font(Theme.mono(13, .bold)).foregroundStyle(resta < 60 ? Theme.red : Theme.amber)
                }
            }
            if !f.testo.isEmpty {
                Text(f.testo).font(f.prova == "cifrario" ? Theme.mono(16, .bold) : .body).textSelection(.enabled)
            }
            if f.immagine {
                if let immagine { Image(uiImage: immagine).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12)) }
                else { ProgressView().frame(maxWidth: .infinity, minHeight: 60) }
            }
            strumentiUtili(f)
        }
        .task(id: f.id) {
            immagine = nil
            if f.immagine, let d = try? await jsoc.scaricaDati("/api/missioni/\(p.missione)/fasi/\(f.id)/immagine") { immagine = UIImage(data: d) }
        }

        if !f.indizi_usati.isEmpty || f.prossimo_indizio_costo != nil {
            Card(title: "Indizi", icon: "lightbulb.fill") {
                ForEach(Array(f.indizi_usati.enumerated()), id: \.offset) { _, t in Label(t, systemImage: "lightbulb").font(.subheadline) }
                if let costo = f.prossimo_indizio_costo {
                    Button {
                        Task { if let n = try? await jsoc.indizio(p.id) { aggiorna(n) } }
                    } label: { Label("Chiedi un indizio (−\(costo) punti)", systemImage: "questionmark.circle") }
                    .buttonStyle(.bordered).tint(Theme.amber)
                }
            }
        }

        Card(title: NomiMissione.sblocco(f.sblocco).0, icon: NomiMissione.sblocco(f.sblocco).1) {
            switch f.sblocco {
            case "codice":
                if !f.scelte.isEmpty {
                    ForEach(f.scelte, id: \.self) { s in
                        Button { Task { await tenta(["valore": s]) } } label: { Text(s).frame(maxWidth: .infinity) }.buttonStyle(.bordered).tint(Theme.olive)
                    }
                }
                TextField("Codice o risposta", text: $risposta)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .font(Theme.mono(20, .heavy)).multilineTextAlignment(.center)
                    .padding(12).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                    .onSubmit { Task { await tenta(["valore": risposta]) } }
                Button { Task { await tenta(["valore": risposta]) } } label: {
                    HStack { if lavoro { ProgressView().tint(.black) }; Text("Prova il codice") }
                }
                .buttonStyle(PrimaryButtonStyle()).disabled(risposta.isEmpty || lavoro)
            case "qr":
                Button { scanner = true } label: { Label("Scansiona il QR trovato", systemImage: "qrcode.viewfinder") }.buttonStyle(PrimaryButtonStyle())
            case "gps":
                Text("Raggiungi il punto (entro \(f.raggio) m) e poi conferma.").font(.footnote).foregroundStyle(Theme.dim)
                Button {
                    guard let l = location.location else { messaggio = ("Posizione GPS non ancora disponibile", false); return }
                    Task { await tenta(["lat": l.coordinate.latitude, "lon": l.coordinate.longitude]) }
                } label: { Label("Sono arrivato", systemImage: "location.fill") }.buttonStyle(PrimaryButtonStyle())
            case "foto":
                if f.prova_stato == "attesa" {
                    Label("Foto mandata: il GM la sta guardando", systemImage: "hourglass").foregroundStyle(Theme.amber)
                } else {
                    if f.prova_stato == "no" { Label("Il GM ha rifiutato la foto: riprova", systemImage: "xmark").foregroundStyle(Theme.red) }
                    PhotosPicker(selection: $foto, matching: .images) {
                        Label(lavoro ? "Invio…" : "Manda la foto al GM", systemImage: "camera.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            default:
                Button { Task { await tenta([:]) } } label: { Label("Avanti", systemImage: "arrow.right") }.buttonStyle(PrimaryButtonStyle())
            }
        }
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

    func aggiorna(_ n: JPartita) {
        if let vecchia = p, vecchia.fatte.count < n.fatte.count, messaggio == nil || messaggio?.1 == false {
            messaggio = ("Fase superata", true); UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        p = n
    }

    func tenta(_ corpo: [String: Any]) async {
        guard let pid = p?.id else { return }
        lavoro = true
        do {
            let e = try await jsoc.tenta(pid, corpo)
            messaggio = (e.messaggio, e.esito)
            UINotificationFeedbackGenerator().notificationOccurred(e.esito ? .success : .error)
            if e.esito { risposta = "" }
            p = e.stato
        } catch { messaggio = (error.localizedDescription, false) }
        lavoro = false
    }
}
