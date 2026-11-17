import Foundation
import WatchConnectivity

/// Collegamento con l'app dell'Apple Watch: manda lo stato (percorso, finestra, meteo, PC/server)
/// e riceve dal polso "OBJ fatto" e "apri finestra".
@MainActor
final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()
    weak var mission: Mission?
    private var ultimo = Data()
    private var ultimoInvio = Date.distantPast

    func avvia() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func invia(_ s: StatoOrologio, forza: Bool = false) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        var confronto = s
        confronto.aggiornato = .distantPast
        guard let firma = try? JSONEncoder().encode(confronto) else { return }
        guard forza || (firma != ultimo && Date().timeIntervalSince(ultimoInvio) > 10) else { return }
        guard let d = try? JSONEncoder().encode(s) else { return }
        ultimo = firma
        ultimoInvio = Date()
        try? WCSession.default.updateApplicationContext(["stato": d])
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        self.session(session, didReceiveMessage: userInfo)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let azione = message["azione"] as? String, code = message["code"] as? String
        let quando = message["quando"] as? Date
        Task { @MainActor in
            guard let m = self.mission else { return }
            if azione == "avvia" { m.avviaPercorso(quando ?? Date()); return }
            guard let code else { return }
            switch azione {
            case "fatto":
                if let t = Gara.percorso.first(where: { $0.code == code }), !m.fatti.contains(code) { m.toggle(t) }
                if m.finestra?.code == code { m.chiudiFinestra(fatto: true) }
            case "finestra": m.apriFinestra(code)
            case "chiudi": m.chiudiFinestra(fatto: false)
            default: break
            }
        }
    }
}
