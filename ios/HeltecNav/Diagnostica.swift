import Foundation
import UIKit

/// Registro dei crash: salva le ultime azioni e l'eventuale eccezione, e al riavvio
/// manda tutto al server (anche da un dispositivo non ancora collegato, appena conosce un indirizzo).
enum Diagnostica {
    private static let cartella = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    static let fileCrash = cartella.appendingPathComponent("diag_crash.txt")
    static let filePassi = cartella.appendingPathComponent("diag_passi.txt")
    static let fileAvvio = cartella.appendingPathComponent("diag_avvio")
    // percorso in C per i gestori dei segnali (lì non si può usare Swift in sicurezza)
    private static var percorsoC: [CChar] = Array(fileCrash.path.utf8CString)

    static func attiva() {
        // l'avvio precedente non è arrivato a "attivo da 15 s" né in background: si è chiuso da solo
        let avvioInterrotto = FileManager.default.fileExists(atPath: fileAvvio.path)
        var rapporto = (try? String(contentsOf: fileCrash, encoding: .utf8)) ?? ""
        if avvioInterrotto && rapporto.isEmpty { rapporto = "chiusura improvvisa (blocco, memoria o crash senza eccezione)" }
        let passi = (try? String(contentsOf: filePassi, encoding: .utf8)) ?? ""
        if !rapporto.isEmpty { UserDefaults.standard.set(rapporto + "\n--- ultime azioni ---\n" + passi, forKey: "diag.dainviare") }
        try? FileManager.default.removeItem(at: fileCrash)
        try? "".write(to: filePassi, atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: fileAvvio.path, contents: Data())

        _ = percorsoC.count   // inizializzato qui, non dentro il gestore del segnale
        NSSetUncaughtExceptionHandler { e in
            let t = "ECCEZIONE \(e.name.rawValue): \(e.reason ?? "")\n" + e.callStackSymbols.joined(separator: "\n")
            try? t.write(to: Diagnostica.fileCrash, atomically: true, encoding: .utf8)
        }
        for s in [SIGABRT, SIGSEGV, SIGBUS, SIGTRAP, SIGILL, SIGFPE] {
            signal(s) { n in
                let fd = Darwin.open(Diagnostica.percorsoC, O_WRONLY | O_CREAT | O_APPEND, 0o644)
                if fd >= 0 {
                    var msg = "\nSEGNALE \(n)\n" + Thread.callStackSymbols.joined(separator: "\n")
                    msg.withUTF8 { _ = Darwin.write(fd, $0.baseAddress, $0.count) }
                    Darwin.close(fd)
                }
                signal(n, SIG_DFL)
                raise(n)
            }
        }
        passo("avvio \(versione)")
    }

    static var versione: String {
        "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")(\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"
    }

    /// annota un'azione (le ultime finiscono nel rapporto)
    static func passo(_ t: String) {
        let riga = "\(Date().formatted(date: .omitted, time: .standard)) \(t)\n"
        guard let d = riga.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: filePassi) {
            h.seekToEndOfFile(); h.write(d); try? h.close()
        } else {
            try? d.write(to: filePassi)
        }
    }

    /// l'app è rimasta su abbastanza o è andata in background: l'avvio è riuscito
    static func avvioRiuscito() { try? FileManager.default.removeItem(at: fileAvvio) }
    static func ripartito() { FileManager.default.createFile(atPath: fileAvvio.path, contents: Data()) }

    /// manda il rapporto in sospeso a tutti gli indirizzi noti
    static func invia() {
        guard let r = UserDefaults.standard.string(forKey: "diag.dainviare"), !r.isEmpty else { return }
        let d = UserDefaults.standard
        let indirizzi = [d.string(forKey: "jsoc.url"), d.string(forKey: "jsoc.url2"), invitoAperto()]
            .compactMap { $0 }.filter { !$0.isEmpty }
        guard !indirizzi.isEmpty else { return }
        let corpo: [String: String] = ["dispositivo": UIDevice.current.model + " " + modello(), "sistema": UIDevice.current.systemVersion,
                                       "versione": versione, "rapporto": r]
        guard let dati = try? JSONSerialization.data(withJSONObject: corpo) else { return }
        for base in Set(indirizzi) {
            guard let url = URL(string: base + "/api/diagnostica") else { continue }
            var q = URLRequest(url: url, timeoutInterval: 15)
            q.httpMethod = "POST"; q.httpBody = dati
            q.setValue("application/json", forHTTPHeaderField: "Content-Type")
            URLSession.shared.dataTask(with: q) { _, resp, _ in
                if (resp as? HTTPURLResponse)?.statusCode == 200 {
                    DispatchQueue.main.async { UserDefaults.standard.removeObject(forKey: "diag.dainviare") }
                }
            }.resume()
        }
    }

    private static func invitoAperto() -> String? {
        guard let s = UserDefaults.standard.string(forKey: "jsoc.invito"), let c = URLComponents(string: s) else { return nil }
        return c.queryItems?.first { $0.name == "u" }?.value
    }

    private static func modello() -> String {
        var s = utsname(); uname(&s)
        return withUnsafeBytes(of: &s.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}
