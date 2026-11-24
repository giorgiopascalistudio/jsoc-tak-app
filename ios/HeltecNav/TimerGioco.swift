import SwiftUI
import UserNotifications

/// Timer di gioco (tavola 61b): «Fine gioco» o cronometro, uguale su orologio Garmin e Android (TimerGioco.kt).
/// Chi lo cambia manda tutto lo stato con una versione: vince la più alta. Si conta da ore di fine/inizio (epoca, s).
@MainActor
final class TimerGioco: ObservableObject {
    static let shared = TimerGioco()
    struct Stato: Codable, Equatable {
        var modo = "fine", corsa = false, durata = 3600, fine = 0, resto = 3600, inizio = 0, accum = 0, avvisi = true, versione = 0
    }
    @Published private(set) var s: Stato
    private var fatti: Set<Int> = []
    private var orologio: Timer?

    init() {
        s = (UserDefaults.standard.data(forKey: "timer.gioco")).flatMap { try? JSONDecoder().decode(Stato.self, from: $0) } ?? Stato()
        battito()
    }

    private var ora: Int { Int(Date().timeIntervalSince1970) }

    var secondi: Int {
        if s.modo == "crono" { return s.corsa ? s.accum + (ora - s.inizio) : s.accum }
        return max(s.corsa ? s.fine - ora : s.resto, 0)
    }

    static func testo(_ x: Int) -> String { String(format: "%02d:%02d", x / 60, x % 60) }

    func avviaPausa() {
        var n = s
        if n.corsa {
            if n.modo == "crono" { n.accum += ora - n.inizio } else { n.resto = max(n.fine - ora, 0) }
            n.corsa = false
        } else {
            if n.modo == "crono" { n.inizio = ora } else { if n.resto <= 0 { n.resto = n.durata }; n.fine = ora + n.resto }
            n.corsa = true
        }
        cambia(n)
    }
    func azzera() { fatti = []; var n = s; n.corsa = false; n.resto = n.durata; n.accum = 0; cambia(n) }
    func cambiaModo() { guard !s.corsa else { return }; fatti = []; var n = s; n.modo = n.modo == "fine" ? "crono" : "fine"; n.resto = n.durata; n.accum = 0; cambia(n) }
    func durata(minuti: Int) { var n = s; n.durata = min(max(minuti, 1), 600) * 60; if !n.corsa { n.resto = n.durata }; cambia(n) }
    func avvisi(_ v: Bool) { var n = s; n.avvisi = v; cambia(n) }

    private func cambia(_ n: Stato) {
        var n = n
        n.versione = max(ora, s.versione + 1)
        applica(n)
        GarminPonte.shared.inviaStato(subito: true)
    }

    private func applica(_ n: Stato) {
        s = n
        if let d = try? JSONEncoder().encode(n) { UserDefaults.standard.set(d, forKey: "timer.gioco") }
        battito()
        programmaAvvisi()
    }

    /// dall'orologio: {"t":"timer", m,c,d,f,r,i,a,av,v}
    func daOrologio(_ d: [String: Any]) {
        func n(_ k: String) -> Int? { (d[k] as? NSNumber)?.intValue }
        guard let v = n("v"), v > s.versione else { return }
        applica(Stato(modo: d["m"] as? String ?? "fine", corsa: (d["c"] as? Bool) ?? false, durata: n("d") ?? 3600, fine: n("f") ?? 0,
                      resto: n("r") ?? 3600, inizio: n("i") ?? 0, accum: n("a") ?? 0, avvisi: (d["av"] as? Bool) ?? true, versione: v))
        GarminPonte.shared.inviaStato(subito: true)
    }

    var perOrologio: [String: Any] {
        ["m": s.modo, "c": s.corsa, "d": s.durata, "f": s.fine, "r": s.resto, "i": s.inizio, "a": s.accum, "av": s.avvisi, "v": s.versione]
    }

