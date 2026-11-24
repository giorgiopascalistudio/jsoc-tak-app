import SwiftUI
import PhotosUI

// MARK: - Associazione (BAS J.S.O.C. · FIGT · CIPB): cariche, tesseramento, aspiranti, fondo cassa,
// registro presenze, assemblee, avvisi con conferma. Ogni carica vede e fa solo la sua parte.

// MARK: Permessi

struct JPermessi: Codable { let carica: String; let stato_socio: String; let direttivo: Bool; let aree: [String] }

@MainActor
final class PermessiStore: ObservableObject {
    static let shared = PermessiStore()
    @Published private(set) var p: JPermessi?
    init() {
        if let d = UserDefaults.standard.data(forKey: "jsoc.permessi") { p = try? JSONDecoder().decode(JPermessi.self, from: d) }
    }
    func puo(_ area: String) -> Bool { p?.aree.contains(area) ?? (JsocClient.shared.utente?.direttivo == true) }
    var gestione: Bool { p?.direttivo == true || !(p?.aree.isEmpty ?? true) }
    var aspirante: Bool { p?.stato_socio == "aspirante" }
    func aggiorna() async {
        guard JsocClient.shared.collegato, let n: JPermessi = try? await JsocClient.shared.get("/api/io/permessi") else { return }
        p = n
        if let d = try? JSONEncoder().encode(n) { UserDefaults.standard.set(d, forKey: "jsoc.permessi") }
    }
}

// MARK: Modelli

struct JLettura: Codable { let callsign: String; let letto: Bool; let ts: Double? }
struct JDaFare: Codable, Identifiable { var id: String { tipo + titolo }; let tipo: String; let livello: String; let titolo: String; let testo: String; let azione: String; let post: Int? }

struct JSocioCarica: Codable, Identifiable { let id: Int; let callsign: String; let nome: String?; let ruolo: String; let carica: String?; let stato_socio: String? }
struct JStoricoMod: Codable, Identifiable { var id: Double { ts }; let ts: Double; let callsign: String?; let azione: String; let dettagli: String? }
struct JCariche: Codable { let nomi: [String]; let soci: [JSocioCarica]; let storico: [JStoricoMod] }

struct JTesserato: Codable, Identifiable {
    var id: Int { utente }
    let utente: Int; let callsign: String; let nome: String?; let stato_socio: String?; let carica: String?
    let eta: Int?; let junior: Bool; let quota: Bool; let quota_importo: Double?; let figt: Bool; let intranet: Bool
    let numero: String?; let rinnova: Bool; let note: String?; let certificato: String?; let giorni_certificato: Int?
}
struct JAffiliazione: Codable { var tipo: String; var stato: String; var data: String?; var note: String? }
struct JTesseramento: Codable { let anno: Int; let soci: [JTesserato]; let affiliazione: JAffiliazione; let obbligatori: [String]; let gestisci: Bool }

struct JUscitaProva: Codable, Hashable, Identifiable {
    var id = UUID(); var data = ""; var titolo = ""; var tutor = ""; var note = ""
    enum CodingKeys: String, CodingKey { case data, titolo, tutor, note }
}
struct JEventoBreve: Codable, Hashable { let id: Int; let nome: String; let inizio: String? }
struct JAspirante: Codable, Identifiable {
    let id: Int; let callsign: String; let nome: String?; let nascita: String?; let creato: Double?
    var documenti: [String: Bool]; var uscite: [JUscitaProva]; let presenze_eventi: [JEventoBreve]; var note: String; let stato: String; let eta: Int?
}
struct JAspiranti: Codable { let aspiranti: [JAspirante]; let uscite_richieste: Int; let documenti: [String] }

struct JSocioLibro: Codable, Identifiable {
    let id: Int; let callsign: String; let nome: String?; let ruolo: String; let carica: String?; let stato_socio: String?
    let ammesso: String?; let uscito: String?; let uscita_motivo: String?; let creato: Double?; let attivo: Int; let telefono: String?; let email: String?
}

struct JMov2: Codable, Identifiable, Hashable {
    let id: Int; let data: String; let tipo: String; let categoria: String?; let importo: Double; let descrizione: String?
    let utente: Int?; let ricevuta: String?; let conto: String?; let conto_a: String?; let natura: String?; let evento: Int?
    let numero: String?; let modificato: Double?; let importato: Int?; let destinazione: String?
    let callsign: String?; let autore_cs: String?; let evento_nome: String?
    var segno: Double { tipo == "entrata" ? importo : tipo == "uscita" ? -importo : 0 }
}
struct JCategoriaTot: Codable, Hashable { let tipo: String; let categoria: String; let totale: Double }
struct JBudget: Codable, Hashable { let categoria: String; let importo: Double; let speso: Double }
struct JCassa2: Codable {
    let anno: Int; let anni: [String]; let movimenti: [JMov2]; let saldi: [String: Double]; let disponibile: Double
    let entrate: Double; let uscite: Double; let categorie: [JCategoriaTot]; let budget: [JBudget]; let da_incassare: Double
    let destinati: [String: Double]; let conti: [String]; let soglia_ok: Double?
}
struct JVoce: Codable, Hashable { let voce: String; let totale: Double }
struct JRendiconto: Codable {
    let anno: Int; let anni: [String]; let entrate: [JVoce]; let uscite: [JVoce]; let totale_entrate: Double; let totale_uscite: Double
    let avanzo: Double; let saldo_iniziale: Double; let saldo_finale: Double; let saldi_conti: [String: Double]?
}
struct JColonnaRegistro: Codable, Hashable { let data: String?; let titolo: String; let evento: Int?; var tipo: String? = nil; var annullato: Bool? = nil }
struct JRigaRegistro: Codable, Hashable { let callsign: String; let celle: [String?]; let presenze: Int; let su: Int }
struct JRegistro: Codable { let anno: Int; let anni: [String]; let colonne: [JColonnaRegistro]; let soci: [JRigaRegistro]; let gestisci: Bool }
struct JAppello: Codable, Identifiable { let id: Int; let callsign: String; let nome: String?; let risposta: String?; let presente: Int? }

struct JConteggio: Codable, Hashable { let si: Int; let no: Int; let astenuto: Int }
struct JNominativo: Codable, Hashable { let callsign: String; let voto: String }
struct JPuntoOdg: Codable, Hashable {
    let titolo: String; let voto: Bool; let segreto: Bool; let stato: String; let esito: String
    let conteggio: JConteggio?; let votanti: Int?; let mio_voto: String?; let nominativi: [JNominativo]?
}
struct JPresenzaAss: Codable, Hashable { let utente: Int; let stato: String; let delegato: Int?; let callsign: String; let delegato_cs: String? }
struct JAssemblea: Codable, Identifiable {
    let id: Int; let titolo: String; let tipo: String; let data: String?; let luogo: String?; let odg: [JPuntoOdg]; let stato: String
    let verbale: String?; let aventi_diritto: Int; let presenti: Int; let deleghe: Int; let quorum: Int; let numero_legale: Bool
    let lista: [JPresenzaAss]; let mia: JPresenzaAss?; let miei_deleganti: [String]; let gestisci: Bool; let posso_votare: Bool
}

extension JsocClient {
    func letture(_ post: Int) async throws -> [JLettura] { try await get("/api/bacheca/\(post)/letture") }
    func daFare() async throws -> [JDaFare] { try await get("/api/da-fare") }
    func cariche() async throws -> JCariche { try await get("/api/cariche") }
    func assegnaCarica(_ u: Int, _ c: String) async throws -> JCariche { try await send("/api/utenti/\(u)/carica", "PUT", ["carica": c]) }
    func tesseramento(_ anno: Int) async throws -> JTesseramento { try await get("/api/tesseramento?anno=\(anno)") }
    func salvaTesseramento(_ c: [String: Any]) async throws -> JTesseramento { try await send("/api/tesseramento", "POST", c) }
    func salvaAffiliazione(_ c: [String: Any]) async throws -> JTesseramento { try await send("/api/tesseramento/affiliazione", "POST", c) }
    func aspiranti() async throws -> JAspiranti { try await get("/api/aspiranti") }
    func salvaAspirante(_ id: Int, _ c: [String: Any]) async throws -> JAspiranti { try await send("/api/aspiranti/\(id)", "PUT", c) }
    func esitoAspirante(_ id: Int, ammesso: Bool) async throws -> JAspiranti { try await send("/api/aspiranti/\(id)/esito", "POST", ["ammesso": ammesso]) }
    func libroSoci() async throws -> [JSocioLibro] { try await get("/api/libro-soci") }
    func uscitaSocio(_ id: Int, motivo: String) async throws -> [JSocioLibro] { try await send("/api/utenti/\(id)/uscita", "POST", ["motivo": motivo]) }
    func cassa2(_ anno: Int) async throws -> JCassa2 { try await get("/api/cassa2?anno=\(anno)") }
    func nuovoMovimento2(_ c: [String: Any]) async throws -> JMov2 { try await send("/api/cassa2", "POST", c) }
    func modificaMovimento(_ id: Int, _ c: [String: Any]) async throws -> JMov2 { try await send("/api/cassa2/\(id)", "PUT", c) }
    func cancellaMovimento2(_ id: Int) async throws { let _: JOk = try await send("/api/cassa2/\(id)", "DELETE", [String: String]()) }
    func salvaBudget(_ anno: Int, _ voci: [String: Double]) async throws -> JCassa2 { try await send("/api/cassa2/budget", "POST", ["anno": anno, "voci": voci]) }
    func rendiconto(_ anno: Int) async throws -> JRendiconto { try await get("/api/rendiconto?anno=\(anno)") }
    func storicoModifiche() async throws -> [JStoricoMod] { try await get("/api/registro-modifiche?area=cassa") }
    func registroPresenze(_ anno: Int) async throws -> JRegistro { try await get("/api/registro-presenze?anno=\(anno)") }
    func appelloEvento(_ ev: Int) async throws -> [JAppello] { try await get("/api/eventi/\(ev)/appello") }
    func segnaAppello(_ ev: Int, _ u: Int, _ p: Bool?) async throws { let _: JOk = try await send("/api/eventi/\(ev)/appello", "POST", ["utente": u, "presente": p.map { $0 as Any } ?? NSNull()]) }
    func assemblee() async throws -> [JAssemblea] { try await get("/api/assemblee") }
    func nuovaAssemblea(_ c: [String: Any]) async throws -> JAssemblea { try await send("/api/assemblee", "POST", c) }
    func presenzaAssemblea(_ id: Int, _ c: [String: Any]) async throws -> JAssemblea { try await send("/api/assemblee/\(id)/presenza", "POST", c) }
    func puntoAssemblea(_ id: Int, _ i: Int, stato: String) async throws -> JAssemblea { try await send("/api/assemblee/\(id)/punti/\(i)", "POST", ["stato": stato]) }
    func votaAssemblea(_ id: Int, _ i: Int, _ v: String) async throws -> JAssemblea { try await send("/api/assemblee/\(id)/punti/\(i)/voto", "POST", ["voto": v]) }
    func chiudiAssemblea(_ id: Int) async throws -> JAssemblea { try await send("/api/assemblee/\(id)/chiudi", "POST", [String: String]()) }
}

