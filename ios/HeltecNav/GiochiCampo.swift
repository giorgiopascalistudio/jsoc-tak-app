import SwiftUI
import AudioToolbox
import Combine

// MARK: - Giochi da campo: il telefono diventa l'oggetto di scena (bomba, bandiera, nucleare, terminale).
// Funzionano senza server: il telefono resta sul campo e lo schermo non si spegne.

struct GiochiCampoView: View {
    var body: some View {
        List {
            Section {
                link("Bomba", "timer, codice di disinnesco, errori che tolgono tempo", "flame.fill", Theme.red) { BombaView() }
                link("Bandiera / dominazione", "tieni premuto per conquistare, vince chi la tiene di più", "flag.fill", Theme.olive) { BandieraView() }
                link("Nucleare", "due chiavi girate insieme, codice di lancio, annullamento", "atom", Theme.amber) { NucleareView() }
                link("Guerra informatica", "viola il terminale ripetendo le sequenze", "cpu", Theme.cyan) { TerminaleView() }
            } footer: { Text("Lascia il telefono sul campo come oggetto di scena: lo schermo resta acceso finché il gioco è aperto.") }
        }
        .listaJSOC()
    }

    func link<D: View>(_ t: String, _ s: String, _ i: String, _ c: Color, @ViewBuilder _ d: @escaping () -> D) -> some View {
        NavigationLink { d().background(Color.black.ignoresSafeArea()).navigationTitle(t).navigationBarTitleDisplayMode(.inline)
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: i).font(.title2).foregroundStyle(c).frame(width: 34)
                VStack(alignment: .leading, spacing: 2) { Text(t).font(.headline); Text(s).font(.caption).foregroundStyle(Theme.dim) }
            }
        }
    }
}

private enum Suono {
    static func bip() { AudioServicesPlaySystemSound(1103) }
    static func ok() { AudioServicesPlaySystemSound(1407) }
    static func errore() { AudioServicesPlaySystemSound(1053); AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) }
    static func allarme() { AudioServicesPlaySystemSound(1005); AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) }
}

private func mmss(_ s: Double) -> String {
    let t = max(0, Int(s.rounded(.up)))
    return String(format: "%02d:%02d", t / 60, t % 60)
}

/// tastierino numerico grande, usabile con i guanti
private struct Tastierino: View {
    @Binding var testo: String
    var max = 8
    var conferma: () -> Void
    var body: some View {
        let tasti = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "⌫", "0", "OK"]
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(tasti, id: \.self) { k in
                Button {
                    haptic()
                    switch k {
                    case "⌫": if !testo.isEmpty { testo.removeLast() }
                    case "OK": conferma()
                    default: if testo.count < max { testo.append(k) }
                    }
                } label: {
                    Text(k).font(Theme.mono(26, .heavy)).frame(maxWidth: .infinity, minHeight: 58)
                        .foregroundStyle(k == "OK" ? .black : .white)
                        .background(k == "OK" ? Theme.olive : Theme.surface2, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(PressStyle())
            }
        }
    }
}

// MARK: Bomba

