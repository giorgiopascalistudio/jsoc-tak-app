import SwiftUI
import CoreLocation

enum FormatoOra { static let f: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "HH:mm"; return f }() }

func oraHHmm(_ d: Date) -> String {
    let f = FormatoOra.f
    return f.string(from: d)
}

// MARK: - Piano di gara: ordine degli OBJ, percorso in mappa, piani alternativi, orari e finestre

struct JTappa: Codable, Hashable, Identifiable {
    var id = UUID()
    var punto: Int? = nil
    var nome: String
    var lat: Double
    var lon: Double
    var sosta: Int = 0
    var da: String = ""         // finestra dell'OBJ "HH:mm" (vuoto = nessuna)
    var a: String = ""
    var nota: String = ""

    enum CodingKeys: String, CodingKey { case punto, nome, lat, lon, sosta, da, a, nota }
    var coord: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    var json: [String: Any] {
        var d: [String: Any] = ["nome": nome, "lat": lat, "lon": lon, "sosta": sosta, "da": da, "a": a, "nota": nota]
        if let punto { d["punto"] = punto }
        return d
    }
}

struct JPiano: Codable, Identifiable, Hashable {
    let id: Int
    let evento: Int
    var nome: String
    var tappe: [JTappa]
    var partenza: String?
    var velocita: Double?
    var note: String?
    var scelto: Int?
    var autore: Int?
    var autore_cs: String?
}

/// calcolo di tratte e orari di un piano
struct CalcoloPiano {
    struct Tratta { let metri: Double; let azimut: Double; let minuti: Double }
    struct Arrivo { let arrivo: Date?; let partenza: Date?; let attesa: Double; let ritardo: Double }
    let tratte: [Tratta?]       // la prima tappa non ha tratta
    let arrivi: [Arrivo]
    let metri: Double
    let minuti: Double

    static func ora(_ s: String?, base: Date) -> Date? {
        guard let s, s.count == 5, let h = Int(s.prefix(2)), let m = Int(s.suffix(2)) else { return nil }
        return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: base)
    }

    init(_ p: JPiano, giorno: Date = Date()) {
        let v = max(0.5, p.velocita ?? 4)
        var tt: [Tratta?] = []
        var arr: [Arrivo] = []
        var tot = 0.0, totMin = 0.0
        var orologio = CalcoloPiano.ora(p.partenza, base: giorno)
        for (i, t) in p.tappe.enumerated() {
            var arrivo = orologio
            if i > 0 {
                let a = p.tappe[i - 1].coord, b = t.coord
                let m = Geo.distance(a, b)
                let min = m / 1000 / v * 60
                tt.append(Tratta(metri: m, azimut: Geo.bearing(a, b), minuti: min))
                tot += m; totMin += min
                arrivo = orologio.map { $0.addingTimeInterval(min * 60) }
            } else {
                tt.append(nil)
            }
            var attesa = 0.0, ritardo = 0.0
            var parte = arrivo
            if let ar = arrivo {
                if let da = CalcoloPiano.ora(t.da, base: giorno), ar < da { attesa = da.timeIntervalSince(ar) / 60; parte = da }
                if let fine = CalcoloPiano.ora(t.a, base: giorno), ar > fine { ritardo = ar.timeIntervalSince(fine) / 60 }
            }
            parte = parte.map { $0.addingTimeInterval(Double(t.sosta) * 60) }
            totMin += attesa + Double(t.sosta)
            arr.append(Arrivo(arrivo: arrivo, partenza: parte, attesa: attesa, ritardo: ritardo))
            orologio = parte
        }
        tratte = tt; arrivi = arr; metri = tot; minuti = totMin
    }

    var km: String { String(format: "%.2f km", metri / 1000).replacingOccurrences(of: ".", with: ",") }
    var durata: String { let m = Int(minuti.rounded()); return m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min" }
    var fuoriFinestra: Int { arrivi.filter { $0.ritardo > 0 }.count }
}

@MainActor
final class PianiStore: ObservableObject {
    static let shared = PianiStore()
    @Published private(set) var piani: [Int: [JPiano]] = [:]
    @Published private(set) var versione = 0

    func carica(_ evento: Int) async {
        guard evento > 0, let p: [JPiano] = try? await JsocClient.shared.get("/api/eventi/\(evento)/piani") else { return }
        metti(evento, p)
    }
    func metti(_ evento: Int, _ p: [JPiano]) { piani[evento] = p; versione += 1 }
    func scelto(_ evento: Int) -> JPiano? { piani[evento]?.first { ($0.scelto ?? 0) != 0 } }
}

