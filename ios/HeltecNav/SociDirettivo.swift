import SwiftUI

// MARK: - Soci (tavola 48) e scheda del socio vista dal direttivo (tavola 49).
// Misure, colori e testi delle tavole Soci10 e SchedaSocio10 della tela.

/// anno delle quote: da novembre si incassa la quota dell'anno dopo (tavole: a novembre 2026 "quota 2027")
enum AnnoDir {
    static var corrente: Int { Calendar.current.component(.year, from: Date()) }
    static var quota: Int { corrente + (Calendar.current.component(.month, from: Date()) >= 11 ? 1 : 0) }
}

/// "Giorgio Pascali" → "Giorgio P."
func nomeBreveDir(_ n: String?) -> String {
    let p = (n ?? "").split(separator: " ")
    guard let primo = p.first else { return "" }
    guard p.count > 1, let c = p.last?.first else { return String(primo) }
    return "\(primo) \(c)."
}

/// sigla dell'avatar dal callsign: prima lettera + prima consonante dopo (RAVEN → RV, WOLF → WL)
func siglaDir(_ cs: String) -> String {
    let l = Array(cs.uppercased().filter(\.isLetter))
    guard let a = l.first else { return "?" }
    let b = l.dropFirst().first { !"AEIOU".contains($0) } ?? l.dropFirst().first
    return String(a) + (b.map(String.init) ?? "")
}

struct StatoDir: Hashable { let testo: String; let colore: Color }

struct SocioRigaDir: Identifiable, Hashable {
    let id: Int
    var callsign: String
    var nome: String
    var sigla: String
    var carica: String
    var assicurato = true
    var giorniCertificato: Int? = nil
    var quotaDaPagare = false
    var aspirante = false
    var uscite = 0
    var usciteRichieste = 3
    var telefono: String? = nil
    var rango = 5

    var stati: [StatoDir] {
        if aspirante { return [StatoDir(testo: "\(uscite) uscite su \(usciteRichieste)", colore: Theme.cyan)] }
        var s = [assicurato ? StatoDir(testo: "assicurato", colore: Theme.oliveBright) : StatoDir(testo: "non assicurato", colore: Theme.red)]
        if let g = giorniCertificato, g <= 30 { s.append(StatoDir(testo: g < 0 ? "certificato scaduto" : "certificato \(g) g", colore: Theme.red)) }
        if quotaDaPagare { s.append(StatoDir(testo: "quota \(AnnoDir.quota)", colore: Theme.amber)) }
        return s
    }
}

/// avatar della tela: tondo #2a3320, sigla 12 bianca (foto del socio se c'è)
struct AvatarDir: View {
    let id: Int
    let sigla: String
    var lato: CGFloat = 38
    var testo: CGFloat = 12
    var fondo = Color(hex: 0x2A3320)
    @State private var img: UIImage?
    var body: some View {
        ZStack {
            Circle().fill(fondo)
            if let img { Image(uiImage: img).resizable().scaledToFill() } else {
                Text(sigla).font(.system(size: testo, weight: .heavy)).foregroundStyle(Theme.testo)
            }
        }
        .frame(width: lato, height: lato).clipShape(Circle())
        .task(id: id) {
            guard !Anteprima.attiva, id > 0 else { return }
            let cache = EventoStore.cartella.appendingPathComponent("foto_\(id).jpg")
            if let d = try? Data(contentsOf: cache), let i = UIImage(data: d) { img = i }
            if let d = try? await JsocClient.shared.scaricaDati("/api/utenti/\(id)/foto"), let i = UIImage(data: d) {
                img = i; try? d.write(to: cache, options: .atomic)
            }
        }
    }
}

// MARK: - Elenco soci (tavola 48)

