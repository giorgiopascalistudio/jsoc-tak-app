import SwiftUI
import CoreLocation
import CoreBluetooth
import AVKit
import Vision
import MessageUI
import MapLibre
import Charts

// MARK: - Meteo e vento (Open-Meteo, gratis, senza chiave) + radar pioggia (RainViewer)

struct MeteoOraJ: Identifiable { let id: Int; let ora: Date; let temp: Double; let vento: Double; let raffica: Double; let dir: Double; let pioggia: Double; let nuvole: Double }
struct MeteoAdesso { var temp = 0.0, vento = 0.0, raffica = 0.0, dir = 0.0, umidita = 0.0, pressione = 0.0, visibilita = 0.0, nuvole = 0.0
    var vento80 = 0.0, vento120 = 0.0, vento180 = 0.0, dir120 = 0.0, alba: Date?, tramonto: Date? }

enum MeteoServizio {
    static func carica(_ c: CLLocationCoordinate2D) async throws -> (MeteoAdesso, [MeteoOraJ]) {
        let u = URL(string: String(format: "https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f&timezone=auto&forecast_days=2&wind_speed_unit=kmh" +
            "&current=temperature_2m,relative_humidity_2m,wind_speed_10m,wind_gusts_10m,wind_direction_10m,surface_pressure,cloud_cover,visibility" +
            "&hourly=temperature_2m,wind_speed_10m,wind_gusts_10m,wind_direction_10m,precipitation,cloud_cover,wind_speed_80m,wind_speed_120m,wind_speed_180m,wind_direction_120m" +
            "&daily=sunrise,sunset", c.latitude, c.longitude))!
        let (d, _) = try await URLSession.shared.data(from: u)
        guard let j = try JSONSerialization.jsonObject(with: d) as? [String: Any],
              let cur = j["current"] as? [String: Any], let h = j["hourly"] as? [String: Any] else { throw URLError(.cannotParseResponse) }
        func n(_ x: Any?) -> Double { (x as? NSNumber)?.doubleValue ?? 0 }
        func a(_ k: String) -> [Double] { (h[k] as? [Any])?.map { n($0) } ?? [] }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.timeZone = TimeZone(secondsFromGMT: (j["utc_offset_seconds"] as? Int) ?? 0)
        let ore = (h["time"] as? [String] ?? []).compactMap { f.date(from: $0) }
        let t = a("temperature_2m"), v = a("wind_speed_10m"), g = a("wind_gusts_10m"), dd = a("wind_direction_10m"), p = a("precipitation"), cl = a("cloud_cover")
        let v80 = a("wind_speed_80m"), v120 = a("wind_speed_120m"), v180 = a("wind_speed_180m"), d120 = a("wind_direction_120m")
        let adesso = Date()
        let i0 = ore.firstIndex { $0 > adesso.addingTimeInterval(-3600) } ?? 0
        var m = MeteoAdesso(temp: n(cur["temperature_2m"]), vento: n(cur["wind_speed_10m"]), raffica: n(cur["wind_gusts_10m"]), dir: n(cur["wind_direction_10m"]),
                            umidita: n(cur["relative_humidity_2m"]), pressione: n(cur["surface_pressure"]), visibilita: n(cur["visibility"]), nuvole: n(cur["cloud_cover"]))
        if i0 < v80.count { m.vento80 = v80[i0]; m.vento120 = v120[i0]; m.vento180 = v180[i0]; m.dir120 = d120[i0] }
        if let dl = j["daily"] as? [String: Any] {
            m.alba = (dl["sunrise"] as? [String])?.first.flatMap { f.date(from: $0) }
            m.tramonto = (dl["sunset"] as? [String])?.first.flatMap { f.date(from: $0) }
        }
        let lista = (i0..<min(i0 + 18, ore.count)).map { i in
            MeteoOraJ(id: i, ora: ore[i], temp: t[i], vento: v[i], raffica: g[i], dir: dd[i], pioggia: p[i], nuvole: cl[i])
        }
        return (m, lista)
    }

    /// Ultimo fotogramma del radar pioggia (RainViewer, gratis): modello di indirizzo per MapLibre.
    static func radar() async -> String? {
        guard let u = URL(string: "https://api.rainviewer.com/public/weather-maps.json"),
              let (d, _) = try? await URLSession.shared.data(from: u),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let host = j["host"] as? String, let radar = j["radar"] as? [String: Any],
              let passato = radar["past"] as? [[String: Any]], let ultimo = passato.last?["path"] as? String else { return nil }
        return "\(host)\(ultimo)/256/{z}/{x}/{y}/2/1_1.png"
    }
}

struct PannelloMeteo: View {
    let dove: CLLocationCoordinate2D
    @Binding var radar: Bool
    var chiudi: () -> Void
    @State private var adesso: MeteoAdesso?
    @State private var ore: [MeteoOraJ] = []
    @State private var errore: String?

