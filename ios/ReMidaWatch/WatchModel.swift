import Foundation
import CoreLocation
import HealthKit
import WatchConnectivity
import WatchKit

/// Tutto lo stato dell'orologio: GPS e bussola del polso, battiti e kcal (sessione di allenamento,
/// che tiene anche l'app attiva in tasca), stato dal telefono e vibrazioni del timer finestra.
@MainActor
final class WatchModel: NSObject, ObservableObject {
    // dal telefono
    @Published var stato = StatoOrologio()
    @Published var telefono = false
    // sensori del polso
    @Published var posizione: CLLocation?
    @Published var direzione: Double?          // nord vero, gradi
    @Published var battiti: Double?
    @Published var kcal: Double = 0
    @Published var allenamento = false
    /// Proposta "entri in FF..?" quando si arriva vicino all'OBJ.
    @Published var proponi: String?
    private var proposti: Set<String> = []
    // azioni fatte sul polso non ancora confermate dal telefono
    private var inAttesaFatti: [String: Date] = [:]
    private var inAttesaFinestra: (code: String, inizio: Date, fine: Date)?
    private var inAttesaAvvio: Date?

    private let lm = CLLocationManager()
    private let hs = HKHealthStore()
    private var sessione: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var avvisiFatti: Set<String> = []
    private var timer: Timer?

    override init() {
        super.init()
        if let d = UserDefaults.standard.data(forKey: "stato"), let s = try? JSONDecoder().decode(StatoOrologio.self, from: d) { stato = s }
        if UserDefaults.standard.bool(forKey: "debug.demo") {
            // solo per le anteprime del simulatore
            stato.operatori = [OperatoreOrologio(cs: "FOX", lat: 43.9690, lon: 12.3760, collegato: true),
                               OperatoreOrologio(cs: "LILLO", lat: 43.9640, lon: 12.3790, collegato: true),
                               OperatoreOrologio(cs: "APO", lat: 43.9600, lon: 12.3650, collegato: false)]
            stato.meteoTemp = 14; stato.meteoIcona = "cloud.sun.fill"; stato.pc = 1; stato.server = 1
            stato.inizioPercorso = Date().addingTimeInterval(-3600)
            if UserDefaults.standard.bool(forKey: "debug.finestra") {
                stato.finestraCode = "FF08"; stato.finestraInizio = Date().addingTimeInterval(-16 * 60)
                stato.finestraFine = Date().addingTimeInterval(4 * 60 + 12)
            }
        }
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyBest
        lm.activityType = .fitness
        lm.headingFilter = 2
        lm.requestWhenInUseAuthorization()
        lm.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { lm.startUpdatingHeading() }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.controllaFinestra() }
        }
    }

    // MARK: percorso

    var avviato: Bool { stato.inizioPercorso != nil }

    func avviaPercorso() {
        let ora = Date()
        if stato.inizioPercorso == nil { stato.inizioPercorso = ora; inAttesaAvvio = ora }
        if !allenamento { avviaAllenamento() }
        manda(["azione": "avvia", "quando": ora])
    }

    func entra(_ code: String) {
        let ora = Date(), fine = ora.addingTimeInterval(Double(TappaMarcia.durata(code)) * 60)
        stato.finestraCode = code; stato.finestraInizio = ora; stato.finestraFine = fine
        inAttesaFinestra = (code, ora, fine)
        proponi = nil
        WKInterfaceDevice.current().play(.start)
        manda(["azione": "finestra", "code": code])
    }

    func fatto(_ code: String) {
        let ora = Date()
        stato.fatti[code] = ora
        inAttesaFatti[code] = ora
        if stato.finestraCode == code { stato.finestraCode = nil; stato.finestraFine = nil; inAttesaFinestra = nil }
        WKInterfaceDevice.current().play(.success)
        manda(["azione": "fatto", "code": code])
    }

    func annullaFinestra() {
        guard let c = stato.finestraCode else { return }
        stato.finestraCode = nil; stato.finestraFine = nil; inAttesaFinestra = nil
        manda(["azione": "chiudi", "code": c])
    }

    /// Messaggio al telefono: subito se raggiungibile, altrimenti in coda (arriva quando si ricollegano).
    private func manda(_ msg: [String: Any]) {
        let s = WCSession.default
        guard s.activationState == .activated else { return }
        if s.isReachable { s.sendMessage(msg, replyHandler: nil) { _ in s.transferUserInfo(msg) } }
        else { s.transferUserInfo(msg) }
    }

    /// Vicino all'OBJ (150 m) con il percorso avviato: vibra e chiede se si entra.
    func controllaVicinanza() {
        guard avviato, stato.finestraCode == nil, let t = prossima, let v = verso(t), v.metri < 150,
              !proposti.contains(t.code) else { return }
        proposti.insert(t.code)
        proponi = t.code
        WKInterfaceDevice.current().play(.directionUp)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { WKInterfaceDevice.current().play(.directionUp) }
    }

    var prossima: TappaMarcia? { Shared.marcia.first { stato.fatti[$0.code] == nil } }
    var fatti: Int { Shared.marcia.filter { stato.fatti[$0.code] != nil }.count }
    var scarto: Int? { Shared.scarto(fatti: stato.fatti) }

    /// Velocità attuale in km/h (dal GPS; sotto 0,5 = fermo).
    var velocita: Double? {
        guard let l = posizione, l.speed >= 0 else { return nil }
        return l.speed * 3.6
    }

    func verso(_ t: TappaMarcia) -> (metri: Double, gradi: Double)? {
        guard let me = posizione?.coordinate else { return nil }
        let a = me, b = CLLocationCoordinate2D(latitude: t.lat, longitude: t.lon)
        let d = CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        let p1 = a.latitude * .pi / 180, p2 = b.latitude * .pi / 180, dl = (b.longitude - a.longitude) * .pi / 180
        let br = atan2(sin(dl) * cos(p2), cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)) * 180 / .pi
        return (d, (br + 360).truncatingRemainder(dividingBy: 360))
    }

    /// Tempo stimato all'arrivo con la velocità media di marcia (3,5 km/h se fermo).
    func eta(_ metri: Double) -> Date {
        let v = max(2.5, (velocita ?? 0) > 1.5 ? velocita! : 3.5)
        return Date().addingTimeInterval(metri / 1000 / v * 3600)
    }

    var utm: String {
        guard let c = posizione?.coordinate else { return "—" }
        return UTM.fromLatLon(c.latitude, c.longitude).text
    }

    // MARK: comandi al telefono

    func invia(_ azione: String, _ code: String) {
        WKInterfaceDevice.current().play(.click)
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["azione": azione, "code": code], replyHandler: nil)
    }

    // MARK: finestra: vibrazioni a −5', −1' e alla fine

    func controllaFinestra() {
        guard let code = stato.finestraCode, let fine = stato.finestraFine else { avvisiFatti = []; return }
        let rest = fine.timeIntervalSinceNow
        for (soglia, nome, tipo) in [(300.0, "5", WKHapticType.notification), (60.0, "1", .retry), (0.0, "0", .failure)] {
            let k = code + nome + String(Int(fine.timeIntervalSince1970))
            if rest <= soglia, rest > soglia - 30, !avvisiFatti.contains(k) {
                avvisiFatti.insert(k)
                WKInterfaceDevice.current().play(tipo)
                if soglia == 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { WKInterfaceDevice.current().play(.failure) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { WKInterfaceDevice.current().play(.failure) }
                }
            }
        }
    }

    // MARK: allenamento (battiti, kcal, app sempre attiva)

    func avviaAllenamento() {
        let tipi: Set<HKSampleType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        hs.requestAuthorization(toShare: [HKObjectType.workoutType()], read: tipi) { ok, _ in
            guard ok else { return }
            Task { @MainActor in self.inizia() }
        }
    }

    private func inizia() {
        let c = HKWorkoutConfiguration()
        c.activityType = .hiking
        c.locationType = .outdoor
        guard let s = try? HKWorkoutSession(healthStore: hs, configuration: c) else { return }
        let b = s.associatedWorkoutBuilder()
        b.dataSource = HKLiveWorkoutDataSource(healthStore: hs, workoutConfiguration: c)
        b.delegate = self
        s.delegate = self
        sessione = s
        builder = b
        let ora = Date()
        s.startActivity(with: ora)
        b.beginCollection(withStart: ora) { _, _ in }
        allenamento = true
        WKInterfaceDevice.current().play(.start)
    }

    func fermaAllenamento() {
        sessione?.end()
        builder?.endCollection(withEnd: Date()) { [weak self] _, _ in
            self?.builder?.finishWorkout { _, _ in }
        }
        allenamento = false
        WKInterfaceDevice.current().play(.stop)
    }
}

