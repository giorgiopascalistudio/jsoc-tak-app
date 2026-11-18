import SwiftUI
import CoreLocation
import Charts
import PhotosUI
import UniformTypeIdentifiers
import MapLibre

// MARK: - Modelli

struct JDisegno: Codable, Identifiable, Hashable {
    let id: Int
    let evento: Int
    let tipo: String          // linea, area, freccia, testo, cerchi, recinto, rotta
    let coord: [[Double]]
    let testo: String?
    let colore: String?
    let raggi: [Double]?
    let autore: Int?
    var callsign: String? = nil
    var coordinate: [CLLocationCoordinate2D] { coord.map { .init(latitude: $0[0], longitude: $0[1]) } }
}

struct JMappa: Codable, Identifiable, Hashable {
    let id: Int
    let evento: Int?
    let nome: String
    let tipo: String          // xyz, mbtiles, immagine
    let url: String?
    let coord: [[Double]]?
    let opacita: Double?
    let stato: String?
    var pronta: Bool { (stato ?? "pronta") == "pronta" }
}

private struct ConteggioImport: Decodable { let punti: Int; let disegni: Int }

extension JsocClient {
    func creaDisegno(_ ev: Int, tipo: String, _ c: [CLLocationCoordinate2D], testo: String = "", colore: String = "", raggi: [Double] = []) async throws -> JDisegno {
        try await send("/api/eventi/\(ev)/disegni", "POST", ["tipo": tipo, "coord": c.map { [$0.latitude, $0.longitude] },
                                                              "testo": testo, "colore": colore, "raggi": raggi])
    }
    func cancellaDisegno(_ id: Int) async throws { let _: JOk = try await send("/api/disegni/\(id)", "DELETE", [String: Any]()) }
    func cancellaPunto(_ id: Int) async throws { let _: JPunto = try await send("/api/punti/\(id)", "DELETE", [String: Any]()) }
    func mappeImportate(evento: Int?) async throws -> [JMappa] { try await get("/api/mappe" + (evento.map { "?evento=\($0)" } ?? "")) }
    func nuovaMappaXYZ(nome: String, url: String, evento: Int?) async throws -> JMappa {
        var b: [String: Any] = ["nome": nome, "tipo": "xyz", "url": url]
        if let evento { b["evento"] = evento }
        return try await send("/api/mappe", "POST", b)
    }
    func caricaMappa(_ dati: Data, tipo: String, nome: String, evento: Int?, coord: [[Double]]? = nil) async throws -> JMappa {
        var q = "tipo=\(tipo)&nome=\(nome.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Mappa")"
        if let evento { q += "&evento=\(evento)" }
        if let coord, let j = try? JSONSerialization.data(withJSONObject: coord), let s = String(data: j, encoding: .utf8) {
            q += "&coord=" + (s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
        }
        return try await inviaFile("/api/mappe/file?" + q, "PUT", dati)
    }
    func modificaMappa(_ id: Int, _ campi: [String: Any]) async throws -> JMappa { try await send("/api/mappe/\(id)", "PATCH", campi) }
    func cancellaMappa(_ id: Int) async throws { let _: JOk = try await send("/api/mappe/\(id)", "DELETE", [String: Any]()) }
    func importaFile(_ ev: Int, _ dati: Data, nome: String) async throws -> (Int, Int) {
        let r: ConteggioImport = try await inviaFile("/api/eventi/\(ev)/importa?nome=\(nome.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "file")", "POST", dati)
        return (r.punti, r.disegni)
    }
}

// MARK: - Mappe importate sulla mappa (MapLibre)

@MainActor
final class MappeImportate: ObservableObject {
    static let shared = MappeImportate()
    @Published var elenco: [JMappa] = []
    @Published var accese: Set<Int> = Set(UserDefaults.standard.array(forKey: "mappe.accese") as? [Int] ?? []) {
        didSet { UserDefaults.standard.set(Array(accese), forKey: "mappe.accese") }
    }
    @Published var opacita: [Int: Double] = [:]
    @Published var errore: String?

    func carica() async {
        do { elenco = try await JsocClient.shared.mappeImportate(evento: EventoStore.shared.corrente?.id); errore = nil }
        catch { errore = error.localizedDescription }
    }

    /// Mette sulla mappa le importate accese (sotto i segnaposti), toglie le altre.
    func applica(_ m: MLNMapView?) {
        guard let st = m?.style else { return }
        for x in elenco {
            let ids = "imp-\(x.id)", idl = "imp-l-\(x.id)"
            let on = accese.contains(x.id) && x.pronta
            if !on {
                if let l = st.layer(withIdentifier: idl) { st.removeLayer(l) }
                if let s = st.source(withIdentifier: ids) { st.removeSource(s) }
                continue
            }
            let op = opacita[x.id] ?? x.opacita ?? 0.8
            if let l = st.layer(withIdentifier: idl) as? MLNRasterStyleLayer {
                l.rasterOpacity = NSExpression(forConstantValue: op)
                continue
            }
            var sorgente: MLNSource?
            switch x.tipo {
            case "xyz":
                if let u = x.url {
                    sorgente = MLNRasterTileSource(identifier: ids, tileURLTemplates: [u], options: [.tileSize: 256, .maximumZoomLevel: 19])
                }
            case "mbtiles":
                if let u = JsocClient.shared.conGettone("/api/mappe/\(x.id)/tiles/{z}/{x}/{y}")?.absoluteString.removingPercentEncoding {
                    sorgente = MLNRasterTileSource(identifier: ids, tileURLTemplates: [u], options: [.tileSize: 256, .maximumZoomLevel: 21])
                }
            default:
                if let c = x.coord, c.count == 4, let u = JsocClient.shared.conGettone("/api/mappe/\(x.id)/immagine") {
                    let q = MLNCoordinateQuad(topLeft: .init(latitude: c[0][0], longitude: c[0][1]),
                                              bottomLeft: .init(latitude: c[3][0], longitude: c[3][1]),
                                              bottomRight: .init(latitude: c[2][0], longitude: c[2][1]),
                                              topRight: .init(latitude: c[1][0], longitude: c[1][1]))
                    sorgente = MLNImageSource(identifier: ids, coordinateQuad: q, url: u)
                }
            }
            guard let s = sorgente else { continue }
            st.addSource(s)
            let l = MLNRasterStyleLayer(identifier: idl, source: s)
            l.rasterOpacity = NSExpression(forConstantValue: op)
            if let sotto = st.layer(withIdentifier: "segni-etichette") { st.insertLayer(l, below: sotto) } else { st.addLayer(l) }
        }
    }
}

