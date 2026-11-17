import SwiftUI
import MapKit
import CoreLocation

// MARK: - Punti personali + punto attivo

struct PuntoMio: Codable, Identifiable, Hashable {
    var id = UUID()
    var nome: String
    var lat: Double
    var lon: Double
    var tipo: String = "wp"          // wp, raduno, pericolo, altro
    var nota: String = ""

    var punto: GaraPoint { GaraPoint(id: nome, lat: lat, lon: lon, kind: .mio, note: nota) }

    static let tipi: [(String, String, Color)] = [
        ("wp", "WP", Color(red: 0.70, green: 0.55, blue: 0.95)),
        ("raduno", "RADUNO", Theme.cyan),
        ("pericolo", "PERICOLO", Theme.red),
        ("altro", "ALTRO", Color(red: 1.0, green: 0.48, blue: 0.85)),
    ]
}

/// Tiene i punti aggiunti a mano (Documents/Raccolta/punti_miei.json, visibile anche dall'app File)
/// e il punto verso cui si sta navigando (resta anche se si chiude l'app).
final class NavStore: ObservableObject {
    static let shared = NavStore()

    @Published private(set) var miei: [PuntoMio] = []
    @Published var target: GaraPoint? {
        didSet { UserDefaults.standard.set(target?.id, forKey: "nav.target") }
    }
    /// Quote dei punti (m s.l.m.), scaricate una volta sola da Open-Meteo.
    @Published var quote: [String: Double] = [:]

    private var file: URL { FieldLog.dir.appendingPathComponent("punti_miei.json") }

    var tutti: [GaraPoint] { Gara.points + miei.map(\.punto) }

    init() {
        if let d = try? Data(contentsOf: file), let p = try? JSONDecoder().decode([PuntoMio].self, from: d) { miei = p }
        if let q = UserDefaults.standard.dictionary(forKey: "nav.quote") as? [String: Double] { quote = q }
        if let t = UserDefaults.standard.string(forKey: "nav.target") { target = tutti.first { $0.id == t } }
    }

    func mio(_ p: GaraPoint) -> PuntoMio? { p.kind == .mio ? miei.first { $0.nome == p.id } : nil }

    /// Salva (nuovo o modificato). Il nome resta unico: se esiste già aggiunge un numero.
    @discardableResult
    func salva(_ p: PuntoMio) -> PuntoMio {
        var p = p
        p.nome = p.nome.trimmingCharacters(in: .whitespaces).uppercased()
        if p.nome.isEmpty { p.nome = "PUNTO \(miei.count + 1)" }
        let base = p.nome
        var n = 2
        while Gara.points.contains(where: { $0.id == p.nome }) || miei.contains(where: { $0.nome == p.nome && $0.id != p.id }) {
            p.nome = "\(base) \(n)"; n += 1
        }
        let vecchio = miei.first { $0.id == p.id }
        if let i = miei.firstIndex(where: { $0.id == p.id }) { miei[i] = p } else { miei.append(p) }
        if let v = vecchio, target?.id == v.nome { target = p.punto }
        quote[p.nome] = nil
        scrivi()
        return p
    }

    func elimina(_ p: PuntoMio) {
        miei.removeAll { $0.id == p.id }
        if target?.id == p.nome { target = nil }
        scrivi()
    }

    private func scrivi() {
        if let d = try? JSONEncoder().encode(miei) { try? d.write(to: file, options: .atomic) }
    }

    func caricaQuota(_ p: GaraPoint) {
        guard quote[p.id] == nil else { return }
        let url = URL(string: String(format: "https://api.open-meteo.com/v1/elevation?latitude=%.6f&longitude=%.6f", p.lat, p.lon))!
        URLSession.shared.dataTask(with: url) { d, _, _ in
            guard let d, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let e = (j["elevation"] as? [Double])?.first else { return }
            DispatchQueue.main.async {
                self.quote[p.id] = e
                UserDefaults.standard.set(self.quote, forKey: "nav.quote")
            }
        }.resume()
    }
}

// MARK: - Coordinate: UTM, MGRS, lat/lon

enum Coordinate {
    /// Riconosce UTM ("33T 290251 4874842"), MGRS ("33T TJ 90251 74842") e lat/lon ("43.99, 12.38").
    static func parse(_ t: String) -> CLLocationCoordinate2D? {
        if let c = mgrs(t) { return c }
        return PuntoField.parse(t)
    }