    var body: some View {
        VStack(spacing: 0) {
            TestataPannello(titolo: "Meteo e vento", sotto: coordTesto(dove), chiudi: chiudi)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Radar pioggia sulla mappa", isOn: $radar).tint(Theme.olive).font(.system(size: 14))
                    if let m = adesso {
                        HStack(alignment: .top, spacing: 14) {
                            VStack(alignment: .leading) {
                                Text(String(format: "%.0f°", m.temp)).font(Theme.mono(34, .heavy))
                                Text(String(format: "umidità %.0f%% · %.0f hPa", m.umidita, m.pressione)).font(.caption2).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                HStack(spacing: 4) {
                                    Image(systemName: "location.north.fill").rotationEffect(.degrees(m.dir + 180)).foregroundStyle(Theme.cyan)
                                    Text(String(format: "%.0f km/h", m.vento)).font(Theme.mono(18, .heavy))
                                }
                                Text(String(format: "raffiche %.0f · da %@", m.raffica, Mission.cardinale(m.dir))).font(.caption2).foregroundStyle(Theme.dim)
                                Text(String(format: "visibilità %.1f km · nuvole %.0f%%", m.visibilita / 1000, m.nuvole)).font(.caption2).foregroundStyle(Theme.dim)
                            }
                        }
                        EtichettaSezione(testo: "Vento in quota (droni)")
                        HStack(spacing: 14) {
                            dato(String(format: "%.0f", m.vento80), "80 m")
                            dato(String(format: "%.0f", m.vento120), "120 m")
                            dato(String(format: "%.0f", m.vento180), "180 m")
                            dato(Mission.cardinale(m.dir120), "da")
                        }
                        if let a = m.alba, let t = m.tramonto {
                            Label("Alba \(a.formatted(date: .omitted, time: .shortened)) · tramonto \(t.formatted(date: .omitted, time: .shortened))", systemImage: "sun.horizon")
                                .font(.caption).foregroundStyle(Theme.amber)
                        }
                        EtichettaSezione(testo: "Prossime ore")
                        Chart {
                            ForEach(ore) { o in
                                LineMark(x: .value("ora", o.ora), y: .value("km/h", o.vento)).foregroundStyle(Theme.cyan)
                                LineMark(x: .value("ora", o.ora), y: .value("km/h", o.raffica), series: .value("s", "raffiche")).foregroundStyle(Theme.cyan.opacity(0.4))
                                BarMark(x: .value("ora", o.ora), y: .value("mm", o.pioggia * 10)).foregroundStyle(Color(red: 0.3, green: 0.55, blue: 1).opacity(0.6))
                            }
                        }
                        .frame(height: 100)
                        ForEach(ore.prefix(12)) { o in
                            HStack {
                                Text(o.ora.formatted(date: .omitted, time: .shortened)).font(Theme.mono(11, .bold)).frame(width: 48, alignment: .leading)
                                Text(String(format: "%.0f°", o.temp)).font(Theme.mono(12)).frame(width: 36)
                                Image(systemName: "location.north.fill").font(.caption2).rotationEffect(.degrees(o.dir + 180)).foregroundStyle(Theme.cyan)
                                Text(String(format: "%.0f (%.0f)", o.vento, o.raffica)).font(Theme.mono(11))
                                Spacer()
                                if o.pioggia > 0 { Text(String(format: "%.1f mm", o.pioggia)).font(Theme.mono(11)).foregroundStyle(Color(red: 0.4, green: 0.65, blue: 1)) }
                            }
                        }
                    } else {
                        Text(errore ?? "Carico…").font(.caption).foregroundStyle(errore == nil ? Theme.dim : Theme.red)
                    }
                }
                .padding(14)
            }
        }
        .task {
            do { (adesso, ore) = try await MeteoServizio.carica(dove) } catch { errore = "Meteo non disponibile (serve rete)" }
        }
    }

    func dato(_ v: String, _ e: String) -> some View {
        VStack(alignment: .leading, spacing: 0) { Text(v).font(Theme.mono(15, .heavy)); Text(e).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.dim) }
    }
}

// MARK: - Cerca luoghi (Photon / OpenStreetMap) e punti dell'evento

struct LuogoTrovato: Identifiable { let id = UUID(); let nome: String; let dettaglio: String; let c: CLLocationCoordinate2D }

struct PannelloCerca: View {
    let vicino: CLLocationCoordinate2D
    var chiudi: () -> Void
    var vai: (CLLocationCoordinate2D, String) -> Void
    @ObservedObject private var store = EventoStore.shared
    @State private var testo = ""
    @State private var luoghi: [LuogoTrovato] = []
    @State private var cerca: Task<Void, Never>?

    var body: some View {
        let miei = (store.corrente?.punti ?? []).filter { !testo.isEmpty && $0.nome.localizedCaseInsensitiveContains(testo) }
        VStack(spacing: 0) {
            TestataPannello(titolo: "Cerca", sotto: "punti dell'evento, località, indirizzi", chiudi: chiudi)
            TextField("Paese, via, monte, OBJ…", text: $testo)
                .padding(10).background(Theme.surface2.opacity(0.85), in: RoundedRectangle(cornerRadius: 10)).padding(12)
                .onChange(of: testo) { t in
                    cerca?.cancel()
                    cerca = Task {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        if !Task.isCancelled { await trova(t) }
                    }
                }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if !miei.isEmpty { EtichettaSezione(testo: "Nell'evento") }
                    ForEach(miei) { p in riga(p.nome, p.tipo, p.coordinate) }
                    if !luoghi.isEmpty { EtichettaSezione(testo: "Luoghi").padding(.top, 6) }
                    ForEach(luoghi) { l in riga(l.nome, l.dettaglio, l.c) }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    func riga(_ n: String, _ d: String, _ c: CLLocationCoordinate2D) -> some View {
        Button { vai(c, n) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(n).font(.system(size: 13.5, weight: .bold)).foregroundStyle(.white)
                    Text(d).font(.caption2).foregroundStyle(Theme.dim).lineLimit(1)
                }
                Spacer()
                Text(Geo.formatDistance(Geo.distance(vicino, c))).font(Theme.mono(11)).foregroundStyle(Theme.olive)
            }
            .padding(.vertical, 6)
        }
    }

    func trova(_ t: String) async {
        guard t.count >= 3, let q = t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let u = URL(string: "https://photon.komoot.io/api/?q=\(q)&lat=\(vicino.latitude)&lon=\(vicino.longitude)&limit=12&lang=it") else { luoghi = []; return }
        var r = URLRequest(url: u); r.setValue("JSOC-TAK/1.0", forHTTPHeaderField: "User-Agent")
        guard let (d, _) = try? await URLSession.shared.data(for: r),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let f = j["features"] as? [[String: Any]] else { return }
        luoghi = f.compactMap { x in
            guard let g = x["geometry"] as? [String: Any], let c = g["coordinates"] as? [Double], c.count == 2,
                  let p = x["properties"] as? [String: Any] else { return nil }
            let nome = (p["name"] as? String) ?? (p["street"] as? String) ?? "?"
            let det = [p["street"], p["city"], p["county"], p["state"]].compactMap { $0 as? String }.filter { $0 != nome }.joined(separator: ", ")
            return LuogoTrovato(nome: nome, dettaglio: det, c: .init(latitude: c[1], longitude: c[0]))
        }
    }
}

// MARK: - Livelli extra sulla mappa: rilievo (ombreggiatura), radar pioggia

