import UIKit
import SwiftUI
import PDFKit

// MARK: - Documenti automatici dell'associazione: carta intestata, testi, firme, tabelle

struct JIntestazione: Codable {
    var nome: String? = "B.A.S. J.S.O.C."
    var sottotitolo: String? = "Soft Air Galatina"
    var indirizzo: String? = ""
    var citta: String? = ""
    var telefono: String? = ""
    var cellulare: String? = ""
    var email: String? = ""
    var pec: String? = ""
    var cf: String? = ""
    var iban: String? = ""
    var quota: Double? = 50
    var presidente: String? = ""
    var affiliazioni: String? = ""
    var polizza: String? = ""
    var polizza_link: String? = ""
    var certificato: String? = ""
    var giorni_certificato: Int? = 15
    var anno: Int? = nil

    var n: String { nome ?? "B.A.S. J.S.O.C." }
    var annoAssociativo: Int { anno ?? Calendar.current.component(.year, from: Date()) }
}

/// intestazione, loghi e firma del presidente (scaricati dal server una volta)
@MainActor
final class DocAssoc: ObservableObject {
    static let shared = DocAssoc()
    @Published var intest = JIntestazione()
    @Published var loghi: [String: UIImage] = [:]
    @Published var firmaPresidente: UIImage?
    private var caricato = false

    func carica(forza: Bool = false) async {
        guard forza || !caricato else { return }
        let j = JsocClient.shared
        if let i: JIntestazione = try? await j.get("/api/associazione/intestazione") { intest = i }
        for k in ["figt", "jsoc", "acsi"] where loghi[k] == nil || forza {
            if let d = try? await j.scaricaDati("/api/associazione/logo/\(k)"), let im = UIImage(data: d) { loghi[k] = im }
        }
        if let d = try? await j.scaricaDati("/api/associazione/firma-presidente"), let im = UIImage(data: d) { firmaPresidente = im }
        caricato = true
    }
}

func dataIta(_ s: String?) -> String {
    guard let s, s.count >= 10 else { return s ?? "" }
    let p = s.prefix(10).split(separator: "-")
    return p.count == 3 ? "\(p[2])/\(p[1])/\(p[0])" : s
}
func oggiISO() -> String { FormatoGiorno.f.string(from: Date()) }
func euroTesto(_ v: Double) -> String { String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",") }

/// importo in lettere, come si scrive sulle ricevute: 50 → "cinquanta/00"
func importoInLettere(_ v: Double) -> String {
    let intero = Int(v), cent = Int(((v - Double(intero)) * 100).rounded())
    return "\(numeroInLettere(intero))/\(String(format: "%02d", cent))"
}
func numeroInLettere(_ n: Int) -> String {
    let unita = ["zero", "uno", "due", "tre", "quattro", "cinque", "sei", "sette", "otto", "nove", "dieci", "undici", "dodici",
                 "tredici", "quattordici", "quindici", "sedici", "diciassette", "diciotto", "diciannove"]
    let decine = ["", "", "venti", "trenta", "quaranta", "cinquanta", "sessanta", "settanta", "ottanta", "novanta"]
    func sotto100(_ x: Int) -> String {
        if x < 20 { return unita[x] }
        var d = decine[x / 10]
        let u = x % 10
        if u == 1 || u == 8 { d.removeLast() }
        return u == 0 ? d : d + unita[u]
    }
    func sotto1000(_ x: Int) -> String {
        let c = x / 100, r = x % 100
        let cs = c == 0 ? "" : (c == 1 ? "cento" : unita[c] + "cento")
        if r == 0 { return cs.isEmpty ? "zero" : cs }
        var rs = sotto100(r)
        if !cs.isEmpty && (r / 10 == 8) { return String(cs.dropLast()) + rs }
        if cs.isEmpty { return rs }
        rs = cs + rs
        return rs
    }
    if n == 0 { return "zero" }
    if n < 1000 { return sotto1000(n) }
    let m = n / 1000, r = n % 1000
    let ms = m == 1 ? "mille" : sotto1000(m) + "mila"
    return r == 0 ? ms : ms + sotto1000(r)
}

// MARK: scrittore di pagine

final class ScrittorePDF {
    let foglio: CGRect
    let ctx: UIGraphicsPDFRendererContext
    let intest: JIntestazione
    let loghi: [String: UIImage]
    var y: CGFloat = 0
    let m: CGFloat = 52
    var pagine = 0
    var filigrana: String?

    var larghezza: CGFloat { foglio.width - 2 * m }
    var fondo: CGFloat { foglio.height - 122 }

    init(foglio: CGRect, ctx: UIGraphicsPDFRendererContext, intest: JIntestazione, loghi: [String: UIImage]) {
        self.foglio = foglio; self.ctx = ctx; self.intest = intest; self.loghi = loghi
    }

    static func crea(orizzontale: Bool = false, intest: JIntestazione, loghi: [String: UIImage], filigrana: String? = nil,
                     _ disegna: (ScrittorePDF) -> Void) -> Data {
        let r = orizzontale ? CGRect(x: 0, y: 0, width: 842, height: 595) : CGRect(x: 0, y: 0, width: 595, height: 842)
        let f = UIGraphicsPDFRendererFormat()
        f.documentInfo = [kCGPDFContextCreator as String: "JSOC TAK", kCGPDFContextAuthor as String: intest.n]
        return UIGraphicsPDFRenderer(bounds: r, format: f).pdfData { ctx in
            let s = ScrittorePDF(foglio: r, ctx: ctx, intest: intest, loghi: loghi)
            s.filigrana = filigrana
            s.pagina()
            disegna(s)
        }
    }

    func pagina() {
        ctx.beginPage()
        pagine += 1
        testata()
        piede()
        if let f = filigrana {
            let a = NSAttributedString(string: f, attributes: [.font: UIFont.boldSystemFont(ofSize: 90), .foregroundColor: UIColor.red.withAlphaComponent(0.18)])
            let c = ctx.cgContext
            c.saveGState()
            c.translateBy(x: foglio.midX, y: foglio.midY)
            c.rotate(by: -.pi / 5)
            let sz = a.size()
            a.draw(at: CGPoint(x: -sz.width / 2, y: -sz.height / 2))
            c.restoreGState()
        }
        y = 138
    }

