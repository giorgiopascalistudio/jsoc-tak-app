import SwiftUI
import CoreLocation

// MARK: - Prove pronte (2): due dispositivi, labirinto, GPS, prove sotto stress

/// chi vede cosa: tutto su uno schermo, solo il congegno, solo il manuale (secondo telefono)
enum ModoProva { case entrambi, dispositivo, manuale }
private struct ModoProvaKey: EnvironmentKey { static let defaultValue = ModoProva.entrambi }
extension EnvironmentValues {
    var modoProva: ModoProva {
        get { self[ModoProvaKey.self] }
        set { self[ModoProvaKey.self] = newValue }
    }
}

/// codice da dettare al secondo telefono: tipo + livello + seme in 8 caratteri leggibili
enum CodiceProva {
    static let alfabeto = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    static func crea(_ t: TipoProva, _ l: LivelloProva, _ seme: UInt64) -> String {
        let i = UInt64(TipoProva.allCases.firstIndex(of: t) ?? 0)
        var v = ((i * 3 + UInt64(l.rawValue - 1)) << 24) | (seme & 0xFF_FFFF)
        var s = ""
        for _ in 0..<8 { s.append(alfabeto[Int(v % 32)]); v /= 32 }
        return String(s.prefix(4)) + "-" + String(s.suffix(4))
    }
    static func leggi(_ c: String) -> (TipoProva, LivelloProva, UInt64)? {
        let ch = Array(c.uppercased().filter { alfabeto.contains($0) })
        guard ch.count == 8 else { return nil }
        var v: UInt64 = 0
        for x in ch.reversed() { v = v * 32 + UInt64(alfabeto.firstIndex(of: x)!) }
        let seme = v & 0xFF_FFFF, k = Int(v >> 24)
        let tipi = TipoProva.allCases
        guard k / 3 < tipi.count, let l = LivelloProva(rawValue: k % 3 + 1) else { return nil }
        return (tipi[k / 3], l, seme)
    }
}

/// il secondo telefono: inserisce il codice e vede solo il manuale
struct ManualeProvaView: View {
    @State private var codice = ""
    @State private var aperto: (TipoProva, LivelloProva, UInt64)?
    @StateObject private var finta = SessioneProva(minuti: 60, livello: .facile)

