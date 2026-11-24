import Foundation

/// Dati di prova delle tavole 37-42 (sezione Eventi). Si aggiungono a quelli di base solo quando l'anteprima
/// parte sulla scheda Eventi (`-debug.tab 2`), così Home e le altre anteprime restano come le loro tavole.
///
/// Argomenti di avvio:
///   -debug.eventi.apri dettaglio|azioni|commenti|nuovo   apre direttamente la sottoschermata
///   -debug.eventi.risposta si|no|nessuna                 risposta all'evento della tavola 38/39 (1ª Tappa PCR)
extension Anteprima {
    static var schedaEventi: Bool { UserDefaults.standard.integer(forKey: "debug.tab") == Schede.eventi }
    static var apriEventi: String? { UserDefaults.standard.string(forKey: "debug.eventi.apri") }
    /// -debug.eventi.cqb si: risposta al Domenicale CQB con conteggi e commenti della tavola 68 (iPad)
    static var cqbTavola68: String? { UserDefaults.standard.string(forKey: "debug.eventi.cqb") }

    private static let fmtEv: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm"; return f
    }()
    private static func tra(_ n: Int, _ ora: Int, _ min: Int = 0) -> String {
        let cal = Calendar.current
        let g = cal.date(byAdding: .day, value: n, to: cal.startOfDay(for: Date())) ?? Date()
        return fmtEv.string(from: cal.date(bySettingHour: ora, minute: min, second: 0, of: g) ?? g)
    }

    /// id dell'evento della tavola 38/39
    static let idTappa = 105

    static func conEventiTavole(_ base: [JEvento]) -> [JEvento] {
        guard schedaEventi else { return base }
        var b = base
        if let i = b.firstIndex(where: { $0.id == 101 }) { b[i].creato_da = utente.id; if let r = cqbTavola68 { b[i].mia_risposta = r } }
        if let i = b.firstIndex(where: { $0.id == 102 }) { b[i].breve = "solo direttivo" }
        if let i = b.firstIndex(where: { $0.id == 104 }) { b[i].breve = "deleghe aperte" }
        let r = UserDefaults.standard.string(forKey: "debug.eventi.risposta")
        var tappa = JEvento(id: idTappa, nome: "1ª Tappa PCR Operation Hidden Path", tipo: "gara", inizio: "2026-12-13T07:00", fine: "2026-12-13T18:00",
                            luogo: "Alberobello (BA)", lat: 40.7826, lon: 17.2370, note: nil, archiviato: 0, mio_ruolo: "operatore",
                            mia_risposta: r == "nessuna" ? nil : (r ?? "no"),
                            interno: 0, stato: "approvato", scadenza: "2026-12-06T20:00", posti: 8, quota: 20, n_si: 5)
        tappa.host = "Simone Cito VIPER"; tappa.n_no = 2; tappa.n_attesa = 0
        b.append(tappa)
        b.append(JEvento(id: 106, nome: "Domenicale Vernole", tipo: "allenamento", inizio: tra(22, 8, 30), fine: tra(22, 13), luogo: "Campo Vernole",
                         lat: 40.29, lon: 18.30, note: nil, archiviato: 0, mio_ruolo: "operatore", mia_risposta: "si", interno: 1, stato: "approvato", n_si: 10))
        b.append(JEvento(id: 107, nome: "Cena sociale", tipo: "associazione", inizio: tra(24, 20, 30), fine: tra(24, 23), luogo: "Sede",
                         lat: nil, lon: nil, note: nil, archiviato: 0, mio_ruolo: "operatore", mia_risposta: "si", stato: "approvato", n_si: 21))
        // proposte da approvare (scheda "Da approvare · 2")
        b.append(JEvento(id: 108, nome: "Notturna CQB", tipo: "allenamento", inizio: tra(12, 20), fine: tra(12, 23), luogo: "Campo Calimera",
                         lat: nil, lon: nil, note: nil, archiviato: 0, mio_ruolo: "operatore", mia_risposta: nil, interno: 1, stato: "proposto"))
        b.append(JEvento(id: 109, nome: "Corso radio", tipo: "riunione", inizio: tra(17, 18), fine: tra(17, 20), luogo: "Sede",
                         lat: nil, lon: nil, note: nil, archiviato: 0, mio_ruolo: "operatore", mia_risposta: nil, stato: "proposto"))
        // passati
        b.append(JEvento(id: 110, nome: "Domenicale CQB", tipo: "allenamento", inizio: tra(-12, 8, 30), fine: tra(-12, 13), luogo: "Campo Calimera",
                         lat: nil, lon: nil, note: nil, archiviato: 0, mio_ruolo: "operatore", mia_risposta: "si", interno: 1, stato: "approvato", n_si: 14))
        return b
    }

    /// tavole 38-40: chi ha risposto (tavola 40: "5 soci" senza risposta)
    static func presenzeEvento(_ ev: Int) -> JPresenze? {
        if ev == idTappa { return presenzeTappa }
        if ev == 101, let r = cqbTavola68 {   // tavola 68: 5 sì · 2 no · 1 arbitro · 35 attesa
            return JPresenze(presenze: [JPresenza(utente: utente.id, callsign: utente.callsign, nome: utente.nome, risposta: r, presente: nil)],
                             conta: JPresenze.Conta(si: 5, no: 2, forse: 0, senza_risposta: 35, attesa: 0, arbitro: 1))
        }
        if ev == 101 { return JPresenze(presenze: [], conta: JPresenze.Conta(si: 12, no: 1, forse: 0, senza_risposta: 5, attesa: 0, arbitro: 0)) }
        return nil
    }

    /// tavole 38-39: chi ha risposto
    static var presenzeTappa: JPresenze {
        let si = UserDefaults.standard.string(forKey: "debug.eventi.risposta") == "si"
        return JPresenze(presenze: [JPresenza(utente: utente.id, callsign: utente.callsign, nome: utente.nome, risposta: si ? "si" : nil, presente: nil)],
                         conta: JPresenze.Conta(si: 5, no: 2, forse: 0, senza_risposta: 35, attesa: 0, arbitro: 1))
    }

    /// tavole 38 e 41: commenti
    static func commentiEvento(_ ev: Int) -> [JCommentoEvento] {
        let cal = Calendar.current
        func ts(_ giorni: Int, _ h: Int, _ m: Int) -> Double {
            let g = cal.date(byAdding: .day, value: giorni, to: cal.startOfDay(for: Date())) ?? Date()
            return (cal.date(bySettingHour: h, minute: m, second: 0, of: g) ?? g).timeIntervalSince1970
        }
        return [
            JCommentoEvento(id: 1, testo: "Porto io le cariche delle radio, ne ho 6.", ts: ts(-1, 18, 40), autore: 7, callsign: "RAVEN"),
            JCommentoEvento(id: 2, testo: "Chi ha posto in macchina da Lecce? Siamo in 2.", ts: ts(-1, 19, 2), autore: 8, callsign: "WOLF"),
            ev == idTappa || (ev == 101 && cqbTavola68 != nil)   // tavole 38 e 68: "4 nuovi", tutti di altri
                ? JCommentoEvento(id: 3, testo: "Iscrizione fatta, quota pagata.", ts: ts(-1, 17, 30), autore: 10, callsign: "VIPER")
                : JCommentoEvento(id: 3, testo: "Io ho 3 posti, partenza 7:30 da piazza Mazzini.", ts: ts(-1, 19, 10), autore: utente.id, callsign: utente.callsign, risposta_a: 2),
            JCommentoEvento(id: 4, testo: ev == idTappa ? "Ricordate occhiali omologati: senza non si entra." : "Ricordate occhiali omologati: senza non si entra in campo.",
                            ts: ts(0, 8, 15), autore: 9, callsign: "DIRETTIVO"),
        ]
    }

    /// tavola 39: riepiloghi sotto i riquadri
    static let riepilogoEvento = RiepilogoEvento(punti: 32, documenti: 3, saldo: 12, pronti: 9, voci: 12)

    /// tavola 42: luoghi suggeriti
    static let luoghiEventi = ["Campo Calimera", "Sede", "Campo Vernole"]
}
