import SwiftUI
import AVFoundation

struct MorseView: View {
    enum Modo: String, CaseIterable, Identifiable {
        case ascolta = "Ascolta", luce = "Luce", tasti = "Tasti", trasmetti = "Trasmetti"
        var id: String { rawValue }
    }
    @Binding var input: String
    var vaiADecifra: () -> Void
    @AppStorage("morse.modo") private var modoRaw = Modo.ascolta.rawValue
    @StateObject private var audio = MorseAudioListener()
    @StateObject private var luce = MorseLightListener()
    @StateObject private var tx = MorseTransmitter()
    @EnvironmentObject var log: FieldLog
    @EnvironmentObject var location: LocationService

    var modo: Modo { Modo(rawValue: modoRaw) ?? .ascolta }

    var body: some View {
        VStack(spacing: 12) {
            Picker("Modo", selection: $modoRaw) {
                ForEach(Modo.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .onChange(of: modoRaw) { _ in
                if audio.running { audio.stop() }
                if luce.running { luce.stop() }
                tx.stop()
            }

            switch modo {
            case .ascolta: AscoltaView(m: audio, usa: usa)
            case .luce: LuceView(m: luce, usa: usa)
            case .tasti: TastiView(usa: usa)
            case .trasmetti: TrasmettiView(tx: tx, testoIniziale: input)
            }

            LegendaMorse()
        }
        .onDisappear { if audio.running { audio.stop() }; if luce.running { luce.stop() }; tx.stop() }
    }

    func usa(_ t: String) {
        input = t.trimmingCharacters(in: .whitespaces)
        log.add(.testo, "Morse: \(t.prefix(500))", at: location.location)
        vaiADecifra()
    }
}

/// Testo decodificato grande + simboli in arrivo + azioni.
struct DecodificatoCard: View {
    let testo: String
    let simboli: String
    let acceso: Bool
    var clear: () -> Void
    var usa: (String) -> Void

    var body: some View {
        Card(title: "Decodificato") {
            HStack(alignment: .top) {
                Circle().fill(acceso ? Theme.green : Color.white.opacity(0.15)).frame(width: 14, height: 14).padding(.top, 6)
                VStack(alignment: .leading, spacing: 4) {
                    Text(testo.isEmpty ? "…" : testo).font(Theme.mono(24, .bold)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(simboli.isEmpty ? " " : simboli).font(Theme.mono(18)).foregroundStyle(Theme.gold)
                }
            }
            HStack {
                Button { copyToClipboard(testo) } label: { Label("Copia", systemImage: "doc.on.doc") }
                Button { usa(testo) } label: { Label("Decifra", systemImage: "wand.and.stars") }.disabled(testo.isEmpty)
                Spacer()
                Button(role: .destructive) { clear() } label: { Image(systemName: "trash") }
            }
            .font(.footnote).buttonStyle(.bordered)
        }
    }
}

struct AscoltaView: View {
    @ObservedObject var m: MorseAudioListener
    var usa: (String) -> Void
    @AppStorage("morse.sens") private var sens = 0.5
    @AppStorage("morse.freqAuto") private var freqAuto = true
    @AppStorage("morse.freq") private var freq = 700.0

    var body: some View {
        Button { applica(); m.toggle() } label: {
            Label(m.running ? "FERMA ASCOLTO" : "ASCOLTA DAL MICROFONO", systemImage: m.running ? "stop.fill" : "mic.fill")
                .font(.headline).frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent).tint(m.running ? Theme.red : Theme.gold).foregroundStyle(.black)
        if let e = m.errore { Text(e).font(.footnote).foregroundStyle(Theme.red) }

        Card {
            HStack {
                Stat(t: "Tono", v: m.frequenza > 0 ? String(format: "%.0f Hz", m.frequenza) : "—")
                Stat(t: "Velocità", v: m.wpm > 0 && !m.testo.isEmpty ? "\(m.wpm) WPM" : "—")
            }
            Livello(v: m.livello, acceso: m.acceso)
            Toggle("Tono automatico", isOn: $freqAuto).font(.footnote).onChange(of: freqAuto) { _ in applica() }
            if !freqAuto {
                Slider(value: $freq, in: 300...2000, step: 10) { Text("Hz") } onEditingChanged: { _ in applica() }
                Text(String(format: "%.0f Hz", freq)).font(.caption).foregroundStyle(Theme.dim)
            }
            HStack {
                Text("Sensibilità").font(.footnote)
                Slider(value: $sens, in: 0...1) { _ in applica() }
            }
            Text("Avvicina il telefono alla radio o all'altoparlante. Tono e velocità si adattano da soli.")
                .font(.caption2).foregroundStyle(Theme.dim)
        }
        DecodificatoCard(testo: m.testo, simboli: m.simboli, acceso: m.acceso, clear: m.clear, usa: usa)
    }

    func applica() { m.sensibilita = sens; m.frequenzaFissa = freqAuto ? nil : freq }
}

struct LuceView: View {
    @ObservedObject var m: MorseLightListener
    var usa: (String) -> Void
    @AppStorage("morse.sensLuce") private var sens = 0.5

    var body: some View {
        ZStack {
            CameraPreview(session: m.session).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 14))
            RoundedRectangle(cornerRadius: 4).stroke(m.acceso ? Theme.green : Theme.gold, lineWidth: 3).frame(width: 64, height: 64)
            if !m.running {
                Text("Inquadra la luce nel quadrato").font(.footnote).padding(8).background(.black.opacity(0.6), in: Capsule())
            }
        }
        Button { m.sensibilita = sens; m.toggle() } label: {
            Label(m.running ? "FERMA" : "LEGGI LA LUCE", systemImage: m.running ? "stop.fill" : "flashlight.on.fill")
                .font(.headline).frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent).tint(m.running ? Theme.red : Theme.gold).foregroundStyle(.black)
        if let e = m.errore { Text(e).font(.footnote).foregroundStyle(Theme.red) }
        Card {
            Stat(t: "Velocità", v: m.wpm > 0 && !m.testo.isEmpty ? "\(m.wpm) WPM" : "—")
            Livello(v: m.livello, acceso: m.acceso)
            HStack {
                Text("Sensibilità").font(.footnote)
                Slider(value: $sens, in: 0...1) { _ in m.sensibilita = sens }
            }
            Text("Tieni il telefono fermo (meglio appoggiato). L'esposizione si blocca dopo 1 s: avvia con la luce spenta.")
                .font(.caption2).foregroundStyle(Theme.dim)
        }
        DecodificatoCard(testo: m.testo, simboli: m.simboli, acceso: m.acceso, clear: m.clear, usa: usa)
    }
}

struct Stat: View {
    let t: String, v: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t.uppercased()).font(.caption2).foregroundStyle(Theme.dim)
            Text(v).font(Theme.mono(17, .bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Livello: View {
    let v: Double, acceso: Bool
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(acceso ? Theme.green : Theme.gold.opacity(0.6)).frame(width: g.size.width * max(0.02, min(1, v)))
            }
        }
        .frame(height: 10)
    }
}

