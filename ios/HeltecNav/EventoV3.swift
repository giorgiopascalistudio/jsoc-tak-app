import SwiftUI
import MapKit

// MARK: - Scheda dell'evento (tavole 38-39) e menu «…» (tavola 40). Misure della tela (390 pt).

/// riepiloghi sotto i riquadri della tavola 39 ("32 punti", "3 · analisi IA", "mi devono 12 €", "9 di 12 pronti")
struct RiepilogoEvento {
    var punti: Int? = nil
    var documenti: Int? = nil
    var saldo: Double? = nil
    var pronti: Int? = nil
    var voci: Int? = nil
}

/// colonne con pesi (tavola: 1.15fr 1.15fr 0.9fr)
struct ColonnePesate: SwiftUI.Layout {
    let pesi: [CGFloat]
    var spazio: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 354
        let h = subviews.map { $0.sizeThatFits(ProposedViewSize(width: w / CGFloat(max(1, subviews.count)), height: nil)).height }.max() ?? 0
        return CGSize(width: w, height: h)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let n = subviews.count
        let p = Array(pesi.prefix(n)) + Array(repeating: 1, count: max(0, n - pesi.count))
        let tot = p.reduce(0, +)
        let libero = b.width - spazio * CGFloat(max(0, n - 1))
        var x = b.minX
        for (i, s) in subviews.enumerated() {
            let w = libero * p[i] / tot
            s.place(at: CGPoint(x: x, y: b.minY), proposal: ProposedViewSize(width: w, height: b.height))
            x += w + spazio
        }
    }
}

/// iniziali del callsign per il tondino dei commenti ("WOLF" → "WL", "RAVEN" → "RV")
func inizialiCommento(_ s: String?) -> String {
    let l = Array((s ?? "?").uppercased().filter { $0.isLetter })
    guard let a = l.first else { return "?" }
    if let b = l.dropFirst().first(where: { !"AEIOU".contains($0) }) { return String([a, b]) }
    return String(l.prefix(2))
}

/// tondino con le iniziali (tavola: #2a3320, testo chiaro)
struct TondoIniziali: View {
    let testo: String
    var lato: CGFloat = 26
    var body: some View {
        Text(testo).font(.system(size: lato * 0.365, weight: .heavy)).foregroundStyle(Theme.testo)
            .frame(width: lato, height: lato).background(Color(hex: 0x2A3320), in: Circle())
    }
}

/// copertina in alto (tavola: gradiente radiale marrone + sfumatura verso lo sfondo)
struct CopertinaTela: View {
    let evento: JEvento
    @State private var img: UIImage?
    var body: some View {
        GeometryReader { g in
            let c = CGPoint(x: g.size.width * 0.6, y: g.size.height * 0.3)
            let r = max(hypot(c.x, g.size.height - c.y), hypot(g.size.width - c.x, g.size.height - c.y), hypot(c.x, c.y))
            ZStack {
                RadialGradient(colors: [Color(hex: 0x6B4A2A), Color(hex: 0x1A1410)], center: UnitPoint(x: 0.6, y: 0.3), startRadius: 0, endRadius: r)
                if let img { Image(uiImage: img).resizable().scaledToFill().frame(width: g.size.width, height: g.size.height).clipped() }
                LinearGradient(colors: [Color.black.opacity(0.1), Theme.bg], startPoint: .top, endPoint: .bottom)
            }
        }
        .task(id: "\(evento.id)-\(evento.copertina ?? "")") {
            guard let v = evento.copertina, !v.isEmpty, !Anteprima.attiva else { img = nil; return }
            let f = EventoStore.cartella.appendingPathComponent("copertina_\(evento.id)_\(v).jpg")
            if let d = try? Data(contentsOf: f), let i = UIImage(data: d) { img = i; return }
            if let d = try? await JsocClient.shared.scaricaDati("/api/eventi/\(evento.id)/copertina"), let i = UIImage(data: d) {
                img = i; try? d.write(to: f, options: .atomic)
            }
        }
    }
}

struct EventoV3: View {
    let evento: JEvento
    var incorporato = false
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var store = EventoStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var classe
    @State private var presenze: JPresenze?
    @State private var commenti: [JCommentoEvento] = []
    @State private var riepilogo = RiepilogoEvento()
    @State private var azioni = Anteprima.attiva && Anteprima.apriEventi == "azioni"
    @State private var errore: String?
    @State private var avviso: String?
    @State private var domande = false
    @State private var risposte: [String: String] = [:]
    // pagine
    @State private var apriCommenti = false
    @State private var apriModifica = false
    @State private var apriDuplica = false
    @State private var apriRisposte: String?
    @State private var apriSpese = false
    @State private var apriChecklist = false
    @State private var apriSquadra = false
    @State private var documenti = false
    // conferme
    @State private var chiediAnnulla = false
    @State private var chiediElimina = false
    @State private var chiediElimina2 = false

