import SwiftUI
import CoreLocation

// MARK: - Calcoli

/// Calcoli in un piano locale (metri, x = est, y = nord vero) centrato sul primo punto:
/// così gli azimut veri si usano direttamente, senza convergenza della griglia UTM.
enum Triang {
    struct P { var x: Double; var y: Double }

    static func piano(_ o: CLLocationCoordinate2D) -> (mx: Double, my: Double) {
        let f = o.latitude * .pi / 180
        return (111412.84 * cos(f) - 93.5 * cos(3 * f), 111132.954 - 559.822 * cos(2 * f) + 1.175 * cos(4 * f))
    }

    static func xy(_ c: CLLocationCoordinate2D, _ o: CLLocationCoordinate2D) -> P {
        let m = piano(o)
        return P(x: (c.longitude - o.longitude) * m.mx, y: (c.latitude - o.latitude) * m.my)
    }

    static func geo(_ p: P, _ o: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let m = piano(o)
        return .init(latitude: o.latitude + p.y / m.my, longitude: o.longitude + p.x / m.mx)
    }

    static func az(_ a: P, _ b: P) -> Double { (atan2(b.x - a.x, b.y - a.y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360) }
    static func dist(_ a: P, _ b: P) -> Double { hypot(b.x - a.x, b.y - a.y) }

    /// Intersezione di 2 o più direzioni (minimi quadrati sulle distanze dalle rette).
    /// Restituisce anche l'errore: per 3 direzioni la distanza media dalle rette (triangolo d'errore).
    static func azimut(_ st: [(P, Double)]) -> (P, Double, Bool)? {
        var a11 = 0.0, a12 = 0.0, a22 = 0.0, b1 = 0.0, b2 = 0.0
        for (s, th) in st {
            let t = th * .pi / 180
            let nx = cos(t), ny = -sin(t)          // normale alla direzione (sin t, cos t)
            let c = nx * s.x + ny * s.y
            a11 += nx * nx; a12 += nx * ny; a22 += ny * ny; b1 += nx * c; b2 += ny * c
        }
        let det = a11 * a22 - a12 * a12
        guard abs(det) > 1e-6 else { return nil }     // direzioni parallele
        let p = P(x: (b1 * a22 - b2 * a12) / det, y: (a11 * b2 - a12 * b1) / det)
        var err = 0.0, avanti = true
        for (s, th) in st {
            let t = th * .pi / 180
            err += abs(cos(t) * (p.x - s.x) - sin(t) * (p.y - s.y))
            if sin(t) * (p.x - s.x) + cos(t) * (p.y - s.y) < 0 { avanti = false }  // punto alle spalle della stazione
        }
        return (p, err / Double(st.count), avanti)
    }

    /// Posizione da distanze note: 2 punti = 2 soluzioni, 3 o più = minimi quadrati.
    static func distanze(_ pts: [(P, Double)]) -> [(P, Double)] {
        if pts.count == 2 {
            let (a, ra) = pts[0], (b, rb) = pts[1]
            let d = dist(a, b)
            guard d > 0, d <= ra + rb + 1e-6, d >= abs(ra - rb) - 1e-6 else { return [] }
            let l = (ra * ra - rb * rb + d * d) / (2 * d)
            let h = sqrt(max(0, ra * ra - l * l))
            let mx = a.x + l * (b.x - a.x) / d, my = a.y + l * (b.y - a.y) / d
            let s1 = P(x: mx + h * (b.y - a.y) / d, y: my - h * (b.x - a.x) / d)
            let s2 = P(x: mx - h * (b.y - a.y) / d, y: my + h * (b.x - a.x) / d)
            return h < 0.5 ? [(s1, 0)] : [(s1, 0), (s2, 0)]
        }
        var p = P(x: pts.map(\.0.x).reduce(0, +) / Double(pts.count), y: pts.map(\.0.y).reduce(0, +) / Double(pts.count))
        for _ in 0..<200 {
            var j00 = 0.0, j01 = 0.0, j11 = 0.0, g0 = 0.0, g1 = 0.0
            for (q, r) in pts {
                let d = max(dist(q, p), 1e-9), res = d - r
                let jx = (p.x - q.x) / d, jy = (p.y - q.y) / d
                j00 += jx * jx; j01 += jx * jy; j11 += jy * jy; g0 += jx * res; g1 += jy * res
            }
            let det = j00 * j11 - j01 * j01
            guard abs(det) > 1e-12 else { break }
            let dx = -(j11 * g0 - j01 * g1) / det, dy = -(j00 * g1 - j01 * g0) / det
            p.x += dx; p.y += dy
            if abs(dx) + abs(dy) < 1e-6 { break }
        }
        let res = sqrt(pts.reduce(0) { $0 + pow(dist($1.0, p) - $1.1, 2) } / Double(pts.count))
        return [(p, res)]
    }

    /// Punto a distanza e angolo da A. Con B: angolo misurato da A→B in senso orario; senza B: azimut.
    static func polare(_ a: P, _ b: P?, _ angolo: Double, _ d: Double) -> P {
        let base = b.map { az(a, $0) } ?? 0
        let t = (base + angolo) * .pi / 180
        return P(x: a.x + d * sin(t), y: a.y + d * cos(t))
    }

    /// Snellius–Pothenot: P vede A-B con angolo alfa e B-C con angolo beta.
    static func snellius(_ a: P, _ b: P, _ c: P, _ alfa: Double, _ beta: Double) -> P? {
        func ang(_ p: P, _ u: P, _ v: P) -> Double {
            let ux = u.x - p.x, uy = u.y - p.y, vx = v.x - p.x, vy = v.y - p.y
            let cosv = (ux * vx + uy * vy) / max(hypot(ux, uy) * hypot(vx, vy), 1e-9)
            return acos(max(-1, min(1, cosv)))
        }
        let al = alfa * .pi / 180, be = beta * .pi / 180
        func f(_ p: P) -> (Double, Double) { (ang(p, a, b) - al, ang(p, b, c) - be) }
        // più partenze: la soluzione dipende da dove si parte
        var migliore: (P, Double)?
        let centro = P(x: (a.x + b.x + c.x) / 3, y: (a.y + b.y + c.y) / 3)
        let scala = max(dist(a, b), dist(b, c), 50)
        for k in 0..<8 {
            let t = Double(k) * .pi / 4
            var p = P(x: centro.x + scala * sin(t), y: centro.y + scala * cos(t))
            for _ in 0..<100 {
                let (r1, r2) = f(p), e = 0.05
                let (r1x, r2x) = f(P(x: p.x + e, y: p.y)), (r1y, r2y) = f(P(x: p.x, y: p.y + e))
                let j11 = (r1x - r1) / e, j12 = (r1y - r1) / e, j21 = (r2x - r2) / e, j22 = (r2y - r2) / e
                let det = j11 * j22 - j12 * j21
                guard abs(det) > 1e-15 else { break }
                let dx = -(j22 * r1 - j12 * r2) / det, dy = -(-j21 * r1 + j11 * r2) / det
                p.x += max(-scala, min(scala, dx)); p.y += max(-scala, min(scala, dy))
                if abs(dx) + abs(dy) < 1e-4 { break }
            }
            let (r1, r2) = f(p), e = abs(r1) + abs(r2)
            if e < 1e-4, p.x.isFinite, migliore == nil || e < migliore!.1 { migliore = (p, e) }
        }
        return migliore?.0
    }
}

// MARK: - Campo punto (UTM / lat,lon / GPS / OBJ)

struct PuntoField: View {
    let titolo: String
    @Binding var testo: String
    @EnvironmentObject var location: LocationService

