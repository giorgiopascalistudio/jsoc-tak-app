import SwiftUI
import MapKit
import PhotosUI

// MARK: - Contenitore: Home · Eventi · Associazione · Strumenti (Profilo dalla Home, Mappa a schermo intero)

struct BarraSchede: View {
    @Binding var tab: Int
    let verticale: Bool
    var badge: [Int: Int] = [:]

    static let voci: [(Int, String, String)] = [(Schede.home, "Home", "house.fill"), (Schede.eventi, "Eventi", "calendar"),
                                               (Schede.associazione, "Associazione", "shield.lefthalf.filled"),
                                               (Schede.strumenti, "Strumenti", "square.grid.2x2.fill")]

    var body: some View {
        let layout = verticale ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 2))
        layout {
            ForEach(Self.voci, id: \.0) { v in
                let on = tab == v.0
                Button { if tab != v.0 { haptic(.soft) }; tab = v.0 } label: {
                    VStack(spacing: 3) {
                        Image(systemName: v.2).font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(on ? Theme.oliveBright : Theme.dim)
                            .overlay(alignment: .topTrailing) {
                                if let n = badge[v.0], n > 0 {
                                    Text("\(n)").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                                        .padding(.horizontal, 4).frame(minWidth: 15, minHeight: 15)
                                        .background(Theme.red, in: Capsule()).offset(x: 10, y: -6)
                                }
                            }
                        Text(v.1).font(.system(size: 10, weight: .bold)).foregroundStyle(on ? .white : Theme.dim)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: verticale ? 64 : .infinity).frame(height: verticale ? 56 : 50)
                    .background(on ? Theme.olive.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(4)
        .background(Theme.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Theme.stroke))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
    }
}

/// Le schede restano in memoria (come una TabView), tranne la mappa che si apre a schermo intero.
struct ContenitoreSchede: View {
    @Binding var tab: Int
    var badge: [Int: Int]
    @State private var visti: Set<Int> = []

    var body: some View {
        GeometryReader { g in
            let land = g.size.width > g.size.height
            HStack(spacing: 0) {
                if land && tab != Schede.mappa {
                    // in orizzontale la barra diventa una colonna stretta a sinistra
                    BarraSchede(tab: $tab, verticale: true, badge: badge)
                        .padding(.leading, 6).padding(.vertical, 8)
                        .frame(maxHeight: .infinity)
                }
                ZStack {
                    ForEach([Schede.home, Schede.eventi, Schede.associazione, Schede.strumenti, Schede.profilo], id: \.self) { t in
                        if visti.contains(t) || t == tab {
                            vista(t).opacity(t == tab ? 1 : 0).allowsHitTesting(t == tab)
                        }
                    }
                    if tab == Schede.mappa { MapTab() }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !land && tab != Schede.mappa {
                        BarraSchede(tab: $tab, verticale: false, badge: badge).padding(.horizontal, 14).padding(.bottom, 2)
                    }
                }
            }
        }
        .onAppear { visti.insert(tab) }
        .onChange(of: tab) { visti.insert($0) }
    }

    @ViewBuilder func vista(_ t: Int) -> some View {
        switch t {
        case Schede.home: HomeV2()
        case Schede.eventi: EventiV2()
        case Schede.associazione: AssociazioneTab()
        case Schede.strumenti: StrumentiTab()
        default: ProfiloTab()
        }
    }
}

// MARK: - Strumenti (da campo e intelligence)

struct StrumentiTab: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    EtichettaSezione(testo: "Da campo")
                    griglia([
                        voce("scope", "Mirino con azimut", "rilevamenti con la bussola") { AnyView(MirinoView()) },
                        voce("triangle", "Triangolazione", "da due o tre rilevamenti") { AnyView(TriangView()) },
                        voce("ruler", "Telemetro", "distanze dalla fotocamera") { AnyView(TelemetroView()) },
                        voce("map", "Campo", "coordinate e conversioni") { AnyView(CampoView()) },
                        voce("target", "Balistica BB", "caduta e tempo di volo") { AnyView(PannelloBalistica(chiudi: {})) },
                        voce("cross.case.fill", "Primo soccorso", "MARCH passo passo") { AnyView(PannelloMedico(chiudi: {})) },
                    ])
                    EtichettaSezione(testo: "Intelligence")
                    griglia([
                        voce("lock.open.fill", "Cifrari e decodifiche", "Cesare, Vigenère, Morse, catene") { AnyView(CipherTab()) },
                        voce("qrcode.viewfinder", "Raccolta dal campo", "foto, audio, QR") { AnyView(KitTab()) },
                    ])
                }
                .padding(14)
                .padding(.bottom, 70)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Strumenti")
        }
    }

    struct Voce: Identifiable { let id: String; let icona: String; let sotto: String; let vista: () -> AnyView }

    func voce(_ icona: String, _ titolo: String, _ sotto: String, _ v: @escaping () -> AnyView) -> Voce {
        Voce(id: titolo, icona: icona, sotto: sotto, vista: v)
    }

    func griglia(_ voci: [Voce]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
            ForEach(voci) { v in
                NavigationLink { v.vista().background(Theme.bg.ignoresSafeArea()).navigationTitle(v.id).navigationBarTitleDisplayMode(.inline) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: v.icona).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.oliveBright)
                        Text(v.id).font(.system(size: 14, weight: .heavy)).foregroundStyle(.white).multilineTextAlignment(.leading)
                        Text(v.sotto).font(.system(size: 11)).foregroundStyle(Theme.dim).multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
                    .padding(12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.stroke))
                }
                .buttonStyle(PressStyle())
            }
        }
    }
}

