import SwiftUI
import AudioToolbox
import Combine

// MARK: - Prove pronte: uno stock infinito di mini giochi generati dall'app.
// Il GM sceglie solo tipo e livello; la squadra risolve a tempo usando gli INDIZI, sempre a schermo.

/// generatore ripetibile: stesso seme = stessa prova (per rigiocarla o confrontare due squadre)
struct Dado: RandomNumberGenerator {
    var s: UInt64
    init(_ seme: UInt64) { s = seme &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        s &+= 0x9E37_79B9_7F4A_7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func int(_ r: ClosedRange<Int>) -> Int { Int.random(in: r, using: &self) }
    mutating func vero(_ p: Double = 0.5) -> Bool { Double.random(in: 0..<1, using: &self) < p }
    mutating func uno<T>(_ a: [T]) -> T { a[int(0...(a.count - 1))] }
}

enum LivelloProva: Int, CaseIterable, Identifiable, Codable {
    case facile = 1, medio, difficile
    var id: Int { rawValue }
    var nome: String { ["", "Facile", "Medio", "Difficile"][rawValue] }
    var colore: Color { [Color.clear, Theme.green, Theme.amber, Theme.red][rawValue] }
    /// secondi tolti a ogni errore
    var penalita: Double { [0, 15, 30, 45][rawValue] }
}

enum TipoProva: String, CaseIterable, Identifiable, Codable {
    case fili, simboli, lucchetto, cifrario, sequenza, memoria, quiz, griglia, interruttori, radio
    case labirinto, raggiungi, azimut, calcolo, kim, lampo
    var id: String { rawValue }
    enum Categoria: String, CaseIterable { case enigmi = "Enigmi e congegni", campo = "Da campo · GPS e bussola", stress = "Sotto stress" }
    var categoria: Categoria {
        switch self {
        case .raggiungi, .azimut: return .campo
        case .calcolo, .kim, .lampo, .memoria: return .stress
        default: return .enigmi
        }
    }
    /// si può giocare con il manuale su un secondo telefono
    var dueDispositivi: Bool { categoria != .campo }
    var nome: String {
        switch self {
        case .fili: return "Disinnesca la bomba"
        case .simboli: return "TastierinoProva a simboli"
        case .lucchetto: return "Lucchetto a enigmi"
        case .cifrario: return "Messaggio cifrato"
        case .sequenza: return "Sequenze logiche"
        case .memoria: return "Memoria sotto stress"
        case .quiz: return "Quiz tattico"
        case .griglia: return "Navigazione su griglia"
        case .interruttori: return "Quadro interruttori"
        case .radio: return "Frequenza radio"
        case .labirinto: return "Labirinto cieco"
        case .raggiungi: return "Raggiungi il punto"
        case .azimut: return "Punta l'azimut"
        case .calcolo: return "Calcolo rapido"
        case .kim: return "Memoria a vista"
        case .lampo: return "Conta lampo"
        }
    }
    var icona: String {
        switch self {
        case .fili: return "scissors"
        case .simboli: return "square.grid.2x2.fill"
        case .lucchetto: return "lock.fill"
        case .cifrario: return "envelope.badge.shield.half.filled"
        case .sequenza: return "number"
        case .memoria: return "brain.head.profile"
        case .quiz: return "questionmark.bubble.fill"
        case .griglia: return "map.fill"
        case .interruttori: return "switch.2"
        case .radio: return "antenna.radiowaves.left.and.right"
        case .labirinto: return "square.grid.3x3.middle.filled"
        case .raggiungi: return "figure.walk.motion"
        case .azimut: return "safari.fill"
        case .calcolo: return "plus.forwardslash.minus"
        case .kim: return "eye.square.fill"
        case .lampo: return "bolt.circle.fill"
        }
    }
    var descrizione: String {
        switch self {
        case .fili: return "Taglia il filo giusto seguendo le regole del manuale"
        case .simboli: return "Trova la colonna e premi i simboli nell'ordine giusto"
        case .lucchetto: return "Ogni cifra del codice è un enigma da risolvere"
        case .cifrario: return "Decifra la parola con il metodo indicato"
        case .sequenza: return "Trova il numero che continua la serie"
        case .memoria: return "Memorizza e ripeti la sequenza di colori"
        case .quiz: return "Domande da campo: NATO, radio, soccorso, orientamento"
        case .griglia: return "Segui gli spostamenti e trova la casella finale"
        case .interruttori: return "Metti gli interruttori come dicono gli indizi"
        case .radio: return "Decifra la parola e sintonizza la frequenza giusta"
        case .labirinto: return "Chi muove non vede i muri: il manuale lo guida a voce"
        case .raggiungi: return "Arriva su un punto con freccia, azimut o solo MGRS"
        case .azimut: return "Ruota sul posto e tieni la direzione giusta per 3 s"
        case .calcolo: return "Conti a raffica, anche col fiatone tra uno sprint e l'altro"
        case .kim: return "Memorizza la griglia e trova l'oggetto cambiato"
        case .lampo: return "Forme lampo: conta solo quelle richieste"
        }
    }
    /// tempo consigliato in minuti per livello
    func minuti(_ l: LivelloProva) -> Int {
        switch self {
        case .fili, .simboli, .memoria: return [0, 4, 3, 2][l.rawValue]
        case .quiz, .sequenza, .griglia, .radio: return [0, 6, 5, 4][l.rawValue]
        case .lucchetto, .cifrario, .interruttori: return [0, 8, 7, 6][l.rawValue]
        case .labirinto, .kim, .lampo, .calcolo: return [0, 4, 3, 3][l.rawValue]
        case .azimut: return [0, 4, 3, 3][l.rawValue]
        case .raggiungi: return [0, 5, 6, 8][l.rawValue]
        }
    }
}

enum Suoni {
    static func tasto() { AudioServicesPlaySystemSound(1104) }
    static func ok() { AudioServicesPlaySystemSound(1407); UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func errore() { AudioServicesPlaySystemSound(1053); UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func boom() { AudioServicesPlaySystemSound(1005); AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) }
}

let ordinali = ["primo", "secondo", "terzo", "quarto", "quinto", "sesto", "settimo", "ottavo"]
let ordinaliF = ["prima", "seconda", "terza", "quarta", "quinta", "sesta", "settima", "ottava"]

// MARK: - Sessione (tempo, errori, esito)

struct EsitoProva: Codable, Identifiable {
    var id = UUID()
    let tipo: TipoProva
    let livello: LivelloProva
    let data: Date
    let secondi: Int
    let errori: Int
    let vinta: Bool
    let squadra: String
}

@MainActor
final class StoricoProve: ObservableObject {
    static let shared = StoricoProve()
    @Published private(set) var esiti: [EsitoProva] = []
    init() {
        if let d = UserDefaults.standard.data(forKey: "prove.storico"), let e = try? JSONDecoder().decode([EsitoProva].self, from: d) { esiti = e }
    }
    func aggiungi(_ e: EsitoProva) {
        esiti.insert(e, at: 0)
        if esiti.count > 300 { esiti.removeLast(esiti.count - 300) }
        if let d = try? JSONEncoder().encode(esiti) { UserDefaults.standard.set(d, forKey: "prove.storico") }
    }
    func svuota() { esiti = []; UserDefaults.standard.removeObject(forKey: "prove.storico") }
}

final class SessioneProva: ObservableObject {
    enum Stato { case pronta, incorso, vinta, persa }
    @Published var stato = Stato.pronta
    @Published var fine = Date()
    @Published var errori = 0
    @Published var messaggio: String?
    let durata: Double
    let penalita: Double
    private(set) var inizio = Date()

    init(minuti: Int, livello: LivelloProva) {
        durata = Double(minuti * 60)
        penalita = livello.penalita
    }

    func parti() { inizio = Date(); fine = Date().addingTimeInterval(durata); stato = .incorso; Suoni.ok() }
    var restano: Double { max(0, fine.timeIntervalSinceNow) }
    var impiegati: Int { Int(Date().timeIntervalSince(inizio)) }