enum NomiAssoc {
    static let cariche: [(String, String, String)] = [
        ("presidente", "Presidente", "tutto · cariche · ammissioni · firma"),
        ("vicepresidente", "Vicepresidente", "come il Presidente, tranne le cariche"),
        ("segretario", "Segretario", "libro soci · tesseramento FIGT · aspiranti · verbali"),
        ("tesoriere", "Tesoriere", "fondo cassa · quote · rimborsi · rendiconto"),
        ("consigliere", "Consigliere", "avvisi · assemblee · aspiranti · registro"),
        ("magazzino", "Resp. magazzino", "materiale · prestiti · danni"),
        ("istruttore", "Istruttore", "allenamenti · presenze · tutor degli aspiranti"),
    ]
    static func carica(_ k: String?) -> String { cariche.first { $0.0 == k }?.1 ?? "Socio" }
    static let conti: [String: String] = ["cassa": "Contanti", "banca": "Banca", "paypal": "PayPal"]
    static func conto(_ k: String?) -> String { conti[k ?? "cassa"] ?? (k ?? "Contanti").capitalized }
    static let categorieEntrata = ["quote associative", "tesseramenti e polizze", "prove", "pallini", "gare e tornei", "abbigliamento e patch", "donazioni ed erogazioni liberali", "sponsorizzazioni", "5x1000", "contributi pubblici", "contributi soci per eventi", "altro"]
    static let categorieUscita = ["affiliazione", "tesseramenti e polizze", "campo e manutenzione", "gare e tornei", "iscrizioni gare", "materiale", "pallini", "rimborsi", "abbigliamento e patch", "eventi e logistica", "trasporti", "banca e oneri", "altro"]
    static let documenti: [(String, String)] = [
        ("domanda", "Domanda d'iscrizione firmata"), ("documento", "Documento e codice fiscale"), ("privacy", "Consenso privacy"),
        ("scarico", "Scarico di responsabilità"), ("certificato", "Certificato medico non agonistico"), ("immagini", "Consenso foto e video"),
    ]
}

func euroIT(_ v: Double) -> String {
    let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = Locale(identifier: "it_IT")
    f.minimumFractionDigits = 2; f.maximumFractionDigits = 2
    return (f.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)) + " €"
}

private struct Pillola: View {
    let testo: String; let colore: Color
    var body: some View {
        Text(testo).font(.system(size: 10, weight: .heavy)).foregroundStyle(.black)
            .padding(.horizontal, 8).padding(.vertical, 3).background(colore, in: Capsule())
    }
}

private struct SelettoreAnno: View {
    @Binding var anno: Int
    var anni: [Int] = []
    var body: some View {
        let lista = Array(Set(anni + [Calendar.current.component(.year, from: Date()), anno])).sorted(by: >)
        Picker("Anno", selection: $anno) { ForEach(lista, id: \.self) { Text(String($0)).tag($0) } }
            .pickerStyle(.menu).tint(Theme.olive)
    }
}

// MARK: - Schermata principale

struct AssociazioneHomeV2: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var home = HomeModel.shared
    @ObservedObject private var perm = PermessiStore.shared
    @State private var mia: JTesserato?
    @State private var anno = Calendar.current.component(.year, from: Date())
    @State private var avviso: JPost?
    @State private var assemblea: JAssemblea?
    @State private var daFare: [JDaFare] = []
    @State private var delega = false
    @State private var soci: [JSocioLibro] = []

    var body: some View {
        let _ = Contatori.disegno("AssociazioneHomeV2")
        ScrollView {
            VStack(spacing: 12) {
                testata.comparsa(0)
                tessera.comparsa(1)
                if let a = avviso { avvisoCard(a).comparsa(2).transition(.move(edge: .trailing).combined(with: .opacity)) }
                if let a = assemblea, a.stato != "chiusa" { assembleaCard(a).comparsa(3) }
                griglia
                if perm.gestione { gestione.comparsa(14) }
            }
            .padding(14)
            .padding(.bottom, 70)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .refreshable { await carica() }
        .task { await carica() }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: avviso?.id)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: daFare.count)
        .sheet(isPresented: $delega) {
            if let a = assemblea { DelegaSheet(assemblea: a, soci: soci) { assemblea = $0 } }
        }
    }

    var testata: some View {
        HStack(spacing: 12) {
            Image("Stemma").resizable().scaledToFit().frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Associazione").font(.title2.weight(.heavy))
                Text("BAS J.S.O.C. · FIGT · Comitato Puglia e Basilicata").font(.caption).foregroundStyle(Theme.dim)
            }
            Spacer()
            if let c = perm.p?.carica, !c.isEmpty { Pillola(testo: NomiAssoc.carica(c).uppercased(), colore: Theme.olive) }
            else if perm.aspirante { Pillola(testo: "ASPIRANTE", colore: Theme.amber) }
        }
    }

    var tessera: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TESSERA FIGT \(String(anno))").font(.system(size: 11, weight: .heavy)).tracking(1.2).foregroundStyle(Theme.oliveBright)
                Spacer()
                if let m = mia {
                    Pillola(testo: m.intranet ? "ASSICURATO" : m.figt ? "IN ATTESA DI CARICAMENTO" : "NON TESSERATO",
                            colore: m.intranet ? Theme.oliveBright : m.figt ? Theme.amber : Theme.red)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(jsoc.utente?.callsign ?? "—").font(.system(size: 24, weight: .heavy))
                if let n = mia?.numero, !n.isEmpty { Text("n. \(n)").font(Theme.mono(13)).foregroundStyle(Theme.dim) }
            }
            HStack(spacing: 8) {
                riquadro("CERTIFICATO MEDICO", certificato, (mia?.giorni_certificato ?? 99) < 30 ? Theme.amber : Theme.oliveBright)
                riquadro("QUOTA \(String(anno))", mia?.quota == true ? "pagata" : "da pagare", mia?.quota == true ? Theme.oliveBright : Theme.amber)
            }
        }
        .padding(14)
        .background(LinearGradient(colors: [Theme.oliveDeep, Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.olive.opacity(0.4)))
    }

    var certificato: String {
        guard let g = mia?.giorni_certificato else { return "non registrato" }
        return g < 0 ? "scaduto" : g == 0 ? "scade oggi" : "scade tra \(g) gg"
    }

    func riquadro(_ t: String, _ v: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.system(size: 9.5, weight: .bold)).foregroundStyle(Theme.dim)
            Text(v).font(.system(size: 13, weight: .heavy)).foregroundStyle(c)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10).background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }

    func avvisoCard(_ p: JPost) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "megaphone.fill").foregroundStyle(Theme.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.titolo?.isEmpty == false ? p.titolo! : "Avviso del direttivo").font(.subheadline.weight(.bold)).lineLimit(1)
                Text("serve la tua conferma").font(.caption).foregroundStyle(Theme.dim)
            }
            Spacer()
            Button("Ho letto") {
                Task { await jsoc.letto(p.id); avviso = nil; await home.aggiorna() }
            }
            .buttonStyle(.borderedProminent).tint(Theme.amber).foregroundStyle(.black)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.amber.opacity(0.6)))
    }

    func assembleaCard(_ a: JAssemblea) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ASSEMBLEA \(a.tipo.uppercased())").font(.system(size: 11, weight: .heavy)).tracking(1.2).foregroundStyle(Theme.dim)
                Spacer()
                Text(a.data ?? "").font(Theme.mono(12, .bold)).foregroundStyle(Theme.oliveBright)
            }
            Text(a.odg.map(\.titolo).joined(separator: " · ")).font(.subheadline).lineLimit(2)
            if let m = a.mia {
                Label(m.stato == "presente" ? "Ci sarai" : m.stato == "delega" ? "Hai delegato \(m.delegato_cs ?? "")" : "Hai detto che non ci sarai",
                      systemImage: "checkmark.circle").font(.caption.weight(.bold)).foregroundStyle(Theme.oliveBright)
            }
            HStack(spacing: 8) {
                Button { Task { assemblea = try? await jsoc.presenzaAssemblea(a.id, ["stato": "presente"]) } } label: { Text("Ci sarò").frame(maxWidth: .infinity) }
                    .buttonStyle(PrimaryButtonStyle())
                Button { Task { soci = (try? await jsoc.libroSoci()) ?? []; delega = true } } label: { Text("Delego un socio").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).tint(Theme.olive)
            }
            NavigationLink { AssembleaView(id: a.id) } label: { Label("Apri l'assemblea", systemImage: "chevron.right").font(.caption) }
                .tint(Theme.dim)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.stroke))
    }

    var griglia: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
            voce("newspaper.fill", "Bacheca", conta(home.dati?.post_nuovi, "nuovi")) { BachecaSociView() }.comparsa(4)
            voce("person.2.fill", "Soci", "rubrica") { SociView() }.comparsa(5)
            voce("chart.bar.fill", "Sondaggi", conta(home.dati?.sondaggi_aperti, "da votare")) { SondaggiView() }.comparsa(6)
            voce("building.columns.fill", "Assemblee", "convocazioni, voti") { AssembleeView() }.comparsa(7)
            voce("shippingbox.fill", "Magazzino", "materiale e prestiti") { MagazzinoView() }.comparsa(8)
            voce("doc.text.fill", "Documenti", "statuto, verbali, moduli") { DocumentiAssociazioneView() }.comparsa(9)
            voce("checklist", "Presenze", "registro") { RegistroPresenzeView() }.comparsa(10)
            voce("eurosign.circle.fill", "Rendiconto", "conti dell'anno") { RendicontoView() }.comparsa(11)
            voce("calendar", "Calendario", "eventi e presenze") { CalendarioView() }.comparsa(12)
            voce("signature", "Iscrizione", "domanda firmata") { DomandaIscrizioneView() }.comparsa(13)
            voce("magnifyingglass.circle.fill", "FIGT", "regolamenti, polizze: cerca") { DocumentiFIGTView() }.comparsa(13)
            voce("calendar.badge.clock", "Scadenze", "certificato, quota") { ScadenzarioView() }.comparsa(14)
            voce("doc.plaintext.fill", "Ricevute", perm.puo("cassa") ? "emetti e archivia" : "le tue ricevute") { RicevuteView() }.comparsa(15)
            voce("shield.lefthalf.filled", "Assicurazione", "polizza e infortuni") { AssicurazioneView() }.comparsa(16)
            voce("arrow.left.arrow.right.square.fill", "Prestiti", perm.puo("magazzino") ? "materiale ai soci" : "materiale che hai") { PrestitiView() }.comparsa(17)
        }
    }

    var gestione: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GESTIONE").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.dim).padding(.top, 6)
            NavigationLink { DaFareView() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "checklist.checked").font(.title3).foregroundStyle(Theme.amber)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Da fare").font(.headline).foregroundStyle(.white)
                        Text(daFare.isEmpty ? "tutto in ordine" : daFare.prefix(2).map(\.titolo).joined(separator: " · ")).font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                    }
                    Spacer()
                    if !daFare.isEmpty { Text("\(daFare.count)").font(Theme.mono(14, .heavy)).foregroundStyle(.black).padding(.horizontal, 9).padding(.vertical, 3).background(Theme.amber, in: Capsule()) }
                }
                .padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.amber.opacity(0.4)))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                if perm.puo("tesseramento") { voce("person.text.rectangle.fill", "Tesseramento", "FIGT e assicurazione") { TesseramentoView() } }
                if perm.puo("aspiranti") { voce("person.badge.clock.fill", "Aspiranti", "domande e prove") { AspirantiView() } }
                if perm.puo("cassa") { voce("banknote.fill", "Fondo cassa", "conti, movimenti, budget") { CassaV2View() } }
                if perm.puo("soci") { voce("books.vertical.fill", "Libro soci", "ammissioni e uscite") { LibroSociView() } }
                voce("person.3.sequence.fill", "Cariche", "chi fa cosa") { CaricheView() }
                if perm.puo("soci") { voce("person.3.fill", "Gruppi", "squadre e sottogruppi") { GruppiView() } }
                if perm.puo("aspiranti") || perm.puo("soci") { voce("person.badge.plus", "Domande", "iscrizioni da valutare") { DomandeView() } }
                if perm.gestione { voce("building.2.fill", "Direttivo", "riunioni e verbali") { RiunioniView() } }
                if perm.puo("documenti") { voce("printer.fill", "Stampe", "registri, rendiconto, attestati") { StampeView() } }
                if perm.puo("documenti") { voce("seal.fill", "Dati associazione", "carta intestata, firma") { IntestazioneView() } }
            }
        }
    }

    func conta(_ n: Int?, _ t: String) -> String { (n ?? 0) > 0 ? "\(n!) \(t)" : "tutto letto" }

    func voce<D: View>(_ icona: String, _ titolo: String, _ sotto: String, @ViewBuilder dest: @escaping () -> D) -> some View {
        NavigationLink { dest() } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icona).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.olive)
                Text(titolo).font(.system(size: 14, weight: .heavy)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
                Text(sotto).font(.system(size: 10.5)).foregroundStyle(Theme.dim).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 0.75))
        }
        .buttonStyle(PressStyle())
    }

    func carica() async {
        await perm.aggiorna()
        await home.aggiorna()
        if let t = try? await jsoc.tesseramento(anno) { mia = t.soci.first { $0.utente == jsoc.utente?.id } }
        if let b = try? await jsoc.bacheca() { avviso = b.first { $0.chiedeConferma && !$0.letto } }
        if let a = try? await jsoc.assemblee() { assemblea = a.first { $0.stato != "chiusa" } }
        if perm.gestione { daFare = (try? await jsoc.daFare()) ?? [] }
    }
}