struct BombaView: View {
    enum Stato { case prepara, armata, esplosa, disinnescata }
    @State private var stato = Stato.prepara
    @State private var minuti = 10
    @State private var codice = ""
    @State private var penalita = 30
    @State private var tentativiMax = 3
    @State private var fine = Date()
    @State private var digitato = ""
    @State private var errori = 0
    @State private var ultimoBip = 0
    private let orologio = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 18) {
            switch stato {
            case .prepara: prepara
            case .armata: armata
            case .esplosa: schermo("ESPLOSA", "La squadra non ha disinnescato in tempo.", Theme.red, "flame.fill")
            case .disinnescata: schermo("DISINNESCATA", "Codice giusto con \(mmss(fine.timeIntervalSinceNow)) rimasti.", Theme.olive, "checkmark.shield.fill")
            }
        }
        .padding(18)
        .frame(maxWidth: 520).frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(orologio) { _ in
            guard stato == .armata else { return }
            let r = fine.timeIntervalSinceNow
            if r <= 0 { stato = .esplosa; for i in 0..<4 { DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.8) { Suono.allarme() } }; return }
            let passo = r < 10 ? 1 : r < 60 ? 2 : 5
            let s = Int(r)
            if s != ultimoBip && s % passo == 0 { ultimoBip = s; Suono.bip() }
        }
    }

    var prepara: some View {
        VStack(spacing: 14) {
            Image(systemName: "flame.fill").font(.system(size: 54)).foregroundStyle(Theme.red)
            Card(title: "Impostazioni del GM", icon: "slider.horizontal.3") {
                Stepper("Timer: \(minuti) min", value: $minuti, in: 1...120)
                Stepper("Errore: −\(penalita) s", value: $penalita, in: 0...300, step: 10)
                Stepper("Tentativi: \(tentativiMax == 0 ? "illimitati" : "\(tentativiMax)")", value: $tentativiMax, in: 0...10)
                SecureField("Codice di disinnesco (solo cifre)", text: $codice).keyboardType(.numberPad)
                    .font(Theme.mono(18, .bold)).padding(10).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
            }
            Button {
                fine = Date().addingTimeInterval(Double(minuti * 60)); errori = 0; digitato = ""; stato = .armata; Suono.allarme()
            } label: { Label("ARMA LA BOMBA", systemImage: "bolt.fill") }
            .buttonStyle(PrimaryButtonStyle()).disabled(codice.count < 3)
            Text("Il codice va dato alla squadra che difende, o nascosto in un'altra fase.").font(.caption).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
        }
    }

    var armata: some View {
        VStack(spacing: 14) {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let r = fine.timeIntervalSinceNow
                Text(mmss(r)).font(.system(size: 84, weight: .heavy, design: .monospaced))
                    .foregroundStyle(r < 60 ? Theme.red : .white)
                    .opacity(r < 10 && Int(r * 4) % 2 == 0 ? 0.35 : 1)
            }
            Text(errori == 0 ? "INSERISCI IL CODICE DI DISINNESCO" : "ERRORI \(errori)\(tentativiMax > 0 ? "/\(tentativiMax)" : "")")
                .font(.caption.weight(.heavy)).foregroundStyle(errori == 0 ? Theme.dim : Theme.red)
            Text(digitato.isEmpty ? "— — — —" : String(repeating: "● ", count: digitato.count))
                .font(Theme.mono(28, .heavy)).frame(height: 40)
            Tastierino(testo: $digitato) {
                if digitato == codice { stato = .disinnescata; Suono.ok(); return }
                errori += 1; digitato = ""; Suono.errore()
                fine = fine.addingTimeInterval(-Double(penalita))
                if tentativiMax > 0 && errori >= tentativiMax { fine = Date() }
            }
        }
    }

    func schermo(_ t: String, _ s: String, _ c: Color, _ i: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: i).font(.system(size: 90)).foregroundStyle(c)
            Text(t).font(.system(size: 40, weight: .heavy)).foregroundStyle(c)
            Text(s).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            Button("Nuova partita") { stato = .prepara }.buttonStyle(.bordered).tint(Theme.olive)
        }
    }
}

// MARK: Bandiera / dominazione

