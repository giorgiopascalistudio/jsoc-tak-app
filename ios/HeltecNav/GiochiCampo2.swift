import SwiftUI
import AudioToolbox
import Combine

// MARK: - Altri giochi da campo: disinnesco a cavi, upload dati, cassaforte

private enum Suono2 {
    static func bip() { AudioServicesPlaySystemSound(1103) }
    static func ok() { AudioServicesPlaySystemSound(1407) }
    static func errore() { AudioServicesPlaySystemSound(1053); AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) }
    static func allarme() { AudioServicesPlaySystemSound(1005); AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) }
}

private func mmss2(_ s: Double) -> String {
    let t = max(0, Int(s.rounded(.up)))
    return String(format: "%02d:%02d", t / 60, t % 60)
}

// MARK: Disinnesco a cavi

struct CaviView: View {
    enum Stato { case prepara, armata, esplosa, salva }
    private let colori: [(String, Color)] = [("ROSSO", .red), ("BLU", .blue), ("GIALLO", .yellow), ("VERDE", .green), ("BIANCO", .white), ("NERO", .gray)]
    @State private var stato = Stato.prepara
    @State private var minuti = 5
    @State private var quanti = 5
    @State private var sequenza: [Int] = []
    @State private var tagliati: [Int] = []
    @State private var fine = Date()
    @State private var mostraSequenza = false
    private let orologio = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            switch stato {
            case .prepara:
                Image(systemName: "scissors").font(.system(size: 56)).foregroundStyle(Theme.red)
                Card(title: "Impostazioni del GM", icon: "slider.horizontal.3") {
                    Stepper("Timer: \(minuti) min", value: $minuti, in: 1...60)
                    Stepper("Cavi da tagliare: \(quanti)", value: $quanti, in: 2...6)
                    Toggle("Mostrami la sequenza giusta", isOn: $mostraSequenza)
                    if mostraSequenza, !sequenza.isEmpty {
                        Text(sequenza.map { colori[$0].0 }.joined(separator: " → ")).font(Theme.mono(13, .bold))
                    }
                }
                Button("Nuova sequenza") { nuovaSequenza() }.buttonStyle(.bordered).tint(Theme.olive)
                Button {
                    if sequenza.count != quanti { nuovaSequenza() }
                    tagliati = []; fine = Date().addingTimeInterval(Double(minuti * 60)); stato = .armata; Suono2.allarme()
                } label: { Label("ARMA", systemImage: "bolt.fill") }
                .buttonStyle(PrimaryButtonStyle())
                Text("La sequenza va scoperta in un'altra fase (cifrario, documento) o data a chi difende. Un taglio sbagliato fa esplodere.")
                    .font(.caption).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            case .armata:
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    Text(mmss2(fine.timeIntervalSinceNow)).font(.system(size: 70, weight: .heavy, design: .monospaced)).foregroundStyle(Theme.red)
                }
                Text("TAGLIATI \(tagliati.count)/\(sequenza.count)").font(.caption.weight(.heavy)).foregroundStyle(Theme.dim)
                VStack(spacing: 10) {
                    ForEach(0..<colori.count, id: \.self) { i in
                        let taglio = tagliati.contains(i)
                        Button { taglia(i) } label: {
                            HStack(spacing: 0) {
                                Capsule().fill(colori[i].1).frame(height: 10)
                                if taglio {
                                    Image(systemName: "scissors").foregroundStyle(.white).padding(.horizontal, 6)
                                    Capsule().fill(colori[i].1.opacity(0.3)).frame(height: 10)
                                }
                            }
                            .frame(height: 44).padding(.horizontal, 10)
                            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(taglio)
                        .accessibilityLabel("Cavo \(colori[i].0)")
                    }
                }
                .animation(.spring(response: 0.3), value: tagliati)
            case .esplosa:
                Image(systemName: "flame.fill").font(.system(size: 90)).foregroundStyle(Theme.red)
                Text("ESPLOSA").font(.system(size: 40, weight: .heavy)).foregroundStyle(Theme.red)
                Button("Nuova partita") { stato = .prepara; sequenza = [] }.buttonStyle(.bordered).tint(Theme.olive)
            case .salva:
                Image(systemName: "checkmark.shield.fill").font(.system(size: 90)).foregroundStyle(Theme.olive)
                Text("DISINNESCATA").font(.system(size: 36, weight: .heavy)).foregroundStyle(Theme.olive)
                Button("Nuova partita") { stato = .prepara; sequenza = [] }.buttonStyle(.bordered).tint(Theme.olive)
            }
        }
        .padding(18).frame(maxWidth: 520).frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(orologio) { _ in
            if stato == .armata && fine.timeIntervalSinceNow <= 0 { stato = .esplosa; Suono2.allarme() }
        }
    }

    func nuovaSequenza() { sequenza = Array(Array(0..<colori.count).shuffled().prefix(quanti)) }

    func taglia(_ i: Int) {
        haptic(.heavy)
        guard tagliati.count < sequenza.count, sequenza[tagliati.count] == i else { stato = .esplosa; Suono2.allarme(); return }
        tagliati.append(i); Suono2.bip()
        if tagliati.count == sequenza.count { stato = .salva; Suono2.ok() }
    }
}

// MARK: Upload dati