struct DelegaSheet: View {
    let assemblea: JAssemblea
    let soci: [JSocioLibro]
    var fatto: (JAssemblea) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var errore: String?
    var body: some View {
        NavigationStack {
            List {
                if let errore { Text(errore).foregroundStyle(Theme.red) }
                Section { Text("Il socio che scegli voterà anche per te. Ognuno può avere al massimo 2 deleghe.").font(.footnote).foregroundStyle(Theme.dim) }
                ForEach(soci.filter { $0.attivo == 1 && $0.id != JsocClient.shared.utente?.id && ($0.stato_socio ?? "socio") == "socio" }) { s in
                    Button {
                        Task {
                            do { fatto(try await JsocClient.shared.presenzaAssemblea(assemblea.id, ["stato": "delega", "delegato": s.id])); dismiss() }
                            catch { errore = error.localizedDescription }
                        }
                    } label: { HStack { Text(s.callsign).font(Theme.mono(15, .bold)).foregroundStyle(.white); Text(s.nome ?? "").foregroundStyle(Theme.dim) } }
                }
            }
            .listaJSOC().navigationTitle("Delega").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } } }
        }
    }
}

// MARK: - Da fare

struct DaFareView: View {
    @State private var voci: [JDaFare] = []
    @State private var caricato = false
    var body: some View {
        List {
            if caricato && voci.isEmpty { Label("Tutto in ordine", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.olive) }
            ForEach(["urgente", "attenzione", "richiesta", "info"], id: \.self) { liv in
                let v = voci.filter { $0.livello == liv }
                if !v.isEmpty {
                    Section(liv == "urgente" ? "Urgente" : liv == "attenzione" ? "Scadenze e mancanze" : liv == "richiesta" ? "Da approvare" : "Da tenere d'occhio") {
                        ForEach(v) { x in
                            NavigationLink { destinazione(x) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(x.titolo).font(.headline).foregroundStyle(liv == "urgente" ? Theme.red : .white)
                                    if !x.testo.isEmpty { Text(x.testo).font(.caption).foregroundStyle(Theme.dim) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .listaJSOC().navigationTitle("Da fare")
        .task { voci = (try? await JsocClient.shared.daFare()) ?? []; caricato = true }
        .refreshable { voci = (try? await JsocClient.shared.daFare()) ?? [] }
    }

    @ViewBuilder func destinazione(_ x: JDaFare) -> some View {
        switch x.azione {
        case "tesseramento": TesseramentoView()
        case "aspiranti": AspirantiView()
        case "soci": TesseramentoView()
        case "bacheca": BachecaSociView()
        default:
            VStack(spacing: 14) {
                Text(x.titolo).font(.headline)
                Button { vaiAllaScheda(Schede.eventi) } label: { Label("Vai agli Eventi", systemImage: "calendar") }.buttonStyle(PrimaryButtonStyle())
            }
            .padding(30)
        }
    }
}

// MARK: - Tesseramento FIGT e assicurazione

struct TesseramentoView: View {
    @State private var anno = Calendar.current.component(.year, from: Date())
    @State private var t: JTesseramento?
    @State private var errore: String?
    @State private var modifica: JTesserato?
    @State private var affiliazione = false
    @State private var csv: URL?

    var body: some View {
        let _ = GuidaApp.segna("tesseramento")
        List {
            if let errore { Text(errore).foregroundStyle(Theme.red) }
            Section { SelettoreAnno(anno: $anno) }
            if let t {
                Section("Affiliazione FIGT · CIPB") {
                    Button { affiliazione = true } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(t.affiliazione.tipo).font(.headline).foregroundStyle(.white)
                                Text(t.obbligatori.isEmpty ? "Assegna Presidente, Vice e Segretario: vanno tesserati" : "Tesserati obbligatori: " + t.obbligatori.joined(separator: ", "))
                                    .font(.caption).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            Pillola(testo: t.affiliazione.stato.uppercased(), colore: t.affiliazione.stato == "fatta" ? Theme.oliveBright : Theme.amber)
                        }
                    }
                    .disabled(!t.gestisci)
                }
                let ass = t.soci.filter(\.intranet).count, att = t.soci.filter { $0.figt && !$0.intranet }.count
                let paga = t.soci.filter { !$0.figt && $0.rinnova }.count, no = t.soci.filter { !$0.rinnova }.count
                Section {
                    GeometryReader { g in
                        let tot = CGFloat(max(1, t.soci.count))
                        HStack(spacing: 0) {
                            Rectangle().fill(Theme.olive).frame(width: g.size.width * CGFloat(ass) / tot)
                            Rectangle().fill(Theme.amber).frame(width: g.size.width * CGFloat(att) / tot)
                            Rectangle().fill(Theme.red).frame(width: g.size.width * CGFloat(paga) / tot)
                            Rectangle().fill(Theme.surface2)
                        }
                        .clipShape(Capsule())
                    }
                    .frame(height: 10)
                    HStack(spacing: 10) {
                        Text("\(ass) assicurati").foregroundStyle(Theme.oliveBright)
                        Text("\(att) da caricare").foregroundStyle(Theme.amber)
                        Text("\(paga) da tesserare").foregroundStyle(Theme.red)
                        Text("\(no) non rinnovano").foregroundStyle(Theme.dim)
                    }
                    .font(.caption2.weight(.bold))
                } footer: { Text("L'assicurazione FIGT vale solo dopo che i nomi sono caricati nell'Intranet FIGT: per questo “pagata” non basta. Dai 13 ai 17 anni = Junior, con i dati di un genitore.") }
                Section {
                    HStack {
                        Text("SOCIO").frame(maxWidth: .infinity, alignment: .leading)
                        Text("QUOTA").frame(width: 46); Text("FIGT").frame(width: 40); Text("CERT.").frame(width: 50); Text("ASS.").frame(width: 34)
                    }
                    .font(.system(size: 9.5, weight: .heavy)).foregroundStyle(Theme.dim)
                    ForEach(t.soci) { s in
                        Button { if t.gestisci { modifica = s } } label: {
                            HStack {
                                HStack(spacing: 4) {
                                    Text(s.callsign).font(Theme.mono(13, .bold)).foregroundStyle(.white)
                                    if s.junior { Text("JR").font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.amber) }
                                    if s.stato_socio == "aspirante" { Text("ASP").font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.cyan) }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: s.quota ? "checkmark" : "minus").foregroundStyle(s.quota ? Theme.oliveBright : Theme.red).frame(width: 46)
                                Image(systemName: s.figt ? "checkmark" : "minus").foregroundStyle(s.figt ? Theme.oliveBright : Theme.red).frame(width: 40)
                                Text(s.giorni_certificato.map { $0 < 0 ? "scad." : "\($0) gg" } ?? "—").font(.caption2.weight(.bold))
                                    .foregroundStyle((s.giorni_certificato ?? -1) < 30 ? Theme.amber : Theme.oliveBright).frame(width: 50)
                                Text(s.intranet ? "SÌ" : "NO").font(.caption.weight(.heavy)).foregroundStyle(s.intranet ? Theme.oliveBright : Theme.red).frame(width: 34)
                            }
                        }
                    }
                }
                if t.gestisci {
                    Section {
                        let daCaricare = t.soci.filter { $0.figt && !$0.intranet }
                        Button {
                            Task { await salva(["utenti": daCaricare.map(\.utente), "intranet": true]) }
                        } label: { Label("Segna caricati nell'Intranet (\(daCaricare.count))", systemImage: "checkmark.shield.fill") }
                        .disabled(daCaricare.isEmpty)
                        Button { Task { await esporta() } } label: { Label("Esporta elenco per l'Intranet (CSV)", systemImage: "square.and.arrow.up") }
                        if let csv { ShareLink(item: csv) { Label("Condividi il file", systemImage: "doc.text") } }
                    }
                }
            }
        }
        .listaJSOC().navigationTitle("Tesseramento")
        .task(id: anno) { await carica() }
        .refreshable { await carica() }
        .sheet(item: $modifica) { s in TesseratoSheet(anno: anno, s: s) { t = $0 } }
        .sheet(isPresented: $affiliazione) { if let t { AffiliazioneSheet(anno: anno, a: t.affiliazione) { self.t = $0 } } }
    }

    func carica() async {
        do { t = try await JsocClient.shared.tesseramento(anno); errore = nil } catch { errore = error.localizedDescription }
    }
    func salva(_ c: [String: Any]) async {
        var c = c; c["anno"] = anno
        do { t = try await JsocClient.shared.salvaTesseramento(c) } catch { errore = error.localizedDescription }
    }
    func esporta() async {
        do {
            let d = try await JsocClient.shared.scaricaDati("/api/tesseramento/intranet.csv?anno=\(anno)")
            let u = FileManager.default.temporaryDirectory.appendingPathComponent("Intranet FIGT \(anno).csv")
            try d.write(to: u, options: .atomic); csv = u
        } catch { errore = error.localizedDescription }
    }
}

struct TesseratoSheet: View {
    let anno: Int
    let s: JTesserato
    var fatto: (JTesseramento) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var quota = false
    @State private var importo = ""
    @State private var figt = false
    @State private var intranet = false
    @State private var numero = ""
    @State private var rinnova = true
    @State private var note = ""
    @State private var errore: String?

    var body: some View {
        NavigationStack {
            Form {
                Section { LabeledContent("Socio", value: "\(s.callsign) · \(s.nome ?? "")"); if let e = s.eta { LabeledContent("Età", value: "\(e)\(s.junior ? " · Junior" : "")") } }
                Section("Stagione \(String(anno))") {
                    Toggle("Quota sociale pagata", isOn: $quota)
                    if quota && !s.quota { TextField("Importo (€)", text: $importo).keyboardType(.decimalPad) }
                    Toggle("Quota FIGT pagata", isOn: $figt)
                    Toggle("Caricato nell'Intranet FIGT (assicurato)", isOn: $intranet)
                    TextField("Numero tessera FIGT", text: $numero).font(Theme.mono(14))
                    Toggle("Rinnova quest'anno", isOn: $rinnova)
                    TextField("Note", text: $note)
                }
                if quota && !s.quota { Section { Text("Segnando la quota come pagata si registra anche l'entrata nel fondo cassa (contanti).").font(.footnote).foregroundStyle(Theme.dim) } }
                if let errore { Text(errore).foregroundStyle(Theme.red) }
            }
            .navigationTitle(s.callsign).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        var c: [String: Any] = ["anno": anno, "utente": s.utente, "figt": figt, "intranet": intranet, "numero": numero, "rinnova": rinnova, "note": note]
                        if quota != s.quota { c["quota"] = quota }
                        if let v = Double(importo.replacingOccurrences(of: ",", with: ".")) { c["importo"] = v }
                        Task {
                            do { fatto(try await JsocClient.shared.salvaTesseramento(c)); dismiss() } catch { errore = error.localizedDescription }
                        }
                    }
                }
            }
            .onAppear { quota = s.quota; figt = s.figt; intranet = s.intranet; numero = s.numero ?? ""; rinnova = s.rinnova; note = s.note ?? "" }
            .onChange(of: intranet) { if $0 { figt = true } }
        }
    }
}