// MARK: - Aiuti per gli eventi

extension JEvento {
    var colore: Color {
        switch tipo {
        case "gara": return Theme.red
        case "allenamento": return Theme.olive
        case "riunione": return Theme.cyan
        default: return Theme.amber
        }
    }
    var nomeTipo: String {
        ["gara": "GARA", "allenamento": "ALLENAMENTO", "riunione": "RIUNIONE"][tipo] ?? "ASSOCIAZIONE"
    }
    var proposto: Bool { stato == "proposto" }
    var dataScadenza: Date? { JEvento.data(scadenza) }
    var iscrizioniChiuse: Bool {
        guard let s = dataScadenza else { return false }
        return Calendar.current.startOfDay(for: Date()) > Calendar.current.startOfDay(for: s)
    }
    /// L'evento tocca questo giorno?
    func nelGiorno(_ g: Date) -> Bool {
        guard let i = dataInizio else { return false }
        let cal = Calendar.current
        let a = cal.startOfDay(for: i), b = cal.startOfDay(for: dataFine ?? i), x = cal.startOfDay(for: g)
        return x >= a && x <= b
    }
}

struct Etichetta: View {
    let testo: String
    let colore: Color
    var body: some View {
        Text(testo).font(Theme.mono(9, .heavy)).foregroundStyle(colore)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(colore.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(colore.opacity(0.35)))
    }
}

/// Immagine di copertina dell'evento (dal server, con copia sul telefono).
struct CopertinaEvento: View {
    let evento: JEvento
    var altezza: CGFloat = 200
    @State private var img: UIImage?

    var body: some View {
        ZStack {
            LinearGradient(colors: [evento.colore.opacity(0.55), Theme.bg], startPoint: .topTrailing, endPoint: .bottomLeading)
            if let img { Image(uiImage: img).resizable().scaledToFill() } else {
                Image(systemName: evento.icona).font(.system(size: altezza * 0.3)).foregroundStyle(.white.opacity(0.18))
            }
        }
        .frame(height: altezza)
        .frame(maxWidth: .infinity)
        .clipped()
        .task(id: "\(evento.id)-\(evento.copertina ?? "")") {
            guard let v = evento.copertina, !v.isEmpty else { img = nil; return }
            let f = EventoStore.cartella.appendingPathComponent("copertina_\(evento.id)_\(v).jpg")
            if let d = try? Data(contentsOf: f), let i = UIImage(data: d) { img = i; return }
            if let d = try? await JsocClient.shared.scaricaDati("/api/eventi/\(evento.id)/copertina"), let i = UIImage(data: d) {
                img = i
                try? d.write(to: f, options: .atomic)
            }
        }
    }
}