struct SociDirettivoV3: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @Environment(\.openURL) private var apriURL
    @State private var righe: [SocioRigaDir] = []
    @State private var totale: Int?
    @State private var filtro = 0
    @State private var cerca = ""
    @State private var aperto: Int?
    @State private var trascina: CGFloat = 0
    @State private var scelto: SocioRigaDir?
    @State private var invita = false
    @State private var avviso: String?
    @State private var dimostrazione: SocioRigaDir?

    var visibili: [SocioRigaDir] {
        righe.filter { r in
            switch filtro {
            case 1: if r.aspirante || r.assicurato { return false }
            case 2: if !r.quotaDaPagare { return false }
            case 3: if !r.aspirante { return false }
            default: break
            }
            if cerca.isEmpty { return true }
            return "\(r.callsign) \(r.nome) \(r.carica)".localizedCaseInsensitiveContains(cerca)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TestataDir(titolo: "Soci") {
                Button { invita = true } label: {
                    HStack(spacing: 5) {
                        IconaTela(d: Ic.qr, colore: Theme.scuro, lato: 15)
                        Text("Invita").font(.system(size: 13, weight: .black))
                    }
                    .foregroundStyle(Theme.scuro).padding(.horizontal, 12).frame(height: 38)
                    .background(Theme.olive, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            ScrollView {
                VStack(spacing: 9) {
                    ricerca.padding(.horizontal, 14)
                    filtri
                    elenco.padding(.horizontal, 14)
                    if let d = dimostrazione {
                        riga(d, apertura: -150)
                            .background(Color(hex: 0x2B3A1F))
                            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                            .padding(.horizontal, 14)
                    }
                    Text("Scorri un socio verso sinistra: Chiama · Scrivi. Toccalo per la scheda completa.")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity).padding(.horizontal, 14)
                }
                .padding(.top, 12).padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
        }
        .paginaDir()
        .navigationDestination(isPresented: Binding(get: { scelto != nil }, set: { if !$0 { scelto = nil } })) {
            if let s = scelto { SchedaSocioDirettivo(id: s.id, sigla: s.sigla, aspirante: s.aspirante) }
        }
        .sheet(isPresented: $invita) { InvitoSheet() }
        .alert(avviso ?? "", isPresented: Binding(get: { avviso != nil }, set: { if !$0 { avviso = nil } })) { Button("OK") {} }
        .task { await carica() }
    }

    // MARK: ricerca (alta 42) e filtri (capsule 32)

    var ricerca: some View {
        HStack(spacing: 8) {
            IconaTela(d: Ic.cerca, colore: Theme.dim, lato: 16)
            ZStack(alignment: .leading) {
                if cerca.isEmpty { Text("Cerca per callsign, nome, carica").font(.system(size: 14)).foregroundStyle(Color(hex: 0x7D8470)) }
                TextField("", text: $cerca).font(.system(size: 14)).foregroundStyle(Theme.testo)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
        }
        .padding(.horizontal, 12).frame(height: 42)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.stroke))
    }

    var filtri: some View {
        let soci = righe.filter { !$0.aspirante }
        let voci = ["Tutti · \(totale ?? righe.count)",
                    "Non assicurati · \(soci.filter { !$0.assicurato }.count)",
                    "Quote · \(soci.filter(\.quotaDaPagare).count)",
                    "Aspiranti"]
        return ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(voci.indices, id: \.self) { i in
                    Button { haptic(.soft); filtro = i; aperto = nil } label: { ChipDir(testo: voci[i], scelto: filtro == i) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: elenco (righe 58, separatore da 61)

    var elenco: some View {
        let v = visibili
        return VStack(spacing: 0) {
            if v.isEmpty {
                Text(righe.isEmpty ? "Carico i soci…" : "Nessun socio").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.dim).frame(height: 58)
            }
            ForEach(Array(v.enumerated()), id: \.element.id) { i, r in
                if i > 0 { Rectangle().fill(Theme.olive.opacity(0.13)).frame(height: 1).padding(.leading, 61) }
                riga(r, apertura: aperto == r.id ? -150 : 0)
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Theme.stroke))
    }

    func riga(_ r: SocioRigaDir, apertura: CGFloat) -> some View {
        let spostamento = min(0, max(-150, apertura + (aperto == r.id || apertura == 0 ? trascinaPer(r) : 0)))
        return ZStack(alignment: .trailing) {
            if spostamento < 0 {
                HStack(spacing: 0) {
                    azione(Ic.telefono, "Chiama", Color(hex: 0x3A6F8F)) { chiama(r, sms: false) }
                    azione(Ic.fumetto, "Scrivi", Color(hex: 0x6B7A3A)) { chiama(r, sms: true) }
                }
                .frame(width: 150)
            }
            contenutoRiga(r)
                .background(spostamento < 0 ? Color(hex: 0x2B3A1F) : Theme.surface)
                .offset(x: spostamento)
                .contentShape(Rectangle())
                .onTapGesture {
                    if aperto != nil { withAnimation(.spring(response: 0.3)) { aperto = nil } } else { haptic(); scelto = r }
                }
                .gesture(
                    DragGesture(minimumDistance: 18)
                        .onChanged { g in
                            guard abs(g.translation.width) > abs(g.translation.height) else { return }
                            if aperto != r.id && aperto != nil { aperto = nil }
                            trascinaId = r.id; trascina = g.translation.width
                        }
                        .onEnded { g in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                let base: CGFloat = aperto == r.id ? -150 : 0
                                aperto = base + g.translation.width < -70 ? r.id : nil
                                trascina = 0; trascinaId = nil
                            }
                        }
                )
        }
        .frame(height: 58)
        .clipped()
    }

    @State private var trascinaId: Int?
    func trascinaPer(_ r: SocioRigaDir) -> CGFloat { trascinaId == r.id ? trascina : 0 }

    func contenutoRiga(_ r: SocioRigaDir) -> some View {
        HStack(spacing: 11) {
            AvatarDir(id: r.aspirante ? 0 : r.id, sigla: r.sigla)
            VStack(alignment: .leading, spacing: 3) {
                (Text(r.callsign).font(Theme.mono(14, .heavy)).foregroundColor(Theme.testo)
                 + Text(" ").font(.system(size: 12))
                 + Text(r.nome).font(.system(size: 12)).foregroundColor(Theme.dim))
                    .lineLimit(1)
                HStack(spacing: 9) {
                    ForEach(r.stati, id: \.self) { s in
                        HStack(spacing: 4) {
                            Circle().fill(s.colore).frame(width: 6, height: 6)
                            Text(s.testo).font(.system(size: 10, weight: .heavy)).foregroundStyle(s.colore)
                        }
                    }
                }
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(r.carica).font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.dim).fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity).frame(height: 58)
    }

    func azione(_ icona: String, _ testo: String, _ colore: Color, _ fai: @escaping () -> Void) -> some View {
        Button(action: fai) {
            VStack(spacing: 2) {
                IconaTela(d: icona, colore: .white, lato: 16)
                Text(testo).font(.system(size: 10.5, weight: .heavy)).foregroundStyle(Theme.testo)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(colore)
        }
        .buttonStyle(.plain)
    }

    func chiama(_ r: SocioRigaDir, sms: Bool) {
        let n = (r.telefono ?? "").filter { $0.isNumber || $0 == "+" }
        guard !n.isEmpty, let u = URL(string: (sms ? "sms:" : "tel:") + n) else { avviso = "\(r.callsign) non ha un numero di telefono nella scheda."; return }
        apriURL(u)
        withAnimation { aperto = nil }
    }

    // MARK: dati: tesseramento dell'anno (assicurazione, certificato), quote dell'anno delle quote, aspiranti, telefoni dal libro soci

    func carica() async {
        if Anteprima.attiva {
            righe = Anteprima.dirSoci; totale = 18
            if let s = DebugDir.scorri, let i = righe.firstIndex(where: { $0.callsign == s }) { dimostrazione = righe.remove(at: i) }
            return
        }
        // stagione delle quote: da novembre quella dell anno dopo (assicurazione e quota della stessa stagione, come le tavole)
        guard let t = try? await jsoc.tesseramento(AnnoDir.quota) else { avviso = "Non riesco a leggere i soci dal server."; return }
        let libro = (try? await jsoc.libroSoci()) ?? []
        let asp = try? await jsoc.aspiranti()
        let ordine = ["presidente": 0, "vicepresidente": 1, "segretario": 2, "tesoriere": 3, "consigliere": 4]
        var n: [SocioRigaDir] = t.soci.filter { ($0.stato_socio ?? "socio") != "aspirante" }.map { s in
            let carica = s.carica.flatMap { $0.isEmpty ? nil : $0 }
            return SocioRigaDir(id: s.utente, callsign: s.callsign, nome: nomeBreveDir(s.nome), sigla: siglaDir(s.callsign),
                                carica: (carica.map { NomiAssoc.carica($0) } ?? "Socio").uppercased(),
                                assicurato: s.intranet, giorniCertificato: s.giorni_certificato,
                                quotaDaPagare: !s.quota,
                                telefono: libro.first { $0.id == s.utente }?.telefono, rango: carica.flatMap { ordine[$0] } ?? 5)
        }
        n.sort { ($0.rango, $0.callsign) < ($1.rango, $1.callsign) }
        for a in asp?.aspiranti ?? [] where a.stato != "respinto" {
            let cs = a.callsign.isEmpty ? (a.nome ?? "Aspirante").split(separator: " ").first.map(String.init) ?? "Aspirante" : a.callsign
            n.append(SocioRigaDir(id: a.id, callsign: cs, nome: "aspirante", sigla: siglaDir(cs), carica: "ASPIRANTE",
                                  aspirante: true, uscite: a.uscite.count, usciteRichieste: asp?.uscite_richieste ?? 3,
                                  telefono: libro.first { $0.id == a.id }?.telefono, rango: 9))
        }
        righe = n; totale = nil
    }
}

// MARK: - Scheda del socio vista dal direttivo (tavola 49)

/// scheda dal server con i campi in più che servono al direttivo (conto e ricevuta delle quote, salute)
struct JSchedaDir: Codable {
    struct Quota: Codable, Hashable {
        let anno: Int
        var importo: Double? = nil
        var pagata: Int? = nil
        var data: String? = nil
        var conto: String? = nil
        var ricevuta: String? = nil
    }
    let id: Int
    var nome: String
    var callsign: String
    var ruolo: String? = nil
    var telefono: String? = nil
    var email: String? = nil
    var nascita: String? = nil
    var luogo_nascita: String? = nil
    var cf: String? = nil
    var indirizzo: String? = nil
    var cap: String? = nil
    var citta: String? = nil
    var provincia: String? = nil
    var gruppo_sanguigno: String? = nil
    var emergenza: String? = nil
    var certificato_scadenza: String? = nil
    var certificato_tipo: String? = nil
    var allergie: String? = nil
    var farmaci: String? = nil
    var carica: String? = nil
    var stato_socio: String? = nil
    var ammesso: String? = nil
    var specialita: String? = nil
    var gruppi: [String]? = nil
    var quote: [Quota]? = nil
    var tesseramenti: [JSchedaSocio.Tessera]? = nil
    var eventi: [JSchedaSocio.Evento]? = nil
    var statistiche: JSchedaSocio.Stat? = nil
}

/// schede a larghezza "flex" della tela: ognuna almeno larga quanto il suo testo, il resto diviso in parti uguali
struct FlessUguale: SwiftUI.Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let h = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? subviews.reduce(0) { $0 + $1.sizeThatFits(.unspecified).width }, height: h)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let w = larghezze(b.width, subviews.map { $0.sizeThatFits(.unspecified).width })
        var x = b.minX
        for (i, s) in subviews.enumerated() {
            s.place(at: CGPoint(x: x, y: b.minY), proposal: ProposedViewSize(width: w[i], height: b.height))
            x += w[i]
        }
    }
    /// algoritmo flex: 1 1 0 con min-width = contenuto
    func larghezze(_ tot: CGFloat, _ minimi: [CGFloat]) -> [CGFloat] {
        var fisse = [Int: CGFloat]()
        while true {
            let libere = minimi.indices.filter { fisse[$0] == nil }
            guard !libere.isEmpty else { break }
            let quota = (tot - fisse.values.reduce(0, +)) / CGFloat(libere.count)
            let troppo = libere.filter { minimi[$0] > quota }
            if troppo.isEmpty { return minimi.indices.map { fisse[$0] ?? quota } }
            for i in troppo { fisse[i] = minimi[i] }
        }
        return minimi.indices.map { fisse[$0] ?? minimi[$0] }
    }
}