extension MappaCtl {
    func livelliExtra(rilievo: Bool, radar: String?) {
        guard let st = mappa?.style else { return }
        let sotto = st.layer(withIdentifier: "segni-etichette")
        // ombreggiatura dal modello del terreno (Terrain Tiles AWS, formato terrarium, gratis)
        if rilievo {
            if st.source(withIdentifier: "dem") == nil {
                let s = MLNRasterDEMSource(identifier: "dem", tileURLTemplates: ["https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"],
                                           options: [.tileSize: 256, .maximumZoomLevel: 15, .demEncoding: MLNDEMEncoding.terrarium.rawValue])
                st.addSource(s)
                let l = MLNHillshadeStyleLayer(identifier: "rilievo", source: s)
                l.hillshadeExaggeration = NSExpression(forConstantValue: 0.55)
                if let sotto { st.insertLayer(l, below: sotto) } else { st.addLayer(l) }
            }
        } else {
            if let l = st.layer(withIdentifier: "rilievo") { st.removeLayer(l) }
            if let s = st.source(withIdentifier: "dem") { st.removeSource(s) }
        }
        if let l = st.layer(withIdentifier: "radar") { st.removeLayer(l) }
        if let s = st.source(withIdentifier: "radar") { st.removeSource(s) }
        if let radar {
            let s = MLNRasterTileSource(identifier: "radar", tileURLTemplates: [radar], options: [.tileSize: 256, .maximumZoomLevel: 7])
            st.addSource(s)
            let l = MLNRasterStyleLayer(identifier: "radar", source: s)
            l.rasterOpacity = NSExpression(forConstantValue: 0.6)
            if let sotto { st.insertLayer(l, below: sotto) } else { st.addLayer(l) }
        }
    }

    /// zona visibile (sud, ovest, nord, est)
    var zonaVisibile: (Double, Double, Double, Double)? {
        if let k = mk {
            let r = k.region
            return (r.center.latitude - r.span.latitudeDelta / 2, r.center.longitude - r.span.longitudeDelta / 2,
                    r.center.latitude + r.span.latitudeDelta / 2, r.center.longitude + r.span.longitudeDelta / 2)
        }
        guard let b = mappa?.visibleCoordinateBounds else { return nil }
        return (b.sw.latitude, b.sw.longitude, b.ne.latitude, b.ne.longitude)
    }
}

// MARK: - Telecamere pubbliche

struct Telecamera: Codable, Identifiable, Hashable {
    let id: String
    let nome: String
    let lat: Double
    let lon: Double
    let immagine: String?
    let pagina: String?
    let fonte: String?
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

@MainActor
final class TelecamerePubbliche: ObservableObject {
    static let shared = TelecamerePubbliche()
    @Published var accese = UserDefaults.standard.bool(forKey: "mappa.telecamere") { didSet { UserDefaults.standard.set(accese, forKey: "mappa.telecamere") } }
    @Published var elenco: [Telecamera] = []
    @Published var stato = ""
    private var ultima = ""

    func aggiorna(_ zona: (Double, Double, Double, Double)?) async {
        guard accese, let z = zona else { return }
        // zona larga al massimo ~1 grado intorno al centro
        let cLat = (z.0 + z.2) / 2, cLon = (z.1 + z.3) / 2
        let dLat = min((z.2 - z.0) / 2, 0.6), dLon = min((z.3 - z.1) / 2, 0.6)
        let chiave = String(format: "%.1f,%.1f,%.1f,%.1f", cLat - dLat, cLon - dLon, cLat + dLat, cLon + dLon)
        guard chiave != ultima else { return }
        ultima = chiave
        stato = "Cerco telecamere…"
        do {
            elenco = try await JsocClient.shared.get("/api/telecamere?bbox=\(chiave)")
            stato = elenco.isEmpty ? "Nessuna telecamera pubblica in questa zona" : "\(elenco.count) telecamere"
        } catch { stato = "Telecamere non disponibili" }
    }
}

struct PannelloTelecamera: View {
    let cam: Telecamera
    var chiudi: () -> Void
    @State private var giro = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TestataPannello(titolo: cam.nome, sotto: "\(cam.fonte ?? "") · \(coordTesto(cam.coordinate))", chiudi: chiudi)
            if let s = cam.immagine, !s.isEmpty, let u = URL(string: s + (s.contains("?") ? "&" : "?") + "t=\(giro)") {
                AsyncImage(url: u) { i in i.resizable().scaledToFit() } placeholder: { ProgressView().frame(maxWidth: .infinity, minHeight: 160) }
                    .frame(maxWidth: .infinity)
                Text("Immagine aggiornata ogni 30 secondi").font(.caption2).foregroundStyle(Theme.dim).padding(12)
            } else {
                Text("Questa telecamera ha solo una pagina web.").font(.caption).foregroundStyle(Theme.dim).padding(14)
            }
            if let p = cam.pagina, let u = URL(string: p) {
                Link(destination: u) { Label("Apri la diretta", systemImage: "play.rectangle.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(Theme.olive).foregroundStyle(.black).padding(.horizontal, 14)
            }
            Spacer()
        }
        .task { while !Task.isCancelled { try? await Task.sleep(nanoseconds: 30_000_000_000); giro += 1 } }
    }
}

// MARK: - Replay delle tracce e cronologia

struct TracciaStorica: Codable, Identifiable { let id: Int; let callsign: String; let punti: [[Double?]] }

struct PannelloReplay: View {
    @Binding var istante: Double
    @Binding var tracce: [TracciaStorica]
    var chiudi: () -> Void
    @ObservedObject private var store = EventoStore.shared
    @State private var gioca = false
    @State private var velocita = 30.0
    @State private var errore: String?

    var inizio: Double { tracce.flatMap { $0.punti.compactMap { $0[2] } }.min() ?? 0 }
    var fine: Double { tracce.flatMap { $0.punti.compactMap { $0[2] } }.max() ?? 1 }

