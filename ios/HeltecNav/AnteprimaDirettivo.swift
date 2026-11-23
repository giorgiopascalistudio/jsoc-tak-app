import Foundation

/// Dati di prova delle tavole 47-51 (Associazione, vista del direttivo) per le anteprime sul simulatore.
extension Anteprima {
    static let dirIdViper = 4

    /// data fissa dell'anno corrente (le tavole sono di novembre)
    private static func giornoDir(_ mese: Int, _ g: Int, _ ora: Int = 0, _ min: Int = 0, anno: Int = AnnoDir.corrente) -> Date {
        Calendar.current.date(from: DateComponents(year: anno, month: mese, day: g, hour: ora, minute: min)) ?? Date()
    }
    private static func iso(_ d: Date) -> String { isoGiorno(d) }

    static var dirSpese: [JSpesaProposta] {
        let ieri = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        let ts = (Calendar.current.date(bySettingHour: 19, minute: 40, second: 0, of: ieri) ?? ieri).timeIntervalSince1970
        return [JSpesaProposta(id: 1, importo: 38.50, descrizione: "Nastro e batterie per il campo", utente: 12, callsign: "COBRA", ts: ts,
                               negozio: "Brico Lecce", data: iso(giornoDir(11, 18)), categoria: "materiale", evento: 101,
                               evento_nome: "Domenicale CQB", evento_inizio: iso(giornoDir(11, 22)), tipo: "rimborso", stato: "attesa", ricevuta: false)]
    }

    static var dirRiepilogo: RiepilogoDir {
        RiepilogoDir(nonAssicurati: 3, aspiranti: 1, spese: dirSpese, scadenze: 5, prossimaAssemblea: "12 dic")
    }

    static let dirSoci: [SocioRigaDir] = [
        SocioRigaDir(id: 1, callsign: "GREG", nome: "Giorgio P.", sigla: "GP", carica: "PRESIDENTE", giorniCertificato: 18, telefono: "+393331234567", rango: 0),
        SocioRigaDir(id: 2, callsign: "RAVEN", nome: "Luca M.", sigla: "RV", carica: "SEGRETARIO", telefono: "+393330000002", rango: 2),
        SocioRigaDir(id: 3, callsign: "WOLF", nome: "Andrea S.", sigla: "WL", carica: "TESORIERE", quotaDaPagare: true, telefono: "+393330000003", rango: 3),
        SocioRigaDir(id: 4, callsign: "VIPER", nome: "Simone C.", sigla: "VP", carica: "SOCIO", assicurato: false, telefono: "+393330000004"),
        SocioRigaDir(id: 5, callsign: "DECA", nome: "Davide R.", sigla: "DC", carica: "SOCIO", assicurato: false),
        SocioRigaDir(id: 6, callsign: "ORSO", nome: "Marco T.", sigla: "OR", carica: "SOCIO", assicurato: false, quotaDaPagare: true),
        SocioRigaDir(id: 7, callsign: "Marco", nome: "aspirante", sigla: "MA", carica: "ASPIRANTE", aspirante: true, uscite: 3, usciteRichieste: 3, rango: 9),
        SocioRigaDir(id: 8, callsign: "LILLO", nome: "Paolo L.", sigla: "LL", carica: "SOCIO", giorniCertificato: 25, telefono: "+393330000008"),
    ]

    /// VIPER (tavola 49): 11 presenze su 18 eventi, serie 3, ultima il 15 novembre
    static var dirScheda: JSchedaDir {
        let a = AnnoDir.corrente, q = AnnoDir.quota
        var s = JSchedaDir(id: dirIdViper, nome: "Simone Conte", callsign: "VIPER")
        s.ruolo = "socio"; s.telefono = "+39 333 000 0004"; s.email = "viper@esempio.it"
        s.nascita = iso(giornoDir(2, 10, anno: a - 31 - (Calendar.current.component(.month, from: Date()) < 2 ? 1 : 0)))
        s.luogo_nascita = "Lecce"; s.indirizzo = "via Trinchese 4"; s.cap = "73100"; s.citta = "Lecce"; s.provincia = "LE"
        s.ammesso = "2021-03-01"; s.specialita = "Assaltatore"
        s.certificato_scadenza = iso(giornoDir(5, 20, anno: a + 1)); s.certificato_tipo = "non agonistico"; s.gruppo_sanguigno = "A+"
        s.quote = [JSchedaDir.Quota(anno: q, importo: 40, pagata: 0),
                   JSchedaDir.Quota(anno: q - 1, importo: 40, pagata: 1, data: iso(giornoDir(1, 9, anno: q - 1)), conto: "cassa", ricevuta: "E-\(q - 1)-004"),
                   JSchedaDir.Quota(anno: q - 2, importo: 40, pagata: 1, data: iso(giornoDir(1, 14, anno: q - 2)), conto: "banca"),
                   JSchedaDir.Quota(anno: q - 3, importo: 40, pagata: 1, data: iso(giornoDir(1, 12, anno: q - 3)), conto: "cassa")]
        s.tesseramenti = [JSchedaSocio.Tessera(anno: q, figt: 0, intranet: 0, numero: nil, note: nil),
                          JSchedaSocio.Tessera(anno: q - 1, figt: 1, intranet: 1, numero: "PB-2231", note: nil),
                          JSchedaSocio.Tessera(anno: q - 2, figt: 1, intranet: 1, numero: "PB-2231", note: nil)]
        let presenti: [(Int, Int)] = [(1, 11), (2, 8), (2, 15), (3, 8), (5, 10), (5, 24), (6, 7), (9, 13), (10, 4), (10, 18), (11, 15)]
        let assenti: [(Int, Int)] = [(1, 25), (3, 22), (4, 12), (6, 21), (7, 5), (8, 9), (9, 27)]
        var ev: [JSchedaSocio.Evento] = []
        for (i, x) in (presenti.map { ($0, 1) } + assenti.map { ($0, 0) }).enumerated() {
            ev.append(JSchedaSocio.Evento(id: 500 + i, nome: "Domenicale", tipo: "allenamento", inizio: isoGiorno(giornoDir(x.0.0, x.0.1)) + "T08:30",
                                          stato: "approvato", risposta: "si", presente: x.1))
        }
        s.eventi = ev
        s.statistiche = JSchedaSocio.Stat(eventi: 18, presenze: 11, arbitro: 0, percentuale: 61)
        return s
    }

    struct MovimentoDir { let cifre: String; let data: Date; let lettura: String; let socio: JSocioLibro; let evento: (id: Int, nome: String, data: Date) }

    /// tavola 50: uscita di 38,50 € letta dallo scontrino, rimborso a COBRA
    static var dirMovimento: MovimentoDir {
        MovimentoDir(cifre: "38,50", data: giornoDir(11, 18), lettura: "Brico Lecce · 18 nov",
                     socio: JSocioLibro(id: 12, callsign: "COBRA", nome: "Fabio R.", ruolo: "socio", carica: nil, stato_socio: "socio",
                                        ammesso: "2022-01-10", uscito: nil, uscita_motivo: nil, creato: nil, attivo: 1, telefono: nil, email: nil),
                     evento: (101, "Domenicale CQB", giornoDir(11, 22, 8, 30)))
    }
}
