import SwiftUI
import UniformTypeIdentifiers
import QuickLook

// MARK: - Scheda di un socio vista da un socio: riproduce la tavola SchedaSocioSocio10 (390 pt).
// Solo i contatti: avatar 84, sigla, Chiama/Scrivi, 5 righe (telefono, email, compleanno, città, carica).

struct SchedaSocioSocio: View {
    let socio: JProfilo
    var gruppi: [JGruppo] = []
    @Environment(\.dismiss) private var chiudi
    @Environment(\.openURL) private var apriURL

    static let compleanno: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "d MMMM"; return f }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { chiudi() } label: { TastoTondo(icona: Ic.indietro) }
                .accessibilityLabel("Indietro")
                .padding(.horizontal, 14).padding(.top, 7)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    testa
                    HStack(spacing: 8) {
                        tasto(Ic.telefono, "Chiama", url: socio.telefono.map { "tel:" + $0.filter { $0.isNumber || $0 == "+" } })
                        tasto(Ic.fumetto, "Scrivi", url: socio.telefono.map { "sms:" + $0.filter { $0.isNumber || $0 == "+" } })
                    }
                    VStack(spacing: 0) {
                        riga("Telefono", socio.telefono)
                        riga("Email", socio.email)
                        riga("Compleanno", compleanno)
                        riga("Città", socio.citta)
                        riga("Carica", carica)
                    }
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Theme.stroke))
                    NotaPiede(testo: "Un socio vede solo i contatti. Presenze, quote, assicurazione e dati personali li vede il direttivo. L'attrezzatura è privata: non la vede nessuno. La posizione si vede solo sulla mappa di un evento, e solo da chi ha messo la presenza.")
                }
                .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 30)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { ModuliAperti.shared.aperti += 1 }
        .onDisappear { ModuliAperti.shared.aperti = max(0, ModuliAperti.shared.aperti - 1) }
    }

    // avatar 84, sigla mono 24, nome 13, etichette
    var testa: some View {
        VStack(spacing: 6) {
            AvatarTela(id: VistaSocio.prova ? nil : socio.id, sigla: socio.callsign, lato: 84, testo: 26)
            Text(socio.callsign).font(Theme.mono(24, .heavy)).foregroundStyle(Theme.testo)
            Text(sottotitolo).font(.system(size: 13)).foregroundStyle(Theme.testo2)
            HStack(spacing: 5) {
                Etichetta(testo: NomiAssoc.carica(socio.carica).uppercased(), colore: Theme.oliveBright)
                if let s = socio.specialita, !s.isEmpty { Etichetta(testo: s.uppercased(), colore: Theme.dim) }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8).padding(.bottom, 4)
    }

    var sottotitolo: String {
        var t = nomeBreve(socio.nome, cognome: socio.cognome)
        if let a = socio.ammesso, a.count >= 4 { t += " · socio dal \(a.prefix(4))" }
        return t
    }

    var compleanno: String? {
        guard let n = socio.nascita, let d = FormatoGiorno.f.date(from: String(n.prefix(10))) else { return nil }
        return Self.compleanno.string(from: d)
    }

    var carica: String {
        var t = NomiAssoc.carica(socio.carica)
        let miei = gruppi.filter { socio.gruppi?.contains($0.id) == true }.map(\.nome)
        if let g = miei.first { t += " · gruppo \(g)" }
        return t
    }

    func tasto(_ ic: String, _ t: String, url: String?) -> some View {
        Button {
            haptic()
            if let url, let u = URL(string: url) { apriURL(u) }
        } label: {
            HStack(spacing: 8) {
                IconaTela(d: ic, colore: Theme.oliveBright, lato: 18)
                Text(t).font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.testo)
            }
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.olive.opacity(0.3)))
        }
        .buttonStyle(PressStyle())
        .disabled(url == nil)
    }

    func riga(_ t: String, _ v: String?) -> some View {
        HStack(spacing: 0) {
            Text(t).font(.system(size: 11.5, weight: .bold)).foregroundStyle(Theme.dim).frame(width: 104, alignment: .leading)
            Text(v?.isEmpty == false ? v! : "—").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.testo)
                .lineLimit(1).minimumScaleFactor(0.8)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 46)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.olive.opacity(0.12)).frame(height: 1) }
    }
}

