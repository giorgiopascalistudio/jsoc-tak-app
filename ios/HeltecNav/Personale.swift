import SwiftUI
import CoreLocation

// MARK: - Modelli (server 0.14)

struct JCommentoEvento: Codable, Identifiable, Hashable {
    let id: Int
    let testo: String
    let ts: Double
    var modificato: Double? = nil
    let autore: Int
    var callsign: String? = nil
    var nome: String? = nil
}

struct JAttrezzo: Codable, Identifiable, Hashable {
    let id: Int
    var categoria: String
    var nome: String
    var marca: String? = nil
    var note: String? = nil
    var quantita: Int? = nil
}

struct JAttrezzatura: Codable { let attrezzi: [JAttrezzo]; let categorie: [String] }

struct JVoceChecklist: Codable, Identifiable, Hashable {
    let id: Int
    var attrezzo: Int? = nil
    var preso: Int
    var testo: String? = nil
    var categoria: String? = nil
    var quantita: Int? = nil
}

struct JPuntoPacchetto: Codable, Hashable {
    var nome: String
    var tipo: String
    var lat: Double
    var lon: Double
    var note: String? = nil
}

struct JPacchetto: Codable, Identifiable, Hashable {
    let id: Int
    var nome: String
    var note: String? = nil
    var punti: [JPuntoPacchetto]
    var origine: Int? = nil
    var creato: Double? = nil
}

struct JSchedaSocio: Codable {
    struct Quota: Codable, Hashable { let anno: Int; let importo: Double?; let pagata: Int?; let data: String? }
    struct Tessera: Codable, Hashable { let anno: Int; let figt: Int?; let intranet: Int?; let numero: String?; let note: String? }
    struct Evento: Codable, Hashable, Identifiable { let id: Int; let nome: String; let tipo: String?; let inizio: String?; let stato: String?; let risposta: String?; let presente: Int? }
    struct Stat: Codable { let eventi: Int; let presenze: Int; let arbitro: Int; let percentuale: Int? }
    struct Mov: Codable, Hashable, Identifiable { let id: Int; let data: String; let tipo: String; let categoria: String?; let importo: Double; let descrizione: String? }
    struct Disp: Codable, Hashable { let nome: String?; let creato: Double? }
    let id: Int
    let nome: String
    let callsign: String
    let ruolo: String
    var email: String? = nil
    var telefono: String? = nil
    var nascita: String? = nil
    var luogo_nascita: String? = nil
    var cf: String? = nil
    var indirizzo: String? = nil
    var gruppo_sanguigno: String? = nil
    var emergenza: String? = nil
    var note_profilo: String? = nil
    var certificato_scadenza: String? = nil
    var carica: String? = nil
    var stato_socio: String? = nil
    var ammesso: String? = nil
    var uscito: String? = nil
    var uscita_motivo: String? = nil
    var gruppi: [String]? = nil
    var quote: [Quota]? = nil
    var tesseramenti: [Tessera]? = nil
    var eventi: [Evento]? = nil
    var statistiche: Stat? = nil
    var movimenti: [Mov]? = nil
    var dispositivi: [Disp]? = nil
}

extension JsocClient {
    func commentiEvento(_ ev: Int) async throws -> [JCommentoEvento] { try await get("/api/eventi/\(ev)/commenti") }
    func commentaEvento(_ ev: Int, _ t: String) async throws -> [JCommentoEvento] { try await send("/api/eventi/\(ev)/commenti", "POST", ["testo": t]) }
    func modificaCommentoEvento(_ k: Int, _ t: String) async throws -> [JCommentoEvento] { try await send("/api/commenti-evento/\(k)", "PUT", ["testo": t]) }
    func cancellaCommentoEvento(_ k: Int) async throws -> [JCommentoEvento] { try await send("/api/commenti-evento/\(k)", "DELETE", [String: Any]()) }
    func modificaEvento(_ ev: Int, _ campi: [String: Any]) async throws -> JEvento { try await send("/api/eventi/\(ev)", "PATCH", campi) }

    func attrezzatura() async throws -> JAttrezzatura { try await get("/api/attrezzatura") }
    func salvaAttrezzo(_ id: Int?, _ campi: [String: Any]) async throws -> JAttrezzatura {
        try await send(id.map { "/api/attrezzatura/\($0)" } ?? "/api/attrezzatura", id == nil ? "POST" : "PUT", campi)
    }
    func cancellaAttrezzo(_ id: Int) async throws -> JAttrezzatura { try await send("/api/attrezzatura/\(id)", "DELETE", [String: Any]()) }
    func checklist(_ ev: Int) async throws -> [JVoceChecklist] { try await get("/api/eventi/\(ev)/checklist") }
    func salvaChecklist(_ ev: Int, _ corpo: [String: Any]) async throws -> [JVoceChecklist] { try await send("/api/eventi/\(ev)/checklist", "PUT", corpo) }
    func spunta(_ voce: Int, _ preso: Bool) async { let _: JOk? = try? await send("/api/checklist/\(voce)", "POST", ["preso": preso]) }