    static func mgrs(_ text: String) -> CLLocationCoordinate2D? {
        let s = text.uppercased().replacingOccurrences(of: " ", with: "")
        guard let re = try? NSRegularExpression(pattern: #"^(\d{1,2})([C-HJ-NP-X])([A-HJ-NP-Z])([A-HJ-NP-V])(\d{2,10})$"#),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        func g(_ i: Int) -> String { Range(m.range(at: i), in: s).map { String(s[$0]) } ?? "" }
        guard let zone = Int(g(1)), (1...60).contains(zone) else { return nil }
        let band = Character(g(2)), col = Character(g(3)), row = Character(g(4)), digits = g(5)
        guard digits.count % 2 == 0 else { return nil }
        let half = digits.count / 2
        let mult = pow(10.0, Double(5 - half))
        guard let e5 = Double(digits.prefix(half)), let n5 = Double(digits.suffix(half)) else { return nil }
        let cols = [Array("ABCDEFGH"), Array("JKLMNPQR"), Array("STUVWXYZ")][(zone - 1) % 3]
        let rows = [Array("ABCDEFGHJKLMNPQRSTUV"), Array("FGHJKLMNPQRSTUVABCDE")][(zone - 1) % 2]
        guard let ci = cols.firstIndex(of: col), let ri = rows.firstIndex(of: row) else { return nil }
        let easting = Double(ci + 1) * 100_000 + e5 * mult
        // il nord si ripete ogni 2000 km: si sceglie quello più vicino al centro della fascia
        let bands = Array("CDEFGHJKLMNPQRSTUVWX")
        guard let bi = bands.firstIndex(of: band) else { return nil }
        let latBand = -80 + Double(bi) * 8 + 4
        let approx = UTM.fromLatLon(latBand, Double((zone - 1) * 6 - 180 + 3)).northing
        var best = 0.0, bestD = Double.greatestFiniteMagnitude
        for k in 0...5 {
            let n = Double(k) * 2_000_000 + Double(ri) * 100_000 + n5 * mult
            if abs(n - approx) < bestD { bestD = abs(n - approx); best = n }
        }
        let (la, lo) = UTM.toLatLon(UTMCoord(zone: zone, north: band >= "N", easting: easting, northing: best, band: band))
        return .init(latitude: la, longitude: lo)
    }

    static func utmText(_ c: CLLocationCoordinate2D) -> String { UTM.fromLatLon(c.latitude, c.longitude).text }

    static func inside(_ c: CLLocationCoordinate2D, _ poly: [CLLocationCoordinate2D]) -> Bool {
        var dentro = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.latitude > c.latitude) != (b.latitude > c.latitude),
               c.longitude < (b.longitude - a.longitude) * (c.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude {
                dentro.toggle()
            }
            j = i
        }
        return dentro
    }
}

func angolo360(_ a: Double) -> Double { (a.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) }
func gradi3(_ a: Double) -> String { String(format: "%03.0f°", angolo360(a.rounded()).truncatingRemainder(dividingBy: 360)) }

// MARK: - Cruscotto di navigazione

struct NavPanel: View {
    let target: GaraPoint
    let landscape: Bool
    var onEdit: () -> Void
    var onChange: () -> Void
    @EnvironmentObject var location: LocationService
    @ObservedObject var nav = NavStore.shared