struct AffiliazioneSheet: View {
    let anno: Int
    @State var a: JAffiliazione
    var fatto: (JTesseramento) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var quotaSociale = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Affiliazione \(String(anno))") {
                    Picker("Tipo", selection: $a.tipo) {
                        Text("Air Soft").tag("Air Soft")
                        Text("Air Soft + tutela legale").tag("Air Soft + tutela legale")
                        Text("Air Soft e Laser Tag").tag("Air Soft e Laser Tag")
                    }
                    Picker("Stato", selection: $a.stato) {
                        Text("Da fare").tag("da fare"); Text("Pagata, in attesa").tag("pagata"); Text("Fatta").tag("fatta")
                    }
                    TextField("Note (es. data bonifico)", text: Binding(get: { a.note ?? "" }, set: { a.note = $0 }))
                }
                Section("Quota sociale") { TextField("Importo standard (€)", text: $quotaSociale).keyboardType(.decimalPad) }
                Section { Text("Per le nuove affiliazioni la FIGT chiede atto costitutivo, statuto, codice fiscale dell'associazione e documento del Presidente. Con la tutela legale serve anche il modulo firmato dal Presidente.").font(.footnote).foregroundStyle(Theme.dim) }
            }
            .navigationTitle("Affiliazione").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        var c: [String: Any] = ["anno": anno, "tipo": a.tipo, "stato": a.stato, "note": a.note ?? ""]
                        if let v = Double(quotaSociale.replacingOccurrences(of: ",", with: ".")) { c["quota_sociale"] = v }
                        Task { if let t = try? await JsocClient.shared.salvaAffiliazione(c) { fatto(t) }; dismiss() }
                    }
                }
            }
        }
    }
}

// MARK: - Aspiranti

struct AspirantiView: View {
    @State private var dati: JAspiranti?
    @State private var invito = false
    @State private var errore: String?
    var body: some View {
        let _ = GuidaApp.segna("aspiranti")
        List {
            if let errore { Text(errore).foregroundStyle(Theme.red) }
            Section {
                Button { invito = true } label: { Label("Invita un aspirante (QR)", systemImage: "qrcode") }
            } footer: { Text("Percorso: domanda → documenti → \(dati?.uscite_richieste ?? 3) uscite di prova con un tutor → voto del direttivo → socio.") }
            if let d = dati {
                if d.aspiranti.isEmpty { Text("Nessun aspirante in prova").foregroundStyle(Theme.dim) }
                ForEach(d.aspiranti) { a in
                    NavigationLink { AspiranteView(a: a, richieste: d.uscite_richieste) { dati = $0 } } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(a.nome ?? a.callsign).font(.headline)
                                Text(a.callsign).font(Theme.mono(12)).foregroundStyle(Theme.dim)
                                Spacer()
                                Pillola(testo: a.stato == "proposto" ? "DA VOTARE" : "IN PROVA", colore: a.stato == "proposto" ? Theme.amber : Theme.cyan)
                            }
                            let docOk = a.documenti.values.filter { $0 }.count
                            let usc = a.uscite.count + a.presenze_eventi.count
                            Text("documenti \(docOk)/\(NomiAssoc.documenti.count) · uscite di prova \(usc)/\(d.uscite_richieste)").font(.caption).foregroundStyle(Theme.dim)
                        }
                    }
                }
            }
        }
        .listaJSOC().navigationTitle("Aspiranti")
        .task { await carica() }
        .refreshable { await carica() }
        .sheet(isPresented: $invito) { InvitoSheet(ruoloIniziale: "aspirante") }
    }
    func carica() async { do { dati = try await JsocClient.shared.aspiranti(); errore = nil } catch { errore = error.localizedDescription } }
}

struct AspiranteView: View {
    @State var a: JAspirante
    let richieste: Int
    var aggiornato: (JAspiranti) -> Void
    @ObservedObject private var perm = PermessiStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var nuova = JUscitaProva()
    @State private var errore: String?
    @State private var conferma: Bool?

    var body: some View {
        Form {
            Section { LabeledContent("Callsign", value: a.callsign); if let e = a.eta { LabeledContent("Età", value: "\(e)\(e < 18 ? " · Junior: servono i dati di un genitore" : "")") } }
            Section("Documenti") {
                ForEach(NomiAssoc.documenti, id: \.0) { k, t in
                    Toggle(t, isOn: Binding(get: { a.documenti[k] ?? false }, set: { a.documenti[k] = $0; Task { await salva() } }))
                }
            }
            Section("Uscite di prova (\(a.uscite.count + a.presenze_eventi.count)/\(richieste))") {
                ForEach(a.presenze_eventi, id: \.id) { e in Label("\(e.nome) · presente", systemImage: "checkmark").foregroundStyle(Theme.oliveBright) }
                ForEach(a.uscite) { u in
                    VStack(alignment: .leading) {
                        Text("\(u.data) · \(u.titolo)").font(.subheadline.weight(.bold))
                        Text("tutor \(u.tutor)\(u.note.isEmpty ? "" : " · \(u.note)")").font(.caption).foregroundStyle(Theme.dim)
                    }
                }
                .onDelete { a.uscite.remove(atOffsets: $0); Task { await salva() } }
                TextField("Data (es. 2026-11-23)", text: $nuova.data)
                TextField("Uscita (es. Domenicale Torre Specchia)", text: $nuova.titolo)
                TextField("Tutor (callsign)", text: $nuova.tutor).textInputAutocapitalization(.characters)
                TextField("Come è andata", text: $nuova.note)
                Button { a.uscite.append(nuova); nuova = JUscitaProva(); Task { await salva() } } label: { Label("Aggiungi uscita", systemImage: "plus.circle.fill") }
                    .disabled(nuova.titolo.isEmpty)
            }
            Section("Note dei tutor") {
                TextField("Sicurezza, comportamento, radio, navigazione…", text: $a.note, axis: .vertical).lineLimit(3...8)
                Button("Salva note") { Task { await salva() } }
            }
            if let errore { Text(errore).foregroundStyle(Theme.red) }
            Section {
                if a.stato != "proposto" {
                    Button { Task { await salva(stato: "proposto") } } label: { Label("Proponi al direttivo", systemImage: "hand.raised.fill") }
                }
                if perm.p?.direttivo == true || ["presidente", "vicepresidente"].contains(perm.p?.carica ?? "") {
                    Button { conferma = true } label: { Label("Ammetti come socio", systemImage: "checkmark.seal.fill") }.tint(Theme.olive)
                    Button(role: .destructive) { conferma = false } label: { Label("Non ammettere", systemImage: "xmark") }
                }
            }
        }
        .navigationTitle(a.nome ?? a.callsign)
        .confirmationDialog(conferma == true ? "Ammettere \(a.callsign) come socio?" : "Non ammettere \(a.callsign)?", isPresented: Binding(get: { conferma != nil }, set: { if !$0 { conferma = nil } }), titleVisibility: .visible) {
            Button(conferma == true ? "Ammetti" : "Non ammettere", role: conferma == true ? nil : .destructive) {
                let ok = conferma == true
                Task {
                    do { aggiornato(try await JsocClient.shared.esitoAspirante(a.id, ammesso: ok)); dismiss() } catch { errore = error.localizedDescription }
                }
            }
        } message: { Text(conferma == true ? "Entra nel libro soci con la data di oggi." : "L'account viene disattivato.") }
    }

    func salva(stato: String? = nil) async {
        var c: [String: Any] = ["documenti": a.documenti, "note": a.note,
                                "uscite": a.uscite.map { ["data": $0.data, "titolo": $0.titolo, "tutor": $0.tutor, "note": $0.note] }]
        if let stato { c["stato"] = stato }
        do { let d = try await JsocClient.shared.salvaAspirante(a.id, c); aggiornato(d); if let n = d.aspiranti.first(where: { $0.id == a.id }) { a = n } }
        catch { errore = error.localizedDescription }
    }
}

// MARK: - Libro soci