// MARK: - I miei documenti: riproduce la tavola DocumentiSocio10 (390 pt).
// La cartella del socio: stato e scadenze; "Chiedi" sollecita il direttivo per quello che manca
// (la tessera FIGT la carica il direttivo in Intranet); il socio carica i suoi file con Fotografa o Da file / PDF.

/// un documento della cartella del socio (GET /api/io/documenti)
struct JDocSocio: Codable, Identifiable, Hashable {
    var id: String { tipo }
    let tipo: String            // documento, certificato, domanda, privacy, tessera, ricevute, attestati, ...
    let titolo: String
    var dettaglio: String? = nil
    var stato: String           // ok · firmata · manca · scade · scaduto · archivio
    var numero: Int? = nil      // per gli archivi (ricevute, attestati)
    var file: String? = nil     // percorso da scaricare, se c'è
}

extension JsocClient {
    func mieiDocumenti() async throws -> [JDocSocio] { try await get("/api/io/documenti") }
    func sollecitaDocumento(_ tipo: String) async throws { let _: JOk = try await send("/api/io/documenti/\(tipo)/sollecita", "POST", [String: Any]()) }
    func caricaMioDocumento(_ tipo: String, nome: String, dati: Data) async throws {
        try await caricaDati("/api/io/documenti/\(tipo)/file/" + percorsoURL(nome), dati: dati)
    }
}

