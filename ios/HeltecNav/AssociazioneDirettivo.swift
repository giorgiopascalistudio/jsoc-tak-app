import SwiftUI

// MARK: - Associazione, vista del direttivo (tavola 47): DA FARE ORA con i tasti azione, 6 voci grandi, Altro, Crea.
// Le misure (pt), i colori e i testi sono quelli della tavola AssociazioneDir10 della tela.
// Anteprime: -debug.dir.apri soci|scheda|movimento|spesa (+ -debug.dir.scorri LILLO nell'elenco soci).

// MARK: modelli e chiamate in più per il direttivo

/// spesa proposta da un socio (rimborso o acquisto) che il direttivo approva o rifiuta (tavola 51)
struct JSpesaProposta: Codable, Identifiable, Hashable {
    let id: Int
    let importo: Double
    var descrizione: String? = nil
    var utente: Int? = nil
    var callsign: String? = nil
    var ts: Double? = nil
    var negozio: String? = nil
    var data: String? = nil
    var categoria: String? = nil
    var evento: Int? = nil
    var evento_nome: String? = nil
    var evento_inizio: String? = nil
    /// "rimborso" (l'ha pagata il socio) o "acquisto" (da pagare)
    var tipo: String? = nil
    /// "attesa", "presidente" (serve l'ok del Presidente), "approvata", "rifiutata"
    var stato: String? = nil
    var ricevuta: Bool? = nil
    var motivo: String? = nil
}

/// esito dell'approvazione: la proposta aggiornata e, se approvata, il numero del movimento in cassa
struct JEsitoSpesa: Codable { var ok: Bool? = nil; var stato: String? = nil; var numero: String? = nil; var errore: String? = nil }

extension JsocClient {
    func speseProposte() async throws -> [JSpesaProposta] { try await get("/api/spese-proposte?stato=attesa") }
    func esitoSpesa(_ id: Int, approva: Bool, conto: String, motivo: String) async throws -> JEsitoSpesa {
        try await send("/api/spese-proposte/\(id)/esito", "POST", ["esito": approva ? "approvata" : "rifiutata", "conto": conto, "motivo": motivo])
    }
    /// avvisa i soci con certificato o quota in scadenza (notifica a ciascuno)
    func ricordaScadenze() async throws -> Int {
        struct R: Codable { let quanti: Int? }
        let r: R = try await send("/api/scadenze/ricorda", "POST", ["giorni": 30])
        return r.quanti ?? 0
    }
}

/// gli errori "endpoint mancante" del server diventano un messaggio gentile
func erroreGentile(_ e: Error) -> String {
    let t = e.localizedDescription
    if t.contains("404") || t.lowercased().contains("non trovat") || t.lowercased().contains("not found") {
        return "Il server non sa ancora farlo: va aggiornato."
    }
    return t
}

// MARK: pezzi comuni delle tavole 47-51

/// tasto tondo 42 con bordo (indietro, altre azioni)
struct TastoTondoDir: View {
    let icona: String
    var lato: CGFloat = 18
    var body: some View {
        IconaTela(d: icona, colore: Theme.testo, lato: lato)
            .frame(width: 42, height: 42).background(Theme.surface, in: Circle()).overlay(Circle().strokeBorder(Theme.stroke))
    }
}

/// intestazione delle pagine: indietro 42, titolo 24, eventuale tasto a destra
struct TestataDir<Destra: View>: View {
    let titolo: String
    @ViewBuilder var destra: () -> Destra
    @Environment(\.dismiss) private var chiudi
    var body: some View {
        HStack(spacing: 8) {
            Button { chiudi() } label: { TastoTondoDir(icona: Ic.indietro) }.accessibilityLabel("Indietro")
            Text(titolo).font(.system(size: 24, weight: .black)).foregroundStyle(Theme.testo).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            destra()
        }
        .padding(.horizontal, 14).padding(.top, 7)
    }
}

extension TestataDir where Destra == EmptyView {
    init(titolo: String) { self.titolo = titolo; self.destra = { EmptyView() } }
}

/// capsula di scelta (filtri, categorie, conti): alta 32, piena quando scelta
struct ChipDir: View {
    let testo: String
    var scelto = false
    var pieno: Color = Theme.testo
    var body: some View {
        Text(testo).font(.system(size: 12, weight: .heavy)).lineLimit(1)
            .foregroundStyle(scelto ? Theme.scuro : Theme.testo2)
            .padding(.horizontal, 11).frame(height: 32)
            .background(scelto ? pieno : Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(scelto ? .clear : Theme.stroke))
            .fixedSize()
    }
}

