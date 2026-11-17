import SwiftUI
import CoreLocation

/// Stato delle due macchine (PC e server), aggiornato ogni 15 s mentre è visibile.
@MainActor
final class Fleet: ObservableObject {
    @Published var stato: [Target: ServerStatus] = [:]
    @Published var errore: [Target: Bool] = [:]
    @Published var operatori: Int?

    func load(_ client: ServerClient) async {
        await client.probe()
        // tutte le richieste insieme: con il relè di Tailscale ognuna costa quasi un secondo
        let cp = client.configured(.pc), cs = client.configured(.server)
        async let a: ServerStatus? = cp ? (try? await client.status(on: .pc)) : nil
        async let b: ServerStatus? = cs ? (try? await client.status(on: .server)) : nil
        async let o: [Operator]? = cs ? (try? await client.operators()) : nil
        let (spc, ssrv, ops) = await (a, b, o)
        withAnimation(.easeInOut(duration: 0.3)) {
            if cp { if let spc { stato[.pc] = spc; errore[.pc] = false } else { errore[.pc] = true } }
            if cs { if let ssrv { stato[.server] = ssrv; errore[.server] = false } else { errore[.server] = true } }
        }
        if let ops { operatori = ops.filter { $0.collegato && !$0.isBot }.count }
    }
}

struct GaraTab: View {
    @EnvironmentObject var location: LocationService
    @EnvironmentObject var mission: Mission
    @EnvironmentObject var client: ServerClient
    @EnvironmentObject var claude: ClaudeModel
    @StateObject private var fleet = Fleet()
    @Environment(\.verticalSizeClass) var vsc

    var body: some View {
        NavigationStack {
            ScrollView {
                if vsc == .compact {
                    // orizzontale: countdown e obiettivo a sinistra, il resto a destra
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 14) {
                            TailscaleBanner()
                            CountdownHero(compatto: true).reveal(0)
                            ProssimoObjCard().reveal(1)
                            RadioCard().reveal(2)
                            PosizioneCard().reveal(3)
                            CodiciCard().reveal(4)
                        }
                        VStack(spacing: 14) {
                            MacchineCard(fleet: fleet).reveal(1)
                            PercorsoCard().reveal(2)
                            AmbienteCard().reveal(3)
                            DynamicIslandCard().reveal(4)
                            TimelineCard().reveal(5)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                } else {
                    VStack(spacing: 14) {
                        TailscaleBanner()
                        CountdownHero().reveal(0)
                        ProssimoObjCard().reveal(1)
                        MacchineCard(fleet: fleet).reveal(2)
                        PercorsoCard().reveal(3)
                        RadioCard().reveal(4)
                        AmbienteCard().reveal(5)
                        DynamicIslandCard().reveal(6)
                        PosizioneCard().reveal(7)
                        CodiciCard().reveal(8)
                        TimelineCard().reveal(9)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Re Mida")
            .nightToggle()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink { ServerView() } label: { Image(systemName: "server.rack") }
                }
            }
            .refreshable { await fleet.load(client) }
            .task {
                while !Task.isCancelled {
                    await fleet.load(client)
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                }
            }
        }
    }
}

// MARK: - Countdown con radar

struct CountdownHero: View {
    var compatto = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let now = ctx.date
            ZStack {
                RadarView().frame(width: compatto ? 190 : 250, height: compatto ? 190 : 250).opacity(0.9)
                VStack(spacing: 6) {
                    if let ev = Shared.prossimo(now) {
                        Text("PROSSIMO").font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(2.5)
                            .foregroundStyle(Theme.olive)
                        Text(ev.title).font(.title3.weight(.bold)).multilineTextAlignment(.center)
                        Text(Self.format(ev.date.timeIntervalSince(now)))
                            .font(.system(size: 40, weight: .bold, design: .monospaced))
                            .monospacedDigit().numericTransition()
                            .foregroundStyle(.white)
                            .shadow(color: Theme.olive.opacity(0.35), radius: 10)
                            .animation(.default, value: Int(ev.date.timeIntervalSince(now)))
                        Text(ev.date.formatted(.dateTime.weekday(.wide).day().month().hour().minute()))
                            .font(Theme.mono(12)).foregroundStyle(Theme.dim)
                        if !ev.detail.isEmpty {
                            Text(ev.detail).font(.footnote).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                    } else {
                        Text("Gara conclusa").font(.title2.weight(.bold))
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: compatto ? 190 : 250)
        }
    }

    static func format(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60, sec = s % 60
        return d > 0 ? String(format: "%dg %02d:%02d:%02d", d, h, m, sec) : String(format: "%02d:%02d:%02d", h, m, sec)
    }
}

// MARK: - Prossimo OBJ

struct ProssimoObjCard: View {
    @EnvironmentObject var mission: Mission
    @EnvironmentObject var location: LocationService
    @EnvironmentObject var docs: DocStore