    var body: some View {
        Group {
            if let a = aperto {
                VStack(spacing: 0) {
                    HStack {
                        Button { aperto = nil } label: { Label("Altro codice", systemImage: "chevron.left").font(.system(size: 15, weight: .bold)) }.tint(.white)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("MANUALE · \(a.0.nome.uppercased())").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.amber)
                            Text(a.1.nome.uppercased()).font(.system(size: 10, weight: .heavy)).foregroundStyle(a.1.colore)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10).background(Theme.surface)
                    VistaProva.crea(a.0, a.1, a.2) {}
                        .environment(\.modoProva, .manuale)
                        .environmentObject(finta)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "book.closed.fill").font(.system(size: 54)).foregroundStyle(Theme.amber)
                    Text("Manuale per il secondo telefono").font(.system(size: 20, weight: .black))
                    Text("Chi ha il congegno legge il codice che vede in alto. Tu lo inserisci qui e vedi solo il manuale: dovete parlarvi (a voce o via radio) senza guardare lo schermo dell'altro.")
                        .font(.system(size: 13.5)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                    TextField("CODICE (es. KQ7M-2RTA)", text: $codice)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .font(Theme.mono(24, .heavy)).multilineTextAlignment(.center)
                        .padding(12).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: 360)
                    Button { if let x = CodiceProva.leggi(codice) { haptic(); aperto = x } else { Suoni.errore() } } label: { Label("Apri il manuale", systemImage: "book") }
                        .buttonStyle(PrimaryButtonStyle()).frame(maxWidth: 360)
                        .disabled(CodiceProva.leggi(codice) == nil)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Manuale")
    }
}

/// costruisce la vista di una prova (usata dalla partita e dal manuale sul secondo telefono)
enum VistaProva {
    static func crea(_ t: TipoProva, _ l: LivelloProva, _ seme: UInt64, fatta: @escaping () -> Void) -> AnyView {
        switch t {
        case .fili: return AnyView(ProvaFili(d: DatiFili(l, seme), fatta: fatta))
        case .simboli: return AnyView(ProvaSimboli(d: DatiSimboli(l, seme), fatta: fatta))
        case .lucchetto: return AnyView(ProvaLucchetto(d: DatiLucchetto(l, seme), fatta: fatta))
        case .cifrario: return AnyView(ProvaCifrario(d: DatiCifrario(l, seme), fatta: fatta))
        case .sequenza: return AnyView(ProvaSequenze(d: DatiSequenze(l, seme), fatta: fatta))
        case .memoria: return AnyView(ProvaMemoria(livello: l, seme: seme, fatta: fatta))
        case .quiz: return AnyView(ProvaQuiz(d: DatiQuiz(l, seme), fatta: fatta))
        case .griglia: return AnyView(ProvaGriglia(d: DatiGriglia(l, seme), fatta: fatta))
        case .interruttori: return AnyView(ProvaInterruttori(d: DatiInterruttori(l, seme), fatta: fatta))
        case .radio: return AnyView(ProvaRadio(d: DatiRadio(l, seme), fatta: fatta))
        case .labirinto: return AnyView(ProvaLabirinto(d: DatiLabirinto(l, seme), fatta: fatta))
        case .raggiungi: return AnyView(ProvaRaggiungi(livello: l, seme: seme, fatta: fatta))
        case .azimut: return AnyView(ProvaAzimut(livello: l, seme: seme, fatta: fatta))
        case .calcolo: return AnyView(ProvaCalcolo(d: DatiCalcolo(l, seme), fatta: fatta))
        case .kim: return AnyView(ProvaKim(livello: l, seme: seme, fatta: fatta))
        case .lampo: return AnyView(ProvaLampo(livello: l, seme: seme, fatta: fatta))
        }
    }
}

// MARK: - Labirinto (il congegno non vede i muri, il manuale sì)

struct DatiLabirinto {
    let n: Int
    /// muri aperti: per ogni cella, le direzioni libere (0 N, 1 E, 2 S, 3 O)
    let aperti: [[Set<Int>]]
    let partenza: (Int, Int)
    let arrivo: (Int, Int)
    let ricomincia: Bool

    init(_ l: LivelloProva, _ seme: UInt64) {
        var g = Dado(seme)
        let n = [0, 5, 6, 7][l.rawValue]
        var ap = Array(repeating: Array(repeating: Set<Int>(), count: n), count: n)
        var visti = Array(repeating: Array(repeating: false, count: n), count: n)
        var pila: [(Int, Int)] = [(0, 0)]
        visti[0][0] = true
        let dx = [0, 1, 0, -1], dy = [-1, 0, 1, 0]
        while let c = pila.last {
            let vicini = (0..<4).filter { d in
                let x = c.0 + dx[d], y = c.1 + dy[d]
                return x >= 0 && x < n && y >= 0 && y < n && !visti[y][x]
            }
            if vicini.isEmpty { pila.removeLast(); continue }
            let d = g.uno(vicini)
            let x = c.0 + dx[d], y = c.1 + dy[d]
            ap[c.1][c.0].insert(d)
            ap[y][x].insert((d + 2) % 4)
            visti[y][x] = true
            pila.append((x, y))
        }
        self.n = n
        aperti = ap
        partenza = (g.int(0...(n - 1)), n - 1)
        arrivo = (g.int(0...(n - 1)), 0)
        ricomincia = l == .difficile
    }
}

struct ProvaLabirinto: View {
    let d: DatiLabirinto
    var fatta: () -> Void
    @EnvironmentObject var s: SessioneProva
    @State private var pos: (Int, Int)?
    @State private var urto = false

    var attuale: (Int, Int) { pos ?? d.partenza }

