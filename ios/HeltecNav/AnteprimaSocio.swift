import SwiftUI

/// Dati di prova della vista del socio (anteprime con `-anteprima.dati YES -debug.socio.vista YES`),
/// uguali alle tavole Associazione10, SchedaSocioSocio10, DocumentiSocio10, SpesaSocio10.
extension Anteprima {
    enum Socio {
    static let gruppi = [JGruppo(id: 1, nome: "Alfa", colore: nil, membri: nil)]

    static var viper: JProfilo {
        var p = JProfilo(id: 7, nome: "Simone Conte", callsign: "VIPER", ruolo: "socio")
        p.cognome = "Conte"; p.telefono = "+39 333 555 0101"; p.email = "simone@esempio.it"
        p.nascita = "1994-08-04"; p.citta = "Lecce"; p.ammesso = "2021-01-09"; p.specialita = "assaltatore"; p.gruppi = [1]
        return p
    }

    static var associazione: DatiAssocSocio {
        var d = DatiAssocSocio()
        d.stagione = "2026/27"
        d.statoTessera = .init(testo: "ASSICURATO", colore: Theme.oliveBright)
        d.certificato = .init(testo: "scade tra 18 g", colore: Theme.red)
        d.annoQuota = 2027
        d.quota = .init(testo: "da pagare · 40 €", colore: Theme.amber)
        d.presenze = .init(testo: "14 nel 2026", colore: Theme.oliveBright)
        d.avviso = (201, "Nuove regole campo di Melendugno")
        d.assemblea = .init(id: 301, titolo: "ASSEMBLEA ORDINARIA", quando: "12 DIC · 21:00",
                            odg: "Rendiconto 2025/26 · quote 2027 · elezione Resp. magazzino", mia: nil)
        d.avvisiNuovi = 2; d.soci = 18; d.sondaggi = 1
        return d
    }

    static let documenti: [JDocSocio] = [
        JDocSocio(tipo: "documento", titolo: "Documento d'identità", dettaglio: "carta d'identità · scade 3/2031", stato: "ok"),
        JDocSocio(tipo: "certificato", titolo: "Certificato medico", dettaglio: "non agonistico · scade 12/5/2027", stato: "ok"),
        JDocSocio(tipo: "domanda", titolo: "Domanda di iscrizione", dettaglio: "firmata il 9 gen 2021", stato: "firmata"),
        JDocSocio(tipo: "privacy", titolo: "Privacy e consensi", dettaglio: "foto/video sì · dati sanitari sì", stato: "ok"),
        JDocSocio(tipo: "tessera", titolo: "Tessera FIGT 2026/27", dettaglio: "non ancora caricata in Intranet", stato: "manca"),
        JDocSocio(tipo: "ricevute", titolo: "Ricevute quote", dettaglio: "2026 · 2025 · 2024", stato: "archivio", numero: 3),
        JDocSocio(tipo: "attestati", titolo: "Attestati e corsi", dettaglio: "primo soccorso BLSD · 2024", stato: "archivio", numero: 1),
    ]

    static var spesa: BozzaSpesa {
        var b = BozzaSpesa()
        b.importo = "38,50"; b.negozio = "Brico Lecce"; b.letto = true
        b.data = Calendar.current.date(from: DateComponents(year: Calendar.current.component(.year, from: Date()), month: 11, day: 18))
        b.perCosa = "Nastro e batterie per il campo"
        b.categoria = 0; b.pagamento = 0
        b.evento = "Domenicale CQB · 22 nov"
        return b
    }
    }
}