struct TastiView: View {
    var usa: (String) -> Void
    @State private var simbolo = ""
    @State private var testo = ""
    @State private var codici = ""

    var body: some View {
        Card(title: "Componi") {
            Text(testo.isEmpty ? "…" : testo).font(Theme.mono(24, .bold)).frame(maxWidth: .infinity, alignment: .leading)
            Text(simbolo.isEmpty ? " " : "\(simbolo)  →  \(MorseTiming.lettera(simbolo))").font(Theme.mono(18)).foregroundStyle(Theme.gold)
            Text(codici).font(Theme.mono(12)).foregroundStyle(Theme.dim).lineLimit(3)
            HStack(spacing: 8) {
                grande("·") { simbolo.append(".") }
                grande("—") { simbolo.append("-") }
            }
            HStack(spacing: 8) {
                piccolo("Lettera") { chiudi() }
                piccolo("Spazio") { chiudi(); testo.append(" "); codici.append(" / ") }
                piccolo("⌫") {
                    if !simbolo.isEmpty { simbolo.removeLast() } else if !testo.isEmpty { testo.removeLast() }
                }
            }
            HStack {
                Button { copyToClipboard(testo) } label: { Label("Copia", systemImage: "doc.on.doc") }
                Button { chiudi(); usa(testo) } label: { Label("Decifra", systemImage: "wand.and.stars") }
                Spacer()
                Button(role: .destructive) { simbolo = ""; testo = ""; codici = "" } label: { Image(systemName: "trash") }
            }
            .font(.footnote).buttonStyle(.bordered)
        }
    }

