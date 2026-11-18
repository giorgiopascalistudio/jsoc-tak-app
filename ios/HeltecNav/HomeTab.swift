import SwiftUI
import CoreLocation

extension Notification.Name {
    /// userInfo["tab"] = indice della scheda da aprire
    static let vaiTab = Notification.Name("jsoc.vaiTab")
}

func vaiAllaScheda(_ i: Int) { NotificationCenter.default.post(name: .vaiTab, object: nil, userInfo: ["tab": i]) }

enum Schede { static let home = 0, mappa = 1, eventi = 2, associazione = 3, profilo = 4, strumenti = 5 }

// MARK: - Home (dashboard)

@MainActor
final class HomeModel: ObservableObject {
    static let shared = HomeModel()
    @Published var dati: JHome?
    @Published var errore: String?
    private let file = EventoStore.cartella.appendingPathComponent("home.json")

    init() {
        if let d = try? Data(contentsOf: file) { dati = try? JSONDecoder().decode(JHome.self, from: d) }
    }

    func aggiorna() async {
        guard JsocClient.shared.collegato else { return }
        do {
            let h = try await JsocClient.shared.home()
            dati = h; errore = nil
            if let d = try? JSONEncoder().encode(h) { try? d.write(to: file, options: .atomic) }
        } catch { errore = error.localizedDescription }
    }

    func rispondi(_ ev: Int, _ r: String) async {
        _ = try? await JsocClient.shared.rispondi(ev, r)
        await aggiorna()
        await EventoStore.shared.aggiorna(JsocClient.shared)
    }
}

