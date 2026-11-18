import SwiftUI
import PhotosUI

// MARK: - Modelli

struct JSpesa: Codable, Identifiable, Hashable {
    let id: Int
    let descrizione: String
    let importo: Double
    let pagato_da: Int
    let data: String?
    let nota: String?
    let categoria: String?
    let foto: String?
    let autore: Int?
    let ts: Double?
    let divisione: [String: Double]
    func quota(_ u: Int?) -> Double { u.flatMap { divisione[String($0)] } ?? 0 }
}

struct JRimborso: Codable, Identifiable, Hashable { let id: Int; let da: Int; let a: Int; let importo: Double; let ts: Double? }
struct JDebito: Codable, Hashable { let da: Int; let a: Int; let importo: Double }
struct JPersonaSpese: Codable, Identifiable, Hashable { let id: Int; let callsign: String }
struct JSpese: Codable {
    let spese: [JSpesa]
    let rimborsi: [JRimborso]
    let saldi: [String: Double]
    let debiti: [JDebito]
    let persone: [JPersonaSpese]
    let totale: Double?
    var nuova: Int? = nil
    func nome(_ id: Int) -> String { id == 0 ? "Associazione" : (persone.first { $0.id == id }?.callsign ?? "#\(id)") }
}

extension JsocClient {
    func spese(_ ev: Int) async throws -> JSpese { try await get("/api/eventi/\(ev)/spese") }
    func nuovaSpesa(_ ev: Int, _ campi: [String: Any]) async throws -> JSpese { try await send("/api/eventi/\(ev)/spese", "POST", campi) }
    func cancellaSpesa(_ id: Int) async throws -> JSpese { try await send("/api/spese/\(id)", "DELETE", [String: Any]()) }
    func rimborso(_ ev: Int, da: Int, a: Int, importo: Double) async throws -> JSpese {
        try await send("/api/eventi/\(ev)/rimborsi", "POST", ["da": da, "a": a, "importo": importo])
    }
    func squadre(_ ev: Int, _ azione: String, utente: Int? = nil, squadra: String = "") async throws -> JEvento {
        var b: [String: Any] = ["azione": azione, "squadra": squadra]
        if let utente { b["utente"] = utente }
        return try await send("/api/eventi/\(ev)/squadre", "POST", b)
    }
}


// MARK: - Squadre Attacco / Difesa

struct SquadreView: View {
    let evento: JEvento
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var store = EventoStore.shared
    @State private var dettaglio: JEvento?
    @State private var errore: String?

    var e: JEvento { dettaglio ?? (store.corrente?.id == evento.id ? store.corrente! : evento) }
    var staff: Bool { jsoc.utente?.direttivo == true || e.staff }
    var membri: [JMembro] { e.membri ?? [] }
    var mia: String? { membri.first { $0.id == jsoc.utente?.id }?.squadra }

