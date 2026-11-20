import Foundation
import Combine
import ConnectIQ

/// Ponte con l'app JSOC TAK sugli orologi Garmin (Connect IQ, tramite l'app Garmin Connect via Bluetooth).
/// Il telefono manda all'orologio eventi, OBJ e compagni; l'orologio rimanda le scelte della Ruota e i messaggi rapidi.
@MainActor
final class GarminPonte: NSObject, ObservableObject {
    static let shared = GarminPonte()
    static let schema = "jsoctak-ciq"
    /// id dell'app nel manifest dell'orologio (garmin/manifest.xml)
    static let idApp = UUID(uuidString: "6c0e39f3-b5ad-4f0b-80da-8d0aa4c28487")!

    @Published private(set) var orologi: [IQDevice] = []
    @Published private(set) var collegati: Set<UUID> = []
    @Published var ultimoMessaggio: String = ""

    private var avviato = false
    private var timer: AnyCancellable?
    private var ultimoInvio = Date.distantPast
    private let chiave = "garmin.orologi"

    func avvia() {
        guard !avviato else { return }
        avviato = true
        ConnectIQ.sharedInstance().initialize(withUrlScheme: Self.schema, uiOverrideDelegate: nil)
        if let d = UserDefaults.standard.data(forKey: chiave),
           let lista = try? NSKeyedUnarchiver.unarchivedArrayOfObjects(ofClass: IQDevice.self, from: d) {
            usa(lista)
        }
        // stato all'orologio ogni 5 secondi (solo se è cambiato qualcosa di importante lo manda subito)
        timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.inviaStato() }
    }

    /// apre Garmin Connect per scegliere gli orologi da collegare
    func scegliOrologi() {
        avvia()
        ConnectIQ.sharedInstance().showDeviceSelection()
    }

    /// Garmin Connect torna nell'app con l'elenco degli orologi scelti
    func apri(_ url: URL) -> Bool {
        guard url.scheme == Self.schema else { return false }
        avvia()
        let lista = (ConnectIQ.sharedInstance().parseDeviceSelectionResponse(from: url) as? [IQDevice]) ?? []
        if let d = try? NSKeyedArchiver.archivedData(withRootObject: lista, requiringSecureCoding: false) {
            UserDefaults.standard.set(d, forKey: chiave)
        }
        usa(lista)
        return true
    }

    private func usa(_ lista: [IQDevice]) {
        ConnectIQ.sharedInstance().unregister(forAllDeviceEvents: self)
        ConnectIQ.sharedInstance().unregister(forAllAppMessages: self)
        orologi = lista
        for d in lista {
            ConnectIQ.sharedInstance().register(forDeviceEvents: d, delegate: self)
            ConnectIQ.sharedInstance().register(forAppMessages: app(d), delegate: self)
        }
        inviaStato(subito: true)
    }

    private func app(_ d: IQDevice) -> IQApp { IQApp(uuid: Self.idApp, store: Self.idApp, device: d) }

    // MARK: stato verso l'orologio

    func inviaStato(subito: Bool = false) {
        guard !orologi.isEmpty, subito || Date().timeIntervalSince(ultimoInvio) > 4.5 else { return }
        ultimoInvio = Date()
        let s = EventoStore.shared
        let presenze = s.eventi.filter { $0.fase != 2 && !$0.proposto && !$0.annullato && ($0.mia_risposta == "si" || $0.mia_risposta == "arbitro" || $0.staff) }
        let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "EEE d · HH:mm"
        var m: [String: Any] = [
            "t": "stato",
            "ev": presenze.prefix(8).map { [$0.id, $0.nome, $0.dataInizio.map { f.string(from: $0) } ?? "", $0.tipo] as [Any] },
            "notte": UserDefaults.standard.bool(forKey: "night.on"),
        ]
        if let e = s.corrente {
            m["id"] = e.id
            m["nome"] = e.nome
            m["obj"] = (e.punti ?? []).filter { $0.tipo == "obj" }.prefix(30).enumerated().map { i, p in
                [Int(p.nome.filter(\.isNumber).prefix(3)) ?? (i + 1), p.nome, p.lat, p.lon] as [Any]
            }
            m["comp"] = s.squadra.prefix(12).map { c -> [Any] in
                return [String(c.callsign.prefix(2)).uppercased(), c.lat, c.lon, c.dir ?? c.rotta ?? 0, NSNull()]
            }
        }
        for d in orologi where collegati.contains(d.uuid) {
            ConnectIQ.sharedInstance().sendMessage(m, to: app(d), progress: nil) { _ in }
        }
    }
}

extension GarminPonte: IQDeviceEventDelegate {
    nonisolated func deviceStatusChanged(_ device: IQDevice!, status: IQDeviceStatus) {
        Task { @MainActor in
            if status == .connected { self.collegati.insert(device.uuid) } else { self.collegati.remove(device.uuid) }
            self.inviaStato(subito: true)
        }
    }
}

extension GarminPonte: IQAppMessageDelegate {
    nonisolated func receivedMessage(_ message: Any!, from app: IQApp!) {
        guard let d = message as? [String: Any], let t = d["t"] as? String else { return }
        Task { @MainActor in
            switch t {
            case "ciao": self.inviaStato(subito: true)
            case "notte": UserDefaults.standard.set((d["v"] as? Bool) ?? false, forKey: "night.on")
            case "evento":
                if let id = d["id"] as? Int, let e = EventoStore.shared.eventi.first(where: { $0.id == id }) { EventoStore.shared.scegli(e) }
                self.inviaStato(subito: true)
            case "chat":
                if let testo = d["testo"] as? String, let id = EventoStore.shared.corrente?.id {
                    _ = try? await JsocClient.shared.scrivi(id, testo, nil)
                }
                self.ultimoMessaggio = "Orologio: \(d["testo"] as? String ?? "")"
            case "azione":
                // le azioni che servono il telefono (foto, resoconto, misura) aprono la mappa sul punto scelto
                self.ultimoMessaggio = "Orologio: \(d["a"] as? String ?? "") su OBJ \(d["obj"] as? Int ?? 0)"
                NotificationCenter.default.post(name: .azioneOrologio, object: nil, userInfo: d)
            default: break
            }
        }
    }
}

extension Notification.Name {
    static let azioneOrologio = Notification.Name("azioneOrologio")
}

import SwiftUI

/// Sezione del Profilo: collega l'orologio Garmin (si sceglie in Garmin Connect)
struct OrologioGarminSezione: View {
    @ObservedObject private var g = GarminPonte.shared
    var body: some View {
        Section {
            Button { g.scegliOrologi() } label: { Label("Collega orologio Garmin", systemImage: "applewatch.radiowaves.left.and.right") }
            if !g.orologi.isEmpty {
                Text("\(g.orologi.count) orologi scelti · \(g.collegati.count) collegati ora").font(.footnote).foregroundStyle(Theme.dim)
            }
        } footer: { Text("Si apre Garmin Connect: scegli l'orologio con l'app JSOC TAK installata.") }
    }
}