    var e: JEvento { store.eventi.first { $0.id == evento.id } ?? evento }
    var io: Int? { jsoc.utente?.id }
    var mia: String? { presenze?.presenze.first { $0.utente == io }?.risposta ?? e.mia_risposta }
    var organizzatore: Bool { e.staff || (e.creato_da != nil && e.creato_da == io) }
    var gestore: Bool { jsoc.utente?.direttivo == true || organizzatore }
    /// mappa, documenti, spese, squadra e checklist si sbloccano con la presenza
    /// (con "Non partecipo" restano chiusi anche per chi organizza o è staff)
    var dentro: Bool { mia == "si" || mia == "arbitro" || (organizzatore && mia != "no") }
    var rispondibile: Bool { !e.proposto && !e.annullato && !e.privato && e.fase != 2 }
    /// iPad (tavola 68): scheda compatta accanto all'elenco
    var ipad: Bool { classe == .regular && UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        let _ = GuidaApp.segna("evento")
        let _ = Contatori.disegno("EventoV3")
        GeometryReader { g in
            if incorporato && ipad && g.size.width >= 560 {
                vistaIPad
            } else {
            let alto = g.safeAreaInsets.top
            ZStack(alignment: .top) {
                ScrollView {
                    ZStack(alignment: .top) {
                        CopertinaTela(evento: e).frame(height: alto + 163)
                        corpo.padding(.top, alto + 103)
                    }
                }
                .ignoresSafeArea(edges: .top)
                // indietro e «…»: top 54 (7 sotto la barra di stato), lati 14, tondi 38
                HStack {
                    if !incorporato { tondo(Ic.indietroCopertina, 2, "Indietro") { dismiss() } }
                    Spacer()
                    tondo(Ic.puntini, 3, "Altro") { haptic(); withAnimation(.easeOut(duration: 0.2)) { azioni = true } }
                }
                .padding(.horizontal, 14).padding(.top, 7)
                if azioni { menuAzioni.transition(.opacity) }
            }
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { if !incorporato { ModuliAperti.shared.aperti += 1 } }
        .onDisappear { if !incorporato { ModuliAperti.shared.aperti = max(0, ModuliAperti.shared.aperti - 1) } }
        .task(id: e.id) { await carica() }
        .refreshable { await store.aggiorna(jsoc); await carica() }
        .sheet(isPresented: $domande) { domandeSheet }
        .navigationDestination(isPresented: $apriCommenti) { CommentiEventoV3(evento: e) }
        .navigationDestination(isPresented: $apriModifica) { NuovoEventoV3(modifica: e) }
        .navigationDestination(isPresented: $apriDuplica) { NuovoEventoV3(base: e) }
        .navigationDestination(isPresented: Binding(get: { apriRisposte != nil }, set: { if !$0 { apriRisposte = nil } })) {
            if let p = presenze { RisposteView(evento: e, presenze: p, filtro: apriRisposte ?? "tutti") }
        }
        .navigationDestination(isPresented: $apriSpese) { SpeseView(evento: e) }
        .navigationDestination(isPresented: $apriChecklist) { ChecklistEventoView(evento: e) }
        .navigationDestination(isPresented: $apriSquadra) { SquadraEventoView(evento: e) }
        .fullScreenCover(isPresented: $documenti) {
            ZStack(alignment: .topTrailing) {
                DocsTab().indietro { documenti = false }
                Button { documenti = false } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 28)).symbolRenderingMode(.palette).foregroundStyle(.white, Theme.surface2)
                }
                .padding(.trailing, 14).padding(.top, 4)
            }
        }
        .confirmationDialog("Annullare \(e.nome)?", isPresented: $chiediAnnulla, titleVisibility: .visible) {
            Button("Annulla l'evento", role: .destructive) { azione { try await jsoc.annullaEvento(e.id); return "Evento annullato" } }
        } message: { Text("Resta in archivio come annullato e non conta nelle presenze.") }
        .confirmationDialog("Eliminare \(e.nome)?", isPresented: $chiediElimina, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { chiediElimina2 = true } }
        } message: { Text("Spariscono risposte, punti, commenti e documenti dell'evento.") }
        .alert("Sei sicuro?", isPresented: $chiediElimina2) {
            Button("Elimina definitivamente", role: .destructive) { azione { try await jsoc.togliEvento(e.id); dismiss(); return "Evento eliminato" } }
            Button("No", role: .cancel) {}
        } message: { Text("Non si può annullare. Se vuoi solo che non si faccia usa «Annulla evento».") }
    }

    func tondo(_ d: String, _ spessore: CGFloat, _ nome: String, _ f: @escaping () -> Void) -> some View {
        Button(action: f) {
            IconaTela(d: d, colore: .white, lato: 20, spessore: spessore)
                .frame(width: 38, height: 38).background(Color.black.opacity(0.5), in: Circle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(nome)
    }

    // MARK: corpo (top 150, lati 18, spazio 9)

    var corpo: some View {
        VStack(alignment: .leading, spacing: 9) {
            etichette
            Text(e.nome).font(.system(size: 25, weight: .black)).foregroundStyle(Theme.testo)
                .lineSpacing(-3).fixedSize(horizontal: false, vertical: true)
            if let h = e.host, !h.isEmpty { Text("Host: \(h)").font(.system(size: 12.5)).foregroundStyle(Theme.dim) }
            info
            tessere
            Group {
            if e.annullato { cartello("Evento annullato: resta in archivio, non conta nelle presenze", Theme.red) }
            if e.privato { nascosto }
            if e.proposto && !e.privato { proposta }
            if rispondibile { pulsantiRisposta }
            if mia == "attesa" { Text("Posti finiti: sei in lista d'attesa, entri appena qualcuno si ritira.").font(.system(size: 11.5, weight: .bold)).foregroundStyle(Theme.amber) }
            if let avviso { Text(avviso).font(.system(size: 11.5, weight: .bold)).foregroundStyle(Theme.oliveBright) }
            if let errore { Text(errore).font(.system(size: 11.5, weight: .bold)).foregroundStyle(Theme.red) }
            }
            if !e.proposto { conteggi }
            riquadroCommenti
            if !e.proposto {
                riquadri.padding(.top, 2)
                if dentro {
                    Text("Ricevi le notifiche di spese, documenti e squadra di questo evento")
                        .font(.system(size: 10.5, weight: .bold)).foregroundStyle(Theme.oliveBright).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 6) {
                        IconaTela(d: Ic.lucchetto, colore: Theme.amber, lato: 13)
                        Text("Metti la presenza per sbloccare mappa, documenti, spese e squadra")
                            .font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.amber).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            if let n = e.note, !n.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DESCRIZIONE").font(.system(size: 11, weight: .heavy)).tracking(0.44).foregroundStyle(Theme.dim)
                    Text(n).font(.system(size: 13.5)).foregroundStyle(Theme.testo2).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 30)
    }

    var etichette: some View {
        HStack(spacing: 6) {
            Etichetta(testo: e.nomeTipo, colore: e.colore)
            if e.tipo != "riunione" && e.interno != nil {
                Etichetta(testo: e.interno == 1 ? "INTERNO" : "ESTERNO", colore: Theme.dim)
                if e.interno == 0 { Etichetta(testo: "SQUADRA JSOC", colore: Theme.olive) }
            }
            if e.annullato { Etichetta(testo: "ANNULLATO", colore: Theme.red) }
            else if e.privato { Etichetta(testo: "NASCOSTO", colore: Theme.cyan) }
            else if e.proposto { Etichetta(testo: "DA APPROVARE", colore: Theme.amber) }
        }
    }

    var info: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let i = e.dataInizio {
                HStack(spacing: 8) {
                    IconaTela(d: Ic.calendario, colore: Theme.olive, lato: 16)
                    Text(FormatiEventi.giornoLungo.string(from: i) + " · " + FormatiEventi.ora.string(from: i)
                         + (e.dataFine.map { " – " + FormatiEventi.ora.string(from: $0) } ?? ""))
                }
            }
            if let l = e.luogo, !l.isEmpty {
                Button { apriMappa() } label: {
                    HStack(spacing: 8) {
                        IconaTela(d: Ic.segnaposto, colore: Theme.olive, lato: 16)
                        if e.lat != nil {
                            (Text(l + " · ").foregroundColor(Theme.testo) + Text("apri in mappa").foregroundColor(Theme.oliveBright).fontWeight(.bold))
                        } else {
                            Text(l).foregroundStyle(Theme.testo)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(e.lat == nil)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.testo)
    }

    func apriMappa() {
        guard let la = e.lat, let lo = e.lon else { return }
        haptic()
        if dentro { store.scegli(e); store.vistaSquadra = nil; vaiAllaScheda(Schede.mappa) }
        else {
            let m = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: la, longitude: lo)))
            m.name = e.luogo; m.openInMaps()
        }
    }

    /// SCADENZA · POSTI · QUOTA (griglia di 3, angoli 12)
    var datiTessere: [(String, String, Color)] {
        var t: [(String, String, Color)] = []
        if let s = e.dataScadenza { t.append((FormatiEventi.giornoMese.string(from: s), e.iscrizioniChiuse ? "CHIUSE" : "SCADENZA", Theme.amber)) }
        if let p = e.posti, p > 0 { t.append(("\(e.n_si ?? 0) / \(p)", (e.n_attesa ?? 0) > 0 ? "POSTI · \(e.n_attesa ?? 0) IN ATTESA" : "POSTI", Theme.testo)) }
        if let q = e.quota, q > 0 { t.append((euroTela(q), "QUOTA", Theme.testo)) }
        return t
    }

    @ViewBuilder var tessere: some View {
        let t = datiTessere
        if !t.isEmpty {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    if i < t.count {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(t[i].0).font(Theme.mono(14, .heavy)).foregroundStyle(t[i].2).lineLimit(1).fixedSize()
                            Text(t[i].1).font(.system(size: 9.5, weight: .bold)).foregroundStyle(Theme.dim).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke))
                    } else {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
            }
        }
    }

    /// Partecipo · Non partecipo · Arbitro (1.15 / 1.15 / 0.9, alti 42)
    var pulsantiRisposta: some View {
        let si = mia == "si" || mia == "attesa"
        let no = mia == "no" || mia == "forse"
        let arb = mia == "arbitro"
        let siPieno = si || mia == nil
        return ColonnePesate(pesi: [1.15, 1.15, 0.9]) {
            Button { scegli("si") } label: {
                HStack(spacing: 6) {
                    if siPieno { IconaTela(d: Ic.spuntaGrossa, colore: Theme.scuro, lato: 16, spessore: 2.6) }
                    Text("Partecipo")
                }
                .modifier(TastoRisposta(pieno: siPieno, colore: siPieno ? Theme.scuro : Theme.oliveBright, fondo: Theme.olive))
            }
            Button { scegli("no") } label: {
                Text("Non partecipo").modifier(TastoRisposta(pieno: no, colore: no ? Theme.scuro : (si || arb ? Theme.dim : Theme.red), fondo: Theme.red))
            }
            Button { scegli("arbitro") } label: {
                Text("Arbitro").modifier(TastoRisposta(pieno: arb, colore: arb ? Theme.scuro : Theme.cyan, fondo: Theme.cyan))
            }
        }
        .buttonStyle(PressStyle())
        .disabled(e.iscrizioniChiuse && jsoc.utente?.direttivo != true)
    }

    struct TastoRisposta: ViewModifier {
        let pieno: Bool
        let colore: Color
        let fondo: Color
        func body(content: Content) -> some View {
            content.font(.system(size: 13.5, weight: .heavy)).foregroundStyle(colore).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity).frame(height: 42)
                .background(pieno ? fondo : Theme.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(pieno ? .clear : Theme.stroke))
        }
    }

    /// 5 sì · 2 no · 1 arbitro · 35 in attesa
    var conteggi: some View {
        let c = presenze?.conta
        let voci: [(Int, String, Color, String)] = [
            (c?.si ?? e.n_si ?? 0, "sì", Theme.oliveBright, "si"),
            ((c?.no ?? e.n_no ?? 0) + (c?.forse ?? 0), "no", Theme.red, "no"),
            (c?.arbitro ?? 0, "arbitro", Theme.cyan, "arbitro"),
            ((c?.senza_risposta ?? 0) + (c?.attesa ?? e.n_attesa ?? 0), "in attesa", Theme.amber, "senza"),
        ]
        return HStack(spacing: 4) {
            ForEach(voci, id: \.1) { v in
                Button { if presenze != nil { haptic(.soft); apriRisposte = v.3 } } label: {
                    VStack(spacing: 0) {
                        Text("\(v.0)").font(Theme.mono(16, .heavy)).foregroundStyle(v.2)
                        Text(v.1).font(.system(size: 9.5, weight: .bold)).foregroundStyle(Theme.dim)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 2).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke))
    }

    // MARK: commenti (ultimi due, dal più recente)

    var nuovi: Int {
        let visto = UserDefaults.standard.double(forKey: "eventi.commentiVisti.\(e.id)")
        return commenti.filter { $0.ts > visto && $0.autore != io }.count
    }

    var riquadroCommenti: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(commenti.isEmpty ? "Commenti" : (nuovi > 0 ? "Commenti · \(nuovi) \(nuovi == 1 ? "nuovo" : "nuovi")" : "Commenti · \(commenti.count)"))
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.testo)
                Spacer()
                if !commenti.isEmpty { Text("Tutti ›").font(.system(size: 11.5, weight: .heavy)).foregroundStyle(Theme.cyan) }
            }
            ForEach(commenti.filter { $0.autore != io }.sorted { $0.ts > $1.ts }.prefix(2)) { k in
                HStack(alignment: .top, spacing: 8) {
                    TondoIniziali(testo: inizialiCommento(k.callsign), lato: 26)
                    VStack(alignment: .leading, spacing: 0) {
                        (Text(k.callsign ?? "?").font(Theme.mono(11, .heavy)).foregroundColor(Theme.oliveBright)
                         + Text(" " + quando(k.ts)).font(.system(size: 10)).foregroundColor(Theme.dim))
                        Text(k.testo).font(.system(size: 12.5)).foregroundStyle(Theme.testo).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text("Scrivi un commento…").font(.system(size: 12.5)).foregroundStyle(Color(hex: 0x7D8470))
                .padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading).frame(height: 36)
                .background(Theme.surface2, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.stroke))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.cyan.opacity(0.3)))
        .contentShape(Rectangle())
        .onTapGesture { haptic(); apriCommenti = true }
    }

    func quando(_ ts: Double) -> String {
        let d = Date(timeIntervalSince1970: ts)
        let cal = Calendar.current
        if cal.isDateInToday(d) { return FormatiEventi.ora.string(from: d) }
        if cal.isDateInYesterday(d) { return "ieri" }
        return FormatiEventi.giornoMese.string(from: d)
    }

    // MARK: riquadri (3 colonne, alti 74, angoli 16)

    var riquadri: some View {
        let r = riepilogo
        let spese: String = {
            guard let s = r.saldo else { return "chi deve a chi" }
            if s > 0.005 { return "mi devono \(euroTela(s))" }
            if s < -0.005 { return "devo \(euroTela(-s))" }
            return "in pari"
        }()
        let colonne = Array(repeating: GridItem(.flexible(), spacing: 7), count: 3)
        return LazyVGrid(columns: colonne, spacing: 7) {
            riquadro(Ic.persona, Theme.cyan, "Presenze", "elenco · appello", aperto: true) { if presenze != nil { apriRisposte = "tutti" } }
            riquadro(Ic.mappa, Theme.olive, "Mappa", r.punti.map { "\($0) punti" } ?? "squadra e punti") {
                store.scegli(e); store.vistaSquadra = nil; vaiAllaScheda(Schede.mappa)
            }
            riquadro(Ic.documentoRighe, Theme.amber, "Documenti", r.documenti.map { $0 > 0 ? "\($0) · analisi IA" : "nessun file" } ?? "file dell'evento") {
                store.scegli(e); documenti = true
            }
            riquadro(Ic.portafoglio, Theme.amber, "Spese", spese) { apriSpese = true }
            riquadro(Ic.gruppo, Theme.red, "Squadra", "chat · piano") { store.scegli(e); apriSquadra = true }
            riquadro(Ic.spunta, Theme.olive, "Checklist", (r.voci ?? 0) > 0 ? "\(r.pronti ?? 0) di \(r.voci ?? 0) pronti" : "cosa porto") { apriChecklist = true }
        }
    }

    func riquadro(_ ic: String, _ c: Color, _ titolo: String, _ sotto: String, aperto: Bool = false, ipad: Bool = false, _ f: @escaping () -> Void) -> some View {
        let libero = aperto || dentro
        return Button { if libero { haptic(); f() } else { haptic(.soft); avviso = "Metti la presenza per aprire \(titolo.lowercased())" } } label: {
            VStack(spacing: 5) {
                IconaTela(d: libero ? ic : Ic.lucchetto, colore: libero ? c : Color(hex: 0x5B6150), lato: 22)
                Text(titolo).font(.system(size: ipad ? 13.5 : 13, weight: .heavy)).foregroundStyle(libero ? Theme.testo : Color(hex: 0x6F7564))
                if libero { Text(sotto).font(.system(size: ipad ? 10.5 : 10)).foregroundStyle(Theme.dim).lineLimit(1) }
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity).frame(height: ipad ? 84 : 74)
            .background(libero ? Theme.surface : Color(hex: 0x0F130C), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.olive.opacity(libero ? 0.3 : 0.12)))
        }
        .buttonStyle(PressStyle())
    }

    // MARK: iPad (tavola 68): copertina 170, risposta + conteggi su una riga, riquadri 3×2 a sinistra e commenti a destra

    /// tavola: il corpo finisce 22 pt dal fondo dello schermo (anche sopra la barretta di sistema)
    var vistaIPad: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 12) {
                copertinaIPad
                if rispondibile || !e.proposto { rigaRispostaIPad }
                Group {
                    if e.annullato { cartello("Evento annullato: resta in archivio, non conta nelle presenze", Theme.red) }
                    if e.privato { nascosto }
                    if e.proposto && !e.privato { proposta }
                    if mia == "attesa" { Text("Posti finiti: sei in lista d'attesa, entri appena qualcuno si ritira.").font(.system(size: 11.5, weight: .bold)).foregroundStyle(Theme.amber) }
                    if let avviso { Text(avviso).font(.system(size: 11.5, weight: .bold)).foregroundStyle(Theme.oliveBright) }
                    if let errore { Text(errore).font(.system(size: 11.5, weight: .bold)).foregroundStyle(Theme.red) }
                }
                GeometryReader { g in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 10) {
                            if !e.proposto { riquadriIPad }
                            if let n = e.note, !n.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("DESCRIZIONE").font(.system(size: 11, weight: .heavy)).tracking(0.44).foregroundStyle(Theme.dim)
                                    Text(n).font(.system(size: 13.5)).foregroundStyle(Theme.testo2).lineLimit(8)
                                }
                                .padding(.top, 4)
                            }
                        }
                        .frame(width: (g.size.width - 12) * 1.15 / 2.15, alignment: .topLeading)
                        commentiIPad
                    }
                }
            }
            .padding(.leading, 20).padding(.trailing, 22).padding(.top, 26).padding(.bottom, 22)
            .ignoresSafeArea(.container, edges: .bottom)
            if azioni { menuAzioni.transition(.opacity) }
        }
    }

    /// "Dom 22 nov · 08:30–13:00 · Campo Calimera"
    var sottoIPad: String {
        var p: [String] = []
        if let i = e.dataInizio {
            let g = FormatiEventi.giornoBreve.string(from: i)
            p.append(g.prefix(1).uppercased() + g.dropFirst())
            p.append(FormatiEventi.ora.string(from: i) + (e.dataFine.map { "–" + FormatiEventi.ora.string(from: $0) } ?? ""))
        }
        if let l = e.luogo, !l.isEmpty { p.append(l) }
        return p.joined(separator: " · ")
    }

    var copertinaIPad: some View {
        ZStack(alignment: .bottomLeading) {
            if let c = e.copertina, !c.isEmpty { CopertinaTela(evento: e) } else { Color(hex: 0x26301A) }
            VStack(alignment: .leading, spacing: 0) {
                etichette
                Text(e.nome).font(.system(size: 28, weight: .black)).foregroundStyle(Theme.testo)
                    .lineLimit(1).minimumScaleFactor(0.7).padding(.top, 6)
                Text(sottoIPad).font(.system(size: 13.5)).foregroundStyle(Theme.testo2).lineLimit(1).padding(.top, 3)
            }
            .padding(.leading, 20).padding(.trailing, 70).padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity).frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button { haptic(); withAnimation(.easeOut(duration: 0.2)) { azioni = true } } label: {
                IconaTela(d: Ic.puntini, colore: Theme.testo, lato: 22, spessore: 2)
                    .frame(width: 42, height: 42).background(Theme.bg.opacity(0.7), in: Circle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Altre azioni")
            .padding(.trailing, 16).padding(.top, 14)
        }
    }

    var rigaRispostaIPad: some View {
        let si = mia == "si" || mia == "attesa"
        let c = presenze?.conta
        let voci: [(Int, String, Color, String)] = [
            (c?.si ?? e.n_si ?? 0, "sì", Theme.oliveBright, "si"),
            ((c?.no ?? e.n_no ?? 0) + (c?.forse ?? 0), "no", Theme.red, "no"),
            (c?.arbitro ?? 0, "arbitro", Theme.cyan, "arbitro"),
            ((c?.senza_risposta ?? 0) + (c?.attesa ?? e.n_attesa ?? 0), "attesa", Theme.amber, "senza"),
        ]
        return HStack(spacing: 10) {
            if rispondibile {
                Group {
                    tastoIPad("Partecipo", "si", pieno: si || mia == nil, fondo: Theme.olive, spunta: true)
                    tastoIPad("Non partecipo", "no", pieno: mia == "no" || mia == "forse", fondo: Theme.red)
                    tastoIPad("Arbitro", "arbitro", pieno: mia == "arbitro", fondo: Theme.cyan)
                }
                .disabled(e.iscrizioniChiuse && jsoc.utente?.direttivo != true)
            }
            Spacer(minLength: 0)
            if !e.proposto {
                ForEach(voci, id: \.1) { v in
                    Button { if presenze != nil { haptic(.soft); apriRisposte = v.3 } } label: {
                        VStack(spacing: 0) {
                            Text("\(v.0)").font(Theme.mono(19, .heavy)).foregroundStyle(v.2)
                            Text(v.1).font(.system(size: 10.5, weight: .bold)).foregroundStyle(Theme.dim)
                        }
                        .frame(minWidth: 54).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    func tastoIPad(_ t: String, _ r: String, pieno: Bool, fondo: Color, spunta: Bool = false) -> some View {
        Button { scegli(r) } label: {
            HStack(spacing: 6) {
                if spunta && pieno { IconaTela(d: Ic.spuntaGrossa, colore: Theme.scuro, lato: 15, spessore: 2.6) }
                Text(t)
            }
            .font(.system(size: 14.5, weight: pieno ? .black : .heavy)).foregroundStyle(pieno ? Theme.scuro : Theme.testo)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 18).frame(height: 48)
            .background(pieno ? fondo : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(pieno ? .clear : Theme.testo.opacity(0.18)))
        }
        .buttonStyle(PressStyle())
    }

    var riquadriIPad: some View {
        let r = riepilogo
        let spese: String = {
            guard let s = r.saldo else { return "chi deve a chi" }
            if s > 0.005 { return "mi devono \(euroTela(s))" }
            if s < -0.005 { return "devo \(euroTela(-s))" }
            return "in pari"
        }()
        let colonne = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
        return LazyVGrid(columns: colonne, spacing: 8) {
            riquadro(Ic.persona, Theme.olive, "Presenze", "elenco · appello", aperto: true, ipad: true) { if presenze != nil { apriRisposte = "tutti" } }
            riquadro(Ic.mappa, Theme.olive, "Mappa", r.punti.map { "\($0) punti" } ?? "squadra e punti", ipad: true) {
                store.scegli(e); store.vistaSquadra = nil; vaiAllaScheda(Schede.mappa)
            }
            riquadro(Ic.file, Theme.amber, "Documenti", r.documenti.map { $0 > 0 ? "\($0) · analisi IA" : "nessun file" } ?? "file dell'evento", ipad: true) {
                store.scegli(e); documenti = true
            }
            riquadro(Ic.carta, Theme.amber, "Spese", spese, ipad: true) { apriSpese = true }
            riquadro(Ic.squadraEvento, Theme.red, "Squadra", "chat · piano", ipad: true) { store.scegli(e); apriSquadra = true }
            riquadro(Ic.spunta, Theme.olive, "Checklist", (r.voci ?? 0) > 0 ? "\(r.pronti ?? 0) di \(r.voci ?? 0)" : "cosa porto", ipad: true) { apriChecklist = true }
        }
    }

    var commentiIPad: some View {
        let titolo = commenti.isEmpty ? "COMMENTI" : (nuovi > 0 ? "COMMENTI · \(nuovi) \(nuovi == 1 ? "NUOVO" : "NUOVI")" : "COMMENTI · \(commenti.count)")
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(titolo).font(.system(size: 12, weight: .heavy)).tracking(0.72).foregroundStyle(Theme.dim)
                Spacer()
                if !commenti.isEmpty { Text("tutti ›").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.oliveBright) }
            }
            .padding(.bottom, 10)
            ForEach(commenti.filter { $0.autore != io }.sorted { $0.ts > $1.ts }.prefix(3)) { k in
                VStack(alignment: .leading, spacing: 2) {
                    (Text(k.callsign ?? "?").font(Theme.mono(11.5, .heavy)).foregroundColor(Theme.oliveBright)
                     + Text(" " + quando(k.ts)).font(.system(size: 11)).foregroundColor(Theme.dim))
                    Text(k.testo).font(.system(size: 13.5)).foregroundStyle(Theme.testo).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Rectangle().fill(Theme.olive.opacity(0.12)).frame(height: 1) }
            }
            Text("Scrivi un commento…").font(.system(size: 13)).foregroundStyle(Color(hex: 0x7D8470))
                .padding(.horizontal, 14).frame(maxWidth: .infinity, alignment: .leading).frame(height: 40)
                .background(Theme.surface2, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.stroke))
                .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.stroke))
        .contentShape(Rectangle())
        .onTapGesture { haptic(); apriCommenti = true }
    }

    // MARK: stati particolari (non nelle tavole: compaiono solo quando servono)

    func cartello(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 12.5, weight: .heavy)).foregroundStyle(c)
            .padding(.horizontal, 12).padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading)
            .background(c.opacity(0.1), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(c.opacity(0.4)))
    }

    var nascosto: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Evento nascosto: lo vedi solo tu").font(.system(size: 12.5, weight: .heavy)).foregroundStyle(Theme.cyan)
            Button {
                azione {
                    try await jsoc.rendiVisibile(e.id)
                    return jsoc.utente?.direttivo == true ? "Ora lo vedono tutti" : "Inviato al direttivo per l'approvazione"
                }
            } label: { Text("Rendi visibile").modifier(TastoRisposta(pieno: true, colore: Theme.scuro, fondo: Theme.cyan)) }
            .buttonStyle(PressStyle())
        }
        .padding(12)
        .background(Theme.cyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.cyan.opacity(0.4)))
    }

    var proposta: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Proposta in attesa di approvazione del direttivo").font(.system(size: 12.5, weight: .heavy)).foregroundStyle(Theme.amber)
            if jsoc.utente?.direttivo == true {
                HStack(spacing: 6) {
                    Button { azione { try await jsoc.approvaEvento(e.id); return "Evento approvato: ora lo vedono tutti" } } label: {
                        Text("Approva").modifier(TastoRisposta(pieno: true, colore: Theme.scuro, fondo: Theme.olive))
                    }
                    Button { azione { try await jsoc.togliEvento(e.id); dismiss(); return "Proposta rifiutata" } } label: {
                        Text("Rifiuta").modifier(TastoRisposta(pieno: false, colore: Theme.red, fondo: Theme.red))
                    }
                }
                .buttonStyle(PressStyle())
            } else if organizzatore {
                Button { azione { try await jsoc.togliEvento(e.id); dismiss(); return "Proposta ritirata" } } label: {
                    Text("Ritira la proposta").modifier(TastoRisposta(pieno: false, colore: Theme.red, fondo: Theme.red))
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(12)
        .background(Theme.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.amber.opacity(0.4)))
    }

    // MARK: menu «…» (tavola 40)

    struct VoceAzione { let ic: String; let titolo: String; let sotto: String; let colore: Color; let f: () -> Void }

    var vociAzioni: [VoceAzione] {
        var v: [VoceAzione] = []
        let senza = presenze?.conta.senza_risposta ?? 0
        if gestore {
            v.append(VoceAzione(ic: Ic.matita, titolo: "Modifica evento", sotto: "Data, luogo, iscrizioni, copertina", colore: Theme.testo) { apriModifica = true })
        }
        v.append(VoceAzione(ic: Ic.duplica, titolo: "Duplica", sotto: "Stesso evento in un'altra data", colore: Theme.testo) { apriDuplica = true })
        if gestore && rispondibile {
            v.append(VoceAzione(ic: Ic.campanellaVuota, titolo: "Promemoria a chi non ha risposto",
                                sotto: "\(senza) \(senza == 1 ? "socio" : "soci") · arriva come notifica", colore: Theme.testo) {
                azione { let n = try await jsoc.promemoria(e.id); return "Promemoria mandato a \(n) soci" }
            })
        }
        v.append(VoceAzione(ic: Ic.scarica, titolo: "Esporta", sotto: "Presenze in Excel · punti in KML", colore: Theme.testo) { esporta() })
        if gestore && !e.proposto && !e.privato {
            if e.annullato {
                v.append(VoceAzione(ic: Ic.croce, titolo: "Ripristina evento", sotto: "Torna a contare nelle presenze", colore: Theme.amber) {
                    azione { try await jsoc.annullaEvento(e.id, false); return "Evento ripristinato" }
                })
            } else {
                v.append(VoceAzione(ic: Ic.croce, titolo: "Annulla evento", sotto: "Resta in archivio, non conta nelle presenze", colore: Theme.amber) { chiediAnnulla = true })
            }
        }
        if gestore {
            v.append(VoceAzione(ic: Ic.cestino, titolo: "Elimina evento", sotto: "Chiede conferma due volte", colore: Theme.red) { chiediElimina = true })
        }
        return v
    }

    var chiOrganizza: String {
        if organizzatore { return "organizzatore: tu" }
        if let h = e.host, !h.isEmpty { return "organizzatore: \(h)" }
        return "evento dell'associazione"
    }

    var menuAzioni: some View {
        ZStack(alignment: .bottom) {
            ZStack { Theme.bg.opacity(0.65); Color.black.opacity(0.55) }.ignoresSafeArea()
                .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { azioni = false } }
            VStack(alignment: .leading, spacing: 0) {
                Capsule().fill(Color(hex: 0x3A4130)).frame(width: 40, height: 5).frame(maxWidth: .infinity).padding(.top, 2).padding(.bottom, 8)
                Text("\(e.nome) · \(chiOrganizza)").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.dim).lineLimit(1)
                    .padding(.horizontal, 16).padding(.bottom, 8)
                let voci = vociAzioni
                ForEach(voci.indices, id: \.self) { i in
                    let v = voci[i]
                    Button {
                        haptic()
                        withAnimation(.easeOut(duration: 0.2)) { azioni = false }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { v.f() }
                    } label: {
                        HStack(spacing: 12) {
                            IconaTela(d: v.ic, colore: v.colore, lato: 19)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(v.titolo).font(.system(size: 14.5, weight: .heavy)).foregroundStyle(v.colore)
                                Text(v.sotto).font(.system(size: 11)).foregroundStyle(Theme.dim)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14).frame(height: 56).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if i < voci.count - 1 { Rectangle().fill(Theme.olive.opacity(0.14)).frame(height: 1).padding(.leading, 46) }
                }
                Button { haptic(.soft); withAnimation(.easeOut(duration: 0.2)) { azioni = false } } label: {
                    Text("Chiudi").font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.testo)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Color(hex: 0x262D1E), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressStyle())
                .padding(.horizontal, 14).padding(.top, 8)
            }
            .padding(.top, 8).padding(.bottom, 10)
            .background(Color(hex: 0x171C12), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.olive.opacity(0.25)))
            .padding(.horizontal, 10).padding(.bottom, 24)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    /// presenze in CSV (si apre in Excel) e punti in KML
    func esporta() {
        var file: [URL] = []
        let nome = e.nome.replacingOccurrences(of: "/", with: "-")
        let dir = FileManager.default.temporaryDirectory
        if let p = presenze {
            var csv = "Callsign;Nome;Risposta;Presente\n"
            for x in p.presenze {
                csv += "\(x.callsign);\(x.nome ?? "");\(x.risposta ?? "senza risposta");\(x.presente == 1 ? "sì" : "")\n"
            }
            let u = dir.appendingPathComponent("\(nome) - presenze.csv")
            if (try? ("\u{FEFF}" + csv).write(to: u, atomically: true, encoding: .utf8)) != nil { file.append(u) }
        }
        let punti = (store.corrente?.id == e.id ? store.corrente?.punti : e.punti) ?? []
        if !punti.isEmpty {
            var kml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<kml xmlns=\"http://www.opengis.net/kml/2.2\"><Document><name>\(xml(e.nome))</name>\n"
            for p in punti {
                kml += "<Placemark><name>\(xml(p.nome))</name><description>\(xml(p.note ?? ""))</description><Point><coordinates>\(p.lon),\(p.lat),0</coordinates></Point></Placemark>\n"
            }
            kml += "</Document></kml>\n"
            let u = dir.appendingPathComponent("\(nome) - punti.kml")
            if (try? kml.write(to: u, atomically: true, encoding: .utf8)) != nil { file.append(u) }
        }
        if file.isEmpty { avviso = "Niente da esportare: nessuna presenza e nessun punto"; return }
        condividi(file)
    }

    func xml(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: azioni

    var domandeSheet: some View {
        NavigationStack {
            Form {
                Section("Prima di confermare") {
                    ForEach(e.domande ?? [], id: \.self) { d in
                        TextField(d, text: Binding(get: { risposte[d] ?? "" }, set: { risposte[d] = $0 }))
                    }
                }
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("Iscrizione").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { domande = false } }
                ToolbarItem(placement: .confirmationAction) { Button("Partecipo") { domande = false; invia("si") } }
            }
        }
        .presentationDetents([.medium])
    }

    func scegli(_ r: String) {
        haptic(.medium)
        if r == "si", !(e.domande ?? []).isEmpty, mia != "si" { domande = true; return }
        invia(r)
    }

    func invia(_ r: String) {
        guard !Anteprima.attiva else { return }
        Task {
            do {
                presenze = try await jsoc.rispondi(e.id, r, risposte: r == "si" ? risposte : [:])
                errore = nil
                await store.aggiorna(jsoc)
                await HomeModel.shared.aggiorna()
                await caricaRiepilogo()
            } catch { errore = error.localizedDescription }
        }
    }

    func azione(_ f: @escaping () async throws -> String) {
        haptic(.medium)
        guard !Anteprima.attiva else { return }
        Task {
            do { avviso = try await f(); errore = nil; await store.aggiorna(jsoc); await HomeModel.shared.aggiorna() }
            catch { errore = error.localizedDescription }
        }
    }

    func carica() async {
        if Anteprima.attiva {
            presenze = Anteprima.presenzeEvento(e.id)
            commenti = Anteprima.commentiEvento(e.id)
            if dentro { riepilogo = Anteprima.riepilogoEvento }
            return
        }
        async let p = try? jsoc.presenze(e.id)
        async let k = try? jsoc.commentiEvento(e.id)
        presenze = await p
        commenti = await k ?? []
        await caricaRiepilogo()
    }

    func caricaRiepilogo() async {
        guard dentro, !Anteprima.attiva else { return }
        var r = RiepilogoEvento()
        if let pt = (store.corrente?.id == e.id ? store.corrente?.punti : e.punti) { r.punti = pt.count }
        async let d = try? jsoc.documenti(e.id)
        async let s = try? jsoc.spese(e.id)
        async let c = try? jsoc.checklist(e.id)
        if let d = await d { r.documenti = d.count }
        if let s = await s, let io {
            let avere = s.debiti.filter { $0.a == io }.reduce(0) { $0 + $1.importo }
            let dare = s.debiti.filter { $0.da == io }.reduce(0) { $0 + $1.importo }
            r.saldo = avere - dare
        }
        if let c = await c { r.voci = c.count; r.pronti = c.filter { $0.preso != 0 }.count }
        riepilogo = r
    }
}

