import SwiftUI

// MARK: - Eventi: elenco (tavola 37). Misure, colori e testi della tavola "Eventi9" (390 pt).

/// formattatori fissi della sezione Eventi (mai dentro body)
enum FormatiEventi {
    private static func it(_ f: String) -> DateFormatter { let d = DateFormatter(); d.locale = Locale(identifier: "it_IT"); d.dateFormat = f; return d }
    static let meseBreve = it("MMM")
    static let mese = it("LLLL")
    static let meseAnno = it("LLLL yyyy")
    static let ora = it("HH:mm")
    static let giornoLungo = it("EEEE d MMM")
    static let giornoMese = it("d MMM")
    static let giornoBreve = it("EEE d MMM")
    static let giornoCompleto = it("EEEE d MMMM")
}

func euroTela(_ v: Double) -> String {
    v.rounded() == v ? String(format: "%.0f €", v) : String(format: "%.2f €", v).replacingOccurrences(of: ".", with: ",")
}

/// rotte della sezione (anche per aprire le sottoschermate nelle anteprime)
enum RottaEventi: Hashable {
    case evento(JEvento)
    case commenti(JEvento)
    case nuovo
}

extension JEvento {
    /// "senza risposta": evento futuro, approvato, non annullato e senza la mia risposta
    var aspettaRisposta: Bool { fase != 2 && !proposto && !annullato && !privato && mia_risposta == nil }
}

