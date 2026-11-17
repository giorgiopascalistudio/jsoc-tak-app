import SwiftUI
import CoreLocation

// MARK: - Scheda Eventi: elenco

struct EventiTab: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var store = EventoStore.shared
    @State private var fase = 1
    @State private var nuovo = false
    @State private var percorso: [JEvento] = []
    @State private var chat = false

    var body: some View {
        NavigationStack(path: $percorso) {
            Group {
                if jsoc.collegato { elenco } else { EntraView() }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Eventi")
            .navigationDestination(for: JEvento.self) { EventoView(evento: $0) }
            .navigationDestination(isPresented: $chat) { ChatView() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if jsoc.utente?.direttivo == true {
                        Button { nuovo = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }.tint(Theme.olive)
                    }
                }
            }
        }
        .sheet(isPresented: $nuovo) { NuovoEventoSheet() }
        .onAppear {
            if store.eventi.contains(where: { $0.fase == 0 }) { fase = 0 }
            if UserDefaults.standard.bool(forKey: "eventi.apriChat") {
                UserDefaults.standard.set(false, forKey: "eventi.apriChat")
                if store.corrente != nil { chat = true }
            }
        }
    }

    var filtrati: [JEvento] {
        let e = store.eventi.filter { $0.fase == fase }
        return fase == 2 ? e.sorted { ($0.dataInizio ?? .distantPast) > ($1.dataInizio ?? .distantPast) }
                         : e.sorted { ($0.dataInizio ?? .distantFuture) < ($1.dataInizio ?? .distantFuture) }
    }

    var elenco: some View {
        ScrollView {
            VStack(spacing: 12) {
                Picker("", selection: $fase) {
                    Text("In corso").tag(0)
                    Text("Prossimi").tag(1)
                    Text("Passati").tag(2)
                }
                .pickerStyle(.segmented)
                if filtrati.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.plus").font(.largeTitle).foregroundStyle(Theme.dim)
                        Text(fase == 0 ? "Nessun evento in corso" : (fase == 1 ? "Nessun evento in programma" : "Nessun evento passato"))
                            .foregroundStyle(Theme.dim)
                        if jsoc.utente?.direttivo == true && fase != 2 {
                            Button("Crea nuovo evento") { nuovo = true }.buttonStyle(.borderedProminent).tint(Theme.olive).foregroundStyle(.black)
                        }
                    }
                    .padding(.top, 50)
                }
                ForEach(Array(filtrati.enumerated()), id: \.element.id) { i, e in
                    NavigationLink(value: e) { EventoRiga(evento: e, attivo: e.id == store.corrente?.id) }
                        .buttonStyle(PressStyle())
                        .reveal(i)
                }
                Text(store.stato).font(Theme.mono(10)).foregroundStyle(Theme.dim)
            }
            .padding(14)
        }
        .refreshable { await store.aggiorna(jsoc) }
    }
}

struct EventoRiga: View {
    let evento: JEvento
    var attivo = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(evento.dataInizio.map { $0.formatted(.dateTime.day()) } ?? "–").font(.system(size: 22, weight: .heavy, design: .monospaced))
                Text(evento.dataInizio.map { $0.formatted(.dateTime.month(.abbreviated)) } ?? "").font(Theme.mono(10, .bold)).textCase(.uppercase)
            }
            .foregroundStyle(Theme.olive)
            .frame(width: 52, height: 56)
            .background(Theme.oliveDeep.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: evento.icona).font(.caption).foregroundStyle(Theme.olive)
                    Text(evento.nome).font(.subheadline.weight(.bold)).foregroundStyle(.white).lineLimit(1)
                }
                Text([evento.tipo.capitalized, evento.dataInizio?.formatted(date: .omitted, time: .shortened), evento.luogo]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                HStack(spacing: 6) {
                    if attivo { etichetta("ATTIVO", Theme.olive) }
                    if evento.staff { etichetta("STAFF", Theme.cyan) }
                    switch evento.mia_risposta {
                    case "si": etichetta("CI SONO", Theme.green)
                    case "no": etichetta("NON CI SONO", Theme.red)
                    case "forse": etichetta("FORSE", Theme.amber)
                    default: if evento.fase != 2 { etichetta("DA RISPONDERE", Theme.amber) }
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(Theme.dim)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(attivo ? Theme.olive : Theme.stroke, lineWidth: attivo ? 1.2 : 0.75))
    }

    func etichetta(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.8)
            .foregroundStyle(c).padding(.horizontal, 6).padding(.vertical, 2)
            .background(c.opacity(0.14), in: Capsule())
    }
}