    var coord: CLLocationCoordinate2D? { PuntoField.parse(testo) }

    static func parse(_ t: String) -> CLLocationCoordinate2D? {
        if let u = UTM.parse(t) {
            let (la, lo) = UTM.toLatLon(u)
            return .init(latitude: la, longitude: lo)
        }
        // "290013 4874586" senza zona: in gara siamo in 33T
        let n = t.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted).filter { !$0.isEmpty }
        if n.count == 2, let e = Double(n[0]), let no = Double(n[1]), (100_000...900_000).contains(e), no > 1_000_000 {
            let (la, lo) = UTM.toLatLon(UTMCoord(zone: 33, north: true, easting: e, northing: no, band: "T"))
            return .init(latitude: la, longitude: lo)
        }
        // "43.99, 12.38"
        let d = t.replacingOccurrences(of: ",", with: " ").components(separatedBy: CharacterSet(charactersIn: "-0123456789.").inverted)
            .filter { !$0.isEmpty }.compactMap(Double.init)
        if d.count == 2, abs(d[0]) <= 90, abs(d[1]) <= 180 { return .init(latitude: d[0], longitude: d[1]) }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(titolo).font(.caption.weight(.bold)).foregroundStyle(Theme.gold).frame(width: 22, alignment: .leading)
                TextField("33T 290013 4874586  o  43.99, 12.38", text: $testo)
                    .font(Theme.mono(13)).textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled().textInputAutocapitalization(.characters)
                Button {
                    if let c = location.location?.coordinate { testo = UTM.fromLatLon(c.latitude, c.longitude).text }
                } label: { Image(systemName: "location.fill") }
                Menu {
                    ForEach(Gara.points) { p in
                        Button(p.id) { testo = UTM.fromLatLon(p.lat, p.lon).text }
                    }
                } label: { Image(systemName: "mappin.and.ellipse") }
                Button { if let s = UIPasteboard.general.string { testo = s } } label: { Image(systemName: "doc.on.clipboard") }
            }
            .buttonStyle(.bordered).controlSize(.small)
            if !testo.isEmpty, coord == nil {
                Text("coordinate non riconosciute").font(.caption2).foregroundStyle(Theme.red)
            }
        }
    }
}