struct HomeTab: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var store = EventoStore.shared
    @ObservedObject private var home = HomeModel.shared
    @EnvironmentObject var location: LocationService
    @State private var sos = false
    @State private var sosInviato: String?

    var body: some View {
        NavigationStack {
            Group {
                if jsoc.collegato { contenuto } else { EntraView() }
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) {
                        Image("Stemma").resizable().scaledToFit().frame(width: 30, height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        Text("JSOC TAK").font(.system(size: 17, weight: .heavy, design: .monospaced)).tracking(1.5)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { NightToolbarButton() }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .confirmationDialog("Mandare un SOS alla squadra?", isPresented: $sos, titleVisibility: .visible) {
            Button("Invia SOS con la mia posizione", role: .destructive) { mandaSOS() }
        } message: {
            Text("Arriva nella chat dell'evento \(store.corrente?.nome ?? "") con le tue coordinate.")
        }
    }

    var contenuto: some View {
        ScrollView {
            VStack(spacing: 14) {
                saluto.reveal(0)
                if let e = store.corrente { eventoAttivo(e).reveal(1) }
                azioni.reveal(2)
                if let a = home.dati?.avvisi, !a.isEmpty { avvisi(a).reveal(3) }
                if let p = home.dati?.prossimi, !p.isEmpty { prossimi(p).reveal(4) }
                associazione.reveal(5)
                if let e = home.errore, home.dati == nil { ErrorCard(text: e) }
            }
            .padding(14)
        }
        .refreshable { await home.aggiorna(); await store.aggiorna(jsoc) }
        .task { await home.aggiorna() }
    }

    var saluto: some View {
        HStack(spacing: 12) {
            FotoSocio(id: jsoc.utente?.id, iniziali: jsoc.utente?.callsign ?? "?", lato: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(salutoOra + ", " + (jsoc.utente?.callsign ?? "")).font(.title3.weight(.heavy))
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized)
                    .font(Theme.mono(12)).foregroundStyle(Theme.dim)
            }
            Spacer()
            StatusDot(on: jsoc.online)
        }
    }

    var salutoOra: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 13 ? "Buongiorno" : (h < 18 ? "Buon pomeriggio" : "Buonasera")
    }

    // MARK: evento attivo

    func eventoAttivo(_ e: JEvento) -> some View {
        let membri = e.membri ?? []
        let attivi = store.squadra.filter { $0.eta < 300 }.count
        return Card(title: e.fase == 0 ? "In corso" : (e.fase == 1 ? "Prossimo evento" : "Ultimo evento"), icon: e.icona,
                    trailing: e.staff ? "STAFF" : nil) {
            Text(e.nome).font(.title2.weight(.heavy))
            if let i = e.dataInizio {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(e.fase == 1 ? "tra " + conto(i.timeIntervalSince(ctx.date)) : i.formatted(date: .abbreviated, time: .shortened))
                        .font(Theme.mono(15, .bold)).foregroundStyle(Theme.olive)
                }
            }
            HStack(spacing: 10) {
                tessera("person.3.fill", "\(attivi)/\(membri.count)", "in mappa")
                tessera("bubble.left.fill", "\(store.nonLetti)", "non letti")
                tessera("mappin.and.ellipse", "\((e.punti ?? []).count)", "punti")
            }
            HStack {
                Button { vaiAllaScheda(Schede.mappa) } label: { Label("Mappa", systemImage: "map.fill") }
                    .buttonStyle(.borderedProminent).tint(Theme.olive).foregroundStyle(.black)
                NavigationLink { EventoView(evento: e) } label: { Label("Apri evento", systemImage: "chevron.right") }
                    .buttonStyle(.bordered).tint(Theme.olive)
                Spacer()
            }
            .font(.subheadline.weight(.semibold))
        }
    }

    func conto(_ s: TimeInterval) -> String {
        let t = max(0, Int(s))
        let g = t / 86400, h = (t % 86400) / 3600, m = (t % 3600) / 60, sec = t % 60
        return g > 0 ? String(format: "%dg %02dh %02dm", g, h, m) : String(format: "%02d:%02d:%02d", h, m, sec)
    }

    func tessera(_ icona: String, _ valore: String, _ etichetta: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(valore, systemImage: icona).font(Theme.mono(15, .heavy)).foregroundStyle(.white)
            Text(etichetta).font(.caption2).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: azioni rapide

    var azioni: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            azione("sos", "SOS", Theme.red) { sos = true }
            azione("mappin.and.ellipse", "Segna punto", Theme.olive) {
                UserDefaults.standard.set(true, forKey: "mappa.nuovoPunto")
                vaiAllaScheda(Schede.mappa)
            }
            azione("bubble.left.and.bubble.right.fill", "Chat", Theme.cyan) {
                UserDefaults.standard.set(true, forKey: "eventi.apriChat")
                vaiAllaScheda(Schede.eventi)
            }
            azione("person.text.rectangle", "Tessera", Theme.amber) { vaiAllaScheda(Schede.profilo) }
        }
        .overlay(alignment: .bottom) {
            if let s = sosInviato {
                Text(s).font(.caption.weight(.bold)).padding(8).background(.ultraThinMaterial, in: Capsule()).offset(y: 34)
            }
        }
    }

    func azione(_ icona: String, _ testo: String, _ colore: Color, _ f: @escaping () -> Void) -> some View {
        Button { haptic(.medium); f() } label: {
            VStack(spacing: 6) {
                Image(systemName: icona).font(.system(size: 22, weight: .bold)).foregroundStyle(colore)
                Text(testo).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(colore.opacity(0.35), lineWidth: 0.75))
        }
        .buttonStyle(PressStyle())
    }

    func mandaSOS() {
        let c = location.location?.coordinate
        let testo = "🆘 SOS da \(jsoc.utente?.callsign ?? "?")" + (c.map { " · " + Coordinate.utmText($0) } ?? " · posizione non disponibile")
        Task {
            do {
                try await store.scrivi(testo, jsoc, posizione: c)
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                sosInviato = "SOS inviato"
            } catch { sosInviato = "SOS NON inviato: \(error.localizedDescription)" }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            sosInviato = nil
        }
    }

    // MARK: avvisi e prossimi eventi

    func avvisi(_ a: [JHome.Avviso]) -> some View {
        Card(title: "Da fare", icon: "exclamationmark.triangle.fill") {
            ForEach(a, id: \.self) { x in
                Button {
                    switch x.tipo {
                    case "evento": vaiAllaScheda(Schede.eventi)
                    case "quota", "certificato", "tessera": vaiAllaScheda(Schede.profilo)
                    default: break
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: icona(x.tipo)).foregroundStyle(x.testo.contains("SCADUT") ? Theme.red : Theme.amber).frame(width: 22)
                        Text(x.testo).font(.subheadline).foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.dim)
                    }
                }
            }
        }
    }

    func icona(_ t: String) -> String {
        switch t {
        case "quota": return "eurosign.circle.fill"
        case "certificato": return "cross.case.fill"
        case "tessera": return "person.text.rectangle.fill"
        default: return "calendar.badge.exclamationmark"
        }
    }

    func prossimi(_ p: [JHome.Prossimo]) -> some View {
        Card(title: "Calendario", icon: "calendar", trailing: "\(p.count)") {
            ForEach(p) { e in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.nome).font(.subheadline.weight(.bold))
                            Text([JEvento.data(e.inizio)?.formatted(date: .abbreviated, time: .shortened), e.luogo]
                                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        Text("\(e.si) ✓").font(Theme.mono(11, .bold)).foregroundStyle(Theme.green)
                    }
                    RispostaBottoni(scelta: e.mia_risposta) { r in Task { await home.rispondi(e.id, r) } }
                }
                if e.id != p.last?.id { Divider().overlay(Theme.stroke) }
            }
        }
    }

    var associazione: some View {
        Card(title: "Associazione", icon: "shield.lefthalf.filled") {
            HStack(spacing: 10) {
                Button { vaiAllaScheda(Schede.associazione) } label: {
                    tessera("newspaper.fill", "\(home.dati?.post_nuovi ?? 0)", "in bacheca")
                }
                Button { vaiAllaScheda(Schede.associazione) } label: {
                    tessera("chart.bar.fill", "\(home.dati?.sondaggi_aperti ?? 0)", "sondaggi")
                }
                tessera("person.2.fill", "\(home.dati?.soci_attivi ?? 0)", "soci")
            }
            if let d = home.dati?.direttivo, jsoc.utente?.direttivo == true {
                HStack(spacing: 10) {
                    tessera("eurosign", euro(d.saldo), "saldo cassa")
                    tessera("hourglass", "\(d.quote_da_incassare ?? 0)", "quote da incassare")
                    tessera("cross.case", "\(d.certificati_scaduti ?? 0)", "certificati mancanti")
                }
            }
        }
    }
}