    var body: some View {
        let me = location.location
        let c = me?.coordinate
        let d = c.map { Geo.distance($0, target.coordinate) }
        let bTrue = c.map { Geo.bearing($0, target.coordinate) } ?? 0
        let decl = location.declinazione ?? 4.6
        let heading = location.heading ?? (me.flatMap { $0.course >= 0 ? $0.course : nil }) ?? bTrue
        let speed = max(0, me?.speed ?? 0)
        let muove = speed > 0.3
        let sec = (d != nil && muove) ? d! / speed : nil
        let arrivato = (d ?? 999) < 10

        VStack(alignment: .leading, spacing: landscape ? 7 : 9) {
            header
            if landscape {
                HStack(alignment: .center, spacing: 12) {
                    NavCompass(heading: heading, bearing: bTrue, decl: decl, attivo: c != nil)
                        .frame(width: 156, height: 156)
                    VStack(alignment: .leading, spacing: 8) {
                        metric("DISTANZA", d.map(distanzaGrande) ?? Text("—"), xl: true)
                        HStack(alignment: .top, spacing: 14) {
                            metric("AZ MAGNETICO", Text(gradi3(bTrue - decl)) + Text(" " + Mission.cardinale(bTrue)).font(Theme.mono(10, .bold)).foregroundColor(Theme.dim), lg: true)
                            metric("CONTRO-AZ", Text(gradi3(bTrue - decl + 180)) + Text(" M").font(Theme.mono(10, .bold)).foregroundColor(Theme.dim))
                        }
                        HStack(alignment: .top, spacing: 14) {
                            metric("TEMPO · ARRIVO", Text(tempo(sec) + " · " + arrivo(sec)))
                            metric("AZ VERO", Text(gradi3(bTrue)))
                        }
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 6) {
                    VStack(alignment: .leading, spacing: 9) {
                        metric("DISTANZA", d.map(distanzaGrande) ?? Text("—"), xl: true)
                        metric("TEMPO", Text(tempo(sec)))
                        metric("ARRIVO", Text(arrivo(sec)))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    NavCompass(heading: heading, bearing: bTrue, decl: decl, attivo: c != nil)
                        .frame(width: 168, height: 168)
                    VStack(alignment: .trailing, spacing: 9) {
                        metric("AZ MAGNETICO", Text(gradi3(bTrue - decl)) + Text(" " + Mission.cardinale(bTrue)).font(Theme.mono(10, .bold)).foregroundColor(Theme.dim), lg: true, right: true)
                        metric("AZ VERO", Text(gradi3(bTrue)), right: true)
                        metric("CONTRO-AZ", Text(gradi3(bTrue - decl + 180)) + Text(" M").font(Theme.mono(10, .bold)).foregroundColor(Theme.dim), right: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            ScartoBar(errore: c == nil ? nil : ((heading - bTrue + 540).truncatingRemainder(dividingBy: 360) - 180))
            HStack(spacing: 6) {
                tile("QUOTA", me.flatMap { $0.verticalAccuracy > 0 ? String(format: "%.0f m", $0.altitude) : nil } ?? "—")
                tile("DISLIVELLO", dislivello(me), amber: abs(dislivelloValore(me) ?? 0) > 15)
                tile("VELOCITÀ", muove ? String(format: "%.1f km/h", speed * 3.6).replacingOccurrences(of: ".", with: ",") : "ferma")
                tile("GPS ±", me.map { String(format: "%.0f m", $0.horizontalAccuracy) } ?? "—", ok: (me?.horizontalAccuracy ?? 99) <= 10)
            }
            HStack {
                Text("PUNTO").foregroundStyle(Theme.dim)
                Spacer()
                Text(Coordinate.utmText(target.coordinate)).foregroundStyle(.white).textSelection(.enabled)
            }
            .font(Theme.mono(10.5, .bold))
            .padding(.top, 5)
            .overlay(alignment: .top) { Rectangle().fill(Theme.stroke).frame(height: 1) }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, landscape ? 10 : 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RadialGradient(colors: [Color(red: 0.08, green: 0.10, blue: 0.05), .black], center: .top, startRadius: 0, endRadius: 420)
        )
        .overlay {
            if arrivato {
                VStack(spacing: 6) {
                    Text("● ARRIVATO").font(Theme.mono(22, .heavy)).foregroundStyle(Theme.oliveBright)
                    Text("entro 10 m da \(target.id)").font(Theme.mono(11, .semibold)).foregroundStyle(Theme.dim)
                    Button("Ferma navigazione") { nav.target = nil }.buttonStyle(.borderedProminent).tint(Theme.olive).foregroundStyle(.black)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.82))
            }
        }
        .onAppear { nav.caricaQuota(target) }
        .onChange(of: target) { nav.caricaQuota($0) }
    }

    var header: some View {
        HStack(spacing: 8) {
            Circle().fill(target.color).frame(width: 11, height: 11)
                .overlay(Circle().stroke(target.color.opacity(0.3), lineWidth: 6))
            Button(action: onChange) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("NAVIGAZIONE VERSO ▾").font(Theme.mono(9, .bold)).tracking(1.4).foregroundStyle(Theme.dim)
                    Text(target.id).font(Theme.mono(15, .heavy)).foregroundStyle(.white).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button(action: onEdit) { chip("✎ MODIFICA", Theme.oliveBright) }.buttonStyle(.plain)
            Button { haptic(); withAnimation(.spring()) { nav.target = nil } } label: { chip("■ STOP", Theme.red) }.buttonStyle(.plain)
        }
    }

    func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(Theme.mono(10, .heavy)).foregroundStyle(c)
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(c.opacity(0.3)))
    }

    func distanzaGrande(_ d: Double) -> Text {
        let (v, u) = d < 1000 ? (String(format: "%.0f", d), "m") : (String(format: "%.2f", d / 1000).replacingOccurrences(of: ".", with: ","), "km")
        return Text(v) + Text(u).font(Theme.mono(14, .bold)).foregroundColor(Theme.olive)
    }

    func metric(_ l: String, _ v: Text, xl: Bool = false, lg: Bool = false, right: Bool = false) -> some View {
        VStack(alignment: right ? .trailing : .leading, spacing: 2) {
            Text(l).font(Theme.mono(8.5, .bold)).tracking(1.3).foregroundStyle(Theme.dim).lineLimit(1)
            v.font(Theme.mono(xl ? 36 : (lg ? 25 : 17), .heavy))
                .foregroundStyle(xl || lg ? Theme.oliveBright : .white)
                .lineLimit(1).minimumScaleFactor(0.6)
                .monospacedDigit()
        }
    }

    func tile(_ l: String, _ v: String, ok: Bool = false, amber: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(l).font(Theme.mono(8, .bold)).tracking(1.1).foregroundStyle(Theme.dim).lineLimit(1)
            Text(v).font(Theme.mono(13, .heavy)).foregroundStyle(amber ? Theme.amber : (ok ? Theme.oliveBright : .white))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Theme.surface2, Theme.surface], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.stroke))
    }