// MARK: - Modi degli strumenti (tocchi sulla mappa = vertici)

enum ModoStrumento: Equatable {
    case disegno(String)   // linea, area, freccia, testo, recinto
    case rotta
    case cerchi
    case vista
    case allinea
}

// MARK: - Pannello disegno

struct PannelloDisegno: View {
    let tipo: String
    @Binding var vertici: [CLLocationCoordinate2D]
    var chiudi: () -> Void
    var avviso: (String) -> Void
    @ObservedObject private var store = EventoStore.shared
    @State private var testo = ""
    @State private var colore = "giallo"
    @State private var lavoro = false

    var minimo: Int { ["area": 3, "recinto": 3, "testo": 1][tipo] ?? 2 }
    static let colori: [(String, Color)] = [("giallo", .yellow), ("rosso", Theme.red), ("blu", Color(red: 0.3, green: 0.6, blue: 1)), ("verde", Theme.green), ("bianco", .white)]
    static func colore(_ n: String?) -> Color { colori.first { $0.0 == n }?.1 ?? .yellow }

    var titolo: String {
        ["linea": "Linea", "area": "Area", "freccia": "Freccia", "testo": "Testo sulla mappa", "recinto": "Recinto con avviso"][tipo] ?? tipo
    }

    var body: some View {
        VStack(spacing: 0) {
            TestataPannello(titolo: titolo, sotto: "tocca la mappa per aggiungere i punti · \(vertici.count)", chiudi: chiudi)
            VStack(alignment: .leading, spacing: 10) {
                if tipo == "recinto" {
                    Text("Quando tu o un compagno entrate o uscite dal recinto, arriva un avviso a tutti.").font(.caption).foregroundStyle(Theme.dim)
                }
                TextField(tipo == "testo" ? "Testo da scrivere sulla mappa" : "Nome (facoltativo)", text: $testo)
                    .padding(10).background(Theme.surface2.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                if tipo != "recinto" {
                    HStack(spacing: 8) {
                        ForEach(Self.colori, id: \.0) { c in
                            Circle().fill(c.1).frame(width: 30, height: 30)
                                .overlay(Circle().stroke(.white, lineWidth: colore == c.0 ? 3 : 0))
                                .onTapGesture { colore = c.0; haptic() }
                        }
                    }
                }
                if vertici.count >= 2 {
                    let m = zip(vertici, vertici.dropFirst()).reduce(0.0) { $0 + Geo.distance($1.0, $1.1) }
                    Text("Lunghezza \(Geo.formatDistance(m))").font(Theme.mono(13, .bold)).foregroundStyle(Theme.oliveBright)
                }
                HStack(spacing: 8) {
                    Button("Togli l'ultimo") { if !vertici.isEmpty { vertici.removeLast() } }.buttonStyle(.bordered).tint(Theme.olive)
                    Spacer()
                    Button { salva() } label: { Text(lavoro ? "Salvo…" : "Salva per la squadra") }
                        .buttonStyle(.borderedProminent).tint(Theme.olive).foregroundStyle(.black)
                        .disabled(vertici.count < minimo || lavoro || store.corrente == nil || (tipo == "testo" && testo.isEmpty))
                }
                .font(.system(size: 13, weight: .bold))
            }
            .padding(14)
            Spacer(minLength: 0)
        }
    }

    func salva() {
        guard let ev = store.corrente?.id else { return }
        lavoro = true
        Task {
            defer { lavoro = false }
            do {
                _ = try await JsocClient.shared.creaDisegno(ev, tipo: tipo, tipo == "testo" ? Array(vertici.prefix(1)) : vertici, testo: testo, colore: colore)
                await store.aggiorna(JsocClient.shared)
                avviso("\(titolo) condiviso con la squadra")
                vertici = []
                chiudi()
            } catch { avviso("Non salvato: \(error.localizedDescription)") }
        }
    }
}

// MARK: - Rotta a tappe

@MainActor
final class RottaAttiva: ObservableObject {
    static let shared = RottaAttiva()
    @Published var tappe: [CLLocationCoordinate2D] = []
    @Published var indice: Int?      // tappa verso cui si naviga

    func naviga() {
        guard !tappe.isEmpty else { return }
        indice = 0
        vai()
    }

    func vai() {
        guard let i = indice, i < tappe.count else { indice = nil; NavStore.shared.target = nil; return }
        NavStore.shared.target = GaraPoint(id: "TAPPA \(i + 1)/\(tappe.count)", lat: tappe[i].latitude, lon: tappe[i].longitude, kind: .mio, note: "Rotta a tappe")
    }

    /// arrivato entro 20 m: passa alla tappa dopo
    func controlla(_ me: CLLocationCoordinate2D) -> String? {
        guard let i = indice, i < tappe.count, Geo.distance(me, tappe[i]) < 20 else { return nil }
        indice = i + 1
        if i + 1 >= tappe.count { indice = nil; NavStore.shared.target = nil; return "Rotta completata" }
        vai()
        return "Tappa \(i + 1) raggiunta · verso la \(i + 2)"
    }
}

struct PannelloRotta: View {
    @ObservedObject var rotta = RottaAttiva.shared
    var chiudi: () -> Void
    var avviso: (String) -> Void
    @ObservedObject private var store = EventoStore.shared