    func pacchetti() async throws -> [JPacchetto] { try await get("/api/pacchetti") }
    func nuovoPacchetto(_ corpo: [String: Any]) async throws -> [JPacchetto] { try await send("/api/pacchetti", "POST", corpo) }
    func modificaPacchetto(_ id: Int, _ corpo: [String: Any]) async throws -> [JPacchetto] { try await send("/api/pacchetti/\(id)", "PUT", corpo) }
    func cancellaPacchetto(_ id: Int) async throws -> [JPacchetto] { try await send("/api/pacchetti/\(id)", "DELETE", [String: Any]()) }
    struct EsitoPacchetto: Codable { let ok: Bool; let punti: Int }
    func usaPacchetto(_ id: Int, evento: Int) async throws -> Int {
        let r: EsitoPacchetto = try await send("/api/pacchetti/\(id)/evento/\(evento)", "POST", [String: Any]())
        return r.punti
    }
    func schedaSocio(_ id: Int) async throws -> JSchedaSocio { try await get("/api/soci/\(id)/scheda") }
}

// MARK: - Tornare indietro: pulsante + scorrimento dal bordo sinistro

struct Indietro: ViewModifier {
    let azione: () -> Void
    var titolo = "Indietro"
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                Button { haptic(); azione() } label: {
                    Label(titolo, systemImage: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .tint(.white)
                .padding(.leading, 12).padding(.top, 6)
            }
            .overlay(alignment: .leading) {
                // striscia invisibile sul bordo: trascinando verso destra si torna indietro
                Color.clear.frame(width: 22).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 15).onEnded { g in
                        if g.translation.width > 70 && abs(g.translation.height) < 90 { haptic(); azione() }
                    })
            }
    }
}

extension View {
    /// tasto "Indietro" in alto a sinistra e scorrimento dal bordo sinistro per chiudere
    func indietro(_ titolo: String = "Indietro", _ azione: @escaping () -> Void) -> some View { modifier(Indietro(azione: azione, titolo: titolo)) }
}

// MARK: - Commenti dell'evento