    func tempo(_ s: Double?) -> String {
        guard let s, s.isFinite else { return "—" }
        return s >= 3600 ? String(format: "%d h %02d", Int(s) / 3600, Int(s) % 3600 / 60) : String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }

    func arrivo(_ s: Double?) -> String {
        guard let s, s.isFinite else { return "—" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: Date().addingTimeInterval(s))
    }

    func dislivelloValore(_ me: CLLocation?) -> Double? {
        guard let me, me.verticalAccuracy > 0, let q = nav.quote[target.id] else { return nil }
        return q - me.altitude
    }

    func dislivello(_ me: CLLocation?) -> String {
        guard let v = dislivelloValore(me) else { return "—" }
        return String(format: "%@%.0f m", v > 0 ? "+" : "", v)
    }
}

/// Barra dello scarto tra dove punta il telefono e il punto.
struct ScartoBar: View {
    let errore: Double?   // positivo = sei girato a destra del punto

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let e = errore ?? 0
            let frac = min(1, abs(e) / 30) * 0.5
            let ok = abs(e) <= 5
            let col = ok ? Theme.olive : (abs(e) <= 15 ? Theme.amber : Theme.red)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.04, green: 0.05, blue: 0.03))
                HStack(spacing: 0) {
                    ForEach(0..<10, id: \.self) { _ in
                        Rectangle().fill(.clear).overlay(alignment: .trailing) { Rectangle().fill(Theme.stroke).frame(width: 1) }
                    }
                }
                Rectangle().fill(Theme.olive.opacity(0.5)).frame(width: 2).offset(x: w / 2 - 1)
                if errore != nil {
                    RoundedRectangle(cornerRadius: 4).fill(col)
                        .frame(width: max(3, w * frac), height: 16)
                        .offset(x: e < 0 ? w / 2 - w * frac : w / 2)
                }
                Text(testo).font(Theme.mono(10, .heavy)).tracking(0.8).foregroundStyle(.white)
                    .shadow(color: .black, radius: 2)
                    .frame(maxWidth: .infinity)
            }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.stroke))
            .animation(.easeOut(duration: 0.25), value: errore)
        }
        .frame(height: 24)
    }

    var testo: String {
        guard let e = errore else { return "IN ATTESA DEL GPS" }
        if abs(e) <= 5 { return "IN ROTTA · SCARTO \(Int(abs(e).rounded()))°" }
        return e > 0 ? "◀ GIRA A SINISTRA \(Int(e.rounded()))°" : "GIRA A DESTRA \(Int((-e).rounded()))° ▶"
    }
}