/// scontrino in miniatura (foto della ricevuta o foglio con le righe della tela)
struct ScontrinoDir: View {
    var foto: UIImage? = nil
    var larghezza: CGFloat = 52
    var altezza: CGFloat = 66
    var righe: [CGFloat] = [1, 0.7, 1, 0.5]
    var body: some View {
        ZStack(alignment: .topLeading) {
            if let foto {
                Image(uiImage: foto).resizable().scaledToFill().frame(width: larghezza, height: altezza).clipped()
            } else {
                Color(hex: 0xE9E6DA)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(righe.indices, id: \.self) { i in
                        Rectangle().fill(Color(hex: 0xB5B19F)).frame(width: (larghezza - 12) * righe[i], height: 3)
                    }
                }
                .padding(.horizontal, 6).padding(.vertical, 8)
            }
        }
        .frame(width: larghezza, height: altezza)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// etichetta mono della tela (SOCIO, IN ATTESA, DA PAGARE · 40 €)
struct TagDir: View {
    let testo: String
    let colore: Color
    var dimensione: CGFloat = 9
    var orizzontale: CGFloat = 6
    var body: some View {
        Text(testo).font(Theme.mono(dimensione, .heavy)).foregroundStyle(colore).lineLimit(1)
            .padding(.horizontal, orizzontale).padding(.vertical, 2)
            .background(colore.opacity(0.13), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(colore.opacity(0.33)))
    }
}

/// pagina a schermo intero del direttivo: niente barra di navigazione né barra in basso (come le tavole 48-51)
struct PaginaDir: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { ModuliAperti.shared.aperti += 1 }
            .onDisappear { ModuliAperti.shared.aperti = max(0, ModuliAperti.shared.aperti - 1) }
    }
}
extension View { func paginaDir() -> some View { modifier(PaginaDir()) } }

enum DebugDir {
    static var apri: String? { UserDefaults.standard.string(forKey: "debug.dir.apri") }
    static var scorri: String? { UserDefaults.standard.string(forKey: "debug.dir.scorri") }
}

// MARK: - Riepilogo per DA FARE ORA

struct RiepilogoDir {
    var nonAssicurati = 0
    var aspiranti = 0
    var spese: [JSpesaProposta] = []
    var scadenze = 0
    var prossimaAssemblea: String?
    var richieste: Int { aspiranti + spese.count }
    var testoRichieste: String {
        var p: [String] = []
        if aspiranti > 0 { p.append(aspiranti == 1 ? "1 aspirante" : "\(aspiranti) aspiranti") }
        if !spese.isEmpty { p.append(spese.count == 1 ? "1 rimborso" : "\(spese.count) rimborsi") }
        return (richieste == 1 ? "richiesta da approvare" : "richieste da approvare") + (p.isEmpty ? "" : " (\(p.joined(separator: ", ")))")
    }
}

// MARK: - Schermata principale (tavola 47)