    private func immagine(_ k: String, in r: CGRect) {
        guard let im = loghi[k], im.size.width > 0 else { return }
        let s = min(r.width / im.size.width, r.height / im.size.height)
        let w = im.size.width * s, h = im.size.height * s
        im.draw(in: CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h))
    }

    private func testata() {
        immagine("figt", in: CGRect(x: m, y: 16, width: 100, height: 66))
        immagine("jsoc", in: CGRect(x: foglio.midX - 58, y: 8, width: 116, height: 116))
        immagine("acsi", in: CGRect(x: foglio.width - m - 100, y: 26, width: 100, height: 46))
    }

    private func piede() {
        var yy = foglio.height - 108
        func riga(_ s: String, _ f: UIFont) {
            guard !s.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            let st = NSMutableParagraphStyle(); st.alignment = .center
            let a = NSAttributedString(string: s, attributes: [.font: f, .paragraphStyle: st, .foregroundColor: UIColor.black])
            let h = a.boundingRect(with: CGSize(width: foglio.width, height: 100), options: .usesLineFragmentOrigin, context: nil).height
            a.draw(in: CGRect(x: 0, y: yy, width: foglio.width, height: h + 2))
            yy += h + 1
        }
        let stencil = UIFont(name: "Copperplate-Bold", size: 21) ?? .boldSystemFont(ofSize: 21)
        let stencil2 = UIFont(name: "Copperplate-Bold", size: 13) ?? .boldSystemFont(ofSize: 13)
        let times = UIFont(name: "TimesNewRomanPSMT", size: 11) ?? .systemFont(ofSize: 11)
        riga(intest.n, stencil)
        riga((intest.sottotitolo ?? "").uppercased(), stencil2)
        riga([intest.indirizzo ?? "", intest.citta ?? ""].filter { !$0.isEmpty }.joined(separator: " – "), times)
        let tel = [(intest.telefono ?? "").isEmpty ? "" : "Tel\\Fax: \(intest.telefono ?? "")", (intest.cellulare ?? "").isEmpty ? "" : "Cell. \(intest.cellulare ?? "")"]
        riga(tel.filter { !$0.isEmpty }.joined(separator: " "), times)
        riga([intest.email ?? "", intest.pec ?? ""].filter { !$0.isEmpty }.joined(separator: "          "), times)
    }

    func spazio(_ h: CGFloat) { y += h }
    func assicura(_ h: CGFloat) { if y + h > fondo { pagina() } }

    func paragrafo(_ a: NSAttributedString, dopo: CGFloat = 7, rientro: CGFloat = 0) {
        let w = larghezza - rientro
        let r = a.boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let h = ceil(r.height)
        if y + h > fondo && h < fondo - 138 { pagina() }
        a.draw(with: CGRect(x: m + rientro, y: y, width: w, height: h + 4), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        y += h + dopo
    }

    func titolo(_ s: String, _ size: CGFloat = 11.5, dopo: CGFloat = 6) {
        paragrafo(Testo.t(s, grassetto: true, size: size, allinea: .center), dopo: dopo)
    }

    /// riga di firma: etichetta, immagine della firma sopra la linea
    func firma(_ etichetta: String, _ img: UIImage?, x: CGFloat? = nil, larghezza w: CGFloat = 220, avanza: Bool = true) {
        assicura(78)
        let xx = x ?? (foglio.width - m - w)
        Testo.t(etichetta, size: 10.5, allinea: .center).draw(in: CGRect(x: xx, y: y, width: w, height: 16))
        if let img, img.size.width > 0 {
            let s = min((w - 20) / img.size.width, 44 / img.size.height)
            let iw = img.size.width * s, ih = img.size.height * s
            img.draw(in: CGRect(x: xx + (w - iw) / 2, y: y + 14 + (44 - ih), width: iw, height: ih))
        }
        let c = ctx.cgContext
        c.setStrokeColor(UIColor.black.cgColor); c.setLineWidth(0.6)
        c.move(to: CGPoint(x: xx, y: y + 62)); c.addLine(to: CGPoint(x: xx + w, y: y + 62)); c.strokePath()
        if avanza { y += 72 }
    }

    /// tabella con intestazione ripetuta a ogni pagina; larghezze in frazioni
    func tabella(_ colonne: [String], _ righe: [[String]], larghezze: [CGFloat], size: CGFloat = 9) {
        let tot = larghezze.reduce(0, +)
        let ws = larghezze.map { $0 / tot * larghezza }
        let c = ctx.cgContext
        func riga(_ celle: [String], testa: Bool) {
            let attr = celle.map { Testo.t($0, grassetto: testa, size: size, allinea: .left) }
            var h: CGFloat = 0
            for (i, a) in attr.enumerated() {
                h = max(h, ceil(a.boundingRect(with: CGSize(width: ws[i] - 6, height: 400), options: [.usesLineFragmentOrigin], context: nil).height))
            }
            h += 6
            if y + h > fondo { pagina(); if !testa { riga(colonne, testa: true) } }
            var x = m
            if testa {
                c.setFillColor(UIColor(white: 0.88, alpha: 1).cgColor)
                c.fill(CGRect(x: m, y: y, width: larghezza, height: h))
            }
            for (i, a) in attr.enumerated() {
                a.draw(with: CGRect(x: x + 3, y: y + 3, width: ws[i] - 6, height: h), options: [.usesLineFragmentOrigin], context: nil)
                x += ws[i]
            }
            c.setStrokeColor(UIColor(white: 0.6, alpha: 1).cgColor); c.setLineWidth(0.4)
            c.stroke(CGRect(x: m, y: y, width: larghezza, height: h))
            var xl = m
            for w in ws.dropLast() { xl += w; c.move(to: CGPoint(x: xl, y: y)); c.addLine(to: CGPoint(x: xl, y: y + h)) }
            c.strokePath()
            y += h
        }
        riga(colonne, testa: true)
        for r in righe { riga(r, testa: false) }
        y += 10
    }
}