struct LibroSociView: View {
    @State private var soci: [JSocioLibro] = []
    @State private var uscita: JSocioLibro?
    @State private var motivo = "dimissioni"
    var body: some View {
        List {
            let attivi = soci.filter { $0.attivo == 1 }, ex = soci.filter { $0.attivo == 0 }
            Section("Soci attivi (\(attivi.count))") {
                ForEach(attivi) { s in
                    NavigationLink { SchedaSocioView(id: s.id) } label: { riga(s) }
                        .swipeActions { Button("Uscita") { uscita = s }.tint(Theme.red) }
                }
            }
            if !ex.isEmpty { Section("Usciti (\(ex.count))") { ForEach(ex) { s in NavigationLink { SchedaSocioView(id: s.id) } label: { riga(s) } } } }
        }
        .listaJSOC().navigationTitle("Libro soci")
        .task { soci = (try? await JsocClient.shared.libroSoci()) ?? [] }
        .confirmationDialog("Uscita di \(uscita?.callsign ?? "")", isPresented: Binding(get: { uscita != nil }, set: { if !$0 { uscita = nil } }), titleVisibility: .visible) {
            ForEach(["dimissioni", "mancato rinnovo", "esclusione"], id: \.self) { m in
                Button(m.capitalized, role: m == "esclusione" ? .destructive : nil) {
                    if let s = uscita { Task { soci = (try? await JsocClient.shared.uscitaSocio(s.id, motivo: m)) ?? soci } }
                }
            }
        } message: { Text("Resta nel libro soci con la data di uscita e il motivo.") }
    }
    func riga(_ s: JSocioLibro) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(s.callsign).font(Theme.mono(14, .bold))
                Text(s.nome ?? "").foregroundStyle(Theme.dim)
                Spacer()
                if let c = s.carica, !c.isEmpty { Pillola(testo: NomiAssoc.carica(c).uppercased(), colore: Theme.olive) }
                if s.stato_socio == "aspirante" { Pillola(testo: "ASPIRANTE", colore: Theme.cyan) }
            }
            Text([s.ammesso.map { "ammesso \($0)" }, s.creato.map { "iscritto all'app " + Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .omitted) },
                  s.uscito.map { "uscito \($0) · \(s.uscita_motivo ?? "")" }].compactMap { $0 }.joined(separator: " · "))
                .font(.caption2).foregroundStyle(Theme.dim)
        }
    }
}

// MARK: - Cariche

struct CaricheView: View {
    @State private var c: JCariche?
    @State private var errore: String?
    @ObservedObject private var perm = PermessiStore.shared
    var puoAssegnare: Bool { perm.puo("cariche") }

    var body: some View {
        List {
            if let errore { Text(errore).foregroundStyle(Theme.red) }
            Section {
                ForEach(NomiAssoc.cariche, id: \.0) { k, nome, cosa in
                    let chi = c?.soci.filter { $0.carica == k } ?? []
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(nome).font(.headline)
                            Text(cosa).font(.caption).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        if puoAssegnare {
                            Menu {
                                ForEach(c?.soci.filter { ($0.stato_socio ?? "socio") == "socio" } ?? []) { s in
                                    Button(s.callsign) { Task { await assegna(s.id, k) } }
                                }
                                if let x = chi.first { Button("Lascia vacante", role: .destructive) { Task { await assegna(x.id, "") } } }
                            } label: { Text(chi.map(\.callsign).joined(separator: ", ").isEmpty ? "vacante" : chi.map(\.callsign).joined(separator: ", ")).font(Theme.mono(13, .bold)) }
                        } else {
                            Text(chi.isEmpty ? "vacante" : chi.map(\.callsign).joined(separator: ", ")).font(Theme.mono(13, .bold)).foregroundStyle(chi.isEmpty ? Theme.dim : Theme.oliveBright)
                        }
                    }
                }
            } header: { Text("Chi ricopre cosa") } footer: { Text(puoAssegnare ? "Le cariche le assegna il Presidente. Ogni cambio resta nello storico." : "Le cariche le assegna il Presidente.") }
            Section("Cosa vede chi") {
                tabella("Rubrica e contatti", "nomi", "tutto", "tutto")
                tabella("Dati sanitari", "no", "se condivisi", "sì")
                tabella("Fondo cassa", "no", "rendiconto", "Tesoriere")
                tabella("Voto in assemblea", "no", "sì", "sì")
                tabella("Tesseramento", "la sua", "la sua", "Segretario")
            }
            if let s = c?.storico, !s.isEmpty {
                Section("Storico") {
                    ForEach(s) { x in
                        VStack(alignment: .leading) {
                            Text(x.azione).font(.subheadline)
                            Text("\(x.callsign ?? "") · \(Date(timeIntervalSince1970: x.ts).formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(Theme.dim)
                        }
                    }
                }
            }
        }
        .listaJSOC().navigationTitle("Cariche")
        .task { do { c = try await JsocClient.shared.cariche() } catch { errore = error.localizedDescription } }
    }

    func tabella(_ t: String, _ a: String, _ s: String, _ d: String) -> some View {
        HStack {
            Text(t).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
            Text(a).frame(width: 54); Text(s).frame(width: 70); Text(d).frame(width: 70)
        }
        .font(.caption2.weight(.bold)).foregroundStyle(Theme.dim)
    }

    func assegna(_ u: Int, _ k: String) async {
        do { c = try await JsocClient.shared.assegnaCarica(u, k); errore = nil } catch { errore = error.localizedDescription }
    }
}

// MARK: - Fondo cassa

struct CassaV2View: View {
    @State private var anno = Calendar.current.component(.year, from: Date())
    @State private var c: JCassa2?
    @State private var scheda = 0
    @State private var mese = 0
    @State private var cerca = ""
    @State private var nuovo = false
    @State private var modifica: JMov2?
    @State private var budget = false
    @State private var errore: String?

    var movimenti: [JMov2] {
        (c?.movimenti ?? []).filter { m in
            if mese != 0 && Int(m.data.dropFirst(5).prefix(2)) != mese { return false }
            if cerca.isEmpty { return true }
            let testo: String = [m.descrizione ?? "", m.categoria ?? "", m.callsign ?? ""].joined(separator: " ")
            return testo.localizedCaseInsensitiveContains(cerca)
        }
    }

    var body: some View {
        let _ = GuidaApp.segna("cassa")
        List {
            if let errore { Text(errore).foregroundStyle(Theme.red) }
            if let c {
                Section { disponibile(c).comparsa(0) }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                Section {
                    HStack { SelettoreAnno(anno: $anno, anni: c.anni.compactMap(Int.init)); Spacer()
                        Picker("", selection: $scheda) { Text("Prima nota").tag(0); Text("Categorie").tag(1); Text("Budget").tag(2) }.pickerStyle(.segmented).frame(maxWidth: 270) }
                }
                switch scheda {
                case 0: primaNota(c)
                case 1: categorie(c)
                default: budgetSezione(c)
                }
                Section {
                    NavigationLink { RendicontoView(annoIniziale: anno) } label: { Label("Rendiconto \(String(anno))", systemImage: "doc.text.magnifyingglass") }
                    NavigationLink { StoricoCassaView() } label: { Label("Storico delle modifiche", systemImage: "clock.arrow.circlepath") }
                }
            } else { ProgressView() }
        }
        .listaJSOC().navigationTitle("Fondo cassa")
        .searchable(text: $cerca, prompt: "Cerca movimenti")
        .toolbar { Button { nuovo = true } label: { Label("Movimento", systemImage: "plus.circle.fill") } }
        .task(id: anno) { await carica() }
        .refreshable { await carica() }
        .sheet(isPresented: $nuovo) { MovimentoSheet2(esistente: nil, soglia: c?.soglia_ok ?? 100) { Task { await carica() } } }
        .sheet(item: $modifica) { m in MovimentoSheet2(esistente: m, soglia: c?.soglia_ok ?? 100) { Task { await carica() } } }
        .sheet(isPresented: $budget) { if let c { BudgetSheet(anno: anno, c: c) { self.c = $0 } } }
    }

    func disponibile(_ c: JCassa2) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DISPONIBILE OGGI").font(.system(size: 11, weight: .heavy)).tracking(1.2).foregroundStyle(Theme.oliveBright)
            Text(euroIT(c.disponibile)).font(Theme.mono(30, .heavy)).foregroundStyle(c.disponibile < 0 ? Theme.red : .white)
                .contentTransition(.numericText())
            HStack(spacing: 8) {
                ForEach(c.conti, id: \.self) { k in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NomiAssoc.conto(k).uppercased()).font(.system(size: 9.5, weight: .bold)).foregroundStyle(Theme.dim)
                        Text(euroIT(c.saldi[k] ?? 0)).font(Theme.mono(13, .heavy)).foregroundStyle((c.saldi[k] ?? 0) < 0 ? Theme.red : .white).minimumScaleFactor(0.7).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9).background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 11))
                }
            }
            HStack {
                Text("Anno \(String(c.anno)): ").foregroundStyle(Theme.dim)
                Text("+" + euroIT(c.entrate)).foregroundStyle(Theme.oliveBright)
                Text("−" + euroIT(c.uscite)).foregroundStyle(Theme.red)
                Spacer()
                if c.da_incassare > 0 { Text("da incassare " + euroIT(c.da_incassare)).foregroundStyle(Theme.amber) }
            }
            .font(.caption.weight(.bold))
            if !c.destinati.isEmpty {
                Text("Fondi destinati: " + c.destinati.map { "\($0.key) \(euroIT($0.value))" }.joined(separator: " · ")).font(.caption2).foregroundStyle(Theme.dim)
            }
        }
        .padding(14)
        .background(LinearGradient(colors: [Theme.oliveDeep, Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.olive.opacity(0.4)))
    }

    @ViewBuilder func primaNota(_ c: JCassa2) -> some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(0..<13, id: \.self) { m in chipMese(m) }
                }
            }
            .buttonStyle(.plain)
            let ent: Double = totale("entrata")
            let usc: Double = totale("uscita")
            HStack { Text("Entrate +\(euroIT(ent))").foregroundStyle(Theme.oliveBright); Spacer(); Text("Uscite −\(euroIT(usc))").foregroundStyle(Theme.red) }
                .font(.caption.weight(.heavy))
        }
        Section("Prima nota · \(movimenti.count) movimenti") {
            if movimenti.isEmpty { Text("Nessun movimento").foregroundStyle(Theme.dim) }
            ForEach(movimenti) { m in
                Button { modifica = m } label: { RigaMovimento(m: m) }
                    .swipeActions {
                        Button(role: .destructive) { Task { try? await JsocClient.shared.cancellaMovimento2(m.id); await carica() } } label: { Label("Elimina", systemImage: "trash") }
                    }
            }
        }
    }

    func totale(_ tipo: String) -> Double {
        var t = 0.0
        for m in movimenti where m.tipo == tipo { t += m.importo }
        return t
    }

    func chipMese(_ m: Int) -> some View {
        let attivo = mese == m
        let nome: String = m == 0 ? "Tutto l'anno" : Calendar.current.shortMonthSymbols[m - 1].capitalized
        return Button(nome) { mese = m }
            .font(.caption.weight(.bold)).padding(.horizontal, 10).padding(.vertical, 6)
            .background(attivo ? Theme.olive : Theme.surface2, in: Capsule())
            .foregroundStyle(attivo ? Color.black : Color.white)
    }

    @ViewBuilder func categorie(_ c: JCassa2) -> some View {
        ForEach(["entrata", "uscita"], id: \.self) { t in
            let v = c.categorie.filter { $0.tipo == t }.sorted { $0.totale > $1.totale }
            let tot: Double = max(1.0, v.map(\.totale).reduce(0.0, +))
            Section(t == "entrata" ? "Entrate per voce" : "Uscite per voce") {
                ForEach(v, id: \.self) { x in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Text(x.categoria.capitalized).font(.subheadline); Spacer(); Text(euroIT(x.totale)).font(Theme.mono(13, .bold)) }
                        GeometryReader { g in Capsule().fill(t == "entrata" ? Theme.olive : Theme.red).frame(width: g.size.width * x.totale / tot) }.frame(height: 5)
                    }
                }
            }
        }
    }

    @ViewBuilder func budgetSezione(_ c: JCassa2) -> some View {
        Section {
            if c.budget.isEmpty { Text("Nessun budget per il \(String(anno)): imposta quanto prevedi di spendere per voce.").foregroundStyle(Theme.dim) }
            ForEach(c.budget, id: \.self) { b in
                VStack(alignment: .leading, spacing: 3) {
                    HStack { Text(b.categoria.capitalized).font(.subheadline); Spacer()
                        Text("\(euroIT(b.speso)) / \(euroIT(b.importo))").font(Theme.mono(12, .bold)).foregroundStyle(b.speso > b.importo ? Theme.red : .white) }
                    ProgressView(value: min(b.speso, b.importo), total: max(b.importo, 1)).tint(b.speso > b.importo ? Theme.red : Theme.olive)
                }
            }
            Button { budget = true } label: { Label("Imposta il budget", systemImage: "slider.horizontal.3") }
        } header: { Text("Budget \(String(anno))") }
    }

    func carica() async {
        do { c = try await JsocClient.shared.cassa2(anno); errore = nil } catch { errore = error.localizedDescription }
    }
}