struct BandieraView: View {
    struct Squadra { var nome: String; var colore: Color; var tempo: Double = 0 }
    @State private var squadre = [Squadra(nome: "ATTACCO", colore: Theme.red), Squadra(nome: "DIFESA", colore: Theme.cyan)]
    @State private var possesso: Int?
    @State private var obiettivo = 10
    @State private var secondiPresa = 5
    @State private var inCorso = false
    @State private var vincitore: Int?
    @State private var presa: (Int, Date)?
    @State private var ultimo = Date()
    private let orologio = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            if !inCorso && vincitore == nil {
                Card(title: "Impostazioni", icon: "slider.horizontal.3") {
                    Stepper("Vince chi la tiene \(obiettivo) min", value: $obiettivo, in: 1...120)
                    Stepper("Conquista: premi \(secondiPresa) s", value: $secondiPresa, in: 1...30)
                    TextField("Squadra 1", text: $squadre[0].nome).textInputAutocapitalization(.characters)
                    TextField("Squadra 2", text: $squadre[1].nome).textInputAutocapitalization(.characters)
                }
                Button { squadre[0].tempo = 0; squadre[1].tempo = 0; possesso = nil; vincitore = nil; ultimo = Date(); inCorso = true } label: {
                    Label("Inizia", systemImage: "flag.fill")
                }.buttonStyle(PrimaryButtonStyle())
            } else if let v = vincitore {
                Image(systemName: "flag.checkered").font(.system(size: 80)).foregroundStyle(squadre[v].colore)
                Text("VINCE \(squadre[v].nome)").font(.system(size: 36, weight: .heavy)).foregroundStyle(squadre[v].colore)
                Button("Nuova partita") { vincitore = nil; inCorso = false }.buttonStyle(.bordered).tint(Theme.olive)
            } else {
                Image(systemName: "flag.fill").font(.system(size: 70)).foregroundStyle(possesso.map { squadre[$0].colore } ?? .gray)
                Text(possesso.map { "IN MANO A \(squadre[$0].nome)" } ?? "NEUTRALE").font(.title2.weight(.heavy))
                ForEach(0..<2, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text(squadre[i].nome).font(.headline); Spacer(); Text("\(mmss(squadre[i].tempo)) / \(obiettivo):00").font(Theme.mono(14, .bold)) }
                        ProgressView(value: min(squadre[i].tempo, Double(obiettivo * 60)), total: Double(obiettivo * 60)).tint(squadre[i].colore)
                    }
                }
                HStack(spacing: 12) {
                    ForEach(0..<2, id: \.self) { i in
                        let progresso = presa?.0 == i ? min(1, Date().timeIntervalSince(presa!.1) / Double(secondiPresa)) : 0
                        Text(presa?.0 == i ? "\(Int(progresso * 100))%" : "TIENI PREMUTO\n\(squadre[i].nome)")
                            .font(.headline.weight(.heavy)).multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 130)
                            .background(squadre[i].colore.opacity(0.25 + 0.6 * progresso), in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(squadre[i].colore, lineWidth: 2))
                            .gesture(DragGesture(minimumDistance: 0)
                                .onChanged { _ in if presa?.0 != i && possesso != i { presa = (i, Date()); haptic() } }
                                .onEnded { _ in presa = nil })
                            .opacity(possesso == i ? 0.4 : 1)
                    }
                }
                Button("Ferma") { inCorso = false }.buttonStyle(.bordered).tint(Theme.dim)
            }
        }
        .padding(18)
        .frame(maxWidth: 560).frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(orologio) { now in
            guard inCorso, vincitore == nil else { return }
            let dt = now.timeIntervalSince(ultimo); ultimo = now
            if let p = possesso {
                squadre[p].tempo += dt
                if squadre[p].tempo >= Double(obiettivo * 60) { vincitore = p; inCorso = false; Suono.allarme() }
            }
            if let pr = presa, now.timeIntervalSince(pr.1) >= Double(secondiPresa) {
                possesso = pr.0; presa = nil; Suono.allarme()
            }
        }
    }
}

// MARK: Nucleare

