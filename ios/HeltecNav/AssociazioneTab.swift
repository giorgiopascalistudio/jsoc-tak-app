import SwiftUI
import QuickLook

// MARK: - Scheda Associazione (stile Spond)

struct AssociazioneTab: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var home = HomeModel.shared

    var direttivo: Bool { jsoc.utente?.direttivo == true }

    var body: some View {
        let _ = Contatori.disegno("AssociazioneTab")
        NavigationStack {
            Group {
                if jsoc.collegato { contenuto } else { EntraView() }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Associazione")
        }
    }

    var contenuto: some View { AssociazioneHomeV2() }

    func conta(_ n: Int?, _ t: String) -> String { (n ?? 0) > 0 ? "\(n!) \(t)" : "tutto letto" }

    func voce<D: View>(_ icona: String, _ titolo: String, _ sotto: String, @ViewBuilder dest: @escaping () -> D) -> some View {
        NavigationLink { dest() } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icona).font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.olive)
                Text(titolo).font(.headline).foregroundStyle(.white)
                Text(sotto).font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Theme.surface2, Theme.surface], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 0.75))
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: - piccoli aiuti comuni

struct Campo: View {
    let titolo: String
    @Binding var testo: String
    var tastiera: UIKeyboardType = .default
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(titolo.uppercased()).font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(1).foregroundStyle(Theme.dim)
            TextField(titolo, text: $testo).keyboardType(tastiera)
                .padding(10).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct Caricamento: ViewModifier {
    let errore: String?
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let errore {
                Text(errore).font(.caption.weight(.semibold)).foregroundStyle(Theme.red)
                    .padding(10).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 20)
            }
        }
    }
}
extension View { func errore(_ e: String?) -> some View { modifier(Caricamento(errore: e)) } }

extension View {
    /// lista con lo sfondo dell'app
    func listaJSOC() -> some View { self.scrollContentBackground(.hidden).background(Theme.bg.ignoresSafeArea()) }
}

// MARK: - Bacheca

struct BachecaSociView: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @State private var post: [JPost] = []
    @State private var errore: String?
    @State private var scrivi = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if post.isEmpty { Text("Nessun annuncio").foregroundStyle(Theme.dim).padding(.top, 40) }
                ForEach(post) { p in PostCard(post: p) { post = $0 } }
            }
            .padding(14)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Bacheca")
        .toolbar {
            if PermessiStore.shared.puo("avvisi") {
                Button { scrivi = true } label: { Image(systemName: "square.and.pencil") }
            }
        }
        .sheet(isPresented: $scrivi) { NuovoPostSheet { post = $0 } }
        .task { await carica() }
        .refreshable { await carica() }
        .errore(errore)
    }

    func carica() async {
        do { post = try await jsoc.bacheca(); errore = nil } catch { errore = error.localizedDescription }
        // gli avvisi con conferma restano "da leggere" finché il socio non tocca Ho letto
        for p in post where !p.letto && !p.chiedeConferma { await jsoc.letto(p.id) }
        await HomeModel.shared.aggiorna()
    }
}

struct PostCard: View {
    let post: JPost
    var aggiornato: ([JPost]) -> Void
    @State private var commento = ""
    @State private var aperto = false
    @State private var letture: [JLettura]?
    @State private var modifica = false
    @State private var titoloM = ""
    @State private var testoM = ""
    @State private var chiediElimina = false
    var mio: Bool { post.autore == JsocClient.shared.utente?.id }
    var direttivo: Bool { JsocClient.shared.utente?.direttivo == true }