extension WatchModel: CLLocationManagerDelegate {
    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let l = locs.last else { return }
        Task { @MainActor in
            self.posizione = l
            self.controllaVicinanza()
        }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didUpdateHeading h: CLHeading) {
        let v = h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading
        Task { @MainActor in self.direzione = v }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}
}

extension WatchModel: WCSessionDelegate {
    nonisolated func session(_ s: WCSession, activationDidCompleteWith st: WCSessionActivationState, error: Error?) {
        let ctx = s.receivedApplicationContext
        Task { @MainActor in
            self.telefono = s.isReachable
            self.ricevi(ctx)
        }
    }
    nonisolated func session(_ s: WCSession, didReceiveApplicationContext ctx: [String: Any]) {
        Task { @MainActor in self.ricevi(ctx) }
    }
    nonisolated func sessionReachabilityDidChange(_ s: WCSession) {
        let r = s.isReachable
        Task { @MainActor in self.telefono = r }
    }

    private func ricevi(_ ctx: [String: Any]) {
        guard let d = ctx["stato"] as? Data, var s = try? JSONDecoder().decode(StatoOrologio.self, from: d) else { return }
        // le azioni fatte sul polso restano finché il telefono non le conferma
        for (c, t) in inAttesaFatti {
            if s.fatti[c] != nil { inAttesaFatti.removeValue(forKey: c) } else { s.fatti[c] = t }
        }
        if let f = inAttesaFinestra {
            if s.finestraCode == f.code || s.fatti[f.code] != nil || f.fine < Date() { inAttesaFinestra = nil }
            else { s.finestraCode = f.code; s.finestraInizio = f.inizio; s.finestraFine = f.fine }
        }
        if let a = inAttesaAvvio {
            if s.inizioPercorso != nil { inAttesaAvvio = nil } else { s.inizioPercorso = a }
        }
        stato = s
        UserDefaults.standard.set(d, forKey: "stato")
    }
}

extension WatchModel: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutSession(_ s: HKWorkoutSession, didChangeTo to: HKWorkoutSessionState, from: HKWorkoutSessionState, date: Date) {}
    nonisolated func workoutSession(_ s: HKWorkoutSession, didFailWithError error: Error) {}
    nonisolated func workoutBuilderDidCollectEvent(_ b: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ b: HKLiveWorkoutBuilder, didCollectDataOf types: Set<HKSampleType>) {
        let bpm = b.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        let k = b.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        Task { @MainActor in
            if let bpm { self.battiti = bpm }
            if let k { self.kcal = k }
        }
    }
}