struct TesseraData: View {
    let evento: JEvento
    var body: some View {
        let d = evento.dataInizio
        VStack(spacing: 0) {
            Text(d.map { $0.formatted(.dateTime.month(.abbreviated)).uppercased() } ?? "—").font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.dim)
            Text(d.map { $0.formatted(.dateTime.day()) } ?? "?").font(Theme.mono(19, .heavy)).foregroundStyle(.white)
        }
        .frame(width: 46, height: 50)
        .background(evento.colore.opacity(evento.fase == 2 ? 0.08 : 0.22), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct RigaEventoV2: View {
    let evento: JEvento
    var body: some View {
        let e = evento
        HStack(spacing: 12) {
            TesseraData(evento: e)
            VStack(alignment: .leading, spacing: 3) {
                Text(e.nome).font(.system(size: 14.5, weight: .heavy)).foregroundStyle(e.fase == 2 ? Theme.dim : .white).lineLimit(1)
                Text(sottotitolo).font(.system(size: 11.5)).foregroundStyle(Theme.dim).lineLimit(1)
                HStack(spacing: 5) {
                    Etichetta(testo: e.nomeTipo, colore: e.colore)
                    if e.tipo != "riunione" { Etichetta(testo: e.interno == 1 ? "INTERNO" : "ESTERNO", colore: Theme.dim) }
                    if e.proposto { Etichetta(testo: "DA APPROVARE", colore: Theme.amber) }
                }
            }
            Spacer(minLength: 4)
            Text(stato.0).font(.system(size: 10.5, weight: .heavy)).foregroundStyle(stato.1).multilineTextAlignment(.trailing).frame(width: 74, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.stroke))
    }

    var sottotitolo: String {
        var p: [String] = []
        if let d = evento.dataInizio { p.append(d.formatted(.dateTime.weekday(.wide).hour().minute())) }
        if let l = evento.luogo, !l.isEmpty { p.append(l) }
        if let n = evento.posti, n > 0 { p.append("\(evento.n_si ?? 0)/\(n) posti") }
        if let q = evento.quota, q > 0 { p.append(String(format: "%.0f €", q)) }
        return p.joined(separator: " · ")
    }

    var stato: (String, Color) {
        if evento.proposto { return ("In attesa", Theme.dim) }
        switch evento.mia_risposta {
        case "si": return ("Partecipi", Theme.oliveBright)
        case "no", "forse": return ("Non partecipi", Theme.red)
        case "attesa": return ("In lista d'attesa", Theme.amber)
        default: return evento.fase == 2 ? ("", Theme.dim) : ("Senza risposta", Theme.amber)
        }
    }
}

// MARK: - Home

struct HomeV2: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var store = EventoStore.shared
    @ObservedObject private var home = HomeModel.shared
    @State private var mese = Date()
    @State private var giorno = Date()
    @State private var percorso: [JEvento] = []
    @State private var profilo = false

    var body: some View {
        NavigationStack(path: $percorso) {
            Group {
                if jsoc.collegato { contenuto } else { EntraView() }
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: JEvento.self) { EventoScheda(evento: $0) }
        }
        .sheet(isPresented: $profilo) { ProfiloTab() }
        .task { await home.aggiorna() }
    }

    var contenuto: some View {
        GeometryReader { g in
            let land = g.size.width > g.size.height
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    intestazione
                    if land {
                        HStack(alignment: .top, spacing: 14) {
                            VStack(spacing: 12) { banner; calendario }.frame(width: min(420, g.size.width * 0.46))
                            VStack(alignment: .leading, spacing: 12) { delGiorno; daFare; luoghi }
                        }
                    } else {
                        banner; calendario; delGiorno; daFare; luoghi
                    }
                }
                .padding(14)
                .padding(.bottom, land ? 10 : 70)
            }
            .refreshable { await store.aggiorna(jsoc); await home.aggiorna() }
        }
    }

    var intestazione: some View {
        HStack {
            Text("Home").font(.system(size: 32, weight: .black))
            Spacer()
            Button { vaiAllaScheda(Schede.eventi) } label: {
                Image(systemName: "bell.fill").font(.system(size: 17)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Theme.surface, in: Circle()).overlay(Circle().strokeBorder(Theme.stroke))
                    .overlay(alignment: .topTrailing) {
                        if !(home.dati?.avvisi ?? []).isEmpty { Circle().fill(Theme.red).frame(width: 9, height: 9).offset(x: -4, y: 4) }
                    }
            }
            Button { profilo = true } label: {
                FotoSocio(id: jsoc.utente?.id, iniziali: jsoc.utente?.callsign ?? "?", lato: 40)
            }
            .accessibilityLabel("Profilo")
        }
    }

    var senzaRisposta: [JEvento] { store.eventi.filter { $0.fase != 2 && !$0.proposto && $0.mia_risposta == nil } }

    @ViewBuilder var banner: some View {
        if let e = senzaRisposta.first {
            NavigationLink(value: e) {
                HStack(spacing: 8) {
                    Circle().fill(Theme.amber).frame(width: 8, height: 8)
                    Text(senzaRisposta.count == 1 ? "1 evento senza risposta" : "\(senzaRisposta.count) eventi senza risposta")
                }
                .font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.amber)
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(Theme.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.amber.opacity(0.4)))
            }
            .buttonStyle(PressStyle())
        }
    }

    var calendario: some View {
        let cal = Calendar(identifier: .iso8601)
        let inizioMese = cal.date(from: cal.dateComponents([.year, .month], from: mese)) ?? mese
        let giorni = cal.range(of: .day, in: .month, for: inizioMese)?.count ?? 30
        let vuoti = (cal.component(.weekday, from: inizioMese) + 5) % 7      // lunedì = 0
        return VStack(spacing: 8) {
            HStack {
                Button { cambiaMese(-1) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 32) }
                Spacer()
                Text(inizioMese.formatted(.dateTime.month(.wide).year()).capitalized).font(.system(size: 15, weight: .heavy))
                Spacer()
                Button { cambiaMese(1) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 32) }
            }
            .foregroundStyle(Theme.dim)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(["L", "M", "M", "G", "V", "S", "D"].indices, id: \.self) { i in
                    Text(["L", "M", "M", "G", "V", "S", "D"][i]).font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.dim)
                }
                ForEach(0..<vuoti, id: \.self) { _ in Color.clear.frame(height: 40) }
                ForEach(1...giorni, id: \.self) { d in
                    let data = cal.date(byAdding: .day, value: d - 1, to: inizioMese) ?? inizioMese
                    cella(data, d, cal)
                }
            }
            HStack(spacing: 12) {
                legenda("Gara", Theme.red); legenda("Allenamento", Theme.olive); legenda("Riunione", Theme.cyan); legenda("Associazione", Theme.amber)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.stroke))
    }

    func cella(_ data: Date, _ d: Int, _ cal: Calendar) -> some View {
        let scelto = cal.isDate(data, inSameDayAs: giorno)
        let oggi = cal.isDateInToday(data)
        let colori = Array(store.eventi.filter { $0.nelGiorno(data) }.map(\.colore).prefix(3))
        return Button { haptic(.soft); giorno = data } label: {
            VStack(spacing: 3) {
                Text("\(d)").font(Theme.mono(13, .heavy)).foregroundStyle(scelto ? Color.black : .white)
                HStack(spacing: 2) { ForEach(colori.indices, id: \.self) { i in Circle().fill(colori[i]).frame(width: 5, height: 5) } }.frame(height: 5)
            }
            .frame(maxWidth: .infinity).frame(height: 40)
            .background(scelto ? Theme.olive : .clear, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(oggi && !scelto ? Theme.olive : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    func legenda(_ t: String, _ c: Color) -> some View {
        HStack(spacing: 4) { Circle().fill(c).frame(width: 7, height: 7); Text(t) }.font(.system(size: 10)).foregroundStyle(Theme.dim)
    }

    func cambiaMese(_ n: Int) {
        haptic(.soft)
        mese = Calendar.current.date(byAdding: .month, value: n, to: mese) ?? mese
    }

    var delGiorno: some View {
        let ev = store.eventi.filter { $0.nelGiorno(giorno) }.sorted { ($0.dataInizio ?? .distantPast) < ($1.dataInizio ?? .distantPast) }
        return VStack(alignment: .leading, spacing: 8) {
            Text(giorno.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                .font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.dim)
            if ev.isEmpty {
                Text("Nessun evento").font(.system(size: 13)).foregroundStyle(Theme.dim).padding(.vertical, 6)
            }
            ForEach(ev) { e in NavigationLink(value: e) { RigaEventoV2(evento: e) }.buttonStyle(PressStyle()) }
        }
    }

    @ViewBuilder var daFare: some View {
        let avvisi = (home.dati?.avvisi ?? []).filter { $0.tipo != "evento" }
        let sondaggi = home.dati?.sondaggi_aperti ?? 0
        let proposte = home.dati?.direttivo?.proposte ?? 0
        if !avvisi.isEmpty || sondaggi > 0 || proposte > 0 {
            VStack(alignment: .leading, spacing: 8) {
                Text("DA FARE").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.dim)
                if proposte > 0 {
                    riga("checkmark.seal.fill", proposte == 1 ? "1 evento proposto da approvare" : "\(proposte) eventi proposti da approvare", Theme.amber) { vaiAllaScheda(Schede.eventi) }
                }
                if sondaggi > 0 {
                    riga("chart.bar.fill", sondaggi == 1 ? "1 sondaggio da votare" : "\(sondaggi) sondaggi da votare", Theme.cyan) { vaiAllaScheda(Schede.associazione) }
                }
                ForEach(avvisi, id: \.self) { a in
                    riga(a.tipo == "promemoria" ? "bell.badge.fill" : "exclamationmark.triangle.fill", a.testo, a.tipo == "promemoria" ? Theme.amber : Theme.red) {
                        if let id = a.evento, let e = store.eventi.first(where: { $0.id == id }) { percorso.append(e) } else { vaiAllaScheda(Schede.associazione) }
                    }
                }
            }
        }
    }

    func riga(_ icona: String, _ testo: String, _ colore: Color, _ f: @escaping () -> Void) -> some View {
        Button { haptic(); f() } label: {
            HStack(spacing: 10) {
                Image(systemName: icona).foregroundStyle(colore).frame(width: 22)
                Text(testo).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white).multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.dim)
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.stroke))
        }
        .buttonStyle(PressStyle())
    }

    struct Luogo: Identifiable { let id: Int; let c: CLLocationCoordinate2D; let e: JEvento }

    @ViewBuilder var luoghi: some View {
        let l = store.eventi.filter { $0.fase != 2 && $0.lat != nil && $0.lon != nil }
            .map { Luogo(id: $0.id, c: .init(latitude: $0.lat!, longitude: $0.lon!), e: $0) }
        if !l.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("LUOGHI DEI PROSSIMI EVENTI").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.dim)
                    Spacer()
                    Text("senza posizioni dei membri").font(.system(size: 10)).foregroundStyle(Theme.dim)
                }
                Map(coordinateRegion: .constant(Self.regione(l.map(\.c))), annotationItems: l) { x in
                    MapAnnotation(coordinate: x.c) {
                        Button { percorso.append(x.e) } label: {
                            Image(systemName: "mappin.circle.fill").font(.system(size: 28)).foregroundStyle(.white, x.e.colore)
                                .shadow(radius: 3)
                        }
                    }
                }
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.stroke))
            }
        }
    }

    static func regione(_ c: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let la = c.map(\.latitude), lo = c.map(\.longitude)
        let centro = CLLocationCoordinate2D(latitude: (la.min()! + la.max()!) / 2, longitude: (lo.min()! + lo.max()!) / 2)
        return MKCoordinateRegion(center: centro, span: MKCoordinateSpan(latitudeDelta: max(0.08, (la.max()! - la.min()!) * 1.5),
                                                                          longitudeDelta: max(0.08, (lo.max()! - lo.min()!) * 1.5)))
    }
}