struct NucleareView: View {
    enum Stato { case prepara, chiavi, lancio, conto, lanciato, annullato }
    @State private var stato = Stato.prepara
    @State private var codiceLancio = ""
    @State private var codiceStop = ""
    @State private var minuti = 5
    @State private var digitato = ""
    @State private var chiave1 = false
    @State private var chiave2 = false
    @State private var dalle: Date?
    @State private var fine = Date()
    @State private var annulla = false
    @State private var avviso: String?
    @State private var ultimoBip = -1
    private let orologio = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            switch stato {
            case .prepara:
                Image(systemName: "atom").font(.system(size: 60)).foregroundStyle(Theme.amber)
                Card(title: "Impostazioni del GM", icon: "slider.horizontal.3") {
                    Stepper("Conto alla rovescia: \(minuti) min", value: $minuti, in: 1...60)
                    SecureField("Codice di lancio", text: $codiceLancio).keyboardType(.numberPad).font(Theme.mono(16, .bold))
                    SecureField("Codice di annullamento", text: $codiceStop).keyboardType(.numberPad).font(Theme.mono(16, .bold))
                }
                Text("Per lanciare servono due persone: le due chiavi vanno tenute premute insieme per 3 secondi, poi il codice. Per annullare: di nuovo le due chiavi e il codice di annullamento.")
                    .font(.caption).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                Button { annulla = false; stato = .chiavi } label: { Label("Attiva la console", systemImage: "power") }
                    .buttonStyle(PrimaryButtonStyle()).disabled(codiceLancio.count < 3 || codiceStop.count < 3)
            case .chiavi:
                if annulla { conto(piccolo: true) }
                Text(annulla ? "ANNULLAMENTO: GIRATE LE DUE CHIAVI" : "GIRATE LE DUE CHIAVI INSIEME").font(.headline.weight(.heavy))
                HStack(spacing: 14) { chiave("CHIAVE 1", $chiave1); chiave("CHIAVE 2", $chiave2) }
                if let d = dalle {
                    ProgressView(value: min(3, Date().timeIntervalSince(d)), total: 3).tint(Theme.amber)
                }
                if let avviso { Text(avviso).foregroundStyle(Theme.red).font(.footnote) }
            case .lancio:
                if annulla { conto(piccolo: true) }
                Text(annulla ? "CODICE DI ANNULLAMENTO" : "CODICE DI LANCIO").font(.headline.weight(.heavy)).foregroundStyle(Theme.amber)
                Text(digitato.isEmpty ? "— — — —" : String(repeating: "● ", count: digitato.count)).font(Theme.mono(26, .heavy))
                Tastierino(testo: $digitato) {
                    if !annulla && digitato == codiceLancio {
                        fine = Date().addingTimeInterval(Double(minuti * 60)); stato = .conto; Suono.allarme()
                    } else if annulla && digitato == codiceStop {
                        stato = .annullato; Suono.ok()
                    } else { Suono.errore(); avviso = "Codice errato"; stato = annulla ? .conto : .chiavi }
                    digitato = ""
                }
            case .conto:
                conto(piccolo: false)
                Button { annulla = true; avviso = nil; stato = .chiavi } label: { Label("Annulla il lancio", systemImage: "xmark.octagon.fill") }
                    .buttonStyle(.borderedProminent).tint(Theme.red)
            case .lanciato:
                Image(systemName: "burst.fill").font(.system(size: 100)).foregroundStyle(Theme.red)
                Text("LANCIATO").font(.system(size: 44, weight: .heavy)).foregroundStyle(Theme.red)
                Button("Nuova partita") { stato = .prepara }.buttonStyle(.bordered).tint(Theme.olive)
            case .annullato:
                Image(systemName: "checkmark.shield.fill").font(.system(size: 100)).foregroundStyle(Theme.olive)
                Text("LANCIO ANNULLATO").font(.system(size: 34, weight: .heavy)).foregroundStyle(Theme.olive)
                Text("con \(mmss(fine.timeIntervalSinceNow)) rimasti").foregroundStyle(Theme.dim)
                Button("Nuova partita") { stato = .prepara }.buttonStyle(.bordered).tint(Theme.olive)
            }
        }
        .padding(18)
        .frame(maxWidth: 560).frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(orologio) { _ in
            if stato == .chiavi {
                if chiave1 && chiave2 {
                    if dalle == nil { dalle = Date(); haptic(.heavy) }
                    else if Date().timeIntervalSince(dalle!) >= 3 { dalle = nil; chiave1 = false; chiave2 = false; avviso = nil; stato = .lancio; Suono.ok() }
                } else { dalle = nil }
            }
            // il conto continua anche mentre provano ad annullare
            let corre = stato == .conto || (annulla && (stato == .chiavi || stato == .lancio))
            if corre && fine.timeIntervalSinceNow <= 0 {
                stato = .lanciato
                for i in 0..<5 { DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.7) { Suono.allarme() } }
            } else if corre {
                let sec = Int(fine.timeIntervalSinceNow)
                if sec != ultimoBip { ultimoBip = sec; Suono.bip() }
            }
        }
    }

    func conto(piccolo: Bool) -> some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            Text(mmss(fine.timeIntervalSinceNow)).font(.system(size: piccolo ? 34 : 80, weight: .heavy, design: .monospaced)).foregroundStyle(Theme.red)
        }
    }

    func chiave(_ t: String, _ b: Binding<Bool>) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "key.fill").font(.system(size: 40)).rotationEffect(.degrees(b.wrappedValue ? 90 : 0))
            Text(t).font(.headline.weight(.heavy))
        }
        .foregroundStyle(b.wrappedValue ? Color.black : Theme.amber)
        .frame(maxWidth: .infinity, minHeight: 170)
        .background(b.wrappedValue ? Theme.amber : Theme.surface2, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.amber, lineWidth: 2))
        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in if !b.wrappedValue { b.wrappedValue = true; haptic() } }.onEnded { _ in b.wrappedValue = false })
        .animation(.spring(response: 0.3), value: b.wrappedValue)
    }
}

// MARK: Guerra informatica (terminale da violare)