/// testi della carta intestata: Times come i moduli dell'associazione
enum Testo {
    static func t(_ s: String, grassetto: Bool = false, corsivo: Bool = false, sottolineato: Bool = false, size: CGFloat = 11,
                  allinea: NSTextAlignment = .justified) -> NSAttributedString {
        let nome = grassetto ? "TimesNewRomanPS-BoldMT" : (corsivo ? "TimesNewRomanPS-ItalicMT" : "TimesNewRomanPSMT")
        let f = UIFont(name: nome, size: size) ?? (grassetto ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size))
        let st = NSMutableParagraphStyle(); st.alignment = allinea; st.lineSpacing = 1.5
        var a: [NSAttributedString.Key: Any] = [.font: f, .paragraphStyle: st, .foregroundColor: UIColor.black]
        if sottolineato { a[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        return NSMutableAttributedString(string: s, attributes: a)
    }
    /// valore compilato: grassetto e sottolineato (come scritto a mano sulla riga); vuoto = riga da riempire
    static func v(_ s: String?, size: CGFloat = 11) -> NSAttributedString {
        let x = (s ?? "").trimmingCharacters(in: .whitespaces)
        return t(x.isEmpty ? "______________" : x, grassetto: !x.isEmpty, sottolineato: !x.isEmpty, size: size)
    }
    static func unisci(_ parti: [NSAttributedString]) -> NSAttributedString {
        let r = NSMutableAttributedString()
        parti.forEach { r.append($0) }
        return r
    }
}

// MARK: - Modelli dei documenti

struct DatiDomanda: Codable {
    var nome = "", nascita = "", luogo_nascita = "", provincia_nascita = "", comune = "", provincia = "", cap = "", via = "", civico = ""
    var telefono = "", email = "", cf = "", allergie = ""
    var genitore_nome = "", genitore_nascita = "", genitore_luogo = "", genitore_cf = "", genitore_telefono = "", genitore_email = ""
    var consenso_privacy = false, consenso_immagini = false, accetta_statuto = false, accetta_rischi = false
    var data = ""

    init() {}
    enum CodingKeys: String, CodingKey {
        case nome, nascita, luogo_nascita, provincia_nascita, comune, provincia, cap, via, civico, telefono, email, cf, allergie
        case genitore_nome, genitore_nascita, genitore_luogo, genitore_cf, genitore_telefono, genitore_email
        case consenso_privacy, consenso_immagini, accetta_statuto, accetta_rischi, data
    }
    /// il server può non avere tutti i campi: quelli mancanti restano vuoti
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) -> String { (try? c.decodeIfPresent(String.self, forKey: k)) ?? "" }
        func b(_ k: CodingKeys) -> Bool { (try? c.decodeIfPresent(Bool.self, forKey: k)) ?? false }
        nome = s(.nome); nascita = s(.nascita); luogo_nascita = s(.luogo_nascita); provincia_nascita = s(.provincia_nascita)
        comune = s(.comune); provincia = s(.provincia); cap = s(.cap); via = s(.via); civico = s(.civico)
        telefono = s(.telefono); email = s(.email); cf = s(.cf); allergie = s(.allergie)
        genitore_nome = s(.genitore_nome); genitore_nascita = s(.genitore_nascita); genitore_luogo = s(.genitore_luogo)
        genitore_cf = s(.genitore_cf); genitore_telefono = s(.genitore_telefono); genitore_email = s(.genitore_email)
        consenso_privacy = b(.consenso_privacy); consenso_immagini = b(.consenso_immagini)
        accetta_statuto = b(.accetta_statuto); accetta_rischi = b(.accetta_rischi); data = s(.data)
    }

    var json: [String: Any] {
        guard let d = try? JSONEncoder().encode(self), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return o
    }
}

enum ModelliPDF {
    private static let T = Testo.self