    func sbaglia(_ m: String = "Sbagliato") {
        guard stato == .incorso else { return }
        errori += 1
        fine = fine.addingTimeInterval(-penalita)
        messaggio = "\(m) · −\(Int(penalita)) s"
        Suoni.errore()
        if restano <= 0 { perdi() }
    }
    func vinci() { guard stato == .incorso else { return }; stato = .vinta; Suoni.ok() }
    func perdi() { guard stato == .incorso else { return }; stato = .persa; Suoni.boom() }
    func controllaTempo() { if stato == .incorso && fine.timeIntervalSinceNow <= 0 { perdi() } }
}

// MARK: - Scelta della prova (GM)

struct ProvePronteView: View {
    @State private var tipo: TipoProva?
    @State private var livello = LivelloProva.medio
    @State private var squadra = ""
    @State private var assalto = false
    @ObservedObject private var storico = StoricoProve.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Scegli il tipo di prova e il livello: l'app la genera nuova ogni volta. La squadra la risolve con gli indizi a schermo, contro il tempo; ogni errore toglie secondi.")
                    .font(.system(size: 13)).foregroundStyle(Theme.dim)
                Picker("Livello", selection: $livello) {
                    ForEach(LivelloProva.allCases) { l in Text(l.nome).tag(l) }
                }
                .pickerStyle(.segmented)
                TextField("Squadra (facoltativo, per lo storico)", text: $squadra)
                    .padding(10).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                Button { assalto = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "bolt.horizontal.fill").font(.system(size: 22)).foregroundStyle(.black)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Fase d'assalto").font(.system(size: 16, weight: .heavy)).foregroundStyle(.black)
                            Text("3 prove casuali di fila, tempo unico").font(.system(size: 12)).foregroundStyle(.black.opacity(0.7))
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.black)
                    }
                    .padding(14).background(Theme.olive, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(PressStyle())
                NavigationLink { ManualeProvaView() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "book.closed.fill").font(.system(size: 22)).foregroundStyle(Theme.amber).frame(width: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Sono il manuale (secondo telefono)").font(.system(size: 14.5, weight: .heavy)).foregroundStyle(.white)
                            Text("Inserisci il codice del congegno e vedi solo gli indizi").font(.system(size: 11.5)).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.dim)
                    }
                    .padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.amber.opacity(0.4)))
                }
                .buttonStyle(PressStyle())
                ForEach(TipoProva.Categoria.allCases, id: \.self) { cat in
                    EtichettaSezione(testo: cat.rawValue)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                        ForEach(Array(TipoProva.allCases.filter { $0.categoria == cat }.enumerated()), id: \.element) { i, t in
                            Button { haptic(); tipo = t } label: { scheda(t) }
                                .buttonStyle(PressStyle())
                                .comparsa(i)
                        }
                    }
                }
                if !storico.esiti.isEmpty {
                    EtichettaSezione(testo: "Ultimi risultati")
                    ForEach(storico.esiti.prefix(12)) { e in
                        HStack {
                            Image(systemName: e.vinta ? "checkmark.seal.fill" : "xmark.octagon.fill").foregroundStyle(e.vinta ? Theme.green : Theme.red)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(e.tipo.nome + (e.squadra.isEmpty ? "" : " · \(e.squadra)")).font(.system(size: 13, weight: .semibold))
                                Text("\(e.livello.nome) · \(e.data.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            Text(String(format: "%d:%02d", e.secondi / 60, e.secondi % 60)).font(Theme.mono(13, .bold))
                            Text("\(e.errori) err").font(Theme.mono(11)).foregroundStyle(e.errori > 0 ? Theme.amber : Theme.dim)
                        }
                        .padding(10).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Prove pronte")
        .fullScreenCover(item: $tipo) { t in
            PartitaProva(tipi: [t], livello: livello, squadra: squadra) { tipo = nil }
        }
        .fullScreenCover(isPresented: $assalto) {
            PartitaProva(tipi: Array(TipoProva.allCases.filter { $0 != .quiz && $0.categoria != .campo }.shuffled().prefix(3)), livello: livello, squadra: squadra) { assalto = false }
        }
    }

    func scheda(_ t: TipoProva) -> some View {
        HStack(spacing: 12) {
            Image(systemName: t.icona).font(.system(size: 22)).foregroundStyle(Theme.oliveBright).frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.nome).font(.system(size: 14.5, weight: .heavy)).foregroundStyle(.white)
                Text(t.descrizione).font(.system(size: 11.5)).foregroundStyle(Theme.dim).lineLimit(2).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Text("\(t.minuti(livello))′").font(Theme.mono(12, .bold)).foregroundStyle(livello.colore)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.stroke))
    }
}

// MARK: - Partita: tempo in alto, dispositivo + indizi sempre visibili

struct PartitaProva: View {
    let tipi: [TipoProva]
    let livello: LivelloProva
    let squadra: String
    var chiudi: () -> Void
    @StateObject private var s: SessioneProva
    @State private var indice = 0
    @State private var seme = UInt64.random(in: 1...0xFF_FFFF)
    @State private var chiediEsci = false
    @State private var dueTelefoni = false
    private let orologio = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    init(tipi: [TipoProva], livello: LivelloProva, squadra: String, chiudi: @escaping () -> Void) {
        self.tipi = tipi; self.livello = livello; self.squadra = squadra; self.chiudi = chiudi
        let minuti = tipi.reduce(0) { $0 + $1.minuti(livello) }
        _s = StateObject(wrappedValue: SessioneProva(minuti: minuti, livello: livello))
    }

    var tipo: TipoProva { tipi[min(indice, tipi.count - 1)] }

    var body: some View {
        VStack(spacing: 0) {
            testata
            Group {
                switch s.stato {
                case .pronta: pronta
                case .incorso:
                    VistaProva.crea(tipo, livello, seme) { prossima() }
                        .id("\(indice)-\(seme)")
                        .environment(\.modoProva, dueTelefoni && tipo.dueDispositivi ? .dispositivo : .entrambi)
                case .vinta, .persa: risultato
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
        .environmentObject(s)
        .onReceive(orologio) { _ in s.controllaTempo() }
        .onChange(of: s.stato) { st in if st == .vinta || st == .persa { registra() } }
        .confirmationDialog("Abbandonare la prova?", isPresented: $chiediEsci, titleVisibility: .visible) {
            Button("Abbandona", role: .destructive) { chiudi() }
        }
    }

    var testata: some View {
        HStack(spacing: 12) {
            Button { if s.stato == .incorso { chiediEsci = true } else { chiudi() } } label: {
                Label("Indietro", systemImage: "chevron.left").font(.system(size: 15, weight: .bold))
            }
            .tint(.white)
            VStack(alignment: .leading, spacing: 0) {
                Text(tipi.count > 1 ? "FASE \(indice + 1)/\(tipi.count) · \(tipo.nome.uppercased())" : tipo.nome.uppercased())
                    .font(.system(size: 11, weight: .heavy)).tracking(1).foregroundStyle(Theme.dim).lineLimit(1)
                Text(livello.nome.uppercased()).font(.system(size: 10, weight: .heavy)).foregroundStyle(livello.colore)
            }
            Spacer()
            if dueTelefoni && tipo.dueDispositivi && s.stato != .pronta {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("CODICE MANUALE").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(Theme.dim)
                    Text(CodiceProva.crea(tipo, livello, seme)).font(Theme.mono(15, .heavy)).foregroundStyle(Theme.amber)
                }
            }
            if s.errori > 0 { Label("\(s.errori)", systemImage: "xmark.circle.fill").font(Theme.mono(14, .bold)).foregroundStyle(Theme.red) }
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let r = s.stato == .pronta ? s.durata : s.restano
                Text(String(format: "%02d:%02d", Int(r) / 60, Int(r) % 60))
                    .font(.system(size: 30, weight: .heavy, design: .monospaced))
                    .foregroundStyle(r < 30 && s.stato == .incorso ? Theme.red : .white)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            if let m = s.messaggio {
                Text(m).font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 6).background(Theme.red, in: Capsule())
                    .offset(y: 22)
                    .transition(.scale.combined(with: .opacity))
                    .task(id: s.errori) { try? await Task.sleep(nanoseconds: 1_600_000_000); withAnimation { s.messaggio = nil } }
            }
        }
        .zIndex(2)
        .animation(.spring(response: 0.3), value: s.messaggio)
    }

    var pronta: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: tipo.icona).font(.system(size: 64)).foregroundStyle(Theme.oliveBright)
            Text(tipi.count > 1 ? "Fase d'assalto: \(tipi.map(\.nome).joined(separator: " → "))" : tipo.nome)
                .font(.system(size: 22, weight: .black)).multilineTextAlignment(.center)
            Text(tipo.descrizione + ".\nGli indizi restano sempre a schermo. Ogni errore: −\(Int(livello.penalita)) secondi.")
                .font(.system(size: 14)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            if tipi.contains(where: \.dueDispositivi) {
                Toggle(isOn: $dueTelefoni) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Manuale su un secondo telefono").font(.system(size: 14, weight: .bold))
                        Text("Qui solo il congegno; l'altro inserisce il codice in «Sono il manuale»").font(.caption).foregroundStyle(Theme.dim)
                    }
                }
                .tint(Theme.olive).frame(maxWidth: 420)
                if dueTelefoni {
                    Text("Codice: \(CodiceProva.crea(tipo, livello, seme))").font(Theme.mono(22, .heavy)).foregroundStyle(Theme.amber)
                }
            }
            Button { s.parti() } label: { Label("VIA", systemImage: "play.fill").font(.system(size: 20, weight: .black)).frame(maxWidth: 320) }
                .buttonStyle(PrimaryButtonStyle())
            Spacer()
        }
        .padding(24)
    }

    func prossima() {
        if indice + 1 < tipi.count {
            Suoni.ok()
            withAnimation(.spring(response: 0.4)) { indice += 1; seme = UInt64.random(in: 1...0xFF_FFFF) }
        } else {
            s.vinci()
        }
    }

    var risultato: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: s.stato == .vinta ? "checkmark.seal.fill" : "flame.fill")
                .font(.system(size: 90)).foregroundStyle(s.stato == .vinta ? Theme.green : Theme.red)
            Text(s.stato == .vinta ? "SUPERATA" : (s.restano <= 0 ? "TEMPO SCADUTO" : "FALLITA"))
                .font(.system(size: 38, weight: .black)).foregroundStyle(s.stato == .vinta ? Theme.green : Theme.red)
            Text("Tempo: \(String(format: "%d:%02d", s.impiegati / 60, s.impiegati % 60)) · errori: \(s.errori)")
                .font(Theme.mono(16, .bold))
            HStack(spacing: 10) {
                Button { rigioca() } label: { Label("Nuova prova", systemImage: "arrow.clockwise").frame(maxWidth: .infinity) }
                    .buttonStyle(PrimaryButtonStyle())
                Button { chiudi() } label: { Text("Fine").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).tint(Theme.olive)
            }
            .frame(maxWidth: 420)
            Spacer()
        }
        .padding(24)
    }

    func rigioca() {
        indice = 0; seme = UInt64.random(in: 1...0xFF_FFFF)
        s.errori = 0; s.stato = .pronta
    }

    func registra() {
        StoricoProve.shared.aggiungi(EsitoProva(tipo: tipi.count > 1 ? tipi[0] : tipo, livello: livello, data: Date(), secondi: s.impiegati,
                                                errori: s.errori, vinta: s.stato == .vinta, squadra: squadra))
    }
}