struct EventiV3: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var store = EventoStore.shared
    @State private var percorso: [RottaEventi] = []
    @State private var scheda = 0              // 0 prossimi · 1 passati · 2 da approvare
    @State private var filtro = "tutti"
    @State private var espansi: Set<String> = []
    @State private var scelto: JEvento?
    @State private var debugFatto = false
    @Environment(\.horizontalSizeClass) private var classe

    /// iPad (tavola 68): elenco semplice a sinistra e scheda compatta a destra. Il telefono resta com'era.
    var ipad: Bool { classe == .regular && UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        let _ = GuidaApp.segna("eventi")
        let _ = Contatori.disegno("EventiV3")
        NavigationStack(path: $percorso) {
            Group {
                if jsoc.collegato { contenuto } else { EntraView() }
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: RottaEventi.self) { r in
                switch r {
                case .evento(let e): EventoV3(evento: e)
                case .commenti(let e): CommentiEventoV3(evento: e)
                case .nuovo: NuovoEventoV3()
                }
            }
            .navigationDestination(for: JEvento.self) { EventoV3(evento: $0) }
        }
        .task { apriDebug() }
    }

    /// anteprime: -debug.eventi.apri dettaglio|azioni|commenti|nuovo
    func apriDebug() {
        guard Anteprima.attiva, !debugFatto, let a = Anteprima.apriEventi else { return }
        debugFatto = true
        let tappa = store.eventi.first { $0.id == Anteprima.idTappa }
        let cqb = store.eventi.first { $0.id == 101 }
        switch a {
        case "dettaglio": if let tappa { percorso = [.evento(tappa)] }
        case "azioni": if let cqb { percorso = [.evento(cqb)] }
        case "commenti": if let cqb { percorso = [.commenti(cqb)] }
        case "nuovo": percorso = [.nuovo]
        default: break
        }
    }

    var contenuto: some View {
        GeometryReader { g in
            if ipad {
                contenutoIPad(g)
            } else if g.size.width > g.size.height || g.size.width > 700 {
                // orizzontale o iPad: elenco a sinistra, scheda dell'evento a destra
                HStack(spacing: 0) {
                    elenco(largo: true).frame(width: min(400, g.size.width * 0.42))
                    Rectangle().fill(Theme.stroke).frame(width: 1)
                    if let e = scelto ?? visibili.first {
                        EventoV3(evento: e, incorporato: true).id(e.id)
                    } else {
                        Text("Scegli un evento").foregroundStyle(Theme.dim).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                elenco(largo: false)
            }
        }
    }

    // MARK: iPad (tavola 68): elenco largo 400 a 24 dalla colonna, riga di separazione, scheda a destra

    func contenutoIPad(_ g: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            elencoIPad.frame(width: min(400, g.size.width * 0.42))
                .padding(.leading, 24).padding(.trailing, 20).padding(.top, 26).padding(.bottom, 22)
            Rectangle().fill(Theme.olive.opacity(0.16)).frame(width: 1).ignoresSafeArea()
            if let e = scelto ?? visibili.first {
                EventoV3(evento: e, incorporato: true).id(e.id)
            } else {
                Text("Scegli un evento").foregroundStyle(Theme.dim).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    var elencoIPad: some View {
        let attivo = (scelto ?? visibili.first)?.id
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .bottom) {
                Text("Eventi").font(.system(size: 30, weight: .black)).tracking(-0.6).foregroundStyle(Theme.testo).padding(.top, 2)
                Spacer()
                Button { haptic(); percorso.append(.nuovo) } label: {
                    Text("+ Proponi").font(.system(size: 14.5, weight: .black)).foregroundStyle(Theme.scuro)
                        .padding(.horizontal, 18).frame(height: 40)
                        .background(Theme.olive, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressStyle())
            }
            schede
            ScrollView {
                VStack(spacing: 9) {
                    if visibili.isEmpty { vuoto }
                    ForEach(visibili) { e in
                        Button { haptic(.soft); scelto = e } label: { RigaEventoIPad(evento: e, scelto: attivo == e.id) }
                            .buttonStyle(PressStyle())
                    }
                }
                .padding(.bottom, 20)
            }
            .refreshable { await store.aggiorna(jsoc) }
        }
    }

    // MARK: dati

    var direttivo: Bool { jsoc.utente?.direttivo == true }
    var proposte: [JEvento] { store.eventi.filter { $0.fase != 2 && $0.proposto } }
    var senzaRisposta: [JEvento] {
        store.eventi.filter { $0.aspettaRisposta }.sorted { ($0.dataInizio ?? .distantFuture) < ($1.dataInizio ?? .distantFuture) }
    }

    func passaFiltro(_ e: JEvento) -> Bool {
        switch filtro {
        case "tutti": return true
        case "assoc": return !["gara", "allenamento", "riunione"].contains(e.tipo)
        default: return e.tipo == filtro
        }
    }

    var visibili: [JEvento] {
        let base: [JEvento]
        switch scheda {
        case 1: base = store.eventi.filter { $0.fase == 2 }
        case 2: base = proposte
        default: base = store.eventi.filter { $0.fase != 2 && !$0.proposto }
        }
        return base.filter(passaFiltro).sorted {
            scheda == 1 ? ($0.dataInizio ?? .distantPast) > ($1.dataInizio ?? .distantPast)
                        : ($0.dataInizio ?? .distantFuture) < ($1.dataInizio ?? .distantFuture)
        }
    }

    struct Gruppo: Identifiable { let id: String; let titolo: String; var eventi: [JEvento]; let mese: String? }

    /// tavola: QUESTA SETTIMANA · PROSSIMA SETTIMANA · poi per mese (DICEMBRE)
    var gruppi: [Gruppo] {
        var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2; cal.locale = Locale(identifier: "it_IT")
        let questa = cal.dateInterval(of: .weekOfYear, for: Date())
        let prossima = questa.flatMap { cal.dateInterval(of: .weekOfYear, for: $0.end.addingTimeInterval(3600)) }
        let anno = cal.component(.year, from: Date())
        var out: [Gruppo] = []
        for e in visibili {
            let d = e.dataInizio ?? Date()
            var chiave: String, titolo: String, mese: String? = nil
            if scheda != 1, let q = questa, d < q.end {
                chiave = "s0"; titolo = "QUESTA SETTIMANA"
            } else if scheda != 1, let p = prossima, p.contains(d) {
                chiave = "s1"; titolo = "PROSSIMA SETTIMANA"
            } else {
                let y = cal.component(.year, from: d), m = cal.component(.month, from: d)
                chiave = "m\(y)-\(m)"
                let nome = (y == anno ? FormatiEventi.mese : FormatiEventi.meseAnno).string(from: d)
                titolo = nome.uppercased(); mese = FormatiEventi.mese.string(from: d)
            }
            if let i = out.firstIndex(where: { $0.id == chiave }) { out[i].eventi.append(e) }
            else { out.append(Gruppo(id: chiave, titolo: titolo, eventi: [e], mese: mese)) }
        }
        return out
    }

    // MARK: vista

    func elenco(largo: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // intestazione: top 54, lati 16, pulsante alto 40
            HStack {
                Text("Eventi").font(.system(size: 30, weight: .black)).tracking(-0.6).foregroundStyle(Theme.testo)
                Spacer()
                Button { haptic(); percorso.append(.nuovo) } label: {
                    HStack(spacing: 6) {
                        IconaTela(d: Ic.piu, colore: Theme.scuro, lato: 16)
                        Text("Proponi").font(.system(size: 13.5, weight: .black)).foregroundStyle(Theme.scuro)
                    }
                    .padding(.horizontal, 14).frame(height: 40)
                    .background(Theme.olive, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(PressStyle())
            }
            .padding(.horizontal, 16).padding(.top, 7)
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    schede
                    filtri
                    if scheda == 0 && !senzaRisposta.isEmpty { banner }
                    if visibili.isEmpty { vuoto }
                    ForEach(gruppi) { g in
                        Text(g.titolo).font(.system(size: 11, weight: .heavy)).tracking(0.66).foregroundStyle(Theme.dim)
                            .padding(.horizontal, 2).padding(.top, 2).padding(.bottom, -3)
                        let chiuso = g.mese != nil && scheda == 0 && !espansi.contains(g.id) && g.eventi.count > 1
                        ForEach(chiuso ? Array(g.eventi.prefix(1)) : g.eventi) { e in riga(e, largo: largo) }
                        if chiuso, let m = g.mese {
                            Button { haptic(.soft); withAnimation(.easeOut(duration: 0.2)) { _ = espansi.insert(g.id) } } label: {
                                Text("Altri \(g.eventi.count - 1) a \(m) ›").font(.system(size: 12.5, weight: .heavy)).foregroundStyle(Theme.oliveBright)
                                    .frame(maxWidth: .infinity).frame(height: 36)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 20)
            }
            .refreshable { await store.aggiorna(jsoc) }
        }
    }

    @ViewBuilder func riga(_ e: JEvento, largo: Bool) -> some View {
        if largo {
            Button { haptic(.soft); scelto = e } label: {
                RigaEventoV3(evento: e)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(scelto?.id == e.id ? Theme.olive : .clear, lineWidth: 2))
            }
            .buttonStyle(PressStyle())
        } else {
            NavigationLink(value: RottaEventi.evento(e)) { RigaEventoV3(evento: e) }.buttonStyle(PressStyle())
        }
    }

    /// schede Prossimi · Passati · Da approvare (fondo #151a10, scelta chiara)
    var schede: some View {
        var voci = ["Prossimi", "Passati"]
        if direttivo || !proposte.isEmpty { voci.append("Da approvare · \(proposte.count)") }
        return SchedeTela(voci: voci, scelta: $scheda)
    }

    var filtri: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach([("tutti", "Tutti"), ("gara", "Gare"), ("allenamento", "Allenamenti"), ("riunione", "Riunioni"), ("assoc", "Assoc.")], id: \.0) { f in
                    let on = filtro == f.0
                    Button { haptic(.soft); filtro = f.0 } label: {
                        Text(f.1).font(.system(size: 12, weight: .heavy)).foregroundStyle(on ? Theme.scuro : Theme.testo2)
                            .padding(.horizontal, 11).frame(height: 32)
                            .background(on ? Theme.testo : Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(on ? .clear : Theme.stroke))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// "2 eventi aspettano la tua risposta · Rispondi ›": apre il primo
    var banner: some View {
        let n = senzaRisposta.count
        return Button { haptic(); if let e = senzaRisposta.first { percorso.append(.evento(e)) } } label: {
            HStack(spacing: 10) {
                Circle().fill(Theme.amber).frame(width: 8, height: 8)
                Text(n == 1 ? "1 evento aspetta la tua risposta" : "\(n) eventi aspettano la tua risposta")
                    .font(.system(size: 12.5, weight: .heavy)).foregroundStyle(Theme.amber).frame(maxWidth: .infinity, alignment: .leading)
                Text("Rispondi ›").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.amber)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Theme.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.amber.opacity(0.4)))
        }
        .buttonStyle(PressStyle())
    }

    var vuoto: some View {
        VStack(spacing: 8) {
            IconaTela(d: Ic.calendario, colore: Theme.dim, lato: 30)
            Text(scheda == 1 ? "Nessun evento passato" : (scheda == 2 ? "Nessuna proposta da approvare" : "Nessun evento in programma"))
                .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity).padding(.top, 40)
    }
}

/// riga dell'evento (tavola 37): data 46×52, nome 14, sottotitolo 11,5, etichette, stato a destra
struct RigaEventoV3: View {
    let evento: JEvento
    var body: some View {
        let e = evento
        let d = e.dataInizio
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(d.map { FormatiEventi.meseBreve.string(from: $0).uppercased() } ?? "—")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.54).foregroundStyle(Theme.dim)
                Text(d.map { String(Calendar.current.component(.day, from: $0)) } ?? "?")
                    .font(Theme.mono(19, .heavy)).foregroundStyle(e.fase == 2 ? Theme.dim : Theme.testo)
            }
            .frame(width: 46, height: 52)
            .background(e.colore.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(e.nome).font(.system(size: 14, weight: .heavy)).foregroundStyle(e.fase == 2 ? Theme.dim : Theme.testo).lineLimit(1)
                Text(sottotitolo).font(.system(size: 11.5)).foregroundStyle(Theme.dim).lineLimit(1).padding(.top, 2)
                HStack(spacing: 5) {
                    Etichetta(testo: e.nomeTipo, colore: e.colore)
                    if e.tipo != "riunione" && e.interno != nil { Etichetta(testo: e.interno == 1 ? "INTERNO" : "ESTERNO", colore: Theme.dim) }
                    if e.annullato { Etichetta(testo: "ANNULLATO", colore: Theme.red) }
                    else if e.privato { Etichetta(testo: "NASCOSTO", colore: Theme.cyan) }
                    else if e.proposto { Etichetta(testo: "DA APPROVARE", colore: Theme.amber) }
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(stato.0).font(.system(size: 10.5, weight: .heavy)).foregroundStyle(stato.1).multilineTextAlignment(.trailing).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(e.aspettaRisposta ? Theme.amber.opacity(0.4) : Theme.stroke))
        .contentShape(Rectangle())
    }

    /// "08:30 · Campo Calimera · 12 sì" / "07:00 · Lecce · 9 sì · posti 9/12" / "21:00 · Sede · solo direttivo"
    var sottotitolo: String {
        var p: [String] = []
        if let d = evento.dataInizio { p.append(evento.fase == 2 ? FormatiEventi.giornoBreve.string(from: d) : FormatiEventi.ora.string(from: d)) }
        if let l = evento.luogo, !l.isEmpty { p.append(l) }
        if let b = evento.breve, !b.isEmpty { p.append(b) }
        else if let n = evento.n_si, n > 0 { p.append("\(n) sì") }
        if let n = evento.posti, n > 0 { p.append("posti \(evento.n_si ?? 0)/\(n)") }
        return p.joined(separator: " · ")
    }

    var stato: (String, Color) {
        if evento.annullato { return ("Annullato", Theme.red) }
        if evento.proposto { return ("In attesa", Theme.dim) }
        switch evento.mia_risposta {
        case "si": return ("Partecipi", Theme.oliveBright)
        case "no", "forse": return ("Non partecipi", Theme.red)
        case "arbitro": return ("Arbitro", Theme.cyan)
        case "attesa": return ("In lista d'attesa", Theme.amber)
        default: return evento.fase == 2 ? ("", Theme.dim) : ("Senza risposta", Theme.amber)
        }
    }
}

/// riga dell'elenco iPad (tavola 68): data 46×50, nome 14,5, ora · luogo, stato a destra, scelta evidenziata
struct RigaEventoIPad: View {
    let evento: JEvento
    let scelto: Bool
    var body: some View {
        let e = evento
        let d = e.dataInizio
        let s = RigaEventoV3(evento: e).stato
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(d.map { FormatiEventi.meseBreve.string(from: $0).uppercased() } ?? "—")
                    .font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.dim)
                Text(d.map { String(Calendar.current.component(.day, from: $0)) } ?? "?")
                    .font(Theme.mono(19, .heavy)).foregroundStyle(e.fase == 2 ? Theme.dim : Theme.testo)
            }
            .frame(width: 46, height: 50)
            .background(e.colore.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(e.nome).font(.system(size: 14.5, weight: .heavy)).foregroundStyle(e.fase == 2 ? Theme.dim : Theme.testo).lineLimit(1)
                Text(sottotitolo).font(.system(size: 11.5)).foregroundStyle(Theme.dim).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(s.0 == "Partecipi" ? "Partecipo" : s.0).font(.system(size: 11, weight: .heavy)).foregroundStyle(s.1).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(scelto ? Color(hex: 0x1D2416) : Theme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(scelto ? Theme.olive : Theme.olive.opacity(0.18)))
        .contentShape(Rectangle())
    }

    /// "08:30 · Campo Calimera" / "07:00 · Lecce · posti 4/12"
    var sottotitolo: String {
        var p: [String] = []
        if let d = evento.dataInizio { p.append(evento.fase == 2 ? FormatiEventi.giornoBreve.string(from: d) : FormatiEventi.ora.string(from: d)) }
        if let l = evento.luogo, !l.isEmpty { p.append(l) }
        if let n = evento.posti, n > 0 { p.append("posti \(evento.n_si ?? 0)/\(n)") }
        return p.joined(separator: " · ")
    }
}