    // MARK: domanda di iscrizione (maggiorenni e minorenni) + dichiarazione dei rischi
    static func domanda(_ d: DatiDomanda, minore: Bool, firma: UIImage?, firmaPresidente: UIImage?, anno: Int,
                        intest: JIntestazione, loghi: [String: UIImage]) -> Data {
        ScrittorePDF.crea(intest: intest, loghi: loghi) { s in
            let nomeA = intest.n.replacingOccurrences(of: "B.A.S. ", with: "")
            s.titolo("DOMANDA DI ISCRIZIONE ASSOCIATIVA ANNO \(anno)" + (minore ? " – SOCIO MINORENNE" : ""), 12, dopo: 8)
            var residenza: [NSAttributedString] = [T.t(", residente in "), T.v(d.comune), T.t(" ("), T.v(d.provincia), T.t("), CAP "), T.v(d.cap)]
            residenza += [T.t(" via "), T.v(d.via), T.t(" n° "), T.v(d.civico)]
            var parti: [NSAttributedString] = []
            if minore {
                parti += [T.t("Il sottoscritto "), T.v(d.genitore_nome), T.t(", nato a "), T.v(d.genitore_luogo), T.t(" il "), T.v(dataIta(d.genitore_nascita))]
                parti += [T.t(", Codice Fiscale "), T.v(d.genitore_cf), T.t(", cellulare n. "), T.v(d.genitore_telefono), T.t(", e-mail "), T.v(d.genitore_email)]
                parti += [T.t(", in qualità di genitore / esercente la responsabilità genitoriale del minore "), T.v(d.nome)]
                parti += [T.t(", nato a "), T.v(d.luogo_nascita), T.t(" ("), T.v(d.provincia_nascita), T.t(") il "), T.v(dataIta(d.nascita))]
                parti += residenza
                parti += [T.t(", Codice Fiscale del minore "), T.v(d.cf), T.t(",")]
            } else {
                parti += [T.t("Il sottoscritto "), T.v(d.nome), T.t(", nato a "), T.v(d.luogo_nascita), T.t(" ("), T.v(d.provincia_nascita)]
                parti += [T.t(") il "), T.v(dataIta(d.nascita))]
                parti += residenza
                parti += [T.t(", cellulare n. "), T.v(d.telefono), T.t(", e-mail "), T.v(d.email), T.t(", Codice Fiscale "), T.v(d.cf), T.t(",")]
            }
            s.paragrafo(T.unisci(parti))
            s.titolo("CHIEDE", dopo: 3)
            s.paragrafo(T.t("al Consiglio Direttivo " + (minore ? "che il minore sopra indicato sia ammesso" : "di essere ammesso") +
                            " nella B.A.S. \u{201C}\(nomeA)\u{201D}, dichiarando di conoscere lo Statuto, di accettarlo integralmente, di osservare le deliberazioni degli organi sociali e si impegna a fare quanto nelle sue possibilità per il raggiungimento degli scopi sociali. Inoltre,"))
            s.titolo("DICHIARA", dopo: 3)
            s.paragrafo(T.t("di assumere in proprio ogni e qualunque responsabilità riguardo la partecipazione " + (minore ? "del minore " : "") +
                            "alle attività associative, svincolando così da ogni e qualunque responsabilità l'Associazione, il Presidente, il Consiglio Direttivo; di essere a conoscenza dei rischi che tale attività ludico-sportiva può comportare alla propria persona ed a terzi, pertanto di assumerne le responsabilità; di aver preso visione e di accettare le polizze assicurative che il Club stipula tramite l'iscrizione alla F.I.G.T.-ASNWG e presenti sul sito www.figt.it"))
            rigaDataFirma(s, d.data, firma, "Firma" + (minore ? " del genitore" : ""))
            s.titolo(d.consenso_privacy ? "ACCONSENTE" : "NON ACCONSENTE", dopo: 3)
            s.paragrafo(T.t("al trattamento dei propri dati personali" + (minore ? " e di quelli del minore" : "") +
                            ", dichiarando di aver avuto, in particolare, conoscenza che i dati medesimi rientrano nel novero dei dati \u{201C}sensibili\u{201D} di cui all'articolo 4, comma 1, lettera d) del decreto legislativo 196/2003, vale a dire i dati idonei a rivelare l'origine razziale ed etnica, le convinzioni religiose, filosofiche o di altro genere, le opinioni politiche, l'adesione a partiti, sindacati, associazioni od organizzazioni a carattere religioso, filosofico, politico o sindacale, nonché i dati personali idonei a rivelare lo stato di salute e la vita sessuale."))
            s.paragrafo(T.t("Tali dati verranno trattati per finalità istituzionali, quindi strettamente connesse e strumentali all'attività statutaria. Il trattamento dei dati avverrà mediante utilizzo di supporto telematico o cartaceo idoneo a garantire la sicurezza e la riservatezza. In relazione ai predetti trattamenti si potrà esercitare i diritti di cui all'art. 7 del D.lgs. n. 196/2003 (cancellazione, modifica, opposizione al trattamento)."))
            s.firma("Firma", firma)
            s.titolo(d.consenso_immagini ? "AUTORIZZA" : "NON AUTORIZZA", dopo: 3)
            s.paragrafo(T.t("la pubblicazione sia in versione cartacea che telematica, su mezzi di stampa, audio-visivi e/o internet, di proprie immagini fotografiche e/o video" + (minore ? " e di quelle del minore" : "") +
                            ". Tale autorizzazione ha valore fino ad eventuale revoca che può avvenire in qualsiasi momento a semplice richiesta."))
            s.firma("Firma", firma)
            s.titolo("ALLEGA", dopo: 3)
            s.paragrafo(T.t("-  quota sociale annuale, non rimborsabile, pari a € \(euroTesto(intest.quota ?? 50))"), dopo: 2, rientro: 14)
            let cert = (intest.certificato ?? "").isEmpty ? "certificato di \u{201C}Idoneità Sportiva\u{201D} con test ECG sotto sforzo" : (intest.certificato ?? "")
            s.paragrafo(T.t("-  \(cert) da presentare all'iscrizione."), dopo: 10, rientro: 14)
            s.paragrafo(T.unisci([T.t("Data "), T.v(dataIta(d.data))]), dopo: 4)
            let y0 = s.y
            s.firma("Firma del Presidente della \(intest.n)", firmaPresidente, x: s.m, larghezza: 230, avanza: false)
            s.y = y0
            s.firma("Firma del Richiedente" + (minore ? " (genitore)" : ""), firma, larghezza: 230)
            s.paragrafo(T.t("NB: l'accettazione o meno della domanda è legata alla presentazione del Certificato di Idoneità Sportiva entro e non oltre \(intest.giorni_certificato ?? 15)gg dalla data della presente ed è ad insindacabile giudizio del Consiglio Direttivo.", size: 10))
            // seconda parte: dichiarazione dei rischi
            s.pagina()
            s.titolo("DICHIARAZIONE DI CONOSCENZA ED ACCETTAZIONE DEI RISCHI CONNESSI ALLA PRATICA DELL'ATTIVITA' LUDICO-SPORTIVA DEL SOFT AIR", 11.5, dopo: 10)
            dichiarazioneRischi(s, d, minore: minore, firma: firma)
        }
    }

    private static func rigaDataFirma(_ s: ScrittorePDF, _ data: String, _ firma: UIImage?, _ etichetta: String) {
        let y0 = s.y
        T.unisci([T.t("Data "), T.v(dataIta(data))]).draw(at: CGPoint(x: s.m + 40, y: y0 + 30))
        s.firma(etichetta, firma)
    }

