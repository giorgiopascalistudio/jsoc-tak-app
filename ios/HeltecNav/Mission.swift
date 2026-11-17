import SwiftUI
import CoreLocation
import WidgetKit
import UserNotifications
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Stato della missione: percorso con gli OBJ fatti, prossimo OBJ, e la Live Activity (Dynamic Island +
/// schermata di blocco) aggiornata dall'app mentre gira (anche in background grazie alla posizione).
@MainActor
final class Mission: ObservableObject {
    @Published var fatti: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(fatti), forKey: "percorso.fatti")
            // ora in cui ogni OBJ è stato segnato fatto (per la tabella di marcia)
            for c in fatti where fattiOra[c] == nil { fattiOra[c] = Date() }
            for c in fattiOra.keys where !fatti.contains(c) { fattiOra.removeValue(forKey: c) }
            UserDefaults.standard.set(fattiOra.mapValues(\.timeIntervalSince1970), forKey: "percorso.fattiOra")
        }
    }
    @Published private(set) var fattiOra: [String: Date] = [:]
    /// Ora di partenza del percorso: prima di questa i comandi degli OBJ sono bloccati.
    @Published private(set) var inizioPercorso: Date? = UserDefaults.standard.object(forKey: "percorso.inizio") as? Date

    func avviaPercorso(_ quando: Date = Date()) {
        guard inizioPercorso == nil else { return }
        withAnimation(.spring()) { inizioPercorso = quando }
        UserDefaults.standard.set(quando, forKey: "percorso.inizio")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Ferma il percorso: tiene gli OBJ fatti e i loro orari.
    func fermaPercorso() {
        withAnimation(.spring()) { inizioPercorso = nil }
        UserDefaults.standard.removeObject(forKey: "percorso.inizio")
        if finestra != nil { chiudiFinestra(fatto: false) }
        stopLive()
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Azzera tutto (dopo una prova): percorso, OBJ fatti, orari, finestra.
    func azzeraPercorso() {
        fermaPercorso()
        withAnimation(.spring()) { fatti = [] }
    }

    /// Posizioni degli operatori (dal server TAK) per la mappa dell'orologio.
    var operatoriOrologio: [OperatoreOrologio] = []
    /// Finestra di ingaggio in corso: codice OBJ e ora di fine.
    @Published private(set) var finestra: (code: String, inizio: Date, fine: Date)?
    @Published private(set) var liveOn = false
    @Published private(set) var liveError: String?
    private var lastPush = Date.distantPast
    private var lastState: String = ""

    init() {
        fattiOra = ((UserDefaults.standard.dictionary(forKey: "percorso.fattiOra") as? [String: Double]) ?? [:])
            .mapValues { Date(timeIntervalSince1970: $0) }
        fatti = Set(UserDefaults.standard.stringArray(forKey: "percorso.fatti") ?? [])
        if let c = UserDefaults.standard.string(forKey: "finestra.code"),
           let i = UserDefaults.standard.object(forKey: "finestra.inizio") as? Date,
           let f = UserDefaults.standard.object(forKey: "finestra.fine") as? Date, f > Date().addingTimeInterval(-600) {
            finestra = (c, i, f)
        }
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) { liveOn = !Activity<ReMidaActivityAttributes>.activities.isEmpty }
        #endif
        WatchSync.shared.mission = self
        WatchSync.shared.avvia()
    }

    var prossima: Gara.Tappa? { Gara.percorso.first { !fatti.contains($0.code) } }
    var avanzamento: Double { Double(fatti.intersection(Gara.percorso.map(\.code)).count) / Double(max(1, Gara.percorso.count)) }

    func toggle(_ t: Gara.Tappa) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            if fatti.contains(t.code) { fatti.remove(t.code) } else { fatti.insert(t.code) }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: Finestra di ingaggio (cronometro OBJ)

    /// Durata delle finestre dai book (minuti).
    static func durata(_ code: String) -> Int { TappaMarcia.durata(code) }

    func apriFinestra(_ code: String) {
        let now = Date(), fine = now.addingTimeInterval(Double(Self.durata(code)) * 60)
        withAnimation(.spring()) { finestra = (code, now, fine) }
        let d = UserDefaults.standard
        d.set(code, forKey: "finestra.code"); d.set(now, forKey: "finestra.inizio"); d.set(fine, forKey: "finestra.fine")
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        let c = UNUserNotificationCenter.current()
        c.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        c.removePendingNotificationRequests(withIdentifiers: ["fin5", "fin1", "fin0"])
        for (id, min, testo) in [("fin5", 5, "mancano 5 minuti"), ("fin1", 1, "manca 1 minuto"), ("fin0", 0, "FINESTRA CHIUSA")] {
            let t = fine.timeIntervalSince(now) - Double(min) * 60
            guard t > 1 else { continue }
            let n = UNMutableNotificationContent()
            n.title = "\(code) · \(testo)"
            n.body = min == 0 ? "Tempo dell'obiettivo finito." : "Finestra di ingaggio: \(testo)."
            n.sound = .default
            n.interruptionLevel = .timeSensitive
            c.add(UNNotificationRequest(identifier: id, content: n, trigger: UNTimeIntervalNotificationTrigger(timeInterval: t, repeats: false)))
        }
    }

    func chiudiFinestra(fatto: Bool) {
        if fatto, let c = finestra?.code { fatti.insert(c) }
        withAnimation(.spring()) { finestra = nil }
        UserDefaults.standard.removeObject(forKey: "finestra.code")
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["fin5", "fin1", "fin0"])
    }

    /// Distanza e direzione verso la prossima tappa.
    func versoProssima(from loc: CLLocation?) -> (dist: String, gradi: Double, dir: String)? {
        guard let t = prossima, let p = Gara.point(t.punto), let me = loc?.coordinate else { return nil }
        let d = Geo.distance(me, p.coordinate), b = Geo.bearing(me, p.coordinate)
        return (Geo.formatDistance(d), b, Self.cardinale(b) + String(format: " %.0f°", b))
    }

    static func cardinale(_ b: Double) -> String {
        ["N", "NE", "E", "SE", "S", "SO", "O", "NO"][Int((b + 22.5) / 45) % 8]
    }

    // MARK: Live Activity + widget

    func aggiorna(location: LocationService, client: ServerClient, claude: ClaudeModel, force: Bool = false) {
        let now = Date()
        var ev = Shared.prossimo(now)
        if let f = finestra, f.fine > now.addingTimeInterval(-60) {
            ev = Shared.Evento(date: f.fine, title: "\(f.code) · finestra", detail: "")
        }
        let verso = versoProssima(from: location.location)
        let utm = location.location.map { "UTM " + UTM.fromLatLon($0.coordinate.latitude, $0.coordinate.longitude).text } ?? "UTM —"
        let stato = { (t: Target) -> Int in client.configured(t) ? (client.online[t] == true ? 1 : 0) : -1 }
        let cl = claude.running ? "lavora" : ""
        let obj = prossima.map { "\($0.code) \($0.nome)" } ?? (fatti.isEmpty ? "" : "Percorso completato")

        // widget Home
        Shared.saveSnapshot(Shared.Snapshot(obj: obj, objDist: verso?.dist ?? "", objDir: verso?.dir ?? "", utm: utm,
                                            pc: stato(.pc), server: stato(.server), claude: cl, ora: now))

        // Apple Watch
        var so = StatoOrologio()
        so.fatti = fattiOra
        so.finestraCode = finestra?.code; so.finestraInizio = finestra?.inizio; so.finestraFine = finestra?.fine
        so.pc = stato(.pc); so.server = stato(.server); so.claude = cl
        so.evento = Shared.prossimo(now)?.title ?? ""; so.eventoData = Shared.prossimo(now)?.date ?? now
        if let o = Meteo.shared.ore.first(where: { $0.ora <= now && $0.ora.addingTimeInterval(3600) > now }) {
            so.meteoTemp = o.temp; so.meteoPioggia = o.pioggia; so.meteoIcona = o.icona; so.meteoVento = o.vento
        }
        so.notte = UserDefaults.standard.bool(forKey: "night.on")
        so.inizioPercorso = inizioPercorso
        so.io = UserDefaults.standard.string(forKey: "video.callsign") ?? "GREG"
        so.operatori = operatoriOrologio
        WatchSync.shared.invia(so, forza: force)

        let firma = "\(ev?.title ?? "")|\(obj)|\(verso?.dist ?? "")|\(utm)|\(stato(.pc))\(stato(.server))|\(cl)"
        guard force || (firma != lastState && now.timeIntervalSince(lastPush) > 15) else { return }
        lastState = firma
        lastPush = now
        WidgetCenter.shared.reloadAllTimelines()

        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        let content = ReMidaActivityAttributes.ContentState(
            evento: ev?.title ?? "Gara conclusa", eventoData: ev?.date ?? now, obj: obj, objDist: verso?.dist ?? "",
            objGradi: verso?.gradi ?? 0, utm: utm, pc: stato(.pc), server: stato(.server), claude: cl)
        for a in Activity<ReMidaActivityAttributes>.activities {
            Task { await a.update(using: content) }
        }
        #endif
    }

    func startLive(location: LocationService, client: ServerClient, claude: ClaudeModel) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { liveError = "Serve iOS 16.1"; return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            liveError = "Attività in tempo reale disattivate: Impostazioni › Re Mida › Attività in tempo reale"
            UserDefaults.standard.set(liveError, forKey: "debug.liveError")
            return
        }
        let ev = Shared.prossimo()
        let content = ReMidaActivityAttributes.ContentState(
            evento: ev?.title ?? "Gara", eventoData: ev?.date ?? Date(), obj: "", objDist: "", objGradi: 0,
            utm: "UTM —", pc: -1, server: -1, claude: "")
        do {
            _ = try Activity.request(attributes: ReMidaActivityAttributes(squadra: "ORO 16"), contentState: content)
            withAnimation { liveOn = true }
            liveError = nil
            aggiorna(location: location, client: client, claude: claude, force: true)
        } catch {
            liveError = error.localizedDescription
        }
        UserDefaults.standard.set(liveError ?? "ok", forKey: "debug.liveError")
        #endif
    }

    func stopLive() {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        for a in Activity<ReMidaActivityAttributes>.activities {
            Task { await a.end(dismissalPolicy: .immediate) }
        }
        withAnimation { liveOn = false }
        #endif
    }
}
