import SwiftUI
import CoreLocation

/// Percorso a piedi su strade e sentieri verso il punto di «Naviga» (NavStore.target), calcolato da Valhalla
/// (OpenStreetMap, servizio pubblico). Stessa logica di Percorso.kt su Android. Resta salvato: senza rete si segue lo stesso.
@MainActor
final class PercorsoPiedi: ObservableObject {
    static let shared = PercorsoPiedi()
    struct Nav: Codable, Equatable {
        var nome: String; var lat: Double; var lon: Double; var punti: [[Double]]; var km: Double; var minuti: Int
        var quote: [Double]? = nil
        var salita: Int { Int(zip(quote ?? [], (quote ?? []).dropFirst()).reduce(0.0) { $0 + max($1.1 - $1.0, 0) }) }
        var discesa: Int { Int(zip(quote ?? [], (quote ?? []).dropFirst()).reduce(0.0) { $0 + max($1.0 - $1.1, 0) }) }
        var difficolta: String {
            let perKm = km > 0 ? Double(salita) / km : 0
            return km > 12 || perKm > 100 ? "impegnativa" : (km > 5 || perKm > 40 ? "media" : "facile")
        }
    }
    @Published private(set) var nav: Nav?
    @Published private(set) var stato = ""
    @Published private(set) var versione = 0

    init() {
        if let d = UserDefaults.standard.data(forKey: "nav.percorso") { nav = try? JSONDecoder().decode(Nav.self, from: d) }
    }

    private func salva(_ n: Nav?) {
        nav = n; versione += 1
        if let n, let d = try? JSONEncoder().encode(n) { UserDefaults.standard.set(d, forKey: "nav.percorso") }
        else { UserDefaults.standard.removeObject(forKey: "nav.percorso") }
    }

    func ferma() { stato = ""; salva(nil) }

    /// il percorso vale solo se porta al punto di Naviga attuale
    func valido(per t: GaraPoint?) -> Bool {
        guard let n = nav, let t else { return false }
        return abs(n.lat - t.lat) < 1e-6 && abs(n.lon - t.lon) < 1e-6
    }

    func calcola(verso t: GaraPoint) async {
        guard let io = LocationService.corrente?.location?.coordinate else { stato = "Aspetto il GPS"; return }
        stato = "calcolo"
        let q = #"{"locations":[{"lat":\#(io.latitude),"lon":\#(io.longitude)},{"lat":\#(t.lat),"lon":\#(t.lon)}],"costing":"pedestrian","costing_options":{"pedestrian":{"use_tracks":1.0,"max_hiking_difficulty":4}},"units":"kilometers","elevation_interval":30}"#
        var c = URLComponents(string: "https://valhalla1.openstreetmap.de/route")!
        c.queryItems = [URLQueryItem(name: "json", value: q)]
        var r = URLRequest(url: c.url!, timeoutInterval: 25)
        r.setValue("JSOC-TAK", forHTTPHeaderField: "User-Agent")
        do {
            let (d, resp) = try await URLSession.shared.data(for: r)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let j = try JSONSerialization.jsonObject(with: d) as? [String: Any], let trip = j["trip"] as? [String: Any],
                  let somma = trip["summary"] as? [String: Any], let legs = trip["legs"] as? [[String: Any]] else {
                stato = "Percorso non trovato: resta la linea d'aria"; return
            }
            let punti = legs.flatMap { Self.decodifica($0["shape"] as? String ?? "") }
            let quote = legs.flatMap { ($0["elevation"] as? [NSNumber] ?? []).map { $0.doubleValue } }
            salva(Nav(nome: t.id, lat: t.lat, lon: t.lon, punti: punti,
                      km: (somma["length"] as? NSNumber)?.doubleValue ?? 0, minuti: Int(((somma["time"] as? NSNumber)?.doubleValue ?? 0) / 60), quote: quote))
            stato = ""
        } catch { stato = "Senza rete: resta la linea d'aria" }
    }