struct DocumentiSocioView: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @Environment(\.dismiss) private var chiudi
    @State private var docs: [JDocSocio] = []
    @State private var sigla = ""
    @State private var nome = ""
    @State private var errore: String?
    @State private var avviso: String?
    @State private var sceltaTipo: Int?          // 0 = fotografa, 1 = da file
    @State private var tipo = ""
    @State private var fotocamera = false
    @State private var importa = false
    @State private var anteprima: URL?
    @State private var vai: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { chiudi() } label: { TastoTondo(icona: Ic.indietro) }.accessibilityLabel("Indietro")
                Spacer()
                Menu {
                    Button { vai = 3 } label: { Label("Documenti dell'associazione", systemImage: "folder") }
                    Button { vai = 4 } label: { Label("Regolamenti FIGT", systemImage: "book") }
                } label: { TastoTondo(icona: Ic.puntini, lato: 22) }
                .accessibilityLabel("Altre azioni")
            }
            .padding(.horizontal, 14).padding(.top, 7)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        AvatarTela(id: VistaSocio.prova ? nil : jsoc.utente?.id, sigla: sigla, lato: 52, testo: 16)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(sigla).font(Theme.mono(19, .heavy)).foregroundStyle(Theme.testo)
                            Text(sottotitolo).font(.system(size: 12)).foregroundStyle(Theme.testo2).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    schede
                    if let errore { Text(errore).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.red) }
                    if let avviso { Text(avviso).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.oliveBright) }
                    VStack(spacing: 0) { ForEach(docs) { riga($0) } }
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Theme.stroke))
                    HStack(spacing: 8) {
                        tasto(Ic.fotocamera, "Fotografa") { sceltaTipo = 0 }
                        tasto(Ic.scatola, "Da file / PDF") { sceltaTipo = 1 }
                    }
                    NotaPiede(testo: "Ogni socio ha la sua cartella. Il socio la ritrova nel Profilo (riquadro Documenti) e può caricare i suoi file; il direttivo vede stato e scadenze e chiede quelli mancanti con «Chiedi».")
                }
                .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 30)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { ModuliAperti.shared.aperti += 1 }
        .onDisappear { ModuliAperti.shared.aperti = max(0, ModuliAperti.shared.aperti - 1) }
        .navigationDestination(isPresented: Binding(get: { vai != nil }, set: { if !$0 { vai = nil } })) { destinazione }
        .confirmationDialog("Che documento è?", isPresented: Binding(get: { sceltaTipo != nil }, set: { if !$0 { sceltaTipo = nil } }), titleVisibility: .visible) {
            ForEach(docs.filter { $0.stato != "archivio" || $0.tipo == "attestati" }) { d in
                Button(d.titolo) { tipo = d.tipo; let s = sceltaTipo; sceltaTipo = nil; if s == 0 { fotocamera = true } else { importa = true } }
            }
            Button("Altro") { tipo = "altro"; let s = sceltaTipo; sceltaTipo = nil; if s == 0 { fotocamera = true } else { importa = true } }
        }
        .sheet(isPresented: $fotocamera) {
            CameraPicker { img in if let d = img.ridotta(lato: 1800).jpegData(compressionQuality: 0.8) { carica(d, nome: "\(tipo).jpg") } }.ignoresSafeArea()
        }
        .fileImporter(isPresented: $importa, allowedContentTypes: [.pdf, .image]) { r in
            if case .success(let u) = r, u.startAccessingSecurityScopedResource() {
                defer { u.stopAccessingSecurityScopedResource() }
                if let d = try? Data(contentsOf: u) { carica(d, nome: u.lastPathComponent) }
            }
        }
        .quickLookPreview($anteprima)
        .task { await caricaElenco() }
        .refreshable { await caricaElenco() }
    }

    @ViewBuilder var destinazione: some View {
        switch vai ?? 4 {
        case 0: MieiDatiView()
        case 1: MieiDatiView(salute: true)
        case 2: SchedaSocioView(id: jsoc.utente?.id ?? 0)
        case 3: DocumentiAssociazioneView()
        default: DocumentiFIGTView()
        }
    }

    var sottotitolo: String {
        let tot = docs.count
        let ok = docs.filter { !["manca", "scaduto"].contains($0.stato) }.count
        return nome.isEmpty ? "\(ok) di \(tot) documenti in regola" : "\(nome) · \(ok) di \(tot) documenti in regola"
    }

    // schede Dati / Salute / Presenze/quote / Documenti: larghe come il testo, le prime due si dividono il resto (come la tavola)
    var schede: some View {
        HStack(spacing: 0) {
            scheda("Dati", largo: true) { vai = 0 }
            scheda("Salute", largo: true) { vai = 1 }
            scheda("Presenze/quote", largo: false) { vai = 2 }
            Text("Documenti").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.scuro)
                .lineLimit(1).fixedSize().padding(.horizontal, 6).frame(height: 38)
                .background(Theme.testo, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(3)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.stroke))
    }

    @ViewBuilder func scheda(_ t: String, largo: Bool, _ f: @escaping () -> Void) -> some View {
        let testo = Text(t).font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.testo2).lineLimit(1)
        Button { haptic(.soft); f() } label: {
            if largo { testo.frame(maxWidth: .infinity).frame(height: 38).contentShape(Rectangle()) }
            else { testo.fixedSize().padding(.horizontal, 6).frame(height: 38).contentShape(Rectangle()) }
        }
        .buttonStyle(.plain)
    }

    func colore(_ d: JDocSocio) -> Color {
        switch d.stato {
        case "ok", "firmata": return Theme.oliveBright
        case "manca", "scaduto": return Theme.red
        case "scade": return Theme.amber
        default: return Theme.dim
        }
    }

    func segno(_ d: JDocSocio) -> String {
        switch d.stato {
        case "archivio": return "\(d.numero ?? 0)"
        default: return d.stato.uppercased()
        }
    }

    func riga(_ d: JDocSocio) -> some View {
        let c = colore(d)
        return HStack(spacing: 11) {
                IconaTela(d: Ic.file, colore: c, lato: 16)
                    .frame(width: 34, height: 42)
                    .background(c.opacity(0.133), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(c.opacity(0.333)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.titolo).font(.system(size: 13.5, weight: .heavy)).foregroundStyle(Theme.testo).lineLimit(1)
                    if let t = d.dettaglio { Text(t).font(.system(size: 10.5)).foregroundStyle(Theme.dim).lineLimit(1) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(segno(d)).font(Theme.mono(9.5, .heavy)).foregroundStyle(c)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(c.opacity(0.133), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(c.opacity(0.333)))
                if d.stato == "manca" {
                    Button { chiedi(d) } label: {
                        Text("Chiedi").font(.system(size: 11.5, weight: .black)).foregroundStyle(Theme.scuro)
                            .padding(.horizontal, 10).frame(height: 30)
                            .background(Theme.amber, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .frame(minHeight: 56)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.olive.opacity(0.12)).frame(height: 1) }
            .contentShape(Rectangle())
            .onTapGesture { apri(d) }
    }

    func tasto(_ ic: String, _ t: String, _ f: @escaping () -> Void) -> some View {
        Button { haptic(); f() } label: {
            HStack(spacing: 7) {
                IconaTela(d: ic, colore: Theme.testo, lato: 16)
                Text(t).font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.testo)
            }
            .frame(maxWidth: .infinity).frame(height: 46)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.olive.opacity(0.25)))
        }
        .buttonStyle(PressStyle())
    }

    // MARK: azioni

    func chiedi(_ d: JDocSocio) {
        haptic(.soft)
        guard !Anteprima.attiva else { avviso = "Richiesta inviata al direttivo"; return }
        Task {
            do { try await jsoc.sollecitaDocumento(d.tipo); avviso = "Richiesta inviata al direttivo"; errore = nil }
            catch { errore = "Non riesco a inviare la richiesta: il server non la gestisce ancora." }
        }
    }

    func apri(_ d: JDocSocio) {
        switch d.tipo {
        case "certificato": vai = 1
        case "ricevute": vai = 2
        default:
            guard let f = d.file, !Anteprima.attiva else { return }
            Task {
                do {
                    let dati = try await jsoc.scaricaDati(f)
                    let u = FileManager.default.temporaryDirectory.appendingPathComponent((f as NSString).lastPathComponent)
                    try dati.write(to: u, options: .atomic)
                    anteprima = u
                } catch { errore = error.localizedDescription }
            }
        }
    }

    func carica(_ dati: Data, nome: String) {
        guard !Anteprima.attiva else { avviso = "File caricato"; return }
        Task {
            do { try await jsoc.caricaMioDocumento(tipo, nome: nome, dati: dati); avviso = "File caricato"; errore = nil; await caricaElenco() }
            catch { errore = "Caricamento non riuscito: il server non ha ancora la cartella documenti del socio." }
        }
    }

    func caricaElenco() async {
        if VistaSocio.prova { sigla = Anteprima.Socio.viper.callsign; nome = "Simone C."; docs = Anteprima.Socio.documenti; return }
        sigla = jsoc.utente?.callsign ?? ""
        if let d = try? await jsoc.mieiDocumenti() {
            docs = d
            if nome.isEmpty, let p = try? await jsoc.profilo() { nome = nomeBreve(p.nome, cognome: p.cognome) }
            return
        }
        // server senza la cartella documenti: la compongo da profilo e scheda socio
        let p = try? await jsoc.profilo()
        let s = try? await jsoc.schedaSocio(jsoc.utente?.id ?? 0)
        if let p { nome = nomeBreve(p.nome, cognome: p.cognome) }
        docs = DocumentiSocioView.componi(p, s)
    }

    static func componi(_ p: JProfilo?, _ s: JSchedaSocio?) -> [JDocSocio] {
        var v: [JDocSocio] = []
        if let p {
            if let sc = p.certificato_scadenza, !sc.isEmpty {
                let g = p.giorniCertificato ?? 0
                v.append(JDocSocio(tipo: "certificato", titolo: "Certificato medico",
                                   dettaglio: [p.certificato_tipo, "scade \(dataBreve(sc))"].compactMap { $0 }.joined(separator: " · "),
                                   stato: g < 0 ? "scaduto" : g <= 30 ? "scade" : "ok"))
            } else {
                v.append(JDocSocio(tipo: "certificato", titolo: "Certificato medico", dettaglio: "non ancora caricato", stato: "manca"))
            }
        }
        let t = s?.tesseramenti?.max { $0.anno < $1.anno }
        let stag = DatiAssocSocio.stagione()
        if let t, t.intranet == 1 {
            v.append(JDocSocio(tipo: "tessera", titolo: "Tessera FIGT \(stag)", dettaglio: t.numero.map { "n. \($0)" } ?? "caricata in Intranet", stato: "ok"))
        } else {
            v.append(JDocSocio(tipo: "tessera", titolo: "Tessera FIGT \(stag)", dettaglio: "non ancora caricata in Intranet", stato: "manca"))
        }
        let pagate = (s?.quote ?? []).filter { $0.pagata == 1 }.map(\.anno).sorted(by: >)
        if !pagate.isEmpty || s != nil {
            v.append(JDocSocio(tipo: "ricevute", titolo: "Ricevute quote",
                               dettaglio: pagate.isEmpty ? "nessuna ancora" : pagate.prefix(3).map(String.init).joined(separator: " · "),
                               stato: "archivio", numero: pagate.count))
        }
        return v
    }

    static func dataBreve(_ s: String) -> String {
        guard let d = FormatoGiorno.f.date(from: String(s.prefix(10))) else { return s }
        let c = Calendar.current.dateComponents([.day, .month, .year], from: d)
        return "\(c.day ?? 0)/\(c.month ?? 0)/\(c.year ?? 0)"
    }
}