    var body: some View {
        VStack(spacing: 0) {
            TestataPannello(titolo: "Replay", sotto: "\(tracce.count) operatori · \(Date(timeIntervalSince1970: istante).formatted(date: .abbreviated, time: .standard))", chiudi: chiudi)
            VStack(alignment: .leading, spacing: 10) {
                if tracce.isEmpty {
                    Text(errore ?? "Carico le posizioni dell'evento…").font(.caption).foregroundStyle(Theme.dim)
                } else {
                    Slider(value: $istante, in: inizio...max(fine, inizio + 1)).tint(Theme.olive)
                    HStack {
                        Text(Date(timeIntervalSince1970: inizio).formatted(date: .omitted, time: .shortened)).font(Theme.mono(10)).foregroundStyle(Theme.dim)
                        Spacer()
                        Text(Date(timeIntervalSince1970: fine).formatted(date: .omitted, time: .shortened)).font(Theme.mono(10)).foregroundStyle(Theme.dim)
                    }
                    HStack(spacing: 8) {
                        Button { gioca.toggle() } label: { Image(systemName: gioca ? "pause.fill" : "play.fill").frame(width: 40, height: 32) }
                            .buttonStyle(.borderedProminent).tint(Theme.olive).foregroundStyle(.black)
                        Picker("", selection: $velocita) {
                            Text("×10").tag(10.0); Text("×30").tag(30.0); Text("×120").tag(120.0); Text("×600").tag(600.0)
                        }
                        .pickerStyle(.segmented)
                    }
                    Text("Le scie mostrano gli ultimi 10 minuti prima dell'istante scelto.").font(.caption2).foregroundStyle(Theme.dim)
                }
            }
            .padding(14)
            Spacer(minLength: 0)
        }
        .task {
            guard let ev = store.corrente?.id else { return }
            do {
                tracce = try await JsocClient.shared.get("/api/eventi/\(ev)/storico?passo=10")
                istante = inizio
            } catch { errore = error.localizedDescription }
        }
        .task(id: gioca) {
            while gioca && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                istante = min(fine, istante + velocita / 10)
                if istante >= fine { gioca = false }
            }
        }
        .onDisappear { tracce = [] }
    }

    /// posizione di ogni operatore all'istante t (+ scia degli ultimi 10 minuti)
    static func posizioni(_ tracce: [TracciaStorica], _ t: Double) -> [(String, CLLocationCoordinate2D, [CLLocationCoordinate2D])] {
        tracce.compactMap { tr in
            let pts = tr.punti.filter { ($0[2] ?? 0) <= t }
            guard let u = pts.last, let la = u[0], let lo = u[1] else { return nil }
            let scia = pts.filter { ($0[2] ?? 0) > t - 600 }.compactMap { p in p[0].flatMap { a in p[1].map { CLLocationCoordinate2D(latitude: a, longitude: $0) } } }
            return (tr.callsign, .init(latitude: la, longitude: lo), scia)
        }
    }
}

struct VoceCronologia: Codable, Identifiable { var id: String { "\(ts)\(testo)" }; let ts: Double; let tipo: String; let chi: String?; let testo: String; let lat: Double?; let lon: Double? }

struct PannelloCronologia: View {
    var chiudi: () -> Void
    var vai: (CLLocationCoordinate2D) -> Void
    @ObservedObject private var store = EventoStore.shared
    @State private var voci: [VoceCronologia] = []

    var body: some View {
        VStack(spacing: 0) {
            TestataPannello(titolo: "Cronologia", sotto: store.corrente?.nome, chiudi: chiudi)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(voci.reversed()) { v in
                        Button { if let la = v.lat, let lo = v.lon { vai(.init(latitude: la, longitude: lo)) } } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: icona(v.tipo)).foregroundStyle(Theme.olive).frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(v.testo).font(.system(size: 12.5)).foregroundStyle(.white).multilineTextAlignment(.leading).lineLimit(3)
                                    Text("\(Date(timeIntervalSince1970: v.ts).formatted(date: .omitted, time: .shortened)) · \(v.chi ?? "")").font(Theme.mono(9.5)).foregroundStyle(Theme.dim)
                                }
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
        .task {
            guard let ev = store.corrente?.id else { return }
            voci = (try? await JsocClient.shared.get("/api/eventi/\(ev)/cronologia")) ?? []
        }
    }

    func icona(_ t: String) -> String {
        ["messaggio": "bubble.left.fill", "punto": "mappin", "indagine": "magnifyingglass", "disegno": "scribble"][t] ?? "circle"
    }
}

// MARK: - Visibilità a 360° (cosa vedo da qui)

enum Visibilita {
    /// 36 raggi da 10°, 20 campioni ciascuno fino a `raggio` metri: verde = visibile dagli occhi (1,7 m), rosso = coperto.
    static func calcola(da c: CLLocationCoordinate2D, raggio: Double) async throws -> [[(CLLocationCoordinate2D, Bool)]] {
        let nRaggi = 36, nPassi = 20
        var punti: [CLLocationCoordinate2D] = [c]
        for r in 0..<nRaggi {
            for s in 1...nPassi {
                punti.append(Geo.proietta(c, azimut: Double(r) * 10, distanza: raggio * Double(s) / Double(nPassi)))
            }
        }
        var quote: [Double] = []
        for blocco in stride(from: 0, to: punti.count, by: 100) {
            let parte = Array(punti[blocco..<min(blocco + 100, punti.count)])
            let la = parte.map { String(format: "%.5f", $0.latitude) }.joined(separator: ",")
            let lo = parte.map { String(format: "%.5f", $0.longitude) }.joined(separator: ",")
            let (d, _) = try await URLSession.shared.data(from: URL(string: "https://api.open-meteo.com/v1/elevation?latitude=\(la)&longitude=\(lo)")!)
            struct R: Decodable { let elevation: [Double] }
            quote += try JSONDecoder().decode(R.self, from: d).elevation
        }
        guard quote.count == punti.count else { return [] }
        let occhio = quote[0] + 1.7
        var out: [[(CLLocationCoordinate2D, Bool)]] = []
        for r in 0..<nRaggi {
            var maxPend = -Double.infinity
            var raggioPts: [(CLLocationCoordinate2D, Bool)] = [(c, true)]
            for s in 1...nPassi {
                let i = 1 + r * nPassi + (s - 1)
                let dist = raggio * Double(s) / Double(nPassi)
                let pend = (quote[i] + 1.0 - occhio) / dist
                let vis = pend >= maxPend
                maxPend = max(maxPend, (quote[i] - occhio) / dist)
                raggioPts.append((punti[i], vis))
            }
            out.append(raggioPts)
        }
        return out
    }
}

extension Geo {
    /// punto a una certa distanza e azimut (sfera, va bene fino a qualche km)
    static func proietta(_ c: CLLocationCoordinate2D, azimut: Double, distanza: Double) -> CLLocationCoordinate2D {
        let r = 6_371_000.0, d = distanza / r, b = azimut * .pi / 180
        let la1 = c.latitude * .pi / 180, lo1 = c.longitude * .pi / 180
        let la2 = asin(sin(la1) * cos(d) + cos(la1) * sin(d) * cos(b))
        let lo2 = lo1 + atan2(sin(b) * sin(d) * cos(la1), cos(d) - sin(la1) * sin(la2))
        return .init(latitude: la2 * 180 / .pi, longitude: lo2 * 180 / .pi)
    }
}