    var body: some View {
        LayoutProva {
            VStack(spacing: 16) {
                // il congegno: solo la griglia, senza muri
                VStack(spacing: 3) {
                    ForEach(0..<d.n, id: \.self) { y in
                        HStack(spacing: 3) {
                            ForEach(0..<d.n, id: \.self) { x in
                                ZStack {
                                    RoundedRectangle(cornerRadius: 5).fill(Theme.surface2)
                                    if x == d.arrivo.0 && y == d.arrivo.1 { Image(systemName: "flag.fill").foregroundStyle(Theme.green) }
                                    if x == attuale.0 && y == attuale.1 {
                                        Circle().fill(urto ? Theme.red : Theme.amber).padding(6)
                                    }
                                }
                                .aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                }
                .frame(maxWidth: 380)
                .animation(.spring(response: 0.25), value: attuale.0 * 100 + attuale.1)
                VStack(spacing: 8) {
                    freccia("arrow.up", 0)
                    HStack(spacing: 40) { freccia("arrow.left", 3); freccia("arrow.right", 1) }
                    freccia("arrow.down", 2)
                }
                Text(d.ricomincia ? "Contro un muro si torna alla partenza." : "Contro un muro perdi secondi.").font(.caption).foregroundStyle(Theme.dim)
            }
        } indizi: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Mappa del labirinto").font(.system(size: 14, weight: .heavy))
                Text("Guida chi ha il congegno: lui vede solo la griglia, i muri li vedi tu. Partenza ●, uscita ⚑. Nord in alto.")
                    .font(.system(size: 13))
                Canvas { ctx, size in
                    let lato = min(size.width, size.height) / CGFloat(d.n)
                    for y in 0..<d.n {
                        for x in 0..<d.n {
                            let o = CGPoint(x: CGFloat(x) * lato, y: CGFloat(y) * lato)
                            var p = Path()
                            let ap = d.aperti[y][x]
                            if !ap.contains(0) { p.move(to: o); p.addLine(to: CGPoint(x: o.x + lato, y: o.y)) }
                            if !ap.contains(1) { p.move(to: CGPoint(x: o.x + lato, y: o.y)); p.addLine(to: CGPoint(x: o.x + lato, y: o.y + lato)) }
                            if !ap.contains(2) { p.move(to: CGPoint(x: o.x, y: o.y + lato)); p.addLine(to: CGPoint(x: o.x + lato, y: o.y + lato)) }
                            if !ap.contains(3) { p.move(to: o); p.addLine(to: CGPoint(x: o.x, y: o.y + lato)) }
                            ctx.stroke(p, with: .color(.white), lineWidth: 2.5)
                        }
                    }
                    let c = { (x: Int, y: Int) -> CGRect in CGRect(x: (CGFloat(x) + 0.25) * lato, y: (CGFloat(y) + 0.25) * lato, width: lato / 2, height: lato / 2) }
                    ctx.fill(Path(ellipseIn: c(d.partenza.0, d.partenza.1)), with: .color(Theme.amber))
                    ctx.fill(Path(c(d.arrivo.0, d.arrivo.1)), with: .color(Theme.green))
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 360)
            }
        }
    }

    func freccia(_ icona: String, _ dir: Int) -> some View {
        Button { muovi(dir) } label: {
            Image(systemName: icona).font(.system(size: 26, weight: .heavy))
                .frame(width: 70, height: 56).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PressStyle()).tint(.white)
    }

    func muovi(_ dir: Int) {
        let c = attuale
        if d.aperti[c.1][c.0].contains(dir) {
            Suoni.tasto()
            let dx = [0, 1, 0, -1], dy = [-1, 0, 1, 0]
            let n = (c.0 + dx[dir], c.1 + dy[dir])
            pos = n
            if n.0 == d.arrivo.0 && n.1 == d.arrivo.1 { fatta() }
        } else {
            urto = true
            Task { try? await Task.sleep(nanoseconds: 400_000_000); urto = false }
            s.sbaglia("Muro")
            if d.ricomincia { pos = d.partenza }
        }
    }
}

// MARK: - Da campo: raggiungi il punto (GPS)

struct ProvaRaggiungi: View {
    let livello: LivelloProva
    let seme: UInt64
    var fatta: () -> Void
    @EnvironmentObject var location: LocationService
    @EnvironmentObject var s: SessioneProva
    @State private var obiettivo: CLLocationCoordinate2D?

    var distanza: Double { [0, 60, 150, 300][livello.rawValue] }