extension JsocClient {
    func nuovoPiano(_ ev: Int, _ corpo: [String: Any]) async throws -> [JPiano] { try await send("/api/eventi/\(ev)/piani", "POST", corpo) }
    func salvaPiano(_ id: Int, _ corpo: [String: Any]) async throws -> [JPiano] { try await send("/api/piani/\(id)", "PUT", corpo) }
    func cancellaPiano(_ id: Int) async throws -> [JPiano] { try await send("/api/piani/\(id)", "DELETE", [String: Any]()) }
    func scegliPiano(_ id: Int) async throws -> [JPiano] { try await send("/api/piani/\(id)/scegli", "POST", [String: Any]()) }
    func copiaPiano(_ id: Int) async throws -> [JPiano] { try await send("/api/piani/\(id)/copia", "POST", [String: Any]()) }
}

struct PianoGaraView: View {
    let evento: JEvento
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var store = EventoStore.shared
    @ObservedObject private var archivio = PianiStore.shared
    @State private var apri: JPiano?
    @State private var errore: String?
    @State private var elimina: JPiano?

    var piani: [JPiano] { archivio.piani[evento.id] ?? [] }
    var gestore: Bool { jsoc.utente?.direttivo == true || evento.staff || evento.creato_da == jsoc.utente?.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Decidete l'ordine degli OBJ e confrontate più piani: l'app calcola distanze, azimut e orari. Il piano scelto compare sulla mappa dell'evento per tutta la squadra.")
                    .font(.system(size: 13)).foregroundStyle(Theme.dim)
                if piani.count > 1 { confronto }
                ForEach(Array(piani.enumerated()), id: \.element.id) { i, p in
                    scheda(p).comparsa(i)
                }
                Button { nuovo() } label: { Label(piani.isEmpty ? "Crea il primo piano" : "Nuovo piano", systemImage: "plus") }
                    .buttonStyle(PrimaryButtonStyle())
                if let errore { ErrorCard(text: errore) }
            }
            .padding(16)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Piano di gara")
        .task { await archivio.carica(evento.id) }
        .refreshable { await archivio.carica(evento.id) }
        .sheet(item: $apri) { p in EditorPianoView(evento: evento, piano: p) }
        .confirmationDialog("Eliminare \(elimina?.nome ?? "")?", isPresented: Binding(get: { elimina != nil }, set: { if !$0 { elimina = nil } }), titleVisibility: .visible) {
            Button("Elimina", role: .destructive) { if let p = elimina { esegui { try await jsoc.cancellaPiano(p.id) } } }
        }
    }

    var confronto: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CONFRONTO").font(.system(size: 11, weight: .heavy)).tracking(1.2).foregroundStyle(Theme.dim)
            ForEach(piani) { p in
                let c = CalcoloPiano(p, giorno: evento.dataInizio ?? Date())
                HStack {
                    Text(p.nome).font(.system(size: 14, weight: .heavy)).frame(width: 110, alignment: .leading)
                    Text(c.km).font(Theme.mono(13, .bold)).frame(width: 90, alignment: .leading)
                    Text(c.durata).font(Theme.mono(13)).frame(width: 100, alignment: .leading)
                    if c.fuoriFinestra > 0 { Label("\(c.fuoriFinestra)", systemImage: "exclamationmark.triangle.fill").font(.caption.weight(.bold)).foregroundStyle(Theme.red) }
                    Spacer()
                    if (p.scelto ?? 0) != 0 { Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.green) }
                }
            }
        }
        .padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.stroke))
    }

    func scheda(_ p: JPiano) -> some View {
        let c = CalcoloPiano(p, giorno: evento.dataInizio ?? Date())
        let scelto = (p.scelto ?? 0) != 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(p.nome).font(.system(size: 18, weight: .black))
                if scelto { Etichetta(testo: "SCELTO · IN MAPPA", colore: Theme.green) }
                Spacer()
                if let a = p.autore_cs { Text(a).font(Theme.mono(11)).foregroundStyle(Theme.dim) }
            }
            HStack(spacing: 8) {
                numero(c.km, "PERCORSO")
                numero(c.durata, "TEMPO")
                numero(c.arrivi.last?.partenza.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—", "FINE")
                numero("\(p.tappe.count)", "TAPPE")
            }
            if !p.tappe.isEmpty {
                Text(p.tappe.map(\.nome).joined(separator: " → ")).font(.system(size: 12.5)).foregroundStyle(Theme.dim).lineLimit(3)
            }
            if c.fuoriFinestra > 0 {
                Label("\(c.fuoriFinestra) OBJ raggiunti fuori finestra", systemImage: "exclamationmark.triangle.fill").font(.caption.weight(.bold)).foregroundStyle(Theme.red)
            }
            HStack(spacing: 8) {
                Button { apri = p } label: { Label("Apri", systemImage: "list.number") }
                if gestore && !scelto { Button { esegui { try await jsoc.scegliPiano(p.id) } } label: { Label("Scegli", systemImage: "checkmark.seal") } }
                Button { store.scegli(evento); vaiAllaScheda(Schede.mappa) } label: { Label("Mappa", systemImage: "map") }
                Menu {
                    Button { esegui { try await jsoc.copiaPiano(p.id) } } label: { Label("Duplica come alternativa", systemImage: "doc.on.doc") }
                    Button(role: .destructive) { elimina = p } label: { Label("Elimina", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
            .buttonStyle(.bordered).tint(Theme.olive).font(.system(size: 13, weight: .bold))
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(scelto ? Theme.green.opacity(0.6) : Theme.stroke, lineWidth: scelto ? 1.5 : 0.75))
    }

    func numero(_ v: String, _ t: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(v).font(Theme.mono(14, .heavy)).lineLimit(1).minimumScaleFactor(0.7)
            Text(t).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
    }

    func nuovo() {
        esegui {
            let r = try await jsoc.nuovoPiano(evento.id, ["partenza": "08:30", "velocita": 4])
            if let ultimo = r.last { apri = ultimo }
            return r
        }
    }

    func esegui(_ f: @escaping () async throws -> [JPiano]) {
        haptic()
        Task {
            do { let r = try await f(); withAnimation(.spring(response: 0.35)) { archivio.metti(evento.id, r) }; errore = nil }
            catch { errore = error.localizedDescription }
        }
    }
}

struct EditorPianoView: View {
    let evento: JEvento
    @State var piano: JPiano
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var jsoc = JsocClient.shared
    @State private var punti: [JPunto] = []
    @State private var partenza = Date()
    @State private var errore: String?
    @State private var finestra: JTappa?

    var calcolo: CalcoloPiano { CalcoloPiano(piano, giorno: evento.dataInizio ?? Date()) }
    var mancanti: [JPunto] { punti.filter { p in !piano.tappe.contains { $0.punto == p.id } } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Nome del piano", text: $piano.nome)
                    DatePicker("Partenza", selection: $partenza, displayedComponents: .hourAndMinute)
                    Stepper(String(format: "Velocità media: %.1f km/h", piano.velocita ?? 4).replacingOccurrences(of: ".", with: ","),
                            value: Binding(get: { piano.velocita ?? 4 }, set: { piano.velocita = $0 }), in: 1...12, step: 0.5)
                    HStack {
                        Text("\(calcolo.km) · \(calcolo.durata)").font(Theme.mono(14, .bold))
                        Spacer()
                        if let f = calcolo.arrivi.last?.partenza { Text("fine \(f.formatted(date: .omitted, time: .shortened))").font(Theme.mono(13)).foregroundStyle(Theme.oliveBright) }
                    }
                } footer: { Text("A piedi in campo 3-4 km/h, di corsa 6-8. Le soste e le attese per le finestre si sommano al tempo.") }
                Section {
                    ForEach(Array(piano.tappe.enumerated()), id: \.element.id) { i, t in riga(i, t) }
                        .onMove { piano.tappe.move(fromOffsets: $0, toOffset: $1) }
                        .onDelete { piano.tappe.remove(atOffsets: $0) }
                    if !mancanti.isEmpty {
                        Menu {
                            Button("Tutti i punti che mancano (\(mancanti.count))") { for p in mancanti { aggiungi(p) } }
                            ForEach(mancanti) { p in Button(p.nome + " · " + p.tipo) { aggiungi(p) } }
                        } label: { Label("Aggiungi tappa", systemImage: "plus.circle") }
                    } else if punti.isEmpty {
                        Text("L'evento non ha ancora punti: aggiungili dalla mappa o da un pacchetto di coordinate.").font(.footnote).foregroundStyle(Theme.dim)
                    }
                    if piano.tappe.count > 2 {
                        Button { ottimizza() } label: { Label("Ordine più corto (dal primo punto)", systemImage: "wand.and.stars") }
                    }
                } header: { Text("Tappe · trascina per cambiare l'ordine") }
                Section("Note") { TextField("Accordi, varianti, punti di raccolta", text: Binding(get: { piano.note ?? "" }, set: { piano.note = $0 }), axis: .vertical).lineLimit(2...6) }
                if let errore { Section { Text(errore).foregroundStyle(Theme.red) } }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle(piano.nome).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salva") { salva() } }
            }
            .task {
                punti = ((try? await jsoc.evento(evento.id))?.punti ?? []).sorted { $0.nome.localizedStandardCompare($1.nome) == .orderedAscending }
                if let d = CalcoloPiano.ora(piano.partenza, base: Date()) { partenza = d }
            }
            .onChange(of: partenza) { d in piano.partenza = oraHHmm(d) }
            .sheet(item: $finestra) { t in FinestraTappaSheet(tappa: t) { nuova in
                if let i = piano.tappe.firstIndex(where: { $0.id == nuova.id }) { piano.tappe[i] = nuova }
            } }
        }
    }

    func riga(_ i: Int, _ t: JTappa) -> some View {
        let tr = i < calcolo.tratte.count ? calcolo.tratte[i] : nil
        let ar = i < calcolo.arrivi.count ? calcolo.arrivi[i] : nil
        return VStack(alignment: .leading, spacing: 4) {
            if let tr {
                Text("↓ \(tr.metri < 1000 ? String(format: "%.0f m", tr.metri) : String(format: "%.2f km", tr.metri / 1000)) · azimut \(String(format: "%03.0f", tr.azimut))° · \(Int(tr.minuti.rounded())) min")
                    .font(Theme.mono(11)).foregroundStyle(Theme.cyan)
            }
            HStack(spacing: 10) {
                Text("\(i + 1)").font(Theme.mono(13, .heavy)).foregroundStyle(.black).frame(width: 26, height: 26).background(Theme.olive, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.nome).font(.system(size: 15, weight: .bold))
                    HStack(spacing: 8) {
                        if let a = ar?.arrivo { Text("arrivo \(a.formatted(date: .omitted, time: .shortened))").font(Theme.mono(11)) }
                        if !t.da.isEmpty || !t.a.isEmpty { Text("finestra \(t.da.isEmpty ? "…" : t.da)–\(t.a.isEmpty ? "…" : t.a)").font(Theme.mono(11)).foregroundStyle(Theme.amber) }
                        if t.sosta > 0 { Text("sosta \(t.sosta)′").font(Theme.mono(11)).foregroundStyle(Theme.dim) }
                    }
                    if let ar, ar.attesa > 0 { Text("attesa \(Int(ar.attesa.rounded())) min prima della finestra").font(.caption2).foregroundStyle(Theme.amber) }
                    if let ar, ar.ritardo > 0 { Text("IN RITARDO di \(Int(ar.ritardo.rounded())) min sulla finestra").font(.caption2.weight(.bold)).foregroundStyle(Theme.red) }
                }
                Spacer()
                Button { finestra = t } label: { Image(systemName: "clock.badge.questionmark").foregroundStyle(Theme.oliveBright) }
                    .buttonStyle(.borderless)
            }
        }
        .listRowBackground(Theme.surface)
    }

    func aggiungi(_ p: JPunto) { piano.tappe.append(JTappa(punto: p.id, nome: p.nome, lat: p.lat, lon: p.lon)) }

    /// vicino più vicino, partendo dalla prima tappa
    func ottimizza() {
        guard piano.tappe.count > 2 else { return }
        var resto = Array(piano.tappe.dropFirst())
        var ordine = [piano.tappe[0]]
        while !resto.isEmpty {
            let u = ordine[ordine.count - 1].coord
            var migliore = 0
            var dist = Double.greatestFiniteMagnitude
            for (j, t) in resto.enumerated() {
                let d = Geo.distance(u, t.coord)
                if d < dist { dist = d; migliore = j }
            }
            ordine.append(resto.remove(at: migliore))
        }
        withAnimation { piano.tappe = ordine }
    }

    func salva() {
        let corpo: [String: Any] = ["nome": piano.nome, "partenza": piano.partenza ?? "", "velocita": piano.velocita ?? 4,
                                    "note": piano.note ?? "", "tappe": piano.tappe.map(\.json)]
        Task {
            do { PianiStore.shared.metti(evento.id, try await jsoc.salvaPiano(piano.id, corpo)); dismiss() }
            catch { errore = error.localizedDescription }
        }
    }
}