    static func dichiarazioneRischi(_ s: ScrittorePDF, _ d: DatiDomanda, minore: Bool, firma: UIImage?) {
        s.paragrafo(T.unisci([T.t("Il Sottoscritto "), T.v(minore ? d.genitore_nome : d.nome),
                              T.t(minore ? ", per conto del minore " : ""), minore ? T.v(d.nome) : T.t(""),
                              T.t(" dichiara inoltre sotto la propria responsabilità:")]))
        s.paragrafo(T.t("1)  di conoscere e condividere il gioco del soft air, le sue regole e le sue modalità, in tutte le sue specialità (combat, biathlon, tiro pratico, altro), di approvarlo in quanto sport salubre e occasione di svago all'aria aperta, in un contesto di sano agonismo;"), rientro: 6)
        s.paragrafo(T.t("2)  in particolare, di sapere ed approvare preventivamente che potrà trovarsi, per esigenze di gioco, nelle seguenti situazioni:"), rientro: 6)
        let punti: [(String, String)] = [
            ("A)", "giocare in terreno accidentato che comporti la possibilità di: scivolare e/o cadere in buche, fossati, canaletti di scolo di origine naturale o artificiale; scivolare a causa di terreno fangoso, sabbioso, ghiaioso o di erba bagnata; inciampare in rialzi del terreno, sassi e pietre nonché altri detriti di origine naturale che si trovino sul campo; urtare pietre o sassi a causa di cadute o di semplici movimenti durante le fasi del gioco, a causa di propria imprudenza, negligenza o imperizia."),
            ("B)", "Nel caso di attività ludico-sportiva Soft Air di provvedere ad indossare obbligatoriamente durante lo svolgimento del gioco le Protezioni di Sicurezza per gli Occhi. Di provvedere personalmente anche all'uso delle protezioni Bocca/Viso e nel caso di mancato utilizzo, di assumersi in proprio ogni qualsiasi responsabilità per eventuali danni che dovesse subire, mallevando l'Organizzazione e la F.I.G.T.-ASNWG da ogni responsabilità in merito."),
            ("C)", "Giocare in aree non urbanizzate ed eventualmente in terreno boschivo, che comportino la possibilità di: urtare piante di alto fusto, cespugli e arbusti, rami, fronde o parte di essi; inciampare o scivolare a causa di tronchi, rami o altro (pigne, ghiande, fogliame, ecc…) che si trovino al suolo; venire a contatto con spine, sostanze di per sé urticanti e/o velenose e sostanze o altro (quali frutti, fiori, pollini, resine e similari) in grado di provocare reazioni allergiche non prevedibili naturalmente prodotte dai vegetali; venire a contatto con animali (mammiferi, uccelli e rettili) selvatici o inselvatichiti e domestici, insetti, che possono essere potenzialmente pericolosi per l'uomo in quanto portatori di malattie o parassiti nocivi, o naturalmente dotati di mezzi difensivi e offensivi di rilevante pericolosità (quali zanne, unghie, pungiglioni, veleni, aculei, ecc…); essere aggrediti e lesionati da tali animali o insetti;"),
            ("D)", "Avere accesso, per motivi di gioco, a strutture o infrastrutture che comportino la possibilità di: urtare, inciampare, scivolare e cadere da e contro tali strutture, a causa di propria imprudenza, negligenza o imperizia o semplice casualità;"),
            ("E)", "Partecipare, per motivi di gioco, allo scavo o alla costruzione di trincee, ripari e simili, nonché eventuali opere di disboscamento o manutenzione di aree boscose o non urbanizzate, con il conseguente utilizzo di utensili ed attrezzi ex-militari (vanghe, picconi, machete e simili), da campeggio o da giardinaggio (decespugliatori, cesoie, tagliaerba e simili), manuali o dotati di motore, nonché materiali di uso comune (pali, reti, fili spinato, travi e simili) o ex-militari (concertine, sacchi a terra, tende, reti mimetiche e simili), che comportino la possibilità di: tagliarsi, ferirsi, pungersi, scottarsi, lesionarsi esercitando un uso improprio (imperito, negligente o imprudente) di tali oggetti e/o materiali;"),
        ]
        for (l, t) in punti {
            s.paragrafo(T.unisci([T.t(l + "  ", grassetto: true, size: 10.5), T.t(t, size: 10.5)]), dopo: 4, rientro: 22)
        }
        let all = d.allergie.trimmingCharacters(in: .whitespaces)
        s.paragrafo(T.unisci([T.t("F)  ", grassetto: true, size: 10.5), T.t("Dichiara inoltre di essere affetto dalle seguenti patologie allergiche (se non presenti sbarrare le righe): ", size: 10.5),
                              all.isEmpty ? T.t("— nessuna —", grassetto: true, size: 10.5) : T.v(all, size: 10.5)]), dopo: 3, rientro: 22)
        s.paragrafo(T.t("Ed in tal senso dichiara, sotto la propria responsabilità, che tali allergie non hanno mai in passato dato atto a manifestazioni tali da mettere in pericolo la salute o l'incolumità dello stesso e che non vi sono indicazioni mediche contrarie all'esercizio fisico ed allo svolgimento di attività all'aria aperta.", size: 10.5), dopo: 4, rientro: 22)
        s.paragrafo(T.unisci([T.t("G)  ", grassetto: true, size: 10.5), T.t("Bersagliare ed eventualmente colpire altri, essere bersagliato ed eventualmente colpito da altri, con dispositivi (cosiddetti Air Soft Gun) ritenuti non idonei a recare offesa alla persona (ex art. 2, 3° comma, legge 110/75) dalla Commissione Consultiva Centrale per il Controllo delle Armi (istituita ex art. 6, legge 110/75), i cui proiettili possono in teoria provocare abrasioni della pelle o lividi.", size: 10.5)]), dopo: 8, rientro: 22)
        rigaDataFirma(s, d.data, firma, "Firma del Richiedente" + (minore ? " (genitore)" : ""))
    }

    // MARK: ricevuta
    struct DatiRicevuta { var numero: Int; var anno: Int; var data: String; var intestatario: String; var cf: String; var importo: Double
        var causale: String; var metodo: String; var annullata: Bool }

    static func ricevuta(_ r: DatiRicevuta, firma: UIImage?, intest: JIntestazione, loghi: [String: UIImage]) -> Data {
        ScrittorePDF.crea(intest: intest, loghi: loghi, filigrana: r.annullata ? "ANNULLATA" : nil) { s in
            s.spazio(10)
            s.titolo("RICEVUTA N. \(r.numero)/\(r.anno)", 16, dopo: 14)
            s.paragrafo(T.unisci([T.t("La \(intest.n)" + ((intest.cf ?? "").isEmpty ? "" : ", C.F. \(intest.cf ?? "")") + ", dichiara di aver ricevuto da "),
                                  T.v(r.intestatario), r.cf.isEmpty ? T.t("") : T.unisci([T.t(", C.F. "), T.v(r.cf)]),
                                  T.t(" la somma di "), T.t("€ \(euroTesto(r.importo))", grassetto: true),
                                  T.t(" (euro \(importoInLettere(r.importo)))", corsivo: true),
                                  T.t(" a titolo di: "), T.v(r.causale), T.t(".")]), dopo: 12)
            let metodo = ["contanti": "contanti", "bonifico": "bonifico bancario", "pos": "carta / POS", "paypal": "PayPal"][r.metodo] ?? r.metodo
            s.paragrafo(T.unisci([T.t("Modalità di pagamento: "), T.t(metodo, grassetto: true)]), dopo: 12)
            if r.causale.lowercased().contains("quota") {
                s.paragrafo(T.t("Quota associativa versata per le attività istituzionali dell'associazione, non soggetta a IVA ai sensi dell'art. 4 del D.P.R. 633/1972.", corsivo: true, size: 10), dopo: 4)
            }
            if r.importo > 77.47 {
                s.paragrafo(T.t("Imposta di bollo da € 2,00 da applicare sull'originale, ove dovuta.", corsivo: true, size: 10), dopo: 4)
            }
            s.spazio(20)
            s.paragrafo(T.unisci([T.t("\((intest.citta ?? "").isEmpty ? "" : (intest.citta ?? "") + ", ")"), T.v(dataIta(r.data))]), dopo: 10)
            s.firma("Per l'associazione – il Presidente / il Tesoriere", firma, larghezza: 250)
        }
    }

