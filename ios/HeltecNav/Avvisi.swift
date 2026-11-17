import Foundation
import UserNotifications
import UIKit

extension Notification.Name {
    /// Tocco su una notifica di novità: apre Documenti (userInfo["fascicolo"] se c'è).
    static let openDocs = Notification.Name("remida.openDocs")
}

/// Notifiche locali delle novità della biblioteca (niente push Apple: con l'Apple ID gratuito non si può).
/// L'app controlla il PC/server ogni 2 minuti, anche col telefono bloccato finché la posizione in
/// background è attiva, e avvisa con le righe nuove di "## Novità" dei riepilogo.md.
final class Avvisi: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Avvisi()

    func attiva() {
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        c.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Righe "- ..." della sezione "## Novità" di un riepilogo.md.
    static func righeNovita(_ testo: String) -> [String] {
        var dentro = false, out: [String] = []
        for riga in testo.components(separatedBy: .newlines) {
            let r = riga.trimmingCharacters(in: .whitespaces)
            if r.hasPrefix("## ") { dentro = r.lowercased().hasPrefix("## novit"); continue }
            if dentro, r.hasPrefix("- ") { out.append(String(r.dropFirst(2))) }
        }
        return out
    }

    /// fascicolo -> righe nuove; altri = file nuovi senza una riga di novità nel loro riepilogo.
    func notifica(novita: [(String, [String])], altri: [String: Int]) {
        guard UserDefaults.standard.object(forKey: "avvisi.on") as? Bool ?? true else { return }
        var richieste: [(String, String, String)] = []
        for (fasc, righe) in novita where !righe.isEmpty {
            let corpo = righe.prefix(3).map { $0.replacingOccurrences(of: "**", with: "") }.joined(separator: "\n")
                + (righe.count > 3 ? "\n+\(righe.count - 3) altre" : "")
            richieste.append((fasc, fasc, corpo))
        }
        for (fasc, n) in altri where n > 0 {
            richieste.append((fasc, fasc, n == 1 ? "1 documento nuovo" : "\(n) documenti nuovi"))
        }
        let c = UNUserNotificationCenter.current()
        for (fasc, titolo, corpo) in richieste.prefix(6) {
            let n = UNMutableNotificationContent()
            n.title = "Re Mida · " + titolo
            n.body = corpo
            n.sound = .default
            n.interruptionLevel = .timeSensitive
            n.threadIdentifier = fasc
            n.userInfo = ["fascicolo": fasc]
            c.add(UNNotificationRequest(identifier: UUID().uuidString, content: n, trigger: nil))
        }
    }

    // banner anche ad app aperta
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if info["fascicolo"] != nil {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .openDocs, object: nil, userInfo: info)
            }
        }
        done()
    }
}
