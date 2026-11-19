import UIKit

/// Cronometro delle prestazioni: quanto ci mette ogni sezione a comparire dopo il tocco e quanti "blocchi"
/// (fotogrammi oltre 50 ms) ci sono in ogni sezione. Ogni 30 s manda un riepilogo al server (diagnostica).
@MainActor
final class Prestazioni: NSObject {
    static let shared = Prestazioni()
    private var link: CADisplayLink?
    private var ultimo: CFTimeInterval = 0
    private var inizio: CFTimeInterval?
    private var verso = ""
    private(set) var sezione = "Home"
    private var cambi: [String: [Double]] = [:]          // sezione → latenze in ms
    private var blocchi: [String: [Double]] = [:]        // sezione → durate dei blocchi in ms
    private var invio: Timer?

    static let nomi = [Schede.home: "Home", Schede.eventi: "Eventi", Schede.associazione: "Associazione", Schede.strumenti: "Strumenti",
                       Schede.profilo: "Profilo", Schede.mappa: "Mappa"]

    func avvia() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(fotogramma(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        invio = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in Task { @MainActor in Prestazioni.shared.manda() } }
    }

    /// chiamato al tocco sulla barra delle sezioni
    func cambio(verso t: Int) {
        inizio = CACurrentMediaTime()
        verso = Self.nomi[t] ?? "\(t)"
    }

    @objc private func fotogramma(_ l: CADisplayLink) {
        let ora = l.timestamp
        if ultimo > 0 {
            let dt = (ora - ultimo) * 1000
            if dt > 50 { blocchi[sezione, default: []].append(dt) }
        }
        ultimo = ora
        if let i = inizio {
            // primo fotogramma dopo il tocco: la sezione nuova è stata disegnata
            cambi[verso, default: []].append((CACurrentMediaTime() - i) * 1000)
            sezione = verso
            inizio = nil
        }
    }

    private func manda() {
        guard !cambi.isEmpty || !blocchi.isEmpty else { return }
        func riassunto(_ v: [Double]) -> String {
            let o = v.sorted()
            return "\(v.count)× media \(Int(v.reduce(0, +) / Double(v.count))) ms, max \(Int(o.last ?? 0)) ms"
        }
        var righe = ["PRESTAZIONI \(Diagnostica.versione) · \(UIDevice.current.model) iOS \(UIDevice.current.systemVersion)"]
        for (k, v) in cambi.sorted(by: { $0.key < $1.key }) { righe.append("cambio → \(k): \(riassunto(v))") }
        for (k, v) in blocchi.sorted(by: { $0.key < $1.key }) { righe.append("blocchi in \(k): \(riassunto(v))") }
        cambi = [:]; blocchi = [:]
        UserDefaults.standard.set(righe.joined(separator: "\n"), forKey: "diag.dainviare")
        Diagnostica.invia()
    }
}