/// dispositivo e indizi: affiancati su schermo largo, uno sotto l'altro sul telefono (gli indizi restano sempre visibili)
struct LayoutProva<D: View, I: View>: View {
    @ViewBuilder var dispositivo: D
    @ViewBuilder var indizi: I
    @Environment(\.modoProva) private var modo
    var body: some View {
        GeometryReader { g in
            if modo == .dispositivo {
                ScrollView { dispositivo.padding(16).frame(maxWidth: 640).frame(maxWidth: .infinity) }
            } else if modo == .manuale {
                pannelloIndizi.padding(14).frame(maxWidth: 760).frame(maxWidth: .infinity)
            } else if g.size.width > 700 {
                HStack(alignment: .top, spacing: 14) {
                    ScrollView { dispositivo.padding(16) }.frame(width: g.size.width * 0.52)
                    pannelloIndizi
                }
                .padding(.trailing, 14).padding(.top, 10)
            } else {
                VStack(spacing: 0) {
                    ScrollView { dispositivo.padding(14) }.frame(height: g.size.height * 0.55)
                    pannelloIndizi.padding(.horizontal, 10).padding(.bottom, 6)
                }
            }
        }
    }
    var pannelloIndizi: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("INDIZI", systemImage: "lightbulb.fill").font(.system(size: 12, weight: .heavy)).tracking(1.2).foregroundStyle(Theme.amber)
            ScrollView { indizi.frame(maxWidth: .infinity, alignment: .leading) }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.amber.opacity(0.35)))
    }
}

/// riga di indizio numerata
struct Indizio: View {
    let n: Int
    let testo: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)").font(Theme.mono(12, .heavy)).foregroundStyle(.black).frame(width: 22, height: 22).background(Theme.amber, in: Circle())
            Text(testo).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 1. Disinnesca la bomba (fili)

struct DatiFili {
    static let colori: [(String, Color)] = [("ROSSO", .red), ("BLU", .blue), ("GIALLO", .yellow), ("BIANCO", .white), ("NERO", Color(white: 0.25)), ("VERDE", .green)]
    let fili: [Int]
    let matricola: String
    let spia: Bool
    let regole: [String]
    let giusto: Int
    let esplodeSubito: Bool

    init(_ l: LivelloProva, _ seme: UInt64) {
        var g = Dado(seme)
        let n = [0, 4, 5, 6][l.rawValue] + (l == .facile ? g.int(0...0) : g.int(0...1))
        let f = (0..<n).map { _ in g.int(0...5) }
        let lettere = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
        var m = "JS-"
        for i in 0..<5 { m.append(i % 2 == 0 ? String(g.int(0...9)) : String(lettere[g.int(0...(lettere.count - 1))])) }
        m.append(String(g.int(0...9)))
        let spia = g.vero()
        let ultimaDispari = (Int(String(m.last!)) ?? 0) % 2 == 1
        let vocale = m.contains { "AEIOU".contains($0) }
        let nomi = DatiFili.colori.map(\.0)

        // regole candidate: (testo, vale, filo da tagliare)
        var cand: [(String, Bool, Int)] = []
        for _ in 0..<14 {
            let c = g.int(0...5), k = g.int(0...(n - 1))
            let conta = f.filter { $0 == c }.count
            switch g.int(0...7) {
            case 0: cand.append(("Se non c'è nessun filo \(nomi[c]) → taglia il \(ordinali[k]) filo.", conta == 0, k))
            case 1: cand.append(("Se c'è più di un filo \(nomi[c]) → taglia l'ultimo filo \(nomi[c]).", conta > 1, f.lastIndex(of: c) ?? 0))
            case 2: cand.append(("Se l'ultimo filo è \(nomi[c]) → taglia l'ultimo filo.", f.last == c, n - 1))
            case 3: cand.append(("Se l'ultima cifra della matricola è dispari → taglia il \(ordinali[k]) filo.", ultimaDispari, k))
            case 4: cand.append(("Se la spia ARM è accesa e c'è almeno un filo \(nomi[c]) → taglia il primo filo \(nomi[c]).", spia && conta > 0, f.firstIndex(of: c) ?? 0))
            case 5:
                let q = g.int(1...2)
                cand.append(("Se ci sono esattamente \(q) fili \(nomi[c]) → taglia il \(ordinali[k]) filo.", conta == q, k))
            case 6: cand.append(("Se il primo filo è \(nomi[c]) → taglia il secondo filo.", f.first == c, 1))
            default: cand.append(("Se la matricola contiene una vocale → taglia il penultimo filo.", vocale, n - 2))
            }
        }
        var visti = Set<String>()
        cand = cand.filter { visti.insert($0.0).inserted }
        let quante = [0, 3, 4, 6][l.rawValue]
        var scelte = Array(cand.prefix(quante))
        // almeno metà delle volte deve scattare una regola prima di quella finale
        if !scelte.isEmpty, !scelte.contains(where: { $0.1 }), let vera = cand.dropFirst(quante).first(where: { $0.1 }), g.vero(0.6) {
            scelte[g.int(0...(scelte.count - 1))] = vera
        }
        let k = g.int(0...(n - 1))
        let giusto = scelte.first(where: { $0.1 })?.2 ?? k
        fili = f; matricola = m; self.spia = spia
        regole = scelte.map { $0.0 } + ["In tutti gli altri casi → taglia il \(ordinali[k]) filo."]
        self.giusto = giusto
        esplodeSubito = l == .difficile
    }
}

struct ProvaFili: View {
    let d: DatiFili
    var fatta: () -> Void
    @EnvironmentObject var s: SessioneProva
    @State private var tagliati: Set<Int> = []

    var body: some View {
        LayoutProva {
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MATRICOLA").font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.dim)
                        Text(d.matricola).font(Theme.mono(20, .heavy))
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Circle().fill(d.spia ? Theme.red : Color(white: 0.2)).frame(width: 16, height: 16)
                            .shadow(color: d.spia ? Theme.red : .clear, radius: 8)
                        Text("ARM").font(Theme.mono(13, .heavy))
                    }
                }
                .padding(12).background(Color.black, in: RoundedRectangle(cornerRadius: 12))
                VStack(spacing: 10) {
                    ForEach(0..<d.fili.count, id: \.self) { i in
                        let col = DatiFili.colori[d.fili[i]].1
                        Button { taglia(i) } label: {
                            HStack(spacing: 8) {
                                Text("\(i + 1)").font(Theme.mono(12, .heavy)).foregroundStyle(Theme.dim).frame(width: 18)
                                if tagliati.contains(i) {
                                    Capsule().fill(col).frame(height: 12)
                                    Image(systemName: "scissors").foregroundStyle(.white)
                                    Capsule().fill(col.opacity(0.3)).frame(height: 12)
                                } else {
                                    Capsule().fill(col).frame(height: 12).shadow(color: col.opacity(0.5), radius: 3)
                                }
                            }
                            .frame(height: 46).padding(.horizontal, 10)
                            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(tagliati.contains(i))
                        .accessibilityLabel("Filo \(i + 1) \(DatiFili.colori[d.fili[i]].0)")
                    }
                }
                Text("Tocca un filo per tagliarlo." + (d.esplodeSubito ? " Al primo errore esplode." : ""))
                    .font(.caption).foregroundStyle(Theme.dim)
            }
        } indizi: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Manuale di disinnesco · bomba a \(d.fili.count) fili").font(.system(size: 14, weight: .heavy))
                Text("Controlla le regole IN ORDINE: applica la prima che vale.").font(.caption).foregroundStyle(Theme.dim)
                ForEach(Array(d.regole.enumerated()), id: \.offset) { i, r in Indizio(n: i + 1, testo: r) }
                Text("I fili si contano dall'alto (1) verso il basso.").font(.caption).foregroundStyle(Theme.dim)
            }
        }
    }

    func taglia(_ i: Int) {
        haptic(.heavy)
        tagliati.insert(i)
        if i == d.giusto { fatta() } else if d.esplodeSubito { s.perdi() } else { s.sbaglia("Filo sbagliato") }
    }
}

// MARK: - 2. TastierinoProva a simboli

struct DatiSimboli {
    static let insieme = ["star.fill", "moon.fill", "sun.max.fill", "bolt.fill", "flame.fill", "drop.fill", "leaf.fill", "snowflake",
                          "cloud.fill", "heart.fill", "suit.club.fill", "suit.spade.fill", "suit.diamond.fill", "triangle.fill", "hexagon.fill",
                          "seal.fill", "shield.fill", "eye.fill", "hand.raised.fill", "key.fill", "lock.fill", "bell.fill", "flag.fill",
                          "scope", "atom", "hourglass", "crown.fill", "pawprint.fill", "ant.fill", "tortoise.fill", "hare.fill",
                          "umbrella.fill", "gift.fill", "music.note", "gearshape.fill", "paperplane.fill", "cross.fill", "staroflife.fill"]
    let colonne: [[String]]
    let tasti: [String]
    let ordine: [String]

    init(_ l: LivelloProva, _ seme: UInt64) {
        var g = Dado(seme)
        let nCol = [0, 4, 5, 6][l.rawValue], quanti = [0, 3, 4, 5][l.rawValue]
        var cols: [[String]] = []
        var sel: [String] = []
        var col = 0
        for _ in 0..<50 {
            cols = (0..<nCol).map { _ in Array(DatiSimboli.insieme.shuffled(using: &g).prefix(7)) }
            col = g.int(0...(nCol - 1))
            let pos = Array(Array(0..<7).shuffled(using: &g).prefix(quanti)).sorted()
            sel = pos.map { cols[col][$0] }
            let unico = cols.enumerated().allSatisfy { j, c in j == col || !sel.allSatisfy { c.contains($0) } }
            if unico { break }
        }
        colonne = cols
        ordine = sel
        tasti = sel.shuffled(using: &g)
    }
}