struct TerminaleView: View {
    enum Stato { case prepara, mostra, ripeti, bloccato, violato }
    @State private var stato = Stato.prepara
    @State private var livelli = 4
    @State private var lunghezza0 = 3
    @State private var premio = ""
    @State private var blocco = 30
    @State private var livello = 0
    @State private var sequenza: [Int] = []
    @State private var acceso: Int?
    @State private var inserite: [Int] = []
    @State private var sbloccoAlle = Date()
    private let simboli = ["0x1F", "A7", "C3", "9E", "4B", "D0", "77", "E2", "5A"]
    private let orologio = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            switch stato {
            case .prepara:
                Image(systemName: "cpu").font(.system(size: 60)).foregroundStyle(Theme.cyan)
                Card(title: "Impostazioni del GM", icon: "slider.horizontal.3") {
                    Stepper("Livelli da superare: \(livelli)", value: $livelli, in: 1...10)
                    Stepper("Sequenza iniziale: \(lunghezza0)", value: $lunghezza0, in: 2...8)
                    Stepper("Blocco se sbagliano: \(blocco) s", value: $blocco, in: 0...300, step: 10)
                    TextField("Premio mostrato a fine hack (es. un codice)", text: $premio).font(Theme.mono(15, .bold))
                }
                Button { livello = 0; nuovoLivello() } label: { Label("Avvia il terminale", systemImage: "terminal.fill") }.buttonStyle(PrimaryButtonStyle())
            case .violato:
                Image(systemName: "lock.open.fill").font(.system(size: 80)).foregroundStyle(Theme.olive)
                Text("ACCESSO OTTENUTO").font(.system(size: 32, weight: .heavy, design: .monospaced)).foregroundStyle(Theme.olive)
                if !premio.isEmpty { Text(premio).font(Theme.mono(30, .heavy)).padding(14).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12)) }
                Button("Nuova partita") { stato = .prepara }.buttonStyle(.bordered).tint(Theme.olive)
            default:
                Text(stato == .bloccato ? "INTRUSIONE RILEVATA" : stato == .mostra ? "MEMORIZZA LA SEQUENZA" : "RIPETI LA SEQUENZA")
                    .font(.system(size: 18, weight: .heavy, design: .monospaced)).foregroundStyle(stato == .bloccato ? Theme.red : Theme.cyan)
                Text("LIVELLO \(livello + 1)/\(livelli)  ·  \(inserite.count)/\(sequenza.count)").font(Theme.mono(13, .bold)).foregroundStyle(Theme.dim)
                if stato == .bloccato {
                    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                        Text("RIPROVA TRA \(mmss(sbloccoAlle.timeIntervalSinceNow))").font(Theme.mono(22, .heavy)).foregroundStyle(Theme.red)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(0..<9, id: \.self) { i in
                        Button { tocca(i) } label: {
                            Text(simboli[i]).font(.system(size: 20, weight: .heavy, design: .monospaced))
                                .frame(maxWidth: .infinity, minHeight: 84)
                                .foregroundStyle(acceso == i ? .black : Theme.cyan)
                                .background(acceso == i ? Theme.cyan : Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cyan.opacity(0.5)))
                        }
                        .buttonStyle(PressStyle())
                        .disabled(stato != .ripeti)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: 520).frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(orologio) { _ in
            if stato == .bloccato && sbloccoAlle.timeIntervalSinceNow <= 0 { nuovoLivello() }
        }
    }

    func nuovoLivello() {
        sequenza = (0..<(lunghezza0 + livello)).map { _ in Int.random(in: 0..<9) }
        inserite = []; stato = .mostra
        for (k, v) in sequenza.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 + Double(k) * 0.75) { acceso = v; Suono.bip() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 + Double(k) * 0.75 + 0.5) { acceso = nil }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 + Double(sequenza.count) * 0.75) { if stato == .mostra { stato = .ripeti } }
    }

    func tocca(_ i: Int) {
        acceso = i
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { if acceso == i { acceso = nil } }
        guard inserite.count < sequenza.count else { return }
        if sequenza[inserite.count] != i {
            Suono.errore(); stato = .bloccato; livello = 0
            sbloccoAlle = Date().addingTimeInterval(Double(blocco))
            return
        }
        inserite.append(i); haptic()
        if inserite.count == sequenza.count {
            livello += 1
            if livello >= livelli { stato = .violato; Suono.ok() } else { Suono.ok(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { nuovoLivello() } }
        }
    }
}