    @State private var conferma = false

    var body: some View {
        Card(title: "Prossimo obiettivo", icon: "scope",
             trailing: mission.inizioPercorso.map { "partiti " + $0.formatted(date: .omitted, time: .shortened) }) {
            if mission.inizioPercorso != nil {
                HStack {
                    Spacer()
                    Menu {
                        Button { mission.fermaPercorso() } label: { Label("Ferma percorso", systemImage: "stop.circle") }
                        Button(role: .destructive) { conferma = true } label: {
                            Label("Azzera prova (OBJ e orari)", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Label("Percorso", systemImage: "ellipsis.circle").font(.caption.weight(.semibold))
                    }
                }
                .confirmationDialog("Azzerare il percorso di prova?", isPresented: $conferma, titleVisibility: .visible) {
                    Button("Azzera tutto", role: .destructive) { mission.azzeraPercorso() }
                } message: { Text("Toglie l'avvio, gli OBJ segnati fatti e i loro orari.") }
            }
            if let t = mission.prossima {
                if let f = docs.fascicolo(prefix: t.code) {
                    NavigationLink { FascicoloView(name: f.name) } label: {
                        HStack {
                            Image(systemName: "folder.fill")
                            Text("Fascicolo \(t.code): riepilogo, kit, originali, analisi").font(.caption.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.bold))
                        }
                        .foregroundStyle(Theme.olive)
                        .padding(10)
                        .background(Theme.olive.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(PressStyle())
                }
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t.code).font(.system(size: 30, weight: .heavy, design: .monospaced)).foregroundStyle(Theme.olive)
                        Text(t.nome).font(.headline)
                        if let v = mission.versoProssima(from: location.location) {
                            Text("\(v.dist) · \(v.dir)").font(Theme.mono(14, .semibold)).numericTransition()
                        } else {
                            Text("posizione in attesa…").font(.caption).foregroundStyle(Theme.dim)
                        }
                    }
                    Spacer()
                    Bussola(gradi: freccia)
                        .frame(width: 84, height: 84)
                }
                if mission.inizioPercorso == nil {
                    Button { mission.avviaPercorso() } label: {
                        Label("Avvia percorso", systemImage: "figure.walk.departure")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Text("Dopo l'avvio: arrivato all'OBJ tocchi \"Entro\" e parte il timer della finestra.")
                        .font(.caption).foregroundStyle(Theme.dim)
                } else if let f = mission.finestra, f.code == t.code {
                    FinestraTimer(f: f)
                } else {
                    HStack(spacing: 10) {
                        Button { mission.apriFinestra(t.code) } label: {
                            Label("Entro in \(t.code) · \(Mission.durata(t.code))'", systemImage: "timer")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        Button { mission.toggle(t) } label: {
                            Image(systemName: "checkmark.seal.fill").font(.title3)
                                .frame(width: 50, height: 44)
                                .background(Theme.olive.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Segna \(t.code) fatto")
                    }
                }
            } else {
                Label("Percorso completato", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(Theme.olive)
            }
        }
    }

    /// Angolo della freccia: rispetto al telefono se c'è la bussola, altrimenti rispetto al nord.
    var freccia: Double {
        guard let v = mission.versoProssima(from: location.location) else { return 0 }
        return v.gradi - (location.heading ?? 0)
    }
}

/// Cronometro della finestra di ingaggio: anello che si svuota, minuti e secondi, avvisi colorati.
struct FinestraTimer: View {
    let f: (code: String, inizio: Date, fine: Date)
    @EnvironmentObject var mission: Mission

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let tot = f.fine.timeIntervalSince(f.inizio), rest = max(0, f.fine.timeIntervalSince(ctx.date))
            let col: Color = rest < 60 ? Theme.red : (rest < 300 ? Theme.amber : Theme.olive)
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 7)
                    Circle().trim(from: 0, to: rest / tot)
                        .stroke(col, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: rest)
                    Text(String(format: "%02d:%02d", Int(rest) / 60, Int(rest) % 60))
                        .font(.system(size: 20, weight: .bold, design: .monospaced)).monospacedDigit().numericTransition()
                        .foregroundStyle(col)
                }
                .frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 8) {
                    Text(rest > 0 ? "FINESTRA IN CORSO" : "FINESTRA CHIUSA")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(1.5).foregroundStyle(col)
                    Text("aperta alle \(f.inizio.formatted(date: .omitted, time: .shortened)) · fine \(f.fine.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(Theme.dim)
                    HStack {
                        Button("Fatto") { mission.chiudiFinestra(fatto: true) }.buttonStyle(.borderedProminent).tint(Theme.olive)
                        Button("Annulla") { mission.chiudiFinestra(fatto: false) }.buttonStyle(.bordered).tint(Theme.dim)
                    }
                    .font(.caption.weight(.bold))
                }
            }
        }
    }
}

struct Bussola: View {
    let gradi: Double
    var body: some View {
        ZStack {
            Circle().fill(Theme.olive.opacity(0.08))
            Circle().strokeBorder(Theme.stroke, lineWidth: 1)
            ForEach(0..<12) { i in
                Rectangle().fill(Theme.olive.opacity(i % 3 == 0 ? 0.6 : 0.25))
                    .frame(width: 1.5, height: i % 3 == 0 ? 8 : 4)
                    .offset(y: -36).rotationEffect(.degrees(Double(i) * 30))
            }
            Image(systemName: "location.north.fill").font(.system(size: 30))
                .foregroundStyle(Theme.olive)
                .rotationEffect(.degrees(gradi))
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: gradi)
        }
    }
}

// MARK: - Macchine (PC e server)

struct MacchineCard: View {
    @ObservedObject var fleet: Fleet
    var link = true
    @EnvironmentObject var client: ServerClient