// MARK: - Eventi (come Spond)

struct EventiV2: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var store = EventoStore.shared
    @State private var percorso: [JEvento] = []
    @State private var passati = false
    @State private var filtro = "tutti"
    @State private var nuovo = false
    @State private var scelto: JEvento?

    var body: some View {
        NavigationStack(path: $percorso) {
            Group {
                if jsoc.collegato { contenuto } else { EntraView() }
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: JEvento.self) { EventoScheda(evento: $0) }
        }
        .sheet(isPresented: $nuovo) { NuovoEventoV2() }
    }

    var contenuto: some View {
        GeometryReader { g in
            if g.size.width > g.size.height {
                // orizzontale: elenco a sinistra, scheda dell'evento a destra
                HStack(spacing: 0) {
                    elenco(land: true).frame(width: min(400, g.size.width * 0.42))
                    Divider().overlay(Theme.stroke)
                    if let e = scelto ?? visibili.first {
                        EventoScheda(evento: e).id(e.id)
                    } else {
                        Text("Scegli un evento").foregroundStyle(Theme.dim).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                elenco(land: false)
            }
        }
    }

    var visibili: [JEvento] {
        store.eventi.filter { e in
            (passati ? e.fase == 2 : e.fase != 2) && (filtro == "tutti" || e.tipo == filtro || (filtro == "altro" && !["gara", "allenamento", "riunione"].contains(e.tipo)))
        }
        .sorted { passati ? ($0.dataInizio ?? .distantPast) > ($1.dataInizio ?? .distantPast) : ($0.dataInizio ?? .distantFuture) < ($1.dataInizio ?? .distantFuture) }
    }

    /// raggruppati per settimana come Spond
    var settimane: [(String, [JEvento])] {
        let cal = Calendar(identifier: .iso8601)
        var gruppi: [(Date, [JEvento])] = []
        for e in visibili {
            let k = cal.dateInterval(of: .weekOfYear, for: e.dataInizio ?? .distantFuture)?.start ?? .distantFuture
            if let i = gruppi.firstIndex(where: { $0.0 == k }) { gruppi[i].1.append(e) } else { gruppi.append((k, [e])) }
        }
        let questa = cal.dateInterval(of: .weekOfYear, for: Date())?.start
        return gruppi.map { k, v in
            if k == questa { return ("QUESTA SETTIMANA", v) }
            let fine = cal.date(byAdding: .day, value: 6, to: k) ?? k
            return ((k.formatted(.dateTime.day().month(.abbreviated)) + " – " + fine.formatted(.dateTime.day().month(.abbreviated))).uppercased(), v)
        }
    }

    func elenco(land: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Eventi").font(.system(size: 32, weight: .black))
                    Spacer()
                    Button { haptic(); nuovo = true } label: {
                        Label(jsoc.utente?.direttivo == true ? "Nuovo" : "Proponi", systemImage: "plus")
                            .font(.system(size: 13.5, weight: .heavy)).foregroundStyle(.black)
                            .padding(.horizontal, 14).frame(height: 38).background(Theme.olive, in: Capsule())
                    }
                }
                Picker("", selection: $passati) { Text("In programma").tag(false); Text("Passati").tag(true) }.pickerStyle(.segmented)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach([("tutti", "Tutti"), ("gara", "Gare"), ("allenamento", "Allenamenti"), ("riunione", "Riunioni"), ("altro", "Associazione")], id: \.0) { f in
                            Button { haptic(.soft); filtro = f.0 } label: {
                                Text(f.1).font(.system(size: 12, weight: .bold)).foregroundStyle(filtro == f.0 ? .black : .white)
                                    .padding(.horizontal, 12).frame(height: 30)
                                    .background(filtro == f.0 ? Theme.olive : Theme.surface, in: Capsule())
                                    .overlay(Capsule().strokeBorder(Theme.stroke))
                            }
                        }
                    }
                }
                let senza = store.eventi.filter { $0.fase != 2 && !$0.proposto && $0.mia_risposta == nil }.count
                if senza > 0 && !passati {
                    Text("● \(senza == 1 ? "1 evento" : "\(senza) eventi") senza risposta").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.amber)
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .background(Theme.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }
                if visibili.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.plus").font(.largeTitle).foregroundStyle(Theme.dim)
                        Text(passati ? "Nessun evento passato" : "Nessun evento in programma").foregroundStyle(Theme.dim)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 40)
                }
                ForEach(settimane, id: \.0) { titolo, ev in
                    Text(titolo).font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.dim).padding(.top, 4)
                    ForEach(ev) { e in
                        if land {
                            Button { haptic(.soft); scelto = e } label: {
                                RigaEventoV2(evento: e)
                                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(scelto?.id == e.id ? Theme.olive : .clear, lineWidth: 2))
                            }
                            .buttonStyle(PressStyle())
                        } else {
                            NavigationLink(value: e) { RigaEventoV2(evento: e) }.buttonStyle(PressStyle())
                        }
                    }
                }
            }
            .padding(14)
            .padding(.bottom, land ? 10 : 70)
        }
        .refreshable { await store.aggiorna(jsoc) }
    }
}

