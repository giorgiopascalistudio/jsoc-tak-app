import SwiftUI
import CoreLocation

/// Console del server JSOC TAK: stato, operatori online, terminale e Claude Code. Passa da Tailscale.
struct ServerView: View {
    @EnvironmentObject var client: ServerClient
    @EnvironmentObject var term: TerminalModel
    @State private var section = 0
    @State private var settings = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $section) {
                Text("Stato").tag(0); Text("Operatori").tag(1); Text("Terminale").tag(2); Text("Claude").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.vertical, 8)

            if !client.configured && !client.configured(.pc) {
                VStack(spacing: 14) {
                    Image(systemName: "qrcode.viewfinder").font(.system(size: 44)).foregroundStyle(Theme.gold)
                    Text("Collega il server").font(.title3.weight(.bold))
                    Text("Scansiona il QR del server una volta sola: il codice resta nel portachiavi del telefono.")
                        .multilineTextAlignment(.center).foregroundStyle(Theme.dim)
                    Button("Configura") { settings = true }.buttonStyle(.borderedProminent)
                }
                .padding(30).frame(maxHeight: .infinity)
            } else {
                switch section {
                case 0: StatusSection(onCommand: { section = 2 })
                case 1: OperatorsSection()
                case 2: TerminalSection()
                default: ClaudeSection()
                }
            }
        }
        .navigationTitle("Console")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button { settings = true } label: { Image(systemName: "gearshape") } }
        .sheet(isPresented: $settings) { ServerSettings() }
    }
}

// MARK: - Stato

struct StatusSection: View {
    @EnvironmentObject var client: ServerClient
    @EnvironmentObject var term: TerminalModel
    var onCommand: () -> Void
    @State private var st: ServerStatus?
    @State private var err: String?
    @State private var confirm: (String, String)?
    @StateObject private var fleet = Fleet()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                MacchineCard(fleet: fleet, link: false)
                if let err { ErrorCard(text: err) }
                if let st {
                    Card(title: term.target.label) {
                        HStack {
                            Circle().fill(st.tuttoOk ? Theme.green : Theme.red).frame(width: 14, height: 14)
                            Text(st.tuttoOk ? "Tutto in funzione" : "Qualcosa non va").font(.title3.weight(.bold))
                            Spacer()
                            Text(st.ora).font(Theme.mono(12)).foregroundStyle(Theme.dim)
                        }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                            if let b = st.batteria {
                                metric("Batteria", "\(b)% · " + (st.alimentato == true ? "in carica" : "A BATTERIA"), warn: st.alimentato == false)
                            } else {
                                metric("Temperatura", st.temperatura.map { String(format: "%.0f °C", $0) } ?? "?", warn: (st.temperatura ?? 0) > 75)
                            }
                            metric("Carico", st.carico.first ?? "?", warn: Double(st.carico.first ?? "0") ?? 0 > 3.5)
                            metric("Memoria", "\(st.memoria_pct)%", warn: st.memoria_pct > 90)
                            metric("Disco", "\(st.disco_pct)% · \(String(format: "%.1f", st.disco_libero_gb)) GB liberi", warn: st.disco_pct > 90)
                            metric("Acceso da", String(format: "%.1f h", st.uptime_ore), warn: false)
                            metric("Alimentazione", st.throttled == "0x0" ? "ok" : st.throttled, warn: st.throttled != "0x0")
                            metric("Rete", (st.lan ? "cavo · " : "") + st.wifi, warn: false)
                            metric("Tailscale", st.tailscale + " · funnel \(st.funnel)", warn: st.tailscale != "Running")
                        }
                        if let sync = st.sync {
                            metric("Biblioteca → server", sync, warn: sync.contains("errore"))
                        }
                    }
                    Card(title: "Servizi") {
                        ForEach(st.servizi) { s in
                            HStack {
                                Circle().fill(s.attivo ? Theme.green : Theme.red).frame(width: 9, height: 9)
                                Text(s.nome).font(Theme.mono(14))
                                Spacer()
                                Text(s.attivo ? "attivo" : "FERMO").font(.caption.weight(.semibold))
                                    .foregroundStyle(s.attivo ? Theme.dim : Theme.red)
                            }
                        }
                    }
                } else if err == nil {
                    ProgressView().padding(40)
                }
                if term.target == .server { Card(title: "Azioni rapide") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(TerminalModel.quick, id: \.0) { q in
                            Button(q.0) {
                                if q.1.contains("restart") { confirm = q } else { term.run(q.1, client: client); onCommand() }
                            }
                            .buttonStyle(.bordered).frame(maxWidth: .infinity)
                        }
                    }
                    Button("Riavvia il server", role: .destructive) { confirm = ("Riavvia il server", "sudo systemctl reboot") }
                        .buttonStyle(.bordered).frame(maxWidth: .infinity)
                } }
            }
            .padding()
        }
        .refreshable { await load(); await fleet.load(client) }
        .task {
            while !Task.isCancelled { await load(); await fleet.load(client); try? await Task.sleep(nanoseconds: 10_000_000_000) }
        }
        .confirmationDialog(confirm?.0 ?? "", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible) {
            Button(confirm?.0 ?? "", role: .destructive) {
                if let c = confirm { term.run(c.1, client: client); onCommand() }
                confirm = nil
            }
        } message: {
            Text(confirm?.1.contains("reboot") == true
                 ? "Il server torna su in circa 2 minuti. Nel frattempo TAK non funziona per nessuno."
                 : "Gli operatori si scollegano per qualche secondo e poi si ricollegano da soli.")
        }
    }

    func load() async {
        do { st = try await client.status(on: term.target); err = nil } catch { err = error.localizedDescription }
    }

    func metric(_ label: String, _ value: String, warn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption).foregroundStyle(Theme.dim)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(warn ? Theme.red : .white).lineLimit(2)
        }
    }
}