struct SchedeFlessDir: View {
    let voci: [String]
    @Binding var scelta: Int
    var body: some View {
        FlessUguale {
            ForEach(voci.indices, id: \.self) { i in
                Button { haptic(.soft); withAnimation(.easeOut(duration: 0.15)) { scelta = i } } label: {
                    Text(voci[i]).font(.system(size: 13, weight: .heavy)).lineLimit(1).fixedSize()
                        .padding(.horizontal, 6)   // tela: i bottoni hanno 6 di margine interno (min-content)
                        .foregroundStyle(i == scelta ? Theme.scuro : Theme.testo2)
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .background(i == scelta ? Theme.testo : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.stroke))
    }
}

struct SchedaSocioDirettivo: View {
    let id: Int
    var sigla: String? = nil
    var aspirante = false
    @ObservedObject private var jsoc = JsocClient.shared
    @Environment(\.openURL) private var apriURL
    @State private var s: JSchedaDir?
    @State private var scheda = 2
    @State private var errore: String?
    @State private var registra: JSchedaDir.Quota?
    @State private var lavoro = false
    @State private var vai: Int?

    static let mesi = ["G", "F", "M", "A", "M", "G", "L", "A", "S", "O", "N", "D"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TestataDir(titolo: "") {
                Menu {
                    if let t = s?.telefono, !t.isEmpty {
                        Button { apri("tel:", t) } label: { Label("Chiama", systemImage: "phone") }
                        Button { apri("sms:", t) } label: { Label("Scrivi", systemImage: "message") }
                    }
                    Button { vai = 1 } label: { Label("Tesseramento", systemImage: "person.text.rectangle") }
                    Button { vai = 2 } label: { Label("Registro presenze", systemImage: "checklist") }
                } label: { TastoTondoDir(icona: Ic.puntini, lato: 22) }
                .accessibilityLabel("Altre azioni")
            }
            if let s {
                ScrollView {
                    VStack(spacing: 10) {
                        testa(s)
                        stati(s)
                        if !assicurato(s) {
                            Button { Task { await segnaCaricato(s) } } label: {
                                Text(lavoro ? "Salvo…" : "Segna caricato in Intranet FIGT").font(.system(size: 13.5, weight: .black)).foregroundStyle(Theme.scuro)
                                    .frame(maxWidth: .infinity).frame(height: 42)
                                    .background(Theme.red, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            }
                            .buttonStyle(PressStyle())
                        }
                        SchedeFlessDir(voci: ["Dati", "Salute", "Presenze/quote", "Documenti"], scelta: $scheda)
                        switch scheda {
                        case 0: righe(datiAnagrafici(s))
                        case 1: righe(datiSalute(s))
                        case 3: righe(documenti(s))
                        default:
                            presenze(s)
                            quote(s)
                        }
                        if let errore { Text(errore).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.red) }
                    }
                    .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            } else {
                Text(errore ?? "Carico la scheda…").font(.system(size: 13, weight: .bold)).foregroundStyle(errore == nil ? Theme.dim : Theme.red)
                    .frame(maxWidth: .infinity).padding(.top, 40)
            }
        }
        .paginaDir()
        .navigationDestination(isPresented: Binding(get: { vai != nil }, set: { if !$0 { vai = nil } })) {
            if vai == 2 { RegistroPresenzeView() } else { TesseramentoView() }
        }
        .confirmationDialog("Quota \(registra.map { String($0.anno) } ?? "") · come ha pagato?", isPresented: Binding(get: { registra != nil }, set: { if !$0 { registra = nil } }), titleVisibility: .visible) {
            ForEach(["cassa", "banca", "paypal"], id: \.self) { c in
                Button(c == "cassa" ? "Contanti" : c == "banca" ? "Bonifico" : "PayPal") { if let q = registra { Task { await registraQuota(q, conto: c) } } }
            }
        }
        .task { await carica() }
    }

    func apri(_ schema: String, _ t: String) {
        if let u = URL(string: schema + t.filter { $0.isNumber || $0 == "+" }) { apriURL(u) }
    }

    // MARK: testa: avatar 62 con bordo verde, callsign mono 21, sottotitolo 12,5, etichette

    func testa(_ s: JSchedaDir) -> some View {
        HStack(spacing: 12) {
            ZStack {
                AvatarDir(id: s.id, sigla: sigla ?? siglaDir(s.callsign), lato: 62, testo: 19, fondo: Color(hex: 0x3A4428))
                Circle().strokeBorder(Theme.olive, lineWidth: 2).frame(width: 62, height: 62)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(s.callsign).font(Theme.mono(21, .heavy)).foregroundStyle(Theme.testo).lineLimit(1)
                Text(sottotitolo(s)).font(.system(size: 12.5)).foregroundStyle(Theme.testo2).lineLimit(1)
                HStack(spacing: 5) {
                    TagDir(testo: (aspirante ? "ASPIRANTE" : s.carica.flatMap { $0.isEmpty ? nil : NomiAssoc.carica($0) } ?? "Socio").uppercased(), colore: Theme.oliveBright)
                    if let g = s.specialita ?? s.gruppi?.first, !g.isEmpty { TagDir(testo: g.uppercased(), colore: Theme.dim) }
                }
                .padding(.top, 5)
            }
            Spacer(minLength: 0)
        }
    }

    func sottotitolo(_ s: JSchedaDir) -> String {
        var p = [nomeBreveDir(s.nome)]
        if let a = s.ammesso, a.count >= 4 { p.append("socio dal \(a.prefix(4))") }
        if let n = s.nascita, n.count >= 10, let d = FormatoGiorno.f.date(from: String(n.prefix(10))),
           let e = Calendar.current.dateComponents([.year], from: d, to: Date()).year { p.append("\(e) anni") }
        return p.joined(separator: " · ")
    }

    // MARK: tre riquadri di stato

    func tessera(_ s: JSchedaDir) -> JSchedaSocio.Tessera? { s.tesseramenti?.first { $0.anno == AnnoDir.quota } }
    func assicurato(_ s: JSchedaDir) -> Bool { aspirante || tessera(s)?.intranet == 1 }
    func quotaAnno(_ s: JSchedaDir) -> JSchedaDir.Quota? { s.quote?.first { $0.anno == AnnoDir.quota } }

    func stati(_ s: JSchedaDir) -> some View {
        let ass = tessera(s)?.intranet == 1
        let g = giorniA(s.certificato_scadenza)
        var cert: (String, Color) = ("manca", Theme.red)
        if let g, let d = FormatoGiorno.f.date(from: String((s.certificato_scadenza ?? "").prefix(10))) {
            cert = g < 0 ? ("scaduto", Theme.red) : g <= 30 ? ("scade tra \(g) g", Theme.red) : ("ok · " + FormatiDir.meseAnno.string(from: d), Theme.oliveBright)
        }
        let pagata = quotaAnno(s)?.pagata == 1
        return HStack(spacing: 6) {
            box("ASSICURAZIONE", ass ? "caricato" : "non caricato", ass ? Theme.oliveBright : Theme.red)
            box("CERTIFICATO", cert.0, cert.1)
            box("QUOTA \(AnnoDir.quota)", pagata ? "pagata" : "da pagare", pagata ? Theme.oliveBright : Theme.amber)
        }
    }

    func box(_ t: String, _ v: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.dim).lineLimit(1)
            Text(v).font(.system(size: 12.5, weight: .heavy)).foregroundStyle(c).lineLimit(1)
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(c.opacity(0.33)))
    }