// MARK: - Scheda dell'evento

struct EventoScheda: View {
    let evento: JEvento
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var store = EventoStore.shared
    @State private var presenze: JPresenze?
    @State private var errore: String?
    @State private var avviso: String?
    @State private var domande = false
    @State private var risposte: [String: String] = [:]
    @State private var tutto = false
    @State private var documenti = false

    var e: JEvento { store.eventi.first { $0.id == evento.id } ?? evento }
    var mia: String? { presenze?.presenze.first { $0.utente == jsoc.utente?.id }?.risposta ?? e.mia_risposta }
    var gestore: Bool { jsoc.utente?.direttivo == true || e.staff }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                CopertinaEvento(evento: e, altezza: 210)
                    .overlay(alignment: .bottom) { LinearGradient(colors: [.clear, Theme.bg], startPoint: .center, endPoint: .bottom) }
                VStack(alignment: .leading, spacing: 12) {
                    testata
                    if e.proposto { proposta }
                    tessere
                    if !e.proposto && e.fase != 2 { iscrizione }
                    if let avviso { Text(avviso).font(.caption).foregroundStyle(Theme.oliveBright) }
                    if let errore { ErrorCard(text: errore) }
                    if e.membro && !e.proposto { sezioni }
                    if let n = e.note, !n.isEmpty { descrizione(n) }
                    if let p = presenze { risposteCard(p) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 80)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await carica() }
        .refreshable { await store.aggiorna(jsoc); await carica() }
        .sheet(isPresented: $domande) { domandeSheet }
        .fullScreenCover(isPresented: $documenti) {
            ZStack(alignment: .topTrailing) {
                DocsTab()
                Button { documenti = false } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 28)).symbolRenderingMode(.palette).foregroundStyle(.white, Theme.surface2)
                }
                .padding(.trailing, 14).padding(.top, 4)
            }
        }
        .navigationDestination(isPresented: $tutto) { EventoView(evento: e) }
    }

    var testata: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Etichetta(testo: e.nomeTipo, colore: e.colore)
                if e.tipo != "riunione" { Etichetta(testo: e.interno == 1 ? "INTERNO · ATTACCO/DIFESA" : "ESTERNO · SQUADRA JSOC", colore: Theme.dim) }
            }
            Text(e.nome).font(.system(size: 25, weight: .black)).fixedSize(horizontal: false, vertical: true)
            if let h = e.host { Text("Organizza: \(h)").font(.system(size: 12.5)).foregroundStyle(Theme.dim) }
            if let i = e.dataInizio {
                Label(i.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()) + (e.dataFine.map { " – " + $0.formatted(date: .omitted, time: .shortened) } ?? ""),
                      systemImage: "calendar").font(.system(size: 13))
            }
            if let l = e.luogo, !l.isEmpty {
                Button {
                    store.scegli(e); vaiAllaScheda(Schede.mappa)
                } label: {
                    Label { Text(l).foregroundStyle(.white) + Text(e.lat != nil ? "  · apri in mappa" : "").foregroundStyle(Theme.oliveBright) } icon: { Image(systemName: "mappin") }
                        .font(.system(size: 13))
                }
                .disabled(!e.membro || e.lat == nil)
            }
        }
    }

    var proposta: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Proposta in attesa di approvazione del direttivo", systemImage: "hourglass").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.amber)
            if jsoc.utente?.direttivo == true {
                HStack(spacing: 8) {
                    Button { azione { try await jsoc.approvaEvento(e.id); return "Evento approvato: ora lo vedono tutti" } } label: {
                        Text("Approva").frame(maxWidth: .infinity)
                    }.buttonStyle(PrimaryButtonStyle())
                    Button(role: .destructive) { azione { try await jsoc.togliEvento(e.id); return "Proposta rifiutata" } } label: {
                        Text("Rifiuta").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).tint(Theme.red)
                }
            } else if e.staff {
                Button(role: .destructive) { azione { try await jsoc.togliEvento(e.id); return "Proposta ritirata" } } label: { Text("Ritira la proposta") }
                    .buttonStyle(.bordered).tint(Theme.red)
            }
        }
        .padding(12)
        .background(Theme.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }

    var datiTessere: [(String, String, Color)] {
        var t: [(String, String, Color)] = []
        if let s = e.dataScadenza {
            t.append((s.formatted(.dateTime.day().month(.abbreviated)), e.iscrizioniChiuse ? "ISCRIZIONI CHIUSE" : "SCADENZA", Theme.amber))
        }
        if let p = e.posti, p > 0 {
            let attesa = e.n_attesa ?? 0
            t.append(("\(e.n_si ?? 0) / \(p)", attesa > 0 ? "POSTI · \(attesa) IN ATTESA" : "POSTI", Color.white))
        }
        if let q = e.quota, q > 0 { t.append((String(format: "%.2f €", q), "QUOTA", Color.white)) }
        return t
    }

    @ViewBuilder var tessere: some View {
        let t = datiTessere
        if !t.isEmpty {
            HStack(spacing: 6) {
                ForEach(t, id: \.1) { v in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(v.0).font(Theme.mono(14, .heavy)).foregroundStyle(v.2)
                        Text(v.1).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.dim).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(9)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.stroke))
                }
            }
        }
    }

    var iscrizione: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button { scegli("si") } label: {
                    Label("Partecipo", systemImage: "checkmark").font(.system(size: 14, weight: .heavy))
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .foregroundStyle(mia == "si" || mia == "attesa" ? Color.black : Theme.oliveBright)
                        .background(mia == "si" || mia == "attesa" ? Theme.olive : Theme.surface, in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.stroke))
                }
                Button { scegli("no") } label: {
                    Text("Non partecipo").font(.system(size: 14, weight: .heavy))
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .foregroundStyle(mia == "no" || mia == "forse" ? Color.white : Theme.red)
                        .background(mia == "no" || mia == "forse" ? Theme.red.opacity(0.85) : Theme.surface, in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.stroke))
                }
            }
            .disabled(e.iscrizioniChiuse && jsoc.utente?.direttivo != true)
            if mia == "attesa" { Text("Posti finiti: sei in lista d'attesa, entri appena qualcuno si ritira.").font(.caption).foregroundStyle(Theme.amber) }
            if e.iscrizioniChiuse { Text("Iscrizioni chiuse il \(e.dataScadenza!.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(Theme.dim) }
        }
    }

    var sezioni: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            tasto("map.fill", "Mappa", "squadra e punti") { store.scegli(e); vaiAllaScheda(Schede.mappa) }
            tasto("folder.fill", "Documenti", "file dell'evento") { store.scegli(e); documenti = true }
            tasto("bubble.left.and.bubble.right.fill", "Chat", "con chi partecipa") { store.scegli(e); UserDefaults.standard.set(true, forKey: "eventi.apriChat"); tutto = true }
            tasto("ellipsis.circle.fill", "Tutte le funzioni", "video, membri, punti") { store.scegli(e); tutto = true }
        }
    }

    func tasto(_ icona: String, _ titolo: String, _ sotto: String, _ f: @escaping () -> Void) -> some View {
        Button { haptic(); f() } label: {
            HStack(spacing: 10) {
                Image(systemName: icona).font(.system(size: 18)).foregroundStyle(Theme.oliveBright).frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(titolo).font(.system(size: 13.5, weight: .heavy)).foregroundStyle(.white)
                    Text(sotto).font(.system(size: 10.5)).foregroundStyle(Theme.dim)
                }
                Spacer(minLength: 0)
            }
            .padding(11)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.stroke))
        }
        .buttonStyle(PressStyle())
    }

    @State private var espandi = false
    func descrizione(_ n: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Descrizione").font(.system(size: 15, weight: .heavy))
            Text(n).font(.system(size: 13.5)).lineLimit(espandi ? nil : 6)
            if n.count > 300 { Button(espandi ? "Mostra meno" : "Leggi di più") { espandi.toggle() }.font(.system(size: 13, weight: .bold)).tint(Theme.oliveBright) }
        }
    }

    func risposteCard(_ p: JPresenze) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Risposte").font(.system(size: 15, weight: .heavy))
            NavigationLink { RisposteView(evento: e, presenze: p, filtro: "si") } label: { rigaConta("checkmark.circle", Theme.olive, "\(p.conta.si) partecipano") }
            if let a = p.conta.attesa, a > 0 {
                NavigationLink { RisposteView(evento: e, presenze: p, filtro: "attesa") } label: { rigaConta("hourglass", Theme.amber, "\(a) in lista d'attesa") }
            }
            NavigationLink { RisposteView(evento: e, presenze: p, filtro: "senza") } label: { rigaConta("questionmark.circle", Theme.amber, "\(p.conta.senza_risposta) senza risposta") }
            NavigationLink { RisposteView(evento: e, presenze: p, filtro: "no") } label: { rigaConta("xmark.circle", Theme.red, "\(p.conta.no + p.conta.forse) non partecipano") }
            if gestore && p.conta.senza_risposta > 0 && e.fase != 2 && !e.proposto {
                Button {
                    azione { let n = try await jsoc.promemoria(e.id); return "Promemoria mandato a \(n) soci" }
                } label: {
                    Label("Manda promemoria a chi non ha risposto", systemImage: "bell.badge").font(.system(size: 13, weight: .heavy))
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .foregroundStyle(Theme.amber).background(Theme.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.stroke))
    }

    func rigaConta(_ icona: String, _ c: Color, _ t: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icona).foregroundStyle(c)
            Text(t).font(.system(size: 13.5)).foregroundStyle(.white)
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.dim)
        }
        .padding(.vertical, 6)
    }

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
        Task {
            do {
                presenze = try await jsoc.rispondi(e.id, r, risposte: r == "si" ? risposte : [:])
                errore = nil
                await store.aggiorna(jsoc)
                await HomeModel.shared.aggiorna()
            } catch { errore = error.localizedDescription }
        }
    }

    func azione(_ f: @escaping () async throws -> String) {
        haptic(.medium)
        Task {
            do { avviso = try await f(); errore = nil; await store.aggiorna(jsoc); await HomeModel.shared.aggiorna() }
            catch { errore = error.localizedDescription }
        }
    }

    func carica() async {
        presenze = try? await jsoc.presenze(e.id)
    }
}