struct AssociazioneDirettivoV3: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var home = HomeModel.shared
    @State private var scheda = 0
    @State private var r = RiepilogoDir()
    @State private var debugAperto = DebugDir.apri != nil
    @State private var crea: String?
    @State private var messaggio: String?
    @State private var vai: String?

    var body: some View {
        let _ = Contatori.disegno("AssociazioneDirettivoV3")
        VStack(alignment: .leading, spacing: 0) {
            intestazione
            if scheda == 0 {
                ScrollView {
                    VStack(spacing: 10) {
                        SchedeTela(voci: ["Gestione", "Come socio"], scelta: $scheda)
                        daFare
                        griglia
                        altro
                    }
                    .padding(.horizontal, 14).padding(.top, 12.5).padding(.bottom, 96)
                }
                .scrollIndicators(.hidden)
                .refreshable { await carica() }
            } else {
                SchedeTela(voci: ["Gestione", "Come socio"], scelta: $scheda)
                    .padding(.horizontal, 14).padding(.top, 12.5)
                AssociazioneHomeV2()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $debugAperto) { vistaDebug }
        .navigationDestination(isPresented: Binding(get: { vai != nil }, set: { if !$0 { vai = nil } })) {
            if vai == "assemblee" { AssembleeView() } else { NuovoMovimentoV3() }
        }
        .sheet(item: Binding(get: { crea.map { CreaDir(id: $0) } }, set: { crea = $0?.id })) { c in
            switch c.id {
            case "avviso": NuovoPostSheet { _ in }
            case "sondaggio": NuovoSondaggioSheet { _ in }
            default: InvitoSheet()
            }
        }
        .alert(messaggio ?? "", isPresented: Binding(get: { messaggio != nil }, set: { if !$0 { messaggio = nil } })) { Button("OK") {} }
        .task { await carica() }
    }

    struct CreaDir: Identifiable { let id: String }

    @ViewBuilder var vistaDebug: some View {
        switch DebugDir.apri ?? "" {
        case "soci": SociDirettivoV3()
        case "scheda": SchedaSocioDirettivo(id: Anteprima.dirIdViper, sigla: "VP")
        case "movimento": NuovoMovimentoV3()
        case "spesa": ApprovaSpesaV3(spesa: r.spese.first ?? Anteprima.dirSpese[0])
        default: RichiesteDirettivo(spese: r.spese)
        }
    }

    // MARK: intestazione (top 54, lati 16): titolo 26, sottotitolo 11,5, Crea 40

    var intestazione: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Associazione").font(.system(size: 26, weight: .black)).foregroundStyle(Theme.testo)
                Text("BAS JSOC · FIGT · Comitato Puglia e Basilicata").font(.system(size: 11.5)).foregroundStyle(Theme.dim).lineLimit(1)
            }
            Spacer(minLength: 0)
            Menu {
                Button { vai = "movimento" } label: { Label("Movimento di cassa", systemImage: "eurosign.circle") }
                Button { crea = "avviso" } label: { Label("Avviso ai soci", systemImage: "megaphone") }
                Button { crea = "sondaggio" } label: { Label("Sondaggio", systemImage: "chart.bar") }
                Button { vai = "assemblee" } label: { Label("Assemblea", systemImage: "building.columns") }
                Button { crea = "invito" } label: { Label("Invito per un nuovo socio", systemImage: "qrcode") }
            } label: {
                HStack(spacing: 6) {
                    IconaTela(d: Ic.piu, colore: Theme.scuro, lato: 16)
                    Text("Crea").font(.system(size: 13.5, weight: .black))
                }
                .foregroundStyle(Theme.scuro)
                .padding(.horizontal, 14).frame(height: 40)
                .background(Theme.olive, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
        }
        .padding(.horizontal, 16).padding(.top, 7)
    }

    // MARK: DA FARE ORA (bordo ambra 40%, righe con numero tondo 30 e tasto 34)

    @ViewBuilder var daFare: some View {
        let righe = righeDaFare
        VStack(spacing: 0) {
            HStack {
                Text("DA FARE ORA").font(.system(size: 11, weight: .heavy)).tracking(0.66).foregroundStyle(Theme.amber)
                Spacer()
                NavigationLink { RichiesteDirettivo(spese: r.spese) } label: {
                    Text("tutto ›").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.dim)
                }
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 2)
            if righe.isEmpty {
                Text("Tutto in ordine: niente da fare adesso.").font(.system(size: 13.5, weight: .bold)).foregroundStyle(Theme.testo2)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 10)
            }
            ForEach(Array(righe.enumerated()), id: \.offset) { i, v in
                HStack(spacing: 11) {
                    Text("\(v.numero)").font(Theme.mono(14, .heavy)).foregroundStyle(v.colore)
                        .frame(minWidth: 30, minHeight: 30).background(v.colore.opacity(0.15), in: Capsule())
                    Text(v.testo).font(.system(size: 13.5, weight: .bold)).foregroundStyle(Theme.testo).lineSpacing(2.4)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    v.tasto
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Theme.olive.opacity(0.12)).frame(height: 1) } }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.amber.opacity(0.4)))
    }

    struct VoceDaFare { let numero: Int; let colore: Color; let testo: String; let tasto: AnyView }

    func tasto(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 12, weight: .black)).foregroundStyle(Theme.scuro)
            .padding(.horizontal, 12).frame(height: 34).background(c, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    var righeDaFare: [VoceDaFare] {
        var v: [VoceDaFare] = []
        if r.nonAssicurati > 0 {
            v.append(VoceDaFare(numero: r.nonAssicurati, colore: Theme.red,
                                testo: (r.nonAssicurati == 1 ? "socio non assicurato" : "soci non assicurati") + ": carica i nomi su FIGT",
                                tasto: AnyView(NavigationLink { TesseramentoView() } label: { tasto("Carica", Theme.red) }.buttonStyle(PressStyle()))))
        }
        if r.richieste > 0 {
            v.append(VoceDaFare(numero: r.richieste, colore: Theme.oliveBright, testo: r.testoRichieste,
                                tasto: AnyView(NavigationLink { RichiesteDirettivo(spese: r.spese) } label: { tasto("Apri", Theme.oliveBright) }.buttonStyle(PressStyle()))))
        }
        if r.scadenze > 0 {
            v.append(VoceDaFare(numero: r.scadenze, colore: Theme.amber, testo: "certificati o quote in scadenza entro 30 giorni",
                                tasto: AnyView(Button { Task { await ricorda() } } label: { tasto("Ricorda", Theme.amber) }.buttonStyle(PressStyle()))))
        }
        return v
    }

    // MARK: 6 voci grandi (2 colonne, alte 88, icona 22)

    var griglia: some View {
        let saldo = home.dati?.direttivo?.saldo
        let soci = home.dati?.soci_attivi ?? 0
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            voce(Ic.soci, Theme.oliveBright, "Soci", soci > 0 ? "\(soci) soci · schede e documenti" : "schede e documenti") { SociDirettivoV3() }
            voce(Ic.carta, Theme.amber, "Tesseramento", "FIGT e assicurazione") { TesseramentoView() }
            voce(Ic.dollaro, Theme.amber, "Cassa", saldo.map { "saldo " + euroIT($0) } ?? "conti e movimenti") { CassaV2View() }
            voce(Ic.nuovoSocio, Theme.amber, "Nuovi soci", "aspiranti e domande") { AspirantiView() }
            voce(Ic.comunicazioni, Theme.cyan, "Comunicazioni", "avvisi e sondaggi") { ComunicazioniDir() }
            voce(Ic.assemblee, Theme.cyan, "Assemblee", r.prossimaAssemblea.map { "prossima \($0)" } ?? "convocazioni e voti") { AssembleeView() }
        }
    }

    func voce<D: View>(_ icona: String, _ colore: Color, _ titolo: String, _ sotto: String, @ViewBuilder dest: @escaping () -> D) -> some View {
        NavigationLink { dest() } label: {
            VStack(alignment: .leading, spacing: 0) {
                IconaTela(d: icona, colore: colore, lato: 22)
                Spacer(minLength: 0)
                Text(titolo).font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.testo).lineLimit(1)
                Text(sotto).font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(1).padding(.top, 2)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading).frame(height: 88)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke))
        }
        .buttonStyle(PressStyle())
    }

    // MARK: Altro (alto 52)

    var altro: some View {
        NavigationLink { AltroDirettivo() } label: {
            HStack(spacing: 10) {
                IconaTela(d: Ic.menu, colore: Theme.dim, lato: 18)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Altro").font(.system(size: 13.5, weight: .heavy)).foregroundStyle(Theme.testo)
                    Text("Libro soci, Gruppi, Cariche, Ricevute, Riunioni, Stampe, Magazzino…").font(.system(size: 10.5)).foregroundStyle(Theme.dim).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                IconaTela(d: Ic.avanti, colore: Color(hex: 0x6F7564), lato: 14)
            }
            .padding(.horizontal, 12).frame(height: 52)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Theme.stroke))
        }
        .buttonStyle(PressStyle())
    }

    // MARK: dati

    func ricorda() async {
        haptic(.medium)
        if Anteprima.attiva { messaggio = "Promemoria inviato a \(r.scadenze) soci."; return }
        do {
            let n = try await jsoc.ricordaScadenze()
            messaggio = n == 1 ? "Promemoria inviato a 1 socio." : "Promemoria inviato a \(n) soci."
        } catch { messaggio = erroreGentile(error) }
    }

    func carica() async {
        if Anteprima.attiva { r = Anteprima.dirRiepilogo; return }
        await home.aggiorna()
        let anno = AnnoDir.quota
        var n = RiepilogoDir()
        if let t = try? await jsoc.tesseramento(anno) {
            let attivi = t.soci.filter { ($0.stato_socio ?? "socio") != "aspirante" && $0.rinnova }
            n.nonAssicurati = attivi.filter { !$0.intranet }.count
            n.scadenze = attivi.filter { ($0.giorni_certificato ?? 999) <= 30 || !$0.quota }.count
        }
        if let a = try? await jsoc.aspiranti() { n.aspiranti = a.aspiranti.filter { $0.stato == "proposto" }.count }
        n.spese = (try? await jsoc.speseProposte()) ?? []
        if let a = try? await jsoc.assemblee(), let p = a.first(where: { $0.stato != "chiusa" }), let d = p.data, d.count >= 10,
           let g = FormatoGiorno.f.date(from: String(d.prefix(10))) {
            n.prossimaAssemblea = FormatiHome.giornoMese.string(from: g)
        }
        r = n
    }
}