    var body: some View {
        let tratti = zip(rotta.tappe, rotta.tappe.dropFirst()).map { (Geo.distance($0, $1), Geo.bearing($0, $1)) }
        let tot = tratti.reduce(0) { $0 + $1.0 }
        VStack(spacing: 0) {
            TestataPannello(titolo: "Rotta a tappe", sotto: "tocca la mappa per aggiungere le tappe", chiudi: chiudi)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Geo.formatDistance(tot)).font(Theme.mono(26, .heavy)).foregroundStyle(Theme.oliveBright)
                    Text("\(rotta.tappe.count) tappe · ~\(Int(tot / 1000 / 4 * 60)) min a piedi").font(.caption).foregroundStyle(Theme.dim)
                }
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(Array(tratti.enumerated()), id: \.offset) { i, t in
                            HStack {
                                Text("\(i + 1)→\(i + 2)").font(Theme.mono(11, .bold)).foregroundStyle(rotta.indice == i + 1 ? Theme.oliveBright : Theme.dim).frame(width: 40, alignment: .leading)
                                Text(Geo.formatDistance(t.0)).font(Theme.mono(13, .bold))
                                Spacer()
                                Text("az \(gradi3(t.1))").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                            }
                        }
                    }
                }
                HStack(spacing: 6) {
                    Button("Togli") { if !rotta.tappe.isEmpty { rotta.tappe.removeLast() } }.buttonStyle(.bordered).tint(Theme.olive)
                    Button("Azzera") { rotta.tappe = []; rotta.indice = nil }.buttonStyle(.bordered).tint(Theme.red)
                    Spacer()
                    Button("Condividi") { condividi() }.buttonStyle(.bordered).tint(Theme.olive).disabled(rotta.tappe.count < 2)
                    Button("Naviga") { rotta.naviga() }.buttonStyle(.borderedProminent).tint(Theme.oliveBright).foregroundStyle(.black).disabled(rotta.tappe.isEmpty)
                }
                .font(.system(size: 12.5, weight: .bold))
            }
            .padding(14)
        }
    }

    func condividi() {
        guard let ev = store.corrente?.id else { return }
        Task {
            do {
                _ = try await JsocClient.shared.creaDisegno(ev, tipo: "rotta", rotta.tappe, testo: "Rotta \(JsocClient.shared.utente?.callsign ?? "")")
                await store.aggiorna(JsocClient.shared)
                avviso("Rotta condivisa con la squadra")
            } catch { avviso("Non condivisa: \(error.localizedDescription)") }
        }
    }
}

// MARK: - Cerchi di distanza

struct PannelloCerchi: View {
    @Binding var centro: CLLocationCoordinate2D?
    @Binding var raggi: [Double]
    let mio: CLLocationCoordinate2D?
    let centroMappa: CLLocationCoordinate2D
    var chiudi: () -> Void
    var avviso: (String) -> Void
    @ObservedObject private var store = EventoStore.shared
    static let scelte: [Double] = [25, 50, 100, 200, 300, 500, 1000, 2000]
    @State private var libero = ""