    var body: some View {
        LayoutProva {
            VStack(spacing: 16) {
                if let o = obiettivo, let qui = location.location {
                    let d = Geo.distance(qui.coordinate, o)
                    let az = Geo.bearing(qui.coordinate, o)
                    if livello == .facile {
                        Image(systemName: "location.north.fill").font(.system(size: 90)).foregroundStyle(d < 15 ? Theme.green : Theme.cyan)
                            .rotationEffect(.degrees(az - (location.heading ?? 0)))
                            .animation(.spring(response: 0.4), value: location.heading)
                    }
                    if livello != .difficile {
                        Text("\(Int(d)) m").font(.system(size: 54, weight: .heavy, design: .monospaced))
                        Text(String(format: "azimut %03.0f°", az)).font(Theme.mono(18, .bold)).foregroundStyle(Theme.oliveBright)
                    } else {
                        Text("OBIETTIVO").font(.system(size: 11, weight: .heavy)).tracking(1.5).foregroundStyle(Theme.dim)
                        Text(Geo.mgrs(o)).font(Theme.mono(20, .heavy)).multilineTextAlignment(.center)
                        Text("TU SEI").font(.system(size: 11, weight: .heavy)).tracking(1.5).foregroundStyle(Theme.dim)
                        Text(Geo.mgrs(qui.coordinate)).font(Theme.mono(16, .bold)).foregroundStyle(Theme.dim)
                    }
                    Text(String(format: "precisione GPS ±%.0f m", qui.horizontalAccuracy)).font(.caption).foregroundStyle(qui.horizontalAccuracy > 15 ? Theme.amber : Theme.dim)
                    Button { if d <= max(12, min(25, qui.horizontalAccuracy)) { fatta() } else { s.sbaglia("Non ci sei ancora") } } label: {
                        Label("Sono arrivato", systemImage: "flag.checkered")
                    }
                    .buttonStyle(PrimaryButtonStyle()).frame(maxWidth: 320)
                } else {
                    ProgressView()
                    Text("Aspetto il GPS…").foregroundStyle(Theme.dim)
                }
            }
            .onReceive(location.$location) { l in
                guard obiettivo == nil, let l, l.horizontalAccuracy > 0, l.horizontalAccuracy < 40 else { return }
                var g = Dado(seme)
                let az = Double(g.int(0...359))
                let m = distanza * (0.8 + Double(g.int(0...40)) / 100)
                obiettivo = puntoVerso(l.coordinate, metri: m, azimut: az)
            }
        } indizi: {
            VStack(alignment: .leading, spacing: 6) {
                Indizio(n: 1, testo: "Il punto è a circa \(Int(distanza)) m da dove avete premuto VIA.")
                Indizio(n: 2, testo: livello == .facile ? "Segui la freccia: punta verso l'obiettivo." :
                            (livello == .medio ? "Hai solo distanza e azimut: usa la bussola (o il sole) per la direzione." :
                                "Hai solo le coordinate MGRS: confronta le cifre est/nord con le tue (1 cifra dell'ultima coppia = 1 m a 5 cifre, 10 m a 4)."))
                Indizio(n: 3, testo: "Quando sei sul punto premi «Sono arrivato»: se sei lontano perdi secondi.")
                Indizio(n: 4, testo: "Muovetevi coperti: in gara chi corre allo scoperto viene visto.")
            }
        }
    }
}

// MARK: - Da campo: punta l'azimut

struct ProvaAzimut: View {
    let livello: LivelloProva
    let seme: UInt64
    var fatta: () -> Void
    @EnvironmentObject var location: LocationService
    @EnvironmentObject var s: SessioneProva
    @State private var giro = 0
    @State private var tenuto: Date?

    var giri: Int { [0, 3, 4, 5][livello.rawValue] }
    var bersagli: [Int] { var g = Dado(seme); return (0..<giri).map { _ in g.int(0...71) * 5 } }
    var bersaglio: Int { bersagli[min(giro, giri - 1)] }
    var tolleranza: Double { [0, 6, 4, 3][livello.rawValue] }

    func testoBersaglio(_ b: Int) -> String {
        guard livello != .facile else { return String(format: "%03d°", b) }
        let card = ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]
        let base = Int((Double(b) / 45).rounded()) % 8
        let diff = b - base * 45
        if livello == .medio { return "\(card[base]) " + (diff == 0 ? "" : (diff > 0 ? "+\(diff)°" : "\(diff)°")) }
        return "ritorno di \(String(format: "%03d°", (b + 180) % 360))"
    }