/// Bussola: il quadrante gira col telefono, triangolo blu = dove punti, freccia verde = il punto.
struct NavCompass: View {
    let heading: Double      // vero
    let bearing: Double      // vero
    let decl: Double
    let attivo: Bool

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height), r = s / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            func pt(_ deg: Double, _ rad: Double) -> CGPoint {
                let a = (deg - 90) * .pi / 180
                return CGPoint(x: c.x + cos(a) * rad, y: c.y + sin(a) * rad)
            }
            // quadrante
            let face = Path(ellipseIn: CGRect(x: c.x - r + 1, y: c.y - r + 1, width: s - 2, height: s - 2))
            ctx.fill(face, with: .radialGradient(Gradient(colors: [Color(red: 0.10, green: 0.13, blue: 0.07), Color(red: 0.02, green: 0.02, blue: 0.015)]),
                                                center: CGPoint(x: c.x, y: c.y - r * 0.15), startRadius: 0, endRadius: r))
            ctx.stroke(face, with: .color(Theme.olive.opacity(0.35)), lineWidth: 1.5)
            for a in stride(from: 0, to: 360, by: 5) {
                let big = a % 30 == 0, mid = a % 10 == 0
                let ang = Double(a) - heading
                var p = Path()
                p.move(to: pt(ang, r * (big ? 0.91 : 0.89)))
                p.addLine(to: pt(ang, r * (big ? 0.78 : (mid ? 0.82 : 0.85))))
                ctx.stroke(p, with: .color(big ? .white : (mid ? Theme.dim : Theme.olive.opacity(0.35))), lineWidth: big ? 2 : 1)
            }
            for a in stride(from: 0, to: 360, by: 30) {
                let card = [0: "N", 90: "E", 180: "S", 270: "O"][a]
                let t = Text(card ?? "\(a)")
                    .font(.system(size: card != nil ? s * 0.08 : s * 0.05, weight: .heavy, design: .monospaced))
                    .foregroundColor(a == 0 ? Theme.red : (card != nil ? .white : Theme.dim))
                ctx.draw(t, at: pt(Double(a) - heading, r * 0.64))
            }
            if attivo {
                // contro-azimut (da dove arrivi)
                let bk = pt(bearing + 180 - heading, r * 0.91)
                ctx.stroke(Path(ellipseIn: CGRect(x: bk.x - 4.5, y: bk.y - 4.5, width: 9, height: 9)), with: .color(Theme.dim), lineWidth: 2)
                // freccia verso il punto
                let rel = bearing - heading
                var shaft = Path(); shaft.move(to: c); shaft.addLine(to: pt(rel, r * 0.5))
                ctx.stroke(shaft, with: .color(.black), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                ctx.stroke(shaft, with: .color(Theme.oliveBright), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                var head = Path()
                head.move(to: pt(rel, r * 0.72))
                head.addLine(to: pt(rel + 13, r * 0.47))
                head.addLine(to: pt(rel, r * 0.53))
                head.addLine(to: pt(rel - 13, r * 0.47))
                head.closeSubpath()
                ctx.fill(head, with: .color(Theme.oliveBright))
                ctx.stroke(head, with: .color(.black), lineWidth: 1.2)
                let dot = pt(rel, r * 0.9)
                ctx.fill(Path(ellipseIn: CGRect(x: dot.x - 6, y: dot.y - 6, width: 12, height: 12)), with: .color(Theme.oliveBright))
            }
            // indice fisso in alto
            var tri = Path()
            tri.move(to: CGPoint(x: c.x, y: c.y - r - 1))
            tri.addLine(to: CGPoint(x: c.x + 8, y: c.y - r + 12))
            tri.addLine(to: CGPoint(x: c.x - 8, y: c.y - r + 12))
            tri.closeSubpath()
            ctx.fill(tri, with: .color(Color(red: 0.31, green: 0.70, blue: 1.0)))
            // centro
            let inner = CGRect(x: c.x - r * 0.31, y: c.y - r * 0.31, width: r * 0.62, height: r * 0.62)
            ctx.fill(Path(ellipseIn: inner), with: .color(.black))
            ctx.stroke(Path(ellipseIn: inner), with: .color(Theme.olive.opacity(0.35)), lineWidth: 1.2)
            ctx.draw(Text(gradi3(heading - decl)).font(.system(size: s * 0.1, weight: .heavy, design: .monospaced)).foregroundColor(.white),
                     at: CGPoint(x: c.x, y: c.y - s * 0.012))
            ctx.draw(Text("ROTTA M").font(.system(size: s * 0.036, weight: .bold, design: .monospaced)).foregroundColor(Theme.dim),
                     at: CGPoint(x: c.x, y: c.y + s * 0.07))
        }
        .accessibilityLabel("Bussola: rotta \(gradi3(heading - decl)) magnetici, punto a \(gradi3(bearing - decl))")
    }
}

/// Riquadro con i propri dati sopra la mappa (stile ATAK).
struct NavHUD: View {
    @EnvironmentObject var location: LocationService
    var body: some View {
        let me = location.location
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            VStack(alignment: .leading, spacing: 1) {
                Text("ORO 16 · \(ora(ctx.date))").foregroundStyle(.white)
                Text(me.map { Coordinate.utmText($0.coordinate) } ?? "in attesa del GPS")
                if let me {
                    Text(String(format: "%@ · %@", me.verticalAccuracy > 0 ? String(format: "%.0f m slm", me.altitude) : "quota —",
                                me.speed > 0.3 ? String(format: "%.1f km/h", me.speed * 3.6) : "fermo"))
                    Text(String(format: "GPS ±%.0f m", me.horizontalAccuracy))
                }
            }
            .font(Theme.mono(10.5, .bold))
            .foregroundStyle(Color(red: 0.5, green: 0.89, blue: 0.83))
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color(red: 0.5, green: 0.89, blue: 0.83).opacity(0.25)))
        }
        .allowsHitTesting(false)
    }
    func ora(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d) }
}