    var body: some View {
        if link {
            NavigationLink { ServerView() } label: { contenuto }.buttonStyle(PressStyle())
        } else {
            contenuto
        }
    }

    var contenuto: some View {
            Card(title: "Macchine", icon: "cpu", trailing: fleet.operatori.map { "\($0) operatori online" }) {
                HStack(alignment: .top, spacing: 12) {
                    MachineTile(target: .pc, stato: fleet.stato[.pc], errore: fleet.errore[.pc] ?? false,
                                configurato: client.configured(.pc), inUso: client.brain == .pc)
                    Divider().background(Theme.stroke)
                    MachineTile(target: .server, stato: fleet.stato[.server], errore: fleet.errore[.server] ?? false,
                                configurato: client.configured(.server), inUso: client.brain == .server)
                }
            }
    }
}

struct MachineTile: View {
    let target: Target
    let stato: ServerStatus?
    let errore: Bool
    let configurato: Bool
    let inUso: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                StatusDot(on: !configurato ? nil : (errore ? false : (stato?.tuttoOk ?? true)), size: 8)
                Image(systemName: target.icon).font(.caption)
                Text(target.label).font(.subheadline.weight(.bold))
                Spacer(minLength: 0)
                if inUso {
                    Text("CLAUDE").font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(Theme.olive.opacity(0.25), in: Capsule()).foregroundStyle(Theme.olive)
                }
            }
            if !configurato {
                Text("da collegare").font(.caption).foregroundStyle(Theme.dim)
            } else if errore {
                Text("non risponde").font(.caption.weight(.semibold)).foregroundStyle(Theme.red)
            } else if let s = stato {
                MeterBar(label: "CPU", value: cpu(s), text: s.carico.first ?? "?")
                MeterBar(label: "RAM", value: Double(s.memoria_pct) / 100, text: "\(s.memoria_pct)%")
                MeterBar(label: "Disco", value: Double(s.disco_pct) / 100, text: String(format: "%.0f GB liberi", s.disco_libero_gb), warnAt: 0.95)
                if let b = s.batteria {
                    MeterBar(label: s.alimentato == true ? "Batteria · in carica" : "Batteria · SCOLLEGATO",
                             value: Double(b) / 100, text: "\(b)%", warnAt: 0.8, inverted: true)
                } else if let t = s.temperatura {
                    MeterBar(label: "Temperatura", value: t / 85, text: String(format: "%.0f °C", t), warnAt: 0.88)
                }
                Text("acceso da \(String(format: "%.0f", s.uptime_ore)) h").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.dim)
            } else {
                ProgressView().tint(Theme.olive)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func cpu(_ s: ServerStatus) -> Double {
        let raw = (s.carico.first ?? "0").replacingOccurrences(of: "%", with: "")
        let v = Double(raw) ?? 0
        return s.carico.first?.contains("%") == true ? v / 100 : v / 4   // server: carico medio su 4 core
    }
}