// MARK: - Operatori

struct OperatorsSection: View {
    @EnvironmentObject var client: ServerClient
    @EnvironmentObject var location: LocationService
    @State private var ops: [Operator] = []
    @State private var err: String?
    @State private var showBots = false

    var body: some View {
        List {
            if let err { ErrorCard(text: err).listRowBackground(Color.clear) }
            let people = ops.filter { !$0.isBot }
            Section("Online \(people.filter(\.collegato).count) di \(people.count)") {
                ForEach(people) { row($0) }
            }
            Section {
                DisclosureGroup("Servizi HQI (\(ops.filter(\.isBot).count))", isExpanded: $showBots) {
                    ForEach(ops.filter(\.isBot)) { row($0) }
                }
            }
        }
        .refreshable { await load() }
        .task { while !Task.isCancelled { await load(); try? await Task.sleep(nanoseconds: 10_000_000_000) } }
    }

    func load() async {
        do { ops = try await client.operators(); err = nil } catch { err = error.localizedDescription }
    }

    func row(_ o: Operator) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(o.collegato ? Theme.green : Color.gray.opacity(0.5)).frame(width: 11, height: 11).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(o.callsign).font(.headline)
                    if !o.utente.isEmpty && o.utente != o.callsign { Text(o.utente).font(.caption).foregroundStyle(Theme.dim) }
                    Spacer()
                    if let b = o.batteria { Label("\(Int(b))%", systemImage: battIcon(b)).font(.caption).foregroundStyle(b < 20 ? Theme.red : Theme.dim) }
                }
                Text("\(o.app.isEmpty ? "?" : o.app) · \(o.collegato ? "collegato" : "visto \(o.ultimo)")")
                    .font(.caption).foregroundStyle(Theme.dim)
                if let lat = o.lat, let lon = o.lon {
                    Text(positionLine(lat, lon, o.pos_ora)).font(Theme.mono(11)).foregroundStyle(Theme.cyan)
                }
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            if let lat = o.lat, let lon = o.lon {
                Button("Copia coordinate") { copyToClipboard(String(format: "%.6f, %.6f", lat, lon)) }
                Link("Apri in Mappe", destination: URL(string: "http://maps.apple.com/?ll=\(lat),\(lon)&q=\(o.callsign)")!)
            }
        }
    }

    func positionLine(_ lat: Double, _ lon: Double, _ t: String) -> String {
        var s = String(format: "%.5f, %.5f", lat, lon)
        if let me = location.location {
            let d = me.distance(from: CLLocation(latitude: lat, longitude: lon))
            s += d < 1000 ? String(format: " · %.0f m", d) : String(format: " · %.1f km", d / 1000)
        }
        return s + " · " + t
    }

    func battIcon(_ b: Double) -> String {
        b > 75 ? "battery.100" : b > 50 ? "battery.75" : b > 25 ? "battery.50" : "battery.25"
    }
}

