import SwiftUI

// MARK: - Associazione, vista del socio normale: riproduce la tavola Associazione10 (390 pt).
// Tessera FIGT, avviso da confermare, assemblea, 9 riquadri (3 colonne, alti 84), nota in fondo.
// Il pulsante "+ Spesa" apre la proposta di spesa (tavola SpesaSocio10).

/// Chi vede la vista del socio: chi non è nel direttivo e non ha aree di gestione.
/// Anteprime: `-debug.socio.vista YES` la forza anche per l'utente di prova (che è del direttivo).
enum VistaSocio {
    static var forzata: Bool { UserDefaults.standard.bool(forKey: "debug.socio.vista") }
    @MainActor static var attiva: Bool {
        if forzata { return true }
        return !(JsocClient.shared.utente?.direttivo == true || PermessiStore.shared.gestione)
    }
    /// `-debug.socio.apri spesa|scheda|documenti` apre direttamente quella schermata
    static var apri: String { UserDefaults.standard.string(forKey: "debug.socio.apri") ?? "" }
    /// anteprime: dati finti della vista socio (VIPER), come le tavole
    static var prova: Bool { Anteprima.attiva && forzata }
}

/// colori della tela usati solo da queste tavole
enum TelaSocio {
    static let tessera = Color(hex: 0x1D2416)
    static let avatar = Color(hex: 0x3A4428)
    static let odg = Color(hex: 0xD8DCCD)
    static let nota = Color(hex: 0xE9DCC0)
}

/// Iniziali come le tavole: VIPER → VP (prima lettera + prima consonante dopo)
func inizialiSigla(_ s: String) -> String {
    let c = Array(s.uppercased().filter(\.isLetter))
    guard let p = c.first else { return "?" }
    let dopo = c.dropFirst().first { !"AEIOU".contains($0) } ?? c.dropFirst().first
    return String(p) + (dopo.map { String($0) } ?? "")
}

/// "Simone Conte" → "Simone C."
func nomeBreve(_ nome: String, cognome: String? = nil) -> String {
    let p = nome.split(separator: " ").map(String.init)
    guard let primo = p.first else { return nome }
    let cog = (cognome?.isEmpty == false ? cognome : (p.count > 1 ? p.last : nil)) ?? ""
    return cog.isEmpty ? primo : "\(primo) \(cog.prefix(1))."
}

/// avatar della tela: cerchio #3a4428, bordo verde 2, iniziali bianche; la foto del socio se c'è
struct AvatarTela: View {
    let id: Int?
    let sigla: String
    var lato: CGFloat = 52
    var testo: CGFloat = 16
    @State private var img: UIImage?
    var body: some View {
        ZStack {
            Circle().fill(TelaSocio.avatar)
            if let img { Image(uiImage: img).resizable().scaledToFill() }
            else { Text(inizialiSigla(sigla)).font(.system(size: testo, weight: .black)).foregroundStyle(Theme.testo) }
        }
        .frame(width: lato, height: lato)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.olive, lineWidth: 2))
        .task(id: id) {
            guard let id, !Anteprima.attiva else { return }
            let cache = EventoStore.cartella.appendingPathComponent("foto_\(id).jpg")
            if let d = try? Data(contentsOf: cache), let i = UIImage(data: d) { img = i }
            if let d = try? await JsocClient.shared.scaricaDati("/api/utenti/\(id)/foto"), let i = UIImage(data: d) { img = i }
        }
    }
}

/// tasto tondo 42 della tela (indietro, altre azioni)
struct TastoTondo: View {
    let icona: String
    var lato: CGFloat = 18
    var body: some View {
        IconaTela(d: icona, colore: Theme.testo, lato: lato)
            .frame(width: 42, height: 42).background(Theme.surface, in: Circle()).overlay(Circle().strokeBorder(Theme.stroke))
    }
}

/// nota grigia centrata in fondo alle tavole
struct NotaPiede: View {
    let testo: String
    var interlinea: CGFloat = 2.2
    var body: some View {
        Text(testo).font(.system(size: 10.5)).foregroundStyle(Theme.dim).multilineTextAlignment(.center).lineSpacing(interlinea)
            .frame(maxWidth: .infinity)
    }
}

// MARK: dati mostrati

struct DatiAssocSocio {
    struct Valore { var testo: String; var colore: Color }
    struct Assemblea { let id: Int; let titolo: String; let quando: String; let odg: String; var mia: String? }
    var stagione = ""
    var statoTessera: Valore?
    var certificato = Valore(testo: "—", colore: Theme.dim)
    var annoQuota = Calendar.current.component(.year, from: Date())
    var quota = Valore(testo: "—", colore: Theme.dim)
    var presenze = Valore(testo: "—", colore: Theme.dim)
    var avviso: (id: Int, titolo: String)?
    var assemblea: Assemblea?
    var avvisiNuovi = 0
    var soci = 0
    var sondaggi = 0