struct CommentiEventoCard: View {
    let evento: Int
    @ObservedObject private var jsoc = JsocClient.shared
    @State private var commenti: [JCommentoEvento] = []
    @State private var testo = ""
    @State private var modifica: JCommentoEvento?
    @State private var testoModifica = ""
    @State private var errore: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Commenti").font(.system(size: 15, weight: .heavy))
                if !commenti.isEmpty { Text("\(commenti.count)").font(Theme.mono(12, .bold)).foregroundStyle(Theme.dim) }
                Spacer()
            }
            if commenti.isEmpty {
                Text("Nessun commento. Scrivi per primo: orari, passaggi in auto, domande.").font(.system(size: 12.5)).foregroundStyle(Theme.dim)
            }
            ForEach(commenti) { k in riga(k) }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Scrivi un commento…", text: $testo, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(10).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                Button { invia() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 32)).foregroundStyle(Theme.olive)
                }
                .disabled(testo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let errore { Text(errore).font(.caption).foregroundStyle(Theme.red) }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.stroke))
        .task { commenti = (try? await jsoc.commentiEvento(evento)) ?? [] }
        .alert("Modifica commento", isPresented: Binding(get: { modifica != nil }, set: { if !$0 { modifica = nil } })) {
            TextField("Commento", text: $testoModifica)
            Button("Salva") { if let k = modifica { esegui { try await jsoc.modificaCommentoEvento(k.id, testoModifica) } } }
            Button("Annulla", role: .cancel) {}
        }
    }

    func riga(_ k: JCommentoEvento) -> some View {
        let mio = k.autore == jsoc.utente?.id
        return HStack(alignment: .top, spacing: 10) {
            FotoSocio(id: k.autore, iniziali: k.callsign ?? "?", lato: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(k.callsign ?? "?").font(.system(size: 13, weight: .heavy))
                    Text(Date(timeIntervalSince1970: k.ts).formatted(.relative(presentation: .named))).font(.system(size: 11)).foregroundStyle(Theme.dim)
                    if k.modificato != nil { Text("modificato").font(.system(size: 10)).foregroundStyle(Theme.dim) }
                }
                Text(k.testo).font(.system(size: 13.5)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if mio || jsoc.utente?.direttivo == true {
                Menu {
                    if mio { Button { testoModifica = k.testo; modifica = k } label: { Label("Modifica", systemImage: "pencil") } }
                    Button(role: .destructive) { esegui { try await jsoc.cancellaCommentoEvento(k.id) } } label: { Label("Elimina", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis").padding(6).foregroundStyle(Theme.dim) }
            }
        }
    }

    func invia() {
        let t = testo.trimmingCharacters(in: .whitespacesAndNewlines)
        testo = ""
        esegui { try await jsoc.commentaEvento(evento, t) }
    }

    func esegui(_ f: @escaping () async throws -> [JCommentoEvento]) {
        haptic()
        Task {
            do { let r = try await f(); withAnimation(.spring(response: 0.3)) { commenti = r }; errore = nil }
            catch { errore = error.localizedDescription }
        }
    }
}

// MARK: - Attrezzatura personale (privata)

enum CategoriaAttrezzo {
    static func nome(_ c: String) -> String {
        ["asg": "ASG (fucili)", "pistola": "Pistole", "ottiche": "Ottiche e red dot", "caricatori": "Caricatori",
         "abbigliamento": "Abbigliamento", "protezioni": "Protezioni (occhiali, maschera, casco)", "tattico": "Tattico (cinturone, plate carrier, tasche)",
         "radio": "Radio e cuffie", "elettronica": "Elettronica (luci, GPS)", "batterie": "Batterie e caricatori",
         "medico": "Medico (IFAK)", "zaino": "Zaini e borse", "altro": "Altro"][c] ?? c.capitalized
    }
    static func icona(_ c: String) -> String {
        ["asg": "scope", "pistola": "scope", "ottiche": "camera.metering.center.weighted", "caricatori": "rectangle.stack.fill",
         "abbigliamento": "tshirt.fill", "protezioni": "eyeglasses", "tattico": "shield.lefthalf.filled", "radio": "antenna.radiowaves.left.and.right",
         "elettronica": "flashlight.on.fill", "batterie": "battery.100.bolt", "medico": "cross.case.fill", "zaino": "bag.fill", "altro": "shippingbox.fill"][c] ?? "shippingbox.fill"
    }
}

struct AttrezzaturaView: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @State private var dati: JAttrezzatura?
    @State private var modifica: JAttrezzo?
    @State private var nuovo = false
    @State private var errore: String?

    var gruppi: [(String, [JAttrezzo])] {
        let a = dati?.attrezzi ?? []
        return (dati?.categorie ?? []).compactMap { c in
            let v = a.filter { $0.categoria == c }
            return v.isEmpty ? nil : (c, v)
        }
    }

    var body: some View {
        List {
            Section {
                Label("Privata: la vedi solo tu. Da qui prepari la checklist di ogni evento.", systemImage: "lock.fill")
                    .font(.footnote).foregroundStyle(Theme.dim)
            }
            .listRowBackground(Color.clear)
            if gruppi.isEmpty && dati != nil {
                Section { Text("Ancora niente. Aggiungi ASG, abbigliamento, protezioni, radio…").foregroundStyle(Theme.dim) }
            }
            ForEach(gruppi, id: \.0) { g in
                Section {
                    ForEach(g.1) { a in
                        Button { modifica = a } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(a.nome).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                    let sotto = [a.marca ?? "", a.note ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
                                    if !sotto.isEmpty { Text(sotto).font(.caption).foregroundStyle(Theme.dim).lineLimit(2) }
                                }
                                Spacer()
                                if (a.quantita ?? 1) > 1 { Text("×\(a.quantita ?? 1)").font(Theme.mono(13, .bold)).foregroundStyle(Theme.oliveBright) }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { elimina(a) } label: { Label("Elimina", systemImage: "trash") }
                        }
                    }
                } header: { Label(CategoriaAttrezzo.nome(g.0), systemImage: CategoriaAttrezzo.icona(g.0)) }
                .listRowBackground(Theme.surface)
            }
            if let errore { Section { Text(errore).foregroundStyle(Theme.red) } }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Attrezzatura")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { nuovo = true } label: { Image(systemName: "plus.circle.fill") } } }
        .task { dati = try? await jsoc.attrezzatura() }
        .refreshable { dati = try? await jsoc.attrezzatura() }
        .sheet(isPresented: $nuovo) { AttrezzoSheet(attrezzo: nil, categorie: dati?.categorie ?? []) { dati = $0 } }
        .sheet(item: $modifica) { a in AttrezzoSheet(attrezzo: a, categorie: dati?.categorie ?? []) { dati = $0 } }
    }

    func elimina(_ a: JAttrezzo) {
        Task {
            do { dati = try await jsoc.cancellaAttrezzo(a.id); errore = nil } catch { errore = error.localizedDescription }
        }
    }
}

struct AttrezzoSheet: View {
    let attrezzo: JAttrezzo?
    let categorie: [String]
    var fatto: (JAttrezzatura) -> Void
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var jsoc = JsocClient.shared
    @State private var categoria = "asg"
    @State private var nome = ""
    @State private var marca = ""
    @State private var note = ""
    @State private var quantita = 1
    @State private var errore: String?
    @State private var chiediElimina = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Categoria", selection: $categoria) {
                        ForEach(categorie.isEmpty ? ["altro"] : categorie, id: \.self) { c in Label(CategoriaAttrezzo.nome(c), systemImage: CategoriaAttrezzo.icona(c)).tag(c) }
                    }
                    TextField("Nome (es. M4 CQB, mimetica MC, occhiali)", text: $nome)
                    TextField("Marca / modello", text: $marca)
                    Stepper("Quantità: \(quantita)", value: $quantita, in: 1...99)
                    TextField("Note (es. 2 batterie 11,1 V, taglia L)", text: $note, axis: .vertical).lineLimit(1...4)
                }
                if attrezzo != nil {
                    Section { Button("Elimina", role: .destructive) { chiediElimina = true } }
                }
                if let errore { Section { Text(errore).foregroundStyle(Theme.red) } }
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle(attrezzo == nil ? "Nuovo attrezzo" : "Modifica").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salva") { salva() }.disabled(nome.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .confirmationDialog("Eliminare \(nome)?", isPresented: $chiediElimina, titleVisibility: .visible) {
                Button("Elimina", role: .destructive) {
                    Task { if let a = attrezzo, let r = try? await jsoc.cancellaAttrezzo(a.id) { fatto(r); dismiss() } }
                }
            }
            .onAppear {
                if let a = attrezzo { categoria = a.categoria; nome = a.nome; marca = a.marca ?? ""; note = a.note ?? ""; quantita = a.quantita ?? 1 }
            }
        }
        .presentationDetents([.medium, .large])
    }

    func salva() {
        Task {
            do {
                let r = try await jsoc.salvaAttrezzo(attrezzo?.id, ["categoria": categoria, "nome": nome.trimmingCharacters(in: .whitespaces),
                                                                  "marca": marca, "note": note, "quantita": quantita])
                fatto(r); dismiss()
            } catch { errore = error.localizedDescription }
        }
    }
}

// MARK: - Checklist dell'evento (privata, costruita dall'attrezzatura)