    /// polilinea codificata di Valhalla (precisione 6) → [lat, lon]
    static func decodifica(_ s: String) -> [[Double]] {
        let b = Array(s.utf8); var i = 0, la = 0, lo = 0; var out: [[Double]] = []
        while i < b.count {
            for k in 0..<2 {
                var r = 0, sh = 0, x = 0
                repeat { x = Int(b[i]) - 63; i += 1; r |= (x & 0x1f) << sh; sh += 5 } while x >= 0x20 && i < b.count
                let d = (r & 1) != 0 ? ~(r >> 1) : r >> 1
                if k == 0 { la += d } else { lo += d }
            }
            out.append([Double(la) / 1e6, Double(lo) / 1e6])
        }
        return out
    }

    /// distanza dal tracciato e metri da fare lungo il percorso
    func avanzamento(_ c: CLLocationCoordinate2D) -> (fuori: Double, resto: Double)? {
        guard let n = nav, n.punti.count >= 2 else { return nil }
        let io = CLLocation(latitude: c.latitude, longitude: c.longitude)
        func L(_ p: [Double]) -> CLLocation { CLLocation(latitude: p[0], longitude: p[1]) }
        var best = Double.greatestFiniteMagnitude, idx = 0
        for (k, p) in n.punti.enumerated() { let d = io.distance(from: L(p)); if d < best { best = d; idx = k } }
        var resto = 0.0
        for k in idx..<(n.punti.count - 1) { resto += L(n.punti[k]).distance(from: L(n.punti[k + 1])) }
        return (best, resto)
    }
}

/// In mappa, quando c'è un punto di «Naviga»: tasto «Percorso a piedi» e poi metri, minuti, fuori percorso.
struct PercorsoMappa: View {
    @ObservedObject private var p = PercorsoPiedi.shared
    @ObservedObject private var navStore = NavStore.shared
    @State private var tic = 0
    let ogni = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        if let t = navStore.target {
            HStack(spacing: 10) {
                Image(systemName: "figure.walk").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    if p.stato == "calcolo" {
                        Text("Calcolo il percorso a piedi…").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.cyan)
                    } else if p.valido(per: t), let c = LocationService.corrente?.location?.coordinate, let a = p.avanzamento(c) {
                        let m = a.resto
                        Text((m >= 1000 ? String(format: "%.1f km", m / 1000) : "\(Int(m)) m") + " a piedi · \(Int(m / 80)) min")
                            .font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundStyle(Theme.testo)
                        if a.fuori > 40 { Text("FUORI PERCORSO · \(Int(a.fuori)) m").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.amber) }
                    } else {
                        Text("Verso \(t.id) in linea d'aria").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.testo)
                    }
                    if !p.stato.isEmpty && p.stato != "calcolo" { Text(p.stato).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.amber) }
                }
                .id(tic)
                Button { Task { await p.calcola(verso: t) } } label: {
                    Text(p.valido(per: t) ? "↻" : "Percorso a piedi").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.cyan)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.cyan.opacity(0.14)))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cyan.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                if p.valido(per: t) {
                    Button { p.ferma() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.dim).padding(8) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0x101C1E).opacity(0.94)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cyan, lineWidth: 1.2))
            .onReceive(ogni) { _ in tic += 1 }
        }
    }
}