struct PannelloVista360: View {
    let da: CLLocationCoordinate2D
    @Binding var raggi: [[(CLLocationCoordinate2D, Bool)]]
    var chiudi: () -> Void
    @State private var distanza = 1000.0
    @State private var lavoro = false
    @State private var errore: String?

    var body: some View {
        VStack(spacing: 0) {
            TestataPannello(titolo: "Visibilità a 360°", sotto: "da " + coordTesto(da), chiudi: chiudi)
            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: $distanza) { Text("300 m").tag(300.0); Text("1 km").tag(1000.0); Text("2 km").tag(2000.0); Text("5 km").tag(5000.0) }
                    .pickerStyle(.segmented)
                Button { calcola() } label: { Text(lavoro ? "Calcolo…" : "Calcola").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(Theme.olive).foregroundStyle(.black).disabled(lavoro)
                if !raggi.isEmpty {
                    let tot = raggi.flatMap { $0 }.count, vis = raggi.flatMap { $0 }.filter(\.1).count
                    Text("Visibile circa il \(tot > 0 ? vis * 100 / tot : 0)% della zona. Verde = si vede, rosso = coperto dal terreno.").font(.caption).foregroundStyle(Theme.dim)
                }
                Text("Solo terreno (modello 90 m): alberi ed edifici non contano. Serve rete. Il punto di vista è il centro della mappa.").font(.caption2).foregroundStyle(Theme.dim)
                if let errore { Text(errore).font(.caption).foregroundStyle(Theme.red) }
            }
            .padding(14)
            Spacer(minLength: 0)
        }
    }

    func calcola() {
        lavoro = true; errore = nil
        Task {
            defer { lavoro = false }
            do { raggi = try await Visibilita.calcola(da: da, raggio: distanza) } catch { errore = "Quote non disponibili: \(error.localizedDescription)" }
        }
    }
}

// MARK: - Chi arriva prima su un punto

struct PannelloPiuVicini: View {
    let punto: JPunto
    var chiudi: () -> Void
    var chat: (Int) -> Void
    @ObservedObject private var store = EventoStore.shared

    var body: some View {
        let lista = store.squadra.filter { $0.eta < 600 }.map { c in (c, Geo.distance(c.coordinate, punto.coordinate)) }.sorted { $0.1 < $1.1 }
        VStack(spacing: 0) {
            TestataPannello(titolo: "Chi arriva prima", sotto: punto.nome, chiudi: chiudi)
            ScrollView {
                VStack(spacing: 6) {
                    if lista.isEmpty { Text("Nessun compagno con posizione recente.").font(.caption).foregroundStyle(Theme.dim) }
                    ForEach(lista, id: \.0.id) { c, d in
                        HStack {
                            Text(c.callsign).font(Theme.mono(14, .heavy))
                            Spacer()
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(Geo.formatDistance(d)).font(Theme.mono(13, .bold)).foregroundStyle(Theme.oliveBright)
                                Text("~\(max(1, Int(d / 1000 / 4.5 * 60 * 1.3))) min a piedi").font(.caption2).foregroundStyle(Theme.dim)
                            }
                            Button { chat(c.id) } label: { Image(systemName: "bubble.left.fill") }.buttonStyle(.bordered).tint(Theme.olive)
                        }
                        .padding(10).background(Theme.surface2.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
                    }
                    Text("Stima in linea d'aria a 4,5 km/h con il 30% in più per il terreno.").font(.caption2).foregroundStyle(Theme.dim)
                }
                .padding(12)
            }
        }
    }
}

// MARK: - Checklist medica (MARCH)

struct PannelloMedico: View {
    var chiudi: () -> Void
    @State private var fatti: Set<String> = []
    let passi: [(String, String, [String])] = [
        ("M", "Emorragie gravi", ["Pressione diretta sulla ferita", "Laccio emostatico alto e stretto, segna l'ora", "Tamponamento della ferita"]),
        ("A", "Vie aeree", ["Parla? Respira?", "Posizione laterale di sicurezza se incosciente", "Libera la bocca"]),
        ("R", "Respirazione", ["Guarda il torace: si alza da entrambi i lati?", "Ferita al torace: medicazione occlusiva"]),
        ("C", "Circolazione", ["Polso, colore, temperatura della pelle", "Controlla altre emorragie", "Gambe sollevate se in shock"]),
        ("H", "Ipotermia e testa", ["Copri con telo termico", "Trauma cranico: tienilo sveglio, osserva le pupille"]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TestataPannello(titolo: "Primo soccorso · MARCH", sotto: "in ordine, dall'alto in basso", chiudi: chiudi)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(passi, id: \.0) { p in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text(p.0).font(Theme.mono(18, .heavy)).foregroundStyle(Theme.red); Text(p.1).font(.system(size: 14, weight: .heavy)) }
                            ForEach(p.2, id: \.self) { v in
                                Button { if fatti.contains(v) { fatti.remove(v) } else { fatti.insert(v); haptic() } } label: {
                                    HStack(alignment: .top) {
                                        Image(systemName: fatti.contains(v) ? "checkmark.square.fill" : "square").foregroundStyle(fatti.contains(v) ? Theme.green : Theme.dim)
                                        Text(v).font(.system(size: 13)).foregroundStyle(.white).multilineTextAlignment(.leading)
                                    }
                                }
                            }
                        }
                    }
                    Text("Promemoria per il primo soccorso in campo: non sostituisce un corso né il 112.").font(.caption2).foregroundStyle(Theme.dim)
                    if let u = URL(string: "tel://112") { Link(destination: u) { Label("Chiama il 112", systemImage: "phone.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(Theme.red) }
                }
                .padding(14)
            }
        }
    }
}

// MARK: - Calcolatore balistico per softair

struct PannelloBalistica: View {
    var chiudi: () -> Void
    @AppStorage("bb.peso") private var peso = 0.28        // grammi
    @AppStorage("bb.fps") private var fps = 350.0
    @AppStorage("bb.hop") private var hop = 85.0           // % del peso compensato dall'hop-up

