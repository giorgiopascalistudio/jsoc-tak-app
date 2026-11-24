import SwiftUI
import CoreLocation

/// Percorso a piedi su strade e sentieri verso il punto di «Naviga» (NavStore.target), calcolato da Valhalla
/// (OpenStreetMap, servizio pubblico). Stessa logica di Percorso.kt su Android. Resta salvato: senza rete si segue lo stesso.
@MainActor
final class PercorsoPiedi: ObservableObject {
    static let shared = PercorsoPiedi()
    struct Nav: Codable, Equatable { var nome: String; var lat: Double; var lon: Double; var punti: [[Double]]; var km: Double; var minuti: Int }
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
        let q = #"{"locations":[{"lat":\#(io.latitude),"lon":\#(io.longitude)},{"lat":\#(t.lat),"lon":\#(t.lon)}],"costing":"pedestrian","costing_options":{"pedestrian":{"use_tracks":1.0,"max_hiking_difficulty":4}},"units":"kilometers"}"#
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
            salva(Nav(nome: t.id, lat: t.lat, lon: t.lon, punti: punti,
                      km: (somma["length"] as? NSNumber)?.doubleValue ?? 0, minuti: Int(((somma["time"] as? NSNumber)?.doubleValue ?? 0) / 60)))
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