struct UploadView: View {
    @State private var secondi = 60
    @State private var progresso: Double = 0
    @State private var premuto = false
    @State private var fatto = false
    @State private var premio = ""
    @State private var pronto = false
    private let orologio = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 18) {
            if !pronto {
                Image(systemName: "arrow.up.doc.fill").font(.system(size: 56)).foregroundStyle(Theme.cyan)
                Card(title: "Impostazioni del GM", icon: "slider.horizontal.3") {
                    Stepper("Durata dell'upload: \(secondi) s", value: $secondi, in: 10...600, step: 10)
                    TextField("Premio a fine upload (es. un codice)", text: $premio).font(Theme.mono(15, .bold))
                }
                Button { progresso = 0; fatto = false; pronto = true } label: { Label("Avvia il terminale", systemImage: "terminal") }.buttonStyle(PrimaryButtonStyle())
                Text("Per caricare i dati bisogna tenere premuto senza staccare: se lasci, l'upload perde terreno.")
                    .font(.caption).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            } else if fatto {
                Image(systemName: "checkmark.icloud.fill").font(.system(size: 80)).foregroundStyle(Theme.olive)
                Text("UPLOAD COMPLETATO").font(.system(size: 28, weight: .heavy, design: .monospaced)).foregroundStyle(Theme.olive)
                if !premio.isEmpty { Text(premio).font(Theme.mono(30, .heavy)).padding(14).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12)) }
                Button("Nuova partita") { pronto = false }.buttonStyle(.bordered).tint(Theme.olive)
            } else {
                Text("\(Int(progresso * 100))%").font(.system(size: 70, weight: .heavy, design: .monospaced)).foregroundStyle(Theme.cyan)
                ProgressView(value: progresso).tint(Theme.cyan).scaleEffect(y: 3)
                Circle().fill(premuto ? Theme.cyan : Theme.surface2).frame(width: 170, height: 170)
                    .overlay(Text(premuto ? "CARICO…" : "TIENI PREMUTO").font(.headline.weight(.heavy)).foregroundStyle(premuto ? .black : Theme.cyan))
                    .overlay(Circle().strokeBorder(Theme.cyan, lineWidth: 3))
                    .scaleEffect(premuto ? 0.95 : 1)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { _ in if !premuto { premuto = true; haptic() } }.onEnded { _ in premuto = false })
                    .animation(.spring(response: 0.3), value: premuto)
            }
        }
        .padding(18).frame(maxWidth: 520).frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(orologio) { _ in
            guard pronto, !fatto else { return }
            progresso = premuto ? min(1, progresso + 0.1 / Double(secondi)) : max(0, progresso - 0.05 / Double(secondi))
            if progresso >= 1 { fatto = true; premuto = false; Suono2.ok() }
        }
    }
}

// MARK: Cassaforte

struct CassaforteView: View {
    @State private var combinazione = ""
    @State private var cifre = [0, 0, 0, 0]
    @State private var pronta = false
    @State private var aperta = false
    @State private var tentativi = 0
    @State private var contenuto = ""

    var body: some View {
        VStack(spacing: 18) {
            if !pronta {
                Image(systemName: "lock.square.stack.fill").font(.system(size: 56)).foregroundStyle(Theme.amber)
                Card(title: "Impostazioni del GM", icon: "slider.horizontal.3") {
                    SecureField("Combinazione a 4 cifre", text: $combinazione).keyboardType(.numberPad).font(Theme.mono(18, .bold))
                    TextField("Cosa c'è dentro (es. coordinate, codice)", text: $contenuto)
                }
                Button { cifre = [0, 0, 0, 0]; aperta = false; tentativi = 0; pronta = true } label: { Label("Chiudi la cassaforte", systemImage: "lock.fill") }
                    .buttonStyle(PrimaryButtonStyle()).disabled(combinazione.count != 4 || Int(combinazione) == nil)
            } else if aperta {
                Image(systemName: "lock.open.fill").font(.system(size: 80)).foregroundStyle(Theme.olive)
                Text("APERTA").font(.system(size: 36, weight: .heavy)).foregroundStyle(Theme.olive)
                Text("in \(tentativi) tentativi").foregroundStyle(Theme.dim)
                if !contenuto.isEmpty { Text(contenuto).font(Theme.mono(22, .heavy)).padding(14).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12)) }
                Button("Nuova partita") { pronta = false }.buttonStyle(.bordered).tint(Theme.olive)
            } else {
                HStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { i in
                        VStack(spacing: 8) {
                            Button { cifre[i] = (cifre[i] + 1) % 10; haptic() } label: { Image(systemName: "chevron.up").font(.title2.weight(.heavy)) }
                            Text("\(cifre[i])").font(.system(size: 52, weight: .heavy, design: .monospaced)).frame(width: 62, height: 80)
                                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                            Button { cifre[i] = (cifre[i] + 9) % 10; haptic() } label: { Image(systemName: "chevron.down").font(.title2.weight(.heavy)) }
                        }
                        .tint(Theme.amber)
                    }
                }
                .animation(.spring(response: 0.25), value: cifre)
                Button {
                    tentativi += 1
                    if cifre.map(String.init).joined() == combinazione { withAnimation(.spring()) { aperta = true }; Suono2.ok() } else { Suono2.errore() }
                } label: { Label("Gira la maniglia", systemImage: "arrow.clockwise") }.buttonStyle(PrimaryButtonStyle())
                Text("Tentativi: \(tentativi)").font(.caption).foregroundStyle(Theme.dim)
            }
        }
        .padding(18).frame(maxWidth: 520).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