    var body: some View {
        VStack(spacing: 0) {
            TestataPannello(titolo: "Cerchi di distanza", sotto: centro.map { coordTesto($0) } ?? "tocca la mappa per il centro", chiudi: chiudi)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button("Su di me") { centro = mio }.buttonStyle(.bordered).tint(Theme.olive).disabled(mio == nil)
                    Button("Centro mappa") { centro = centroMappa }.buttonStyle(.bordered).tint(Theme.olive)
                }
                .font(.system(size: 12.5, weight: .bold))
                EtichettaSezione(testo: "Raggi")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 6)], spacing: 6) {
                    ForEach(Self.scelte, id: \.self) { r in
                        let on = raggi.contains(r)
                        Button { if on { raggi.removeAll { $0 == r } } else { raggi.append(r); raggi.sort() } } label: {
                            Text(r >= 1000 ? "\(Int(r / 1000)) km" : "\(Int(r)) m").font(Theme.mono(12, .bold))
                                .frame(maxWidth: .infinity).frame(height: 32)
                                .foregroundStyle(on ? .black : .white)
                                .background(on ? Theme.olive : Theme.surface2.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                HStack {
                    TextField("Distanza a scelta (m)", text: $libero).keyboardType(.numberPad)
                        .padding(9).background(Theme.surface2.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                    Button("Aggiungi") {
                        if let v = Double(libero.replacingOccurrences(of: ",", with: ".")), v > 0, v <= 50_000, !raggi.contains(v) {
                            raggi.append(v); raggi.sort(); libero = ""; haptic()
                        }
                    }
                    .buttonStyle(.bordered).tint(Theme.olive)
                }
                ForEach(raggi.filter { !Self.scelte.contains($0) }, id: \.self) { r in
                    HStack {
                        Text(r >= 1000 ? String(format: "%.2f km", r / 1000) : "\(Int(r)) m").font(Theme.mono(12, .bold))
                        Spacer()
                        Button { raggi.removeAll { $0 == r } } label: { Image(systemName: "xmark.circle.fill") }.tint(Theme.dim)
                    }
                }
                Button { condividi() } label: { Text("Condividi con la squadra").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(Theme.olive).foregroundStyle(.black)
                    .disabled(centro == nil || raggi.isEmpty || store.corrente == nil)
            }
            .padding(14)
            Spacer(minLength: 0)
        }
    }

    func condividi() {
        guard let ev = store.corrente?.id, let c = centro else { return }
        Task {
            do {
                _ = try await JsocClient.shared.creaDisegno(ev, tipo: "cerchi", [c], testo: "Cerchi", raggi: raggi)
                await store.aggiorna(JsocClient.shared)
                avviso("Cerchi condivisi")
                centro = nil
                chiudi()
            } catch { avviso("Non condivisi: \(error.localizedDescription)") }
        }
    }
}

// MARK: - Profilo altimetrico e linea di vista

struct PuntoProfilo: Identifiable { let id: Int; let distanza: Double; let quota: Double; let coord: CLLocationCoordinate2D }

enum Quote {
    /// Quote dal modello Copernicus 90 m (Open-Meteo), fino a 100 punti per richiesta.
    static func lungo(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, n: Int = 100) async throws -> [PuntoProfilo] {
        let pts = (0..<n).map { i -> CLLocationCoordinate2D in
            let t = Double(i) / Double(n - 1)
            return .init(latitude: a.latitude + (b.latitude - a.latitude) * t, longitude: a.longitude + (b.longitude - a.longitude) * t)
        }
        let la = pts.map { String(format: "%.5f", $0.latitude) }.joined(separator: ",")
        let lo = pts.map { String(format: "%.5f", $0.longitude) }.joined(separator: ",")
        guard let u = URL(string: "https://api.open-meteo.com/v1/elevation?latitude=\(la)&longitude=\(lo)") else { return [] }
        let (d, _) = try await URLSession.shared.data(from: u)
        struct R: Decodable { let elevation: [Double] }
        let q = try JSONDecoder().decode(R.self, from: d).elevation
        let tot = Geo.distance(a, b)
        return zip(pts.indices, q).map { i, z in PuntoProfilo(id: i, distanza: tot * Double(i) / Double(n - 1), quota: z, coord: pts[i]) }
    }
}

struct PannelloProfilo: View {
    let da: CLLocationCoordinate2D?
    let a: CLLocationCoordinate2D?
    @Binding var visibile: [(CLLocationCoordinate2D, Bool)]
    var chiudi: () -> Void
    @State private var profilo: [PuntoProfilo] = []
    @State private var errore: String?
    @State private var altezza = 1.7

    var body: some View {
        VStack(spacing: 0) {
            TestataPannello(titolo: "Profilo e linea di vista", sotto: "da te al punto toccato sulla mappa", chiudi: chiudi)
            VStack(alignment: .leading, spacing: 8) {
                if profilo.isEmpty {
                    Text(errore ?? (a == nil ? "Tocca un punto sulla mappa." : "Calcolo…")).font(.caption).foregroundStyle(errore == nil ? Theme.dim : Theme.red)
                } else {
                    let salita = zip(profilo, profilo.dropFirst()).reduce(0.0) { $0 + max(0, $1.1.quota - $1.0.quota) }
                    let discesa = zip(profilo, profilo.dropFirst()).reduce(0.0) { $0 + max(0, $1.0.quota - $1.1.quota) }
                    let coperto = visibile.firstIndex { !$0.1 }
                    HStack(spacing: 14) {
                        dato(Geo.formatDistance(profilo.last?.distanza ?? 0), "DISTANZA")
                        dato(String(format: "+%.0f m", salita), "SALITA")
                        dato(String(format: "−%.0f m", discesa), "DISCESA")
                    }
                    Chart {
                        ForEach(profilo) { p in
                            AreaMark(x: .value("m", p.distanza), y: .value("quota", p.quota)).foregroundStyle(Theme.olive.opacity(0.25))
                            LineMark(x: .value("m", p.distanza), y: .value("quota", p.quota)).foregroundStyle(Theme.olive)
                        }
                        if let f = profilo.first, let l = profilo.last {
                            LineMark(x: .value("m", f.distanza), y: .value("quota", f.quota + altezza), series: .value("v", "vista"))
                                .foregroundStyle(coperto == nil ? Theme.green : Theme.red)
                            LineMark(x: .value("m", l.distanza), y: .value("quota", l.quota + altezza), series: .value("v", "vista"))
                                .foregroundStyle(coperto == nil ? Theme.green : Theme.red)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 120)
                    Text(coperto == nil ? "VISIBILE: nessun rilievo in mezzo" : "COPERTO dal terreno a \(Geo.formatDistance(profilo[min(coperto!, profilo.count - 1)].distanza))")
                        .font(Theme.mono(12, .heavy)).foregroundStyle(coperto == nil ? Theme.green : Theme.red)
                    Text("Quote da modello del terreno (non conta alberi ed edifici). Occhi a \(String(format: "%.1f", altezza)) m.").font(.caption2).foregroundStyle(Theme.dim)
                }
            }
            .padding(14)
            Spacer(minLength: 0)
        }
        .task(id: "\(a?.latitude ?? 0)\(a?.longitude ?? 0)") { await calcola() }
    }

    func dato(_ v: String, _ e: String) -> some View {
        VStack(alignment: .leading, spacing: 0) { Text(v).font(Theme.mono(15, .heavy)); Text(e).font(.system(size: 8.5, weight: .bold)).foregroundStyle(Theme.dim) }
    }

    func calcola() async {
        guard let da, let a else { return }
        do {
            let p = try await Quote.lungo(da, a)
            profilo = p
            // linea di vista: dall'occhio di partenza all'occhio d'arrivo
            guard let f = p.first, let l = p.last, l.distanza > 0 else { return }
            let h0 = f.quota + altezza, h1 = l.quota + altezza
            visibile = p.map { x in
                let linea = h0 + (h1 - h0) * x.distanza / l.distanza
                return (x.coord, x.quota <= linea + 0.5)
            }
            errore = nil
        } catch { errore = "Quote non disponibili (serve rete): \(error.localizedDescription)" }
    }
}

// MARK: - Simboli tattici

struct SimboloTattico {
    static let affiliazioni: [(String, String, Color)] = [("am", "Amico", Color(red: 0.4, green: 0.7, blue: 1)), ("ne", "Nemico", Theme.red),
                                                          ("nu", "Neutro", Theme.green), ("sc", "Sconosciuto", .yellow)]
    static let categorie: [(String, String, String)] = [("FAN", "Fanteria", "figure.walk"), ("VEI", "Veicolo", "car.fill"),
                                                        ("CEC", "Cecchino", "scope"), ("POS", "Postazione", "shield.fill"),
                                                        ("OSS", "Osservatore", "binoculars.fill"), ("MIN", "Mina / IED", "burst.fill"),
                                                        ("AER", "Drone / aereo", "airplane"), ("BAS", "Base / comando", "flag.fill")]
    static func colore(_ aff: String) -> Color { affiliazioni.first { $0.0 == aff }?.2 ?? .yellow }
}

struct PannelloSimboli: View {
    let dove: CLLocationCoordinate2D
    var chiudi: () -> Void
    var avviso: (String) -> Void
    @ObservedObject private var store = EventoStore.shared
    @State private var aff = "ne"

    var body: some View {
        VStack(spacing: 0) {
            TestataPannello(titolo: "Simbolo tattico", sotto: coordTesto(dove) + " · centro mappa", chiudi: chiudi)
            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: $aff) { ForEach(SimboloTattico.affiliazioni, id: \.0) { Text($0.1).tag($0.0) } }.pickerStyle(.segmented)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach(SimboloTattico.categorie, id: \.0) { c in
                        Button { metti(c) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: c.2).foregroundStyle(SimboloTattico.colore(aff)).frame(width: 22)
                                Text(c.1).font(.system(size: 12.5, weight: .bold)).foregroundStyle(.white)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10).frame(height: 40)
                            .background(Theme.surface2.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(SimboloTattico.colore(aff).opacity(0.5)))
                        }
                    }
                }
                Text("Il simbolo va al centro della mappa: spostala prima sul punto giusto (o usa la croce di mira).").font(.caption2).foregroundStyle(Theme.dim)
            }
            .padding(14)
            Spacer(minLength: 0)
        }
    }

    func metti(_ c: (String, String, String)) {
        guard let ev = store.corrente?.id else { avviso("Scegli prima un evento"); return }
        haptic(.medium)
        let nomeAff = SimboloTattico.affiliazioni.first { $0.0 == aff }?.1 ?? ""
        Task {
            do {
                _ = try await JsocClient.shared.creaPunto(ev, nome: "\(c.1) \(nomeAff.lowercased())", tipo: "sim-\(aff)-\(c.0)", dove)
                await store.aggiorna(JsocClient.shared)
                avviso("\(c.1) \(nomeAff.lowercased()) segnato")
            } catch { avviso("Non salvato: \(error.localizedDescription)") }
        }
    }
}