    var body: some View {
        let v0 = fps * 0.3048
        let joule = 0.5 * peso / 1000 * v0 * v0
        let r = simula(v0: v0, m: peso / 1000, hop: hop / 100)
        VStack(spacing: 0) {
            TestataPannello(titolo: "Balistica BB", sotto: "pallino 6 mm", chiudi: chiudi)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    riga("Peso pallino", String(format: "%.2f g", peso)); Slider(value: $peso, in: 0.12...0.48, step: 0.01).tint(Theme.olive)
                    riga("Velocità in uscita", String(format: "%.0f fps · %.0f m/s", fps, v0)); Slider(value: $fps, in: 200...600, step: 5).tint(Theme.olive)
                    riga("Hop-up", String(format: "%.0f%%", hop)); Slider(value: $hop, in: 0...110, step: 1).tint(Theme.olive)
                    Divider().overlay(Theme.stroke)
                    HStack(spacing: 16) {
                        dato(String(format: "%.2f J", joule), "ENERGIA")
                        dato(String(format: "%.0f m", r.gittata), "TIRO UTILE")
                        dato(String(format: "%.2f s", r.tempo50), "VOLO A 50 m")
                    }
                    Text(String(format: "A 50 m: %.1f m/s, %.2f J. Tiro utile = finché il pallino resta entro ±30 cm dalla linea di mira.", r.v50, 0.5 * peso / 1000 * r.v50 * r.v50))
                        .font(.caption).foregroundStyle(Theme.dim)
                    Text("Modello semplificato (resistenza dell'aria e hop-up costante): utile per confrontare le configurazioni, non per misure ufficiali.").font(.caption2).foregroundStyle(Theme.dim)
                }
                .padding(14)
            }
        }
    }

    func riga(_ a: String, _ b: String) -> some View { HStack { Text(a).font(.system(size: 13)); Spacer(); Text(b).font(Theme.mono(13, .bold)).foregroundStyle(Theme.oliveBright) } }
    func dato(_ v: String, _ e: String) -> some View {
        VStack(alignment: .leading, spacing: 0) { Text(v).font(Theme.mono(16, .heavy)); Text(e).font(.system(size: 8.5, weight: .bold)).foregroundStyle(Theme.dim) }
    }

    /// traiettoria orizzontale con resistenza (Cd 0,47) e spinta dell'hop-up proporzionale al peso
    func simula(v0: Double, m: Double, hop: Double) -> (gittata: Double, tempo50: Double, v50: Double) {
        let rho = 1.225, d = 0.00595, a = Double.pi * d * d / 4, cd = 0.47, g = 9.81
        var x = 0.0, y = 0.0, vx = v0, vy = 0.0, t = 0.0, dt = 0.001
        var gittata = 0.0, t50 = 0.0, v50 = 0.0
        while t < 4 && x < 150 {
            let v = sqrt(vx * vx + vy * vy)
            let fd = 0.5 * rho * cd * a * v * v
            let lift = hop * m * g * (v / v0)       // l'hop-up cala con la velocità
            vx += (-fd * vx / v / m) * dt
            vy += (-g + lift / m - fd * vy / v / m) * dt
            x += vx * dt; y += vy * dt; t += dt
            if abs(y) <= 0.30 { gittata = x }
            if t50 == 0 && x >= 50 { t50 = t; v50 = v }
            if y < -2 { break }
        }
        return (gittata, t50, v50)
    }
}

// MARK: - SMS con la posizione (quando non c'è dati)

struct ComponiSMS: UIViewControllerRepresentable {
    let testo: String
    var fine: () -> Void
    func makeCoordinator() -> C { C(fine) }
    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let v = MFMessageComposeViewController()
        v.body = testo
        v.messageComposeDelegate = context.coordinator
        return v
    }
    func updateUIViewController(_ v: MFMessageComposeViewController, context: Context) {}
    final class C: NSObject, MFMessageComposeViewControllerDelegate {
        let fine: () -> Void
        init(_ f: @escaping () -> Void) { fine = f }
        func messageComposeViewController(_ c: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) { fine() }
    }
}

