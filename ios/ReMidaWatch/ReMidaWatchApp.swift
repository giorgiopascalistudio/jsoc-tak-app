import SwiftUI
import WatchKit
import MapKit

@main
struct ReMidaWatchApp: App {
    @StateObject private var m = WatchModel()
    @AppStorage("notte.locale") private var notteLocale = -1     // -1 segue il telefono, 0 giorno, 1 notte
    @State private var pagina = UserDefaults.standard.integer(forKey: "debug.pagina")

    var notte: Bool { notteLocale == -1 ? m.stato.notte : notteLocale == 1 }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                TabView(selection: $pagina) {
                    Cruscotto().tag(0)
                    PercorsoPagina().tag(1)
                    MappaPagina().tag(2)
                }
                .tabViewStyle(.verticalPage)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack(spacing: 6) {
                            Button {
                                notteLocale = notte ? 0 : 1
                                WKInterfaceDevice.current().play(.click)
                            } label: {
                                Image(systemName: notte ? "moon.fill" : "moon").font(.system(size: 14, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(notte ? W.rosso : W.oliva)
                            Spacer(minLength: 4)
                            Pallino(stato: m.stato.pc, icona: "desktopcomputer")
                            Pallino(stato: m.stato.server, icona: "server.rack")
                            Pallino(stato: m.telefono ? 1 : 0, icona: "iphone")
                        }
                    }
                }
                .alert("Entri in \(m.proponi ?? "")?", isPresented: Binding(get: { m.proponi != nil }, set: { if !$0 { m.proponi = nil } })) {
                    Button("Entro · parte il timer") { if let c = m.proponi { m.entra(c) } }
                    Button("Non ancora", role: .cancel) { m.proponi = nil }
                }
            }
            .tint(notte ? W.rosso : W.oliva)
            .colorMultiply(notte ? W.rosso : .white)
            .environment(\.locale, Locale(identifier: "it_IT"))
            .environmentObject(m)
        }
    }
}

enum W {
    static let oliva = Color(red: 0.604, green: 0.682, blue: 0.357)
    static let rosso = Color(red: 0.85, green: 0, blue: 0)
    static let ok = Color(red: 0.45, green: 0.85, blue: 0.45)
    static let ko = Color(red: 0.95, green: 0.36, blue: 0.30)
    static let ambra = Color(red: 0.92, green: 0.64, blue: 0.28)
    static let compagno = Color(red: 0.98, green: 0.42, blue: 0.32)
    static func mono(_ s: CGFloat, _ w: Font.Weight = .semibold) -> Font { .system(size: s, weight: w, design: .monospaced) }
    static func distanza(_ m: Double) -> String { m < 1000 ? String(format: "%.0f m", m) : String(format: "%.2f km", m / 1000) }
}

struct Pallino: View {
    let stato: Int
    let icona: String
    var body: some View {
        HStack(spacing: 2) {
            Circle().fill(stato == 1 ? W.ok : (stato == 0 ? W.ko : Color.gray)).frame(width: 6, height: 6)
            Image(systemName: icona).font(.system(size: 9))
        }
    }
}

// MARK: - Cruscotto: tutto in una schermata