struct ChecklistEventoView: View {
    let evento: JEvento
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var store = EventoStore.shared
    @State private var voci: [JVoceChecklist] = []
    @State private var attrezzi: JAttrezzatura?
    @State private var scegli = false
    @State private var extra = ""
    @State private var errore: String?
    @State private var caricato = false

    var presi: Int { voci.filter { $0.preso != 0 }.count }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(presi) / \(voci.count) nello zaino").font(.system(size: 15, weight: .heavy))
                        Spacer()
                        Label("Privata", systemImage: "lock.fill").font(.caption).foregroundStyle(Theme.dim)
                    }
                    ProgressView(value: voci.isEmpty ? 0 : Double(presi) / Double(voci.count)).tint(presi == voci.count && !voci.isEmpty ? Theme.green : Theme.olive)
                }
            }
            .listRowBackground(Theme.surface)
            if voci.isEmpty && caricato {
                Section {
                    Text("Scegli dalla tua attrezzatura cosa portare a \(evento.nome).").foregroundStyle(Theme.dim)
                    Button { scegli = true } label: { Label("Scegli dall'attrezzatura", systemImage: "checklist") }
                    let altri = store.eventi.filter { $0.id != evento.id }.prefix(20)
                    if !altri.isEmpty {
                        Menu {
                            ForEach(Array(altri)) { e in Button(e.nome) { salva(["da_evento": e.id]) } }
                        } label: { Label("Copia la lista di un altro evento", systemImage: "doc.on.doc") }
                    }
                }
                .listRowBackground(Theme.surface)
            }
            if !voci.isEmpty {
                Section {
                    ForEach(voci) { v in
                        Button { spunta(v) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: v.preso != 0 ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22)).foregroundStyle(v.preso != 0 ? Theme.green : Theme.dim)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(v.testo ?? "").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).strikethrough(v.preso != 0, color: Theme.dim)
                                    if let c = v.categoria { Text(CategoriaAttrezzo.nome(c)).font(.caption2).foregroundStyle(Theme.dim) }
                                }
                                Spacer()
                                if (v.quantita ?? 1) > 1 { Text("×\(v.quantita ?? 1)").font(Theme.mono(12, .bold)).foregroundStyle(Theme.dim) }
                            }
                        }
                        .swipeActions { Button(role: .destructive) { togli(v) } label: { Label("Togli", systemImage: "minus.circle") } }
                    }
                }
                .listRowBackground(Theme.surface)
                Section {
                    HStack {
                        TextField("Aggiungi altro (es. acqua, pranzo)", text: $extra)
                        Button("Aggiungi") { aggiungiTesto() }.disabled(extra.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Button { scegli = true } label: { Label("Modifica dall'attrezzatura", systemImage: "checklist") }
                    Button { salva(["voci": voci.map { voce($0, preso: false) }]) } label: { Label("Togli tutte le spunte", systemImage: "arrow.counterclockwise") }
                }
                .listRowBackground(Theme.surface)
            }
            if let errore { Section { Text(errore).foregroundStyle(Theme.red) } }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Cosa porto")
        .task {
            voci = (try? await jsoc.checklist(evento.id)) ?? []
            attrezzi = try? await jsoc.attrezzatura()
            caricato = true
        }
        .sheet(isPresented: $scegli) {
            SceltaAttrezziSheet(attrezzi: attrezzi?.attrezzi ?? [], scelti: Set(voci.compactMap(\.attrezzo))) { ids in
                var nuove: [[String: Any]] = ids.map { id in ["attrezzo": id, "preso": voci.first { $0.attrezzo == id }?.preso ?? 0] }
                nuove += voci.filter { $0.attrezzo == nil }.map { voce($0, preso: $0.preso != 0) }
                salva(["voci": nuove])
            }
        }
    }

    func voce(_ v: JVoceChecklist, preso: Bool) -> [String: Any] {
        var d: [String: Any] = ["preso": preso]
        if let a = v.attrezzo { d["attrezzo"] = a } else { d["testo"] = v.testo ?? "" }
        return d
    }

    func spunta(_ v: JVoceChecklist) {
        haptic()
        guard let i = voci.firstIndex(of: v) else { return }
        voci[i].preso = v.preso != 0 ? 0 : 1
        let nuovo = voci[i].preso != 0
        Task { await jsoc.spunta(v.id, nuovo) }
    }

    func togli(_ v: JVoceChecklist) { salva(["voci": voci.filter { $0.id != v.id }.map { voce($0, preso: $0.preso != 0) }]) }

    func aggiungiTesto() {
        let t = extra.trimmingCharacters(in: .whitespaces)
        extra = ""
        salva(["voci": voci.map { voce($0, preso: $0.preso != 0) } + [["testo": t, "preso": false]]])
    }

    func salva(_ corpo: [String: Any]) {
        Task {
            do { let r = try await jsoc.salvaChecklist(evento.id, corpo); withAnimation { voci = r }; errore = nil }
            catch { errore = error.localizedDescription }
        }
    }
}