    /// stagione FIGT: da settembre si parla della stagione che inizia (2026/27)
    static func stagione(_ d: Date = Date()) -> String {
        let c = Calendar.current
        let y = c.component(.year, from: d), m = c.component(.month, from: d)
        let a = m >= 9 ? y : y - 1
        return "\(a)/\(String(a + 1).suffix(2))"
    }

    static let formatoQuando: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "d MMM · HH:mm"; return f }()
    static let leggi: [DateFormatter] = ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"].map {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = $0; return f
    }
    static func quando(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "" }
        for f in leggi {
            if let d = f.date(from: String(s.prefix(f.dateFormat.replacingOccurrences(of: "'", with: "").count))) {
                return formatoQuando.string(from: d).replacingOccurrences(of: ".", with: "").uppercased()
            }
        }
        return s
    }
}

// MARK: - Schermata

struct AssociazioneSocio: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var home = HomeModel.shared
    @State private var d = DatiAssocSocio()
    @State private var spesa = VistaSocio.apri == "spesa"
    @State private var scheda = VistaSocio.apri == "scheda"
    @State private var documenti = VistaSocio.apri == "documenti"
    @State private var delega = false
    @State private var sociDelega: [JSocioLibro] = []
    @State private var assembleaVera: JAssemblea?

    var body: some View {
        let _ = Contatori.disegno("AssociazioneSocio")
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                testata.padding(.horizontal, 16).padding(.top, 7)
                VStack(spacing: 9) {
                    tessera
                    if let a = d.avviso { avvisoCard(a) }
                    if let a = d.assemblea { assembleaCard(a) }
                    griglia
                    NotaPiede(testo: "Vedi solo documenti, assemblee e rendiconti rivolti a tutti i soci o che riguardano te.", interlinea: 1.9)
                }
                .padding(.horizontal, 14).padding(.top, 14)
            }
            .padding(.bottom, 96)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $spesa) { SpesaSocioView() }
        .navigationDestination(isPresented: $scheda) { SchedaSocioSocio(socio: Anteprima.Socio.viper, gruppi: Anteprima.Socio.gruppi) }
        .navigationDestination(isPresented: $documenti) { DocumentiSocioView() }
        .sheet(isPresented: $delega) {
            if let a = assembleaVera { DelegaSheet(assemblea: a, soci: sociDelega) { assembleaVera = $0; d.assemblea?.mia = statoAssemblea($0) } }
        }
        .task { await carica() }
        .refreshable { await carica() }
    }

    // MARK: intestazione: "Associazione" 26 nero, sotto 11,5 grigio, "+ Spesa" alto 40

    var testata: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Associazione").font(.system(size: 26, weight: .black)).foregroundStyle(Theme.testo)
                Text("BAS JSOC · FIGT · Comitato Puglia e Basilicata").font(.system(size: 11.5)).foregroundStyle(Theme.dim).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { haptic(); spesa = true } label: {
                HStack(spacing: 5) {
                    IconaTela(d: Ic.piu, colore: Theme.scuro, lato: 15)
                    Text("Spesa").font(.system(size: 13, weight: .black)).foregroundStyle(Theme.scuro)
                }
                .padding(.horizontal, 13).frame(height: 40)
                .background(Theme.olive, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Proponi una spesa")
        }
    }

    // MARK: tessera FIGT (fondo #1d2416, bordo verde 35%, angoli 18)

    var tessera: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("LA MIA TESSERA FIGT \(d.stagione)").font(.system(size: 10.5, weight: .heavy)).tracking(1.1).foregroundStyle(Theme.oliveBright)
                Spacer(minLength: 6)
                if let s = d.statoTessera { Etichetta(testo: s.testo, colore: s.colore) }
            }
            HStack(spacing: 8) {
                casella("CERTIFICATO", d.certificato)
                casella("QUOTA \(String(d.annoQuota))", d.quota)
                casella("PRESENZE", d.presenze)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(TelaSocio.tessera, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.olive.opacity(0.35)))
    }

    func casella(_ t: String, _ v: DatiAssocSocio.Valore) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(t).font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.dim).lineLimit(1)
            Text(v.testo).font(.system(size: 12, weight: .heavy)).foregroundStyle(v.colore).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    // MARK: avviso da confermare (bordo ambra 45%)

    func avvisoCard(_ a: (id: Int, titolo: String)) -> some View {
        HStack(spacing: 11) {
            IconaTela(d: Ic.invia, colore: Theme.amber, lato: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(a.titolo).font(.system(size: 13.5, weight: .heavy)).foregroundStyle(Theme.testo).lineLimit(1)
                Text("Avviso del direttivo · conferma la lettura").font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                haptic(.soft)
                Task {
                    if !Anteprima.attiva { await jsoc.letto(a.id); await home.aggiorna() }
                    withAnimation(.easeOut(duration: 0.2)) { d.avviso = nil }
                }
            } label: {
                Text("Ho letto").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.scuro)
                    .padding(.horizontal, 12).frame(height: 34).background(Theme.amber, in: Capsule())
            }
            .buttonStyle(PressStyle())
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Theme.amber.opacity(0.45)))
    }

    // MARK: assemblea

    func assembleaCard(_ a: DatiAssocSocio.Assemblea) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink { AssembleaView(id: a.id) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(a.titolo).font(.system(size: 10.5, weight: .heavy)).tracking(1.1).foregroundStyle(Theme.dim).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(a.quando).font(Theme.mono(11.5, .medium)).foregroundStyle(Theme.oliveBright)
                    }
                    Text(a.odg).font(.system(size: 12.5)).foregroundStyle(TelaSocio.odg).lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                Button { rispondiAssemblea(a) } label: {
                    Text(a.mia == "presente" ? "Ci sarai ✓" : "Ci sarò").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.scuro)
                        .frame(maxWidth: .infinity).frame(height: 36)
                        .background(Theme.olive, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                Button { apriDelega() } label: {
                    Text(a.mia.map { $0.hasPrefix("delega") ? "Hai delegato \($0.dropFirst(7))" : "Delego un socio" } ?? "Delego un socio")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.testo).lineLimit(1)
                        .frame(maxWidth: .infinity).frame(height: 36)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.olive.opacity(0.3)))
                }
            }
            .buttonStyle(PressStyle())
            .padding(.top, 8)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Theme.stroke))
    }

    func rispondiAssemblea(_ a: DatiAssocSocio.Assemblea) {
        haptic(.soft)
        guard !Anteprima.attiva else { d.assemblea?.mia = "presente"; return }
        Task {
            if let n = try? await jsoc.presenzaAssemblea(a.id, ["stato": "presente"]) { assembleaVera = n; d.assemblea?.mia = statoAssemblea(n) }
        }
    }

    func apriDelega() {
        guard !Anteprima.attiva else { return }
        Task { sociDelega = (try? await jsoc.libroSoci()) ?? []; delega = assembleaVera != nil }
    }

    func statoAssemblea(_ a: JAssemblea) -> String? {
        guard let m = a.mia else { return nil }
        return m.stato == "delega" ? "delega:\(m.delegato_cs ?? "")" : m.stato
    }

    // MARK: 9 riquadri, 3 colonne, alti 84, spazio 7

    var griglia: some View {
        let id = jsoc.utente?.id ?? 0
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
            riquadro(Ic.foglioRighe, Theme.oliveBright, "Avvisi", d.avvisiNuovi > 0 ? "\(d.avvisiNuovi) nuovi" : "tutto letto") { BachecaSociView() }
            riquadro(Ic.soci, Theme.oliveBright, "Soci", d.soci > 0 ? "\(d.soci) · rubrica" : "rubrica") { SociView() }
            riquadro(Ic.sondaggio, Theme.cyan, "Sondaggi", d.sondaggi > 0 ? "\(d.sondaggi) da votare" : "nessuno aperto") { SondaggiView() }
            riquadro(Ic.magazzino, Theme.cyan, "Magazzino", "materiale e prestiti") { MagazzinoView() }
            riquadro(Ic.file, Theme.dim, "Documenti", "statuto e i tuoi") { DocumentiSocioView() }
            riquadro(Ic.dollaro, Theme.amber, "Rendiconto", "approvato in assemblea") { RendicontoView() }
            riquadro(Ic.sede, Theme.oliveBright, "Assemblee", "convocazioni per tutti") { AssembleeView() }
            riquadro(Ic.carta, Theme.amber, "Le mie quote", "scadenze e ricevute") { SchedaSocioView(id: id) }
            riquadro(Ic.stella, Theme.dim, "Iscrizione e polizza", "domanda, assicurazione") { IscrizionePolizzaView() }
        }
    }

    func riquadro<D: View>(_ icona: String, _ colore: Color, _ titolo: String, _ sotto: String, @ViewBuilder dest: @escaping () -> D) -> some View {
        NavigationLink { dest() } label: {
            VStack(alignment: .leading, spacing: 0) {
                IconaTela(d: icona, colore: colore, lato: 19)
                Spacer(minLength: 0)
                Text(titolo).font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.testo).lineLimit(2).multilineTextAlignment(.leading)
                Text(sotto).font(.system(size: 10)).foregroundStyle(Theme.dim).lineLimit(1).padding(.top, 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 9)
            .frame(height: 84)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Theme.stroke))
        }
        .buttonStyle(PressStyle())
    }

    // MARK: dati

    func carica() async {
        if VistaSocio.prova { d = Anteprima.Socio.associazione; return }
        var n = DatiAssocSocio()
        n.stagione = DatiAssocSocio.stagione()
        let anno = Calendar.current.component(.year, from: Date())
        let p = try? await jsoc.profilo()
        let s = try? await jsoc.schedaSocio(jsoc.utente?.id ?? 0)
        let ba = try? await jsoc.bacheca()
        let asse = try? await jsoc.assemblee()
        await home.aggiorna()
        // certificato: rosso entro 30 giorni o scaduto
        if let g = p?.giorniCertificato {
            n.certificato = g < 0 ? .init(testo: "scaduto", colore: Theme.red)
                : g <= 30 ? .init(testo: g == 0 ? "scade oggi" : "scade tra \(g) g", colore: Theme.red)
                : .init(testo: "valido", colore: Theme.oliveBright)
        } else { n.certificato = .init(testo: "da caricare", colore: Theme.red) }
        // quota: l'ultima dell'elenco
        if let q = (p?.quote ?? []).max(by: { $0.anno < $1.anno }) ?? (s?.quote ?? []).max(by: { $0.anno < $1.anno }).map({ JQuotaMia(anno: $0.anno, importo: $0.importo, pagata: $0.pagata, data: $0.data) }) {
            n.annoQuota = q.anno
            n.quota = q.pagata == 1 ? .init(testo: "pagata", colore: Theme.oliveBright)
                : .init(testo: "da pagare" + (q.importo.map { " · \(Int($0)) €" } ?? ""), colore: Theme.amber)
        }
        n.presenze = .init(testo: "\(s?.statistiche?.presenze ?? 0) nel \(anno)", colore: Theme.oliveBright)
        let tess = s?.tesseramenti?.max { $0.anno < $1.anno }
        if let t = tess {
            n.statoTessera = t.intranet == 1 ? .init(testo: "ASSICURATO", colore: Theme.oliveBright)
                : t.figt == 1 ? .init(testo: "IN ATTESA", colore: Theme.amber) : .init(testo: "NON TESSERATO", colore: Theme.red)
        }
        if let b = ba {
            if let a = b.first(where: { $0.chiedeConferma && !$0.letto }) { n.avviso = (a.id, a.titolo?.isEmpty == false ? a.titolo! : "Avviso del direttivo") }
        }
        if let a = asse?.first(where: { $0.stato != "chiusa" }) {
            assembleaVera = a
            n.assemblea = .init(id: a.id, titolo: "ASSEMBLEA \(a.tipo.uppercased())", quando: DatiAssocSocio.quando(a.data),
                                odg: a.odg.map(\.titolo).joined(separator: " · "), mia: statoAssemblea(a))
        }
        n.avvisiNuovi = home.dati?.post_nuovi ?? 0
        n.soci = home.dati?.soci_attivi ?? 0
        n.sondaggi = home.dati?.sondaggi_aperti ?? 0
        d = n
    }
}

// MARK: - Iscrizione e polizza (riquadro della griglia): domanda, assicurazione, regolamenti FIGT

struct IscrizionePolizzaView: View {
    var body: some View {
        List {
            NavigationLink { DomandaIscrizioneView() } label: { voce(Ic.documento, "Domanda di iscrizione", "compila e firma") }
                .listRowBackground(Theme.surface)
            NavigationLink { AssicurazioneView() } label: { voce(Ic.scudo, "Assicurazione", "polizza FIGT e infortuni") }
                .listRowBackground(Theme.surface)
            NavigationLink { DocumentiFIGTView() } label: { voce(Ic.libro, "Regolamenti FIGT", "cerca nei documenti federali") }
                .listRowBackground(Theme.surface)
        }
        .listaJSOC()
        .navigationTitle("Iscrizione e polizza")
    }

    func voce(_ ic: String, _ t: String, _ s: String) -> some View {
        HStack(spacing: 12) {
            IconaTela(d: ic, colore: Theme.oliveBright, lato: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(t).font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.testo)
                Text(s).font(.system(size: 12)).foregroundStyle(Theme.dim)
            }
        }
    }
}