    func chiudi() {
        guard !simbolo.isEmpty else { return }
        testo.append(MorseTiming.lettera(simbolo))
        codici.append(simbolo + " ")
        simbolo = ""
    }

    func grande(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button { a(); UIImpactFeedbackGenerator(style: .medium).impactOccurred() } label: {
            Text(t).font(.system(size: 40, weight: .heavy)).frame(maxWidth: .infinity, minHeight: 72)
        }
        .buttonStyle(.borderedProminent).tint(Theme.gold).foregroundStyle(.black)
    }

    func piccolo(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Text(t).font(.callout.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44) }.buttonStyle(.bordered)
    }
}

struct TrasmettiView: View {
    @ObservedObject var tx: MorseTransmitter
    let testoIniziale: String
    @State private var testo = ""
    @AppStorage("tx.wpm") private var wpm = 12.0
    @AppStorage("tx.suono") private var suono = true
    @AppStorage("tx.torcia") private var torcia = false
    @AppStorage("tx.vibra") private var vibra = false

    var morse: String { Cipher.morseEncode(testo) }

    var body: some View {
        Card(title: "Testo da trasmettere") {
            TextField("SOS", text: $testo).font(Theme.mono(18)).textFieldStyle(.roundedBorder)
                .autocorrectionDisabled().textInputAutocapitalization(.characters)
            // morse con il simbolo in trasmissione evidenziato
            Text(evidenziato).font(Theme.mono(18)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            HStack {
                Toggle(isOn: $suono) { Image(systemName: "speaker.wave.2.fill") }.toggleStyle(.button)
                Toggle(isOn: $torcia) { Image(systemName: "flashlight.on.fill") }.toggleStyle(.button)
                Toggle(isOn: $vibra) { Image(systemName: "iphone.radiowaves.left.and.right") }.toggleStyle(.button)
                Spacer()
                Text("\(Int(wpm)) WPM").font(Theme.mono(13))
                Stepper("", value: $wpm, in: 4...30, step: 1).labelsHidden()
            }
            Button {
                if tx.playing { tx.stop() } else {
                    tx.suono = suono; tx.torcia = torcia; tx.vibrazione = vibra; tx.wpm = wpm
                    tx.play(morse)
                }
            } label: {
                Label(tx.playing ? "FERMA" : "TRASMETTI", systemImage: tx.playing ? "stop.fill" : "play.fill")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent).tint(tx.playing ? Theme.red : Theme.gold).foregroundStyle(.black)
            .disabled(morse.isEmpty)
            Button { copyToClipboard(morse) } label: { Label("Copia il Morse", systemImage: "doc.on.doc") }.font(.footnote).buttonStyle(.bordered)
        }
        .onAppear { if testo.isEmpty { testo = String(testoIniziale.prefix(60)) } }
    }

    var evidenziato: AttributedString {
        var a = AttributedString()
        for (i, c) in morse.enumerated() {
            var s = AttributedString(String(c))
            if i == tx.corrente { s.foregroundColor = Theme.gold; s.backgroundColor = .white.opacity(0.2) }
            a.append(s)
        }
        return a
    }
}

struct LegendaMorse: View {
    @AppStorage("morse.legenda") private var aperta = false
    let righe: [(String, String)] = (Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")).map { (String($0), Cipher.morse[$0] ?? "") }

    var body: some View {
        DisclosureGroup("Legenda Morse", isExpanded: $aperta) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 6) {
                ForEach(righe, id: \.0) { r in
                    HStack(spacing: 4) {
                        Text(r.0).font(Theme.mono(14, .bold)).foregroundStyle(Theme.gold)
                        Text(r.1.replacingOccurrences(of: ".", with: "·").replacingOccurrences(of: "-", with: "—")).font(Theme.mono(13))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 6)
        }
        .font(.footnote).padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }
}