    func ricarica() async { if let p = try? await JsocClient.shared.bacheca() { aggiornato(p) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                FotoSocio(id: post.autore, iniziali: post.callsign ?? "?", lato: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(post.callsign ?? "?").font(Theme.mono(12, .bold))
                    Text(Date(timeIntervalSince1970: post.ts).formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(Theme.dim)
                }
                Spacer()
                if post.fissato == 1 { Image(systemName: "pin.fill").foregroundStyle(Theme.amber) }
                if !post.letto { Circle().fill(Theme.olive).frame(width: 8, height: 8) }
                if mio || direttivo {
                    Menu {
                        Button { titoloM = post.titolo ?? ""; testoM = post.testo; modifica = true } label: { Label("Modifica", systemImage: "pencil") }
                        if direttivo { Button(role: .destructive) { chiediElimina = true } label: { Label("Elimina", systemImage: "trash") } }
                    } label: { Image(systemName: "ellipsis").padding(6).foregroundStyle(Theme.dim) }
                }
            }
            if let t = post.titolo, !t.isEmpty { Text(t).font(.headline) }
            Text(post.testo).font(.subheadline)
            if post.chiedeConferma && !post.letto {
                Button {
                    Task {
                        await JsocClient.shared.letto(post.id)
                        if let p = try? await JsocClient.shared.bacheca() { aggiornato(p) }
                        await HomeModel.shared.aggiorna()
                    }
                } label: { Label("Ho letto", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity) }
                .buttonStyle(PrimaryButtonStyle())
            }
            HStack {
                if PermessiStore.shared.puo("avvisi") {
                    Button {
                        Task { letture = try? await JsocClient.shared.letture(post.id) }
                    } label: { Label("Letto da \(post.letto_da)/\(post.destinatari)", systemImage: post.chiedeConferma ? "checkmark.seal" : "eye").font(.caption2) }
                    .tint(Theme.dim)
                } else {
                    Label("Letto da \(post.letto_da)/\(post.destinatari)", systemImage: "eye").font(.caption2).foregroundStyle(Theme.dim)
                }
                Spacer()
                Button { withAnimation { aperto.toggle() } } label: {
                    Label("\(post.commenti.count)", systemImage: "bubble.left").font(.caption.weight(.semibold))
                }
                .tint(Theme.olive)
            }
            if aperto {
                ForEach(post.commenti) { c in
                    HStack(alignment: .top, spacing: 6) {
                        Text(c.callsign ?? "?").font(Theme.mono(11, .bold)).foregroundStyle(Theme.olive)
                        Text(c.testo).font(.caption)
                        Spacer(minLength: 0)
                    }
                    .contextMenu {
                        if c.autore == JsocClient.shared.utente?.id || direttivo {
                            Button(role: .destructive) { Task { try? await JsocClient.shared.modificaCommento(c.id, ""); await ricarica() } } label: {
                                Label("Elimina commento", systemImage: "trash")
                            }
                        }
                    }
                }
                HStack {
                    TextField("Commenta…", text: $commento).font(.caption)
                        .padding(8).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 8))
                    Button {
                        let t = commento; commento = ""
                        Task { if let p = try? await JsocClient.shared.commenta(post.id, t) { aggiornato(p) } }
                    } label: { Image(systemName: "paperplane.fill") }
                        .tint(Theme.olive).disabled(commento.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(post.chiedeConferma && !post.letto ? Theme.amber : post.fissato == 1 ? Theme.amber.opacity(0.5) : Theme.stroke, lineWidth: post.chiedeConferma && !post.letto ? 1.5 : 0.75))
        .confirmationDialog("Eliminare l'avviso?", isPresented: $chiediElimina, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) { Task { try? await JsocClient.shared.cancellaPost(post.id); await ricarica() } }
        } message: { Text("Spariscono anche commenti e letture.") }
        .sheet(isPresented: $modifica) {
            NavigationStack {
                Form {
                    TextField("Titolo", text: $titoloM)
                    TextField("Testo", text: $testoM, axis: .vertical).lineLimit(4...14)
                }
                .listaJSOC().navigationTitle("Modifica avviso").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annulla") { modifica = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Salva") {
                            Task { try? await JsocClient.shared.modificaPost(post.id, titolo: titoloM, testo: testoM); await ricarica(); modifica = false }
                        }
                        .disabled(testoM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: Binding(get: { letture != nil }, set: { if !$0 { letture = nil } })) {
            NavigationStack {
                List {
                    let l = letture ?? []
                    Section("Non hanno ancora letto (\(l.filter { !$0.letto }.count))") {
                        ForEach(l.filter { !$0.letto }, id: \.callsign) { Text($0.callsign).font(Theme.mono(14, .bold)) }
                    }
                    Section("Hanno letto (\(l.filter(\.letto).count))") {
                        ForEach(l.filter(\.letto), id: \.callsign) { x in
                            HStack {
                                Text(x.callsign).font(Theme.mono(14, .bold))
                                Spacer()
                                if let t = x.ts { Text(Date(timeIntervalSince1970: t).formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(Theme.dim) }
                            }
                        }
                    }
                }
                .listaJSOC().navigationTitle("Letture").navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
    }
}

struct NuovoPostSheet: View {
    var fatto: ([JPost]) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var titolo = ""
    @State private var testo = ""
    @State private var fissato = false
    @State private var conferma = false
    @State private var errore: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Titolo", text: $titolo)
                TextField("Testo dell'annuncio", text: $testo, axis: .vertical).lineLimit(4...12)
                Toggle("Fissa in alto", isOn: $fissato)
                Toggle("Chiedi conferma di lettura", isOn: $conferma)
                if let errore { Text(errore).foregroundStyle(Theme.red) }
            }
            .listaJSOC()
            .navigationTitle("Nuovo annuncio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pubblica") {
                        Task {
                            do { fatto(try await JsocClient.shared.nuovoPost(titolo: titolo, testo: testo, fissato: fissato, conferma: conferma)); dismiss() }
                            catch { errore = error.localizedDescription }
                        }
                    }
                    .disabled(testo.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Calendario (tutti gli eventi con la risposta)

struct CalendarioView: View {
    @ObservedObject private var store = EventoStore.shared

    var body: some View {
        let prossimi = store.eventi.filter { $0.fase != 2 }.sorted { ($0.dataInizio ?? .distantFuture) < ($1.dataInizio ?? .distantFuture) }
        let passati = store.eventi.filter { $0.fase == 2 }
        ScrollView {
            VStack(spacing: 10) {
                if !prossimi.isEmpty { SectionLabel(text: "In programma", icon: "calendar") }
                ForEach(prossimi) { e in NavigationLink { EventoView(evento: e) } label: { EventoRiga(evento: e, attivo: e.id == store.corrente?.id) }.buttonStyle(PressStyle()) }
                if !passati.isEmpty { SectionLabel(text: "Passati", icon: "clock.arrow.circlepath").padding(.top, 8) }
                ForEach(passati) { e in NavigationLink { EventoView(evento: e) } label: { EventoRiga(evento: e) }.buttonStyle(PressStyle()) }
            }
            .padding(14)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Calendario")
        .refreshable { await store.aggiorna(JsocClient.shared) }
    }
}

// MARK: - Soci

struct SociView: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @State private var dati: JSoci?
    @State private var cerca = ""
    @State private var errore: String?
    @State private var invito = false

    var direttivo: Bool { jsoc.utente?.direttivo == true }

    var body: some View {
        List {
            let soci = (dati?.soci ?? []).filter { cerca.isEmpty || ($0.callsign + " " + $0.nome).localizedCaseInsensitiveContains(cerca) }
            ForEach(soci) { s in
                NavigationLink { SocioView(socio: s, gruppi: dati?.gruppi ?? []) { _ in Task { await carica() } } } label: {
                    HStack(spacing: 10) {
                        FotoSocio(id: s.id, iniziali: s.callsign, lato: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(s.callsign).font(Theme.mono(14, .bold))
                                if s.direttivo { Text("DIRETTIVO").font(.system(size: 8, weight: .heavy)).foregroundStyle(Theme.cyan) }
                                if s.attivo == 0 { Text("SOSPESO").font(.system(size: 8, weight: .heavy)).foregroundStyle(Theme.red) }
                            }
                            Text(s.nome).font(.caption).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        if direttivo {
                            VStack(alignment: .trailing, spacing: 3) {
                                stato("cross.case.fill", s.giorniCertificato)
                                if let q = s.quota_pagata {
                                    Image(systemName: "eurosign.circle.fill").font(.caption).foregroundStyle(q == 1 ? Theme.green : Theme.amber)
                                }
                            }
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            }
        }
        .listaJSOC()
        .searchable(text: $cerca, prompt: "Cerca socio")
        .navigationTitle("Soci")
        .toolbar {
            if direttivo { Button { invito = true } label: { Image(systemName: "person.badge.plus") } }
        }
        .sheet(isPresented: $invito) { InvitoSheet() }
        .task { await carica() }
        .refreshable { await carica() }
        .errore(errore)
    }

    func stato(_ icona: String, _ giorni: Int?) -> some View {
        Image(systemName: icona).font(.caption)
            .foregroundStyle(giorni == nil ? Theme.dim : (giorni! < 0 ? Theme.red : (giorni! <= 30 ? Theme.amber : Theme.green)))
    }

    func carica() async {
        do { dati = try await jsoc.soci(); errore = nil } catch { errore = error.localizedDescription }
    }
}

struct SocioView: View {
    @State var socio: JProfilo
    let gruppi: [JGruppo]
    var salvato: (JProfilo) -> Void
    @ObservedObject private var jsoc = JsocClient.shared
    @State private var errore: String?
    @State private var ok = false

    var direttivo: Bool { jsoc.utente?.direttivo == true }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    FotoSocio(id: socio.id, iniziali: socio.callsign, lato: 64)
                    VStack(alignment: .leading) {
                        Text(socio.callsign).font(Theme.mono(20, .heavy))
                        Text(socio.nome).foregroundStyle(Theme.dim)
                    }
                }
            }
            .listRowBackground(Color.clear)
            if direttivo || PermessiStore.shared.gestione {
                Section {
                    NavigationLink { SchedaSocioView(id: socio.id) } label: {
                        Label("Scheda completa: presenze, quote, tessera, cassa", systemImage: "person.text.rectangle.fill")
                    }
                }
            }
            if direttivo {
                Section("Anagrafica") {
                    TextField("Nome e cognome", text: $socio.nome)
                    TextField("Email", text: bind(\.email)).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    TextField("Telefono", text: bind(\.telefono)).keyboardType(.phonePad)
                    TextField("Nascita (AAAA-MM-GG)", text: bind(\.nascita))
                    TextField("Luogo di nascita", text: bind(\.luogo_nascita))
                    TextField("Codice fiscale", text: bind(\.cf)).textInputAutocapitalization(.characters)
                    TextField("Indirizzo", text: bind(\.indirizzo))
                }
                Section("Tessera e certificato") {
                    TextField("Numero tessera", text: bind(\.tessera))
                    TextField("Scadenza tessera (AAAA-MM-GG)", text: bind(\.tessera_scadenza))
                    TextField("Scadenza certificato medico (AAAA-MM-GG)", text: bind(\.certificato_scadenza))
                }
                Section("Ruolo") {
                    Picker("Ruolo", selection: $socio.ruolo) {
                        Text("Socio").tag("socio")
                        Text("Direttivo").tag("direttivo")
                    }
                    Toggle("Attivo", isOn: Binding(get: { socio.attivo != 0 }, set: { socio.attivo = $0 ? 1 : 0 }))
                    if !gruppi.isEmpty {
                        ForEach(gruppi) { g in
                            Toggle(g.nome, isOn: Binding(get: { (socio.gruppi ?? []).contains(g.id) }, set: { on in
                                var l = socio.gruppi ?? []
                                if on { l.append(g.id) } else { l.removeAll { $0 == g.id } }
                                socio.gruppi = l
                            }))
                        }
                    }
                }
                Section("Emergenza") {
                    TextField("Gruppo sanguigno", text: bind(\.gruppo_sanguigno))
                    TextField("Contatto di emergenza", text: bind(\.emergenza))
                }
                if let errore { Text(errore).foregroundStyle(Theme.red) }
            } else {
                Section { Text("Contatta \(socio.callsign) dalla chat degli eventi.").foregroundStyle(Theme.dim) }
            }
        }
        .listaJSOC()
        .navigationTitle(socio.callsign)
        .toolbar {
            if direttivo {
                Button(ok ? "Salvato" : "Salva") {
                    Task {
                        do {
                            var campi: [String: Any] = ["nome": socio.nome, "ruolo": socio.ruolo, "attivo": socio.attivo != 0,
                                                        "gruppi": socio.gruppi ?? []]
                            for (k, v) in [("email", socio.email), ("telefono", socio.telefono), ("nascita", socio.nascita),
                                           ("luogo_nascita", socio.luogo_nascita), ("cf", socio.cf), ("indirizzo", socio.indirizzo),
                                           ("tessera", socio.tessera), ("tessera_scadenza", socio.tessera_scadenza),
                                           ("certificato_scadenza", socio.certificato_scadenza), ("gruppo_sanguigno", socio.gruppo_sanguigno),
                                           ("emergenza", socio.emergenza)] { campi[k] = v ?? "" }
                            let s = try await jsoc.salvaSocio(socio.id, campi)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            ok = true; errore = nil
                            salvato(s)
                        } catch { errore = error.localizedDescription }
                    }
                }
            }
        }
    }

    func bind(_ k: WritableKeyPath<JProfilo, String?>) -> Binding<String> {
        Binding(get: { socio[keyPath: k] ?? "" }, set: { socio[keyPath: k] = $0; ok = false })
    }
}

// MARK: - Gruppi

struct GruppiView: View {
    @State private var dati: JSoci?
    @State private var nuovo = ""
    @State private var errore: String?

    var body: some View {
        List {
            Section("Nuovo gruppo") {
                HStack {
                    TextField("Nome (es. Squadra Alfa, Istruttori)", text: $nuovo)
                    Button("Crea") {
                        Task {
                            do { _ = try await JsocClient.shared.salvaGruppo(nil, ["nome": nuovo]); nuovo = ""; await carica() }
                            catch { errore = error.localizedDescription }
                        }
                    }
                    .disabled(nuovo.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .listRowBackground(Theme.surface)
            ForEach(dati?.gruppi ?? []) { g in
                Section(g.nome) {
                    ForEach(dati?.soci ?? []) { s in
                        let dentro = (s.gruppi ?? []).contains(g.id)
                        Button {
                            var membri = (dati?.soci ?? []).filter { ($0.gruppi ?? []).contains(g.id) }.map(\.id)
                            if dentro { membri.removeAll { $0 == s.id } } else { membri.append(s.id) }
                            Task { _ = try? await JsocClient.shared.salvaGruppo(g.id, ["membri": membri]); await carica() }
                        } label: {
                            HStack {
                                Text(s.callsign).font(Theme.mono(13, .bold)).foregroundStyle(.white)
                                Spacer()
                                Image(systemName: dentro ? "checkmark.circle.fill" : "circle").foregroundStyle(dentro ? Theme.olive : Theme.dim)
                            }
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            }
        }
        .listaJSOC()
        .navigationTitle("Gruppi")
        .task { await carica() }
        .errore(errore)
    }

    func carica() async {
        do { dati = try await JsocClient.shared.soci() } catch { errore = error.localizedDescription }
    }
}

// MARK: - Sondaggi

struct SondaggiView: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @State private var lista: [JSondaggio] = []
    @State private var nuovo = false
    @State private var errore: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if lista.isEmpty { Text("Nessun sondaggio").foregroundStyle(Theme.dim).padding(.top, 40) }
                ForEach(lista) { s in sondaggio(s) }
            }
            .padding(14)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Sondaggi")
        .toolbar { if jsoc.utente?.direttivo == true { Button { nuovo = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $nuovo) { NuovoSondaggioSheet { lista = $0 } }
        .task { await carica() }
        .refreshable { await carica() }
        .errore(errore)
    }

    func sondaggio(_ s: JSondaggio) -> some View {
        let tot = max(1, s.opzioni.map(\.voti).reduce(0, +))
        return Card(title: s.chiuso ? "Chiuso" : (s.multipla == 1 ? "Più risposte" : "Una risposta"), icon: "chart.bar.fill",
                    trailing: "\(s.votanti) votanti") {
            Text(s.domanda).font(.headline)
            ForEach(Array(s.opzioni.enumerated()), id: \.offset) { i, o in
                let mio = s.miei.contains(i)
                Button {
                    guard !s.chiuso else { return }
                    var scelte = s.multipla == 1 ? s.miei : []
                    if mio { scelte.removeAll { $0 == i } } else { scelte.append(i) }
                    Task {
                        do { lista = try await jsoc.vota(s.id, scelte); haptic(); await HomeModel.shared.aggiorna() }
                        catch { errore = error.localizedDescription }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: mio ? "checkmark.circle.fill" : "circle").foregroundStyle(mio ? Theme.olive : Theme.dim)
                            Text(o.testo).foregroundStyle(.white)
                            Spacer()
                            Text("\(o.voti)").font(Theme.mono(13, .bold)).foregroundStyle(Theme.olive)
                        }
                        GeometryReader { g in
                            Capsule().fill(Theme.olive.opacity(0.7)).frame(width: g.size.width * CGFloat(o.voti) / CGFloat(tot))
                        }
                        .frame(height: 4)
                        .background(Capsule().fill(Theme.surface2))
                        let chi = o.chi.compactMap { $0 }
                        if !chi.isEmpty { Text(chi.joined(separator: ", ")).font(.caption2).foregroundStyle(Theme.dim) }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    func carica() async {
        do { lista = try await jsoc.sondaggi(); errore = nil } catch { errore = error.localizedDescription }
    }
}

struct NuovoSondaggioSheet: View {
    var fatto: ([JSondaggio]) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var domanda = ""
    @State private var opzioni = ["", ""]
    @State private var multipla = false
    @State private var anonimo = false
    @State private var errore: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Domanda", text: $domanda)
                Section("Opzioni") {
                    ForEach(opzioni.indices, id: \.self) { i in TextField("Opzione \(i + 1)", text: $opzioni[i]) }
                    Button("Aggiungi opzione") { opzioni.append("") }
                }
                Toggle("Più risposte", isOn: $multipla)
                Toggle("Anonimo", isOn: $anonimo)
                if let errore { Text(errore).foregroundStyle(Theme.red) }
            }
            .listaJSOC()
            .navigationTitle("Nuovo sondaggio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crea") {
                        Task {
                            do {
                                fatto(try await JsocClient.shared.nuovoSondaggio(domanda, opzioni.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                                                                                  multipla: multipla, anonimo: anonimo))
                                dismiss()
                            } catch { errore = error.localizedDescription }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Quote

struct QuoteView: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @State private var anno = Calendar.current.component(.year, from: Date())
    @State private var dati: JQuote?
    @State private var importo = "50"
    @State private var errore: String?

    var direttivo: Bool { jsoc.utente?.direttivo == true }

    var body: some View {
        List {
            Section {
                Stepper("Anno \(String(anno))", value: $anno, in: 2020...2100)
            }
            .listRowBackground(Theme.surface)
            if direttivo {
                let q = dati?.quote ?? []
                let pagate = q.filter { $0.pagata == 1 }
                Section("Riepilogo") {
                    HStack { Text("Pagate"); Spacer(); Text("\(pagate.count)/\(q.count) · \(euro(pagate.compactMap(\.importo).reduce(0, +)))").font(Theme.mono(13, .bold)) }
                    HStack {
                        TextField("Importo", text: $importo).keyboardType(.decimalPad).frame(width: 90)
                        Button("Chiedi la quota a tutti") {
                            Task { await salva(["tutti": true, "anno": anno, "importo": Double(importo.replacingOccurrences(of: ",", with: ".")) ?? 0]) }
                        }
                    }
                }
                .listRowBackground(Theme.surface)
                Section("Soci") {
                    ForEach(q) { x in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(x.callsign ?? "?").font(Theme.mono(13, .bold))
                                Text(x.importo == nil ? "nessuna richiesta" : euro(x.importo) + (x.pagata == 1 ? " · pagata il \(dataIT(x.data))" : " · da pagare"))
                                    .font(.caption).foregroundStyle(x.pagata == 1 ? Theme.green : Theme.dim)
                            }
                            Spacer()
                            if x.importo != nil {
                                Button(x.pagata == 1 ? "Annulla" : "Incassata") {
                                    Task { await salva(["utente": x.utente, "anno": anno, "pagata": x.pagata != 1]) }
                                }
                                .buttonStyle(.bordered).tint(x.pagata == 1 ? Theme.dim : Theme.olive)
                            }
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            } else {
                Section("La mia quota") {
                    if let x = dati?.quote.first {
                        HStack {
                            Text(euro(x.importo)).font(Theme.mono(20, .heavy))
                            Spacer()
                            Text(x.pagata == 1 ? "PAGATA \(dataIT(x.data))" : "DA PAGARE").font(Theme.mono(12, .heavy))
                                .foregroundStyle(x.pagata == 1 ? Theme.green : Theme.amber)
                        }
                        if x.pagata != 1 { Text("Paga al direttivo: lo segnerà come incassata.").font(.caption).foregroundStyle(Theme.dim) }
                    } else {
                        Text("Nessuna quota richiesta per il \(String(anno))").foregroundStyle(Theme.dim)
                    }
                }
                .listRowBackground(Theme.surface)
            }
        }
        .listaJSOC()
        .navigationTitle("Quote")
        .task(id: anno) { await carica() }
        .errore(errore)
    }

    func carica() async {
        do { dati = try await jsoc.quote(anno: anno); errore = nil } catch { errore = error.localizedDescription }
    }

    func salva(_ campi: [String: Any]) async {
        do { dati = try await jsoc.salvaQuota(campi); haptic(); errore = nil } catch { errore = error.localizedDescription }
    }
}

// MARK: - Cassa

struct CassaView: View {
    @State private var anno = Calendar.current.component(.year, from: Date())
    @State private var dati: JCassa?
    @State private var nuovo = false
    @State private var errore: String?

    var body: some View {
        List {
            Section {
                Stepper("Anno \(String(anno))", value: $anno, in: 2020...2100)
                if let d = dati {
                    HStack(spacing: 10) {
                        totale("Entrate", d.entrate, Theme.green)
                        totale("Uscite", d.uscite, Theme.red)
                        totale("Saldo cassa", d.saldo_totale, Theme.olive)
                    }
                }
            }
            .listRowBackground(Theme.surface)
            if let d = dati, !d.categorie.isEmpty {
                Section("Per categoria") {
                    ForEach(d.categorie, id: \.self) { c in
                        HStack {
                            Image(systemName: c.tipo == "entrata" ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                .foregroundStyle(c.tipo == "entrata" ? Theme.green : Theme.red)
                            Text(c.categoria.capitalized)
                            Spacer()
                            Text(euro(c.totale)).font(Theme.mono(13, .semibold))
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            }
            Section("Movimenti") {
                ForEach(dati?.movimenti ?? []) { m in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.descrizione?.isEmpty == false ? m.descrizione! : (m.categoria ?? "")).font(.subheadline)
                            Text("\(dataIT(m.data)) · \(m.categoria ?? "")").font(.caption2).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        Text((m.tipo == "entrata" ? "+" : "−") + euro(m.importo)).font(Theme.mono(13, .bold))
                            .foregroundStyle(m.tipo == "entrata" ? Theme.green : Theme.red)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { try? await JsocClient.shared.cancellaMovimento(m.id); await carica() }
                        } label: { Label("Elimina", systemImage: "trash") }
                    }
                }
            }
            .listRowBackground(Theme.surface)
        }
        .listaJSOC()
        .navigationTitle("Cassa")
        .toolbar { Button { nuovo = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $nuovo) { MovimentoSheet { Task { await carica() } } }
        .task(id: anno) { await carica() }
        .errore(errore)
    }

    func totale(_ t: String, _ v: Double, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t.uppercased()).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(Theme.dim)
            Text(euro(v)).font(Theme.mono(13, .heavy)).foregroundStyle(c).minimumScaleFactor(0.6).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func carica() async {
        do { dati = try await JsocClient.shared.cassa(anno: anno); errore = nil } catch { errore = error.localizedDescription }
    }
}

struct MovimentoSheet: View {
    var fatto: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var tipo = "uscita"
    @State private var importo = ""
    @State private var categoria = "campo"
    @State private var descrizione = ""
    @State private var data = Date()
    @State private var errore: String?
    let categorie = ["quote", "campo", "materiale", "gare", "assicurazione", "eventi", "donazioni", "altro"]

    var body: some View {
        NavigationStack {
            Form {
                Picker("", selection: $tipo) { Text("Uscita").tag("uscita"); Text("Entrata").tag("entrata") }.pickerStyle(.segmented)
                TextField("Importo (€)", text: $importo).keyboardType(.decimalPad)
                Picker("Categoria", selection: $categoria) { ForEach(categorie, id: \.self) { Text($0.capitalized).tag($0) } }
                TextField("Descrizione", text: $descrizione)
                DatePicker("Data", selection: $data, displayedComponents: .date)
                if let errore { Text(errore).foregroundStyle(Theme.red) }
            }
            .listaJSOC()
            .navigationTitle("Movimento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        Task {
                            do {
                                _ = try await JsocClient.shared.nuovoMovimento(["tipo": tipo, "importo": Double(importo.replacingOccurrences(of: ",", with: ".")) ?? 0,
                                                                                "categoria": categoria, "descrizione": descrizione, "data": isoGiorno(data)])
                                fatto(); dismiss()
                            } catch { errore = error.localizedDescription }
                        }
                    }
                    .disabled(Double(importo.replacingOccurrences(of: ",", with: ".")) == nil)
                }
            }
        }
    }
}

// MARK: - Magazzino

struct MagazzinoView: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @State private var lista: [JMateriale] = []
    @State private var modifica: JMateriale?
    @State private var nuovo = false
    @State private var errore: String?

    var body: some View {
        let cat = Dictionary(grouping: lista) { ($0.categoria ?? "").isEmpty ? "Altro" : $0.categoria!.capitalized }
        List {
            if lista.isEmpty { Text("Magazzino vuoto").foregroundStyle(Theme.dim).listRowBackground(Theme.surface) }
            ForEach(cat.keys.sorted(), id: \.self) { k in
                Section(k) {
                    ForEach(cat[k] ?? []) { m in
                        Button { if jsoc.utente?.direttivo == true { modifica = m } } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.nome).foregroundStyle(.white)
                                    Text([m.assegnato_a.map { "a \($0)" }, m.note].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.caption2).foregroundStyle(Theme.dim)
                                }
                                Spacer()
                                Text("\(String(format: "%g", m.quantita ?? 1)) \(m.unita ?? "pz")").font(Theme.mono(13, .bold)).foregroundStyle(Theme.olive)
                                Circle().fill(m.stato == "ok" ? Theme.green : (m.stato == "guasto" ? Theme.red : Theme.amber)).frame(width: 8, height: 8)
                            }
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            }
        }
        .listaJSOC()
        .navigationTitle("Magazzino")
        .toolbar { if jsoc.utente?.direttivo == true { Button { nuovo = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $nuovo) { MaterialeSheet(materiale: nil) { Task { await carica() } } }
        .sheet(item: $modifica) { m in MaterialeSheet(materiale: m) { Task { await carica() } } }
        .task { await carica() }
        .refreshable { await carica() }
        .errore(errore)
    }

    func carica() async {
        do { lista = try await jsoc.materiale(); errore = nil } catch { errore = error.localizedDescription }
    }
}

struct MaterialeSheet: View {
    let materiale: JMateriale?
    var fatto: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var nome = ""
    @State private var categoria = ""
    @State private var quantita = "1"
    @State private var unita = "pz"
    @State private var stato = "ok"
    @State private var assegnato: Int?
    @State private var note = ""
    @State private var soci: [JProfilo] = []
    @State private var errore: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome (es. Radio Baofeng)", text: $nome)
                TextField("Categoria (comunicazioni, ottiche, campo…)", text: $categoria)
                HStack {
                    TextField("Quantità", text: $quantita).keyboardType(.decimalPad)
                    TextField("Unità", text: $unita).frame(width: 70)
                }
                Picker("Stato", selection: $stato) {
                    Text("Ok").tag("ok"); Text("Da controllare").tag("controllo"); Text("Guasto").tag("guasto")
                }
                Picker("Assegnato a", selection: $assegnato) {
                    Text("Magazzino").tag(Int?.none)
                    ForEach(soci) { Text($0.callsign).tag(Int?.some($0.id)) }
                }
                TextField("Note", text: $note)
                if let materiale {
                    Button("Elimina", role: .destructive) {
                        Task { try? await JsocClient.shared.cancellaMateriale(materiale.id); fatto(); dismiss() }
                    }
                }
                if let errore { Text(errore).foregroundStyle(Theme.red) }
            }
            .listaJSOC()
            .navigationTitle(materiale == nil ? "Nuovo materiale" : materiale!.nome)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        Task {
                            do {
                                var c: [String: Any] = ["nome": nome, "categoria": categoria, "quantita": Double(quantita.replacingOccurrences(of: ",", with: ".")) ?? 1,
                                                        "unita": unita, "stato": stato, "note": note]
                                c["assegnato"] = assegnato.map { $0 as Any } ?? NSNull()
                                _ = try await JsocClient.shared.salvaMateriale(materiale?.id, c)
                                fatto(); dismiss()
                            } catch { errore = error.localizedDescription }
                        }
                    }
                    .disabled(nome.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task {
                if let m = materiale {
                    nome = m.nome; categoria = m.categoria ?? ""; quantita = String(format: "%g", m.quantita ?? 1)
                    unita = m.unita ?? "pz"; stato = m.stato ?? "ok"; assegnato = m.assegnato; note = m.note ?? ""
                }
                soci = (try? await JsocClient.shared.soci().soci) ?? []
            }
        }
    }
}

// MARK: - Documenti dell'associazione

struct DocumentiAssociazioneView: View {
    @State private var file: [JFile] = []
    @State private var anteprima: URL?
    @State private var errore: String?
    @State private var scarica: String?
    @State private var importa = false
    @State private var cartella = "Generale"
    @State private var chiediCartella = false
    @State private var caricando = false
    @State private var daCancellare: JFile?
    @ObservedObject private var permessi = PermessiStore.shared

    var body: some View {
        let gruppi = Dictionary(grouping: file) { f -> String in
            let p = f.percorso.split(separator: "/")
            return p.count > 1 ? String(p[0]) : "Generale"
        }
        List {
            if file.isEmpty { Text("Nessun documento ancora.").foregroundStyle(Theme.dim).listRowBackground(Theme.surface) }
            if caricando { HStack { ProgressView(); Text("Carico…") }.listRowBackground(Theme.surface) }
            ForEach(gruppi.keys.sorted(), id: \.self) { g in
                Section(g) {
                    ForEach(gruppi[g] ?? [], id: \.percorso) { f in
                        Button { apri(f) } label: {
                            HStack {
                                Image(systemName: icona(f.percorso)).foregroundStyle(Theme.olive)
                                Text((f.percorso as NSString).lastPathComponent).foregroundStyle(.white)
                                Spacer()
                                if scarica == f.percorso { ProgressView() }
                                else { Text(ByteCountFormatter.string(fromByteCount: Int64(f.dim), countStyle: .file)).font(.caption2).foregroundStyle(Theme.dim) }
                            }
                        }
                        .swipeActions {
                            if permessi.puo("documenti") {
                                Button(role: .destructive) { daCancellare = f } label: { Label("Elimina", systemImage: "trash") }
                            }
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            }
        }
        .listaJSOC()
        .navigationTitle("Documenti")
        .toolbar {
            if permessi.puo("documenti") {
                Button { chiediCartella = true } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Carica un documento")
            }
        }
        .alert("In quale cartella?", isPresented: $chiediCartella) {
            TextField("Cartella (es. Verbali, Moduli, Statuto)", text: $cartella)
            Button("Scegli il file") { importa = true }
            Button("Annulla", role: .cancel) {}
        } message: { Text("Poi scegli il file da File, iCloud o dal telefono.") }
        .fileImporter(isPresented: $importa, allowedContentTypes: [.item], allowsMultipleSelection: true) { esito in
            guard case .success(let urls) = esito else { return }
            Task { await carica(urls) }
        }
        .confirmationDialog("Eliminare il documento?", isPresented: Binding(get: { daCancellare != nil }, set: { if !$0 { daCancellare = nil } }), titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                if let f = daCancellare {
                    Task {
                        do { let _: JOk = try await JsocClient.shared.send("/api/associazione/file/" + percorsoURL(f.percorso), "DELETE", [String: String]()); await carica() }
                        catch { errore = error.localizedDescription }
                    }
                }
            }
        }
        .quickLookPreview($anteprima)
        .task { await carica() }
        .refreshable { await carica() }
        .errore(errore)
    }

    func icona(_ p: String) -> String {
        switch (p as NSString).pathExtension.lowercased() {
        case "pdf": return "doc.richtext.fill"
        case "jpg", "jpeg", "png", "heic": return "photo.fill"
        case "xlsx", "xls", "csv": return "tablecells.fill"
        default: return "doc.fill"
        }
    }

    func carica() async {
        do { file = try await JsocClient.shared.documentiAssociazione(); errore = nil } catch { errore = error.localizedDescription }
    }

    func carica(_ urls: [URL]) async {
        caricando = true
        defer { caricando = false }
        let dir = cartella.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "-")
        for u in urls {
            let ok = u.startAccessingSecurityScopedResource()
            defer { if ok { u.stopAccessingSecurityScopedResource() } }
            guard let d = try? Data(contentsOf: u) else { errore = "Non riesco a leggere " + u.lastPathComponent; continue }
            let rel = (dir.isEmpty || dir == "Generale" ? "" : dir + "/") + u.lastPathComponent
            do { try await JsocClient.shared.caricaDati("/api/associazione/file/" + percorsoURL(rel), dati: d) }
            catch { errore = error.localizedDescription }
        }
        await carica()
    }

    func apri(_ f: JFile) {
        scarica = f.percorso
        Task {
            defer { scarica = nil }
            do {
                let d = try await JsocClient.shared.scaricaDati("/api/associazione/file/" + percorsoURL(f.percorso))
                let u = FileManager.default.temporaryDirectory.appendingPathComponent((f.percorso as NSString).lastPathComponent)
                try d.write(to: u, options: .atomic)
                anteprima = u
            } catch { errore = error.localizedDescription }
        }
    }
}