/// Colonna a destra sotto la bussola (tavola 12): tasto Timer, timer attivi, navigazione con profilo altimetrico.
struct ColonnaNavigazione: View {
    @ObservedObject private var p = PercorsoPiedi.shared
    @ObservedObject private var navStore = NavStore.shared
    @ObservedObject private var tg = TimerGioco.shared
    @ObservedObject private var to = TimerObj.shared
    @State private var pannelloTimer = false
    @State private var tic = 0
    private let ogni = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // tasto Timer tondo come nord e 2D; il timer compare solo se attivo
            Button { haptic(); pannelloTimer.toggle(); if pannelloTimer { GuidaApp.shared.entra("mappa.timer") } } label: {
                Image(systemName: "timer").font(.system(size: 15, weight: .bold))
                    .foregroundStyle(tg.s.corsa || to.attivo != nil ? Theme.green : Theme.olive)
                    .frame(width: 44, height: 44).background(Theme.bg, in: Circle())
            }
            .accessibilityLabel("Timer")
            if pannelloTimer || tg.s.corsa || tg.secondi != tg.s.durata { TimerGiocoMappa(apertoIniziale: pannelloTimer) }
            TimerObjMappa()
            if let t = navStore.target { scheda(t).id(tic) }
        }
        .onReceive(ogni) { _ in if navStore.target != nil { tic += 1 } }
    }

    func scheda(_ t: GaraPoint) -> some View {
        let io = LocationService.corrente?.location
        let valido = p.valido(per: t)
        let av = valido ? io.flatMap { p.avanzamento($0.coordinate) } : nil
        let metri = av?.resto ?? io.map { $0.distance(from: CLLocation(latitude: t.lat, longitude: t.lon)) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("→ \(t.id)").font(.system(size: 13, weight: .black)).foregroundStyle(Theme.testo).lineLimit(1)
                Spacer(minLength: 4)
                Button { p.ferma(); navStore.target = nil } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.dim) }
                    .buttonStyle(.plain)
            }
            if p.stato == "calcolo" {
                Text("Calcolo il percorso…").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.cyan)
            } else if let m = metri {
                Text((m >= 1000 ? String(format: "%.1f km", m / 1000) : "\(Int(m)) m") + " · \(Int(m / 80)) min")
                    .font(.system(size: 17, weight: .heavy, design: .monospaced)).foregroundStyle(Theme.testo)
                Text(valido ? "a piedi" : "linea d'aria").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.cyan)
            }
            if let a = av, a.fuori > 40 {
                Text("FUORI PERCORSO \(Int(a.fuori)) m").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.amber)
            }
            if valido, let n = p.nav, let q = n.quote, q.count >= 2 {
                Text("↑\(n.salita) m ↓\(n.discesa) m · \(n.difficolta)").font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(n.difficolta == "facile" ? Theme.green : (n.difficolta == "media" ? Theme.amber : Theme.red))
                ProfiloAltimetrico(quote: q, fatto: av.map { 1 - $0.resto / max(n.km * 1000, 1) } ?? 0)
                    .frame(height: 54)
                HStack {
                    Text("\(Int(q.min() ?? 0)) m").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(Theme.dim)
                    Spacer()
                    Text("\(Int(q.max() ?? 0)) m").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(Theme.dim)
                }
            }
            if !p.stato.isEmpty && p.stato != "calcolo" { Text(p.stato).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.amber) }
            Button { Task { await p.calcola(verso: t) } } label: {
                Text(valido ? "Ricalcola" : "Percorso a piedi").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.cyan)
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.cyan.opacity(0.14)))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.cyan.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(10).frame(width: 168)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.bg.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cyan.opacity(0.7), lineWidth: 1))
    }
}

/// Profilo altimetrico del percorso; la parte già fatta è più chiara.
struct ProfiloAltimetrico: View {
    let quote: [Double]
    let fatto: Double
    var body: some View {
        GeometryReader { g in
            let lo = quote.min() ?? 0, hi = max((quote.max() ?? 1), lo + 10)
            let pts = quote.enumerated().map { i, q in
                CGPoint(x: g.size.width * CGFloat(i) / CGFloat(max(quote.count - 1, 1)), y: g.size.height * (1 - CGFloat((q - lo) / (hi - lo))))
            }
            let linea = Path { p in p.addLines(pts) }
            let area = Path { p in p.move(to: CGPoint(x: 0, y: g.size.height)); p.addLines(pts); p.addLine(to: CGPoint(x: g.size.width, y: g.size.height)); p.closeSubpath() }
            ZStack {
                area.fill(Theme.cyan.opacity(0.18))
                linea.stroke(Theme.cyan, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                Rectangle().fill(Theme.testo).frame(width: 2)
                    .position(x: g.size.width * CGFloat(min(max(fatto, 0), 1)), y: g.size.height / 2)
            }
        }
    }
}