    // MARK: verbale del consiglio direttivo
    struct DatiRiunione { var numero: Int?; var data: String; var ora: String; var luogo: String; var odg: [String]
        var presenti: [String]; var assenti: [String]; var delibere: [(testo: String, esito: String, fav: Int, con: Int, ast: Int)]; var varie: String }

    static func verbaleDirettivo(_ r: DatiRiunione, firma: UIImage?, intest: JIntestazione, loghi: [String: UIImage]) -> Data {
        ScrittorePDF.crea(intest: intest, loghi: loghi) { s in
            s.titolo("VERBALE" + (r.numero.map { " N. \($0)" } ?? "") + " DELLA RIUNIONE DEL CONSIGLIO DIRETTIVO", 13, dopo: 12)
            s.paragrafo(T.unisci([T.t("Il giorno "), T.v(dataIta(r.data)), r.ora.isEmpty ? T.t("") : T.unisci([T.t(" alle ore "), T.v(r.ora)]),
                                  r.luogo.isEmpty ? T.t("") : T.unisci([T.t(", presso "), T.v(r.luogo)]),
                                  T.t(", si è riunito il Consiglio Direttivo della \(intest.n) per discutere e deliberare sul seguente ordine del giorno:")]))
            for (i, p) in r.odg.enumerated() { s.paragrafo(T.t("\(i + 1).  \(p)"), dopo: 2, rientro: 16) }
            s.spazio(6)
            s.paragrafo(T.unisci([T.t("Sono presenti: "), T.t(r.presenti.isEmpty ? "—" : r.presenti.joined(separator: ", "), grassetto: true), T.t(".")]), dopo: 3)
            if !r.assenti.isEmpty { s.paragrafo(T.unisci([T.t("Sono assenti: "), T.t(r.assenti.joined(separator: ", "), grassetto: true), T.t(".")]), dopo: 3) }
            s.paragrafo(T.t("Constatata la presenza di \(r.presenti.count) consiglieri su \(r.presenti.count + r.assenti.count), il Presidente dichiara validamente costituita la riunione e apre la seduta."), dopo: 10)
            for (i, d) in r.delibere.enumerated() {
                s.paragrafo(T.unisci([T.t("Delibera n. \(i + 1) – ", grassetto: true), T.t(d.testo)]), dopo: 2)
                let es = d.esito == "respinta" ? "respinta" : "approvata"
                s.paragrafo(T.t("La proposta è \(es) con \(d.fav) voti favorevoli, \(d.con) contrari e \(d.ast) astenuti.", corsivo: true), dopo: 8, rientro: 16)
            }
            if !r.varie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                s.paragrafo(T.t("Varie ed eventuali", grassetto: true), dopo: 2)
                s.paragrafo(T.t(r.varie), dopo: 8)
            }
            s.paragrafo(T.t("Non essendovi altro da discutere e deliberare, il Presidente dichiara chiusa la seduta. Del che è verbale, letto, approvato e sottoscritto."), dopo: 16)
            let y0 = s.y
            s.firma("Il Segretario", nil, x: s.m, larghezza: 200, avanza: false)
            s.y = y0
            s.firma("Il Presidente", firma, larghezza: 200)
        }
    }

    // MARK: assemblea: convocazione e verbale
    static func convocazione(_ a: JAssemblea, firma: UIImage?, intest: JIntestazione, loghi: [String: UIImage]) -> Data {
        ScrittorePDF.crea(intest: intest, loghi: loghi) { s in
            let tipo = a.tipo == "straordinaria" ? "STRAORDINARIA" : "ORDINARIA"
            s.titolo("CONVOCAZIONE DELL'ASSEMBLEA \(tipo) DEI SOCI", 13, dopo: 14)
            s.paragrafo(T.unisci([T.t("Il Presidente della \(intest.n) convoca l'Assemblea \(tipo.lowercased()) dei soci per il giorno "),
                                  T.v(dataIta(a.data)), (a.data ?? "").count > 10 ? T.unisci([T.t(" alle ore "), T.v(String((a.data ?? "").dropFirst(11).prefix(5)))]) : T.t(""),
                                  T.t(" presso "), T.v(a.luogo), T.t(", per discutere e deliberare sul seguente")]))
            s.titolo("ORDINE DEL GIORNO", dopo: 4)
            for (i, p) in a.odg.enumerated() { s.paragrafo(T.t("\(i + 1).  \(p.titolo)"), dopo: 2, rientro: 16) }
            s.spazio(8)
            s.paragrafo(T.t("Hanno diritto di voto i soci in regola con il versamento della quota associativa. Ogni socio può farsi rappresentare da un altro socio mediante delega scritta; ciascun socio può essere portatore di non più di due deleghe."), dopo: 6)
            s.paragrafo(T.t("Le deleghe possono essere conferite anche dall'app JSOC TAK, nella sezione Assemblee.", corsivo: true, size: 10), dopo: 18)
            s.paragrafo(T.unisci([T.t("\((intest.citta ?? "").isEmpty ? "" : (intest.citta ?? "") + ", ")"), T.v(dataIta(oggiISO()))]), dopo: 10)
            s.firma("Il Presidente", firma)
        }
    }

    static func verbaleAssemblea(_ a: JAssemblea, firma: UIImage?, intest: JIntestazione, loghi: [String: UIImage]) -> Data {
        ScrittorePDF.crea(intest: intest, loghi: loghi) { s in
            s.titolo("VERBALE DELL'ASSEMBLEA \(a.tipo == "straordinaria" ? "STRAORDINARIA" : "ORDINARIA") DEI SOCI", 13, dopo: 4)
            s.titolo(a.titolo, 11, dopo: 12)
            let righe = (a.verbale ?? "").components(separatedBy: "\n")
            for r in righe {
                let t = r.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { s.spazio(4); continue }
                s.paragrafo(T.t(t, grassetto: t.hasPrefix("#") || t == t.uppercased() && t.count < 60), dopo: 3)
            }
            s.spazio(14)
            let y0 = s.y
            s.firma("Il Segretario", nil, x: s.m, larghezza: 200, avanza: false)
            s.y = y0
            s.firma("Il Presidente", firma, larghezza: 200)
        }
    }

    // MARK: stampe
    static func libroSoci(_ soci: [JSocioLibro], intest: JIntestazione, loghi: [String: UIImage]) -> Data {
        ScrittorePDF.crea(orizzontale: true, intest: intest, loghi: loghi) { s in
            s.titolo("LIBRO DEI SOCI – aggiornato al \(dataIta(oggiISO()))", 13, dopo: 10)
            let righe = soci.enumerated().map { i, x in
                ["\(i + 1)", x.callsign, x.nome ?? "", NomiAssoc.carica(x.carica ?? "").capitalized, dataIta(x.ammesso),
                 dataIta(x.uscito), x.uscita_motivo ?? "", x.telefono ?? "", x.email ?? ""]
            }
            s.tabella(["N°", "Callsign", "Nome e cognome", "Carica", "Ammesso", "Uscito", "Motivo uscita", "Telefono", "E-mail"], righe,
                      larghezze: [3, 8, 16, 9, 7, 7, 10, 10, 16])
        }
    }

    static func tesserati(_ t: JTesseramento, intest: JIntestazione, loghi: [String: UIImage]) -> Data {
        ScrittorePDF.crea(orizzontale: true, intest: intest, loghi: loghi) { s in
            s.titolo("ELENCO TESSERATI F.I.G.T. – ANNO \(t.anno)", 13, dopo: 10)
            let righe = t.soci.enumerated().map { i, x in
                ["\(i + 1)", x.callsign, x.nome ?? "", x.eta.map { "\($0)" } ?? "", x.junior ? "sì" : "", x.quota ? "pagata" : "no",
                 x.figt ? "sì" : "no", x.intranet ? "sì" : "no", x.numero ?? "", dataIta(x.certificato)]
            }
            s.tabella(["N°", "Callsign", "Nome e cognome", "Età", "Junior", "Quota", "Tesserato", "Assicurato", "N. tessera", "Certificato"], righe,
                      larghezze: [3, 8, 18, 4, 5, 6, 7, 7, 9, 9])
        }
    }

    static func registro(_ r: JRegistro, intest: JIntestazione, loghi: [String: UIImage]) -> Data {
        ScrittorePDF.crea(orizzontale: true, intest: intest, loghi: loghi) { s in
            s.titolo("REGISTRO PRESENZE – ANNO \(r.anno)", 13, dopo: 10)
            let gruppo = 16
            var inizio = 0
            repeat {
                let fine = min(inizio + gruppo, r.colonne.count)
                let col = Array(r.colonne[inizio..<fine])
                let teste = ["Socio"] + col.map { c in (c.data.map { String(dataIta($0).prefix(5)) } ?? "") + "\n" + String(c.titolo.prefix(14)) } + (fine == r.colonne.count ? ["Tot."] : [])
                let righe = r.soci.map { x -> [String] in
                    var celle = [x.callsign]
                    for i in inizio..<fine { celle.append(i < x.celle.count ? (x.celle[i] ?? "") : "") }
                    if fine == r.colonne.count { celle.append("\(x.presenze)/\(x.su)") }
                    return celle
                }
                var larg: [CGFloat] = [9] + Array(repeating: 5, count: col.count)
                if fine == r.colonne.count { larg.append(5) }
                s.tabella(teste, righe, larghezze: larg, size: 7.5)
                inizio = fine
                if inizio < r.colonne.count { s.pagina() }
            } while inizio < r.colonne.count
            if r.colonne.isEmpty { s.paragrafo(Testo.t("Nessun evento nell'anno.")) }
        }
    }

    static func rendiconto(_ r: JRendiconto, firma: UIImage?, intest: JIntestazione, loghi: [String: UIImage]) -> Data {
        ScrittorePDF.crea(intest: intest, loghi: loghi) { s in
            s.titolo("RENDICONTO ECONOMICO-FINANZIARIO – ESERCIZIO \(r.anno)", 13, dopo: 6)
            s.paragrafo(Testo.t("Rendiconto per cassa: entrate e uscite effettivamente incassate e pagate nell'anno.", corsivo: true, size: 10, allinea: .center), dopo: 10)
            s.titolo("ENTRATE", dopo: 4)
            s.tabella(["Voce", "Importo (€)"], r.entrate.map { [$0.voce, euroTesto($0.totale)] } + [["TOTALE ENTRATE", euroTesto(r.totale_entrate)]], larghezze: [5, 2], size: 10)
            s.titolo("USCITE", dopo: 4)
            s.tabella(["Voce", "Importo (€)"], r.uscite.map { [$0.voce, euroTesto($0.totale)] } + [["TOTALE USCITE", euroTesto(r.totale_uscite)]], larghezze: [5, 2], size: 10)
            s.titolo("RIEPILOGO", dopo: 4)
            var rie: [[String]] = [["Saldo iniziale (1° gennaio)", euroTesto(r.saldo_iniziale)], ["Totale entrate", euroTesto(r.totale_entrate)],
                                   ["Totale uscite", euroTesto(r.totale_uscite)], [r.avanzo >= 0 ? "Avanzo di gestione" : "Disavanzo di gestione", euroTesto(r.avanzo)],
                                   ["Saldo finale (31 dicembre)", euroTesto(r.saldo_finale)]]
            for (k, v) in (r.saldi_conti ?? [:]).sorted(by: { $0.key < $1.key }) { rie.append(["   di cui \(k)", euroTesto(v)]) }
            s.tabella(["", "€"], rie, larghezze: [5, 2], size: 10)
            s.paragrafo(Testo.t("Il presente rendiconto è sottoposto all'approvazione dell'Assemblea dei soci.", corsivo: true, size: 10), dopo: 16)
            let y0 = s.y
            s.firma("Il Tesoriere", nil, x: s.m, larghezza: 200, avanza: false)
            s.y = y0
            s.firma("Il Presidente", firma, larghezza: 200)
        }
    }

    static func attestato(nome: String, callsign: String, nascita: String?, luogo: String?, anno: Int, quotaPagata: Bool,
                          firma: UIImage?, intest: JIntestazione, loghi: [String: UIImage]) -> Data {
        ScrittorePDF.crea(intest: intest, loghi: loghi) { s in
            s.spazio(30)
            s.titolo("ATTESTATO DI ISCRIZIONE", 16, dopo: 24)
            var parti: [NSAttributedString] = [Testo.t("Si attesta che "), Testo.v(nome), Testo.t(" (\(callsign))")]
            if let l = luogo, !l.isEmpty { parti += [Testo.t(", nato a "), Testo.v(l)] }
            if let n = nascita, !n.isEmpty { parti += [Testo.t(" il "), Testo.v(dataIta(n))] }
            parti.append(Testo.t(", è socio della \(intest.n) per l'anno associativo \(anno)" + (quotaPagata ? ", in regola con il versamento della quota sociale." : ".")))
            s.paragrafo(Testo.unisci(parti), dopo: 14)
            s.paragrafo(Testo.t("Si rilascia su richiesta dell'interessato per gli usi consentiti dalla legge."), dopo: 30)
            s.paragrafo(Testo.unisci([Testo.t("\((intest.citta ?? "").isEmpty ? "" : (intest.citta ?? "") + ", ")"), Testo.v(dataIta(oggiISO()))]), dopo: 10)
            s.firma("Il Presidente", firma)
        }
    }
}