// MARK: - Pagina dell'evento

struct EventoView: View {
    let evento: JEvento
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var store = EventoStore.shared
    @EnvironmentObject var location: LocationService
    @EnvironmentObject var docs: DocStore
    @State private var presenze: JPresenze?
    @State private var errore: String?
    @State private var aperto: Sezione?

    enum Sezione: String, Identifiable { case documenti, strumenti, raccolta, video; var id: String { rawValue } }

    /// i dati completi (punti, aree, membri) li ha lo store quando l'evento è quello attivo
    var e: JEvento { store.corrente?.id == evento.id ? store.corrente! : (store.eventi.first { $0.id == evento.id } ?? evento) }
    var attivo: Bool { store.corrente?.id == evento.id }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                testata
                if e.fase != 2 { rispostaCard }
                if e.membro {
                    if !attivo {
                        Button { store.scegli(e); haptic(.medium) } label: { Label("Rendi attivo (mappa, squadra, documenti)", systemImage: "scope") }
                            .buttonStyle(PrimaryButtonStyle())
                    } else {
                        sezioni
                        squadraCard
                    }
                } else {
                    Card { Label("Rispondi \"Ci sono\" per entrare nell'evento: vedrai mappa, documenti e chat.", systemImage: "lock.fill")
                        .font(.subheadline).foregroundStyle(Theme.dim) }
                }
                if let p = presenze { presenzeCard(p) }
                if let errore { ErrorCard(text: errore) }
            }
            .padding(14)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(e.nome)
        .navigationBarTitleDisplayMode(.inline)
        .task { await caricaPresenze() }
        .refreshable { await store.aggiorna(jsoc); await caricaPresenze() }
        .fullScreenCover(item: $aperto) { s in
            ZStack(alignment: .topTrailing) {
                switch s {
                case .documenti: DocsTab()
                case .strumenti: CipherTab()
                case .raccolta: KitTab()
                case .video: VideoTab()
                }
                Button { aperto = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 28)).symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Theme.surface2)
                }
                .padding(.trailing, 14).padding(.top, 4)
            }
        }
    }

    var testata: some View {
        Card(title: e.tipo, icon: e.icona, trailing: e.staff ? "STAFF" : nil) {
            Text(e.nome).font(.title2.weight(.heavy))
            if let i = e.dataInizio {
                Label(i.formatted(date: .complete, time: .shortened) + (e.dataFine.map { " → " + $0.formatted(date: .omitted, time: .shortened) } ?? ""),
                      systemImage: "clock").font(.caption).foregroundStyle(Theme.dim)
            }
            if let l = e.luogo, !l.isEmpty { Label(l, systemImage: "mappin").font(.caption).foregroundStyle(Theme.dim) }
            if let la = e.lat, let lo = e.lon {
                Label(Coordinate.utmText(.init(latitude: la, longitude: lo)), systemImage: "scope").font(Theme.mono(11)).foregroundStyle(Theme.olive)
            }
            if let n = e.note, !n.isEmpty { Text(n).font(.subheadline).foregroundStyle(.white.opacity(0.9)) }
        }
    }

    var rispostaCard: some View {
        Card(title: "Partecipi?", icon: "hand.raised.fill") {
            RispostaBottoni(scelta: presenze?.presenze.first { $0.utente == jsoc.utente?.id }?.risposta ?? e.mia_risposta) { r in
                Task {
                    do {
                        presenze = try await jsoc.rispondi(e.id, r)
                        await store.aggiorna(jsoc)
                        await HomeModel.shared.aggiorna()
                    } catch { errore = error.localizedDescription }
                }
            }
        }
    }

    // MARK: sezioni dell'evento attivo

    var sezioni: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            sezione("map.fill", "Mappa", "\((e.punti ?? []).count) punti · \((e.aree ?? []).count) aree") { vaiAllaScheda(Schede.mappa) }
            NavigationLink { ChatView() } label: {
                riquadro("bubble.left.and.bubble.right.fill", "Chat", store.nonLetti > 0 ? "\(store.nonLetti) non letti" : "\(store.messaggi.count) messaggi")
            }.buttonStyle(PressStyle())
            sezione("folder.fill", "Documenti", "\(docs.items.count) file" + (docs.newItems.isEmpty ? "" : " · \(docs.newItems.count) nuovi")) { aperto = .documenti }
            sezione("wrench.and.screwdriver.fill", "Intelligence e strumenti", "cifrari, Morse, rilevamenti") { aperto = .strumenti }
            sezione("camera.viewfinder", "Raccolta dal campo", "foto, audio, QR, Claude") { aperto = .raccolta }
            sezione("video.fill", "Video", "trasmetti e guarda la squadra") { aperto = .video }
            NavigationLink { PuntiView() } label: {
                riquadro("mappin.and.ellipse", "Punti e aree", "elenco e navigazione")
            }.buttonStyle(PressStyle())
            if e.staff {
                NavigationLink { MembriView(evento: e) } label: {
                    riquadro("person.badge.key.fill", "Membri e ruoli", "\((e.membri ?? []).count) membri")
                }.buttonStyle(PressStyle())
            }
        }
    }

    func sezione(_ icona: String, _ titolo: String, _ sotto: String, _ f: @escaping () -> Void) -> some View {
        Button { haptic(); f() } label: { riquadro(icona, titolo, sotto) }.buttonStyle(PressStyle())
    }

    func riquadro(_ icona: String, _ titolo: String, _ sotto: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icona).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.olive)
            Text(titolo).font(.subheadline.weight(.bold)).foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.leading)
            Text(sotto).font(.caption2).foregroundStyle(Theme.dim).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 0.75))
    }

    // MARK: squadra

    var squadraCard: some View {
        let me = location.location?.coordinate
        let membri = e.membri ?? []
        return Card(title: "Squadra", icon: "person.3.fill", trailing: "\(store.squadra.filter { $0.eta < 300 }.count)/\(membri.count) in mappa") {
            ForEach(membri) { m in
                let pos = store.squadra.first { $0.id == m.id }
                HStack(spacing: 10) {
                    FotoSocio(id: m.id, iniziali: m.callsign, lato: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(m.callsign).font(Theme.mono(14, .bold))
                        Text([m.nome, m.squadra ?? "", m.ruolo == "staff" ? "staff" : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption2).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    if let p = pos {
                        VStack(alignment: .trailing, spacing: 1) {
                            if let me, m.id != jsoc.utente?.id {
                                Text("\(Geo.formatDistance(Geo.distance(me, p.coordinate))) · \(gradi3(Geo.bearing(me, p.coordinate)))")
                                    .font(Theme.mono(12, .semibold)).foregroundStyle(Theme.olive)
                            }
                            Text(p.eta < 60 ? "adesso" : "\(Int(p.eta / 60)) min fa").font(.caption2).foregroundStyle(p.eta < 300 ? Theme.dim : Theme.amber)
                        }
                        if m.id != jsoc.utente?.id {
                            Button {
                                haptic(.medium)
                                NavStore.shared.target = GaraPoint(id: m.callsign, lat: p.lat, lon: p.lon, kind: .recon, note: "Ultima posizione di \(m.callsign)")
                                vaiAllaScheda(Schede.mappa)
                            } label: { Image(systemName: "location.north.line.fill") }
                                .buttonStyle(.bordered).tint(Theme.olive)
                        }
                    } else {
                        Text("non in mappa").font(.caption2).foregroundStyle(Theme.dim)
                    }
                }
            }
            Divider().overlay(Theme.stroke)
            Toggle(isOn: $store.condividiPosizione) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Condividi posizione e direzione").font(.subheadline.weight(.semibold))
                    Text(store.inCoda > 0 ? "\(store.inCoda) posizioni in attesa di rete" : "Visibile alla squadra di questo evento")
                        .font(.caption2).foregroundStyle(store.inCoda > 0 ? Theme.amber : Theme.dim)
                }
            }
            .tint(Theme.olive)
        }
    }

    // MARK: presenze (come Spond)

    func presenzeCard(_ p: JPresenze) -> some View {
        Card(title: "Presenze", icon: "checklist", trailing: "\(p.conta.si) sì · \(p.conta.forse) forse · \(p.conta.no) no") {
            ForEach(["si", "forse", "no", ""], id: \.self) { r in
                let lista = p.presenze.filter { ($0.risposta ?? "") == r }
                if !lista.isEmpty {
                    Text(r == "si" ? "CI SONO" : (r == "forse" ? "FORSE" : (r == "no" ? "NON CI SONO" : "NON HANNO RISPOSTO")))
                        .font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(1.2)
                        .foregroundStyle(r == "si" ? Theme.green : (r == "no" ? Theme.red : Theme.amber))
                    ForEach(lista) { x in
                        HStack {
                            Text(x.callsign).font(Theme.mono(13, .bold))
                            Text(x.nome ?? "").font(.caption).foregroundStyle(Theme.dim)
                            Spacer()
                            if e.staff && e.fase != 1 {
                                Button {
                                    Task { presenze = try? await jsoc.appello(e.id, utente: x.utente, presente: x.presente != 1) }
                                } label: {
                                    Image(systemName: x.presente == 1 ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(x.presente == 1 ? Theme.green : Theme.dim)
                                }
                            } else if x.presente == 1 {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
                            }
                        }
                    }
                }
            }
            if e.staff && e.fase != 1 { Text("Tocca il cerchio per fare l'appello").font(.caption2).foregroundStyle(Theme.dim) }
        }
    }

    func caricaPresenze() async {
        do { presenze = try await jsoc.presenze(evento.id) } catch { errore = error.localizedDescription }
    }
}