struct FinestraTappaSheet: View {
    @State var tappa: JTappa
    var fatto: (JTappa) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var conFinestra = false
    @State private var da = Date()
    @State private var a = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section(tappa.nome) {
                    Stepper("Sosta: \(tappa.sosta) min", value: $tappa.sosta, in: 0...240, step: 5)
                    Toggle("Finestra oraria dell'OBJ", isOn: $conFinestra)
                    if conFinestra {
                        DatePicker("Dalle", selection: $da, displayedComponents: .hourAndMinute)
                        DatePicker("Alle", selection: $a, displayedComponents: .hourAndMinute)
                    }
                    TextField("Nota (es. aspettare il segnale)", text: $tappa.nota)
                }
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("Tappa").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fatto") {
                        let f: (Date) -> String = { oraHHmm($0) }
                        tappa.da = conFinestra ? f(da) : ""
                        tappa.a = conFinestra ? f(a) : ""
                        fatto(tappa); dismiss()
                    }
                }
            }
            .onAppear {
                conFinestra = !tappa.da.isEmpty || !tappa.a.isEmpty
                if let d = CalcoloPiano.ora(tappa.da, base: Date()) { da = d }
                if let d = CalcoloPiano.ora(tappa.a, base: Date()) { a = d }
            }
        }
        .presentationDetents([.medium])
    }
}
