import SwiftUI
import CoreLocation
import UserNotifications

/// Timer degli obiettivi (come TimerObj.kt su Android): avvicinandosi a X metri da un OBJ compare
/// «Avvia timer / Salta obiettivo» (banner in mappa + notifica); avvisi a −1 minuto e allo scadere.
@MainActor
final class TimerObj: ObservableObject {
    static let shared = TimerObj()
    struct Attivo: Codable, Equatable { var evento: Int; var obj: String; var fine: Double; var durata: Int }
    struct Vicino: Equatable { var evento: Int; var obj: String; var metri: Int }

    @Published private(set) var attivo: Attivo?
    @Published private(set) var vicino: Vicino?
    @AppStorage("timerobj.minuti") var minuti = 30
    @AppStorage("timerobj.metri") var metri = 50
    @AppStorage("timerobj.avvisi") var avvisi = true
    private let d = UserDefaults.standard
    private var giro: Timer?

    init() {
        if let x = d.data(forKey: "timerobj.attivo") { attivo = try? JSONDecoder().decode(Attivo.self, from: x) }
        giro = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in Task { @MainActor in TimerObj.shared.controlla() } }
    }

    func durata(_ e: JEvento?) -> Int { minuti }
    func saltato(_ ev: Int, _ o: String) -> Bool { d.bool(forKey: "timerobj.saltato.\(ev).\(o)") }
    func fatto(_ ev: Int, _ o: String) -> Bool { d.bool(forKey: "timerobj.fatto.\(ev).\(o)") }
    func ripristina(_ ev: Int, _ o: String) { d.removeObject(forKey: "timerobj.saltato.\(ev).\(o)"); d.removeObject(forKey: "timerobj.fatto.\(ev).\(o)") }

    var rimasti: Int { attivo.map { Int($0.fine - Date().timeIntervalSince1970) } ?? 0 }

    func avvia(_ ev: Int, _ obj: String) {
        let a = Attivo(evento: ev, obj: obj, fine: Date().timeIntervalSince1970 + Double(minuti * 60), durata: minuti)
        imposta(a); vicino = nil
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["obj.vicino"])
    }
    func aggiungi(_ m: Int) { guard var a = attivo else { return }; a.fine += Double(m * 60); a.durata += m; imposta(a) }
    func ferma() { imposta(nil) }
    func salta(_ ev: Int, _ obj: String) { d.set(true, forKey: "timerobj.saltato.\(ev).\(obj)"); if vicino?.obj == obj { vicino = nil } }

    private func imposta(_ a: Attivo?) {
        attivo = a
        if let a, let x = try? JSONEncoder().encode(a) { d.set(x, forKey: "timerobj.attivo") } else { d.removeObject(forKey: "timerobj.attivo") }
        let c = UNUserNotificationCenter.current()
        c.removePendingNotificationRequests(withIdentifiers: ["obj.1min", "obj.fine"])
        guard let a else { return }
        for (id, prima, titolo) in [("obj.1min", 60.0, "\(a.obj): manca 1 minuto"), ("obj.fine", 0.0, "\(a.obj): tempo scaduto")] {
            let dt = a.fine - prima - Date().timeIntervalSince1970
            guard dt > 1 else { continue }
            let x = UNMutableNotificationContent(); x.title = titolo; x.sound = .default
            c.add(UNNotificationRequest(identifier: id, content: x, trigger: UNTimeIntervalNotificationTrigger(timeInterval: dt, repeats: false)))
        }
    }

    func controlla() {
        if let a = attivo {
            objectWillChange.send()
            if rimasti <= 0 { d.set(true, forKey: "timerobj.fatto.\(a.evento).\(a.obj)"); imposta(nil) }
            return
        }
        guard avvisi, let l = LocationService.corrente?.location, let ev = EventoStore.shared.corrente else { return }
        let vicini = (ev.punti ?? []).filter { $0.obiettivo && !$0.fatto && !saltato(ev.id, $0.nome) && !fatto(ev.id, $0.nome) }
            .map { ($0, l.distance(from: CLLocation(latitude: $0.lat, longitude: $0.lon))) }
            .filter { $0.1 <= Double(metri) }.min { $0.1 < $1.1 }
        guard let migliore = vicini else {
            if let v = vicino, let p = ev.punti?.first(where: { $0.nome == v.obj }),
               l.distance(from: CLLocation(latitude: p.lat, longitude: p.lon)) > Double(metri) * 1.5 { vicino = nil }
            return
        }
        let (p, dist) = migliore
        let nuovo = vicino?.obj != p.nome
        vicino = Vicino(evento: ev.id, obj: p.nome, metri: Int(dist))
        if nuovo {
            let x = UNMutableNotificationContent()
            x.title = "\(p.nome) a \(Int(dist)) m"; x.body = "Apri la mappa: Avvia timer (\(minuti) min) o Salta obiettivo"; x.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "obj.vicino", content: x, trigger: nil))
        }
    }
}

/// In mappa: banner dell'OBJ vicino, oppure il conto alla rovescia del timer OBJ con +1' +5' Stop.
struct TimerObjMappa: View {
    @ObservedObject private var t = TimerObj.shared
    var body: some View {
        if let a = t.attivo {
            let r = t.rimasti
            let col = r <= 60 ? Theme.red : (r <= 300 ? Theme.amber : Theme.oliveBright)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(a.obj).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(Theme.dim)
                    Text(TimerGioco.testo(max(r, 0))).font(.system(size: 24, weight: .heavy, design: .monospaced)).foregroundStyle(col)
                }
                chip("+1'") { t.aggiungi(1) }
                chip("+5'") { t.aggiungi(5) }
                chip("Stop", Theme.red) { t.ferma() }
            }
            .modifier(Riquadro(col: col))
        } else if let v = t.vicino {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(v.obj) · \(v.metri) m").font(.system(size: 15, weight: .black)).foregroundStyle(Theme.testo)
                    Text("Timer \(t.minuti) min").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.dim)
                }
                chip("Avvia timer") { t.avvia(v.evento, v.obj) }
                chip("Salta", Theme.dim) { t.salta(v.evento, v.obj) }
            }
            .modifier(Riquadro(col: Theme.red))
        }
    }

    struct Riquadro: ViewModifier {
        let col: Color
        func body(content: Content) -> some View {
            content.padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface.opacity(0.95)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(col, lineWidth: 1.5))
        }
    }

    private func chip(_ s: String, _ c: Color = Theme.oliveBright, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(s).font(.system(size: 13, weight: .heavy)).foregroundStyle(c)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10).fill(c.opacity(0.14)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(c.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Impostazioni del timer OBJ (nel pannello del timer di gioco).
struct ImpostazioniTimerObj: View {
    @ObservedObject private var t = TimerObj.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TIMER OBIETTIVI").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundStyle(Theme.dim)
            Stepper("Durata \(t.minuti) min", value: $t.minuti, in: 1...600, step: 5)
            Stepper("Avviso a \(t.metri) m", value: $t.metri, in: 10...1000, step: 10)
            Toggle("Avviso avvicinandosi", isOn: $t.avvisi)
        }
        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.testo).tint(Theme.olive)
    }
}