    // MARK: presenze: anello 78, 4 numeri, barre per mese

    struct Presenze { var anno = 0; var totali = 0; var serie = 0; var ultima: Date?; var mesi = [Int](repeating: 0, count: 12); var perc = 0 }

    func calcola(_ s: JSchedaDir) -> Presenze {
        var p = Presenze()
        let cal = Calendar.current, oggi = Date(), anno = AnnoDir.corrente
        let passati = (s.eventi ?? []).compactMap { e -> (Date, Bool)? in
            guard let i = e.inizio, let d = JEvento.data(i), d <= oggi else { return nil }
            return (d, e.presente == 1)
        }.sorted { $0.0 > $1.0 }
        for (d, si) in passati where si && cal.component(.year, from: d) == anno {
            p.anno += 1; p.mesi[cal.component(.month, from: d) - 1] += 1
        }
        p.totali = s.statistiche?.eventi ?? passati.filter { cal.component(.year, from: $0.0) == anno }.count
        p.serie = passati.prefix { $0.1 }.count
        p.ultima = passati.first { $0.1 }?.0
        p.perc = p.totali > 0 ? Int((Double(p.anno) / Double(p.totali) * 100).rounded()) : (s.statistiche?.percentuale ?? 0)
        return p
    }

    func presenze(_ s: JSchedaDir) -> some View {
        let p = calcola(s)
        let meseOra = Calendar.current.component(.month, from: Date()) - 1
        let massimo = max(2, p.mesi.max() ?? 0)
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Color(hex: 0x26301A), lineWidth: 9)
                    Circle().trim(from: 0, to: CGFloat(p.perc) / 100)
                        .stroke(Theme.oliveBright, style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
                    Text("\(p.perc)%").font(Theme.mono(17, .heavy)).foregroundStyle(Theme.testo)
                }
                .frame(width: 64, height: 64).frame(width: 78, height: 78)
                // tela: griglia 1fr 1fr, spazi 8 (righe) e 10 (colonne)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        numero("\(p.anno)", "presenze \(AnnoDir.corrente)").frame(maxWidth: .infinity, alignment: .leading)
                        numero("\(p.totali)", "eventi in totale").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(alignment: .top, spacing: 10) {
                        numero("\(p.serie)", "di fila (serie)").frame(maxWidth: .infinity, alignment: .leading)
                        numero(p.ultima.map { FormatiHome.giornoMese.string(from: $0) } ?? "—", "ultima presenza").frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Rectangle().fill(Theme.olive.opacity(0.13)).frame(height: 1).padding(.top, 11).padding(.bottom, 9)
            HStack {
                Text("PRESENZE PER MESE · \(String(AnnoDir.corrente))").font(.system(size: 10.5, weight: .heavy)).foregroundStyle(Theme.dim)
                Spacer()
                NavigationLink { RegistroPresenzeView() } label: { Text("registro ›").font(.system(size: 10.5, weight: .heavy)).foregroundStyle(Theme.oliveBright) }
            }
            .padding(.bottom, 6)
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(0..<12, id: \.self) { m in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(p.mesi[m] == 0 ? Color(hex: 0x26301A) : m == meseOra ? Theme.oliveBright : Color(hex: 0x5F7136))
                            .frame(height: p.mesi[m] == 0 ? 4 : max(8, 44 * CGFloat(p.mesi[m]) / CGFloat(massimo)))
                        Text(Self.mesi[m]).font(.system(size: 9, weight: .heavy)).foregroundStyle(m == meseOra ? Theme.testo : Color(hex: 0x7D8470))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 64, alignment: .bottom).padding(.horizontal, 2)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke))
    }

    func numero(_ n: String, _ t: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(n).font(Theme.mono(17, .heavy)).foregroundStyle(Theme.testo).lineLimit(1)
            Text(t).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.dim).lineLimit(1)
        }
    }

    // MARK: quote e tessera FIGT (ultime 3 stagioni)

    func quote(_ s: JSchedaDir) -> some View {
        var lista = s.quote ?? []
        if !lista.contains(where: { $0.anno == AnnoDir.quota }) {
            lista.append(JSchedaDir.Quota(anno: AnnoDir.quota, importo: lista.max { $0.anno < $1.anno }?.importo, pagata: 0))
        }
        lista.sort { $0.anno > $1.anno }
        let versato = lista.filter { $0.pagata == 1 }.reduce(0) { $0 + ($1.importo ?? 0) }
        return VStack(spacing: 0) {
            HStack {
                Text("QUOTE E TESSERA FIGT")
                Spacer()
                Text("totale versato " + euroTondo(versato))
            }
            .font(.system(size: 10.5, weight: .heavy)).foregroundStyle(Theme.dim)
            .padding(.horizontal, 12).padding(.top, 10)
            ForEach(Array(lista.prefix(3).enumerated()), id: \.element.anno) { i, q in
                rigaQuota(q, s)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Theme.olive.opacity(0.12)).frame(height: 1) } }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke))
    }

    func euroTondo(_ v: Double) -> String { v == v.rounded() ? "\(Int(v)) €" : euroIT(v) }

    func rigaQuota(_ q: JSchedaDir.Quota, _ s: JSchedaDir) -> some View {
        let pagata = q.pagata == 1
        let figt = s.tesseramenti?.first { $0.anno == q.anno }?.intranet == 1
        var sotto: [String] = []
        if pagata {
            if let d = q.data, d.count >= 10, let g = FormatoGiorno.f.date(from: String(d.prefix(10))) { sotto.append(FormatiHome.giornoMese.string(from: g)) }
            if let c = q.conto { sotto.append(c == "cassa" ? "contanti" : c == "banca" ? "bonifico" : NomiAssoc.conto(c)) }
            if let r = q.ricevuta, !r.isEmpty { sotto.append("ricevuta \(r)") }
            sotto.append(figt ? "FIGT ✓" : "FIGT da caricare")
        } else {
            sotto = ["scade il 31 dic", figt ? "FIGT caricata" : "FIGT non ancora caricata"]
        }
        let colore = pagata ? Theme.oliveBright : Theme.amber
        return HStack(spacing: 11) {
            Text(String(q.anno)).font(Theme.mono(15, .heavy)).foregroundStyle(Theme.testo).frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                TagDir(testo: (pagata ? "PAGATA" : "DA PAGARE") + (q.importo.map { " · " + euroTondo($0) } ?? ""), colore: colore, dimensione: 9.5, orizzontale: 7)
                    .frame(height: 22)   // tela: etichetta in linea dentro una riga di testo da 16
                Text(sotto.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !pagata {
                Button { registra = q } label: {
                    Text("Registra").font(.system(size: 12, weight: .black)).foregroundStyle(Theme.scuro)
                        .padding(.horizontal, 11).frame(height: 34).background(Theme.olive, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    // MARK: altre schede: righe etichetta (112) e valore

    func righe(_ r: [(String, String)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(r.enumerated()), id: \.offset) { i, x in
                HStack(alignment: .top, spacing: 0) {
                    Text(x.0).foregroundStyle(Theme.dim).frame(width: 112, alignment: .leading)
                    Text(x.1.isEmpty ? "—" : x.1).foregroundStyle(Theme.testo).frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Theme.olive.opacity(0.12)).frame(height: 1) } }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke))
    }

    func datiAnagrafici(_ s: JSchedaDir) -> [(String, String)] {
        let residenza = [s.indirizzo, [s.cap, s.citta].compactMap { $0 }.joined(separator: " "), s.provincia].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return [("Nome", s.nome), ("Telefono", s.telefono ?? ""), ("Email", s.email ?? ""),
                ("Nato il", s.nascita.map { dataIT($0) } ?? ""), ("Luogo", s.luogo_nascita ?? ""), ("Codice fiscale", s.cf ?? ""),
                ("Residenza", residenza), ("Socio dal", s.ammesso.map { dataIT($0) } ?? ""),
                ("Gruppi", (s.gruppi ?? []).joined(separator: ", "))]
    }

    func datiSalute(_ s: JSchedaDir) -> [(String, String)] {
        let e = (s.emergenza ?? "").split(separator: "|").map(String.init)
        return [("Certificato", [s.certificato_tipo, s.certificato_scadenza.map { "scade " + dataIT($0) }].compactMap { $0 }.joined(separator: " · ")),
                ("Gruppo sang.", s.gruppo_sanguigno ?? ""), ("Allergie", s.allergie ?? ""), ("Farmaci", s.farmaci ?? ""),
                ("Emergenza", e.joined(separator: " · "))]
    }

    func documenti(_ s: JSchedaDir) -> [(String, String)] {
        let t = tessera(s)
        return [("Tessera FIGT", t.map { ($0.numero ?? "senza numero") + ($0.intranet == 1 ? " · caricata" : " · da caricare") } ?? "non tesserato"),
                ("Certificato", s.certificato_scadenza.map { "fino al " + dataIT($0) } ?? "manca"),
                ("Ricevute", (s.quote ?? []).compactMap(\.ricevuta).joined(separator: ", "))]
    }

    // MARK: dati e azioni

    func carica() async {
        if Anteprima.attiva { s = Anteprima.dirScheda; return }
        do { let x: JSchedaDir = try await jsoc.get("/api/soci/\(id)/scheda"); s = x; errore = nil } catch { errore = erroreGentile(error) }
    }

    func segnaCaricato(_ s: JSchedaDir) async {
        haptic(.medium)
        if Anteprima.attiva {
            var n = s; n.tesseramenti = [JSchedaSocio.Tessera(anno: AnnoDir.quota, figt: 1, intranet: 1, numero: nil, note: nil)] + (s.tesseramenti ?? []).filter { $0.anno != AnnoDir.quota }; self.s = n; return
        }
        lavoro = true; defer { lavoro = false }
        let t = tessera(s)
        do {
            _ = try await jsoc.salvaTesseramento(["anno": AnnoDir.quota, "utente": s.id, "figt": true, "intranet": true,
                                                  "numero": t?.numero ?? "", "rinnova": true, "note": t?.note ?? ""])
            await carica()
        } catch { errore = erroreGentile(error) }
    }

    func registraQuota(_ q: JSchedaDir.Quota, conto: String) async {
        haptic(.medium)
        if Anteprima.attiva { return }
        do {
            var c: [String: Any] = ["utente": id, "anno": q.anno, "pagata": true, "conto": conto]
            if let i = q.importo { c["importo"] = i }
            _ = try await jsoc.salvaQuota(c)
            await carica()
        } catch { errore = erroreGentile(error) }
    }
}

enum FormatiDir {
    static let meseAnno: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "MMM yyyy"; return f }()
    static let giornoMeseAnno: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "d MMM yyyy"; return f }()
}