    var body: some View {
        LayoutProva {
            VStack(spacing: 16) {
                Text("BERSAGLIO \(min(giro + 1, giri))/\(giri)").font(.system(size: 11, weight: .heavy)).tracking(1.5).foregroundStyle(Theme.dim)
                Text(testoBersaglio(bersaglio)).font(.system(size: 44, weight: .heavy, design: .monospaced))
                if let h = location.heading {
                    let vero = (h - (location.declinazione ?? 0) + 360).truncatingRemainder(dividingBy: 360)
                    let scarto = abs(((vero - Double(bersaglio)) + 540).truncatingRemainder(dividingBy: 360) - 180)
                    ZStack {
                        Circle().strokeBorder(Theme.stroke, lineWidth: 2).frame(width: 180, height: 180)
                        Image(systemName: "arrowtriangle.up.fill").font(.system(size: 30)).foregroundStyle(scarto <= tolleranza ? Theme.green : Theme.red)
                            .offset(y: -78).rotationEffect(.degrees(Double(bersaglio) - vero))
                        Text(livello == .difficile ? "—" : String(format: "%03.0f°", vero)).font(Theme.mono(22, .heavy))
                    }
                    .animation(.spring(response: 0.3), value: h)
                    Text(scarto <= tolleranza ? "TIENI FERMO…" : "Ruota finché il triangolo è in alto e verde").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(scarto <= tolleranza ? Theme.green : Theme.dim)
                        .onChange(of: scarto <= tolleranza) { ok in tenuto = ok ? Date() : nil }
                    TimelineView(.periodic(from: .now, by: 0.2)) { ctx in
                        let t = tenuto.map { ctx.date.timeIntervalSince($0) } ?? 0
                        ProgressView(value: min(1, t / 3)).tint(Theme.green).frame(maxWidth: 220)
                            .onChange(of: t >= 3) { fatto in if fatto { avanti() } }
                    }
                } else {
                    Text("Bussola non disponibile: calibrala muovendo il telefono a 8").foregroundStyle(Theme.amber)
                }
            }
        } indizi: {
            VStack(alignment: .leading, spacing: 6) {
                Indizio(n: 1, testo: "Tieni il telefono in piano davanti a te e ruota sul posto fino a puntare il bersaglio, poi resta fermo 3 secondi.")
                Indizio(n: 2, testo: "N 000 · NE 045 · E 090 · SE 135 · S 180 · SO 225 · O 270 · NO 315.")
                if livello != .facile { Indizio(n: 3, testo: "«SE +12°» = 135 + 12 = 147°. «Ritorno di X» = X ± 180°.") }
                if livello == .difficile { Indizio(n: 4, testo: "I gradi non sono a schermo: calcola il bersaglio a mente e fidati del triangolo.") }
            }
        }
    }

    func avanti() {
        tenuto = nil
        Suoni.ok()
        if giro + 1 < giri { withAnimation { giro += 1 } } else { fatta() }
    }
}

// MARK: - Sotto stress: calcolo rapido

struct DatiCalcolo {
    struct Conto { let testo: String; let risultato: Int }
    let conti: [Conto]

    init(_ l: LivelloProva, _ seme: UInt64) {
        var g = Dado(seme)
        let n = [0, 8, 12, 16][l.rawValue]
        var out: [Conto] = []
        for _ in 0..<n {
            let op = g.int(0...(l == .facile ? 1 : 3))
            switch op {
            case 0:
                let a = g.int(5...(l == .difficile ? 99 : 49)), b = g.int(5...(l == .difficile ? 99 : 49))
                out.append(Conto(testo: "\(a) + \(b)", risultato: a + b))
            case 1:
                let a = g.int(20...99), b = g.int(2...19)
                out.append(Conto(testo: "\(a) − \(b)", risultato: a - b))
            case 2:
                let a = g.int(2...(l == .difficile ? 19 : 12)), b = g.int(2...9)
                out.append(Conto(testo: "\(a) × \(b)", risultato: a * b))
            default:
                let b = g.int(2...9), r = g.int(2...12)
                out.append(Conto(testo: "\(b * r) ÷ \(b)", risultato: r))
            }
        }
        conti = out
    }
}

struct ProvaCalcolo: View {
    let d: DatiCalcolo
    var fatta: () -> Void
    @EnvironmentObject var s: SessioneProva
    @State private var n = 0
    @State private var r = ""