// MARK: - Soccorso 9 righe e report SALUTE (moduli che finiscono in chat e sulla mappa)

struct PannelloModulo: View {
    enum Tipo { case noveRighe, salute }
    let tipo: Tipo
    let dove: CLLocationCoordinate2D?
    var chiudi: () -> Void
    var avviso: (String) -> Void
    @ObservedObject private var store = EventoStore.shared
    @State private var valori: [String] = Array(repeating: "", count: 9)

    var campi: [(String, String)] {
        switch tipo {
        case .noveRighe:
            return [("1 · Posizione", "coordinate della zona di raccolta"), ("2 · Frequenza / callsign", "canale radio, chi chiama"),
                    ("3 · Feriti per urgenza", "A urgente · B prioritario · C ordinario"), ("4 · Materiale speciale", "nessuno, barella, ossigeno…"),
                    ("5 · Barellati / che camminano", "es. 1 L, 2 A"), ("6 · Sicurezza della zona", "N nessun nemico · P possibile · E presente"),
                    ("7 · Come è segnata", "fumogeno, telo, luce…"), ("8 · Chi sono i feriti", "nostri, altre squadre, civili"),
                    ("9 · Terreno / ostacoli", "pendenza, alberi, accesso mezzi")]
        case .salute:
            return [("S · Quanti", "numero di persone o mezzi"), ("A · Cosa fanno", "fermi, in movimento, scavano…"),
                    ("L · Dove", "coordinate"), ("U · Chi sono", "uniformi, segni, squadra"),
                    ("T · Quando", "ora dell'avvistamento"), ("E · Equipaggiamento", "armi, radio, veicoli")]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TestataPannello(titolo: tipo == .noveRighe ? "Soccorso 9 righe" : "Report SALUTE", sotto: "si invia in chat e come punto sulla mappa", chiudi: chiudi)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(campi.enumerated()), id: \.offset) { i, c in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.0.uppercased()).font(Theme.mono(9, .heavy)).tracking(0.8).foregroundStyle(Theme.olive)
                            TextField(c.1, text: $valori[i]).font(.system(size: 13.5))
                                .padding(.horizontal, 9).frame(height: 36).background(Theme.surface2.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(14)
            }
            Button { invia() } label: { Text("Invia alla squadra").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).tint(tipo == .noveRighe ? Theme.red : Theme.amber).foregroundStyle(.black)
                .font(.system(size: 14, weight: .heavy))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .disabled(store.corrente == nil)
        }
        .onAppear {
            let c = dove.map { Geo.mgrs($0) } ?? ""
            if tipo == .noveRighe { valori[0] = c } else { valori[2] = c; valori[4] = Date().formatted(date: .omitted, time: .shortened) }
        }
    }

    func invia() {
        guard let ev = store.corrente?.id else { return }
        let testo = (tipo == .noveRighe ? "🚑 SOCCORSO 9 RIGHE\n" : "👁 SALUTE\n") +
            zip(campi, valori).filter { !$0.1.isEmpty }.map { "\($0.0.0): \($0.1)" }.joined(separator: "\n")
        Task {
            do {
                try await store.scrivi(testo, JsocClient.shared, posizione: dove)
                if let d = dove {
                    _ = try? await JsocClient.shared.creaPunto(ev, nome: tipo == .noveRighe ? "9 RIGHE" : "SALUTE", tipo: tipo == .noveRighe ? "pericolo" : "contatto", d, note: testo)
                }
                await store.aggiorna(JsocClient.shared)
                avviso(tipo == .noveRighe ? "Richiesta di soccorso inviata" : "Report SALUTE inviato")
                chiudi()
            } catch { avviso("Non inviato: \(error.localizedDescription)") }
        }
    }
}