// MARK: - Terminale

struct TerminalSection: View {
    @EnvironmentObject var client: ServerClient
    @EnvironmentObject var term: TerminalModel
    @State private var cmd = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if term.blocks.isEmpty {
                            Text(term.target == .server
                                 ? "Comandi bash sul server. Un comando alla volta; i programmi interattivi (nano, top) non funzionano: usa top -bn1, cat, sed."
                                 : "Comandi bash (Git Bash) sul PC. Un comando alla volta, niente programmi interattivi.")
                                .font(.caption).foregroundStyle(Theme.dim)
                        }
                        ForEach(term.blocks) { b in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(b.dir) $ \(b.cmd)").font(Theme.mono(12, .bold)).foregroundStyle(Theme.gold)
                                Text(b.output.joined(separator: "\n")).font(Theme.mono(11)).textSelection(.enabled)
                                if b.running { ProgressView().scaleEffect(0.7) }
                                else if let c = b.exitCode, c != 0 { Text("uscita \(c)").font(Theme.mono(10)).foregroundStyle(Theme.red) }
                            }
                            .id(b.id)
                            .contextMenu { Button("Copia output") { copyToClipboard(b.output.joined(separator: "\n")) } }
                        }
                        Color.clear.frame(height: 1).id("fondo")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
                .background(Color.black)
                .onChange(of: term.blocks.last?.output.count) { _ in proxy.scrollTo("fondo", anchor: .bottom) }
                .onChange(of: term.blocks.count) { _ in proxy.scrollTo("fondo", anchor: .bottom) }
            }
            if let e = term.error { Text(e).font(.caption2).foregroundStyle(Theme.red).padding(.horizontal) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(term.target == .server ? TerminalModel.quick.filter { !$0.1.contains("restart") } : [], id: \.0) { q in
                        Button(q.0) { term.run(q.1, client: client) }.buttonStyle(.bordered).font(.caption)
                    }
                    ForEach(Array(Set(term.blocks.suffix(8).map(\.cmd))).sorted(), id: \.self) { c in
                        Button(c) { cmd = c; focused = true }.buttonStyle(.bordered).font(Theme.mono(11)).tint(.gray)
                    }
                }
                .padding(.horizontal).padding(.vertical, 6)
            }
            HStack(spacing: 8) {
                Text("\(term.cwd) $").font(Theme.mono(12)).foregroundStyle(Theme.gold).lineLimit(1)
                TextField("comando", text: $cmd)
                    .font(Theme.mono(14)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.send).focused($focused)
                    .onSubmit { send() }
                if term.running {
                    Button { term.stop(client: client) } label: { Image(systemName: "stop.circle.fill").font(.title2) }.tint(Theme.red)
                } else {
                    Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }.disabled(cmd.isEmpty)
                }
            }
            .padding(10)
            .background(Theme.card)
        }
    }

    func send() {
        term.run(cmd, client: client)
        cmd = ""
        focused = true
    }
}

// MARK: - Claude