struct Cruscotto: View {
    @EnvironmentObject var m: WatchModel
    @State private var azioni = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            GeometryReader { g in
                let t = m.prossima
                let v = t.flatMap { m.verso($0) }
                let lato = min(g.size.width * 0.78, g.size.height * 0.56)
                let fin = finestra(ctx.date)
                VStack(spacing: 2) {
                    // obiettivo
                    HStack(spacing: 5) {
                        Text(t?.code ?? "FINE").font(W.mono(15, .heavy)).foregroundStyle(W.oliva)
                        Text(t?.nome ?? "Percorso completato").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    }
                    // bussola con battiti e kcal in alto a sinistra
                    ZStack {
                        Bussola(gradiObj: v?.gradi, direzione: m.direzione ?? 0, compagni: compagni,
                                finestra: fin?.frazione, coloreFinestra: fin?.colore ?? W.oliva)
                            .frame(width: lato, height: lato)
                            .contentShape(Circle())
                            .onTapGesture { azioni = true; WKInterfaceDevice.current().play(.click) }
                        VStack(alignment: .leading, spacing: 3) {
                            Label { Text(m.battiti.map { String(format: "%.0f", $0) } ?? "--").font(W.mono(14, .bold)) }
                                icon: { Image(systemName: "heart.fill").foregroundStyle(W.ko) }
                            Label { Text(String(format: "%.0f", m.kcal)).font(W.mono(12, .bold)) }
                                icon: { Image(systemName: "flame.fill").foregroundStyle(W.ambra) }
                        }
                        .font(.system(size: 11))
                        .labelStyle(CompattaLabel())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(height: lato)
                    // posizione, distanza o timer, meteo
                    Text(m.utm).font(W.mono(11, .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    HStack(alignment: .firstTextBaseline) {
                        if let fin {
                            Text(fin.testo).font(W.mono(30, .heavy)).foregroundStyle(fin.colore).monospacedDigit()
                        } else {
                            Text(v.map { W.distanza($0.metri) } ?? "GPS…").font(W.mono(30, .heavy)).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                        Spacer(minLength: 2)
                        HStack(spacing: 2) {
                            Image(systemName: m.stato.meteoIcona).symbolRenderingMode(.multicolor)
                            Text(m.stato.meteoTemp.map { String(format: "%.0f°", $0) } ?? "--").font(W.mono(12))
                        }
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "figure.walk")
                        Text(m.velocita.map { String(format: "%.1f km/h", $0) } ?? "--")
                        if fin != nil {
                            Text("finestra \(m.stato.finestraCode ?? "")")
                        } else if let v {
                            Text("ETA " + m.eta(v.metri).hhmm)
                        }
                    }
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .confirmationDialog(m.prossima.map { "\($0.code) \($0.nome)" } ?? "Re Mida", isPresented: $azioni) {
            if !m.avviato {
                Button("Avvia percorso") { m.avviaPercorso() }
            } else if let t = m.prossima {
                if m.stato.finestraCode == t.code {
                    Button("Fatto \(t.code)") { m.fatto(t.code) }
                    Button("Annulla finestra", role: .destructive) { m.annullaFinestra() }
                } else {
                    Button("Entro in \(t.code) · \(TappaMarcia.durata(t.code))'") { m.entra(t.code) }
                    Button("Fatto senza timer") { m.fatto(t.code) }
                }
            }
            Button("Chiudi", role: .cancel) {}
        }
    }

    /// Compagni da mostrare sul bordo della bussola (non me stesso).
    var compagni: [(String, Double, Bool)] {
        guard let me = m.posizione?.coordinate else { return [] }
        return m.stato.operatori.filter { $0.cs.uppercased() != m.stato.io.uppercased() }.map { o in
            let p1 = me.latitude * .pi / 180, p2 = o.lat * .pi / 180, dl = (o.lon - me.longitude) * .pi / 180
            let b = atan2(sin(dl) * cos(p2), cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)) * 180 / .pi
            return (String(o.cs.prefix(3)).uppercased(), (b + 360).truncatingRemainder(dividingBy: 360), o.collegato)
        }
    }

    func finestra(_ ora: Date) -> (frazione: Double, testo: String, colore: Color)? {
        guard m.stato.finestraCode != nil, let i = m.stato.finestraInizio, let f = m.stato.finestraFine else { return nil }
        let tot = f.timeIntervalSince(i), rest = max(0, f.timeIntervalSince(ora))
        let col = rest < 60 ? W.ko : (rest < 300 ? W.ambra : W.oliva)
        return (rest / tot, String(format: "%02d:%02d", Int(rest) / 60, Int(rest) % 60), col)
    }
}

struct CompattaLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon; configuration.title }
    }
}

/// Bussola: bordo con tacche e N (gira col polso), freccia verso l'OBJ, compagni come pallini sul bordo.
/// Con la finestra aperta il bordo diventa il timer.
struct Bussola: View {
    let gradiObj: Double?
    let direzione: Double
    let compagni: [(String, Double, Bool)]
    let finestra: Double?
    let coloreFinestra: Color