/// Condivide un punto (AirDrop, messaggi, WhatsApp): testo con coordinate e link, più un GPX.
func condividiPunto(nome: String, _ c: CLLocationCoordinate2D) {
    let gpx = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="JSOC TAK"><wpt lat="\(c.latitude)" lon="\(c.longitude)"><name>\(nome)</name></wpt></gpx>
    """
    let f = FileManager.default.temporaryDirectory.appendingPathComponent("\(nome.replacingOccurrences(of: "/", with: "-")).gpx")
    try? gpx.write(to: f, atomically: true, encoding: .utf8)
    let testo = "\(nome)\n\(Geo.mgrs(c))\n\(String(format: "%.6f, %.6f", c.latitude, c.longitude))\nhttps://maps.apple.com/?ll=\(c.latitude),\(c.longitude)"
    let vc = UIActivityViewController(activityItems: [testo, f], applicationActivities: nil)
    guard let s = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
          var top = s.keyWindow?.rootViewController else { return }
    while let p = top.presentedViewController { top = p }
    vc.popoverPresentationController?.sourceView = top.view
    top.present(vc, animated: true)
}

// MARK: - Stampa la mappa (PDF)

enum StampaMappa {
    @MainActor static func pdf(ctl: MappaCtl, titolo: String, punti: [JPunto]) async -> URL? {
        guard let m = ctl.mappa else { return nil }
        let size = CGSize(width: 1600, height: 1130)
        let opt = MLNMapSnapshotOptions(styleURL: ctl.stile.url, camera: m.camera, size: size)
        opt.zoomLevel = m.zoomLevel
        let snap = MLNMapSnapshotter(options: opt)
        let s: MLNMapSnapshot? = await withCheckedContinuation { k in snap.start { r, _ in k.resume(returning: r) } }
        guard let s else { return nil }
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("\(titolo.replacingOccurrences(of: "/", with: "-")) mappa.pdf")
        let pagina = CGRect(x: 0, y: 0, width: 842, height: 595)   // A4 orizzontale
        let r = UIGraphicsPDFRenderer(bounds: pagina)
        try? r.writePDF(to: f) { ctx in
            ctx.beginPage()
            let img = UIGraphicsImageRenderer(size: size).image { _ in
                s.image.draw(at: .zero)
                for p in punti {
                    let q = s.point(for: p.coordinate)
                    UIColor.red.setFill()
                    UIBezierPath(ovalIn: CGRect(x: q.x - 7, y: q.y - 7, width: 14, height: 14)).fill()
                    (p.nome as NSString).draw(at: CGPoint(x: q.x + 9, y: q.y - 9), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 16),
                        .foregroundColor: UIColor.black, .backgroundColor: UIColor.white.withAlphaComponent(0.7)])
                }
            }
            img.draw(in: CGRect(x: 20, y: 46, width: 802, height: 802 * size.height / size.width))
            let a: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 16)]
            (titolo as NSString).draw(at: CGPoint(x: 20, y: 16), withAttributes: a)
            let info = "Centro \(Geo.mgrs(m.centerCoordinate)) · \(Date().formatted(date: .abbreviated, time: .shortened)) · JSOC TAK"
            (info as NSString).draw(at: CGPoint(x: 20, y: 572), withAttributes: [.font: UIFont.systemFont(ofSize: 10)])
        }
        return f
    }
}

// MARK: - Droni (Remote ID via Bluetooth, standard ASTM F3411)

struct Drone: Identifiable { let id: String; var lat: Double; var lon: Double; var quota: Double?; var velocita: Double?; var direzione: Double?; var visto: Date
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) } }

final class DroniRemoteID: NSObject, ObservableObject, CBCentralManagerDelegate {
    static let shared = DroniRemoteID()
    @Published var attivo = false
    @Published var droni: [String: Drone] = [:]
    @Published var stato = ""
    private var central: CBCentralManager?
    private var idPerPeriferica: [UUID: String] = [:]
    static let servizio = CBUUID(string: "FFFA")

    func avvia() {
        attivo = true
        if central == nil { central = CBCentralManager(delegate: self, queue: nil) } else { cerca() }
    }
    func ferma() { attivo = false; central?.stopScan(); stato = "Spento" }

    private func cerca() {
        guard central?.state == .poweredOn, attivo else { return }
        central?.scanForPeripherals(withServices: [Self.servizio], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        stato = "In ascolto dei droni vicini (Bluetooth)…"
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) { c.state == .poweredOn ? cerca() : (stato = "Bluetooth non disponibile") }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        guard let sd = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data], let d = sd[Self.servizio], d.count >= 27 else { return }
        // [0x0D app code][contatore][messaggio 25 byte]
        let msg = [UInt8](d.dropFirst(2))
        interpreta(msg, p.identifier)
    }

    private func interpreta(_ m: [UInt8], _ per: UUID) {
        guard m.count >= 25 else { return }
        let tipo = m[0] >> 4
        switch tipo {
        case 0x0:   // Basic ID: numero di serie
            let id = String(bytes: m[2..<22], encoding: .ascii)?.trimmingCharacters(in: .controlCharacters.union(.whitespaces)) ?? ""
            if !id.isEmpty { idPerPeriferica[per] = id }
        case 0x1:   // Location
            func i32(_ o: Int) -> Int32 { Int32(bitPattern: UInt32(m[o]) | UInt32(m[o + 1]) << 8 | UInt32(m[o + 2]) << 16 | UInt32(m[o + 3]) << 24) }
            let lat = Double(i32(5)) / 1e7, lon = Double(i32(9)) / 1e7
            guard lat != 0 || lon != 0, abs(lat) <= 90 else { return }
            let ew = (m[1] & 0x02) != 0
            let dir = Double(m[2]) + (ew ? 180 : 0)
            let mult = (m[1] & 0x01) != 0
            let vel = mult ? Double(m[3]) * 0.75 + 255 * 0.25 : Double(m[3]) * 0.25
            let alt = Double(UInt16(m[15]) | UInt16(m[16]) << 8) * 0.5 - 1000
            let id = idPerPeriferica[per] ?? String(per.uuidString.prefix(6))
            DispatchQueue.main.async {
                self.droni[id] = Drone(id: id, lat: lat, lon: lon, quota: alt, velocita: vel, direzione: dir, visto: Date())
            }
        case 0xF:   // pacchetto con più messaggi
            let n = Int(m[2]), dim = Int(m[1])
            guard dim == 25 else { return }
            for k in 0..<n where 3 + (k + 1) * 25 <= m.count { interpreta(Array(m[(3 + k * 25)..<(3 + (k + 1) * 25)]), per) }
        default: break
        }
    }
}

struct PannelloDroni: View {
    @ObservedObject var droni = DroniRemoteID.shared
    var chiudi: () -> Void
    var vai: (CLLocationCoordinate2D) -> Void
    @EnvironmentObject var location: LocationService

    var body: some View {
        VStack(spacing: 0) {
            TestataPannello(titolo: "Droni vicini", sotto: droni.stato, chiudi: chiudi)
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Ascolta i droni (Remote ID)", isOn: Binding(get: { droni.attivo }, set: { $0 ? droni.avvia() : droni.ferma() })).tint(Theme.olive)
                ForEach(droni.droni.values.sorted { $0.visto > $1.visto }) { d in
                    Button { vai(d.coordinate) } label: {
                        HStack {
                            Image(systemName: "airplane").foregroundStyle(Theme.amber)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(d.id).font(Theme.mono(12, .bold)).foregroundStyle(.white)
                                Text([d.quota.map { String(format: "%.0f m", $0) }, d.velocita.map { String(format: "%.0f km/h", $0 * 3.6) }].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption2).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            if let me = location.location?.coordinate { Text(Geo.formatDistance(Geo.distance(me, d.coordinate))).font(Theme.mono(12)).foregroundStyle(Theme.olive) }
                        }
                    }
                }
                Text("Riceve il Remote ID che i droni recenti trasmettono via Bluetooth (portata qualche centinaio di metri). Il Remote ID via wifi non è leggibile da iPhone.").font(.caption2).foregroundStyle(Theme.dim)
            }
            .font(.system(size: 14))
            .padding(14)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Muro video con rilevamento persone

struct MuroVideo: View {
    var chiudi: () -> Void
    @State private var flussi: [JFlusso] = []
    @State private var rileva = false

    var body: some View {
        let on = flussi.filter(\.pronto).prefix(4)
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if on.isEmpty {
                Text("Nessun video in onda").foregroundStyle(Theme.dim)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], spacing: 4) {
                    ForEach(Array(on)) { f in CellaVideo(nome: f.nome, rileva: rileva) }
                }
                .padding(4)
            }
            HStack {
                Toggle("Rileva persone", isOn: $rileva).toggleStyle(.button).tint(Theme.amber)
                Button { chiudi() } label: { Image(systemName: "xmark.circle.fill").font(.title) }.tint(.white)
            }
            .padding(10)
        }
        .task {
            while !Task.isCancelled {
                flussi = (try? await JsocClient.shared.flussiVideo()) ?? flussi
                try? await Task.sleep(nanoseconds: 8_000_000_000)
            }
        }
    }
}

struct CellaVideo: View {
    let nome: String
    let rileva: Bool
    @StateObject private var m = ModelloCella()

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let p = m.player { VideoPlayer(player: p) }
            GeometryReader { g in
                ForEach(m.riquadri.indices, id: \.self) { i in
                    let r = m.riquadri[i]
                    Rectangle().stroke(Theme.amber, lineWidth: 2)
                        .frame(width: r.width * g.size.width, height: r.height * g.size.height)
                        .position(x: r.midX * g.size.width, y: (1 - r.midY) * g.size.height)
                }
            }
            .allowsHitTesting(false)
            Text("LIVE · \(nome)\(m.riquadri.isEmpty ? "" : " · \(m.riquadri.count) persone")").font(Theme.mono(10, .heavy)).foregroundStyle(.black)
                .padding(.horizontal, 6).padding(.vertical, 2).background(Theme.red, in: RoundedRectangle(cornerRadius: 4)).padding(6)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .onAppear { m.avvia(nome) }
        .onDisappear { m.ferma() }
        .onChange(of: rileva) { m.rileva = $0 }
    }
}

/// Lettore di un flusso + rilevamento persone sul telefono (Vision, ogni mezzo secondo).
@MainActor
final class ModelloCella: ObservableObject {
    @Published var player: AVPlayer?
    @Published var riquadri: [CGRect] = []
    var rileva = false { didSet { if !rileva { riquadri = [] } } }
    private let uscita = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    private var timer: Timer?

    func avvia(_ nome: String) {
        guard let u = JsocClient.shared.videoURL(nome) else { return }
        let item = AVPlayerItem(url: u)
        item.add(uscita)
        let p = AVPlayer(playerItem: item)
        p.isMuted = true
        p.play()
        player = p
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.analizza() }
        }
    }

    func ferma() { timer?.invalidate(); player?.pause() }

    private func analizza() {
        guard rileva, let item = player?.currentItem else { return }
        let t = item.currentTime()
        guard uscita.hasNewPixelBuffer(forItemTime: t), let buf = uscita.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: nil) else { return }
        let req = VNDetectHumanRectanglesRequest()
        req.upperBodyOnly = false
        DispatchQueue.global(qos: .userInitiated).async {
            try? VNImageRequestHandler(cvPixelBuffer: buf, options: [:]).perform([req])
            let r = (req.results ?? []).map(\.boundingBox)
            DispatchQueue.main.async { self.riquadri = r }
        }
    }
}

/// Foglio di condivisione di sistema (AirDrop, Messaggi, WhatsApp, File…).
func condividi(_ items: [Any]) {
    let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
    guard let s = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
          var top = s.keyWindow?.rootViewController else { return }
    while let p = top.presentedViewController { top = p }
    vc.popoverPresentationController?.sourceView = top.view
    top.present(vc, animated: true)
}

// MARK: - Messaggi vocali in chat (tieni premuto per parlare)

struct RegistraVoce: View {
    let dest: Int?
    @ObservedObject private var store = EventoStore.shared
    @State private var registratore: AVAudioRecorder?
    @State private var inizio: Date?
    @State private var invio = false

    var body: some View {
        Image(systemName: registratore == nil ? "mic.fill" : "waveform")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(registratore == nil ? (invio ? Theme.dim : Theme.olive) : .black)
            .frame(width: 40, height: 40)
            .background(registratore == nil ? Color.clear : Theme.red, in: Circle())
            .scaleEffect(registratore == nil ? 1 : 1.25)
            .animation(.spring(response: 0.25), value: registratore == nil)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if registratore == nil && !invio { avvia() } }
                .onEnded { _ in ferma() })
            .accessibilityLabel("Tieni premuto per un messaggio vocale")
    }

    func avvia() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try? s.setActive(true)
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("voce-\(Int(Date().timeIntervalSince1970)).m4a")
        let r = try? AVAudioRecorder(url: f, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 22050, AVNumberOfChannelsKey: 1,
                                                       AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue])
        r?.record()
        registratore = r
        inizio = Date()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func ferma() {
        guard let r = registratore else { return }
        r.stop()
        registratore = nil
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        let durata = Date().timeIntervalSince(inizio ?? Date())
        guard durata > 0.6, let ev = store.corrente?.id, let d = try? Data(contentsOf: r.url) else { return }
        invio = true
        let percorso = "Inviati/voce/\(JsocClient.shared.utente?.callsign ?? "io")-\(Int(Date().timeIntervalSince1970)).m4a"
        Task {
            defer { invio = false }
            do {
                try await JsocClient.shared.caricaFile(ev, percorso, dati: d)
                try await store.scrivi(String(format: "🎙 messaggio vocale · %.0f s", durata), JsocClient.shared, posizione: nil, dest: dest, allegato: percorso)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {}
        }
    }
}

struct TastoVoce: View {
    let percorso: String
    @ObservedObject private var store = EventoStore.shared
    @State private var lettore: AVAudioPlayer?
    @State private var carico = false

    var body: some View {
        Button {
            if let l = lettore, l.isPlaying { l.stop(); lettore = nil; return }
            guard let ev = store.corrente?.id else { return }
            carico = true
            Task {
                defer { carico = false }
                guard let u = try? await JsocClient.shared.scaricaFile(ev, percorso), let d = try? Data(contentsOf: u) else { return }
                try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
                lettore = try? AVAudioPlayer(data: d)
                lettore?.play()
            }
        } label: {
            HStack(spacing: 6) {
                if carico { ProgressView() } else { Image(systemName: lettore?.isPlaying == true ? "stop.fill" : "play.fill") }
                Image(systemName: "waveform").foregroundStyle(Theme.olive)
                Text("messaggio vocale").font(.subheadline)
            }
        }
        .tint(.white)
    }
}