struct RigaMovimento: View {
    let m: JMov2
    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 0) {
                Text(String(m.data.dropFirst(8).prefix(2))).font(Theme.mono(14, .heavy))
                Text(meseBreve).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.dim)
            }
            .frame(width: 30)
            Image(systemName: m.tipo == "giroconto" ? "arrow.left.arrow.right" : m.tipo == "entrata" ? "arrow.down.left" : "arrow.up.right")
                .font(.caption.weight(.heavy)).foregroundStyle(m.tipo == "entrata" ? Theme.oliveBright : m.tipo == "uscita" ? Theme.red : Theme.dim)
                .frame(width: 26, height: 26).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(m.descrizione?.isEmpty == false ? m.descrizione! : (m.categoria ?? "Movimento")).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                Text(dettaglio).font(.caption2).foregroundStyle(Theme.dim).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text((m.tipo == "entrata" ? "+" : m.tipo == "uscita" ? "−" : "⇄ ") + euroIT(m.importo)).font(Theme.mono(13, .heavy))
                    .foregroundStyle(m.tipo == "entrata" ? Theme.oliveBright : m.tipo == "uscita" ? Theme.red : Theme.dim)
                if m.ricevuta != nil { Image(systemName: "paperclip").font(.caption2).foregroundStyle(Theme.dim) }
            }
        }
    }
    var meseBreve: String {
        guard let n = Int(m.data.dropFirst(5).prefix(2)), (1...12).contains(n) else { return "" }
        return Calendar.current.shortMonthSymbols[n - 1].uppercased()
    }
    var dettaglio: String {
        var p: [String] = []
        if m.tipo == "giroconto" { p.append("\(NomiAssoc.conto(m.conto)) → \(NomiAssoc.conto(m.conto_a))") } else { p.append(NomiAssoc.conto(m.conto)) }
        if let c = m.categoria, !c.isEmpty { p.append(c) }
        if let s = m.callsign { p.append(s) }
        if let e = m.evento_nome { p.append(e) }
        if m.importato == 1 { p.append("storico Excel") } else if let n = m.numero, !n.isEmpty { p.append(n) }
        return p.joined(separator: " · ")
    }
}

struct MovimentoSheet2: View {
    let esistente: JMov2?
    let soglia: Double
    var fatto: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = EventoStore.shared
    @State private var tipo = "uscita"
    @State private var importo = ""
    @State private var descrizione = ""
    @State private var categoria = "altro"
    @State private var conto = "cassa"
    @State private var contoA = "banca"
    @State private var data = Date()
    @State private var socio: Int?
    @State private var evento: Int?
    @State private var natura = "istituzionale"
    @State private var destinazione = ""
    @State private var foto: PhotosPickerItem?
    @State private var ricevuta: UIImage?
    @State private var ricevutaServer: UIImage?
    @State private var soci: [JSocioLibro] = []
    @State private var errore: String?
    @State private var lavoro = false

    var categorie: [String] { tipo == "entrata" ? NomiAssoc.categorieEntrata : NomiAssoc.categorieUscita }

    var body: some View {
        NavigationStack {
            Form {
                Picker("", selection: $tipo) { Text("Entrata").tag("entrata"); Text("Uscita").tag("uscita"); Text("Giroconto").tag("giroconto") }
                    .pickerStyle(.segmented).disabled(esistente != nil)
                Section {
                    TextField("0,00", text: $importo).keyboardType(.decimalPad).font(Theme.mono(34, .heavy)).multilineTextAlignment(.center)
                    TextField("Descrizione (es. Nastro e batterie per il campo)", text: $descrizione)
                }
                Section {
                    if tipo != "giroconto" {
                        Picker("Categoria", selection: $categoria) { ForEach(Array(Set(categorie + [categoria])).sorted(), id: \.self) { Text($0.capitalized).tag($0) } }
                    }
                    Picker(tipo == "giroconto" ? "Da" : "Conto", selection: $conto) { ForEach(["cassa", "banca", "paypal"], id: \.self) { Text(NomiAssoc.conto($0)).tag($0) } }
                    if tipo == "giroconto" { Picker("A", selection: $contoA) { ForEach(["cassa", "banca", "paypal"], id: \.self) { Text(NomiAssoc.conto($0)).tag($0) } } }
                    DatePicker("Data", selection: $data, displayedComponents: .date)
                    if tipo != "giroconto" {
                        Picker(tipo == "entrata" ? "Pagato da" : "Rimborso a / pagato a", selection: $socio) {
                            Text("—").tag(Int?.none)
                            ForEach(soci.filter { $0.attivo == 1 }) { Text($0.callsign).tag(Int?.some($0.id)) }
                        }
                        Picker("Evento collegato", selection: $evento) {
                            Text("—").tag(Int?.none)
                            ForEach(store.eventi.prefix(40)) { Text($0.nome).tag(Int?.some($0.id)) }
                        }
                        Picker("Natura", selection: $natura) { Text("Istituzionale").tag("istituzionale"); Text("Commerciale").tag("commerciale") }
                        TextField("Fondo destinato (es. Fondo campo)", text: $destinazione)
                    }
                }
                if tipo != "giroconto" {
                    Section("Ricevuta o scontrino") {
                        if let img = ricevuta ?? ricevutaServer { Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 10)) }
                        PhotosPicker(selection: $foto, matching: .images) { Label(ricevuta == nil && ricevutaServer == nil ? "Allega foto della ricevuta" : "Cambia la ricevuta", systemImage: "doc.viewfinder") }
                    }
                }
                if tipo == "uscita", let v = Double(importo.replacingOccurrences(of: ",", with: ".")), v > soglia {
                    Section { Label("Sopra \(euroIT(soglia)) serve l'ok del Presidente", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber).font(.footnote) }
                }
                if let m = esistente {
                    Section { Text("Numero \(m.numero ?? "—")\(m.modificato != nil ? " · modificato" : "")\(m.autore_cs.map { " · inserito da \($0)" } ?? "")").font(.caption).foregroundStyle(Theme.dim) }
                }
                if let errore { Text(errore).foregroundStyle(Theme.red) }
            }
            .navigationTitle(esistente == nil ? "Nuovo movimento" : "Movimento").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await salva() } } label: { if lavoro { ProgressView() } else { Text("Salva") } }
                        .disabled(Double(importo.replacingOccurrences(of: ",", with: ".")) == nil || lavoro)
                }
            }
            .task {
                soci = (try? await JsocClient.shared.libroSoci()) ?? []
                if let m = esistente {
                    tipo = m.tipo; importo = String(format: "%.2f", m.importo).replacingOccurrences(of: ".", with: ",")
                    descrizione = m.descrizione ?? ""; categoria = m.categoria?.isEmpty == false ? m.categoria! : "altro"
                    conto = m.conto ?? "cassa"; contoA = m.conto_a ?? "banca"; socio = m.utente; evento = m.evento
                    natura = m.natura ?? "istituzionale"; destinazione = m.destinazione ?? ""
                    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; data = f.date(from: m.data) ?? Date()
                    if m.ricevuta != nil, let d = try? await JsocClient.shared.scaricaDati("/api/cassa2/\(m.id)/ricevuta") { ricevutaServer = UIImage(data: d) }
                }
            }
            .onChange(of: foto) { item in
                guard let item else { return }
                Task { if let d = try? await item.loadTransferable(type: Data.self) { ricevuta = UIImage(data: d) } }
            }
        }
    }

    func salva() async {
        guard let v = Double(importo.replacingOccurrences(of: ",", with: ".")) else { return }
        lavoro = true; defer { lavoro = false }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        var c: [String: Any] = ["tipo": tipo, "importo": v, "descrizione": descrizione, "categoria": tipo == "giroconto" ? "giroconto" : categoria,
                                "conto": conto, "data": f.string(from: data), "natura": natura, "destinazione": destinazione]
        if tipo == "giroconto" { c["conto_a"] = contoA }
        c["utente"] = socio.map { $0 as Any } ?? NSNull()
        c["evento"] = evento.map { $0 as Any } ?? NSNull()
        do {
            let m = esistente == nil ? try await JsocClient.shared.nuovoMovimento2(c) : try await JsocClient.shared.modificaMovimento(esistente!.id, c)
            if let img = ricevuta, let jpg = img.ridotta(lato: 1800).jpegData(compressionQuality: 0.75) {
                try await JsocClient.shared.caricaDati("/api/cassa2/\(m.id)/ricevuta", dati: jpg)
            }
            fatto(); dismiss()
        } catch { errore = error.localizedDescription }
    }
}