// MARK: - Firma col dito

struct FirmaPad: View {
    @Binding var tratti: [[CGPoint]]
    @State private var nuovo = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.white)
            Canvas { ctx, _ in
                for t in tratti where t.count > 1 {
                    var p = Path(); p.addLines(t)
                    ctx.stroke(p, with: .color(.black), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                }
            }
            if tratti.isEmpty {
                Text("Firma qui col dito").font(.system(size: 15, weight: .semibold)).foregroundStyle(.gray)
            }
            VStack { Spacer(); Rectangle().fill(Color.gray.opacity(0.5)).frame(height: 1).padding(.horizontal, 24).padding(.bottom, 26) }
                .allowsHitTesting(false)
        }
        .frame(height: 170)
        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
            if nuovo { tratti.append([v.location]); nuovo = false } else if !tratti.isEmpty { tratti[tratti.count - 1].append(v.location) }
        }.onEnded { _ in nuovo = true })
        .overlay(alignment: .topTrailing) {
            if !tratti.isEmpty {
                Button { tratti = [] } label: { Image(systemName: "arrow.counterclockwise.circle.fill").font(.title2).foregroundStyle(.gray) }.padding(6)
            }
        }
    }

    /// immagine ritagliata della firma (nero su trasparente)
    static func immagine(_ tratti: [[CGPoint]]) -> UIImage? {
        let punti = tratti.flatMap { $0 }
        guard punti.count > 3, let minX = punti.map(\.x).min(), let maxX = punti.map(\.x).max(),
              let minY = punti.map(\.y).min(), let maxY = punti.map(\.y).max() else { return nil }
        let r = CGRect(x: minX - 8, y: minY - 8, width: maxX - minX + 16, height: maxY - minY + 16)
        let f = UIGraphicsImageRendererFormat(); f.scale = 3; f.opaque = false
        return UIGraphicsImageRenderer(size: r.size, format: f).image { c in
            c.cgContext.setStrokeColor(UIColor.black.cgColor)
            c.cgContext.setLineWidth(2.6); c.cgContext.setLineCap(.round); c.cgContext.setLineJoin(.round)
            for t in tratti where t.count > 1 {
                c.cgContext.move(to: CGPoint(x: t[0].x - r.minX, y: t[0].y - r.minY))
                for p in t.dropFirst() { c.cgContext.addLine(to: CGPoint(x: p.x - r.minX, y: p.y - r.minY)) }
                c.cgContext.strokePath()
            }
        }
    }
}