// MARK: - Punti e aree dell'evento

struct PuntiView: View {
    @ObservedObject private var store = EventoStore.shared
    @EnvironmentObject var location: LocationService

    var body: some View {
        List {
            Section("Punti") {
                ForEach(store.corrente?.punti ?? []) { p in
                    let c = CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon)
                    Button {
                        NavStore.shared.target = GaraPoint(id: p.nome, lat: p.lat, lon: p.lon, kind: DatiEvento.kind(p.tipo), note: p.note ?? "")
                        vaiAllaScheda(Schede.mappa)
                    } label: {
                        HStack {
                            Circle().fill(GaraPoint(id: "", lat: 0, lon: 0, kind: DatiEvento.kind(p.tipo), note: "").color).frame(width: 10, height: 10)
                            VStack(alignment: .leading) {
                                Text(p.nome).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                Text(Coordinate.utmText(c)).font(Theme.mono(11)).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            if let me = location.location?.coordinate {
                                Text(Geo.formatDistance(Geo.distance(me, c))).font(Theme.mono(12, .semibold)).foregroundStyle(Theme.olive)
                            }
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            Section("Aree") {
                ForEach(store.corrente?.aree ?? []) { a in
                    Label("\(a.nome) · \(a.tipo)", systemImage: "square.dashed").listRowBackground(Theme.surface)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Punti e aree")
    }
}

// MARK: - Ingresso con l'invito

struct EntraView: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @AppStorage("jsoc.invito") private var invitoAperto = ""
    @State private var link = ""
    @State private var nome = ""
    @State private var callsign = ""
    @State private var scanner = false
    @State private var lavoro = false
    @State private var errore: String?

    var invito: (String, String)? { JsocClient.leggiInvito(link) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image("Stemma").resizable().scaledToFit().frame(width: 130, height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .padding(.top, 20)
                Text("Entra in JSOC TAK").font(.title2.weight(.heavy))
                Text("Inquadra il QR dell'invito che ti ha dato il direttivo. Server e accesso si configurano da soli.")
                    .font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                Card(title: "Invito", icon: "qrcode.viewfinder") {
                    if let inv = invito {
                        Label("Codice \(inv.1)", systemImage: "checkmark.seal.fill").font(Theme.mono(14, .bold)).foregroundStyle(Theme.olive)
                        Text(inv.0).font(Theme.mono(10)).foregroundStyle(Theme.dim).lineLimit(1).truncationMode(.middle)
                    } else {
                        Button { scanner = true } label: { Label("Inquadra il QR", systemImage: "camera.viewfinder") }
                            .buttonStyle(PrimaryButtonStyle())
                        TextField("oppure incolla il link jsoctak://…", text: $link)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .font(Theme.mono(12)).padding(10)
                            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                Card(title: "Chi sei", icon: "person.fill") {
                    TextField("Nome e cognome", text: $nome)
                        .padding(10).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                    TextField("Callsign (es. GREG)", text: $callsign)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .font(Theme.mono(15, .bold))
                        .padding(10).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                }
                if let errore { ErrorCard(text: errore) }
                Button {
                    guard let inv = invito else { return }
                    let (u, c) = inv
                    lavoro = true; errore = nil
                    Task {
                        do {
                            try await jsoc.entra(indirizzo: u, codice: c, nome: nome, callsign: callsign)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            invitoAperto = ""
                            await EventoStore.shared.aggiorna(jsoc)
                        } catch { errore = error.localizedDescription }
                        lavoro = false
                    }
                } label: {
                    HStack { if lavoro { ProgressView().tint(.black) }; Text("Entra") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(invito == nil || nome.trimmingCharacters(in: .whitespaces).isEmpty || callsign.trimmingCharacters(in: .whitespaces).isEmpty || lavoro)
                .opacity(invito == nil || nome.isEmpty || callsign.isEmpty ? 0.5 : 1)
            }
            .padding(16)
        }
        .onAppear { if !invitoAperto.isEmpty { link = invitoAperto } }
        .onChange(of: invitoAperto) { if !$0.isEmpty { link = $0 } }
        .sheet(isPresented: $scanner) {
            ZStack(alignment: .bottom) {
                CodeScanner { s, _ in
                    if JsocClient.leggiInvito(s) != nil { link = s; scanner = false }
                }
                .ignoresSafeArea()
                Text("Inquadra il QR dell'invito JSOC TAK").font(.subheadline.weight(.semibold))
                    .padding(12).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Nuovo evento

struct NuovoEventoSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var location: LocationService
    @State private var nome = ""
    @State private var tipo = "gara"
    @State private var inizio = Date()
    @State private var fine = Date().addingTimeInterval(86400)
    @State private var luogo = ""
    @State private var note = ""
    @State private var quiPosizione = true
    @State private var lavoro = false
    @State private var errore: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Evento") {
                    TextField("Nome (es. Operazione Re Mida)", text: $nome)
                    Picker("Tipo", selection: $tipo) {
                        Text("Gara").tag("gara")
                        Text("Allenamento").tag("allenamento")
                        Text("Riunione").tag("riunione")
                        Text("Altro").tag("altro")
                    }
                    DatePicker("Inizio", selection: $inizio, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Fine", selection: $fine, in: inizio..., displayedComponents: [.date, .hourAndMinute])
                }
                Section("Dove") {
                    TextField("Luogo", text: $luogo)
                    Toggle("Centra sulla mia posizione", isOn: $quiPosizione)
                }
                Section("Note") { TextField("Note, briefing, materiale", text: $note, axis: .vertical).lineLimit(3...8) }
                if let errore { Section { Text(errore).foregroundStyle(Theme.red) } }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Nuovo evento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crea") { crea() }.disabled(nome.trimmingCharacters(in: .whitespaces).isEmpty || lavoro)
                }
            }
        }
    }

    func crea() {
        lavoro = true; errore = nil
        let iso = ISO8601DateFormatter()
        var campi: [String: Any] = ["nome": nome.trimmingCharacters(in: .whitespaces), "tipo": tipo,
                                    "inizio": iso.string(from: inizio), "fine": iso.string(from: fine),
                                    "luogo": luogo, "note": note]
        if quiPosizione, let c = location.location?.coordinate { campi["lat"] = c.latitude; campi["lon"] = c.longitude }
        Task {
            do {
                let e = try await JsocClient.shared.creaEvento(campi)
                EventoStore.shared.scegli(e)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } catch { errore = error.localizedDescription }
            lavoro = false
        }
    }
}

// MARK: - Invito

struct InvitoSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var ruolo = "socio"
    @State private var invito: JInvito?
    @State private var errore: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Picker("Ruolo", selection: $ruolo) {
                    Text("Socio").tag("socio")
                    Text("Direttivo").tag("direttivo")
                }
                .pickerStyle(.segmented)
                .onChange(of: ruolo) { _ in invito = nil }
                if let i = invito, let img = QR.immagine(i.link) {
                    Image(uiImage: img).interpolation(.none).resizable().scaledToFit()
                        .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 16))
                        .frame(maxWidth: 300)
                    Text(i.codice).font(Theme.mono(28, .heavy)).tracking(4).foregroundStyle(Theme.olive)
                    Text("Valido 7 giorni, per una sola persona. Il socio lo inquadra all'apertura di JSOC TAK.")
                        .font(.caption).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                    ShareLink(item: i.link) { Label("Condividi il link", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered).tint(Theme.olive)
                } else {
                    Spacer()
                    Button { crea() } label: { Label("Crea invito \(ruolo)", systemImage: "qrcode") }
                        .buttonStyle(PrimaryButtonStyle())
                }
                if let errore { ErrorCard(text: errore) }
                Spacer()
            }
            .padding(20)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Invita")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
        }
    }

    func crea() {
        errore = nil
        Task {
            do { invito = try await JsocClient.shared.invito(ruolo: ruolo) } catch { errore = error.localizedDescription }
        }
    }
}

// MARK: - Membri dell'evento (staff)

struct MembriView: View {
    let evento: JEvento
    @State private var utenti: [JUtente] = []
    @State private var membri: [JMembro] = []
    @State private var errore: String?

    var body: some View {
        List {
            if let errore { Text(errore).foregroundStyle(Theme.red) }
            ForEach(utenti) { u in
                let m = membri.first { $0.id == u.id }
                HStack {
                    VStack(alignment: .leading) {
                        Text(u.callsign).font(Theme.mono(14, .bold))
                        Text(u.nome).font(.caption).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    Menu {
                        Button("Operatore") { cambia(u, "operatore") }
                        Button("Staff") { cambia(u, "staff") }
                        Button("Togli dall'evento", role: .destructive) { cambia(u, nil) }
                    } label: {
                        Text(m?.ruolo.uppercased() ?? "AGGIUNGI").font(Theme.mono(11, .heavy))
                            .foregroundStyle(m == nil ? Theme.dim : Theme.olive)
                    }
                }
                .listRowBackground(Theme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Membri")
        .task { await carica() }
    }

    func carica() async {
        do {
            utenti = try await JsocClient.shared.utenti()
            membri = try await JsocClient.shared.evento(evento.id).membri ?? []
        } catch { errore = error.localizedDescription }
    }

    func cambia(_ u: JUtente, _ ruolo: String?) {
        Task {
            do {
                let e = try await JsocClient.shared.membro(evento.id, utente: u.id, ruolo: ruolo)
                membri = e.membri ?? []
                await EventoStore.shared.aggiorna(JsocClient.shared)
            } catch { errore = error.localizedDescription }
        }
    }
}

// MARK: - Chat dell'evento

struct ChatView: View {
    /// nil = chat di tutto l'evento; un id = chat diretta con quell'operatore
    var con: Int? = nil
    @ObservedObject private var store = EventoStore.shared
    @ObservedObject private var jsoc = JsocClient.shared
    @EnvironmentObject var location: LocationService
    @State private var testo = ""
    @State private var conPosizione = false
    @State private var errore: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { sv in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(visibili) { m in bolla(m).id(m.id) }
                    }
                    .padding(12)
                }
                .onAppear { sv.scrollTo(store.messaggi.last?.id, anchor: .bottom); store.letti() }
                .onChange(of: store.messaggi.count) { _ in
                    withAnimation { sv.scrollTo(store.messaggi.last?.id, anchor: .bottom) }
                    store.letti()
                }
            }
            if let errore { Text(errore).font(.caption).foregroundStyle(Theme.red).padding(.horizontal) }
            HStack(spacing: 8) {
                Button { conPosizione.toggle(); haptic() } label: {
                    Image(systemName: conPosizione ? "location.fill" : "location").foregroundStyle(conPosizione ? Theme.olive : Theme.dim)
                }
                RegistraVoce(dest: con)
                TextField("Messaggio", text: $testo, axis: .vertical).lineLimit(1...4)
                    .padding(10).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                Button { invia() } label: { Image(systemName: "paperplane.fill").font(.title3).foregroundStyle(Theme.olive) }
                    .disabled(testo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(10)
            .background(Theme.surface)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(store.corrente?.nome ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            while !Task.isCancelled {
                await store.aggiorna(jsoc)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    var visibili: [JMessaggio] {
        let io = jsoc.utente?.id
        guard let con else { return store.messaggi.filter { $0.dest == nil } }
        return store.messaggi.filter { ($0.autore == con && $0.dest == io) || ($0.autore == io && $0.dest == con) }
    }

    func bolla(_ m: JMessaggio) -> some View {
        let mio = m.autore == jsoc.utente?.id
        return HStack {
            if mio { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 3) {
                if !mio { Text(m.callsign ?? "?").font(Theme.mono(11, .heavy)).foregroundStyle(Theme.olive) }
                if let a = m.allegato, a.hasSuffix(".m4a") { TastoVoce(percorso: a) } else { Text(m.testo).font(.subheadline) }
                HStack(spacing: 6) {
                    if let la = m.lat, let lo = m.lon {
                        Button {
                            NavStore.shared.target = GaraPoint(id: "MSG \(m.callsign ?? "")", lat: la, lon: lo, kind: .recon, note: m.testo)
                        } label: { Label(Coordinate.utmText(.init(latitude: la, longitude: lo)), systemImage: "mappin") }
                            .font(Theme.mono(10, .semibold)).foregroundStyle(Theme.cyan)
                    }
                    Text(Date(timeIntervalSince1970: m.ts).formatted(date: .omitted, time: .shortened))
                        .font(Theme.mono(9)).foregroundStyle(Theme.dim)
                }
            }
            .padding(10)
            .background(mio ? Theme.oliveDeep : Theme.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if !mio { Spacer(minLength: 40) }
        }
    }

    func invia() {
        let t = testo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        testo = ""; errore = nil
        let c = conPosizione ? location.location?.coordinate : nil
        Task {
            do { try await store.scrivi(t, jsoc, posizione: c, dest: con); haptic() }
            catch { errore = error.localizedDescription; testo = t }
        }
    }
}