struct ProvaSimboli: View {
    let d: DatiSimboli
    var fatta: () -> Void
    @EnvironmentObject var s: SessioneProva
    @State private var premuti: [String] = []

    var body: some View {
        LayoutProva {
            VStack(spacing: 14) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: d.tasti.count > 4 ? 3 : 2), spacing: 10) {
                    ForEach(d.tasti, id: \.self) { t in
                        Button { premi(t) } label: {
                            Image(systemName: t).font(.system(size: 38))
                                .frame(maxWidth: .infinity).frame(height: 92)
                                .foregroundStyle(premuti.contains(t) ? Theme.green : .white)
                                .background(premuti.contains(t) ? Theme.green.opacity(0.15) : Theme.surface2, in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(premuti.contains(t) ? Theme.green : Theme.stroke, lineWidth: 1.5))
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                Text("Premuti \(premuti.count)/\(d.ordine.count)").font(Theme.mono(13, .bold)).foregroundStyle(Theme.dim)
            }
        } indizi: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Trova l'unica colonna che contiene TUTTI i simboli del tastierino, poi premili nell'ordine in cui compaiono in quella colonna (dall'alto in basso).")
                    .font(.system(size: 13.5))
                HStack(alignment: .top, spacing: 10) {
                    ForEach(0..<d.colonne.count, id: \.self) { c in
                        VStack(spacing: 6) {
                            Text("\(c + 1)").font(Theme.mono(11, .heavy)).foregroundStyle(Theme.dim)
                            ForEach(d.colonne[c], id: \.self) { sm in Image(systemName: sm).font(.system(size: 19)).frame(height: 24) }
                        }
                        .padding(6).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    func premi(_ t: String) {
        guard !premuti.contains(t) else { return }
        Suoni.tasto()
        if d.ordine[premuti.count] == t {
            premuti.append(t)
            if premuti.count == d.ordine.count { fatta() }
        } else {
            premuti = []
            s.sbaglia("Ordine sbagliato")
        }
    }
}

// MARK: - 3. Lucchetto a enigmi

struct DatiLucchetto {
    let codice: [Int]
    let indizi: [String]

    static let fatti: [Int: [String]] = [
        0: ["gli angoli di un cerchio", "le ruote di una barca"],
        1: ["le lune della Terra", "il naso di un operatore"],
        2: ["le ali di un uccello", "i piatti di una bilancia"],
        3: ["i lati di un triangolo", "i colori di un semaforo"],
        4: ["i punti cardinali", "i lati di un quadrato", "le zampe di un cane"],
        5: ["le dita di una mano", "i lati di un pentagono", "i cerchi olimpici"],
        6: ["i lati di un esagono", "le facce di un dado", "le zampe di un insetto"],
        7: ["i giorni della settimana", "i colori dell'arcobaleno", "le note musicali"],
        8: ["le zampe di un ragno", "i lati di un ottagono", "i bit di un byte"],
        9: ["i pianeti del sistema solare… meno Plutone che non conta più, più 1", "le caselle di un tris"],
    ]
    static let parole = ["RADIO", "MAPPA", "BUSSOLA", "ZAINO", "ELMETTO", "TATTICA", "OBIETTIVO", "PATTUGLIA", "AGGUATO", "RECON",
                         "SQUADRA", "ESFILTRAZIONE", "SENTINELLA", "BINOCOLO", "CODICE", "VALICO", "TRINCEA", "RADAR", "OMBRA", "ALBA"]

    init(_ l: LivelloProva, _ seme: UInt64) {
        var g = Dado(seme)
        let n = [0, 3, 4, 5][l.rawValue]
        let c = (0..<n).map { _ in g.int(0...9) }
        var ind: [String] = []
        for (i, v) in c.enumerated() {
            let pos = "La \(ordinaliF[i]) cifra"
            var t = ""
            // nel difficile alcune cifre dipendono da quelle prima
            if l == .difficile, i > 0, g.vero(0.4) {
                let j = g.int(0...(i - 1)), diff = v - c[j]
                let pj = ordinaliF[j]
                t = diff == 0 ? "\(pos) è uguale alla \(pj)." : (diff > 0 ? "\(pos) è la \(pj) più \(diff)." : "\(pos) è la \(pj) meno \(-diff).")
            } else {
                switch g.int(0...(l == .facile ? 2 : 5)) {
                case 0:
                    let a = g.int(2...9), b = g.int(2...9)
                    let k = a * b - v
                    t = "\(pos) è \(a) × \(b) − \(k)."
                case 1:
                    t = "\(pos) è come \(g.uno(DatiLucchetto.fatti[v] ?? ["\(v)"]))."
                case 2:
                    let k = g.int(1...20)
                    t = "\(pos) è \(v + k) − \(k)."
                case 3:
                    let m = g.int(max(v + 1, 5)...11), q = g.int(3...12)
                    t = "\(pos) è il resto di \(m * q + v) diviso \(m)."
                case 4:
                    let lunghe = DatiLucchetto.parole.filter { $0.count % 10 == v }
                    if let p = lunghe.isEmpty ? nil : g.uno(lunghe) {
                        t = "\(pos) è l'ultima cifra del numero di lettere di \"\(p)\"."
                    } else {
                        t = "\(pos) è la metà di \(v * 2)."
                    }
                default:
                    if v >= 1 {
                        let a = g.int(max(1, v - 9)...min(9, v)), b = v - a
                        t = "\(pos) è la somma delle cifre di \(a * 10 + b)."
                    } else {
                        t = "\(pos) è il risultato di \(g.int(2...9)) × 0."
                    }
                }
            }
            ind.append(t)
        }
        codice = c
        indizi = ind
    }
}

struct ProvaLucchetto: View {
    let d: DatiLucchetto
    var fatta: () -> Void
    @EnvironmentObject var s: SessioneProva
    @State private var cifre: [Int] = []

    var body: some View {
        LayoutProva {
            VStack(spacing: 16) {
                Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(Theme.amber)
                HStack(spacing: 10) {
                    ForEach(0..<d.codice.count, id: \.self) { i in
                        Text(i < cifre.count ? "\(cifre[i])" : "–")
                            .font(.system(size: 40, weight: .heavy, design: .monospaced))
                            .frame(width: 54, height: 70)
                            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                TastierinoProva { n in
                    Suoni.tasto()
                    if n == -1 { if !cifre.isEmpty { cifre.removeLast() } ; return }
                    guard cifre.count < d.codice.count else { return }
                    cifre.append(n)
                    if cifre.count == d.codice.count {
                        if cifre == d.codice { fatta() } else { s.sbaglia("Codice errato"); cifre = [] }
                    }
                }
            }
        } indizi: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Combinazione di \(d.codice.count) cifre").font(.system(size: 14, weight: .heavy))
                ForEach(Array(d.indizi.enumerated()), id: \.offset) { i, t in Indizio(n: i + 1, testo: t) }
            }
        }
    }
}

struct TastierinoProva: View {
    var premi: (Int) -> Void
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9, -2, 0, -1], id: \.self) { n in
                if n == -2 { Color.clear.frame(height: 56) } else {
                    Button { premi(n) } label: {
                        Group { if n == -1 { Image(systemName: "delete.left.fill") } else { Text("\(n)") } }
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .frame(maxWidth: .infinity).frame(height: 56)
                            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(PressStyle()).tint(.white)
                }
            }
        }
        .frame(maxWidth: 320)
    }
}

// MARK: - 4. Messaggio cifrato

enum AlfabetoProve {
    static let lettere = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    static let nato = ["Alfa", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel", "India", "Juliett", "Kilo", "Lima", "Mike",
                       "November", "Oscar", "Papa", "Quebec", "Romeo", "Sierra", "Tango", "Uniform", "Victor", "Whiskey", "X-ray", "Yankee", "Zulu"]
    static let morse = [".-", "-...", "-.-.", "-..", ".", "..-.", "--.", "....", "..", ".---", "-.-", ".-..", "--", "-.", "---", ".--.", "--.-",
                        ".-.", "...", "-", "..-", "...-", ".--", "-..-", "-.--", "--.."]
    static func indice(_ c: Character) -> Int? { lettere.firstIndex(of: c) }
    static func sposta(_ c: Character, _ k: Int) -> Character {
        guard let i = indice(c) else { return c }
        return lettere[((i + k) % 26 + 26) % 26]
    }
}

struct DatiCifrario {
    enum Metodo { case nato, cesare(Int), numeri(Int), atbash, morse, cesareNascosto(Int, String), vigenere(String) }
    let parola: String
    let cifrato: String
    let metodo: Metodo
    let spiegazione: [String]