/// Chi ha risposto: Partecipano · In attesa · Senza risposta · Non partecipano · Tutti, con ricerca.
struct RisposteView: View {
    let evento: JEvento
    @State var presenze: JPresenze
    @State var filtro: String
    @State private var cerca = ""

    var righe: [JPresenza] {
        presenze.presenze.filter { p in
            let ok: Bool
            switch filtro {
            case "si": ok = p.risposta == "si"
            case "attesa": ok = p.risposta == "attesa"
            case "no": ok = p.risposta == "no" || p.risposta == "forse"
            case "senza": ok = p.risposta == nil
            default: ok = true
            }
            return ok && (cerca.isEmpty || p.callsign.localizedCaseInsensitiveContains(cerca) || (p.nome ?? "").localizedCaseInsensitiveContains(cerca))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $filtro) {
                Text("Presenti").tag("si"); Text("Senza risp.").tag("senza"); Text("No").tag("no"); Text("Tutti").tag("tutti")
            }
            .pickerStyle(.segmented).padding(12)
            List(righe) { p in
                HStack(spacing: 10) {
                    FotoSocio(id: p.utente, iniziali: p.callsign, lato: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.callsign).font(.system(size: 14, weight: .heavy))
                        if let n = p.nome { Text(n).font(.caption).foregroundStyle(Theme.dim) }
                    }
                    Spacer()
                    Image(systemName: p.risposta == "si" ? "checkmark.circle.fill" : (p.risposta == "attesa" ? "hourglass" : (p.risposta == nil ? "questionmark.circle" : "xmark.circle.fill")))
                        .foregroundStyle(p.risposta == "si" ? Theme.olive : (p.risposta == nil || p.risposta == "attesa" ? Theme.amber : Theme.red))
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .searchable(text: $cerca, prompt: "Cerca")
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Destinatari")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Nuovo evento / proposta (con immagine di copertina)

struct NuovoEventoV2: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var location: LocationService
    @ObservedObject private var jsoc = JsocClient.shared
    @State private var foto: PhotosPickerItem?
    @State private var copertina: UIImage?
    @State private var nome = ""
    @State private var tipo = "allenamento"
    @State private var interno = true
    @State private var inizio = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var fine = Calendar.current.date(byAdding: .day, value: 7, to: Date())?.addingTimeInterval(4 * 3600) ?? Date()
    @State private var luogo = ""
    @State private var quiPosizione = false
    @State private var note = ""
    @State private var conScadenza = false
    @State private var scadenza = Calendar.current.date(byAdding: .day, value: 5, to: Date()) ?? Date()
    @State private var conPosti = false
    @State private var posti = 8
    @State private var conQuota = false
    @State private var quota = ""
    @State private var domande: [String] = []
    @State private var nuovaDomanda = ""
    @State private var lavoro = false
    @State private var errore: String?

    var direttivo: Bool { jsoc.utente?.direttivo == true }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $foto, matching: .images) {
                        ZStack {
                            if let copertina { Image(uiImage: copertina).resizable().scaledToFill() } else { Theme.surface2 }
                            VStack(spacing: 6) {
                                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 26))
                                Text(copertina == nil ? "Aggiungi immagine di copertina" : "Cambia immagine").font(.system(size: 13, weight: .heavy))
                            }
                            .foregroundStyle(.white).padding(10).background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .frame(height: 160).frame(maxWidth: .infinity).clipped()
                    }
                    .listRowInsets(EdgeInsets())
                }
                Section("Evento") {
                    TextField("Titolo (es. Domenicale CQB)", text: $nome)
                    Picker("Tipo", selection: $tipo) {
                        Text("Gara").tag("gara"); Text("Allenamento").tag("allenamento"); Text("Riunione").tag("riunione"); Text("Associazione").tag("altro")
                    }
                    if tipo != "riunione" {
                        Picker("Squadre", selection: $interno) {
                            Text("Interno · Attacco/Difesa").tag(true); Text("Esterno · squadra JSOC").tag(false)
                        }
                        .pickerStyle(.segmented)
                    }
                    DatePicker("Inizio", selection: $inizio, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Fine", selection: $fine, in: inizio..., displayedComponents: [.date, .hourAndMinute])
                }
                Section("Dove") {
                    TextField("Luogo", text: $luogo)
                    Toggle("Usa la mia posizione per la mappa", isOn: $quiPosizione)
                }
                Section("Iscrizioni") {
                    Toggle("Scadenza per rispondere", isOn: $conScadenza)
                    if conScadenza { DatePicker("Entro il", selection: $scadenza, in: ...inizio, displayedComponents: .date) }
                    Toggle("Posti limitati", isOn: $conPosti)
                    if conPosti { Stepper("\(posti) posti (poi lista d'attesa)", value: $posti, in: 1...200) }
                    Toggle("Quota di partecipazione", isOn: $conQuota)
                    if conQuota { TextField("Quota in €", text: $quota).keyboardType(.decimalPad) }
                }
                Section("Domande all'iscrizione") {
                    ForEach(domande, id: \.self) { d in Text(d) }.onDelete { domande.remove(atOffsets: $0) }
                    HStack {
                        TextField("Es. Porti l'auto? Quanti posti?", text: $nuovaDomanda)
                        Button("Aggiungi") {
                            let t = nuovaDomanda.trimmingCharacters(in: .whitespaces)
                            if !t.isEmpty && !domande.contains(t) { domande.append(t) }
                            nuovaDomanda = ""
                        }
                    }
                }
                Section("Descrizione") { TextField("Programma, regolamento, materiale", text: $note, axis: .vertical).lineLimit(3...10) }
                if !direttivo {
                    Section { Label("Lo vedranno tutti dopo l'approvazione del direttivo", systemImage: "checkmark.seal").foregroundStyle(Theme.amber) }
                }
                if let errore { Section { Text(errore).foregroundStyle(Theme.red) } }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(direttivo ? "Nuovo evento" : "Proponi evento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(direttivo ? "Crea" : "Proponi") { crea() }.disabled(nome.trimmingCharacters(in: .whitespaces).isEmpty || lavoro)
                }
            }
            .onChange(of: foto) { f in
                Task {
                    if let d = try? await f?.loadTransferable(type: Data.self), let i = UIImage(data: d) { copertina = i }
                }
            }
        }
    }

    func crea() {
        lavoro = true; errore = nil
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        var campi: [String: Any] = ["nome": nome.trimmingCharacters(in: .whitespaces), "tipo": tipo,
                                    "inizio": f.string(from: inizio), "fine": f.string(from: fine),
                                    "luogo": luogo, "note": note, "interno": tipo != "riunione" && interno ? 1 : 0, "domande": domande]
        if conScadenza { campi["scadenza"] = f.string(from: scadenza) }
        if conPosti { campi["posti"] = posti }
        if conQuota, let q = Double(quota.replacingOccurrences(of: ",", with: ".")) { campi["quota"] = q }
        if quiPosizione, let c = location.location?.coordinate { campi["lat"] = c.latitude; campi["lon"] = c.longitude }
        Task {
            do {
                let e = try await jsoc.creaEvento(campi)
                if let img = copertina, let d = img.ridotta(lato: 1600).jpegData(compressionQuality: 0.75) {
                    try? await jsoc.caricaDati("/api/eventi/\(e.id)/copertina", dati: d)
                }
                await EventoStore.shared.aggiorna(jsoc)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } catch { errore = error.localizedDescription }
            lavoro = false
        }
    }
}