/// Campo numerico compatto.
struct NumField: View {
    let titolo: String
    @Binding var valore: String
    var unita = ""
    var body: some View {
        HStack(spacing: 6) {
            Text(titolo).font(.caption).foregroundStyle(Theme.dim)
            TextField("0", text: $valore).keyboardType(.decimalPad).font(Theme.mono(15)).textFieldStyle(.roundedBorder)
            if !unita.isEmpty { Text(unita).font(.caption).foregroundStyle(Theme.dim) }
        }
    }
}

func num(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) }

// MARK: - Vista

/// Azimut acquisiti dal mirino: posizione del telefono + direzione vera. Li usa la triangolazione.
final class Rilevamenti: ObservableObject {
    struct R: Identifiable, Hashable {
        let id = UUID()
        let lat: Double, lon: Double, az: Double, quando: Date
        var utm: String { UTM.fromLatLon(lat, lon).text }
    }
    @Published var lista: [R] = []
    @Published var angoli: [Double] = []   // angoli misurati tra due direzioni (per Snellius)
    func add(_ c: CLLocationCoordinate2D, _ az: Double) {
        lista.insert(R(lat: c.latitude, lon: c.longitude, az: az, quando: Date()), at: 0)
        if lista.count > 6 { lista.removeLast() }
    }
}

struct TriangView: View {
    enum Metodo: String, CaseIterable, Identifiable {
        case azimut = "Azimut", distanze = "Distanze", polare = "Polare", snellius = "Snellius"
        var id: String { rawValue }
        var spiegazione: String {
            switch self {
            case .azimut: return "Da 2–3 punti noti misuri la direzione verso il bersaglio: dove le direzioni si incrociano c'è il bersaglio."
            case .distanze: return "Conosci la distanza da 2–3 punti noti: con 2 punti ci sono due soluzioni, con 3 una sola."
            case .polare: return "Il bersaglio è a una certa distanza e direzione da un punto noto (azimut, oppure angolo da un secondo punto B)."
            case .snellius: return "Sei in un punto sconosciuto e vedi 3 punti noti A, B, C: misura l'angolo A–B (α) e B–C (β) e trovi dove sei."
            }
        }
    }

    @EnvironmentObject var location: LocationService
    @EnvironmentObject var log: FieldLog
    @EnvironmentObject var ril: Rilevamenti
    @AppStorage("tri.metodo") private var metodoRaw = Metodo.azimut.rawValue
    @AppStorage("tri.declinazione") private var declinazione = "4.6"
    @AppStorage("tri.magnetico") private var magnetico = true
    @State private var p = ["", "", ""]
    @State private var v = ["", "", ""]      // azimut o distanze
    @State private var angolo = ""
    @State private var distanza = ""
    @State private var alfa = ""
    @State private var beta = ""
    @State private var conB = false