    init(_ l: LivelloProva, _ seme: UInt64) {
        var g = Dado(seme)
        let p = g.uno(DatiLucchetto.parole.filter { l == .facile ? $0.count <= 7 : true })
        let m: Metodo
        let k1 = g.int(1...5), k2 = g.int(2...6), k3 = g.int(7...11)
        let parolaChiave = g.uno(DatiLucchetto.parole.filter { $0.count >= 3 && $0.count <= 9 })
        let chiaveV = g.uno(["ALFA", "ROMA", "LUPO", "FUOCO", "NOTTE", "JSOC"])
        let scelta = g.int(0...3)
        switch l {
        case .facile: m = [Metodo.nato, .cesare(k1), .numeri(0)][scelta % 3]
        case .medio: m = [Metodo.atbash, .morse, .cesareNascosto(parolaChiave.count, parolaChiave), .numeri(k2)][scelta]
        case .difficile: m = [Metodo.vigenere(chiaveV), .cesareNascosto(k3, ""), .morse][scelta % 3]
        }
        var c = ""
        var sp: [String] = []
        switch m {
        case .nato:
            c = p.map { AlfabetoProve.nato[AlfabetoProve.indice($0) ?? 0] }.joined(separator: " ")
            sp = ["AlfabetoProve fonetico NATO: ogni parola è la sua iniziale."]
        case .cesare(let k):
            c = String(p.map { AlfabetoProve.sposta($0, k) })
            sp = ["Cifrario di Cesare: ogni lettera è stata spostata AVANTI di \(k) posizioni.", "Per decifrare sposta ogni lettera INDIETRO di \(k)."]
        case .cesareNascosto(let k, let parola):
            c = String(p.map { AlfabetoProve.sposta($0, k) })
            sp = ["Cifrario di Cesare: ogni lettera è stata spostata avanti.",
                  parola.isEmpty ? "La chiave è il numero di mesi dell'anno meno \(12 - k)." : "La chiave è il numero di lettere della parola \"\(parola)\"."]
        case .numeri(let k):
            c = p.map { String((AlfabetoProve.indice($0) ?? 0) + 1 + k) }.joined(separator: " ")
            sp = [k == 0 ? "Ogni numero è la posizione della lettera nell'alfabeto: A=1, B=2 … Z=26." : "Ogni numero è la posizione della lettera nell'alfabeto (A=1 … Z=26) PIÙ \(k)."]
        case .atbash:
            c = String(p.map { AlfabetoProve.lettere[25 - (AlfabetoProve.indice($0) ?? 0)] })
            sp = ["Atbash: l'alfabeto è rovesciato. A↔Z, B↔Y, C↔X, D↔W …"]
        case .morse:
            c = p.map { AlfabetoProve.morse[AlfabetoProve.indice($0) ?? 0] }.joined(separator: "  /  ")
            sp = ["Codice Morse: le lettere sono separate da /."]
        case .vigenere(let chiave):
            let k = Array(chiave)
            c = String(p.enumerated().map { i, ch in AlfabetoProve.sposta(ch, AlfabetoProve.indice(k[i % k.count]) ?? 0) })
            sp = ["Vigenère con chiave \"\(chiave)\": la chiave si ripete sotto il messaggio (\(chiave)\(chiave)…).",
                  "Ogni lettera è stata spostata avanti del valore della lettera di chiave sotto di lei (A=0, B=1 … Z=25).",
                  "Per decifrare: sposta INDIETRO ogni lettera del valore della sua lettera di chiave."]
        }
        parola = p; cifrato = c; metodo = m; spiegazione = sp
    }

    var tabella: String {
        switch metodo {
        case .nato: return zip(AlfabetoProve.lettere, AlfabetoProve.nato).map { "\($0) \($1)" }.joined(separator: " · ")
        case .morse: return zip(AlfabetoProve.lettere, AlfabetoProve.morse).map { "\($0) \($1)" }.joined(separator: "   ")
        default:
            return AlfabetoProve.lettere.enumerated().map { i, c in "\(c)=\(i)" }.joined(separator: " ")
        }
    }
}

struct ProvaCifrario: View {
    let d: DatiCifrario
    var fatta: () -> Void
    @EnvironmentObject var s: SessioneProva
    @State private var risposta = ""

    var body: some View {
        LayoutProva {
            VStack(spacing: 16) {
                Text("MESSAGGIO INTERCETTATO").font(.system(size: 11, weight: .heavy)).tracking(1.5).foregroundStyle(Theme.dim)
                Text(d.cifrato).font(.system(size: 24, weight: .heavy, design: .monospaced)).multilineTextAlignment(.center)
                    .padding(16).frame(maxWidth: .infinity).background(Color.black, in: RoundedRectangle(cornerRadius: 12))
                    .textSelection(.enabled)
                Text("La parola in chiaro ha \(d.parola.count) lettere").font(.caption).foregroundStyle(Theme.dim)
                TextField("Parola decifrata", text: $risposta)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .font(Theme.mono(22, .bold)).multilineTextAlignment(.center)
                    .padding(12).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                    .onSubmit { verifica() }
                Button { verifica() } label: { Label("Verifica", systemImage: "checkmark.shield") }.buttonStyle(PrimaryButtonStyle())
            }
        } indizi: {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(d.spiegazione.enumerated()), id: \.offset) { i, t in Indizio(n: i + 1, testo: t) }
                Text("Tabella").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.dim).padding(.top, 4)
                Text(d.tabella).font(Theme.mono(13)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func verifica() {
        let r = risposta.uppercased().filter { $0.isLetter }
        if r == d.parola { fatta() } else { s.sbaglia("Parola errata") }
    }
}

// MARK: - 5. Sequenze logiche

struct DatiSequenze {
    struct Serie { let termini: [Int]; let prossimo: Int; let aiuto: String }
    let serie: [Serie]

    init(_ l: LivelloProva, _ seme: UInt64) {
        var g = Dado(seme)
        let quante = [0, 3, 4, 5][l.rawValue]
        var out: [Serie] = []
        for _ in 0..<quante {
            let tipo = g.int(0...(l == .facile ? 2 : (l == .medio ? 5 : 7)))
            var t: [Int] = []
            var aiuto = ""
            switch tipo {
            case 0:
                let a = g.int(1...20), d = g.int(2...9)
                t = (0..<7).map { a + d * $0 }; aiuto = "si aggiunge sempre lo stesso numero"
            case 1:
                let a = g.int(60...120), d = g.int(3...9)
                t = (0..<7).map { a - d * $0 }; aiuto = "si toglie sempre lo stesso numero"
            case 2:
                let a = g.int(1...4), r = g.int(2...3)
                t = (0..<7).map { a * Int(pow(Double(r), Double($0))) }; aiuto = "si moltiplica sempre per lo stesso numero"
            case 3:
                let a = g.int(1...9)
                var x = a; t = []
                for i in 0..<7 { t.append(x); x += i + 1 }
                aiuto = "si aggiunge 1, poi 2, poi 3…"
            case 4:
                let a = g.int(1...5), b = g.int(1...5)
                t = [a, b]; for _ in 2..<7 { t.append(t[t.count - 1] + t[t.count - 2]) }
                aiuto = "ogni numero è la somma dei due precedenti"
            case 5:
                let c = g.int(0...5)
                t = (1...7).map { $0 * $0 + c }; aiuto = "quadrati (1, 4, 9, 16…) più qualcosa"
            case 6:
                let a = g.int(2...9), d1 = g.int(2...5), b = g.int(30...50), d2 = g.int(2...5)
                t = (0..<7).map { $0 % 2 == 0 ? a + d1 * ($0 / 2) : b - d2 * ($0 / 2) }; aiuto = "sono due serie alternate"
            default:
                let a = g.int(1...3), r = g.int(2...3), k = g.int(1...3)
                var x = a; t = []
                for _ in 0..<7 { t.append(x); x = x * r + k }
                aiuto = "si moltiplica e poi si aggiunge"
            }
            out.append(Serie(termini: Array(t.prefix(6)), prossimo: t[6], aiuto: aiuto))
        }
        serie = out
    }
}

struct ProvaSequenze: View {
    let d: DatiSequenze
    var fatta: () -> Void
    @EnvironmentObject var s: SessioneProva
    @State private var n = 0
    @State private var risposta = ""

    var body: some View {
        LayoutProva {
            VStack(spacing: 16) {
                Text("SERIE \(n + 1) DI \(d.serie.count)").font(.system(size: 11, weight: .heavy)).tracking(1.5).foregroundStyle(Theme.dim)
                let x = d.serie[min(n, d.serie.count - 1)]
                Text(x.termini.map(String.init).joined(separator: "   ") + "   ?")
                    .font(.system(size: 26, weight: .heavy, design: .monospaced)).multilineTextAlignment(.center)
                    .padding(16).frame(maxWidth: .infinity).background(Color.black, in: RoundedRectangle(cornerRadius: 12))
                    .minimumScaleFactor(0.5)
                Text(risposta.isEmpty ? "–" : risposta).font(.system(size: 34, weight: .heavy, design: .monospaced))
                TastierinoProva { k in
                    Suoni.tasto()
                    if k == -1 { if !risposta.isEmpty { risposta.removeLast() }; return }
                    if risposta.count < 6 { risposta.append(String(k)) }
                }
                Button { verifica() } label: { Label("Conferma", systemImage: "checkmark") }.buttonStyle(PrimaryButtonStyle()).frame(maxWidth: 320)
            }
        } indizi: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Trova il numero che continua ogni serie.").font(.system(size: 14, weight: .heavy))
                Indizio(n: 1, testo: "Guarda la differenza tra un numero e il successivo.")
                Indizio(n: 2, testo: "Se le differenze cambiano, guarda le differenze delle differenze.")
                Indizio(n: 3, testo: "Se crescono troppo in fretta, prova a dividere invece di sottrarre.")
                Indizio(n: 4, testo: "Questa serie: \(d.serie[min(n, d.serie.count - 1)].aiuto).")
            }
        }
    }

    func verifica() {
        guard let v = Int(risposta) else { return }
        risposta = ""
        if v == d.serie[n].prossimo {
            Suoni.ok()
            if n + 1 < d.serie.count { withAnimation { n += 1 } } else { fatta() }
        } else { s.sbaglia("Numero sbagliato") }
    }
}

// MARK: - 6. Memoria sotto stress