    /// ridisegno ogni secondo solo mentre corre
    private func battito() {
        if s.corsa, orologio == nil {
            orologio = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tic() }
            }
        } else if !s.corsa { orologio?.invalidate(); orologio = nil }
    }

    private func tic() {
        objectWillChange.send()
        if s.corsa, s.modo == "fine", s.fine - ora <= 0 { var n = s; n.corsa = false; n.resto = 0; applica(n) }
    }

    /// avvisi a -10, -5, -1 minuti e alla fine come notifiche programmate: arrivano anche a telefono bloccato
    private func programmaAvvisi() {
        let c = UNUserNotificationCenter.current()
        let ids = ["timer.600", "timer.300", "timer.60", "timer.0"]
        c.removePendingNotificationRequests(withIdentifiers: ids)
        guard s.corsa, s.modo == "fine", s.avvisi else { return }
        for soglia in [600, 300, 60, 0] where soglia < s.durata {
            let dt = s.fine - soglia - ora
            guard dt > 0 else { continue }
            let x = UNMutableNotificationContent()
            x.title = soglia == 0 ? "Fine gioco" : "Fine gioco tra \(soglia / 60) min"
            x.sound = .default
            c.add(UNNotificationRequest(identifier: "timer.\(soglia)", content: x,
                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(dt), repeats: false)))
        }
    }
}

/// Pillola in mappa (tocca per i comandi) + pannello.
struct TimerGiocoMappa: View {
    @ObservedObject private var t = TimerGioco.shared
    @State private var aperto = false
    var body: some View {
        VStack(spacing: 8) {
            Button { aperto.toggle(); if aperto { GuidaApp.shared.entra("mappa.timer") } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "timer").font(.system(size: 13, weight: .bold))
                    Text(t.s.modo == "crono" ? "CRONO" : "FINE GIOCO").font(.system(size: 9, weight: .heavy, design: .monospaced))
                    Text(TimerGioco.testo(t.secondi)).font(.system(size: 17, weight: .heavy, design: .monospaced)).foregroundStyle(Theme.testo)
                }
                .foregroundStyle(t.s.corsa ? Theme.green : Theme.amber)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x0F1C10).opacity(0.94)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(t.s.corsa ? Theme.green : Theme.amber, lineWidth: 1))
            }
            .buttonStyle(.plain)
            if aperto { pannello }
        }
    }

    var pannello: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TIMER DI GIOCO · UGUALE SULL'OROLOGIO").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundStyle(Theme.dim)
            HStack {
                chip(t.s.modo == "crono" ? "Cronometro" : "Fine gioco", t.s.corsa ? Theme.dim : Theme.oliveBright) { t.cambiaModo() }
                Spacer()
                Text(TimerGioco.testo(t.secondi)).font(.system(size: 26, weight: .heavy, design: .monospaced))
                    .foregroundStyle(t.s.corsa ? Theme.green : Theme.testo)
            }
            if t.s.modo == "fine" {
                HStack {
                    Text("Durata").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.testo)
                    Spacer()
                    chip("−") { t.durata(minuti: t.s.durata / 60 - 5) }
                    Text("\(t.s.durata / 60) min").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundStyle(Theme.testo).frame(width: 70)
                    chip("+") { t.durata(minuti: t.s.durata / 60 + 5) }
                }
            }
            HStack(spacing: 8) {
                chip(t.s.corsa ? "Pausa" : "Avvia", t.s.corsa ? Theme.amber : Theme.green) { t.avviaPausa() }
                chip("Azzera", Theme.dim) { t.azzera() }
                chip(t.s.avvisi ? "Avvisi −10 −5 −1" : "Avvisi spenti", t.s.avvisi ? Theme.amber : Theme.dim) { t.avvisi(!t.s.avvisi) }
            }
        }
        .padding(14).frame(width: 320)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.stroke, lineWidth: 1))
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