struct BudgetSheet: View {
    let anno: Int
    let c: JCassa2
    var fatto: (JCassa2) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var voci: [String: String] = [:]
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("Quanto prevedi di spendere nel \(String(anno)) per ogni voce. Lascia vuoto per togliere.").font(.footnote).foregroundStyle(Theme.dim) }
                ForEach(NomiAssoc.categorieUscita, id: \.self) { k in
                    HStack {
                        Text(k.capitalized)
                        Spacer()
                        TextField("—", text: Binding(get: { voci[k] ?? "" }, set: { voci[k] = $0 })).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                        Text("€").foregroundStyle(Theme.dim)
                    }
                }
            }
            .navigationTitle("Budget \(String(anno))").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        var d: [String: Double] = [:]
                        for k in NomiAssoc.categorieUscita { d[k] = Double((voci[k] ?? "").replacingOccurrences(of: ",", with: ".")) ?? 0 }
                        Task { if let n = try? await JsocClient.shared.salvaBudget(anno, d) { fatto(n) }; dismiss() }
                    }
                }
            }
            .onAppear { for b in c.budget { voci[b.categoria] = String(format: "%.0f", b.importo) } }
        }
    }
}

struct StoricoCassaView: View {
    @State private var r: [JStoricoMod] = []
    var body: some View {
        List(r) { x in
            VStack(alignment: .leading, spacing: 2) {
                Text(x.azione.capitalized).font(.subheadline.weight(.bold))
                Text("\(x.callsign ?? "?") · \(Date(timeIntervalSince1970: x.ts).formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(Theme.dim)
                if let d = x.dettagli { Text(d).font(Theme.mono(10)).foregroundStyle(Theme.dim).lineLimit(3) }
            }
        }
        .listaJSOC().navigationTitle("Storico modifiche")
        .task { r = (try? await JsocClient.shared.storicoModifiche()) ?? [] }
    }
}

// MARK: - Rendiconto (lo vedono tutti i soci)

struct RendicontoView: View {
    var annoIniziale: Int? = nil
    @State private var anno = Calendar.current.component(.year, from: Date())
    @State private var r: JRendiconto?
    @State private var file: URL?
    @State private var errore: String?
    var body: some View {
        List {
            if let errore { Text(errore).foregroundStyle(Theme.red) }
            Section { SelettoreAnno(anno: $anno, anni: r?.anni.compactMap(Int.init) ?? []) }
            if let r {
                Section { riga("Saldo a inizio anno", r.saldo_iniziale, bold: true).comparsa(0) }
                Section("Entrate") {
                    ForEach(r.entrate, id: \.self) { riga($0.voce.capitalized, $0.totale) }
                    riga("Totale entrate", r.totale_entrate, bold: true, colore: Theme.oliveBright)
                }
                Section("Uscite") {
                    ForEach(r.uscite, id: \.self) { riga($0.voce.capitalized, $0.totale) }
                    riga("Totale uscite", r.totale_uscite, bold: true, colore: Theme.red)
                }
                Section {
                    riga(r.avanzo >= 0 ? "Avanzo dell'esercizio" : "Disavanzo dell'esercizio", r.avanzo, bold: true, colore: r.avanzo >= 0 ? Theme.oliveBright : Theme.red)
                    riga("Saldo a fine anno", r.saldo_finale, bold: true)
                }
                if let s = r.saldi_conti {
                    Section {
                        ForEach(s.keys.sorted(), id: \.self) { k in riga(NomiAssoc.conto(k), s[k] ?? 0) }
                    } header: { Text("Quadratura dei conti (oggi)") } footer: { Text("Confronta con l'estratto conto della banca e con la conta dei contanti.") }
                }
                Section {
                    Button { esporta(r) } label: { Label("Esporta (CSV per Excel)", systemImage: "square.and.arrow.up") }
                    if let file { ShareLink(item: file) { Label("Condividi il rendiconto", systemImage: "doc.text") } }
                } footer: { Text("Rendiconto per cassa: va approvato in assemblea ogni anno.") }
            }
        }
        .listaJSOC().navigationTitle("Rendiconto")
        .onAppear { if let a = annoIniziale { anno = a } }
        .task(id: anno) { do { r = try await JsocClient.shared.rendiconto(anno); errore = nil } catch { errore = error.localizedDescription } }
    }
    func riga(_ t: String, _ v: Double, bold: Bool = false, colore: Color = .white) -> some View {
        HStack { Text(t).font(bold ? .subheadline.weight(.heavy) : .subheadline); Spacer(); Text(euroIT(v)).font(Theme.mono(13, bold ? .heavy : .regular)).foregroundStyle(colore) }
    }
    func esporta(_ r: JRendiconto) {
        var s = "Rendiconto per cassa \(r.anno) - BAS J.S.O.C.\n\nSaldo iniziale;\(String(format: "%.2f", r.saldo_iniziale))\n\nENTRATE;\n"
        for x in r.entrate { s += "\(x.voce);\(String(format: "%.2f", x.totale))\n" }
        s += "Totale entrate;\(String(format: "%.2f", r.totale_entrate))\n\nUSCITE;\n"
        for x in r.uscite { s += "\(x.voce);\(String(format: "%.2f", x.totale))\n" }
        s += "Totale uscite;\(String(format: "%.2f", r.totale_uscite))\n\nAvanzo;\(String(format: "%.2f", r.avanzo))\nSaldo finale;\(String(format: "%.2f", r.saldo_finale))\n"
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("Rendiconto JSOC \(r.anno).csv")
        try? ("\u{FEFF}" + s.replacingOccurrences(of: ".", with: ",")).data(using: .utf8)?.write(to: u, options: .atomic)
        file = u
    }
}

// MARK: - Registro presenze

struct RegistroPresenzeView: View {
    @State private var anno = Calendar.current.component(.year, from: Date())
    @State private var r: JRegistro?
    @State private var errore: String?
    @State private var appello: Int?
    @ObservedObject private var store = EventoStore.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SelettoreAnno(anno: $anno, anni: r?.anni.compactMap(Int.init) ?? [])
                Spacer()
                if r?.gestisci == true {
                    Menu {
                        ForEach(store.eventi.filter { $0.fase != 1 && !$0.privato }.prefix(30)) { e in Button(e.nome) { appello = e.id } }
                    } label: { Label("Fai l'appello", systemImage: "checklist") }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            if let errore { Text(errore).foregroundStyle(Theme.red) }
            if let r {
                if r.colonne.isEmpty { Text("Nessuna presenza registrata nel \(String(anno))").foregroundStyle(Theme.dim).padding(40); Spacer() }
                else {
                    ScrollView([.vertical, .horizontal]) {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 0) {
                                Text("SOCIO").frame(width: 92, alignment: .leading)
                                Text("%").frame(width: 40)
                                ForEach(Array(r.colonne.enumerated()), id: \.offset) { _, c in
                                    VStack(spacing: 0) {
                                        Text(String((c.data ?? "").dropFirst(8))).font(Theme.mono(11, .heavy))
                                        Text(meseDi(c.data)).font(.system(size: 8, weight: .bold))
                                    }
                                    .frame(width: 34).foregroundStyle(c.annullato == true ? Theme.red : c.evento != nil ? Theme.cyan : Theme.dim)
                                    .strikethrough(c.annullato == true)
                                }
                            }
                            .font(.system(size: 9.5, weight: .heavy)).foregroundStyle(Theme.dim).padding(.vertical, 6)
                            ForEach(Array(r.soci.enumerated()), id: \.element.callsign) { i, s in
                                HStack(spacing: 0) {
                                    Text(s.callsign).font(Theme.mono(12, .bold)).frame(width: 92, alignment: .leading).lineLimit(1)
                                    Text(s.su > 0 ? "\(s.presenze * 100 / s.su)" : "—").font(Theme.mono(11, .bold)).foregroundStyle(Theme.oliveBright).frame(width: 40)
                                    ForEach(Array(s.celle.enumerated()), id: \.offset) { _, v in cella(v) }
                                }
                                .padding(.vertical, 3)
                                .comparsa(i)
                                Divider().overlay(Theme.stroke)
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                    HStack(spacing: 12) {
                        legenda(Theme.olive, "Presente"); legenda(Theme.red.opacity(0.5), "Assente"); legenda(Theme.surface2, "Annullato"); legenda(Theme.cyan, "Gara / altro")
                        Spacer()
                        Text("si compila da solo con gli eventi").font(.caption2).foregroundStyle(Theme.cyan)
                    }
                    .font(.caption2).padding(10)
                }
            } else { Spacer(); ProgressView(); Spacer() }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Registro presenze")
        .task(id: anno) { await carica() }
        .sheet(item: Binding(get: { appello.map { IdBox(id: $0) } }, set: { appello = $0?.id })) { b in
            AppelloView(evento: b.id) { Task { await carica() } }
        }
    }

    struct IdBox: Identifiable { let id: Int }

    func meseDi(_ d: String?) -> String {
        guard let d, let n = Int(d.dropFirst(5).prefix(2)), (1...12).contains(n) else { return "" }
        return Calendar.current.shortMonthSymbols[n - 1].uppercased()
    }
    func cella(_ v: String?) -> some View {
        let t = (v ?? "").lowercased()
        let c: Color = v == nil ? .clear : t.hasPrefix("pres") ? Theme.olive : t.hasPrefix("ass") ? Theme.red.opacity(0.35) : t.hasPrefix("annull") ? Theme.surface2 : Theme.cyan
        return RoundedRectangle(cornerRadius: 4).fill(c).frame(width: 26, height: 18).frame(width: 34)
            .overlay {
                if t.hasPrefix("annull") { Image(systemName: "xmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(Theme.dim) }
                else if let v, !t.hasPrefix("pres"), !t.hasPrefix("ass") { Text(String(v.prefix(3))).font(.system(size: 8, weight: .heavy)).foregroundStyle(.black) }
            }
    }
    func legenda(_ c: Color, _ t: String) -> some View { HStack(spacing: 4) { RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 12, height: 10); Text(t) } }
    func carica() async { do { r = try await JsocClient.shared.registroPresenze(anno); errore = nil } catch { errore = error.localizedDescription } }
}

struct AppelloView: View {
    let evento: Int
    var fatto: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var l: [JAppello] = []
    var body: some View {
        NavigationStack {
            List(l) { s in
                HStack {
                    VStack(alignment: .leading) {
                        Text(s.callsign).font(Theme.mono(14, .bold))
                        if let r = s.risposta { Text(r == "si" ? "aveva detto partecipo" : r == "no" ? "aveva detto non partecipo" : r).font(.caption2).foregroundStyle(Theme.dim) }
                    }
                    Spacer()
                    Button { segna(s, true) } label: { Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(s.presente == 1 ? Theme.olive : Theme.surface2) }
                    Button { segna(s, false) } label: { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(s.presente == 0 ? Theme.red : Theme.surface2) }
                }
                .buttonStyle(.plain)
            }
            .listaJSOC().navigationTitle("Appello").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { fatto(); dismiss() } } }
            .task { l = (try? await JsocClient.shared.appelloEvento(evento)) ?? [] }
        }
    }
    func segna(_ s: JAppello, _ p: Bool) {
        haptic()
        Task {
            try? await JsocClient.shared.segnaAppello(evento, s.id, p)
            l = (try? await JsocClient.shared.appelloEvento(evento)) ?? l
        }
    }
}

// MARK: - Assemblee

struct AssembleeView: View {
    @State private var a: [JAssemblea] = []
    @State private var nuova = false
    @ObservedObject private var perm = PermessiStore.shared
    var body: some View {
        List {
            if a.isEmpty { Text("Nessuna assemblea").foregroundStyle(Theme.dim) }
            ForEach(a) { x in
                NavigationLink { AssembleaView(id: x.id) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Text(x.titolo).font(.headline); Spacer(); Pillola(testo: x.stato.uppercased(), colore: x.stato == "chiusa" ? Theme.dim : x.stato == "in corso" ? Theme.amber : Theme.olive) }
                        Text("\(x.data ?? "") · \(x.luogo ?? "") · \(x.odg.count) punti").font(.caption).foregroundStyle(Theme.dim)
                    }
                }
            }
        }
        .listaJSOC().navigationTitle("Assemblee")
        .toolbar { if perm.puo("assemblee") { Button { nuova = true } label: { Label("Convoca", systemImage: "plus") } } }
        .task { a = (try? await JsocClient.shared.assemblee()) ?? [] }
        .refreshable { a = (try? await JsocClient.shared.assemblee()) ?? [] }
        .sheet(isPresented: $nuova) { NuovaAssembleaSheet { Task { a = (try? await JsocClient.shared.assemblee()) ?? a } } }
    }
}