struct ProvaMemoria: View {
    let livello: LivelloProva
    let seme: UInt64
    var fatta: () -> Void
    @EnvironmentObject var s: SessioneProva
    @State private var sequenza: [Int] = []
    @State private var acceso: Int?
    @State private var mostro = false
    @State private var inserita: [Int] = []
    @State private var giro = 0
    private let colori: [(String, Color)] = [("ROSSO", .red), ("VERDE", .green), ("BLU", .blue), ("GIALLO", .yellow)]

    var lunghezza: Int { [0, 4, 6, 7][livello.rawValue] }
    var alContrario: Bool { livello == .difficile }

    var body: some View {
        LayoutProva {
            VStack(spacing: 16) {
                Text(mostro ? "GUARDA…" : (sequenza.isEmpty ? "PRONTI?" : "RIPETI \(inserita.count)/\(sequenza.count)"))
                    .font(.system(size: 14, weight: .heavy)).tracking(1.5).foregroundStyle(mostro ? Theme.amber : Theme.dim)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(0..<4, id: \.self) { i in
                        Button { premi(i) } label: {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(colori[i].1.opacity(acceso == i ? 1 : 0.28))
                                .frame(height: 120)
                                .overlay(Text(colori[i].0).font(.system(size: 13, weight: .heavy)).foregroundStyle(.white.opacity(0.8)))
                                .shadow(color: acceso == i ? colori[i].1 : .clear, radius: 16)
                        }
                        .disabled(mostro || sequenza.isEmpty)
                    }
                }
                Button { nuovoGiro() } label: { Label(sequenza.isEmpty ? "Mostra la sequenza" : "Mostrala di nuovo (−\(Int(livello.penalita)) s)", systemImage: "eye") }
                    .buttonStyle(.bordered).tint(Theme.olive).disabled(mostro)
            }
        } indizi: {
            VStack(alignment: .leading, spacing: 6) {
                Indizio(n: 1, testo: "Premi «Mostra»: i colori si accendono uno alla volta (\(lunghezza) colori).")
                Indizio(n: 2, testo: alContrario ? "Ripetila AL CONTRARIO: dall'ultimo colore al primo." : "Ripetila nello stesso ordine.")
                Indizio(n: 3, testo: "Consiglio: uno dice i colori ad alta voce, un altro conta.")
                Indizio(n: 4, testo: "Se sbagli si ricomincia con una sequenza nuova.")
            }
        }
    }

    @MainActor func nuovoGiro() {
        if !sequenza.isEmpty { s.sbaglia("Rivista") }
        var g = Dado(seme &+ UInt64(giro))
        giro += 1
        sequenza = (0..<lunghezza).map { _ in g.int(0...3) }
        inserita = []
        mostro = true
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            for c in sequenza {
                acceso = c; Suoni.tasto()
                try? await Task.sleep(nanoseconds: livello == .difficile ? 450_000_000 : 650_000_000)
                acceso = nil
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            mostro = false
        }
    }

    @MainActor func premi(_ i: Int) {
        haptic()
        acceso = i
        Task { try? await Task.sleep(nanoseconds: 180_000_000); if acceso == i { acceso = nil } }
        let attesa = alContrario ? Array(sequenza.reversed()) : sequenza
        if attesa[inserita.count] == i {
            inserita.append(i)
            if inserita.count == attesa.count { fatta() }
        } else {
            s.sbaglia("Sequenza sbagliata")
            sequenza = []
            inserita = []
        }
    }
}

// MARK: - 7. Quiz tattico (risposte nel manuale a fianco)

struct DomandaQuiz { let d: String; let r: [String]; let giusta: Int }

struct DatiQuiz {
    static let banca: [DomandaQuiz] = [
        .init(d: "Nell'alfabeto NATO, la lettera K si dice…", r: ["Kilo", "King", "Kappa", "Key"], giusta: 0),
        .init(d: "Nell'alfabeto NATO, la lettera J si dice…", r: ["Jolly", "Juliett", "Jack", "Jupiter"], giusta: 1),
        .init(d: "\"Whiskey Sierra\" sono le lettere…", r: ["V S", "W S", "W Z", "U S"], giusta: 1),
        .init(d: "Nell'alfabeto NATO, Q è…", r: ["Queen", "Quebec", "Quota", "Quick"], giusta: 1),
        .init(d: "Che cosa vuol dire \"ROGER\" alla radio?", r: ["Ripeti", "Ricevuto", "Fine trasmissione", "Attendere"], giusta: 1),
        .init(d: "\"OVER\" alla radio significa…", r: ["Chiudo, non rispondere", "Passo, tocca a te", "Ripeti", "Emergenza"], giusta: 1),
        .init(d: "\"OUT\" alla radio significa…", r: ["Passo", "Fine comunicazione, non serve risposta", "Esco dall'area", "Silenzio radio"], giusta: 1),
        .init(d: "\"SAY AGAIN\" significa…", r: ["Ripeti", "Confermo", "Parla più forte", "Cambio canale"], giusta: 0),
        .init(d: "\"WILCO\" significa…", r: ["Non ho capito", "Ricevuto ed eseguirò", "Aspetta", "Negativo"], giusta: 1),
        .init(d: "Nel protocollo MARCH, la M sta per…", r: ["Medicazione", "Emorragia massiva", "Movimento", "Morfina"], giusta: 1),
        .init(d: "Nel protocollo MARCH, la A sta per…", r: ["Vie aeree", "Allarme", "Ambulanza", "Arresto"], giusta: 0),
        .init(d: "Nel protocollo MARCH, la R sta per…", r: ["Radio", "Respirazione", "Riposo", "Rianimazione cardiaca"], giusta: 1),
        .init(d: "Nel protocollo MARCH, la C sta per…", r: ["Circolazione", "Coscienza", "Collare", "Chiamata"], giusta: 0),
        .init(d: "Nel protocollo MARCH, la H sta per…", r: ["Elicottero", "Ipotermia e trauma cranico", "Aiuto", "Ospedale"], giusta: 1),
        .init(d: "Un laccio emostatico si mette…", r: ["Sopra la ferita, verso il cuore", "Sotto la ferita", "Sulla ferita", "Al polso sempre"], giusta: 0),
        .init(d: "Azimut 090° indica…", r: ["Nord", "Est", "Sud", "Ovest"], giusta: 1),
        .init(d: "Azimut 225° indica…", r: ["Nord-Est", "Sud-Est", "Sud-Ovest", "Nord-Ovest"], giusta: 2),
        .init(d: "Azimut 315° indica…", r: ["Nord-Ovest", "Nord-Est", "Ovest", "Sud-Ovest"], giusta: 0),
        .init(d: "Il contrario di 060° (azimut di ritorno) è…", r: ["120°", "240°", "300°", "180°"], giusta: 1),
        .init(d: "Il contrario di 300° è…", r: ["120°", "060°", "200°", "030°"], giusta: 0),
        .init(d: "In una coordinata MGRS \"34T BL 1234 5678\", 1234 è…", r: ["Il nord", "L'est (easting)", "La quota", "Il fuso"], giusta: 1),
        .init(d: "Su una carta 1:25.000, 4 cm corrispondono a…", r: ["100 m", "1 km", "400 m", "10 km"], giusta: 1),
        .init(d: "Su una carta 1:50.000, 1 cm corrisponde a…", r: ["50 m", "500 m", "5 km", "50 km"], giusta: 1),
        .init(d: "Curve di livello molto vicine indicano…", r: ["Terreno pianeggiante", "Pendio ripido", "Un fiume", "Una strada"], giusta: 1),
        .init(d: "Con 10 m di equidistanza, 6 curve salendo sono…", r: ["6 m", "60 m", "600 m", "16 m"], giusta: 1),
        .init(d: "La regola dei passi: 100 m in piano sono circa…", r: ["30-40 passi doppi", "60-70 passi doppi", "150 passi doppi", "10 passi"], giusta: 1),
        .init(d: "Nello SALUTE, la S sta per…", r: ["Size, dimensione", "Sicurezza", "Squadra", "Segnale"], giusta: 0),
        .init(d: "Nello SALUTE, la L sta per…", r: ["Luce", "Location, posizione", "Lato", "Lancio"], giusta: 1),
        .init(d: "In formazione a cuneo, il capo squadra di solito sta…", r: ["In punta", "In fondo", "Al centro, dietro la punta", "Fuori formazione"], giusta: 2),
        .init(d: "\"Copertura\" e \"riparo\": la copertura…", r: ["Nasconde e protegge", "Nasconde soltanto", "Protegge dai colpi", "È uguale al riparo"], giusta: 2),
        .init(d: "Muovendosi a sbalzi sotto fuoco, ogni sbalzo dura circa…", r: ["3-5 secondi", "15 secondi", "30 secondi", "1 minuto"], giusta: 0),
        .init(d: "Ore 12 in una chiamata a orologio indicano…", r: ["Davanti", "Dietro", "A destra", "A sinistra"], giusta: 0),
        .init(d: "Ore 3 in una chiamata a orologio indicano…", r: ["Davanti", "Destra", "Dietro", "Sinistra"], giusta: 1),
        .init(d: "La sigla \"KIA\" significa…", r: ["Ferito", "Ucciso in azione", "Disperso", "Prigioniero"], giusta: 1),
        .init(d: "La sigla \"WIA\" significa…", r: ["Ferito in azione", "Disperso", "Rientrato", "Senza radio"], giusta: 0),
        .init(d: "In Morse, \"...\" è la lettera…", r: ["O", "S", "E", "H"], giusta: 1),
        .init(d: "In Morse, \"---\" è la lettera…", r: ["T", "M", "O", "S"], giusta: 2),
        .init(d: "SOS in Morse è…", r: ["--- ... ---", "... --- ...", ".-.-.-", "...---"], giusta: 1),
        .init(d: "Il fuso orario \"Z\" (Zulu) corrisponde a…", r: ["Ora italiana", "UTC", "Ora legale", "Ora locale"], giusta: 1),
        .init(d: "In inverno l'Italia è…", r: ["Zulu", "Zulu + 1 (Alfa)", "Zulu + 2 (Bravo)", "Zulu − 1"], giusta: 1),
    ]
    let domande: [DomandaQuiz]
    let minimo: Int

