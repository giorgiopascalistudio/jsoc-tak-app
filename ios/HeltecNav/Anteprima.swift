import Foundation

/// Dati di prova per le anteprime sul simulatore (argomento di avvio `-anteprima.dati YES`).
/// Non tocca il server: l'app si comporta come collegata e mostra eventi e avvisi finti.
enum Anteprima {
    static var attiva: Bool { UserDefaults.standard.bool(forKey: "anteprima.dati") }

    static let utente = JUtente(id: 1, nome: "Giorgio", callsign: "GREG", ruolo: "direttivo")

    private static let formato: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm"; return f
    }()

    /// data a N giorni da oggi, all'ora indicata
    private static func giorno(_ n: Int, _ ora: Int, _ min: Int = 0) -> String {
        let cal = Calendar.current
        let g = cal.date(byAdding: .day, value: n, to: cal.startOfDay(for: Date())) ?? Date()
        return formato.string(from: cal.date(bySettingHour: ora, minute: min, second: 0, of: g) ?? g)
    }

    static func eventi() -> [JEvento] {
        [
            JEvento(id: 101, nome: "Domenicale CQB", tipo: "allenamento", inizio: giorno(2, 8, 30), fine: giorno(2, 13), luogo: "Campo Calimera",
                    lat: 40.2503, lon: 18.2789, note: nil, archiviato: 0, mio_ruolo: "operatore", mia_risposta: nil,
                    interno: 1, stato: "approvato", scadenza: giorno(1, 20), posti: nil, quota: nil, n_si: 12),
            JEvento(id: 102, nome: "Riunione direttivo", tipo: "riunione", inizio: giorno(7, 21), fine: giorno(7, 23), luogo: "Sede",
                    lat: nil, lon: nil, note: nil, archiviato: 0, mio_ruolo: "operatore", mia_risposta: "si", stato: "approvato", n_si: 5),
            JEvento(id: 103, nome: "Trofeo del Salento", tipo: "gara", inizio: giorno(9, 7), fine: giorno(9, 18), luogo: "Lecce",
                    lat: 40.35, lon: 18.17, note: nil, archiviato: 0, mio_ruolo: "operatore", mia_risposta: nil,
                    interno: 0, stato: "approvato", scadenza: giorno(5, 20), posti: 12, quota: 25, n_si: 9),
            JEvento(id: 104, nome: "Assemblea ordinaria", tipo: "associazione", inizio: giorno(15, 18), fine: giorno(15, 20), luogo: "Sede",
                    lat: nil, lon: nil, note: nil, archiviato: 0, mio_ruolo: "operatore", mia_risposta: "si", stato: "approvato", n_si: 14),
        ]
    }

    static let home = JHome(
        prossimi: [],
        avvisi: [JHome.Avviso(tipo: "promemoria", testo: "Quota sociale 2027 · 40 €", evento: nil, destra: "entro 31 dic"),
                 JHome.Avviso(tipo: "avviso", testo: "Certificato medico", evento: nil, destra: "scade tra 18 g")],
        post_nuovi: 1, sondaggi_aperti: 1, soci_attivi: 18,
        direttivo: JHome.Direttivo(quote_da_incassare: 3, saldo: 412.30, certificati_scaduti: 1, proposte: 0))

    static var profilo: JProfilo {
        var p = JProfilo(id: 1, nome: "Giorgio Pascali", callsign: "GREG", ruolo: "direttivo")
        p.email = "giorgio@esempio.it"; p.telefono = "+39 333 1234567"; p.nascita = "1990-03-12"; p.luogo_nascita = "Lecce"
        p.cf = "PSCGRG90C12E506X"; p.gruppo_sanguigno = "A+"; p.emergenza = "Maria R. +39 333 7654321"
        p.certificato_scadenza = String(giorno(18, 0).prefix(10))
        p.quote = [JQuotaMia(anno: Calendar.current.component(.year, from: Date()) + 1, importo: 40, pagata: 0, data: nil)]
        return p
    }

    static var scheda: JSchedaSocio {
        var s = JSchedaSocio(id: 1, nome: "Giorgio Pascali", callsign: "GREG", ruolo: "direttivo")
        s.carica = "Presidente"; s.ammesso = "2019-04-01"
        s.tesseramenti = [JSchedaSocio.Tessera(anno: Calendar.current.component(.year, from: Date()), figt: 1, intranet: 1, numero: nil, note: nil)]
        s.statistiche = JSchedaSocio.Stat(eventi: 18, presenze: 14, arbitro: 1, percentuale: 78)
        s.dispositivi = [JSchedaSocio.Disp(nome: "iPhone", creato: nil), JSchedaSocio.Disp(nome: "iPad", creato: nil)]
        return s
    }
}