// MARK: - Richieste da approvare (dal tasto Apri e da "tutto ›")

struct RichiesteDirettivo: View {
    var spese: [JSpesaProposta]
    @State private var lista: [JSpesaProposta]?
    @State private var aspiranti: [JAspirante] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TestataDir(titolo: "Da approvare")
            ScrollView {
                VStack(spacing: 10) {
                    let s = lista ?? spese
                    if s.isEmpty && aspiranti.isEmpty {
                        Text("Nessuna richiesta in attesa.").font(.system(size: 13.5, weight: .bold)).foregroundStyle(Theme.dim).padding(.top, 30)
                    }
                    ForEach(s) { x in
                        NavigationLink { ApprovaSpesaV3(spesa: x) } label: {
                            riga(titolo: euroIT(x.importo) + " · " + (x.descrizione ?? "spesa"), sotto: "\(x.callsign ?? "socio") · \((x.tipo ?? "rimborso"))", colore: Theme.amber)
                        }
                        .buttonStyle(PressStyle())
                    }
                    ForEach(aspiranti) { a in
                        NavigationLink { AspirantiView() } label: {
                            riga(titolo: (a.callsign.isEmpty ? (a.nome ?? "Aspirante") : a.callsign) + " · aspirante", sotto: "uscite di prova \(a.uscite.count) · da votare", colore: Theme.cyan)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .padding(.horizontal, 14).padding(.top, 12)
            }
        }
        .paginaDir()
        .task {
            if Anteprima.attiva { lista = Anteprima.dirSpese; return }
            lista = (try? await JsocClient.shared.speseProposte()) ?? spese
            aspiranti = ((try? await JsocClient.shared.aspiranti())?.aspiranti ?? []).filter { $0.stato == "proposto" }
        }
    }

    func riga(titolo: String, sotto: String, colore: Color) -> some View {
        HStack(spacing: 11) {
            Circle().fill(colore).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(titolo).font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.testo).lineLimit(1)
                Text(sotto).font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(1)
            }
            Spacer(minLength: 0)
            IconaTela(d: Ic.avanti, colore: Color(hex: 0x6F7564), lato: 14)
        }
        .padding(.horizontal, 12).frame(height: 58)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Theme.stroke))
    }
}

