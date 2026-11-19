import SwiftUI
import Combine
import BackgroundTasks

@main
struct JsocTakApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegato
    @StateObject private var location = LocationService()
    @StateObject private var log = FieldLog()
    @StateObject private var docs = DocStore()
    @StateObject private var server = ServerClient()
    @StateObject private var terminal = TerminalModel()
    @StateObject private var claude = ClaudeModel()
    @StateObject private var rilevamenti = Rilevamenti()
    @StateObject private var night = NightMode()
    @StateObject private var mission = Mission()
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var evento = EventoStore.shared
    @ObservedObject private var home = HomeModel.shared
    private var avvisiHome: Int { (home.dati?.avvisi ?? []).filter { $0.tipo != "evento" }.count }
    @Environment(\.scenePhase) private var phase
    @State private var tab = UserDefaults.standard.integer(forKey: "debug.tab")   // per le anteprime

    init() { Diagnostica.attiva() }

    var body: some Scene {
        WindowGroup {
            // Home · Eventi · Associazione · Strumenti (barra in basso, colonna a sinistra in orizzontale);
            // il Profilo si apre dalla Home, la Mappa dagli eventi
            ContenitoreSchede(tab: $tab, badge: [
                Schede.home: avvisiHome,
                Schede.eventi: evento.nonLetti + evento.eventi.filter { $0.fase != 2 && $0.stato != "proposto" && $0.mia_risposta == nil }.count,
                Schede.associazione: (home.dati?.post_nuovi ?? 0) + (home.dati?.sondaggi_aperti ?? 0),
            ])
            .tint(night.on ? Night.red : Theme.olive)
            // modalità notturna: tutto moltiplicato per il rosso (il nero resta nero, il bianco diventa rosso)
            .colorMultiply(night.on ? Night.filtro : .white)
            .background(Theme.bg.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .environment(\.locale, Locale(identifier: "it_IT"))
            .environmentObject(night)
            .environmentObject(location)
            .environmentObject(log)
            .environmentObject(docs)
            .environmentObject(server)
            .environmentObject(terminal)
            .environmentObject(claude)
            .environmentObject(rilevamenti)
            .environmentObject(mission)
            .onAppear {
                Diagnostica.invia()
                DispatchQueue.main.asyncAfter(deadline: .now() + 15) { Diagnostica.avvioRiuscito() }
                Avvisi.shared.attiva()
                location.start()
                if UserDefaults.standard.bool(forKey: "debug.landscape"),
                   let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
                }
                if UserDefaults.standard.bool(forKey: "debug.live") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { mission.startLive(location: location, client: server, claude: claude) }
                }
            }
            .task {
                // Dynamic Island, blocco schermo e widget: ogni 20 s (e quando cambia la posizione)
                while !Task.isCancelled {
                    await server.probe()
                    if server.online[.server] == true, let ops = try? await server.operators() {
                        mission.operatoriOrologio = ops.filter { !$0.isBot }.compactMap { o in
                            guard let la = o.lat, let lo = o.lon else { return nil }
                            return OperatoreOrologio(cs: o.callsign, lat: la, lon: lo, collegato: o.collegato)
                        }
                    }
                    mission.aggiorna(location: location, client: server, claude: claude)
                    try? await Task.sleep(nanoseconds: 20_000_000_000)
                }
            }
            .onReceive(location.$location.throttle(for: .seconds(15), scheduler: RunLoop.main, latest: true)) { _ in
                mission.aggiorna(location: location, client: server, claude: claude)
            }
            .onChange(of: claude.running) { _ in mission.aggiorna(location: location, client: server, claude: claude, force: true) }
            .onChange(of: mission.fatti) { _ in mission.aggiorna(location: location, client: server, claude: claude, force: true) }
            .onChange(of: mission.finestra?.code) { _ in mission.aggiorna(location: location, client: server, claude: claude, force: true) }
            .task {
                // biblioteca: controlla le novità ogni 2 minuti, anche col telefono bloccato
                // (l'app resta viva grazie alla posizione in background) -> notifiche
                while !Task.isCancelled {
                    await docs.sync(jsoc)
                    try? await Task.sleep(nanoseconds: 120_000_000_000)
                }
            }
            .onChange(of: phase) { p in
                location.sfondo(p == .background)
                Diagnostica.passo("fase \(p)")
                if p == .background { Diagnostica.avvioRiuscito() }
                if p == .active { Diagnostica.ripartito(); DispatchQueue.main.asyncAfter(deadline: .now() + 15) { Diagnostica.avvioRiuscito() }; Diagnostica.invia() }
                if p == .active { Task { await evento.aggiorna(jsoc); await docs.sync(jsoc) } }
                if p == .background { programmaControllo() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openDocs)) { n in
                if let f = n.userInfo?["fascicolo"] as? String { UserDefaults.standard.set(f, forKey: "docs.apri") }
                tab = Schede.eventi
            }
            .onReceive(NotificationCenter.default.publisher(for: .openClaude)) { _ in
                UserDefaults.standard.set(1, forKey: "raccolta.seg")
                tab = Schede.eventi
            }
            .onReceive(NotificationCenter.default.publisher(for: .claudeFinished)) { _ in
                Task { await docs.sync(jsoc, force: true) }
            }
            .task {
                // JSOC TAK: evento, squadra, chat e posizioni ogni 15 s (anche in background grazie al GPS)
                while !Task.isCancelled {
                    await evento.aggiorna(jsoc)
                    if Int(Date().timeIntervalSince1970) % 60 < 15 { await home.aggiorna() }
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                }
            }
            .onReceive(location.$location) { l in if let l { evento.registra(l, direzione: location.heading) } }
            .onReceive(location.$heading.throttle(for: .seconds(2), scheduler: RunLoop.main, latest: true)) { h in
                if let l = location.location { evento.registra(l, direzione: h) }
            }
            .onChange(of: tab) { t in Diagnostica.passo("scheda \(t)"); if t != Schede.mappa { ruotaSchermo(.allButUpsideDown) } }
            .onReceive(NotificationCenter.default.publisher(for: .vaiTab)) { n in
                if let t = n.userInfo?["tab"] as? Int { tab = t }
            }
            .onChange(of: evento.corrente?.id) { _ in
                docs.cambiaEvento()
                Task { await docs.sync(jsoc, force: true) }
            }
            .onOpenURL { url in
                Diagnostica.passo("apre link \(url.scheme ?? "")")
                if url.scheme == "jsoctak" {
                    UserDefaults.standard.set(url.absoluteString, forKey: "jsoc.invito")
                    tab = 0
                    return
                }
                docs.importFile(url)
                tab = Schede.eventi
            }
        }
        .backgroundTask(.appRefresh("remida.novita")) {
            programmaControllo()
            await evento.aggiorna(jsoc)
            await docs.sync(jsoc, force: true)
        }
    }
}

/// Controllo di riserva quando iOS sveglia l'app (se la posizione in background è spenta).
func programmaControllo() {
    let r = BGAppRefreshTaskRequest(identifier: "remida.novita")
    r.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
    try? BGTaskScheduler.shared.submit(r)
}

func copyToClipboard(_ s: String) {
    UIPasteboard.general.string = s
    UINotificationFeedbackGenerator().notificationOccurred(.success)
}