    var body: some View {
        GeometryReader { g in
            let r = min(g.size.width, g.size.height) / 2
            ZStack {
                Circle().stroke(W.oliva.opacity(0.45), lineWidth: 1.5)
                if let finestra {
                    Circle().trim(from: 0, to: finestra)
                        .stroke(coloreFinestra, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: finestra)
                }
                ForEach(0..<12, id: \.self) { i in
                    Rectangle().fill(W.oliva.opacity(i % 3 == 0 ? 0.9 : 0.4))
                        .frame(width: 1.5, height: i % 3 == 0 ? 8 : 4)
                        .offset(y: -r + 6)
                        .rotationEffect(.degrees(Double(i) * 30 - direzione))
                }
                Text("N").font(.system(size: 11, weight: .heavy)).foregroundStyle(W.ko)
                    .offset(y: -r + 20).rotationEffect(.degrees(-direzione))
                if let gradiObj {
                    Circle().fill(W.oliva).frame(width: 9, height: 9)
                        .offset(y: -r).rotationEffect(.degrees(gradiObj - direzione))
                    Image(systemName: "location.north.fill").font(.system(size: r * 0.62))
                        .foregroundStyle(W.oliva)
                        .rotationEffect(.degrees(gradiObj - direzione))
                        .animation(.easeOut(duration: 0.3), value: direzione)
                }
                ForEach(Array(compagni.enumerated()), id: \.offset) { _, c in
                    let a = (c.1 - direzione) * .pi / 180
                    let x = sin(a) * r, y = -cos(a) * r
                    ZStack {
                        Circle().fill(c.2 ? W.compagno : Color.gray).frame(width: 9, height: 9).offset(x: x, y: y)
                        Text(c.0).font(.system(size: 10, weight: .heavy)).foregroundStyle(c.2 ? W.compagno : .gray)
                            .offset(x: x + (x >= 0 ? 16 : -16), y: y + (y >= 0 ? 8 : -8))
                    }
                }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }
}

// MARK: - Percorso: in linea con i tempi

struct PercorsoPagina: View {
    @EnvironmentObject var m: WatchModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("PERCORSO").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(W.oliva)
                HStack(spacing: 10) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.12), lineWidth: 5)
                        Circle().trim(from: 0, to: Double(m.fatti) / Double(Shared.marcia.count))
                            .stroke(W.oliva, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                        Text("\(m.fatti)/\(Shared.marcia.count)").font(W.mono(13, .bold))
                    }
                    .frame(width: 50, height: 50)
                    VStack(alignment: .leading, spacing: 1) {
                        if let s = m.scarto {
                            Text(abs(s) <= 5 ? "IN LINEA" : (s > 0 ? "+\(s)' RITARDO" : "\(-s)' ANTICIPO"))
                                .font(W.mono(13, .heavy)).foregroundStyle(abs(s) <= 5 ? W.ok : (s > 0 ? W.ko : W.oliva))
                        } else {
                            Text(m.avviato ? "in marcia" : "non partiti").font(W.mono(12)).foregroundStyle(.secondary)
                        }
                        if let i = m.stato.inizioPercorso {
                            Text("partiti " + i.hhmm).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(Shared.marcia) { t in
                    let fatto = m.stato.fatti[t.code]
                    HStack {
                        Text(t.code).font(W.mono(12, .bold)).foregroundStyle(fatto != nil ? .secondary : W.oliva)
                        Spacer()
                        Text(TappaMarcia.ora(t.arrivo)).font(W.mono(11)).foregroundStyle(.secondary)
                        if let fatto {
                            Text(fatto.hhmm).font(W.mono(11, .bold)).foregroundStyle(W.ok)
                        }
                    }
                    .opacity(fatto != nil ? 0.7 : 1)
                }
                if !m.avviato {
                    Button { m.avviaPercorso() } label: { Label("Avvia percorso", systemImage: "figure.walk.departure") }
                        .tint(W.oliva)
                } else {
                    Button {
                        if m.allenamento { m.fermaAllenamento() } else { m.avviaAllenamento() }
                    } label: {
                        Label(m.allenamento ? "Ferma registrazione" : "Riprendi registrazione",
                              systemImage: m.allenamento ? "stop.fill" : "heart.fill")
                    }
                    .tint(m.allenamento ? .gray : W.oliva)
                }
            }
        }
    }
}

// MARK: - Mappa con operatori e obiettivi

struct MappaPagina: View {
    @EnvironmentObject var m: WatchModel
    @State private var camera: MapCameraPosition = .userLocation(fallback: .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 43.978, longitude: 12.379),
        span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04))))

    static let ff04 = TappaMarcia(code: "FF04", nome: "Deposito armi", lat: 43.989508, lon: 12.379986, arrivo: 0, fine: 0)

    var body: some View {
        Map(position: $camera) {
            UserAnnotation()
            ForEach(Shared.marcia + [Self.ff04]) { t in
                Annotation(t.code, coordinate: CLLocationCoordinate2D(latitude: t.lat, longitude: t.lon)) {
                    Text(String(Int(t.code.dropFirst(2)) ?? 0))
                        .font(.system(size: 10, weight: .heavy))
                        .frame(width: 18, height: 18)
                        .background(m.stato.fatti[t.code] != nil ? Color.gray : (m.prossima == t ? W.oliva : W.ko), in: Circle())
                        .foregroundStyle(.black)
                }
            }
            ForEach(m.stato.operatori.filter { $0.cs.uppercased() != m.stato.io.uppercased() }) { o in
                Annotation(o.cs, coordinate: CLLocationCoordinate2D(latitude: o.lat, longitude: o.lon)) {
                    Circle().fill(o.collegato ? W.compagno : Color.gray).frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white, lineWidth: 1))
                }
            }
        }
        .mapStyle(.imagery(elevation: .flat))
        .mapControls { MapUserLocationButton() }
    }
}

extension Date {
    /// Ora a 24 ore (le anteprime mostravano "5:10 PM").
    var hhmm: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "HH:mm"
        return f.string(from: self)
    }
}