// MARK: - Scheda nuovo / modifica punto

struct PuntoEditor: View {
    enum Scheda: Hashable { case utm, cerca }
    var modifica: GaraPoint? = nil
    var coordIniziale: CLLocationCoordinate2D? = nil
    var scheda: Scheda = .utm
    /// Chiude la scheda e mette il mirino sulla mappa.
    var scegliSullaMappa: (GaraPoint?) -> Void
    @EnvironmentObject var location: LocationService
    @EnvironmentObject var log: FieldLog
    @ObservedObject var nav = NavStore.shared
    @Environment(\.dismiss) var dismiss

    @State private var tab: Scheda = .utm
    @State private var nome = ""
    @State private var zona = "33T"
    @State private var est = ""
    @State private var nord = ""
    @State private var tipo = "wp"
    @State private var nota = ""
    @State private var query = ""
    @State private var luoghi: [MKMapItem] = []
    @State private var cercando = false
    @State private var pronto = false

    var ufficiale: Bool { modifica != nil && modifica?.kind != .mio }
    var mio: PuntoMio? { modifica.flatMap { nav.mio($0) } }

    var coord: CLLocationCoordinate2D? {
        let z = zona.uppercased().trimmingCharacters(in: .whitespaces)
        return UTM.parse("\(z) \(est) \(nord)").map { let (la, lo) = UTM.toLatLon($0); return .init(latitude: la, longitude: lo) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                segmenti
                if tab == .utm { formUTM } else { formCerca }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(modifica != nil ? "MODIFICA PUNTO" : (tab == .cerca ? "CAMBIA PUNTO" : "NUOVO PUNTO"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                if tab == .utm {
                    ToolbarItem(placement: .confirmationAction) { Button("Salva") { salva(naviga: true) }.disabled(coord == nil).fontWeight(.bold) }
                }
            }
        }
        .tint(Theme.oliveBright)
        .onAppear(perform: prepara)
    }

    var segmenti: some View {
        HStack(spacing: 0) {
            seg("UTM", tab == .utm) { tab = .utm }
            seg("CERCA", tab == .cerca) { tab = .cerca }
            seg("MAPPA", false) { dismiss(); scegliSullaMappa(modifica) }
        }
        .padding(3)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.stroke))
    }

    func seg(_ t: String, _ on: Bool, _ a: @escaping () -> Void) -> some View {
        Button { haptic(); a() } label: {
            Text(t).font(Theme.mono(11.5, .heavy)).tracking(0.6)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .foregroundStyle(on ? .black : Theme.dim)
                .background(on ? Theme.olive : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    func label(_ t: String) -> some View {
        Text(t).font(Theme.mono(9, .bold)).tracking(1.4).foregroundStyle(Theme.dim)
    }

    func campo(_ t: Binding<String>, _ ph: String, mono: Bool = true, kb: UIKeyboardType = .default) -> some View {
        TextField(ph, text: t)
            .font(mono ? Theme.mono(15.5, .heavy) : .system(size: 15, weight: .medium))
            .keyboardType(kb)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.characters)
            .padding(.horizontal, 11).padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.stroke))
    }

    var formUTM: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) { label("NOME"); campo($nome, "es. WP GUADO", mono: false) }
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) { label("ZONA"); campo($zona, "33T") }.frame(width: 72)
                    VStack(alignment: .leading, spacing: 4) { label("EST"); campo($est, "290251", kb: .numbersAndPunctuation) }
                    VStack(alignment: .leading, spacing: 4) { label("NORD"); campo($nord, "4874842", kb: .numbersAndPunctuation) }
                }
                .onChange(of: est) { incolla($0) }
                .onChange(of: nord) { incolla($0) }
                verifica
                if !ufficiale {
                    VStack(alignment: .leading, spacing: 6) {
                        label("TIPO")
                        HStack(spacing: 6) {
                            ForEach(PuntoMio.tipi, id: \.0) { t in
                                Button { tipo = t.0 } label: {
                                    HStack(spacing: 5) { Circle().fill(t.2).frame(width: 8, height: 8); Text(t.1) }
                                        .font(Theme.mono(11, .heavy))
                                        .foregroundStyle(tipo == t.0 ? .white : Theme.dim)
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(tipo == t.0 ? Theme.oliveDeep : .clear, in: Capsule())
                                        .overlay(Capsule().strokeBorder(tipo == t.0 ? Theme.olive : Theme.stroke))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) { label("NOTA"); campo($nota, "facoltativa", mono: false) }
                if ufficiale {
                    Text("Punto ufficiale: le modifiche vengono salvate come copia, l'originale resta.")
                        .font(Theme.mono(11, .semibold)).foregroundStyle(Theme.amber)
                }
                HStack(spacing: 8) {
                    Button { salva(naviga: false) } label: {
                        Text("SALVA").font(Theme.mono(13, .heavy)).frame(maxWidth: .infinity).padding(.vertical, 13)
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.olive))
                    }
                    Button { salva(naviga: true) } label: {
                        Text("SALVA E NAVIGA ▸").font(Theme.mono(13, .heavy)).foregroundStyle(.black)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(Theme.olive, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .layoutPriority(1)
                }
                .buttonStyle(.plain)
                .disabled(coord == nil)
                .opacity(coord == nil ? 0.45 : 1)
                if let m = mio {
                    Button(role: .destructive) { nav.elimina(m); dismiss() } label: {
                        Text("ELIMINA PUNTO").font(Theme.mono(12, .heavy)).frame(maxWidth: .infinity).padding(.vertical, 11)
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.red.opacity(0.5)))
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.red)
                }
            }
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder var verifica: some View {
        let me = location.location?.coordinate
        Group {
            if let c = coord {
                let area = Gara.areas.first { $0.tipo == "operativa" }
                let dentro = area.map { Coordinate.inside(c, $0.coordinates) } ?? true
                let vietata = Gara.areas.filter(\.interdetta).contains { Coordinate.inside(c, $0.coordinates) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("✓ UTM WGS84 riconosciuto").foregroundStyle(vietata ? Theme.red : Theme.oliveBright)
                    Text("MGRS \(Geo.mgrs(c))").foregroundStyle(Theme.dim)
                    Text(String(format: "%.5f N  %.5f E", c.latitude, c.longitude)).foregroundStyle(Theme.dim)
                    if let me {
                        Text("da te \(Geo.formatDistance(Geo.distance(me, c))) · az \(gradi3(Geo.bearing(me, c) - (location.declinazione ?? 4.6))) magn.")
                            .foregroundStyle(Theme.dim)
                    }
                    Text(vietata ? "DENTRO UN'AREA INTERDETTA" : (dentro ? "dentro l'area di gara" : "fuori dall'area di gara"))
                        .foregroundStyle(vietata ? Theme.red : (dentro ? Theme.dim : Theme.amber))
                }
            } else {
                Text("Scrivi Est e Nord, oppure incolla in un campo un UTM intero, un MGRS (33T TJ 90251 74842) o lat/lon.")
                    .foregroundStyle(Theme.dim)
            }
        }
        .font(Theme.mono(11, .bold))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11).padding(.vertical, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.stroke))
    }

    var formCerca: some View {
        let me = location.location?.coordinate
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let trovati = nav.tutti
            .filter { q.isEmpty || $0.id.lowercased().contains(q) || $0.note.lowercased().contains(q) }
            .sorted { a, b in
                guard let me else { return a.id < b.id }
                return Geo.distance(me, a.coordinate) < Geo.distance(me, b.coordinate)
            }
        let gruppi: [(String, [GaraPoint])] = [
            ("I TUOI PUNTI", trovati.filter { $0.kind == .mio }),
            ("OBJ", trovati.filter { $0.kind == .obj }),
            ("RECON / WP", trovati.filter { $0.kind == .recon }),
            ("LOGISTICA", trovati.filter { $0.kind == .logistica }),
            ("ACQUA", trovati.filter { $0.kind == .acqua }),
            ("IPOTESI", trovati.filter { $0.kind == .ipotesi }),
            ("HOTEL", trovati.filter { $0.kind == .hotel }),
        ].filter { !$0.1.isEmpty }
        return VStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.dim)
                TextField("Cerca OBJ, ingresso, WP, luogo…", text: $query)
                    .autocorrectionDisabled()
                    .onSubmit(cercaLuoghi)
                if !query.isEmpty { Button { query = ""; luoghi = [] } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.dim) } }
            }
            .padding(.horizontal, 11).padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.stroke))
            .onChange(of: query) { _ in pianificaRicerca() }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(gruppi, id: \.0) { g in
                        label("\(g.0) · \(g.1.count)")
                        VStack(spacing: 0) {
                            ForEach(g.1) { p in riga(p, me: me) }
                        }
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.stroke))
                    }
                    if !q.isEmpty {
                        HStack { label("LUOGHI · APPLE MAPPE"); if cercando { ProgressView().scaleEffect(0.7) } }
                        if luoghi.isEmpty && !cercando {
                            Text(trovati.isEmpty ? "Nessun punto noto. Nessun luogo trovato (serve la rete)." : "Nessun luogo trovato (serve la rete).")
                                .font(Theme.mono(11, .semibold)).foregroundStyle(Theme.dim)
                        }
                        VStack(spacing: 0) {
                            ForEach(luoghi, id: \.self) { it in
                                let p = GaraPoint(id: (it.name ?? "LUOGO").uppercased(), lat: it.placemark.coordinate.latitude,
                                                  lon: it.placemark.coordinate.longitude, kind: .mio,
                                                  note: it.placemark.title ?? "")
                                Button { usaLuogo(p) } label: {
                                    rigaContenuto(p, sotto: it.placemark.title ?? "", me: me, colore: Theme.cyan)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.bottom, 20)
            }
        }
    }

    func riga(_ p: GaraPoint, me: CLLocationCoordinate2D?) -> some View {
        Button {
            haptic()
            nav.target = p
            dismiss()
        } label: { rigaContenuto(p, sotto: Coordinate.utmText(p.coordinate), me: me, colore: p.color) }
        .buttonStyle(.plain)
    }

    func rigaContenuto(_ p: GaraPoint, sotto: String, me: CLLocationCoordinate2D?, colore: Color) -> some View {
        HStack(spacing: 10) {
            Circle().fill(colore).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.id).font(Theme.mono(12, .heavy)).foregroundStyle(nav.target?.id == p.id ? Theme.oliveBright : .white).lineLimit(1)
                Text(sotto).font(Theme.mono(10, .semibold)).foregroundStyle(Theme.dim).lineLimit(1)
            }
            Spacer(minLength: 6)
            if let me {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Geo.formatDistance(Geo.distance(me, p.coordinate))).foregroundStyle(Theme.oliveBright)
                    Text(gradi3(Geo.bearing(me, p.coordinate) - (location.declinazione ?? 4.6)) + "M").foregroundStyle(Theme.dim)
                }
                .font(Theme.mono(11, .heavy))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .contentShape(Rectangle())
        .overlay(alignment: .top) { Rectangle().fill(Theme.stroke).frame(height: 0.5) }
    }

    /// Un luogo di Apple Mappe diventa un punto tuo (così resta anche offline) e ci si naviga.
    func usaLuogo(_ p: GaraPoint) {
        let salvato = nav.salva(PuntoMio(nome: p.id, lat: p.lat, lon: p.lon, tipo: "altro", nota: p.note))
        nav.target = salvato.punto
        dismiss()
    }

    @State private var timer: Timer?
    func pianificaRicerca() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in cercaLuoghi() }
    }

    func cercaLuoghi() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 3 else { luoghi = []; return }
        let r = MKLocalSearch.Request()
        r.naturalLanguageQuery = q
        let centro = location.location?.coordinate ?? CLLocationCoordinate2D(latitude: 43.99, longitude: 12.38)
        r.region = MKCoordinateRegion(center: centro, latitudinalMeters: 30_000, longitudinalMeters: 30_000)
        cercando = true
        MKLocalSearch(request: r).start { res, _ in
            cercando = false
            luoghi = Array((res?.mapItems ?? []).prefix(8))
        }
    }

    func incolla(_ v: String) {
        let t = v.trimmingCharacters(in: .whitespaces)
        guard t.contains(" ") || t.contains(",") || t.rangeOfCharacter(from: .letters) != nil,
              let c = Coordinate.parse(t) else { return }
        imposta(c)
    }

    func imposta(_ c: CLLocationCoordinate2D) {
        let u = UTM.fromLatLon(c.latitude, c.longitude)
        zona = "\(u.zone)\(u.band)"
        est = String(format: "%.0f", u.easting)
        nord = String(format: "%.0f", u.northing)
    }

    func prepara() {
        guard !pronto else { return }
        pronto = true
        tab = scheda
        if let m = modifica {
            imposta(m.coordinate)
            nome = m.id
            if let p = nav.mio(m) { tipo = p.tipo; nota = p.nota }
        }
        if let c = coordIniziale {
            imposta(c)
            if modifica == nil { nome = "PUNTO \(nav.miei.count + 1)" }
        }
    }

    func salva(naviga: Bool) {
        guard let c = coord else { return }
        var p = mio ?? PuntoMio(nome: nome, lat: c.latitude, lon: c.longitude)
        p.nome = ufficiale ? "\(nome) COPIA" : nome
        p.lat = c.latitude; p.lon = c.longitude; p.tipo = tipo; p.nota = nota
        let s = nav.salva(p)
        if mio == nil {
            log.add(.punto, "Punto \(s.nome) · \(Coordinate.utmText(c))", at: CLLocation(latitude: c.latitude, longitude: c.longitude))
        }
        if naviga { nav.target = s.punto }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