    var metodo: Metodo { Metodo(rawValue: metodoRaw) ?? .azimut }

    var body: some View {
        VStack(spacing: 12) {
            Picker("Metodo", selection: $metodoRaw) {
                ForEach(Metodo.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            Text(metodo.spiegazione).font(.caption).foregroundStyle(Theme.dim).frame(maxWidth: .infinity, alignment: .leading)

            Card(title: "Dati") { campi }

            if let r = risultato {
                RisultatoCard(r: r)
            } else {
                Text("Completa i campi per vedere il risultato").font(.footnote).foregroundStyle(Theme.dim)
            }
        }
    }

    @ViewBuilder var campi: some View {
        switch metodo {
        case .azimut:
            if !ril.lista.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dal mirino (tocca per usare):").font(.caption2).foregroundStyle(Theme.dim)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(ril.lista) { r in
                                Button(String(format: "%.0f° · %@", r.az, r.quando.formatted(date: .omitted, time: .shortened))) {
                                    let i = p.firstIndex(where: { $0.isEmpty }) ?? 2
                                    p[i] = r.utm; v[i] = String(format: "%.1f", r.az)
                                    if i < 3 { magneticoPerStazione[i] = false }
                                }
                                .font(.caption2).buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            ForEach(0..<3, id: \.self) { i in
                VStack(alignment: .leading, spacing: 4) {
                    PuntoField(titolo: "S\(i + 1)", testo: $p[i])
                    HStack {
                        NumField(titolo: "azimut", valore: $v[i], unita: "°")
                        if i < 3 {
                            Toggle("bussola", isOn: Binding(get: { magneticoPerStazione[i] }, set: { magneticoPerStazione[i] = $0 }))
                                .toggleStyle(.button).font(.caption2)
                        }
                    }
                }
                if i < 2 { Divider() }
            }
            NumField(titolo: "declinazione (E +)", valore: $declinazione, unita: "°")
            Text("\"bussola\" = azimut letto su una bussola (magnetico): si aggiunge la declinazione. Gli azimut del mirino sono già veri.")
                .font(.caption2).foregroundStyle(Theme.dim)
        case .distanze:
            ForEach(0..<3, id: \.self) { i in
                PuntoField(titolo: "P\(i + 1)", testo: $p[i])
                NumField(titolo: "distanza", valore: $v[i], unita: "m")
                if i < 2 { Divider() }
            }
        case .polare:
            PuntoField(titolo: "A", testo: $p[0])
            Toggle("Angolo misurato da un punto B (invece dell'azimut)", isOn: $conB).font(.caption)
            if conB { PuntoField(titolo: "B", testo: $p[1]) }
            NumField(titolo: conB ? "angolo da A→B (orario)" : "azimut", valore: $angolo, unita: "°")
            NumField(titolo: "distanza", valore: $distanza, unita: "m")
        case .snellius:
            PuntoField(titolo: "A", testo: $p[0])
            PuntoField(titolo: "B", testo: $p[1])
            PuntoField(titolo: "C", testo: $p[2])
            NumField(titolo: "α (A-B)", valore: $alfa, unita: "°")
            NumField(titolo: "β (B-C)", valore: $beta, unita: "°")
            if !ril.angoli.isEmpty {
                HStack {
                    Text("Dal mirino:").font(.caption2).foregroundStyle(Theme.dim)
                    ForEach(ril.angoli.prefix(4), id: \.self) { a in
                        Button(String(format: "%.1f°", a)) { if alfa.isEmpty { alfa = String(format: "%.1f", a) } else { beta = String(format: "%.1f", a) } }
                            .font(.caption2).buttonStyle(.bordered)
                    }
                }
            }
        }
        Button(role: .destructive) { p = ["", "", ""]; v = ["", "", ""]; angolo = ""; distanza = ""; alfa = ""; beta = "" } label: {
            Label("Svuota", systemImage: "trash")
        }
        .font(.footnote).buttonStyle(.bordered)
    }

    @State private var magneticoPerStazione = [true, true, true]

    struct Risultato {
        var soluzioni: [CLLocationCoordinate2D]
        var note: [String]
        var basi: [CLLocationCoordinate2D]
        var raggi: [(CLLocationCoordinate2D, Double)] = []   // per il disegno: direzioni dalle stazioni
    }

    var risultato: Risultato? {
        let cs = p.map { PuntoField.parse($0) }
        switch metodo {
        case .azimut:
            let decl = num(declinazione) ?? 0
            var st: [(CLLocationCoordinate2D, Double)] = []
            for i in 0..<3 { if let c = cs[i], let a = num(v[i]) { st.append((c, a + (magneticoPerStazione[i] ? decl : 0))) } }
            guard st.count >= 2 else { return nil }
            let o = st[0].0
            guard let ris = Triang.azimut(st.map { (Triang.xy($0.0, o), $0.1) }) else {
                return Risultato(soluzioni: [], note: ["Direzioni parallele: nessun incrocio"], basi: st.map(\.0))
            }
            let (pt, err, avanti) = ris
            var note = st.count == 3 ? [String(format: "Triangolo d'errore: %.0f m in media", err)] : []
            if !avanti { note.append("⚠︎ L'incrocio è alle spalle di una stazione: controlla gli azimut") }
            for (i, s) in st.enumerated() {
                note.append(String(format: "Da S%d: %.0f m", i + 1, Triang.dist(Triang.xy(s.0, o), pt)))
            }
            return Risultato(soluzioni: [Triang.geo(pt, o)], note: note, basi: st.map(\.0), raggi: st)
        case .distanze:
            var pts: [(CLLocationCoordinate2D, Double)] = []
            for i in 0..<3 { if let c = cs[i], let d = num(v[i]), d > 0 { pts.append((c, d)) } }
            guard pts.count >= 2 else { return nil }
            let o = pts[0].0
            let sol = Triang.distanze(pts.map { (Triang.xy($0.0, o), $0.1) })
            if sol.isEmpty { return Risultato(soluzioni: [], note: ["I cerchi non si incontrano: distanze incompatibili"], basi: pts.map(\.0)) }
            var note = sol.count == 2 ? ["Due soluzioni possibili (aggiungi un terzo punto per sceglierne una)"] : []
            if pts.count >= 3 { note.append(String(format: "Scarto medio sulle distanze: %.1f m", sol[0].1)) }
            return Risultato(soluzioni: sol.map { Triang.geo($0.0, o) }, note: note, basi: pts.map(\.0))
        case .polare:
            guard let a = cs[0], let ang = num(angolo), let d = num(distanza) else { return nil }
            let b = conB ? cs[1] : nil
            if conB && b == nil { return nil }
            let pt = Triang.polare(Triang.xy(a, a), b.map { Triang.xy($0, a) }, ang, d)
            let azv = Triang.az(Triang.P(x: 0, y: 0), pt)
            return Risultato(soluzioni: [Triang.geo(pt, a)], note: [String(format: "Azimut da A: %.1f°", azv)],
                             basi: [a] + (b.map { [$0] } ?? []), raggi: [(a, azv)])
        case .snellius:
            guard let a = cs[0], let b = cs[1], let c = cs[2], let al = num(alfa), let be = num(beta) else { return nil }
            guard let pt = Triang.snellius(Triang.xy(a, a), Triang.xy(b, a), Triang.xy(c, a), al, be) else {
                return Risultato(soluzioni: [], note: ["Nessuna soluzione (sei sul cerchio per A, B, C o angoli impossibili)"], basi: [a, b, c])
            }
            let pp = Triang.geo(pt, a)
            let note = zip(["A", "B", "C"], [a, b, c]).map { n, q in String(format: "Distanza da %@: %.0f m", n, Geo.distance(pp, q)) }
            return Risultato(soluzioni: [pp], note: note, basi: [a, b, c])
        }
    }
}

struct RisultatoCard: View {
    let r: TriangView.Risultato
    @EnvironmentObject var location: LocationService
    @EnvironmentObject var log: FieldLog

    var body: some View {
        Card(title: r.soluzioni.count > 1 ? "Risultato (2 soluzioni)" : "Risultato") {
            if !r.soluzioni.isEmpty || !r.basi.isEmpty { Schizzo(r: r, io: location.location?.coordinate).frame(height: 190) }
            ForEach(Array(r.soluzioni.enumerated()), id: \.offset) { i, s in
                VStack(alignment: .leading, spacing: 4) {
                    if r.soluzioni.count > 1 { Text("Soluzione \(i + 1)").font(.caption.weight(.bold)) }
                    Text(Geo.describe(s)).font(Theme.mono(13)).textSelection(.enabled)
                    if let me = location.location?.coordinate {
                        Text(String(format: "Da te: %@ a %.0f°", Geo.formatDistance(Geo.distance(me, s)), Geo.bearing(me, s)))
                            .font(.footnote).foregroundStyle(Theme.cyan)
                    }
                    HStack {
                        Button { copyToClipboard(UTM.fromLatLon(s.latitude, s.longitude).text) } label: { Label("UTM", systemImage: "doc.on.doc") }
                        Button { copyToClipboard(String(format: "%.6f, %.6f", s.latitude, s.longitude)) } label: { Label("Lat/Lon", systemImage: "doc.on.doc") }
                        Button {
                            log.add(.punto, "Triangolazione: \(UTM.fromLatLon(s.latitude, s.longitude).text)",
                                    at: CLLocation(latitude: s.latitude, longitude: s.longitude))
                        } label: { Label("Registra", systemImage: "tray.and.arrow.down") }
                    }
                    .font(.caption).buttonStyle(.bordered)
                }
            }
            ForEach(r.note, id: \.self) { Text($0).font(.footnote).foregroundStyle($0.hasPrefix("⚠︎") ? Theme.red : Theme.dim) }
        }
    }
}

/// Disegno schematico: punti noti (verdi), direzioni, soluzioni (oro), io (blu). Nord in alto.
struct Schizzo: View {
    let r: TriangView.Risultato
    let io: CLLocationCoordinate2D?

    var body: some View {
        Canvas { ctx, size in
            let tutti = r.basi + r.soluzioni
            guard let o = tutti.first else { return }
            var pts = tutti.map { Triang.xy($0, o) }
            if let io { pts.append(Triang.xy(io, o)) }
            let minX = pts.map(\.x).min()!, maxX = pts.map(\.x).max()!, minY = pts.map(\.y).min()!, maxY = pts.map(\.y).max()!
            let span = max(maxX - minX, maxY - minY, 20) * 1.25
            let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
            let k = min(size.width, size.height) / span
            func s(_ c: CLLocationCoordinate2D) -> CGPoint {
                let p = Triang.xy(c, o)
                return CGPoint(x: size.width / 2 + (p.x - cx) * k, y: size.height / 2 - (p.y - cy) * k)
            }
            // direzioni
            for (c, az) in r.raggi {
                let a = s(c), t = az * .pi / 180, l = span * k
                var path = Path(); path.move(to: a); path.addLine(to: CGPoint(x: a.x + sin(t) * l, y: a.y - cos(t) * l))
                ctx.stroke(path, with: .color(Theme.green.opacity(0.6)), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
            for (i, b) in r.basi.enumerated() {
                let q = s(b)
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - 5, y: q.y - 5, width: 10, height: 10)), with: .color(Theme.green))
                ctx.draw(Text("\(i + 1)").font(.caption2).foregroundColor(Theme.green), at: CGPoint(x: q.x + 10, y: q.y - 8))
            }
            for sol in r.soluzioni {
                let q = s(sol)
                ctx.stroke(Path(ellipseIn: CGRect(x: q.x - 8, y: q.y - 8, width: 16, height: 16)), with: .color(Theme.gold), lineWidth: 2.5)
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - 2, y: q.y - 2, width: 4, height: 4)), with: .color(Theme.gold))
            }
            if let io {
                let q = s(io)
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - 5, y: q.y - 5, width: 10, height: 10)), with: .color(.blue))
            }
            ctx.draw(Text("N ↑").font(.caption2.bold()).foregroundColor(.white), at: CGPoint(x: size.width - 18, y: 10))
            // scala
            let metri = pow(10, floor(log10(span / 3)))
            var bar = Path(); bar.move(to: CGPoint(x: 8, y: size.height - 8)); bar.addLine(to: CGPoint(x: 8 + metri * k, y: size.height - 8))
            ctx.stroke(bar, with: .color(.white), lineWidth: 2)
            ctx.draw(Text(Geo.formatDistance(metri)).font(.caption2).foregroundColor(.white), at: CGPoint(x: 8 + metri * k / 2, y: size.height - 18))
        }
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}