// MARK: - Pacchetti missione: esporta KML, importa KML/KMZ/GPX

struct PannelloPacchetti: View {
    var chiudi: () -> Void
    var avviso: (String) -> Void
    @ObservedObject private var store = EventoStore.shared
    @State private var importa = false
    @State private var file: URL?
    @State private var lavoro = false

    var body: some View {
        VStack(spacing: 0) {
            TestataPannello(titolo: "Pacchetti missione", sotto: store.corrente?.nome, chiudi: chiudi)
            VStack(alignment: .leading, spacing: 12) {
                Text("Esporta punti, aree, rotte e disegni dell'evento in KML: si apre con Google Earth, Garmin, ATAK, OsmAnd.").font(.caption).foregroundStyle(Theme.dim)
                if let file {
                    ShareLink(item: file) { Label("Condividi \(file.lastPathComponent)", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(Theme.olive).foregroundStyle(.black)
                } else {
                    Button { esporta() } label: { Label(lavoro ? "Preparo…" : "Prepara il KML", systemImage: "shippingbox.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(Theme.olive).foregroundStyle(.black).disabled(store.corrente == nil || lavoro)
                }
                Divider().overlay(Theme.stroke)
                Text("Importa nell'evento un file KML, KMZ o GPX (anche esportato da Garmin Explore, Gaia, OsmAnd, Google Earth).").font(.caption).foregroundStyle(Theme.dim)
                Button { importa = true } label: { Label("Importa file", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).tint(Theme.olive).disabled(store.corrente == nil || lavoro)
            }
            .font(.system(size: 13.5, weight: .bold))
            .padding(14)
            Spacer(minLength: 0)
        }
        .fileImporter(isPresented: $importa, allowedContentTypes: [.xml, .data, UTType(filenameExtension: "kml") ?? .xml,
                                                                   UTType(filenameExtension: "kmz") ?? .data, UTType(filenameExtension: "gpx") ?? .xml]) { r in
            guard case .success(let u) = r, let ev = store.corrente?.id else { return }
            let ok = u.startAccessingSecurityScopedResource()
            defer { if ok { u.stopAccessingSecurityScopedResource() } }
            guard let d = try? Data(contentsOf: u) else { avviso("File non leggibile"); return }
            lavoro = true
            Task {
                defer { lavoro = false }
                do {
                    let (p, dis) = try await JsocClient.shared.importaFile(ev, d, nome: u.lastPathComponent)
                    await store.aggiorna(JsocClient.shared)
                    avviso("Importati \(p) punti e \(dis) linee/aree")
                } catch { avviso("Import non riuscito: \(error.localizedDescription)") }
            }
        }
    }

    func esporta() {
        guard let e = store.corrente, let u = JsocClient.shared.conGettone("/api/eventi/\(e.id)/esporta.kml") else { return }
        lavoro = true
        Task {
            defer { lavoro = false }
            do {
                let (d, _) = try await URLSession.shared.data(from: u)
                let f = FileManager.default.temporaryDirectory.appendingPathComponent("\(e.nome.replacingOccurrences(of: "/", with: "-")).kml")
                try d.write(to: f, options: .atomic)
                file = f
            } catch { avviso("Esportazione non riuscita: \(error.localizedDescription)") }
        }
    }
}

// MARK: - Mappe importate (dentro Impostazioni)

struct SezioneMappeImportate: View {
    @ObservedObject var mappe = MappeImportate.shared
    var allinea: (UIImage) -> Void
    var aggiorna: () -> Void
    @ObservedObject private var store = EventoStore.shared
    @State private var indirizzo = false
    @State private var nome = ""
    @State private var url = ""
    @State private var file = false
    @State private var foto: PhotosPickerItem?
    @State private var lavoro: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EtichettaSezione(testo: "Mappe importate")
            if mappe.elenco.isEmpty { Text("Nessuna. Aggiungi un file, un indirizzo o una carta da allineare.").font(.caption).foregroundStyle(Theme.dim) }
            ForEach(mappe.elenco) { m in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: m.tipo == "immagine" ? "photo" : (m.tipo == "xyz" ? "globe" : "square.stack.3d.down.right"))
                            .foregroundStyle(Theme.olive).frame(width: 20)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(m.nome).font(.system(size: 13, weight: .bold))
                            Text(m.pronta ? (m.tipo == "xyz" ? "indirizzo · serve rete" : "dal server") : (m.stato ?? "")).font(.caption2).foregroundStyle(m.pronta ? Theme.dim : Theme.amber)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(get: { mappe.accese.contains(m.id) }, set: { on in
                            if on { mappe.accese.insert(m.id) } else { mappe.accese.remove(m.id) }
                            aggiorna()
                        })).labelsHidden().disabled(!m.pronta)
                    }
                    if mappe.accese.contains(m.id) {
                        Slider(value: Binding(get: { mappe.opacita[m.id] ?? m.opacita ?? 0.8 }, set: { mappe.opacita[m.id] = $0; aggiorna() }), in: 0.15...1)
                    }
                }
                .contextMenu { Button("Elimina", role: .destructive) { Task { try? await JsocClient.shared.cancellaMappa(m.id); await mappe.carica(); aggiorna() } } }
            }
            if let lavoro { HStack { ProgressView(); Text(lavoro).font(.caption) } }
            HStack(spacing: 6) {
                Button { file = true } label: { Text("+ File").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                Button { indirizzo.toggle() } label: { Text("+ Indirizzo").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                PhotosPicker(selection: $foto, matching: .images) { Text("+ Carta").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
            }
            .font(.system(size: 12, weight: .bold)).tint(Theme.olive)
            Text("File: MBTiles, GeoTIFF, GeoPDF. Carta: foto o scansione da allineare sulla mappa.").font(.caption2).foregroundStyle(Theme.dim)
            if indirizzo {
                TextField("Nome", text: $nome).padding(8).background(Theme.surface2.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                TextField("https://…/{z}/{x}/{y}.png  oppure WMS con {bbox-epsg-3857}", text: $url)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().font(Theme.mono(11))
                    .padding(8).background(Theme.surface2.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                Button("Aggiungi") {
                    Task {
                        do { _ = try await JsocClient.shared.nuovaMappaXYZ(nome: nome.isEmpty ? "Mappa" : nome, url: url, evento: store.corrente?.id)
                             indirizzo = false; nome = ""; url = ""; await mappe.carica() }
                        catch { mappe.errore = error.localizedDescription }
                    }
                }
                .buttonStyle(.borderedProminent).tint(Theme.olive).foregroundStyle(.black)
            }
            if let e = mappe.errore { Text(e).font(.caption2).foregroundStyle(Theme.red) }
        }
        .task { await mappe.carica() }
        .fileImporter(isPresented: $file, allowedContentTypes: [.data, .pdf, .tiff]) { r in
            guard case .success(let u) = r else { return }
            let ok = u.startAccessingSecurityScopedResource()
            defer { if ok { u.stopAccessingSecurityScopedResource() } }
            guard let d = try? Data(contentsOf: u) else { return }
            let ext = u.pathExtension.lowercased()
            let tipo = ext == "mbtiles" ? "mbtiles" : "geotiff"
            lavoro = "Carico \(u.lastPathComponent)…"
            Task {
                defer { lavoro = nil }
                do { _ = try await JsocClient.shared.caricaMappa(d, tipo: tipo, nome: u.deletingPathExtension().lastPathComponent, evento: store.corrente?.id)
                     await mappe.carica() }
                catch { mappe.errore = error.localizedDescription }
            }
        }
        .onChange(of: foto) { item in
            guard let item else { return }
            Task {
                if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) { allinea(img) }
                foto = nil
            }
        }
    }
}

// MARK: - Allineare una carta sulla mappa

struct AllineaCarta: View {
    let immagine: UIImage
    let vista: CGRect
    @Binding var trasparenza: Double
    var fissa: ([CGPoint]) -> Void
    var annulla: () -> Void

    var rettangolo: CGRect {
        let r = immagine.size.width / max(immagine.size.height, 1)
        var w = vista.width * 0.86, h = w / r
        if h > vista.height * 0.8 { h = vista.height * 0.8; w = h * r }
        return CGRect(x: vista.midX - w / 2, y: vista.midY - h / 2, width: w, height: h)
    }

    var body: some View {
        let q = rettangolo
        ZStack(alignment: .topLeading) {
            Image(uiImage: immagine).resizable().frame(width: q.width, height: q.height)
                .opacity(trasparenza).border(Theme.amber, width: 2)
                .position(x: q.midX, y: q.midY)
                .allowsHitTesting(false)
            VStack(spacing: 8) {
                Text("Muovi, ruota e zooma la MAPPA sotto la carta finché coincidono").font(.system(size: 12, weight: .heavy))
                HStack {
                    Slider(value: $trasparenza, in: 0.2...0.9).frame(width: 140).tint(Theme.amber)
                    Button("Annulla", action: annulla).buttonStyle(.bordered).tint(.white)
                    Button("Fissa qui") {
                        fissa([CGPoint(x: q.minX, y: q.minY), CGPoint(x: q.maxX, y: q.minY), CGPoint(x: q.maxX, y: q.maxY), CGPoint(x: q.minX, y: q.maxY)])
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.amber).foregroundStyle(.black)
                }
            }
            .padding(10)
            .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
            .position(x: vista.midX, y: vista.maxY - 46)
        }
    }
}

// MARK: - Recinti: chi entra e chi esce

@MainActor
final class Recinti {
    static let shared = Recinti()
    private var dentro: [String: Bool] = [:]    // "recinto-id|chi" → dentro?

    /// Controlla me e i compagni contro i recinti dell'evento; restituisce gli avvisi nuovi.
    func controlla(io: CLLocationCoordinate2D?, ioNome: String, compagni: [JCompagno]) -> [String] {
        var avvisi: [String] = []
        for r in DatiEvento.disegni where r.tipo == "recinto" {
            let poly = r.coordinate
            var chi: [(String, CLLocationCoordinate2D)] = compagni.filter { $0.eta < 300 }.map { ($0.callsign, $0.coordinate) }
            if let io { chi.append((ioNome, io)) }
            for (nome, c) in chi {
                let k = "\(r.id)|\(nome)"
                let ora = Coordinate.inside(c, poly)
                if let prima = dentro[k], prima != ora {
                    avvisi.append("\(nome) \(ora ? "è ENTRATO in" : "è USCITO da") \(r.testo?.isEmpty == false ? r.testo! : "recinto")")
                }
                dentro[k] = ora
            }
        }
        return avvisi
    }
}

// MARK: - Disegni sulla mappa (disegni condivisi, bozza in corso, rotta, cerchi, linea di vista)

struct Sovrapposizioni2: View {
    @ObservedObject var ctl: MappaCtl
    let disegni: [JDisegno]
    let bozza: [CLLocationCoordinate2D]
    let tipoBozza: String
    let rotta: [CLLocationCoordinate2D]
    let cerchi: CLLocationCoordinate2D?
    let raggi: [Double]
    let vista: [(CLLocationCoordinate2D, Bool)]
    var raggiVista: [[(CLLocationCoordinate2D, Bool)]] = []
    var replay: [(String, CLLocationCoordinate2D, [CLLocationCoordinate2D])] = []

    var body: some View {
        let _ = ctl.giro
        Canvas { ctx, _ in
            for r in raggiVista {
                for (a, b) in zip(r, r.dropFirst()) {
                    guard let p = ctl.punto(a.0), let q = ctl.punto(b.0) else { continue }
                    var l = Path(); l.move(to: p); l.addLine(to: q)
                    ctx.stroke(l, with: .color((b.1 ? Theme.green : Theme.red).opacity(0.75)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
            }
            for (nome, c, scia) in replay {
                let pts = scia.compactMap { ctl.punto($0) }
                if pts.count > 1 { var l = Path(); l.addLines(pts); ctx.stroke(l, with: .color(Theme.cyan.opacity(0.7)), style: StrokeStyle(lineWidth: 3, lineCap: .round)) }
                if let p = ctl.punto(c) {
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16)), with: .color(Theme.cyan))
                    ctx.draw(Text(nome).font(Theme.mono(11, .heavy)).foregroundColor(.white), at: CGPoint(x: p.x, y: p.y + 16))
                }
            }
            for d in disegni { disegna(ctx, d.tipo, d.coordinate, colore: PannelloDisegno.colore(d.colore), testo: d.testo ?? "", raggi: d.raggi ?? []) }
            if !bozza.isEmpty {
                disegna(ctx, tipoBozza, bozza, colore: Theme.amber, testo: "", raggi: [], tratteggio: true)
                for c in bozza { if let s = ctl.punto(c) { ctx.fill(Path(ellipseIn: CGRect(x: s.x - 5, y: s.y - 5, width: 10, height: 10)), with: .color(Theme.amber)) } }
            }
            if !rotta.isEmpty { disegna(ctx, "rotta", rotta, colore: Theme.oliveBright, testo: "", raggi: []) }
            if let c = cerchi { disegna(ctx, "cerchi", [c], colore: Theme.amber, testo: "", raggi: raggi, tratteggio: true) }
            if vista.count > 1 {
                for (a, b) in zip(vista, vista.dropFirst()) {
                    guard let p = ctl.punto(a.0), let q = ctl.punto(b.0) else { continue }
                    var l = Path(); l.move(to: p); l.addLine(to: q)
                    ctx.stroke(l, with: .color(b.1 ? Theme.green : Theme.red), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                }
            }
        }
    }

    func disegna(_ ctx: GraphicsContext, _ tipo: String, _ c: [CLLocationCoordinate2D], colore: Color, testo: String, raggi: [Double], tratteggio: Bool = false) {
        let pts = c.compactMap { ctl.punto($0) }
        guard let primo = pts.first else { return }
        let stile = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: tratteggio ? [7, 5] : [])
        func scritta(_ t: String, _ p: CGPoint, _ col: Color = .white) {
            guard !t.isEmpty else { return }
            ctx.draw(Text(t).font(.system(size: 12, weight: .heavy)).foregroundColor(col), at: CGPoint(x: p.x, y: p.y - 14))
        }
        switch tipo {
        case "area", "recinto":
            guard pts.count >= 2 else { return }
            var p = Path(); p.addLines(pts); p.closeSubpath()
            let col = tipo == "recinto" ? Theme.red : colore
            ctx.fill(p, with: .color(col.opacity(0.14)))
            ctx.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: 2.5, dash: tipo == "recinto" ? [10, 6] : (tratteggio ? [7, 5] : [])))
            let cx = pts.map(\.x).reduce(0, +) / CGFloat(pts.count), cy = pts.map(\.y).reduce(0, +) / CGFloat(pts.count)
            scritta(tipo == "recinto" ? "⚠ " + (testo.isEmpty ? "RECINTO" : testo) : testo, CGPoint(x: cx, y: cy + 14), col)
        case "testo":
            ctx.draw(Text(testo.isEmpty ? "testo" : testo).font(.system(size: 15, weight: .heavy)).foregroundColor(colore), at: primo)
        case "cerchi":
            for r in raggi {
                let rp = CGFloat(r / ctl.metriPerPunto)
                ctx.stroke(Path(ellipseIn: CGRect(x: primo.x - rp, y: primo.y - rp, width: 2 * rp, height: 2 * rp)),
                           with: .color(colore), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                ctx.draw(Text(r >= 1000 ? String(format: "%.1f km", r / 1000) : "\(Int(r)) m").font(Theme.mono(10, .heavy)).foregroundColor(colore),
                         at: CGPoint(x: primo.x, y: primo.y - rp - 8))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: primo.x - 4, y: primo.y - 4, width: 8, height: 8)), with: .color(colore))
        default:
            guard pts.count >= 2 else { return }
            var p = Path(); p.addLines(pts)
            ctx.stroke(p, with: .color(.black.opacity(0.55)), style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round, dash: stile.dash))
            ctx.stroke(p, with: .color(colore), style: stile)
            if tipo == "freccia", let a = pts.last, let b = pts.dropLast().last {
                let ang = atan2(a.y - b.y, a.x - b.x)
                var punta = Path()
                punta.move(to: a)
                punta.addLine(to: CGPoint(x: a.x - 16 * cos(ang - 0.45), y: a.y - 16 * sin(ang - 0.45)))
                punta.addLine(to: CGPoint(x: a.x - 16 * cos(ang + 0.45), y: a.y - 16 * sin(ang + 0.45)))
                punta.closeSubpath()
                ctx.fill(punta, with: .color(colore))
            }
            if tipo == "rotta" {
                for (i, s) in pts.enumerated() {
                    ctx.fill(Path(ellipseIn: CGRect(x: s.x - 9, y: s.y - 9, width: 18, height: 18)), with: .color(colore))
                    ctx.draw(Text("\(i + 1)").font(Theme.mono(10, .heavy)).foregroundColor(.black), at: s)
                }
            }
            scritta(testo, pts[pts.count / 2], colore)
        }
    }
}