    var body: some View {
        LayoutProva {
            VStack(spacing: 14) {
                Text("\(n + 1)/\(d.conti.count)").font(Theme.mono(13, .bold)).foregroundStyle(Theme.dim)
                Text(d.conti[min(n, d.conti.count - 1)].testo).font(.system(size: 48, weight: .heavy, design: .monospaced))
                Text(r.isEmpty ? "?" : r).font(.system(size: 36, weight: .heavy, design: .monospaced)).foregroundStyle(Theme.oliveBright)
                TastierinoProva { k in
                    Suoni.tasto()
                    if k == -1 { if !r.isEmpty { r.removeLast() }; return }
                    if r.count < 4 { r.append(String(k)) }
                    let giusto = String(d.conti[n].risultato)
                    if r.count >= giusto.count {
                        if r == giusto { r = ""; if n + 1 < d.conti.count { n += 1 } else { fatta() } }
                        else { r = ""; s.sbaglia("Sbagliato") }
                    }
                }
            }
        } indizi: {
            VStack(alignment: .leading, spacing: 6) {
                Indizio(n: 1, testo: "Rispondi il più in fretta possibile: la risposta si controlla da sola appena hai scritto abbastanza cifre.")
                Indizio(n: 2, testo: "Da fare col fiatone: uno sprint di 20 m, poi un blocco di conti, poi ancora sprint.")
            }
        }
    }
}

// MARK: - Sotto stress: memoria a vista (cos'è cambiato?)

struct ProvaKim: View {
    let livello: LivelloProva
    let seme: UInt64
    var fatta: () -> Void
    @EnvironmentObject var s: SessioneProva
    @State private var giro = 0
    @State private var fase = 0          // 0 pronto, 1 guarda, 2 rispondi
    @State private var oggetti: [String] = []
    @State private var cambiato = 0
    @State private var dopo: [String] = []

    var giri: Int { [0, 3, 4, 5][livello.rawValue] }
    var quanti: Int { [0, 6, 9, 12][livello.rawValue] }
    var secondi: Double { [0, 6, 5, 3.5][livello.rawValue] }

    var body: some View {
        LayoutProva {
            VStack(spacing: 14) {
                Text("GIRO \(min(giro + 1, giri))/\(giri)").font(.system(size: 11, weight: .heavy)).tracking(1.5).foregroundStyle(Theme.dim)
                if fase == 0 {
                    Button { mostra() } label: { Label("Guarda", systemImage: "eye") }.buttonStyle(PrimaryButtonStyle()).frame(maxWidth: 300)
                } else {
                    Text(fase == 1 ? "MEMORIZZA" : "COSA È CAMBIATO? TOCCALO").font(.system(size: 14, weight: .heavy)).foregroundStyle(fase == 1 ? Theme.amber : Theme.oliveBright)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: quanti > 9 ? 4 : 3), spacing: 8) {
                        ForEach(0..<(fase == 1 ? oggetti : dopo).count, id: \.self) { i in
                            Button { if fase == 2 { scegli(i) } } label: {
                                Image(systemName: (fase == 1 ? oggetti : dopo)[i]).font(.system(size: 34))
                                    .frame(maxWidth: .infinity).frame(height: 76)
                                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(PressStyle()).tint(.white)
                        }
                    }
                    .frame(maxWidth: 420)
                }
            }
        } indizi: {
            VStack(alignment: .leading, spacing: 6) {
                Indizio(n: 1, testo: "Hai \(String(format: "%.1f", secondi).replacingOccurrences(of: ".", with: ",")) secondi per memorizzare \(quanti) oggetti e la loro posizione.")
                Indizio(n: 2, testo: "Poi un oggetto viene sostituito: tocca la casella cambiata.")
                Indizio(n: 3, testo: "Trucco: dividi la griglia in righe e ripeti a mente una parola per riga.")
            }
        }
    }

    @MainActor func mostra() {
        var g = Dado(seme &+ UInt64(giro * 7919))
        let tutti = DatiSimboli.insieme.shuffled(using: &g)
        oggetti = Array(tutti.prefix(quanti))
        cambiato = g.int(0...(quanti - 1))
        dopo = oggetti
        dopo[cambiato] = tutti[quanti]
        fase = 1
        Task {
            try? await Task.sleep(nanoseconds: UInt64(secondi * 1_000_000_000))
            fase = 2
        }
    }