    init(_ l: LivelloProva, _ seme: UInt64) {
        var g = Dado(seme)
        let n = [0, 5, 8, 10][l.rawValue]
        domande = Array(DatiQuiz.banca.shuffled(using: &g).prefix(n)).map { q in
            // mescola anche le risposte
            let ordine = Array(0..<q.r.count).shuffled(using: &g)
            return DomandaQuiz(d: q.d, r: ordine.map { q.r[$0] }, giusta: ordine.firstIndex(of: q.giusta) ?? 0)
        }
        minimo = Int((Double(n) * [0, 0.6, 0.7, 0.8][l.rawValue]).rounded(.up))
    }
}

struct ProvaQuiz: View {
    let d: DatiQuiz
    var fatta: () -> Void
    @EnvironmentObject var s: SessioneProva
    @State private var n = 0
    @State private var giuste = 0

    var body: some View {
        LayoutProva {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("DOMANDA \(min(n + 1, d.domande.count))/\(d.domande.count)").font(.system(size: 11, weight: .heavy)).tracking(1.5).foregroundStyle(Theme.dim)
                    Spacer()
                    Text("\(giuste) giuste · servono \(d.minimo)").font(Theme.mono(12, .bold)).foregroundStyle(Theme.oliveBright)
                }
                if n < d.domande.count {
                    let q = d.domande[n]
                    Text(q.d).font(.system(size: 20, weight: .heavy)).fixedSize(horizontal: false, vertical: true)
                    ForEach(0..<q.r.count, id: \.self) { i in
                        Button { rispondi(i) } label: {
                            HStack {
                                Text(["A", "B", "C", "D"][i]).font(Theme.mono(14, .heavy)).foregroundStyle(Theme.oliveBright).frame(width: 24)
                                Text(q.r[i]).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).multilineTextAlignment(.leading)
                                Spacer()
                            }
                            .padding(14).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
        } indizi: {
            ManualeCampo()
        }
    }

    func rispondi(_ i: Int) {
        if i == d.domande[n].giusta { giuste += 1; Suoni.ok() } else { s.sbaglia("Risposta errata") }
        if n + 1 < d.domande.count { withAnimation { n += 1 } } else {
            if giuste >= d.minimo { fatta() } else { s.perdi() }
        }
    }
}

struct ManualeCampo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sezione("AlfabetoProve NATO", zip(AlfabetoProve.lettere, AlfabetoProve.nato).map { "\($0) \($1)" }.joined(separator: " · "))
            sezione("Morse", zip(AlfabetoProve.lettere, AlfabetoProve.morse).map { "\($0) \($1)" }.joined(separator: "   "))
            sezione("Radio", "ROGER ricevuto · WILCO ricevuto ed eseguirò · OVER passo · OUT fine, nessuna risposta · SAY AGAIN ripeti · WAIT attendere · AFFIRMATIVE / NEGATIVE sì / no · BREAK pausa nel messaggio")
            sezione("MARCH", "M emorragia massiva (laccio sopra la ferita) · A vie aeree · R respirazione · C circolazione · H ipotermia e trauma cranico")
            sezione("Azimut", "000 N · 045 NE · 090 E · 135 SE · 180 S · 225 SO · 270 O · 315 NO. Ritorno: ± 180°.")
            sezione("Scale", "1:25.000 → 1 cm = 250 m · 1:50.000 → 1 cm = 500 m. Equidistanza × numero di curve = dislivello.")
            sezione("Sigle", "SALUTE: Size, Activity, Location, Unit, Time, Equipment · KIA ucciso · WIA ferito · MIA disperso · Z = UTC, Alfa = UTC+1, Bravo = UTC+2")
            sezione("Tattica", "Copertura = protegge dai colpi; riparo = nasconde. Sbalzi 3-5 s. Ore 12 davanti, 3 destra, 6 dietro, 9 sinistra. Cuneo: capo dietro la punta. 100 m in piano ≈ 60-70 passi doppi.")
        }
    }
    func sezione(_ t: String, _ testo: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.amber)
            Text(testo).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 8. Navigazione su griglia

struct DatiGriglia {
    let lato: Int
    let codici: [[String]]
    let partenza: (Int, Int)
    let mosse: [String]
    let arrivo: (Int, Int)

    init(_ l: LivelloProva, _ seme: UInt64) {
        var g = Dado(seme)
        let n = [0, 6, 7, 8][l.rawValue]
        var usati = Set<String>()
        var cod: [[String]] = []
        let lettere = Array("ABCDEFGHJKLMNPRSTUVZ")
        for _ in 0..<n {
            var riga: [String] = []
            for _ in 0..<n {
                var c = ""
                repeat { c = String(lettere[g.int(0...(lettere.count - 1))]) + String(g.int(1...9)) } while usati.contains(c)
                usati.insert(c); riga.append(c)
            }
            cod.append(riga)
        }
        var x = g.int(0...(n - 1)), y = g.int(0...(n - 1))
        let p = (x, y)
        var m: [String] = []
        let passi = [0, 3, 5, 7][l.rawValue]
        let dir: [(Int, Int, String, String)] = [(0, -1, "Nord", "000°"), (1, 0, "Est", "090°"), (0, 1, "Sud", "180°"), (-1, 0, "Ovest", "270°")]
        for _ in 0..<passi {
            var tent = 0
            while tent < 20 {
                tent += 1
                let d = g.uno(dir), k = g.int(1...3)
                let nx = x + d.0 * k, ny = y + d.1 * k
                guard nx >= 0, nx < n, ny >= 0, ny < n else { continue }
                x = nx; y = ny
                m.append(l == .difficile && g.vero(0.6) ? "rotta \(d.3) per \(k)" : "\(k) \(k == 1 ? "casella" : "caselle") a \(d.2)")
                break
            }
        }
        lato = n; codici = cod; partenza = p; mosse = m; arrivo = (x, y)
    }
    func nome(_ c: (Int, Int)) -> String { String(Array("ABCDEFGH")[c.0]) + String(c.1 + 1) }
}

struct ProvaGriglia: View {
    let d: DatiGriglia
    var fatta: () -> Void
    @EnvironmentObject var s: SessioneProva

    var body: some View {
        LayoutProva {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text("").frame(width: 20)
                    ForEach(0..<d.lato, id: \.self) { c in Text(String(Array("ABCDEFGH")[c])).font(Theme.mono(11, .heavy)).foregroundStyle(Theme.dim).frame(maxWidth: .infinity) }
                }
                ForEach(0..<d.lato, id: \.self) { r in
                    HStack(spacing: 4) {
                        Text("\(r + 1)").font(Theme.mono(11, .heavy)).foregroundStyle(Theme.dim).frame(width: 20)
                        ForEach(0..<d.lato, id: \.self) { c in
                            Button { tocca(c, r) } label: {
                                Text(d.codici[r][c]).font(Theme.mono(12, .bold))
                                    .frame(maxWidth: .infinity).frame(height: 38)
                                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 6))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                }
                Text("Tocca la casella d'arrivo.").font(.caption).foregroundStyle(Theme.dim).padding(.top, 6)
            }
        } indizi: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Partenza: casella \(d.nome(d.partenza))").font(.system(size: 15, weight: .heavy))
                Text("Nord è in alto (riga 1). Colonne A→… da ovest a est.").font(.caption).foregroundStyle(Theme.dim)
                ForEach(Array(d.mosse.enumerated()), id: \.offset) { i, m in Indizio(n: i + 1, testo: "Spostati di " + m + ".") }
            }
        }
    }

    func tocca(_ c: Int, _ r: Int) {
        haptic()
        if c == d.arrivo.0 && r == d.arrivo.1 { fatta() } else { s.sbaglia("Casella sbagliata") }
    }
}

// MARK: - 9. Quadro interruttori

struct DatiInterruttori {
    let n: Int
    let soluzione: [Bool]
    let indizi: [String]