struct SceltaAttrezziSheet: View {
    let attrezzi: [JAttrezzo]
    @State var scelti: Set<Int>
    var fatto: ([Int]) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                if attrezzi.isEmpty {
                    Text("La tua attrezzatura è vuota: aggiungila da Profilo → Attrezzatura.").foregroundStyle(Theme.dim)
                }
                ForEach(attrezzi) { a in
                    Button {
                        if scelti.contains(a.id) { scelti.remove(a.id) } else { scelti.insert(a.id) }
                    } label: {
                        HStack {
                            Image(systemName: CategoriaAttrezzo.icona(a.categoria)).foregroundStyle(Theme.oliveBright).frame(width: 24)
                            Text(a.nome).foregroundStyle(.white)
                            Spacer()
                            Image(systemName: scelti.contains(a.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(scelti.contains(a.id) ? Theme.olive : Theme.dim)
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("Cosa porto").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .principal) {
                    Button(scelti.count == attrezzi.count ? "Nessuno" : "Tutto") {
                        scelti = scelti.count == attrezzi.count ? [] : Set(attrezzi.map(\.id))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fatto") { fatto(attrezzi.map(\.id).filter { scelti.contains($0) }); dismiss() }
                }
            }
        }
    }
}

// MARK: - Archivio personale: tracce GPS (sul telefono) e pacchetti di coordinate (sul server)

struct TracciaSalvata: Codable, Identifiable, Hashable {
    var id: String
    var nome: String
    var data: Date
    var punti: [[Double]]           // lat, lon
    var metri: Double

    var coordinate: [CLLocationCoordinate2D] { punti.map { .init(latitude: $0[0], longitude: $0[1]) } }
    var lunghezza: String { metri < 1000 ? String(format: "%.0f m", metri) : String(format: "%.2f km", metri / 1000).replacingOccurrences(of: ".", with: ",") }

    var gpx: String {
        let pts = punti.map { "<trkpt lat=\"\($0[0])\" lon=\"\($0[1])\"></trkpt>" }.joined(separator: "\n")
        let n = nome.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="JSOC TAK" xmlns="http://www.topografix.com/GPX/1/1">
        <trk><name>\(n)</name><trkseg>
        \(pts)
        </trkseg></trk></gpx>
        """
    }
}

@MainActor
final class ArchivioTracce: ObservableObject {
    static let shared = ArchivioTracce()
    @Published private(set) var tracce: [TracciaSalvata] = []
    private var file: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("JSOC", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("tracce_archivio.json")
    }

    init() {
        if let d = try? Data(contentsOf: file), let t = try? JSONDecoder().decode([TracciaSalvata].self, from: d) { tracce = t }
    }

    private func salva() { try? JSONEncoder().encode(tracce).write(to: file, options: .atomic) }

    func aggiungi(_ punti: [CLLocationCoordinate2D], nome: String? = nil) {
        guard punti.count >= 2 else { return }
        let m = zip(punti, punti.dropFirst()).reduce(0) { $0 + Geo.distance($1.0, $1.1) }
        let n = nome ?? "Traccia " + Date().formatted(.dateTime.day().month(.abbreviated).hour().minute())
        tracce.insert(TracciaSalvata(id: UUID().uuidString, nome: n, data: Date(), punti: punti.map { [$0.latitude, $0.longitude] }, metri: m), at: 0)
        salva()
    }
    func rinomina(_ t: TracciaSalvata, _ n: String) {
        guard let i = tracce.firstIndex(of: t), !n.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        tracce[i].nome = n; salva()
    }
    func elimina(_ t: TracciaSalvata) { tracce.removeAll { $0.id == t.id }; salva() }

    func condividi(_ t: TracciaSalvata) {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent(t.nome.replacingOccurrences(of: "/", with: "-") + ".gpx")
        try? t.gpx.write(to: f, atomically: true, encoding: .utf8)
        HeltecNav.condividi([f])
    }

    /// la mette sulla mappa personale come livello
    func mostra(_ t: TracciaSalvata) {
        EventoStore.shared.apriPersonale()
        let id = "l-tr-" + t.id
        if !Livelli.shared.miei.contains(where: { $0.id == id }) {
            Livelli.shared.aggiungi(ElementoLivello(id: id, tipo: "traccia", coord: t.punti, testo: t.nome, colore: "#FF8C26"))
        }
        vaiAllaScheda(Schede.mappa)
    }
}

struct ArchivioPersonaleView: View {
    @ObservedObject private var archivio = ArchivioTracce.shared
    @ObservedObject private var traccia = Traccia.shared
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var store = EventoStore.shared
    @State private var sezione = 0
    @State private var pacchetti: [JPacchetto] = []
    @State private var rinomina: TracciaSalvata?
    @State private var nuovoNome = ""
    @State private var nuovoPacchetto = false
    @State private var apri: JPacchetto?
    @State private var errore: String?
    @State private var avviso: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $sezione) {
                Text("Tracce GPS").tag(0); Text("Pacchetti coordinate").tag(1)
            }
            .pickerStyle(.segmented).padding(12)
            List {
                if let avviso { Section { Label(avviso, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.oliveBright) }.listRowBackground(Theme.surface) }
                if let errore { Section { Text(errore).foregroundStyle(Theme.red) }.listRowBackground(Theme.surface) }
                if sezione == 0 { tracceLista } else { pacchettiLista }
            }
            .scrollContentBackground(.hidden)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Archivio personale")
        .toolbar {
            if sezione == 1 { ToolbarItem(placement: .primaryAction) { Button { nuovoPacchetto = true } label: { Image(systemName: "plus.circle.fill") } } }
        }
        .task { pacchetti = (try? await jsoc.pacchetti()) ?? [] }
        .alert("Rinomina traccia", isPresented: Binding(get: { rinomina != nil }, set: { if !$0 { rinomina = nil } })) {
            TextField("Nome", text: $nuovoNome)
            Button("Salva") { if let t = rinomina { archivio.rinomina(t, nuovoNome) } }
            Button("Annulla", role: .cancel) {}
        }
        .sheet(isPresented: $nuovoPacchetto) { NuovoPacchettoSheet { pacchetti = $0 } }
        .sheet(item: $apri) { p in PacchettoSheet(pacchetto: p) { pacchetti = $0 } }
    }

    @ViewBuilder var tracceLista: some View {
        if traccia.punti.count >= 2 {
            Section("In registrazione") {
                HStack {
                    Image(systemName: traccia.attiva ? "record.circle" : "pause.circle").foregroundStyle(traccia.attiva ? Theme.red : Theme.amber)
                    Text("Traccia attuale · \(traccia.testo)")
                    Spacer()
                    Button("Archivia") {
                        traccia.attiva = false
                        archivio.aggiungi(traccia.punti)
                        traccia.azzera()
                        avviso = "Traccia archiviata"
                    }
                    .buttonStyle(.bordered).tint(Theme.olive)
                }
            }
            .listRowBackground(Theme.surface)
        }
        if archivio.tracce.isEmpty {
            Section {
                Text("Nessuna traccia. Avviala dalla mappa (Strumenti → Traccia): quando la fermi finisce qui.").foregroundStyle(Theme.dim)
            }
            .listRowBackground(Theme.surface)
        }
        Section {
            ForEach(Array(archivio.tracce.enumerated()), id: \.element.id) { i, t in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "point.bottomleft.forward.to.point.topright.scurvepath").foregroundStyle(Theme.amber)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.nome).font(.system(size: 15, weight: .semibold))
                            Text("\(t.data.formatted(date: .abbreviated, time: .shortened)) · \(t.lunghezza) · \(t.punti.count) punti")
                                .font(.caption).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                    }
                    HStack(spacing: 8) {
                        Button { archivio.mostra(t) } label: { Label("Mappa", systemImage: "map") }
                        Button { archivio.condividi(t) } label: { Label("Invia GPX", systemImage: "square.and.arrow.up") }
                        Menu {
                            Button { nuovoNome = t.nome; rinomina = t } label: { Label("Rinomina", systemImage: "pencil") }
                            Button { inPacchetto(t) } label: { Label("Salva come pacchetto coordinate", systemImage: "shippingbox") }
                            Button(role: .destructive) { archivio.elimina(t) } label: { Label("Elimina", systemImage: "trash") }
                        } label: { Label("Altro", systemImage: "ellipsis.circle") }
                    }
                    .buttonStyle(.bordered).tint(Theme.olive).font(.system(size: 12.5, weight: .bold))
                }
                .padding(.vertical, 4)
                .comparsa(i)
                .swipeActions { Button(role: .destructive) { archivio.elimina(t) } label: { Label("Elimina", systemImage: "trash") } }
            }
        }
        .listRowBackground(Theme.surface)
    }

    @ViewBuilder var pacchettiLista: some View {
        Section {
            Text("Gruppi di coordinate da riusare: crea un pacchetto dai punti di un evento e caricalo in un evento nuovo.")
                .font(.footnote).foregroundStyle(Theme.dim)
        }
        .listRowBackground(Color.clear)
        if pacchetti.isEmpty {
            Section { Button { nuovoPacchetto = true } label: { Label("Crea il primo pacchetto", systemImage: "plus") } }.listRowBackground(Theme.surface)
        }
        Section {
            ForEach(pacchetti) { p in
                Button { apri = p } label: {
                    HStack {
                        Image(systemName: "shippingbox.fill").foregroundStyle(Theme.oliveBright)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.nome).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                            Text("\(p.punti.count) punti" + ((p.note ?? "").isEmpty ? "" : " · \(p.note ?? "")")).font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.dim)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) { Task { pacchetti = (try? await jsoc.cancellaPacchetto(p.id)) ?? pacchetti } } label: { Label("Elimina", systemImage: "trash") }
                }
            }
        }
        .listRowBackground(Theme.surface)
    }

    func inPacchetto(_ t: TracciaSalvata) {
        // punti della traccia diradati (uno ogni ~50 m) come waypoint
        var scelti: [[Double]] = []
        for p in t.punti {
            if let u = scelti.last, Geo.distance(.init(latitude: u[0], longitude: u[1]), .init(latitude: p[0], longitude: p[1])) < 50 { continue }
            scelti.append(p)
        }
        let punti: [[String: Any]] = scelti.enumerated().map { i, p in ["nome": "\(t.nome) \(i + 1)", "tipo": "waypoint", "lat": p[0], "lon": p[1]] }
        Task {
            do { pacchetti = try await jsoc.nuovoPacchetto(["nome": t.nome, "punti": punti]); sezione = 1; avviso = "Pacchetto creato"; errore = nil }
            catch { errore = error.localizedDescription }
        }
    }
}

struct NuovoPacchettoSheet: View {
    var fatto: ([JPacchetto]) -> Void
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var store = EventoStore.shared
    @State private var nome = ""
    @State private var note = ""
    @State private var evento: Int?
    @State private var errore: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome (es. Campo Calimera – OBJ)", text: $nome)
                    TextField("Note", text: $note)
                }
                Section("Punti da") {
                    Picker("Evento", selection: $evento) {
                        Text("Scegli…").tag(Int?.none)
                        ForEach(store.eventi.filter { $0.membro }) { e in Text(e.nome).tag(Int?.some(e.id)) }
                    }
                }
                if let errore { Section { Text(errore).foregroundStyle(Theme.red) } }
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("Nuovo pacchetto").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crea") {
                        Task {
                            do {
                                var c: [String: Any] = ["nome": nome, "note": note]
                                if let evento { c["da_evento"] = evento }
                                fatto(try await jsoc.nuovoPacchetto(c)); dismiss()
                            } catch { errore = error.localizedDescription }
                        }
                    }
                    .disabled(nome.trimmingCharacters(in: .whitespaces).isEmpty || evento == nil)
                }
            }
            .onChange(of: evento) { id in if nome.isEmpty, let e = store.eventi.first(where: { $0.id == id }) { nome = e.nome } }
        }
        .presentationDetents([.medium])
    }
}

struct PacchettoSheet: View {
    @State var pacchetto: JPacchetto
    var fatto: ([JPacchetto]) -> Void
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var store = EventoStore.shared
    @State private var avviso: String?
    @State private var errore: String?
    @State private var chiediElimina = false

    var eventiGestiti: [JEvento] { store.eventi.filter { jsoc.utente?.direttivo == true || $0.staff || $0.creato_da == jsoc.utente?.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nome") {
                    TextField("Nome", text: $pacchetto.nome)
                    TextField("Note", text: Binding(get: { pacchetto.note ?? "" }, set: { pacchetto.note = $0 }))
                }
                Section {
                    Menu {
                        ForEach(eventiGestiti) { e in
                            Button(e.nome) {
                                Task {
                                    do {
                                        let n = try await jsoc.usaPacchetto(pacchetto.id, evento: e.id)
                                        avviso = "\(n) punti aggiunti a \(e.nome)"; errore = nil
                                        await store.aggiorna(jsoc)
                                    } catch { errore = error.localizedDescription }
                                }
                            }
                        }
                    } label: { Label("Carica in un evento", systemImage: "square.and.arrow.down.on.square") }
                    .disabled(eventiGestiti.isEmpty)
                    Button { condividiGPX() } label: { Label("Invia come GPX", systemImage: "square.and.arrow.up") }
                    if let avviso { Text(avviso).foregroundStyle(Theme.oliveBright) }
                    if let errore { Text(errore).foregroundStyle(Theme.red) }
                }
                Section("Punti · \(pacchetto.punti.count)") {
                    ForEach(Array(pacchetto.punti.enumerated()), id: \.offset) { _, p in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.nome.isEmpty ? p.tipo : p.nome).font(.system(size: 14, weight: .semibold))
                            Text(Geo.mgrs(.init(latitude: p.lat, longitude: p.lon))).font(Theme.mono(11)).foregroundStyle(Theme.dim)
                        }
                    }
                    .onDelete { pacchetto.punti.remove(atOffsets: $0) }
                }
                Section { Button("Elimina il pacchetto", role: .destructive) { chiediElimina = true } }
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle(pacchetto.nome).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salva") { salva() } }
            }
            .confirmationDialog("Eliminare \(pacchetto.nome)?", isPresented: $chiediElimina, titleVisibility: .visible) {
                Button("Elimina", role: .destructive) {
                    Task { if let r = try? await jsoc.cancellaPacchetto(pacchetto.id) { fatto(r); dismiss() } }
                }
            }
        }
    }

    func salva() {
        let pp: [[String: Any]] = pacchetto.punti.map { ["nome": $0.nome, "tipo": $0.tipo, "lat": $0.lat, "lon": $0.lon, "note": $0.note ?? ""] }
        Task {
            do { fatto(try await jsoc.modificaPacchetto(pacchetto.id, ["nome": pacchetto.nome, "note": pacchetto.note ?? "", "punti": pp])); dismiss() }
            catch { errore = error.localizedDescription }
        }
    }

    func condividiGPX() {
        let w = pacchetto.punti.map { p in
            "<wpt lat=\"\(p.lat)\" lon=\"\(p.lon)\"><name>\(p.nome.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;"))</name><type>\(p.tipo)</type></wpt>"
        }.joined(separator: "\n")
        let gpx = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gpx version=\"1.1\" creator=\"JSOC TAK\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n\(w)\n</gpx>"
        let f = FileManager.default.temporaryDirectory.appendingPathComponent(pacchetto.nome.replacingOccurrences(of: "/", with: "-") + ".gpx")
        try? gpx.write(to: f, atomically: true, encoding: .utf8)
        HeltecNav.condividi([f])
    }
}

// MARK: - Scheda socio completa (direttivo)

struct SchedaSocioView: View {
    let id: Int
    @ObservedObject private var jsoc = JsocClient.shared
    @State private var s: JSchedaSocio?
    @State private var errore: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let s {
                    HStack(spacing: 14) {
                        FotoSocio(id: s.id, iniziali: s.callsign, lato: 70)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.callsign).font(.system(size: 26, weight: .black))
                            Text(s.nome).font(.system(size: 15)).foregroundStyle(Theme.dim)
                            HStack(spacing: 6) {
                                Etichetta(testo: (s.carica ?? s.ruolo).uppercased(), colore: Theme.olive)
                                if let st = s.stato_socio, !st.isEmpty { Etichetta(testo: st.uppercased(), colore: Theme.amber) }
                            }
                        }
                    }
                    if let st = s.statistiche {
                        HStack(spacing: 8) {
                            // numeri che entrano uno dopo l'altro
                            numero("\(st.presenze)/\(st.eventi)", "PRESENZE")
                            numero(st.percentuale.map { "\($0)%" } ?? "—", "FREQUENZA")
                            numero("\(st.arbitro)", "DA ARBITRO")
                        }
                    }
                    Card(title: "Anagrafica", icon: "person.text.rectangle") {
                        campo("Email", s.email); campo("Telefono", s.telefono); campo("Nato il", s.nascita.map { dataIT($0) }); campo("Luogo di nascita", s.luogo_nascita)
                        campo("Codice fiscale", s.cf); campo("Indirizzo", s.indirizzo); campo("Ammesso il", s.ammesso.map { dataIT($0) })
                        if let u = s.uscito, !u.isEmpty { campo("Uscito il", dataIT(u)); campo("Motivo", s.uscita_motivo) }
                        if let g = s.gruppi, !g.isEmpty { campo("Gruppi", g.joined(separator: ", ")) }
                    }.comparsa(1)
                    Card(title: "Salute ed emergenze", icon: "cross.case.fill") {
                        campo("Gruppo sanguigno", s.gruppo_sanguigno); campo("Contatto di emergenza", s.emergenza)
                        campo("Certificato medico fino al", s.certificato_scadenza.map { dataIT($0) }); campo("Note", s.note_profilo)
                    }.comparsa(2)
                    if let t = s.tesseramenti, !t.isEmpty {
                        Card(title: "Tesseramento FIGT", icon: "creditcard.fill") {
                            ForEach(t, id: \.anno) { x in
                                HStack {
                                    Text(String(x.anno)).font(Theme.mono(14, .bold))
                                    Text(x.numero.flatMap { $0.isEmpty ? nil : "n. \($0)" } ?? "").font(.caption).foregroundStyle(Theme.dim)
                                    Spacer()
                                    Etichetta(testo: x.intranet == 1 ? "ASSICURATO" : (x.figt == 1 ? "TESSERATO" : "DA FARE"), colore: x.intranet == 1 ? Theme.green : Theme.amber)
                                }
                            }
                        }.comparsa(3)
                    }
                    if let q = s.quote, !q.isEmpty {
                        Card(title: "Quote", icon: "eurosign.circle.fill") {
                            ForEach(q, id: \.anno) { x in
                                HStack {
                                    Text(String(x.anno)).font(Theme.mono(14, .bold))
                                    Spacer()
                                    Text(euro(x.importo)).font(Theme.mono(13))
                                    Image(systemName: x.pagata == 1 ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(x.pagata == 1 ? Theme.green : Theme.red)
                                }
                            }
                        }.comparsa(4)
                    }
                    if let m = s.movimenti, !m.isEmpty {
                        Card(title: "Movimenti di cassa", icon: "banknote.fill") {
                            ForEach(m) { x in
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(x.descrizione?.isEmpty == false ? x.descrizione! : (x.categoria ?? "")).font(.system(size: 13)).lineLimit(1)
                                        Text(dataIT(x.data)).font(.caption2).foregroundStyle(Theme.dim)
                                    }
                                    Spacer()
                                    Text((x.tipo == "uscita" ? "−" : "+") + euro(x.importo)).font(Theme.mono(13, .bold)).foregroundStyle(x.tipo == "uscita" ? Theme.red : Theme.green)
                                }
                            }
                        }.comparsa(5)
                    }
                    if let ev = s.eventi, !ev.isEmpty {
                        Card(title: "Eventi", icon: "calendar") {
                            ForEach(ev.prefix(30)) { e in
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(e.nome).font(.system(size: 13)).lineLimit(1)
                                        Text(dataIT(e.inizio)).font(.caption2).foregroundStyle(Theme.dim)
                                    }
                                    Spacer()
                                    Text(etichetta(e)).font(.system(size: 11, weight: .bold)).foregroundStyle(colore(e))
                                }
                            }
                        }.comparsa(6)
                    }
                    if let d = s.dispositivi, !d.isEmpty {
                        Card(title: "Dispositivi collegati", icon: "ipad.and.iphone") {
                            ForEach(Array(d.enumerated()), id: \.offset) { _, x in Text(x.nome ?? "dispositivo").font(.system(size: 13)) }
                        }.comparsa(7)
                    }
                } else if let errore { ErrorCard(text: errore) } else { ProgressView().frame(maxWidth: .infinity).padding(40) }
            }
            .padding(16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Scheda socio")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { s = try await jsoc.schedaSocio(id) } catch { errore = error.localizedDescription }
        }
    }

    func etichetta(_ e: JSchedaSocio.Evento) -> String {
        if e.stato == "annullato" { return "ANNULLATO" }
        if e.presente == 1 { return "PRESENTE" }
        if e.presente == 0 { return "ASSENTE" }
        switch e.risposta { case "si": return "CI SONO"; case "arbitro": return "ARBITRO"; case "attesa": return "IN ATTESA"; default: return "NO" }
    }
    func colore(_ e: JSchedaSocio.Evento) -> Color {
        if e.stato == "annullato" { return Theme.dim }
        if e.presente == 1 || e.risposta == "si" { return Theme.green }
        if e.risposta == "arbitro" { return Theme.cyan }
        return Theme.red
    }

    func numero(_ v: String, _ t: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(v).font(Theme.mono(18, .heavy))
            Text(t).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.stroke))
    }

    @ViewBuilder func campo(_ n: String, _ v: String?) -> some View {
        if let v, !v.isEmpty {
            HStack(alignment: .top) {
                Text(n).font(.system(size: 12.5)).foregroundStyle(Theme.dim).frame(width: 150, alignment: .leading)
                Text(v).font(.system(size: 13.5)).textSelection(.enabled)
                Spacer(minLength: 0)
            }
        }
    }
}
