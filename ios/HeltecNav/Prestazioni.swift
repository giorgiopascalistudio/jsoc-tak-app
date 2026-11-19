import UIKit

/// Cronometro delle prestazioni. Un "sorvegliante" su un altro filo chiede ogni 50 ms al filo principale di rispondere:
/// se tarda più di 80 ms l'app è davvero bloccata (non è il display che rallenta da solo a schermo fermo).
/// Registra la sezione, cosa stava facendo l'app (decodifiche lente ecc.) e ogni 30 s manda il riepilogo al server.
final class Sentinella: Thread {
    override func main() {
        while true {
            let t0 = CACurrentMediaTime()
            let s = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { s.signal() }
            s.wait()
            let dt = (CACurrentMediaTime() - t0) * 1000
            if dt > 80 { DispatchQueue.main.async { Prestazioni.shared.blocco(dt) } }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }
}

@MainActor
final class Prestazioni {
    static let shared = Prestazioni()
    private var sentinella: Sentinella?
    private(set) var sezione = "Home"
    private var cambioDa: CFTimeInterval?
    private var blocchi: [(String, Double, String)] = []     // sezione, ms, attività recenti
    private var attivitaRecenti: [(CFTimeInterval, String)] = []
    private var lente: [String] = []
    private var cambi: [String] = []
    private var invio: Timer?

    static let nomi = [Schede.home: "Home", Schede.eventi: "Eventi", Schede.associazione: "Associazione", Schede.strumenti: "Strumenti",
                       Schede.profilo: "Profilo", Schede.mappa: "Mappa"]

    func avvia() {
        guard sentinella == nil else { return }
        let s = Sentinella(); s.qualityOfService = .userInteractive; s.start()
        sentinella = s
        invio = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in Task { @MainActor in Prestazioni.shared.manda() } }
    }

    func cambio(verso t: Int) {
        sezione = Self.nomi[t] ?? "\(t)"
        cambioDa = CACurrentMediaTime()
        // quando il filo principale torna libero, la sezione è disegnata
        DispatchQueue.main.async { [weak self] in
            guard let self, let i = self.cambioDa else { return }
            self.cambi.append("\(self.sezione) \(Int((CACurrentMediaTime() - i) * 1000)) ms")
            self.cambioDa = nil
        }
    }

    /// annota un lavoro fatto sul filo principale (es. decodifica lenta di una risposta del server)
    func attivita(_ t: String) {
        let ora = CACurrentMediaTime()
        attivitaRecenti.append((ora, t))
        attivitaRecenti.removeAll { ora - $0.0 > 3 }
        if lente.count < 60 { lente.append(t) }
    }

    func blocco(_ ms: Double) {
        let ora = CACurrentMediaTime()
        let vicine = attivitaRecenti.filter { ora - $0.0 < 1.5 }.map(\.1).joined(separator: "; ")
        if blocchi.count < 80 { blocchi.append((sezione, ms, vicine)) }
    }

    private func manda() {
        guard !blocchi.isEmpty || !cambi.isEmpty || !lente.isEmpty else { return }
        var righe = ["PRESTAZIONI2 \(Diagnostica.versione) · \(UIDevice.current.model) iOS \(UIDevice.current.systemVersion)"]
        if !cambi.isEmpty { righe.append("cambi sezione: " + cambi.joined(separator: ", ")) }
        for b in blocchi { righe.append("BLOCCO \(Int(b.1)) ms in \(b.0)" + (b.2.isEmpty ? "" : " · durante: \(b.2)")) }
        if !lente.isEmpty { righe.append("lavori lenti: " + lente.joined(separator: " | ")) }
        blocchi = []; cambi = []; lente = []
        UserDefaults.standard.set(righe.joined(separator: "\n"), forKey: "diag.dainviare")
        Diagnostica.invia()
    }
}