/// Tre pulsanti come Spond: ci sono / forse / non ci sono.
struct RispostaBottoni: View {
    let scelta: String?
    var azione: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            bottone("si", "Ci sono", "checkmark", Theme.green)
            bottone("forse", "Forse", "questionmark", Theme.amber)
            bottone("no", "No", "xmark", Theme.red)
        }
    }

    func bottone(_ v: String, _ testo: String, _ icona: String, _ colore: Color) -> some View {
        let on = scelta == v
        return Button { haptic(.medium); azione(v) } label: {
            Label(testo, systemImage: icona).font(.caption.weight(.bold))
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .foregroundStyle(on ? .black : colore)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? colore : colore.opacity(0.12)))
        }
        .buttonStyle(PressStyle())
    }
}

/// Foto del socio dal server (con le iniziali se non c'è).
struct FotoSocio: View {
    let id: Int?
    let iniziali: String
    var lato: CGFloat = 40
    var aggiorna = 0
    @State private var img: UIImage?

    var body: some View {
        ZStack {
            Circle().fill(Theme.oliveDeep)
            if let img {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Text(String(iniziali.prefix(2))).font(.system(size: lato * 0.36, weight: .heavy, design: .monospaced)).foregroundStyle(Theme.olive)
            }
        }
        .frame(width: lato, height: lato)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.olive.opacity(0.6), lineWidth: 1))
        .task(id: "\(id ?? 0)-\(aggiorna)") {
            guard let id else { return }
            let cache = EventoStore.cartella.appendingPathComponent("foto_\(id).jpg")
            if aggiorna == 0, let d = try? Data(contentsOf: cache), let i = UIImage(data: d) { img = i }
            if let d = try? await JsocClient.shared.scaricaDati("/api/utenti/\(id)/foto"), let i = UIImage(data: d) {
                img = i
                try? d.write(to: cache, options: .atomic)
            }
        }
    }
}