    var body: some View {
        GeometryReader { g in
            let land = g.size.width > g.size.height
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if staff {
                        HStack(spacing: 8) {
                            azione("shuffle", "Mescola", Theme.olive) { try await jsoc.squadre(e.id, "mescola") }
                            azione("arrow.left.arrow.right", "Scambia", Theme.amber) { try await jsoc.squadre(e.id, "scambia") }
                            azione("arrow.uturn.backward", "Svuota", Theme.dim) { try await jsoc.squadre(e.id, "svuota") }
                        }
                    } else if let m = mia, !m.isEmpty {
                        Text("Sei in \(m.uppercased()): sulla mappa vedi solo la tua squadra.").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(m == "attacco" ? Theme.red : Theme.cyan)
                    }
                    HStack(alignment: .top, spacing: 10) {
                        colonna("ATTACCO", "attacco", Theme.red)
                        colonna("DIFESA", "difesa", Theme.cyan)
                    }
                    let senza = membri.filter { ($0.squadra ?? "").isEmpty }
                    if !senza.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SENZA SQUADRA · \(senza.count)").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.amber)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: land ? 180 : 150), spacing: 6)], spacing: 6) {
                                ForEach(senza) { m in persona(m, Theme.amber) }
                            }
                        }
                    }
                    if staff {
                        Text(staff ? "Tocca un nome per spostarlo · ognuno vede solo la mappa della propria squadra" : "")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.dim)
                        Text("MAPPE DELL'EVENTO").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.dim).padding(.top, 4)
                        HStack(spacing: 10) {
                            mappa("Mappa Attacco", "attacco", Theme.red)
                            mappa("Mappa Difesa", "difesa", Theme.cyan)
                        }
                        Button { apri(nil) } label: { Text("Mappa con tutte e due le squadre").font(.system(size: 13, weight: .bold)) }
                            .tint(Theme.oliveBright)
                    } else {
                        Button { apri(nil) } label: {
                            Label("Apri la mappa della mia squadra", systemImage: "map.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    if let errore { ErrorCard(text: errore) }
                }
                .padding(14)
                .padding(.bottom, 70)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Squadre")
        .navigationBarTitleDisplayMode(.inline)
        .task { dettaglio = try? await jsoc.evento(evento.id) }
        .refreshable { dettaglio = try? await jsoc.evento(evento.id) }
    }

    func colonna(_ titolo: String, _ sq: String, _ c: Color) -> some View {
        let m = membri.filter { $0.squadra == sq }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(titolo).font(.system(size: 14, weight: .black)).foregroundStyle(c)
                Spacer()
                Text("\(m.count)").font(Theme.mono(12, .bold)).foregroundStyle(Theme.dim)
            }
            ForEach(m) { x in persona(x, c) }
            if m.isEmpty { Text("nessuno").font(.caption).foregroundStyle(Theme.dim).padding(.vertical, 6) }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(c.opacity(0.45)))
    }

    @ViewBuilder func persona(_ m: JMembro, _ c: Color) -> some View {
        let riga = HStack(spacing: 8) {
            FotoSocio(id: m.id, iniziali: m.callsign, lato: 28)
            Text(m.callsign).font(.system(size: 12.5, weight: .bold)).lineLimit(1)
            Spacer(minLength: 0)
            if m.ruolo == "staff" { Text("STAFF").font(Theme.mono(8, .heavy)).foregroundStyle(Theme.dim) }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 11))
        if staff {
            Menu {
                Button { sposta(m, "attacco") } label: { Label("In Attacco", systemImage: "arrow.right.circle") }
                Button { sposta(m, "difesa") } label: { Label("In Difesa", systemImage: "shield") }
                Button { sposta(m, "") } label: { Label("Senza squadra", systemImage: "minus.circle") }
            } label: { riga }
        } else {
            riga
        }
    }

    func mappa(_ t: String, _ sq: String, _ c: Color) -> some View {
        Button { apri(sq) } label: {
            VStack(spacing: 6) {
                Image(systemName: "map.fill").font(.system(size: 20))
                Text(t).font(.system(size: 13, weight: .heavy))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 78)
            .background(LinearGradient(colors: [c.opacity(0.35), Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(c.opacity(0.5)))
        }
        .buttonStyle(PressStyle())
    }

    func apri(_ sq: String?) {
        haptic(.medium)
        store.scegli(e)
        store.vistaSquadra = staff ? sq : nil
        vaiAllaScheda(Schede.mappa)
    }

    func sposta(_ m: JMembro, _ sq: String) {
        Task {
            do { dettaglio = try await jsoc.squadre(e.id, "sposta", utente: m.id, squadra: sq); haptic(); errore = nil }
            catch { errore = error.localizedDescription }
        }
    }

    func azione(_ icona: String, _ t: String, _ c: Color, _ f: @escaping () async throws -> JEvento) -> some View {
        Button {
            haptic(.medium)
            Task { do { dettaglio = try await f(); errore = nil; await store.aggiorna(jsoc) } catch { errore = error.localizedDescription } }
        } label: {
            Label(t, systemImage: icona).font(.system(size: 12.5, weight: .heavy)).foregroundStyle(c)
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.stroke))
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: - Spese (come Splitwise)

struct SpeseView: View {
    let evento: JEvento
    @ObservedObject private var jsoc = JsocClient.shared
    @State private var dati: JSpese?
    @State private var errore: String?
    @State private var nuova = false
    @State private var anticipo = false
    @State private var pareggia = false
    @State private var aperta: JSpesa?

    var io: Int? { jsoc.utente?.id }
    var gestore: Bool { jsoc.utente?.direttivo == true || evento.staff }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    CopertinaEvento(evento: evento, altezza: 150)
                        .overlay(alignment: .bottomLeading) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Spese · \(evento.nome)").font(.system(size: 22, weight: .black)).lineLimit(2)
                                Text("\(dati?.persone.filter { $0.id != 0 }.count ?? 0) persone · totale \(euro(dati?.totale ?? 0))")
                                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                            }
                            .padding(14)
                        }
                        .overlay(LinearGradient(colors: [.clear, Theme.bg.opacity(0.9)], startPoint: .center, endPoint: .bottom).allowsHitTesting(false))
                    VStack(alignment: .leading, spacing: 12) {
                        riepilogo
                        HStack(spacing: 8) {
                            capsula("Pareggia", Theme.olive, pieno: true) { pareggia = true }
                            if gestore { capsula("Anticipo associazione", Theme.amber) { anticipo = true } }
                        }
                        if let errore { ErrorCard(text: errore) }
                        elenco
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 140)
                }
            }
            Button { haptic(); nuova = true } label: {
                Label("Aggiungi spesa", systemImage: "doc.text.fill").font(.system(size: 14, weight: .heavy)).foregroundStyle(.black)
                    .padding(.horizontal, 18).frame(height: 50).background(Theme.olive, in: Capsule())
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
            }
            .padding(.trailing, 16).padding(.bottom, 84)
        }
        .ignoresSafeArea(edges: .top)
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await carica() }
        .refreshable { await carica() }
        .sheet(isPresented: $nuova) { if let d = dati { AggiungiSpesaView(evento: evento, dati: d, anticipo: false) { dati = $0 } } }
        .sheet(isPresented: $anticipo) { if let d = dati { AggiungiSpesaView(evento: evento, dati: d, anticipo: true) { dati = $0 } } }
        .sheet(isPresented: $pareggia) { if let d = dati { PareggiaView(evento: evento, dati: d) { dati = $0 } } }
        .sheet(item: $aperta) { s in DettaglioSpesa(spesa: s, dati: dati, puoTogliere: s.autore == io || jsoc.utente?.direttivo == true) { dati = $0 } }
    }

    @ViewBuilder var riepilogo: some View {
        if let d = dati {
            let miei = d.debiti.filter { $0.da == io }
            let amme = d.debiti.filter { $0.a == io }
            VStack(alignment: .leading, spacing: 4) {
                if miei.isEmpty && amme.isEmpty { Text("Sei in pari").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.oliveBright) }
                ForEach(miei, id: \.self) { x in
                    (Text("Devi ") + Text(euro(x.importo)).foregroundColor(Theme.red).bold() + Text(" a \(d.nome(x.a))")).font(.system(size: 14))
                }
                ForEach(amme, id: \.self) { x in
                    (Text("\(d.nome(x.da)) ti deve ") + Text(euro(x.importo)).foregroundColor(Theme.oliveBright).bold()).font(.system(size: 14))
                }
            }
        } else {
            ProgressView().tint(Theme.olive)
        }
    }

    func capsula(_ t: String, _ c: Color, pieno: Bool = false, _ f: @escaping () -> Void) -> some View {
        Button { haptic(); f() } label: {
            Text(t).font(.system(size: 13, weight: .heavy)).foregroundStyle(pieno ? .black : c)
                .padding(.horizontal, 14).frame(height: 34)
                .background(pieno ? c : c.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(c.opacity(pieno ? 0 : 0.45)))
        }
    }

    enum Voce: Identifiable { case spesa(JSpesa), rimborso(JRimborso)
        var id: String { switch self { case .spesa(let s): return "s\(s.id)"; case .rimborso(let r): return "r\(r.id)" } }
        var ts: Double { switch self { case .spesa(let s): return s.ts ?? 0; case .rimborso(let r): return r.ts ?? 0 } }
    }

    @ViewBuilder var elenco: some View {
        if let d = dati {
            let voci = (d.spese.map { Voce.spesa($0) } + d.rimborsi.map { Voce.rimborso($0) }).sorted { $0.ts > $1.ts }
            if voci.isEmpty { Text("Nessuna spesa. Aggiungi la prima con il pulsante in basso.").font(.system(size: 13)).foregroundStyle(Theme.dim).padding(.top, 10) }
            VStack(spacing: 0) {
                ForEach(voci) { v in
                    switch v {
                    case .spesa(let s): Button { aperta = s } label: { riga(s, d) }.buttonStyle(.plain)
                    case .rimborso(let r): rigaRimborso(r, d)
                    }
                    Divider().overlay(Theme.stroke)
                }
            }
        }
    }

    static func icona(_ cat: String?) -> String {
        switch cat {
        case "benzina": return "fuelpump.fill"
        case "cibo": return "fork.knife"
        case "iscrizione": return "ticket.fill"
        case "materiale": return "cart.fill"
        case "alloggio": return "bed.double.fill"
        default: return "doc.text.fill"
        }
    }

    func giorno(_ ts: Double?, _ data: String?) -> some View {
        let d = JEvento.data(data) ?? Date(timeIntervalSince1970: ts ?? 0)
        return VStack(spacing: 0) {
            Text(d.formatted(.dateTime.month(.abbreviated))).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.dim)
            Text(d.formatted(.dateTime.day())).font(Theme.mono(14, .heavy))
        }
        .frame(width: 30)
    }

    func riga(_ s: JSpesa, _ d: JSpese) -> some View {
        let mia = s.quota(io)
        let (etichetta, valore, colore): (String, String, Color) = {
            if s.pagato_da == io { return ("hai prestato", euro(s.importo - mia), Theme.oliveBright) }
            if mia > 0 { return ("devi restituire", euro(mia), Theme.red) }
            return ("non coinvolto", "", Theme.dim)
        }()
        return HStack(spacing: 10) {
            giorno(s.ts, s.data)
            Image(systemName: Self.icona(s.categoria)).font(.system(size: 17)).foregroundStyle(s.pagato_da == 0 ? Theme.amber : Theme.dim)
                .frame(width: 38, height: 38).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(s.descrizione).font(.system(size: 14.5, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                Text(s.pagato_da == io ? "Hai pagato \(euro(s.importo))" : "\(d.nome(s.pagato_da)) ha pagato \(euro(s.importo))")
                    .font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(etichetta).font(.system(size: 10, weight: .bold)).foregroundStyle(colore)
                if !valore.isEmpty { Text(valore).font(Theme.mono(14, .heavy)).foregroundStyle(colore) }
            }
            if !(s.foto ?? "").isEmpty { Image(systemName: "paperclip").font(.caption).foregroundStyle(Theme.dim) }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    func rigaRimborso(_ r: JRimborso, _ d: JSpese) -> some View {
        HStack(spacing: 10) {
            giorno(r.ts, nil)
            Image(systemName: "banknote.fill").font(.system(size: 16)).foregroundStyle(Theme.oliveBright)
                .frame(width: 38, height: 38).background(Theme.olive.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            Text("\(r.da == io ? "Hai" : d.nome(r.da) + " ha") pagato \(euro(r.importo)) a \(r.a == io ? "te" : d.nome(r.a))")
                .font(.system(size: 12)).foregroundStyle(Theme.dim)
            Spacer()
        }
        .padding(.vertical, 8)
    }

    func carica() async {
        do { dati = try await jsoc.spese(evento.id); errore = nil } catch { errore = error.localizedDescription }
    }
}

/// Aggiungi una spesa: chi ha pagato e come dividere (=, importi esatti, percentuali, quote).
struct AggiungiSpesaView: View {
    let evento: JEvento
    let dati: JSpese
    let anticipo: Bool
    var fatto: (JSpese) -> Void
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var jsoc = JsocClient.shared
    @State private var descrizione = ""
    @State private var importo = ""
    @State private var pagatoDa = 0
    @State private var data = Date()
    @State private var categoria = "altro"
    @State private var nota = ""
    @State private var modo = "uguali"
    @State private var dentro: Set<Int> = []
    @State private var valori: [Int: String] = [:]
    @State private var foto: PhotosPickerItem?
    @State private var scontrino: UIImage?
    @State private var lavoro = false
    @State private var errore: String?

    var persone: [JPersonaSpese] { dati.persone.filter { $0.id != 0 } }
    var totale: Double { Double(importo.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Descrizione (es. Benzina)", text: $descrizione).font(.system(size: 18, weight: .semibold))
                    HStack {
                        Text("€").font(.system(size: 22)).foregroundStyle(Theme.dim)
                        TextField("0,00", text: $importo).keyboardType(.decimalPad).font(Theme.mono(28, .heavy))
                    }
                }
                Section {
                    if anticipo {
                        Label("Pagato dall'associazione: i partecipanti la restituiscono all'associazione", systemImage: "building.columns.fill")
                            .font(.footnote).foregroundStyle(Theme.amber)
                    } else {
                        Picker("Pagato da", selection: $pagatoDa) {
                            ForEach(persone) { p in Text(p.id == jsoc.utente?.id ? "te" : p.callsign).tag(p.id) }
                        }
                    }
                    DatePicker("Data", selection: $data, displayedComponents: .date)
                    Picker("Tipo", selection: $categoria) {
                        Text("Benzina").tag("benzina"); Text("Cibo").tag("cibo"); Text("Iscrizione").tag("iscrizione")
                        Text("Materiale").tag("materiale"); Text("Alloggio").tag("alloggio"); Text("Altro").tag("altro")
                    }
                    PhotosPicker(selection: $foto, matching: .images) {
                        Label(scontrino == nil ? "Foto dello scontrino" : "Scontrino allegato", systemImage: scontrino == nil ? "camera.fill" : "checkmark.circle.fill")
                    }
                    TextField("Nota", text: $nota)
                }
                Section {
                    Picker("Divisione", selection: $modo) {
                        Text("=").tag("uguali"); Text("1,23").tag("importi"); Text("%").tag("percentuali"); Text("quote").tag("quote")
                    }
                    .pickerStyle(.segmented)
                    ForEach(persone) { p in rigaPersona(p) }
                } header: {
                    Text(spiegazione)
                } footer: {
                    Text(piede).font(Theme.mono(12, .bold)).foregroundStyle(valida ? Theme.oliveBright : Theme.amber)
                }
                if let errore { Section { Text(errore).foregroundStyle(Theme.red) } }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(anticipo ? "Anticipo associazione" : "Aggiungi una spesa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salva") { salva() }.disabled(!valida || lavoro) }
            }
            .onAppear {
                pagatoDa = anticipo ? 0 : (jsoc.utente?.id ?? persone.first?.id ?? 0)
                dentro = Set(persone.map(\.id))
            }
            .onChange(of: foto) { f in
                Task { if let d = try? await f?.loadTransferable(type: Data.self), let i = UIImage(data: d) { scontrino = i } }
            }
        }
    }

    var spiegazione: String {
        switch modo {
        case "importi": return "Importi esatti: scrivi quanto spetta a ognuno"
        case "percentuali": return "Percentuali: il totale deve fare 100%"
        case "quote": return "Quote: es. 2 per chi ha portato un ospite"
        default: return "In parti uguali: scegli chi partecipa alla spesa"
        }
    }

    @ViewBuilder func rigaPersona(_ p: JPersonaSpese) -> some View {
        HStack {
            FotoSocio(id: p.id, iniziali: p.callsign, lato: 30)
            Text(p.id == jsoc.utente?.id ? "Tu" : p.callsign).font(.system(size: 14, weight: .semibold))
            Spacer()
            if modo == "uguali" {
                Text(dentro.contains(p.id) ? euro(divisione[p.id] ?? 0) : "—").font(Theme.mono(12)).foregroundStyle(Theme.dim)
                Image(systemName: dentro.contains(p.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(dentro.contains(p.id) ? Theme.olive : Theme.dim).font(.system(size: 22))
                    .onTapGesture { if dentro.contains(p.id) { dentro.remove(p.id) } else { dentro.insert(p.id) } }
            } else {
                TextField(modo == "percentuali" ? "%" : (modo == "quote" ? "quote" : "€"),
                          text: Binding(get: { valori[p.id] ?? "" }, set: { valori[p.id] = $0 }))
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80).font(Theme.mono(14, .bold))
                if modo != "importi" { Text(euro(divisione[p.id] ?? 0)).font(Theme.mono(11)).foregroundStyle(Theme.dim).frame(width: 70, alignment: .trailing) }
            }
        }
    }

    func numero(_ id: Int) -> Double { Double((valori[id] ?? "").replacingOccurrences(of: ",", with: ".")) ?? 0 }

    /// quanto spetta a ognuno, in euro (arrotondato al centesimo, il resto al primo)
    var divisione: [Int: Double] {
        var d: [Int: Double] = [:]
        switch modo {
        case "importi":
            for p in persone where numero(p.id) > 0 { d[p.id] = numero(p.id) }
            return d
        case "percentuali":
            for p in persone where numero(p.id) > 0 { d[p.id] = totale * numero(p.id) / 100 }
        case "quote":
            let tot = persone.map { numero($0.id) }.reduce(0, +)
            guard tot > 0 else { return [:] }
            for p in persone where numero(p.id) > 0 { d[p.id] = totale * numero(p.id) / tot }
        default:
            let chi = persone.filter { dentro.contains($0.id) }
            guard !chi.isEmpty else { return [:] }
            for p in chi { d[p.id] = totale / Double(chi.count) }
        }
        var arrotondati = d.mapValues { ($0 * 100).rounded(.down) / 100 }
        let resto = ((totale - arrotondati.values.reduce(0, +)) * 100).rounded() / 100
        if let primo = arrotondati.keys.sorted().first { arrotondati[primo, default: 0] += resto }
        return arrotondati
    }

    var somma: Double { divisione.values.reduce(0, +) }
    var valida: Bool {
        totale > 0 && !divisione.isEmpty && abs(somma - totale) < 0.02 && (modo != "percentuali" || abs(persone.map { numero($0.id) }.reduce(0, +) - 100) < 0.01)
    }
    var piede: String {
        if totale <= 0 { return "Scrivi l'importo" }
        switch modo {
        case "uguali": return dentro.isEmpty ? "Scegli almeno una persona" : "\(euro(totale / Double(dentro.count))) / persona (\(dentro.count) persone)"
        case "percentuali": return String(format: "%.0f%% su 100%%", persone.map { numero($0.id) }.reduce(0, +))
        default: return "\(euro(somma)) su \(euro(totale))" + (abs(somma - totale) < 0.02 ? " ✓" : "")
        }
    }

    func salva() {
        lavoro = true; errore = nil
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        let campi: [String: Any] = ["descrizione": descrizione.isEmpty ? "Spesa" : descrizione, "importo": totale, "pagato_da": anticipo ? 0 : pagatoDa,
                                    "data": f.string(from: data), "categoria": categoria, "nota": nota,
                                    "divisione": Dictionary(uniqueKeysWithValues: divisione.map { (String($0.key), $0.value) })]
        Task {
            do {
                var r = try await jsoc.nuovaSpesa(evento.id, campi)
                if let img = scontrino, let id = r.nuova, let d = img.ridotta(lato: 1600).jpegData(compressionQuality: 0.7) {
                    try? await jsoc.caricaDati("/api/spese/\(id)/foto", dati: d)
                    r = (try? await jsoc.spese(evento.id)) ?? r
                }
                fatto(r)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } catch { errore = error.localizedDescription }
            lavoro = false
        }
    }
}

/// Pareggia: segna come pagati i tuoi debiti (o quelli che ti devono).
struct PareggiaView: View {
    let evento: JEvento
    @State var dati: JSpese
    var fatto: (JSpese) -> Void
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var jsoc = JsocClient.shared
    @State private var errore: String?

    var body: some View {
        NavigationStack {
            List {
                let io = jsoc.utente?.id
                let rilevanti = dati.debiti.filter { $0.da == io || $0.a == io || jsoc.utente?.direttivo == true }
                if rilevanti.isEmpty { Text("Tutti in pari").foregroundStyle(Theme.oliveBright) }
                ForEach(rilevanti, id: \.self) { x in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(x.da == io ? "Tu" : dati.nome(x.da)) → \(x.a == io ? "te" : dati.nome(x.a))").font(.system(size: 15, weight: .bold))
                            Text(euro(x.importo)).font(Theme.mono(14, .heavy)).foregroundStyle(x.da == io ? Theme.red : Theme.oliveBright)
                        }
                        Spacer()
                        Button("Pagato") {
                            Task {
                                do { dati = try await jsoc.rimborso(evento.id, da: x.da, a: x.a, importo: x.importo); fatto(dati); haptic(.medium) }
                                catch { errore = error.localizedDescription }
                            }
                        }
                        .buttonStyle(.borderedProminent).tint(Theme.olive).foregroundStyle(.black)
                    }
                    .listRowBackground(Theme.surface)
                }
                if let errore { Text(errore).foregroundStyle(Theme.red) }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Pareggia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

struct DettaglioSpesa: View {
    let spesa: JSpesa
    let dati: JSpese?
    let puoTogliere: Bool
    var fatto: (JSpese) -> Void
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var jsoc = JsocClient.shared
    @State private var img: UIImage?
    @State private var conferma = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(spesa.descrizione).font(.system(size: 20, weight: .heavy))
                    Text(euro(spesa.importo)).font(Theme.mono(26, .heavy))
                    Text("Pagato da \(dati?.nome(spesa.pagato_da) ?? "?")").foregroundStyle(Theme.dim)
                    if let n = spesa.nota, !n.isEmpty { Text(n) }
                }
                Section("Divisa tra") {
                    ForEach(spesa.divisione.sorted { $0.key < $1.key }, id: \.key) { k, v in
                        HStack { Text(dati?.nome(Int(k) ?? -1) ?? k); Spacer(); Text(euro(v)).font(Theme.mono(13)) }
                    }
                }
                if let img { Section("Scontrino") { Image(uiImage: img).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 10)) } }
                if puoTogliere {
                    Section { Button("Elimina spesa", role: .destructive) { conferma = true } }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
            .task {
                if !(spesa.foto ?? "").isEmpty, let d = try? await jsoc.scaricaDati("/api/spese/\(spesa.id)/foto") { img = UIImage(data: d) }
            }
            .confirmationDialog("Eliminare la spesa?", isPresented: $conferma, titleVisibility: .visible) {
                Button("Elimina", role: .destructive) {
                    Task { if let r = try? await jsoc.cancellaSpesa(spesa.id) { fatto(r) }; dismiss() }
                }
            }
        }
    }
}