// MARK: - Comunicazioni (avvisi e sondaggi)

struct ComunicazioniDir: View {
    @State private var scheda = 0
    var body: some View {
        VStack(spacing: 0) {
            SchedeTela(voci: ["Avvisi", "Sondaggi"], scelta: $scheda).padding(.horizontal, 14).padding(.top, 8)
            if scheda == 0 { BachecaSociView() } else { SondaggiView() }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Comunicazioni").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Altro: le voci meno usate

struct AltroDirettivo: View {
    var body: some View {
        List {
            Section {
                link("books.vertical.fill", "Libro soci", "ammissioni e uscite") { LibroSociView() }
                link("person.3.fill", "Gruppi", "squadre e sottogruppi") { GruppiView() }
                link("person.3.sequence.fill", "Cariche", "chi fa cosa") { CaricheView() }
                link("doc.plaintext.fill", "Ricevute", "emetti e archivia") { RicevuteView() }
                link("building.2.fill", "Riunioni", "direttivo e verbali") { RiunioniView() }
                link("printer.fill", "Stampe", "registri, rendiconto, attestati") { StampeView() }
                link("shippingbox.fill", "Magazzino", "materiale e prestiti") { MagazzinoView() }
            }
            Section {
                link("checklist", "Registro presenze", "uscite e allenamenti") { RegistroPresenzeView() }
                link("eurosign.circle.fill", "Rendiconto", "conti dell'anno") { RendicontoView() }
                link("person.badge.plus", "Domande", "iscrizioni da valutare") { DomandeView() }
                link("doc.text.fill", "Documenti", "statuto, verbali, moduli") { DocumentiAssociazioneView() }
                link("seal.fill", "Dati associazione", "carta intestata, firma") { IntestazioneView() }
            }
        }
        .listaJSOC()
        .navigationTitle("Altro")
    }

    func link<D: View>(_ icona: String, _ t: String, _ s: String, @ViewBuilder _ d: @escaping () -> D) -> some View {
        NavigationLink { d() } label: {
            HStack(spacing: 12) {
                Image(systemName: icona).foregroundStyle(Theme.olive).frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(t).font(.system(size: 15, weight: .bold))
                    Text(s).font(.system(size: 11)).foregroundStyle(Theme.dim)
                }
            }
        }
    }
}