// MARK: - Squadra dell'evento: chat, squadre, piano di gara, coordinate, tutte le funzioni

struct SquadraEventoView: View {
    let evento: JEvento
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var store = EventoStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var pacchetti: [JPacchetto] = []
    @State private var chiediPacchetto = false
    @State private var nomePacchetto = ""
    @State private var avviso: String?

    var gestore: Bool { jsoc.utente?.direttivo == true || evento.staff || (evento.creato_da != nil && evento.creato_da == jsoc.utente?.id) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { dismiss() } label: {
                    IconaTela(d: Ic.indietro, colore: Theme.testo, lato: 18)
                        .frame(width: 42, height: 42).background(Theme.surface, in: Circle()).overlay(Circle().strokeBorder(Theme.stroke))
                }
                .accessibilityLabel("Indietro")
                Text("Squadra").font(.system(size: 24, weight: .black)).foregroundStyle(Theme.testo)
                Spacer()
                Text(evento.nome).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.dim).lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.top, 7)
            ScrollView {
                VStack(spacing: 8) {
                    NavigationLink { ChatView().onAppear { store.scegli(evento) } } label: { voce(Ic.invia, Theme.cyan, "Chat", "con chi partecipa") }
                    if evento.interno == 1 {
                        NavigationLink { SquadreView(evento: evento) } label: { voce(Ic.gruppo, Theme.red, "Squadre", "Attacco / Difesa") }
                    }
                    if evento.tipo != "riunione" {
                        NavigationLink { PianoGaraView(evento: evento) } label: { voce(Ic.mappa, Theme.olive, "Piano di gara", "ordine OBJ, orari, alternative") }
                    }
                    if gestore {
                        Button { nomePacchetto = evento.nome; chiediPacchetto = true } label: { voce(Ic.scatola, Theme.amber, "Salva i punti", "come pacchetto di coordinate") }
                        if !pacchetti.isEmpty {
                            Menu {
                                ForEach(pacchetti) { p in
                                    Button("\(p.nome) · \(p.punti.count) punti") {
                                        Task { if let n = try? await jsoc.usaPacchetto(p.id, evento: evento.id) { avviso = "\(n) punti aggiunti da \(p.nome)" } }
                                    }
                                }
                            } label: { voce(Ic.scarica, Theme.amber, "Carica un pacchetto", "punti dall'archivio personale") }
                        }
                    }
                    NavigationLink { EventoView(evento: evento) } label: { voce(Ic.griglia, Theme.dim, "Tutte le funzioni", "video, membri, punti, appello") }
                    if let avviso { Text(avviso).font(.system(size: 11.5, weight: .bold)).foregroundStyle(Theme.oliveBright) }
                }
                .buttonStyle(PressStyle())
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 30)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { if gestore && !Anteprima.attiva { pacchetti = (try? await jsoc.pacchetti()) ?? [] } }
        .alert("Salva i punti come pacchetto", isPresented: $chiediPacchetto) {
            TextField("Nome del pacchetto", text: $nomePacchetto)
            Button("Salva") {
                Task { if (try? await jsoc.nuovoPacchetto(["nome": nomePacchetto, "da_evento": evento.id])) != nil { avviso = "Punti salvati nell'archivio personale" } }
            }
            Button("Annulla", role: .cancel) {}
        }
    }

    func voce(_ ic: String, _ c: Color, _ t: String, _ s: String) -> some View {
        HStack(spacing: 12) {
            IconaTela(d: ic, colore: c, lato: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(t).font(.system(size: 14.5, weight: .heavy)).foregroundStyle(Theme.testo)
                Text(s).font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
            Spacer()
            IconaTela(d: Ic.avanti, colore: Theme.dim, lato: 14)
        }
        .padding(.horizontal, 14).frame(height: 60)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke))
    }
}