struct NuovaAssembleaSheet: View {
    var fatto: () -> Void
    @Environment(\.dismiss) private var dismiss
    struct Punto: Identifiable { let id = UUID(); var titolo = ""; var voto = true; var segreto = false }
    @State private var titolo = "Assemblea ordinaria dei soci"
    @State private var tipo = "ordinaria"
    @State private var data = Calendar.current.date(byAdding: .day, value: 15, to: Date()) ?? Date()
    @State private var luogo = "Sede · Galatina"
    @State private var punti = [Punto(titolo: "Approvazione del rendiconto"), Punto(titolo: "Quota sociale"), Punto(titolo: "Varie ed eventuali", voto: false)]
    @State private var errore: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titolo", text: $titolo)
                    Picker("Tipo", selection: $tipo) { Text("Ordinaria").tag("ordinaria"); Text("Straordinaria").tag("straordinaria") }
                    DatePicker("Data e ora", selection: $data)
                    TextField("Luogo", text: $luogo)
                }
                Section {
                    ForEach($punti) { $p in
                        VStack(alignment: .leading) {
                            TextField("Punto", text: $p.titolo)
                            HStack { Toggle("Si vota", isOn: $p.voto); if p.voto { Toggle("Segreto", isOn: $p.segreto) } }.font(.caption)
                        }
                    }
                    .onDelete { punti.remove(atOffsets: $0) }
                    Button { punti.append(Punto()) } label: { Label("Aggiungi punto", systemImage: "plus") }
                } header: { Text("Ordine del giorno") } footer: { Text("La convocazione va in bacheca con conferma di lettura. Convocala con almeno 15 giorni di anticipo, se lo statuto non dice diversamente.") }
                if let errore { Text(errore).foregroundStyle(Theme.red) }
            }
            .navigationTitle("Convoca assemblea").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Convoca") {
                        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
                        let c: [String: Any] = ["titolo": titolo, "tipo": tipo, "data": f.string(from: data), "luogo": luogo,
                                                "odg": punti.filter { !$0.titolo.isEmpty }.map { ["titolo": $0.titolo, "voto": $0.voto, "segreto": $0.segreto] }]
                        Task {
                            do { _ = try await JsocClient.shared.nuovaAssemblea(c); fatto(); dismiss() } catch { errore = error.localizedDescription }
                        }
                    }
                }
            }
        }
    }
}

struct AssembleaView: View {
    let id: Int
    @State private var a: JAssemblea?
    @State private var errore: String?
    @State private var delega = false
    @State private var soci: [JSocioLibro] = []
    @State private var chiudi = false

    var body: some View {
        let _ = GuidaApp.segna("assemblea")
        ScrollView {
            VStack(spacing: 12) {
                if let errore { ErrorCard(text: errore) }
                if let a { contenuto(a) } else { ProgressView().padding(40) }
            }
            .padding(14).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(a?.titolo ?? "Assemblea").navigationBarTitleDisplayMode(.inline)
        .task {
            while !Task.isCancelled {
                await carica()
                try? await Task.sleep(nanoseconds: a?.stato == "chiusa" ? 60_000_000_000 : 6_000_000_000)
            }
        }
        .sheet(isPresented: $delega) { if let a { DelegaSheet(assemblea: a, soci: soci) { self.a = $0 } } }
        .confirmationDialog("Chiudere l'assemblea e generare il verbale?", isPresented: $chiudi, titleVisibility: .visible) {
            Button("Chiudi e genera verbale") { Task { do { a = try await JsocClient.shared.chiudiAssemblea(id) } catch { errore = error.localizedDescription } } }
        }
    }

    @ViewBuilder func contenuto(_ a: JAssemblea) -> some View {
        Card {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Theme.surface2, lineWidth: 8)
                    Circle().trim(from: 0, to: min(1, CGFloat(a.presenti + a.deleghe) / CGFloat(max(1, a.aventi_diritto))))
                        .stroke(a.numero_legale ? Theme.olive : Theme.amber, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                    Text("\(a.presenti + a.deleghe)/\(a.aventi_diritto)").font(Theme.mono(13, .heavy))
                }
                .frame(width: 66, height: 66)
                VStack(alignment: .leading, spacing: 3) {
                    Text(a.numero_legale ? "Numero legale raggiunto" : "Numero legale non ancora raggiunto").font(.headline).foregroundStyle(a.numero_legale ? Theme.oliveBright : Theme.amber)
                    Text("\(a.presenti) presenti + \(a.deleghe) deleghe · servono \(a.quorum)").font(.caption).foregroundStyle(Theme.dim)
                    Text("\(a.data ?? "") · \(a.luogo ?? "")").font(.caption2).foregroundStyle(Theme.dim)
                }
            }
        }
        if a.stato != "chiusa" {
            Card(title: "La mia presenza", icon: "person.fill.checkmark") {
                if let m = a.mia { Text(m.stato == "presente" ? "Presente" : m.stato == "delega" ? "Hai delegato \(m.delegato_cs ?? "")" : "Assente").font(.subheadline.weight(.bold)).foregroundStyle(Theme.oliveBright) }
                if !a.miei_deleganti.isEmpty { Text("Voti anche per: " + a.miei_deleganti.joined(separator: ", ")).font(.caption).foregroundStyle(Theme.amber) }
                if !a.posso_votare { Text("Aspiranti ed ex soci partecipano ma non votano.").font(.caption).foregroundStyle(Theme.dim) }
                HStack {
                    Button { Task { await presenza(["stato": "presente"]) } } label: { Text("Presente").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButtonStyle())
                    Button { Task { soci = (try? await JsocClient.shared.libroSoci()) ?? []; delega = true } } label: { Text("Delego").frame(maxWidth: .infinity) }.buttonStyle(.bordered).tint(Theme.olive)
                    Button { Task { await presenza(["stato": "assente"]) } } label: { Text("Assente").frame(maxWidth: .infinity) }.buttonStyle(.bordered).tint(Theme.dim)
                }
            }
        }
        Card(title: "Ordine del giorno", icon: "list.number") {
            ForEach(Array(a.odg.enumerated()), id: \.offset) { i, p in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        Text("\(i + 1)").font(Theme.mono(15, .heavy)).foregroundStyle(p.stato == "aperto" ? Theme.amber : Theme.olive)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.titolo).font(.subheadline.weight(.bold))
                            if p.voto, let k = p.conteggio {
                                Text(p.stato == "chiuso" ? "\(p.esito.uppercased()) · \(k.si) sì, \(k.no) no, \(k.astenuto) astenuti" :
                                        p.stato == "aperto" ? "votazione aperta · \(p.votanti ?? 0) voti\(p.segreto ? " · segreta" : "")" : "da votare\(p.segreto ? " · segreta" : "")")
                                    .font(.caption).foregroundStyle(p.stato == "chiuso" ? (p.esito == "approvato" ? Theme.oliveBright : Theme.red) : Theme.dim)
                            }
                        }
                        Spacer()
                    }
                    if p.voto && p.stato == "aperto" && a.posso_votare {
                        HStack {
                            ForEach([("si", "Favorevole", Theme.olive), ("no", "Contrario", Theme.red), ("astenuto", "Astenuto", Theme.dim)], id: \.0) { k, t, c in
                                Button { Task { await vota(i, k) } } label: { Text(t).font(.caption.weight(.bold)).frame(maxWidth: .infinity) }
                                    .buttonStyle(.borderedProminent).tint(p.mio_voto == k ? c : Theme.surface2)
                            }
                        }
                    }
                    if a.gestisci && p.voto && a.stato != "chiusa" {
                        HStack {
                            if p.stato != "aperto" { Button("Apri votazione") { Task { await punto(i, "aperto") } }.buttonStyle(.bordered).tint(Theme.amber) }
                            else { Button("Chiudi votazione") { Task { await punto(i, "chiuso") } }.buttonStyle(.bordered).tint(Theme.amber) }
                        }
                        .font(.caption)
                    }
                    if let n = p.nominativi, !n.isEmpty, p.stato == "chiuso" {
                        Text(n.map { "\($0.callsign) \($0.voto)" }.joined(separator: " · ")).font(.caption2).foregroundStyle(Theme.dim)
                    }
                }
                .padding(.vertical, 4)
                if i < a.odg.count - 1 { Divider().overlay(Theme.stroke) }
            }
        }
        if a.gestisci && a.stato != "chiusa" {
            Button { chiudi = true } label: { Label("Chiudi e genera il verbale", systemImage: "doc.badge.gearshape") }.buttonStyle(PrimaryButtonStyle())
        }
        if let v = a.verbale, !v.isEmpty {
            Card(title: "Verbale", icon: "doc.text") {
                Text(v).font(Theme.mono(11)).textSelection(.enabled)
                ShareLink(item: v) { Label("Condividi il verbale", systemImage: "square.and.arrow.up") }
                Text("Salvato anche in Documenti › Verbali.").font(.caption2).foregroundStyle(Theme.dim)
            }
        }
    }

    func carica() async { do { a = try await JsocClient.shared.assemblee().first { $0.id == id }; errore = nil } catch { errore = error.localizedDescription } }
    func presenza(_ c: [String: Any]) async { do { a = try await JsocClient.shared.presenzaAssemblea(id, c) } catch { errore = error.localizedDescription } }
    func vota(_ i: Int, _ v: String) async { haptic(.medium); do { a = try await JsocClient.shared.votaAssemblea(id, i, v) } catch { errore = error.localizedDescription } }
    func punto(_ i: Int, _ s: String) async { do { a = try await JsocClient.shared.puntoAssemblea(id, i, stato: s) } catch { errore = error.localizedDescription } }
}