struct ClaudeSection: View {
    @EnvironmentObject var client: ServerClient
    @EnvironmentObject var claude: ClaudeModel
    @State private var prompt = ""
    @State private var sessions: [ClaudeSession] = []
    @State private var pickSession = false
    @State private var sending = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(claude.target.label, systemImage: claude.target.icon).font(.caption.weight(.bold))
                    .foregroundStyle(client.online[claude.target] == false ? Theme.red : Theme.green)
                Text(claude.session.map { "sessione \($0.prefix(8))" } ?? "nuova conversazione")
                    .font(Theme.mono(11)).foregroundStyle(Theme.dim)
                Spacer()
                Button("Conversazioni") {
                    Task { await client.probe(); sessions = (try? await client.sessions(on: client.brain)) ?? []; pickSession = true }
                }
                .font(.caption).disabled(claude.running)
                Button("Nuova") { claude.newConversation(client: client) }.font(.caption).disabled(claude.running)
            }
            .padding(.horizontal).padding(.bottom, 6)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if claude.items.isEmpty {
                            Text("Claude Code gira sul PC di casa (se è spento passa da solo al server), con la stessa memoria. Scrivi come faresti al PC, oppure tocca la graffetta per mandargli foto, video, audio o PDF: li analizza, li collega agli altri indizi e aggiorna i fascicoli. Per mandare cose su TAK chiede conferma.")
                                .font(.caption).foregroundStyle(Theme.dim).padding()
                        }
                        ForEach(claude.items) { bubble($0).id($0.id) }
                        if claude.running {
                            HStack { ProgressView(); Text("Claude sta lavorando…").font(.caption).foregroundStyle(Theme.dim) }.padding(.horizontal)
                        }
                        if let e = claude.netError { Text(e).font(.caption2).foregroundStyle(Theme.red).padding(.horizontal) }
                        Color.clear.frame(height: 1).id("fondo")
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: claude.items.count) { _ in withAnimation { proxy.scrollTo("fondo", anchor: .bottom) } }
                .onAppear { proxy.scrollTo("fondo", anchor: .bottom) }
            }

            HStack(alignment: .bottom, spacing: 8) {
                Button { sending = true } label: { Image(systemName: "paperclip.circle.fill").font(.title) }
                    .disabled(claude.running)
                TextField("Scrivi a Claude…", text: $prompt, axis: .vertical)
                    .lineLimit(1...6).textFieldStyle(.roundedBorder)
                if claude.running {
                    Button { claude.stop(client: client) } label: { Image(systemName: "stop.circle.fill").font(.title) }.tint(Theme.red)
                } else {
                    Button {
                        claude.send(prompt, client: client); prompt = ""
                    } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                        .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(10)
            .background(Theme.card)
        }
        .overlay(alignment: .top) { TailscaleBanner().padding() }
        .onAppear { claude.resumeIfNeeded(client: client) }
        .task { await client.probe() }
        .sheet(isPresented: $sending) { SendSheet() }
        .sheet(isPresented: $pickSession) {
            NavigationStack {
                List(sessions) { s in
                    Button {
                        claude.open(s, on: client.brain); pickSession = false
                    } label: {
                        VStack(alignment: .leading) {
                            Text(s.titolo).lineLimit(2).foregroundStyle(.white)
                            Text(s.ora).font(.caption).foregroundStyle(Theme.dim)
                        }
                    }
                }
                .navigationTitle("Conversazioni su \(client.brain.label)")
                .toolbar { Button("Chiudi") { pickSession = false } }
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    func bubble(_ i: ClaudeModel.Item) -> some View {
        switch i.kind {
        case "tu":
            HStack { Spacer(minLength: 40)
                Text(i.text).padding(10).background(Theme.gold.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
            }.padding(.horizontal)
        case "file":
            HStack { Spacer(minLength: 40)
                Label(i.text, systemImage: "paperclip").padding(10)
                    .background(Theme.cyan.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
            }.padding(.horizontal)
        case "testo":
            Text(markdown(i.text)).textSelection(.enabled).padding(.horizontal)
        case "strumento":
            Label(i.text, systemImage: "gearshape").font(Theme.mono(11)).foregroundStyle(Theme.cyan).lineLimit(3).padding(.horizontal)
        case "esito":
            Text(i.text).font(Theme.mono(10)).foregroundStyle(Theme.dim).lineLimit(4).padding(.horizontal, 30)
        case "errore":
            Text(i.text).font(.caption).foregroundStyle(Theme.red).padding(.horizontal)
        default:
            Text(i.text).font(.caption2).foregroundStyle(Theme.dim).frame(maxWidth: .infinity)
        }
    }

    func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

// MARK: - Impostazioni

struct ServerSettings: View {
    @EnvironmentObject var client: ServerClient
    @Environment(\.dismiss) var dismiss
    @State private var scanning = false
    @State private var manual = ""
    @State private var manualTarget: Target = .pc
    @State private var msg: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { scanning = true } label: { Label("Scansiona il QR (PC o server)", systemImage: "qrcode.viewfinder") }
                    Picker("Codice per", selection: $manualTarget) {
                        ForEach(Target.allCases) { Text($0.label).tag($0) }
                    }
                    HStack {
                        TextField("oppure incolla il codice", text: $manual).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("Usa") {
                            msg = client.pair(with: manual, default: manualTarget).map { "\($0.label) collegato" } ?? "Codice non valido"
                            manual = ""
                        }
                    }
                    if let msg { Text(msg).foregroundStyle(msg.hasSuffix("collegato") ? Theme.green : Theme.red) }
                } footer: { Text("I codici restano nel portachiavi del telefono. Claude, biblioteca e invii vanno al PC se risponde, altrimenti al server.") }
                ForEach(Target.allCases) { t in
                    Section {
                        HStack {
                            Circle().fill(client.online[t] == true ? Theme.green : (client.configured(t) ? Theme.red : Color.gray)).frame(width: 10, height: 10)
                            Text(client.configured(t) ? (client.online[t] == true ? "raggiungibile" : "non risponde") : "da collegare")
                            Spacer()
                            if client.brain == t { Text("in uso").font(.caption.weight(.bold)).foregroundStyle(Theme.gold) }
                        }
                        TextField("indirizzo", text: Binding(get: { client.urls[t] ?? "" }, set: { client.setURL($0, for: t) }))
                            .font(Theme.mono(13)).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        Button("Ripristina indirizzo") { client.setURL(t.defaultURL, for: t) }
                        if client.configured(t) {
                            Button("Dimentica il codice", role: .destructive) { client.setToken("", for: t) }
                        }
                    } header: { Label(t.label, systemImage: t.icon) }
                }
                Section {
                    Button("Controlla adesso") { Task { await client.probe(force: true) } }
                    Text("Si raggiungono solo con Tailscale acceso su questo iPhone.").font(.caption).foregroundStyle(Theme.dim)
                }
            }
            .navigationTitle("Collegamenti")
            .toolbar { Button("Fatto") { dismiss() } }
            .task { await client.probe() }
            .sheet(isPresented: $scanning) {
                CodeScanner { code, _ in
                    msg = client.pair(with: code).map { "\($0.label) collegato" } ?? "QR non valido"
                    scanning = false
                }
                .ignoresSafeArea()
            }
        }
    }
}

struct ErrorCard: View {
    let text: String
    var body: some View {
        Card { Label(text, systemImage: "wifi.exclamationmark").font(.footnote).foregroundStyle(Theme.red) }
    }
}

/// Riquadro per la scheda Gara: stato del server in breve, tocca per aprire la console.
struct ServerSummaryCard: View {
    @EnvironmentObject var client: ServerClient
    @State private var st: ServerStatus?
    @State private var online: Int?
    @State private var err = false

    var body: some View {
        NavigationLink { ServerView() } label: {
            Card(title: "Console · PC e server") {
                HStack(spacing: 10) {
                    Circle().fill(color).frame(width: 12, height: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.headline).foregroundStyle(.white)
                        Text(detail).font(.caption).foregroundStyle(Theme.dim)
                        Label(pcLine, systemImage: "desktopcomputer").font(.caption)
                            .foregroundStyle(client.online[.pc] == true ? Theme.green : Theme.dim)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.dim)
                }
            }
        }
        .buttonStyle(.plain)
        .task {
            while !Task.isCancelled {
                await client.probe()
                if client.configured {
                    do {
                        st = try await client.status()
                        online = try await client.operators().filter { $0.collegato && !$0.isBot }.count
                        err = false
                    } catch { err = true }
                }
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    var pcLine: String {
        if !client.configured(.pc) { return "PC da collegare" }
        return client.online[.pc] == true ? "PC acceso · Claude sul PC" : "PC non risponde · Claude sul server"
    }

    var color: Color { !client.configured || err ? .gray : (st?.tuttoOk == true ? Theme.green : Theme.red) }
    var title: String {
        if !client.configured { return "Da collegare" }
        if err { return "Non raggiungibile" }
        guard let st else { return "…" }
        return st.tuttoOk ? "In funzione" : "Problemi: \(st.servizi.filter { !$0.attivo }.map(\.nome).joined(separator: ", "))"
    }
    var detail: String {
        if !client.configured { return "Tocca per configurare" }
        if err { return "Tailscale acceso sul telefono?" }
        guard let st else { return "" }
        return "\(online.map { "\($0) operatori online · " } ?? "")\(st.temperatura.map { String(format: "%.0f °C", $0) } ?? "")"
    }
}