    func scegli(_ i: Int) {
        if i == cambiato {
            Suoni.ok()
            if giro + 1 < giri { giro += 1; fase = 0 } else { fatta() }
        } else {
            s.sbaglia("Non era quello")
            fase = 0
        }
    }
}

// MARK: - Sotto stress: conta lampo

struct ProvaLampo: View {
    let livello: LivelloProva
    let seme: UInt64
    var fatta: () -> Void
    @EnvironmentObject var s: SessioneProva
    @State private var giro = 0
    @State private var fase = 0          // 0 pronto, 1 lampi, 2 risposta
    @State private var lampo: (String, Color)?
    @State private var giusti = 0
    @State private var domanda = ("", Color.red)

    var giri: Int { [0, 3, 4, 5][livello.rawValue] }
    var lampi: Int { [0, 8, 12, 16][livello.rawValue] }
    var durata: UInt64 { [0, 700, 500, 330][livello.rawValue] }
    let forme = ["triangle.fill", "circle.fill", "square.fill", "star.fill"]
    let colori: [(String, Color)] = [("rossi", .red), ("blu", .blue), ("gialli", .yellow), ("verdi", .green)]
    let nomiForme = ["triangoli", "cerchi", "quadrati", "stelle"]

    var body: some View {
        LayoutProva {
            VStack(spacing: 16) {
                Text("GIRO \(min(giro + 1, giri))/\(giri)").font(.system(size: 11, weight: .heavy)).tracking(1.5).foregroundStyle(Theme.dim)
                Text("Conta i \(nomeDomanda)").font(.system(size: 20, weight: .black))
                ZStack {
                    RoundedRectangle(cornerRadius: 18).fill(Color.black).frame(height: 200)
                    if let l = lampo { Image(systemName: l.0).font(.system(size: 110)).foregroundStyle(l.1) }
                }
                .frame(maxWidth: 360)
                if fase == 0 {
                    Button { parti() } label: { Label("Via ai lampi", systemImage: "bolt.fill") }.buttonStyle(PrimaryButtonStyle()).frame(maxWidth: 300)
                } else if fase == 2 {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                        ForEach(0...12, id: \.self) { k in
                            Button { rispondi(k) } label: {
                                Text("\(k)").font(.system(size: 26, weight: .heavy, design: .monospaced))
                                    .frame(maxWidth: .infinity).frame(height: 56)
                                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(PressStyle()).tint(.white)
                        }
                    }
                    .frame(maxWidth: 360)
                }
            }
        } indizi: {
            VStack(alignment: .leading, spacing: 6) {
                Indizio(n: 1, testo: "Compariranno \(lampi) forme colorate, una alla volta, molto in fretta.")
                Indizio(n: 2, testo: "Conta solo quelle richieste (forma E colore), poi scegli il numero.")
                Indizio(n: 3, testo: "Come riconoscere amico/nemico in un attimo: occhi sul bersaglio, niente pensieri.")
            }
        }
    }

    var nomeDomanda: String {
        let f = forme.firstIndex(of: domanda.0) ?? 0
        let c = colori.firstIndex { $0.1 == domanda.1 } ?? 0
        return "\(nomiForme[f]) \(colori[c].0)"
    }

    @MainActor func parti() {
        var g = Dado(seme &+ UInt64(giro * 104729))
        let qf = g.int(0...3), qc = g.int(0...3)
        domanda = (forme[qf], colori[qc].1)
        var seq: [(String, Color)] = []
        var conta = 0
        for _ in 0..<lampi {
            // più probabile la forma richiesta, per confondere
            let f = g.vero(0.45) ? qf : g.int(0...3)
            let c = g.vero(0.45) ? qc : g.int(0...3)
            seq.append((forme[f], colori[c].1))
            if f == qf && c == qc { conta += 1 }
        }
        giusti = conta
        fase = 1
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            for x in seq {
                lampo = x
                try? await Task.sleep(nanoseconds: durata * 1_000_000)
                lampo = nil
                try? await Task.sleep(nanoseconds: 180_000_000)
            }
            fase = 2
        }
    }

    func rispondi(_ k: Int) {
        if k == giusti {
            Suoni.ok()
            if giro + 1 < giri { giro += 1; fase = 0 } else { fatta() }
        } else {
            s.sbaglia("Erano \(giusti)")
            fase = 0
        }
    }
}