    init(_ l: LivelloProva, _ seme: UInt64) {
        var g = Dado(seme)
        let n = [0, 4, 6, 7][l.rawValue]
        let sol = (0..<n).map { _ in g.vero() }
        let L = Array("ABCDEFGH").map(String.init)
        var vincoli: [(String, ([Bool]) -> Bool)] = []
        func soluzioni() -> Int {
            var tot = 0
            for m in 0..<(1 << n) {
                let v = (0..<n).map { (m >> $0) & 1 == 1 }
                if vincoli.allSatisfy({ $0.1(v) }) { tot += 1; if tot > 1 { return tot } }
            }
            return tot
        }
        var giri = 0
        while soluzioni() != 1 && giri < 80 {
            giri += 1
            let a = g.int(0...(n - 1)), b = g.int(0...(n - 1)), c = g.int(0...(n - 1))
            guard a != b else { continue }
            let tipo = g.int(0...(l == .facile ? 3 : 5))
            let la = L[a], lb = L[b], lc = L[c]
            switch tipo {
            case 0:
                if sol[a] == sol[b] {
                    let f: ([Bool]) -> Bool = { v in v[a] == v[b] }
                    vincoli.append(("\(la) e \(lb) sono nella stessa posizione.", f))
                } else {
                    let f: ([Bool]) -> Bool = { v in v[a] != v[b] }
                    vincoli.append(("\(la) e \(lb) sono in posizioni opposte.", f))
                }
            case 1:
                let k: Int = sol.filter { $0 }.count
                if !vincoli.contains(where: { $0.0.hasPrefix("In tutto") }) {
                    let f: ([Bool]) -> Bool = { v in v.filter { $0 }.count == k }
                    vincoli.append(("In tutto ci sono \(k) interruttori accesi.", f))
                }
            case 2:
                if l == .facile || g.vero(0.25) {
                    let acceso: Bool = sol[a]
                    let f: ([Bool]) -> Bool = { v in v[a] == acceso }
                    vincoli.append(("\(la) è \(acceso ? "acceso" : "spento").", f))
                }
            case 3:
                // implicazione vera nella soluzione: se A è (com'è) allora B è (com'è)
                let sa: Bool = sol[a], sb: Bool = sol[b]
                let f: ([Bool]) -> Bool = { v in v[a] != sa || v[b] == sb }
                let testo = "Se \(la) è \(sa ? "acceso" : "spento"), \(lb) è \(sb ? "acceso" : "spento")."
                vincoli.append((testo, f))
            case 4:
                guard c != a, c != b else { continue }
                let k: Int = [sol[a], sol[b], sol[c]].filter { $0 }.count
                let nomi = ["nessuno è acceso", "uno solo è acceso", "due sono accesi", "sono tutti accesi"]
                let f: ([Bool]) -> Bool = { v in [v[a], v[b], v[c]].filter { $0 }.count == k }
                vincoli.append(("Tra \(la), \(lb) e \(lc) \(nomi[k]).", f))
            default:
                if a > 0 {
                    let k: Int = (0..<a).filter { sol[$0] }.count
                    let f: ([Bool]) -> Bool = { v in (0..<a).filter { v[$0] }.count == k }
                    vincoli.append(("Prima di \(la) (a sinistra) ci sono \(k) interruttori accesi.", f))
                }
            }
        }
        // se dopo tanti giri non è ancora unica, chiudo con indizi diretti
        var i = 0
        while soluzioni() != 1 && i < n {
            let j = i
            let acceso: Bool = sol[j]
            let f: ([Bool]) -> Bool = { v in v[j] == acceso }
            vincoli.append(("\(L[j]) è \(acceso ? "acceso" : "spento").", f))
            i += 1
        }
        self.n = n; soluzione = sol
        indizi = vincoli.map { $0.0 }.shuffled(using: &g)
    }
}

struct ProvaInterruttori: View {
    let d: DatiInterruttori
    var fatta: () -> Void
    @EnvironmentObject var s: SessioneProva
    @State private var stato: [Bool] = []

    var body: some View {
        LayoutProva {
            VStack(spacing: 18) {
                HStack(spacing: 10) {
                    ForEach(0..<d.n, id: \.self) { i in
                        VStack(spacing: 8) {
                            Circle().fill(acceso(i) ? Theme.green : Color(white: 0.18)).frame(width: 14, height: 14)
                                .shadow(color: acceso(i) ? Theme.green : .clear, radius: 6)
                            Button { haptic(); if stato.count == d.n { stato[i].toggle() } } label: {
                                ZStack(alignment: acceso(i) ? .top : .bottom) {
                                    RoundedRectangle(cornerRadius: 10).fill(Color.black).frame(width: 40, height: 84)
                                    RoundedRectangle(cornerRadius: 8).fill(acceso(i) ? Theme.olive : Color(white: 0.4)).frame(width: 34, height: 40).padding(3)
                                }
                            }
                            .animation(.spring(response: 0.2), value: stato)
                            Text(String(Array("ABCDEFGH")[i])).font(Theme.mono(16, .heavy))
                        }
                    }
                }
                Button { verifica() } label: { Label("Dai corrente", systemImage: "bolt.fill") }.buttonStyle(PrimaryButtonStyle()).frame(maxWidth: 320)
            }
            .onAppear { if stato.count != d.n { stato = Array(repeating: false, count: d.n) } }
        } indizi: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Su = acceso, giù = spento. Tutti gli indizi devono essere veri insieme.").font(.caption).foregroundStyle(Theme.dim)
                ForEach(Array(d.indizi.enumerated()), id: \.offset) { i, t in Indizio(n: i + 1, testo: t) }
            }
        }
    }

    func acceso(_ i: Int) -> Bool { i < stato.count && stato[i] }
    func verifica() { if stato == d.soluzione { fatta() } else { s.sbaglia("Configurazione errata") } }
}

// MARK: - 10. Frequenza radio

struct DatiRadio {
    let parola: String
    let messaggio: String
    let tabella: [(String, Double)]
    let frequenza: Double
    let lampeggia: Bool

    init(_ l: LivelloProva, _ seme: UInt64) {
        var g = Dado(seme)
        let nomi = ["LUPO", "FALCO", "ORSO", "VOLPE", "AQUILA", "COBRA", "TIGRE", "GUFO", "LINCE", "SQUALO", "CORVO", "VIPERA"].shuffled(using: &g)
        let righe = [0, 5, 7, 9][l.rawValue]
        var tab: [(String, Double)] = []
        for nome in nomi.prefix(righe) {
            let f = Double(g.int(30...87)) + Double(g.int(0...39)) * 0.025
            tab.append((nome, (f * 1000).rounded() / 1000))
        }
        let scelta = tab[g.int(0...(tab.count - 1))]
        parola = scelta.0
        frequenza = scelta.1
        tabella = tab
        lampeggia = l == .difficile
        messaggio = l == .facile ? parola.map { AlfabetoProve.nato[AlfabetoProve.indice($0) ?? 0] }.joined(separator: " ")
                                 : parola.map { AlfabetoProve.morse[AlfabetoProve.indice($0) ?? 0] }.joined(separator: "  /  ")
    }
}

struct ProvaRadio: View {
    let d: DatiRadio
    var fatta: () -> Void
    @EnvironmentObject var s: SessioneProva
    @State private var mhz: Double = 50
    @State private var luce = false
    @State private var lampeggio = false

    var body: some View {
        LayoutProva {
            VStack(spacing: 16) {
                Text("SEGNALE RICEVUTO").font(.system(size: 11, weight: .heavy)).tracking(1.5).foregroundStyle(Theme.dim)
                if d.lampeggia {
                    Circle().fill(luce ? Color.white : Color(white: 0.12)).frame(width: 90, height: 90)
                        .shadow(color: luce ? .white : .clear, radius: 20)
                    Button { lampeggia() } label: { Label(lampeggio ? "In onda…" : "Ascolta il segnale luminoso", systemImage: "light.max") }
                        .buttonStyle(.bordered).tint(Theme.olive).disabled(lampeggio)
                } else {
                    Text(d.messaggio).font(.system(size: 22, weight: .heavy, design: .monospaced)).multilineTextAlignment(.center)
                        .padding(14).frame(maxWidth: .infinity).background(Color.black, in: RoundedRectangle(cornerRadius: 12))
                }
                Text(String(format: "%.3f MHz", mhz)).font(.system(size: 38, weight: .heavy, design: .monospaced)).foregroundStyle(Theme.green)
                    .padding(.horizontal, 14).padding(.vertical, 8).background(Color.black, in: RoundedRectangle(cornerRadius: 10))
                HStack(spacing: 8) {
                    passo("−1", -1); passo("−0,025", -0.025); passo("+0,025", 0.025); passo("+1", 1)
                }
                HStack(spacing: 8) { passo("−10", -10); passo("+10", 10) }
                Button { verifica() } label: { Label("Trasmetti", systemImage: "antenna.radiowaves.left.and.right") }.buttonStyle(PrimaryButtonStyle()).frame(maxWidth: 320)
            }
        } indizi: {
            VStack(alignment: .leading, spacing: 8) {
                Indizio(n: 1, testo: d.lampeggia ? "Il segnale è in Morse luminoso: lampo corto = punto, lampo lungo = linea." : (d.messaggio.contains("-") || d.messaggio.contains(".") ? "Il segnale è in codice Morse." : "Il segnale è in alfabeto NATO."))
                Indizio(n: 2, testo: "Decifra il nominativo e sintonizza la sua frequenza, poi trasmetti.")
                Text("Frequenze").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.amber)
                ForEach(d.tabella, id: \.0) { r in
                    HStack { Text(r.0).font(Theme.mono(14, .bold)); Spacer(); Text(String(format: "%.3f", r.1)).font(Theme.mono(14)) }
                }
                Text("Morse").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.amber).padding(.top, 4)
                Text(zip(AlfabetoProve.lettere, AlfabetoProve.morse).map { "\($0) \($1)" }.joined(separator: "   ")).font(Theme.mono(12)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func passo(_ t: String, _ v: Double) -> some View {
        Button { Suoni.tasto(); mhz = min(99.975, max(30, ((mhz + v) * 1000).rounded() / 1000)) } label: {
            Text(t).font(Theme.mono(15, .bold)).frame(maxWidth: .infinity).frame(height: 46)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(PressStyle()).tint(.white)
    }

    func verifica() { if abs(mhz - d.frequenza) < 0.001 { fatta() } else { s.sbaglia("Nessuna risposta su questa frequenza") } }

    @MainActor func lampeggia() {
        lampeggio = true
        Task {
            for ch in d.parola {
                for simbolo in AlfabetoProve.morse[AlfabetoProve.indice(ch) ?? 0] {
                    luce = true
                    try? await Task.sleep(nanoseconds: simbolo == "." ? 220_000_000 : 650_000_000)
                    luce = false
                    try? await Task.sleep(nanoseconds: 220_000_000)
                }
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
            lampeggio = false
        }
    }
}