// MARK: - Percorso

struct PercorsoCard: View {
    @EnvironmentObject var mission: Mission
    @EnvironmentObject var location: LocationService
    @EnvironmentObject var docs: DocStore

    var body: some View {
        Card(title: "Percorso Fase FERRO", icon: "point.topleft.down.curvedto.point.bottomright.up") {
            HStack(spacing: 14) {
                ZStack {
                    ProgressRing(progress: mission.avanzamento)
                    Text("\(Int(mission.avanzamento * Double(Gara.percorso.count)))/\(Gara.percorso.count)")
                        .font(Theme.mono(13, .bold)).numericTransition()
                }
                .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 2) {
                    Text("~15 km · finisce a FF03").font(.subheadline.weight(.semibold))
                    Text("FF04 non è nel percorso · tocca un OBJ per segnarlo fatto").font(.caption).foregroundStyle(Theme.dim)
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(Gara.percorso.enumerated()), id: \.element.id) { i, t in
                    let fatto = mission.fatti.contains(t.code)
                    let prossima = mission.prossima == t
                    Button { mission.toggle(t) } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                if i < Gara.percorso.count - 1 {
                                    Rectangle().fill(fatto ? Theme.olive : Theme.stroke).frame(width: 2, height: 34).offset(y: 17)
                                }
                                Circle().fill(fatto ? Theme.olive : Theme.bg).frame(width: 18, height: 18)
                                    .overlay(Circle().strokeBorder(prossima ? Theme.olive : Theme.stroke, lineWidth: prossima ? 2 : 1))
                                if fatto { Image(systemName: "checkmark").font(.system(size: 9, weight: .black)).foregroundStyle(.black) }
                            }
                            .frame(width: 22, height: 34)
                            Text(t.code).font(Theme.mono(13, .bold)).foregroundStyle(fatto ? Theme.dim : Theme.olive)
                            Text(t.nome).font(.subheadline).foregroundStyle(fatto ? Theme.dim : .white).strikethrough(fatto, color: Theme.dim)
                            Spacer()
                            if prossima { Text("PROSSIMO").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(Theme.olive) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .overlay(alignment: .trailing) {
                        if let f = docs.fascicolo(prefix: t.code) {
                            NavigationLink { FascicoloView(name: f.name) } label: {
                                Image(systemName: "folder").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.olive)
                                    .frame(width: 40, height: 34)
                            }
                            .offset(x: prossima ? -62 : 0)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Dynamic Island

struct DynamicIslandCard: View {
    @EnvironmentObject var mission: Mission
    @EnvironmentObject var location: LocationService
    @EnvironmentObject var client: ServerClient
    @EnvironmentObject var claude: ClaudeModel

    var body: some View {
        Card(title: "Dynamic Island e blocco schermo", icon: "capsule.portrait") {
            Toggle(isOn: Binding(get: { mission.liveOn }, set: { on in
                haptic(.medium)
                if on { mission.startLive(location: location, client: client, claude: claude) } else { mission.stopLive() }
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(mission.liveOn ? "Attiva" : "Spenta").font(.subheadline.weight(.semibold))
                    Text("Countdown, prossimo OBJ con direzione, UTM, PC e server").font(.caption).foregroundStyle(Theme.dim)
                }
            }
            .tint(Theme.olive)
            if let e = mission.liveError { Text(e).font(.caption).foregroundStyle(Theme.red) }
        }
    }
}

// MARK: - Posizione, codici, timeline

struct PosizioneCard: View {
    @EnvironmentObject var location: LocationService

    var body: some View {
        Card(title: "Posizione", icon: "location") {
            if let l = location.location {
                let u = UTM.fromLatLon(l.coordinate.latitude, l.coordinate.longitude)
                Text(u.text).font(.system(size: 22, weight: .bold, design: .monospaced)).numericTransition().textSelection(.enabled)
                Text("MGRS " + Geo.mgrs(l.coordinate)).font(Theme.mono(13)).foregroundStyle(Theme.dim)
                Text(String(format: "%.6f, %.6f · quota %.0f m · ±%.0f m", l.coordinate.latitude, l.coordinate.longitude,
                            l.altitude, l.horizontalAccuracy)).font(Theme.mono(11)).foregroundStyle(Theme.dim)
                Button { copyToClipboard(location.coordText) } label: { Label("Copia", systemImage: "doc.on.doc") }
                    .buttonStyle(.bordered).tint(Theme.olive).font(.caption)
            } else {
                Text("In attesa del GPS…").foregroundStyle(Theme.dim)
            }
        }
    }
}

struct CodiciCard: View {
    @State private var copiato: String?

    var body: some View {
        Card(title: "Codici", icon: "key") {
            ForEach(Gara.codes, id: \.0) { c in
                Button {
                    copyToClipboard(c.1)
                    withAnimation(.spring()) { copiato = c.0 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { if copiato == c.0 { copiato = nil } } }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.0).font(.caption).foregroundStyle(Theme.dim)
                            Text(c.1).font(Theme.mono(15, .semibold)).foregroundStyle(.white)
                        }
                        Spacer()
                        Image(systemName: copiato == c.0 ? "checkmark.circle.fill" : "doc.on.doc")
                            .foregroundStyle(Theme.olive).transition(.scale.combined(with: .opacity))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
    }
}

struct TimelineCard: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            Card(title: "Timeline", icon: "clock") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(Gara.timeline.enumerated()), id: \.element.id) { i, ev in
                        let past = ev.date < ctx.date
                        let next = Gara.timeline.first(where: { $0.date > ctx.date })?.id == ev.id
                        HStack(alignment: .top, spacing: 10) {
                            VStack(spacing: 0) {
                                Circle().fill(next ? Theme.olive : (past ? Theme.stroke : Theme.surface2))
                                    .overlay(Circle().strokeBorder(Theme.olive.opacity(past ? 0.3 : 0.8), lineWidth: 1))
                                    .frame(width: 10, height: 10).padding(.top, 4)
                                if i < Gara.timeline.count - 1 { Rectangle().fill(Theme.stroke).frame(width: 1.5) }
                            }
                            .frame(width: 12)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ev.date.formatted(.dateTime.weekday(.abbreviated).day().hour().minute()))
                                    .font(Theme.mono(11)).foregroundStyle(next ? Theme.olive : Theme.dim)
                                Text(ev.title).font(.subheadline.weight(next ? .bold : .semibold))
                                if !ev.detail.isEmpty { Text(ev.detail).font(.caption).foregroundStyle(Theme.dim) }
                            }
                            .padding(.bottom, 12)
                        }
                        .opacity(past ? 0.4 : 1)
                    }
                }
            }
        }
    }
}