// MARK: - Anteprima PDF con condivisione

struct VistaPDF: UIViewRepresentable {
    let dati: Data
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.backgroundColor = UIColor(white: 0.12, alpha: 1)
        v.document = PDFDocument(data: dati)
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {}
}

struct DocumentoPronto: Identifiable {
    let id = UUID()
    let titolo: String
    let dati: Data
    var salva: (() async throws -> Void)? = nil
}

struct AnteprimaPDF: View {
    let doc: DocumentoPronto
    @Environment(\.dismiss) var dismiss
    @State private var esito: String?

    var file: URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(doc.titolo.replacingOccurrences(of: "/", with: "-") + ".pdf")
        try? doc.dati.write(to: u)
        return u
    }

    var body: some View {
        NavigationStack {
            VistaPDF(dati: doc.dati)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(doc.titolo).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } }
                    ToolbarItemGroup(placement: .primaryAction) {
                        if let salva = doc.salva {
                            Button {
                                Task {
                                    do { try await salva(); esito = "Salvato nei documenti dell'associazione" }
                                    catch { esito = error.localizedDescription }
                                }
                            } label: { Image(systemName: "tray.and.arrow.down.fill") }
                        }
                        ShareLink(item: file) { Image(systemName: "square.and.arrow.up") }
                    }
                }
                .overlay(alignment: .bottom) {
                    if let esito {
                        Text(esito).font(.system(size: 13, weight: .bold)).foregroundStyle(.black)
                            .padding(.horizontal, 14).padding(.vertical, 8).background(Theme.olive, in: Capsule()).padding(.bottom, 30)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.35), value: esito)
        }
    }
}
