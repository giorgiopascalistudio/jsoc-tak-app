import QuartzCore
import SwiftUI
import Combine
import BackgroundTasks

/// I servizi dell'app tenuti fuori dall'osservazione della radice: GPS, bussola, server e missione cambiano
/// molte volte al secondo e, se la radice li osservasse, ricalcolerebbe tutta l'app a ogni cambiamento (scatti).
/// Le schermate che ne hanno bisogno li ricevono come environmentObject e osservano solo loro.
@MainActor
final class Servizi {
    let location = LocationService()
    let log = FieldLog()
    let docs = DocStore()
    let server = ServerClient()
    let terminal = TerminalModel()
    let claude = ClaudeModel()
    let rilevamenti = Rilevamenti()
    let mission = Mission()
}

@main
struct JsocTakApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegato
    @State private var servizi = Servizi()
    @StateObject private var night = NightMode()
    private var location: LocationService { servizi.location }
    private var log: FieldLog { servizi.log }
    private var docs: DocStore { servizi.docs }
    private var server: ServerClient { servizi.server }
    private var terminal: TerminalModel { servizi.terminal }
    private var claude: ClaudeModel { servizi.claude }
    private var rilevamenti: Rilevamenti { servizi.rilevamenti }
    private var mission: Mission { servizi.mission }
    private var jsoc: JsocClient { .shared }
    private var evento: EventoStore { .shared }
    private var home: HomeModel { .shared }
    @Environment(\.scenePhase) private var phase
    @State private var tab = UserDefaults.standard.integer(forKey: "debug.tab")   // per le anteprime

    init() { Diagnostica.attiva() }

    /// misura un lavoro fatto sul filo principale e lo annota se è lento
    private func misura(_ nome: String, _ f: () -> Void) {
        let t0 = CACurrentMediaTime()
        f()
        let ms = (CACurrentMediaTime() - t0) * 1000
        if ms > 15 { Prestazioni.shared.attivita("\(nome) \(Int(ms)) ms") }
    }

    var body: some Scene {
        WindowGroup {
            // Home · Eventi · Associazione · Strumenti (barra in basso, colonna a sinistra in orizzontale);
            // il Profilo si apre dalla Home, la Mappa dagli eventi
            ContenitoreSchede(tab: $tab)
            .overlay(alignment: .top) { if tab == Schede.mappa { TimerGiocoMappa().padding(.top, 64) } }
            .overlay { GuidaSopra() }   // la guida di ogni schermata, la prima volta che si apre
            .tint(night.on ? Night.red : Theme.olive)
            // modalità notturna: tutto moltiplicato per il rosso (il nero resta nero, il bianco diventa rosso).
            // Solo quando è accesa: un filtro su tutta l'app costa un passaggio in più a ogni fotogramma
            .overlay {
                if night.on { Night.filtro.blendMode(.multiply).ignoresSafeArea().allowsHitTesting(false) }
            }
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
                Prestazioni.shared.avvia()
                let C = Contatori.shared
                C.osserva("EventoStore", EventoStore.shared.objectWillChange); C.osserva("HomeModel", HomeModel.shared.objectWillChange)
                C.osserva("JsocClient", JsocClient.shared.objectWillChange); C.osserva("PermessiStore", PermessiStore.shared.objectWillChange)
                C.osserva("CampiStore", CampiStore.shared.objectWillChange); C.osserva("Livelli", Livelli.shared.objectWillChange)
                C.osserva("NavStore", NavStore.shared.objectWillChange); C.osserva("DocAssoc", DocAssoc.shared.objectWillChange)
                C.osserva("PianiStore", PianiStore.shared.objectWillChange); C.osserva("Traccia", Traccia.shared.objectWillChange)
                C.osserva("Posizione/bussola", location.objectWillChange); C.osserva("Notte", night.objectWillChange)
                C.osserva("Missione", mission.objectWillChange); C.osserva("ServerTAK", server.objectWillChange)
                C.osserva("Documenti", docs.objectWillChange); C.osserva("Claude", claude.objectWillChange)
                C.osserva("Registro", log.objectWillChange); C.osserva("Rilevamenti", rilevamenti.objectWillChange)
                Task { await jsoc.aggiornaIndirizzo() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 15) { Diagnostica.avvioRiuscito() }
                if !Anteprima.attiva { Avvisi.shared.attiva() }
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
                    misura("missione") { mission.aggiorna(location: location, client: server, claude: claude) }
                    try? await Task.sleep(nanoseconds: 20_000_000_000)
                }
            }
            .onReceive(location.$location.throttle(for: .seconds(15), scheduler: RunLoop.main, latest: true)) { _ in
                misura("missione") { mission.aggiorna(location: location, client: server, claude: claude) }
            }
            .onReceive(claude.$running.removeDuplicates().dropFirst()) { _ in misura("missione") { mission.aggiorna(location: location, client: server, claude: claude, force: true) } }
            .onReceive(mission.$fatti.removeDuplicates().dropFirst()) { _ in misura("missione") { mission.aggiorna(location: location, client: server, claude: claude, force: true) } }
            .onReceive(mission.$finestra.map { $0?.code }.removeDuplicates().dropFirst()) { _ in misura("missione") { mission.aggiorna(location: location, client: server, claude: claude, force: true) } }
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
            .onReceive(location.$location) { l in if let l { misura("posizione") { evento.registra(l, direzione: location.heading) } } }
            .onReceive(location.$heading.throttle(for: .seconds(2), scheduler: RunLoop.main, latest: true)) { h in
                if let l = location.location { evento.registra(l, direzione: h) }
            }
            .onChange(of: tab) { t in
                Diagnostica.passo("scheda \(t)")
                if t != Schede.mappa { ruotaSchermo(.allButUpsideDown); SchedaPrecedente.valore = t }
            }
            .onReceive(NotificationCenter.default.publisher(for: .vaiTab)) { n in
                if let t = n.userInfo?["tab"] as? Int { tab = t }
            }
            .onReceive(EventoStore.shared.$corrente.map { $0?.id }.removeDuplicates().dropFirst()) { _ in
                docs.cambiaEvento()
                Task { await docs.sync(jsoc, force: true) }
            }
            .task { GarminPonte.shared.avvia() }
            .onOpenURL { url in
                Diagnostica.passo("apre link \(url.scheme ?? "")")
                if GarminPonte.shared.apri(url) { return }
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
