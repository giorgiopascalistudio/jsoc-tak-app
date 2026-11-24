import SwiftUI
import CoreLocation
import AVKit
import PhotosUI
import QuickLook
import HaishinKit
import MapLibre
import UserNotifications
import MessageUI

// MARK: - Stato condiviso della mappa

enum SelezioneMappa: Hashable {
    case punto(Int)
    case compagno(Int)
}

enum PannelloMappa: Equatable {
    case resoconto(Int), video(String?), naviga, squadra, chat(Int?), livelli, misura, info(Int), strumenti, impostazioni
    case nuovoPunto(Double, Double)
    case segnala
    case coordinate
    case disegno(String), rotta, cerchi, profilo, simboli, noveRighe, salute, pacchetti, lora
    case meteo, cerca, telecamera(Int), replay, cronologia, vista360, piuVicini(Int), medico, balistica, droni
}

/// Punto toccabile sotto il dito (per scegliere quando sono vicini).
struct Candidato: Identifiable {
    let id = UUID()
    let sel: SelezioneMappa
    let c: CLLocationCoordinate2D
    let nome: String
    let colore: Color
    let distanza: CGFloat
}

/// Coordinate nel formato scelto nelle impostazioni della mappa.
func coordTesto(_ c: CLLocationCoordinate2D) -> String {
    switch UserDefaults.standard.string(forKey: "mappa.coordinate") ?? "utm" {
    case "utm": return Coordinate.utmText(c)
    case "dd": return String(format: "%.5f, %.5f", c.latitude, c.longitude)
    case "dms":
        func g(_ v: Double, _ p: String, _ n: String) -> String {
            let a = abs(v), d = Int(a), m = Int((a - Double(d)) * 60), s = (a - Double(d) - Double(m) / 60) * 3600
            return String(format: "%d°%02d'%04.1f\"%@", d, m, s, v >= 0 ? p : n)
        }
        return g(c.latitude, "N", "S") + " " + g(c.longitude, "E", "O")
    default: return Geo.mgrs(c)
    }
}

/// Traccia registrata (resta anche chiudendo l'app).
@MainActor
final class Traccia: ObservableObject {
    static let shared = Traccia()
    @Published private(set) var punti: [CLLocationCoordinate2D] = []
    @Published var attiva = UserDefaults.standard.bool(forKey: "traccia.attiva") {
        didSet { UserDefaults.standard.set(attiva, forKey: "traccia.attiva") }
    }
    private var file: URL { EventoStore.cartella.appendingPathComponent("traccia.json") }

    init() {
        if let d = try? Data(contentsOf: file), let a = try? JSONDecoder().decode([[Double]].self, from: d) {
            punti = a.map { .init(latitude: $0[0], longitude: $0[1]) }
        }
    }
    var metri: Double { zip(punti, punti.dropFirst()).reduce(0) { $0 + Geo.distance($1.0, $1.1) } }
    var testo: String { metri < 1000 ? String(format: "%.0f m", metri) : String(format: "%.1f km", metri / 1000).replacingOccurrences(of: ".", with: ",") }

    func aggiungi(_ l: CLLocation) {
        guard attiva, l.horizontalAccuracy >= 0, l.horizontalAccuracy < 30 else { return }
        if let u = punti.last, Geo.distance(u, l.coordinate) < 8 { return }
        punti.append(l.coordinate)
        if punti.count % 5 == 0 { salva() }
    }
    func azzera() { punti = []; salva() }
    func salva() { try? JSONEncoder().encode(punti.map { [$0.latitude, $0.longitude] }).write(to: file, options: .atomic) }
}

private let oliva = Theme.olive
private let olivaChiaro = Theme.oliveBright
private let fondoPannello = Color(red: 0.043, green: 0.051, blue: 0.031)

// MARK: - Schermata

extension Notification.Name { static let mappaCentra = Notification.Name("jsoc.mappaCentra") }

struct MappaTattica: View {
    /// punto su cui centrarsi alla prossima apertura (Strumenti › Coordinate › In mappa / Naviga)
    static var centroInSospeso: CLLocationCoordinate2D?

    func centraInSospeso() {
        guard let c = Self.centroInSospeso else { return }
        Self.centroInSospeso = nil
        ctl.vai(c, zoom: max(ctl.zoom, 15))
    }

    @EnvironmentObject var location: LocationService
    @EnvironmentObject var docs: DocStore
    @EnvironmentObject var night: NightMode
    @StateObject private var ctl = MappaCtl()
    @ObservedObject private var store = EventoStore.shared
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var nav = NavStore.shared
    @ObservedObject private var volume = VolumeTasti.shared
    @ObservedObject private var traccia = Traccia.shared
    @ObservedObject private var percorsoPiedi = PercorsoPiedi.shared
    @ObservedObject private var piani = PianiStore.shared
    @State private var selezione: SelezioneMappa?
    /// colonna dei pulsanti a scomparsa (orizzontale con l'isola): esce con uno swipe da sinistra
    @State private var barraVisibile = false
    @State private var timerBarra: Task<Void, Never>?
    @State private var pannello: PannelloMappa?
    @State private var misura: [CLLocationCoordinate2D] = []
    @State private var nuovoPunto: CoordinataScelta?
    @State private var avviso: String?
    @State private var indiceVolume = -1
    @State private var scelta: [Candidato] = []
    @State private var vaiCoordinate = false
    @State private var sosConferma = false
    @State private var proiezione = false
    @State private var attrezzo: Attrezzo?
    @State private var puntoScelta: CGPoint = .zero
    /// croce di mira (tenendo premuto): dove cade il punto, 70 pt sopra il dito
    @State private var mira: CGPoint?
    @State private var sosConto: Int?
    @State private var modo: ModoStrumento?
    /// eliminazione di un punto: due conferme
    @State private var daEliminare: JPunto?
    @State private var secondaConferma = false
    @State private var vertici: [CLLocationCoordinate2D] = []
    @State private var cerchiCentro: CLLocationCoordinate2D?
    @State private var cerchiRaggi: [Double] = [100, 250, 500]
    @State private var profiloA: CLLocationCoordinate2D?
    @State private var lineaVista: [(CLLocationCoordinate2D, Bool)] = []
    @State private var carta: UIImage?
    @State private var cartaTrasparenza = 0.55
    @ObservedObject private var rotta = RottaAttiva.shared
    @ObservedObject private var livelli = Livelli.shared
    @ObservedObject private var lora = LoRaMesh.shared
    @ObservedObject private var importate = MappeImportate.shared
    @ObservedObject private var telecamere = TelecamerePubbliche.shared
    @ObservedObject private var droni = DroniRemoteID.shared
    @AppStorage("mappa.radar") private var radar = false
    @AppStorage("mappa.rilievo") private var rilievo = true
    @State private var replayT: Double = 0
    @State private var replayTracce: [TracciaStorica] = []
    @State private var raggiVista: [[(CLLocationCoordinate2D, Bool)]] = []
    @State private var muroVideo = false
    @State private var sms: String?
    @AppStorage("mappa.griglia") private var griglia = true
    @AppStorage("mappa.aree") private var mostraAree = true
    @AppStorage("mappa.squadra") private var mostraSquadra = true
    /// zona di mappa visibile (fuori da colonna e pannello): la Ruota ci deve stare dentro
    @State private var vistaMappa: CGRect = .zero

    var punti: [JPunto] {
        if Anteprima.mappaAttiva { return Anteprima.puntiMappa }
        let v = store.vistaSquadra
        return (store.corrente?.punti ?? []).filter { v == nil || ($0.squadra ?? "").isEmpty || $0.squadra == v }
    }
    var compagni: [JCompagno] {
        if Anteprima.mappaAttiva { return mostraSquadra ? Anteprima.compagniMappa : [] }
        let v = store.vistaSquadra
        return mostraSquadra ? store.squadra.filter { $0.id != jsoc.utente?.id && (v == nil || $0.squadra == v) } : []
    }

    var body: some View {
        let _ = GuidaApp.segna("mappa")
        GeometryReader { g in
            let land = g.size.width > g.size.height || UIDevice.current.userInterfaceIdiom == .pad
            let ins = margini
            // con l'isola dinamica: accanto all'isola solo le informazioni, i pulsanti escono con uno swipe dal bordo.
            // L'iPad non ha l'isola: gli do una colonna uguale, così ha la stessa mappa nuova del telefono
            // iPad: barra degli strumenti fissa a sinistra (anche in verticale), barra di stato sempre in alto,
            // niente colonna informazioni né scorrimento: lo schermo è grande
            let pad = UIDevice.current.userInterfaceIdiom == .pad
            // su iPadOS 26 il margine sinistro può essere quello dei comandi della finestra: non è un'isola
            let veraIsola = ins.left >= 30 && !pad
            let colonna: CGFloat = veraIsola ? ins.left : 0
            let isola = land && veraIsola
            // tavole 10-12: colonna sempre visibile = informazioni accanto all'isola + 62 pt di pulsanti
            let lBarra: CGFloat = land ? (isola ? colonna + 62 : 66 + colonna) : 0
            let lPannello: CGFloat = pannello == nil ? 0 : (land ? min(360, (g.size.width - ins.left - ins.right) * 0.42) : 0)
            let hStato: CGFloat = isola ? 0 : 30 + (land && !pad ? 0 : ins.top)
            let hPannelloV: CGFloat = (!land && pannello != nil) ? g.size.height * 0.46 : 0
            let hBarraV: CGFloat = land ? 0 : 60 + ins.bottom
            // zona di mappa davvero visibile (fuori da barre e pannelli)
            let vista = CGRect(x: lBarra + lPannello, y: hStato,
                               width: g.size.width - lBarra - lPannello,
                               height: g.size.height - hStato - hPannelloV - hBarraV)
            ZStack(alignment: .topLeading) {
                mappaSotto

                if isola {
                    interfacciaTela(g.size, ins, colonna: colonna, lPannello: lPannello)
                } else if land {
                    HStack(spacing: 0) {
                        ZStack(alignment: .leading) {
                            if isola { InfoIsola(spazioIsola: veraIsola).frame(width: colonna) }
                            if !isola || barraVisibile {
                                BarraStrumenti(verticale: true, attivo: pannello, notte: night.on, impostazioni: isola || pad, azione: barra)
                                    .padding(.leading, colonna).padding(.bottom, ins.bottom * 0.6)
                                    .transition(.move(edge: .leading).combined(with: .opacity))
                            }
                        }
                        .frame(width: lBarra, alignment: .leading)
                        .clipped()
                        .background(Color.black)
                        .overlay(alignment: .topTrailing) {
                            // angoli "al contrario": è la mappa ad avere gli angoli arrotondati verso la colonna nera
                            AngoloInverso(alto: true).fill(Color.black).frame(width: 52, height: 52).offset(x: 52).allowsHitTesting(false)
                        }
                        .overlay(alignment: .bottomTrailing) {
                            AngoloInverso(alto: false).fill(Color.black).frame(width: 52, height: 52).offset(x: 52).allowsHitTesting(false)
                        }
                        .overlay(alignment: .trailing) {
                            // maniglia: ricorda che da qui escono i pulsanti
                            if isola && !barraVisibile {
                                Capsule().fill(oliva.opacity(0.7)).frame(width: 4, height: 44).padding(.trailing, 3)
                                    .allowsHitTesting(false)
                            }
                        }
                        .contentShape(Rectangle())
                        .simultaneousGesture(DragGesture(minimumDistance: 14).onEnded { v in
                            guard isola else { return }
                            if v.translation.width > 28, !barraVisibile {
                                haptic(); withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { barraVisibile = true }
                                nascondiPresto()
                            } else if v.translation.width < -28, barraVisibile {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { barraVisibile = false }
                            }
                        })
                        VStack(spacing: 0) {
                            if !isola { barraStato.padding(.trailing, max(ins.right * 0.6, 26)).padding(.top, pad ? ins.top : 0) }
                            HStack(spacing: 0) {
                                if let p = pannello {
                                    pannelloVista(p).padding(.bottom, ins.bottom)
                                        .frame(width: lPannello)
                                        .background(vetroPannello)
                                        .transition(.move(edge: .leading).combined(with: .opacity))
                                }
                                if isola || pad {
                                    // lontano dagli angoli arrotondati dello schermo
                                    comandiOrizzontali(EdgeInsets(top: 0, leading: 0, bottom: max(ins.bottom, 10) + 6, trailing: 22))
                                } else {
                                    comandiMappa(EdgeInsets(top: 0, leading: 0, bottom: max(ins.bottom, 10), trailing: 10))
                                }
                            }
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        barraStato.padding(.top, ins.top)
                        comandiMappa(EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 10))
                        if let p = pannello {
                            pannelloVista(p).frame(height: hPannelloV)
                                .background(vetroPannello)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        BarraStrumenti(verticale: false, attivo: pannello, notte: night.on, azione: barra)
                            .frame(height: 60)
                            .padding(.bottom, ins.bottom)
                            .background(vetro)
                    }
                }

                livelloAlto(vista)
            }
            .onAppear { ctl.margini(vista, g.size); vistaMappa = vista }
            .onChange(of: vista) { ctl.margini($0, g.size); vistaMappa = $0 }
        }
        .ignoresSafeArea()
        .background(Color.black)        .ignoresSafeArea()
        .background(Color.black)
        .animation(.spring(response: 0.35, dampingFraction: 0.88), value: pannello)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            ruotaSchermo(.landscape)
            aggiornaSegni()
            aggiornaDisegni()
            applicaLivelli()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { centraInSospeso() }
            if Anteprima.mappaAttiva {
                // anteprime sul simulatore: stessa inquadratura delle tavole 10-12 (e Ruota aperta su OBJ 03)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { ctl.vai(Anteprima.centroMappa, zoom: Anteprima.zoomMappa) }
                if Anteprima.ruotaAperta { DispatchQueue.main.asyncAfter(deadline: .now() + 4) { selezione = .punto(3) } }
            }
            volume.azione = { tastoVolume($0) }
            volume.sos = { avviaSOS() }
            volume.avvia()
            if UserDefaults.standard.bool(forKey: "mappa.nuovoPunto") {
                UserDefaults.standard.set(false, forKey: "mappa.nuovoPunto")
                let c = location.location?.coordinate ?? ctl.centro
                pannello = .nuovoPunto(c.latitude, c.longitude)
            }
            if nav.target != nil { pannello = .naviga }
            if ctl.zoom < 8, let c = location.location?.coordinate { ctl.vai(c, zoom: 15) }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            volume.ferma()
        }
        .onChange(of: nav.target) { t in
            aggiornaSegni()
            if t != nil { pannello = .naviga; inquadraNavigazione() } else if pannello == .naviga { pannello = nil }
        }
        .onReceive(location.$location) { l in
            guard let l else { return }
            traccia.aggiungi(l)
            if let m = rotta.controlla(l.coordinate) { mostra(m); UINotificationFeedbackGenerator().notificationOccurred(.success) }
            controllaRecinti()
        }
        .onReceive(lora.$nodi) { _ in DispatchQueue.main.async { aggiornaSegni() } }
        .onReceive(telecamere.$elenco) { _ in DispatchQueue.main.async { aggiornaSegni() } }
        .onReceive(droni.$droni) { _ in DispatchQueue.main.async { aggiornaSegni() } }
        .onChange(of: telecamere.accese) { _ in aggiornaSegni() }
        .onChange(of: rilievo) { _ in applicaLivelli() }
        .onChange(of: radar) { _ in applicaLivelli() }
        .task(id: store.idCorrente) { await piani.carica(store.idCorrente) }
        .task {
            // telecamere della zona visibile (ogni 5 s se si è spostata la mappa)
            while !Task.isCancelled {
                await telecamere.aggiorna(ctl.zonaVisibile)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        .fullScreenCover(isPresented: $muroVideo) { MuroVideo { muroVideo = false } }
        .sheet(isPresented: Binding(get: { sms != nil }, set: { if !$0 { sms = nil } })) {
            ComponiSMS(testo: sms ?? "") { sms = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .loraMessaggio)) { n in
            if let t = n.userInfo?["testo"] as? String { mostra("📡 " + t) }
        }
        // Strumenti › Coordinate › "In mappa": centra sul punto (se la mappa era già aperta)
        .onReceive(NotificationCenter.default.publisher(for: .mappaCentra)) { _ in centraInSospeso() }
        .onReceive(importate.$elenco) { _ in DispatchQueue.main.async { importate.applica(ctl.mappa) } }
        .onChange(of: pannello) { p in
            // chiudendo il pannello dello strumento finisce anche la modalità
            let tieni: Bool
            switch (modo, p) {
            case (.disegno, .disegno?), (.rotta, .rotta?), (.cerchi, .cerchi?), (.vista, .profilo?): tieni = true
            default: tieni = false
            }
            if !tieni && modo != nil {
                if modo == .cerchi, let c = cerchiCentro, !cerchiRaggi.isEmpty {
                    // i cerchi non condivisi restano nei Livelli di questo telefono
                    Livelli.shared.aggiungi(ElementoLivello(id: "l" + UUID().uuidString, tipo: "cerchi", coord: [[c.latitude, c.longitude]],
                                                            testo: "Cerchi", colore: esadecimale(Theme.amber), raggi: cerchiRaggi))
                    cerchiCentro = nil
                }
                modo = nil; vertici = []; lineaVista = []
            }
        }
        .onChange(of: punti) { _ in aggiornaSegni() }
        .onChange(of: firmaDisegni) { _ in aggiornaDisegni() }
        .onChange(of: store.vistaSquadra) { _ in aggiornaSegni(); aggiornaDisegni() }
        .onChange(of: selezione) { _ in aggiornaSegni() }
        .onReceive(store.$squadra) { _ in DispatchQueue.main.async { aggiornaSegni() } }
        .onChange(of: mostraSquadra) { _ in aggiornaSegni() }
        .onChange(of: store.corrente?.id) { _ in
            let c = (punti.map(\.coordinate) + DatiEvento.aree.flatMap(\.coordinates))
            if !c.isEmpty { ctl.inquadra(c) }
        }
        .sheet(item: $nuovoPunto) { s in NuovoPuntoSheet(coordinata: s.c) }
        .confirmationDialog("Eliminare \(daEliminare?.nome ?? "il punto")?",
                            isPresented: Binding(get: { daEliminare != nil && !secondaConferma }, set: { if !$0 && !secondaConferma { daEliminare = nil } }),
                            titleVisibility: .visible) {
            Button("Elimina", role: .destructive) { secondaConferma = true }
            Button("Annulla", role: .cancel) { daEliminare = nil }
        } message: { Text("Il punto sparisce dalla mappa di tutta la squadra.") }
        .alert("Sei sicuro?", isPresented: $secondaConferma) {
            Button("Elimina per tutti", role: .destructive) { eliminaPunto() }
            Button("Annulla", role: .cancel) { daEliminare = nil }
        } message: { Text("\(daEliminare?.nome ?? "Il punto") verrà cancellato definitivamente dall'evento, con le sue note di indagine.") }
        .confirmationDialog("Mandare un SOS alla squadra?", isPresented: $sosConferma, titleVisibility: .visible) {
            Button("Invia SOS con la mia posizione", role: .destructive) { mandaSOS() }
        } message: { Text("Arriva in chat a tutti i membri dell'evento con le tue coordinate.") }
        .sheet(isPresented: $vaiCoordinate) {
            VaiCoordinateSheet { c, n in nav.target = GaraPoint(id: n, lat: c.latitude, lon: c.longitude, kind: .mio, note: "") }
        }
        .sheet(isPresented: $proiezione) {
            ProiezioneSheet(origineScelta: nil) { c, _ in ctl.vai(c); nuovoPunto = CoordinataScelta(c: c) }
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $attrezzo) { a in
            ZStack(alignment: .topTrailing) {
                Group {
                    switch a {
                    case .cifrari: CipherTab()
                    case .raccolta: KitTab()
                    }
                }
                .indietro("Mappa") { attrezzo = nil }
                Button { attrezzo = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 30)).foregroundStyle(.white, Theme.surface2)
                }
                .padding(.trailing, 18).padding(.top, 8)
            }
        }
    }

    /// Margini reali dello schermo (tacca, isola dinamica, barra Home): la mappa ci va sotto, i comandi no.
    var margini: UIEdgeInsets {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.safeAreaInsets ?? .zero
    }

    // MARK: area mappa

    private var vetro: Color { Color(red: 0.02, green: 0.027, blue: 0.016).opacity(0.78) }
    private var vetroPannello: Color { Color(red: 0.035, green: 0.043, blue: 0.027).opacity(0.88) }

    var barraStato: some View {
        BarraStato(ctl: ctl, offlineOk: !ctl.esitoOffline.isEmpty)
            .padding(.leading, 6)
            .background(vetro)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1) }
    }

    /// La mappa a schermo intero, sotto barre e pannelli.
    var mappaSotto: some View {
        ZStack {
            if ctl.stile.apple {
                MappaApple(ctl: ctl, tocco: { p, _ in toccoMappa(p) }, mira: { stato, p in croce(stato, p) })
            } else {
                MappaLibre(ctl: ctl, tocco: { p, _ in toccoMappa(p) }, mira: { stato, p in croce(stato, p) })
            }
            Sovrapposizioni(ctl: ctl, griglia: griglia, aree: [], misura: [],
                            traccia: [], me: location.location?.coordinate, target: nav.target?.coordinate)
                .allowsHitTesting(false)
            Sovrapposizioni2(ctl: ctl, disegni: [], bozza: vertici, tipoBozza: modoTipo,
                             rotta: [], cerchi: nil, raggi: cerchiRaggi, vista: lineaVista,
                             raggiVista: pannello == .vista360 ? raggiVista : [],
                             replay: pannello == .replay ? PannelloReplay.posizioni(replayTracce, replayT) : [])
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    /// Croce di mira: compare tenendo premuto, si sposta col dito (70 pt sopra), al rilascio apre "Nuovo punto".
    func croce(_ stato: UIGestureRecognizer.State, _ p: CGPoint) {
        switch stato {
        case .began:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            selezione = nil; scelta = []
            mira = CGPoint(x: p.x, y: p.y - 70)
        case .changed:
            mira = CGPoint(x: p.x, y: p.y - 70)
        case .ended:
            if let m = mira, let c = ctl.coordinata(m) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                if modo != nil { vertice(c) }
                else if pannello == .misura { misura.append(c) } else { pannello = .nuovoPunto(c.latitude, c.longitude) }
            }
            mira = nil
        default:
            mira = nil
        }
    }

    /// Ruota, scelta tra punti vicini, croce di mira e conto alla rovescia dell'SOS: sopra a tutto.
    func livelloAlto(_ vista: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            if selezione != nil || !scelta.isEmpty {
                // tavola 12: la mappa non si scurisce; un tocco fuori dalla Ruota la chiude
                Color.clear.contentShape(Rectangle()).ignoresSafeArea()
                    .onTapGesture { withAnimation(.spring(response: 0.3)) { selezione = nil; scelta = [] } }
            }
            if let s = selezione, let c = coordSelezione(s) {
                // la Ruota si apre sul punto, alla stessa scala della mappa (si sposta solo se uscirebbe dalla zona visibile)
                let _ = ctl.giro
                let p0 = ctl.punto(c) ?? CGPoint(x: vista.midX, y: vista.midY)
                let m = MenuRadiale.raggio + 4
                let p = CGPoint(x: min(max(p0.x, vista.minX + m), max(vista.minX + m, vista.maxX - m)),
                                y: min(max(p0.y, vista.minY + m), max(vista.minY + m, vista.maxY - m)))
                MenuRadiale(voci: voci(s), centro: titoloMenu(s), colore: coloreMenu(s), posizione: p)
                    .id(s)   // toccando un altro punto il ventaglio riparte
                    .transition(.identity)
            }
            if !scelta.isEmpty { sceltaVicini }
            if let m = mira { CroceMira(punto: m, testo: ctl.coordinata(m).map { coordTesto($0) } ?? "").allowsHitTesting(false) }
            if let n = sosConto { contoSOS(n) }
            if let img = carta {
                AllineaCarta(immagine: img, vista: vista, trasparenza: $cartaTrasparenza, fissa: fissaCarta) { carta = nil }
            }
        }
        .ignoresSafeArea()
    }

    /// La carta allineata diventa una mappa dell'evento (angoli: alto-sx, alto-dx, basso-dx, basso-sx).
    func fissaCarta(_ angoli: [CGPoint]) {
        guard let img = carta else { return }
        let c = angoli.compactMap { ctl.coordinata($0) }
        guard c.count == 4, let jpg = img.ridotta(lato: 3000).jpegData(compressionQuality: 0.82) else { return }
        carta = nil
        mostra("Carico la carta…")
        Task {
            do {
                let m = try await JsocClient.shared.caricaMappa(jpg, tipo: "immagine", nome: "Carta \(Date().formatted(date: .abbreviated, time: .shortened))",
                                                               evento: store.corrente?.id, coord: c.map { [$0.latitude, $0.longitude] })
                importate.accese.insert(m.id)
                importate.opacita[m.id] = cartaTrasparenza
                await importate.carica()
                importate.applica(ctl.mappa)
                mostra("Carta fissata sulla mappa (in Impostazioni la trasparenza)")
            } catch { mostra("Carta non caricata: \(error.localizedDescription)") }
        }
    }

    func contoSOS(_ n: Int) -> some View {
        VStack(spacing: 12) {
            Text("SOS").font(Theme.mono(34, .heavy)).foregroundStyle(.white)
            Text(n > 0 ? "parte tra \(n)…" : "inviato").font(Theme.mono(16, .bold)).foregroundStyle(.white)
            if n > 0 {
                Button { sosConto = nil; haptic() } label: {
                    Text("ANNULLA").font(.system(size: 16, weight: .heavy)).foregroundStyle(.black)
                        .padding(.horizontal, 30).padding(.vertical, 12).background(.white, in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.red.opacity(0.88))
    }

    /// SOS dai tasti volume (su e giù insieme): 3 secondi per annullare.
    func avviaSOS() {
        guard sosConto == nil else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        sosConto = 3
        func passo() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                guard let n = sosConto else { return }
                if n <= 1 {
                    sosConto = 0
                    mandaSOS()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { sosConto = nil }
                } else {
                    sosConto = n - 1
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    passo()
                }
            }
        }
        passo()
    }

    /// Tocco sulla mappa: MapLibre dice quali segnaposti ci sono sotto il dito. Se più d'uno, chiedo quale.
    /// Cambia quando cambia qualcosa da disegnare sulla mappa.
    var firmaDisegni: String {
        let d = store.corrente?.disegni ?? []
        return "\(d.count)-\(d.last?.id ?? 0)-\(misura.count)-\(misura.last?.latitude ?? 0)-\(cerchiCentro?.latitude ?? 0)-\(cerchiCentro?.longitude ?? 0)-\(cerchiRaggi)-\(modo == .cerchi)-\(rotta.tappe.count)-\(rotta.tappe.last?.longitude ?? 0)-\(traccia.punti.count)-\(mostraAree)-\(livelli.versione)-\(DatiEvento.aree.count)-\(piani.versione)-\(percorsoPiedi.versione)"
    }

    func aggiornaDisegni() {
        var el: [ElementoLivello] = []
        if mostraAree {
            let v = store.vistaSquadra
            let dis = (store.corrente?.disegni ?? DatiEvento.disegni).filter { v == nil || ($0.squadra ?? "").isEmpty || $0.squadra == v }
            el = livelli.tutti(dis, aree: DatiEvento.aree).filter { livelli.visibile($0) }
        }
        func cc(_ c: [CLLocationCoordinate2D]) -> [[Double]] { c.map { [$0.latitude, $0.longitude] } }
        if traccia.punti.count >= 2 { el.append(ElementoLivello(id: "t-traccia", tipo: "traccia", coord: cc(traccia.punti), colore: "#FF8C26")) }
        if let pp = percorsoPiedi.nav, pp.punti.count >= 2 { el.append(ElementoLivello(id: "t-percorso", tipo: "traccia", coord: pp.punti, colore: "#73C7DB")) }
        // piano di gara scelto: il percorso con le tappe numerate, per tutta la squadra
        if store.idCorrente > 0, let p = piani.scelto(store.idCorrente), p.tappe.count >= 2 {
            el.append(ElementoLivello(id: "t-piano", tipo: "rotta", coord: p.tappe.map { [$0.lat, $0.lon] }, testo: p.nome, colore: "#4FC3F7"))
        }
        if rotta.tappe.count >= 1 { el.append(ElementoLivello(id: "t-rotta", tipo: "rotta", coord: cc(rotta.tappe), colore: esadecimale(Theme.oliveBright))) }
        if misura.count >= 1 { el.append(ElementoLivello(id: "t-misura", tipo: "misura", coord: cc(misura), colore: esadecimale(Theme.amber), tratteggio: true)) }
        if modo == .cerchi, let c = cerchiCentro {
            el.append(ElementoLivello(id: "t-cerchi", tipo: "cerchi", coord: [[c.latitude, c.longitude]], colore: esadecimale(Theme.amber), raggi: cerchiRaggi))
        }
        ctl.impostaDisegni(el)
    }

    func salvaMisura() {
        guard misura.count >= 2 else { return }
        var tot = 0.0
        for i in 1..<misura.count { tot += Geo.distance(misura[i - 1], misura[i]) }
        Livelli.shared.aggiungi(ElementoLivello(id: "l" + UUID().uuidString, tipo: "misura", coord: misura.map { [$0.latitude, $0.longitude] },
                                                testo: "Misura " + Geo.formatDistance(tot), colore: esadecimale(Theme.amber), tratteggio: true))
        mostra("Misura salvata in Livelli")
    }

    func toccoMappa(_ p: CGPoint) {
        if barraVisibile { withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { barraVisibile = false } }
        if selezione != nil || !scelta.isEmpty { withAnimation(.spring(response: 0.3)) { selezione = nil; scelta = [] }; return }
        if modo != nil, let c = ctl.coordinata(p) { vertice(c); return }
        if let k = ctl.segniSotto(p).first(where: { $0.hasPrefix("w") }), let i = Int(k.dropFirst()), i < telecamere.elenco.count {
            haptic(); pannello = .telecamera(i); return
        }
        let c: [Candidato] = ctl.segniSotto(p).compactMap { k in
            guard let id = Int(k.dropFirst()) else { return nil }
            if k.hasPrefix("c"), let x = compagni.first(where: { $0.id == id }) {
                return Candidato(sel: .compagno(id), c: x.coordinate, nome: x.callsign, colore: Theme.cyan, distanza: 0)
            }
            if let x = punti.first(where: { $0.id == id }) {
                return Candidato(sel: .punto(id), c: x.coordinate, nome: x.nome, colore: SegnapostoPunto(punto: x).colore, distanza: 0)
            }
            return nil
        }
        guard let primo = c.first else { return }
        if c.count == 1 {
            seleziona(primo.sel, primo.c)
        } else {
            haptic()
            puntoScelta = p
            withAnimation(.spring(response: 0.3)) { scelta = Array(c.prefix(6)) }
        }
    }

    var modoTipo: String {
        if case .disegno(let x) = modo { return x }
        return ""
    }

    /// Un tocco (o il rilascio della croce) mentre uno strumento è attivo.
    func vertice(_ c: CLLocationCoordinate2D) {
        haptic()
        switch modo {
        case .disegno(let tipo):
            if tipo == "testo" { vertici = [c] } else { vertici.append(c) }
        case .rotta: rotta.tappe.append(c)
        case .cerchi: cerchiCentro = c
        case .vista: profiloA = c; lineaVista = []
        default: break
        }
    }

    func avviaModo(_ m: ModoStrumento, _ p: PannelloMappa, _ aiuto: String) {
        vertici = []; lineaVista = []
        modo = m
        pannello = p
        mostra(aiuto)
    }

    /// Segnaposti per MapLibre (obiettivi prima nelle collisioni delle etichette).
    func aggiornaSegni() {
        var s: [SegnoMappa] = punti.map { p in
            if p.tipo.hasPrefix("sim-") {
                let parti = p.tipo.split(separator: "-").map(String.init)
                let aff = parti.count > 1 ? parti[1] : "sc", cat = parti.count > 2 ? parti[2] : "?"
                let forma: SegnoMappa.Forma = aff == "am" ? .quadro : (aff == "ne" ? .rombo : (aff == "nu" ? .quadrato : .cerchio))
                return SegnoMappa(chiave: "p\(p.id)", coord: p.coordinate, forma: forma, colore: UIColor(SimboloTattico.colore(aff)), glifo: cat,
                                  etichetta: p.nome, rotazione: nil, priorita: 1, scelto: selezione == .punto(p.id))
            }
            let v = SegnapostoPunto(punto: p)
            let forma: SegnoMappa.Forma = p.obiettivo ? .rombo : (p.tipo == "pericolo" ? .triangolo : .cerchio)
            let glifo = p.obiettivo ? (p.fatto ? "✓" : (v.numero ?? "")) : (p.tipo == "pericolo" ? "!" : v.glifo)
            return SegnoMappa(chiave: "p\(p.id)", coord: p.coordinate, forma: forma, colore: UIColor(v.colore), glifo: glifo,
                              etichetta: p.nome, rotazione: nil, priorita: p.obiettivo ? 0 : 2,
                              scelto: selezione == .punto(p.id) || nav.target?.id == p.nome)
        }
        s += compagni.map { c in
            let vecchio = c.eta > 300
            let dir = vecchio ? nil : (c.dir ?? ((c.vel ?? 0) > 0.5 ? c.rotta : nil))
            return SegnoMappa(chiave: "c\(c.id)", coord: c.coordinate, forma: .freccia,
                              colore: vecchio ? UIColor(white: 0.5, alpha: 1) : UIColor(Theme.cyan), glifo: "",
                              etichetta: vecchio ? "\(c.callsign) · \(Int(c.eta / 60))′" : c.callsign, rotazione: dir,
                              priorita: 1, scelto: selezione == .compagno(c.id))
        }
        if telecamere.accese {
            s += telecamere.elenco.enumerated().map { i, c in
                SegnoMappa(chiave: "w\(i)", coord: c.coordinate, forma: .quadro, colore: UIColor(red: 0.35, green: 0.75, blue: 1, alpha: 1), glifo: "CAM",
                           etichetta: c.nome, rotazione: nil, priorita: 3, scelto: pannello == .telecamera(i))
            }
        }
        s += droni.droni.values.map { d in
            SegnoMappa(chiave: "d\(abs(d.id.hashValue % 100000))", coord: d.coordinate, forma: .triangolo, colore: UIColor(Theme.amber), glifo: "D",
                       etichetta: "DRONE \(d.quota.map { String(format: "%.0f m", $0) } ?? "")", rotazione: nil, priorita: 0, scelto: false)
        }
        s += lora.nodi.values.compactMap { n in
            guard let c = n.coordinate else { return nil }
            return SegnoMappa(chiave: "l\(n.id)", coord: c, forma: .freccia, colore: UIColor(red: 1, green: 0.45, blue: 0.85, alpha: 1),
                              glifo: "", etichetta: "\(n.nome) · LoRa", rotazione: nil, priorita: 1, scelto: false)
        }
        ctl.impostaSegni(s)
    }

    /// Elenco "quale intendi?" quando più punti sono uno sopra l'altro.
    var sceltaVicini: some View {
        GeometryReader { g in
            VStack(alignment: .leading, spacing: 0) {
                Text("QUALE?").font(Theme.mono(9, .heavy)).tracking(1.4).foregroundStyle(Theme.dim).padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)
                ForEach(scelta) { x in
                    Button { scelta = []; seleziona(x.sel, x.c) } label: {
                        HStack(spacing: 8) {
                            Circle().fill(x.colore).frame(width: 10, height: 10)
                            Text(x.nome).font(.system(size: 14, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12).frame(height: 40).contentShape(Rectangle())
                    }
                }
            }
            .frame(width: 210)
            .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.stroke))
            .position(x: min(max(puntoScelta.x + 120, 110), g.size.width - 110),
                      y: min(max(puntoScelta.y, CGFloat(scelta.count) * 20 + 40), g.size.height - CGFloat(scelta.count) * 20 - 40))
        }
        .transition(.opacity)
    }

    // MARK: tavole 10-12 (iPhone in orizzontale)

    /// Colonna a sinistra (informazioni accanto all'isola + pulsanti), velata sopra la mappa, pannello e comandi.
    func interfacciaTela(_ s: CGSize, _ ins: UIEdgeInsets, colonna: CGFloat, lPannello: CGFloat) -> some View {
        let lati = colonna + 62
        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                InfoIsola(spazioIsola: true).frame(width: colonna, height: s.height)
                ColonnaTela(attivo: pannello, notte: night.on, azione: barra)
                    .frame(width: 62, height: s.height)
                    .offset(x: colonna)
            }
            .frame(width: lati, height: s.height, alignment: .topLeading)
            .background(Color(red: 6 / 255, green: 8 / 255, blue: 5 / 255).opacity(0.72))
            .overlay(alignment: .trailing) { Rectangle().fill(Theme.olive.opacity(0.22)).frame(width: 1) }
            if let p = pannello {
                pannelloVista(p).padding(.bottom, ins.bottom)
                    .frame(width: lPannello, height: s.height)
                    .background(vetroPannello)
                    .offset(x: lati)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            comandiTela(s, sinistra: lati + lPannello)
        }
        .frame(width: s.width, height: s.height, alignment: .topLeading)
    }

    /// Comandi sulla mappa come nella tavola 10: strumenti scelti in alto al centro, Nord e 2D/3D in alto a destra,
    /// scala e coordinate in basso al centro, "segui la mia posizione" in basso a destra.
    func comandiTela(_ s: CGSize, sinistra: CGFloat) -> some View {
        let destra = s.width - 39                       // asse dei tasti tondi a destra
        let cx = (sinistra + s.width - 61) / 2          // centro tra la colonna e i tasti a destra
        let libero = ctl.modo == .none
        return ZStack(alignment: .topLeading) {
            if s.width - sinistra - 61 >= 450 {
                BarraRapida(usa: strumento) {
                    pannello = .strumenti
                    mostra("Tieni premuto uno strumento per metterlo in alto")
                }
                .position(x: cx, y: 8 + 19.5)
            }
            if let v = store.vistaSquadra {
                // organizzatore: mappa di una sola squadra
                Button { haptic(); store.vistaSquadra = nil; aggiornaSegni(); aggiornaDisegni() } label: {
                    HStack(spacing: 5) {
                        Text("MAPPA " + v.uppercased()).font(Theme.mono(11, .heavy))
                        Image(systemName: "xmark.circle.fill")
                    }
                    .foregroundStyle(v == "attacco" ? Theme.red : Theme.cyan)
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(Color.black.opacity(0.7), in: Capsule())
                }
                .accessibilityLabel("Torna alla mappa di tutte le squadre")
                .position(x: cx, y: 70)
            }
            if let a = avviso {
                Text(a).font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(olivaChiaro.opacity(0.55)))
                    .frame(maxWidth: max(160, s.width - sinistra - 140))
                    .position(x: cx, y: store.vistaSquadra == nil ? 74 : 108)
                    .transition(.opacity)
            }
            // Nord in alto (ruota con la mappa) e vista 2D/3D
            Button { haptic(); ctl.nordInAlto() } label: {
                IconaTela(d: Ic.mNord, colore: Theme.red, lato: 22)
                    .rotationEffect(.degrees(-ctl.rotazione))
                    .frame(width: 44, height: 44).background(Theme.bg, in: Circle())
            }
            .accessibilityLabel("Nord in alto")
            .position(x: destra, y: 19 + 22)
            Button { haptic(); ctl.cambiaTreD() } label: {
                Text(ctl.tre_d ? "3D" : "2D").font(Theme.mono(13, .heavy)).foregroundStyle(oliva)
                    .frame(width: 34, height: 34).background(Theme.bg, in: Circle())
            }
            .accessibilityLabel("Vista 2D/3D")
            .position(x: destra, y: 72 + 17)
            if let o = ctl.offline {
                ProgressView(value: Double(o.fatti), total: Double(o.totale)) {
                    Text("Scarico la zona: \(o.fatti)/\(o.totale)").font(Theme.mono(10, .bold))
                }
                .tint(oliva).padding(8).frame(width: min(300, s.width - sinistra - 140))
                .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
                .position(x: cx, y: s.height - 72)
            }
            // scala a sinistra del centro, coordinate a destra del centro
            HStack(alignment: .top, spacing: 0) {
                ScalaMappa(metriPerPunto: ctl.metriPerPunto)
                    .padding(.trailing, 14)
                    .frame(width: 220, alignment: .trailing)
                Text(location.location.map { coordTesto($0.coordinate) } ?? "in attesa del GPS")
                    .font(Theme.mono(11, .heavy)).foregroundStyle(Theme.testo)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: 220, alignment: .leading)
            }
            .frame(height: 24, alignment: .top)
            .allowsHitTesting(false)
            .position(x: cx, y: s.height - 36 + 12)
            // segui la mia posizione: libera → segue → segue orientata
            Button {
                haptic(.medium); ctl.cicloModo()
                mostra(ctl.modo == .follow ? "Ti seguo · nord in alto" : (ctl.modo == .followWithHeading ? "Ti seguo · orientata sulla tua direzione" : "Mappa libera"))
            } label: {
                IconaTela(d: Ic.mSegui, colore: libero ? Theme.testo : Theme.scuro, lato: 26,
                          piena: ctl.modo == .followWithHeading ? Theme.scuro : nil)
                    .frame(width: 43, height: 43)
                    .background(libero ? Color.clear : olivaChiaro, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.testo, lineWidth: 2).opacity(libero ? 1 : 0))
            }
            .accessibilityLabel("Segui la mia posizione")
            .position(x: destra + 1.5, y: s.height - 22 - 21.5)
        }
        .frame(width: s.width, height: s.height, alignment: .topLeading)
        .animation(.spring(response: 0.3), value: avviso)
    }

    // MARK: comandi sopra la parte visibile della mappa

    func comandiMappa(_ bordi: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                HStack(alignment: .top) {
                    EmptyView()
                    Spacer()
                    tastoTondo(pannello == .impostazioni ? "gearshape.fill" : "gearshape", pannello == .impostazioni ? Theme.oliveBright : oliva) {
                        pannello = pannello == .impostazioni ? nil : .impostazioni
                    }
                    .accessibilityLabel("Impostazioni e mappe")
                }
                if let a = avviso {
                    Text(a).font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(olivaChiaro.opacity(0.55)))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 8)
            Spacer(minLength: 0)
            if let o = ctl.offline {
                ProgressView(value: Double(o.fatti), total: Double(o.totale)) {
                    Text("Scarico la zona: \(o.fatti)/\(o.totale)").font(Theme.mono(10, .bold))
                }
                .tint(oliva).padding(8).frame(maxWidth: 320)
                .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
            }
            HStack(alignment: .bottom, spacing: 8) {
                ScalaMappa(metriPerPunto: ctl.metriPerPunto).padding(.leading, 12)
                Spacer()
                tastoTondo("location.north.fill", Theme.red, rotazione: -ctl.rotazione) { ctl.nordInAlto() }
                    .accessibilityLabel("Nord in alto")
                Button { haptic(); ctl.cambiaTreD() } label: {
                    Text(ctl.tre_d ? "2D" : "3D").font(Theme.mono(13, .heavy)).foregroundStyle(oliva)
                        .frame(width: 46, height: 46).background(Color.black.opacity(0.72), in: Circle())
                        .overlay(Circle().strokeBorder(Theme.stroke))
                }
                Button {
                    haptic(.medium); ctl.cicloModo()
                    mostra(ctl.modo == .follow ? "Ti seguo · nord in alto" : (ctl.modo == .followWithHeading ? "Ti seguo · orientata sulla tua direzione" : "Mappa libera"))
                } label: {
                    Image(systemName: ctl.modo == .followWithHeading ? "location.north.line.fill" : (ctl.modo == .follow ? "location.fill" : "location"))
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(.black).frame(width: 56, height: 56)
                        .background(ctl.modo == .none ? oliva : olivaChiaro, in: Circle())
                        .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                }
                .accessibilityLabel("Segui la mia posizione")
            }
            .padding(.bottom, bordi.bottom)
        }
        .padding(.trailing, bordi.trailing)
        .animation(.spring(response: 0.3), value: avviso)
    }

    /// Orizzontale: strumenti a scelta in alto, Nord e 3D in alto a destra, coordinate accanto alla scala, posizione in basso a destra.
    func comandiOrizzontali(_ bordi: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                if let v = store.vistaSquadra {
                    // organizzatore: mappa di una sola squadra
                    Button { haptic(); store.vistaSquadra = nil; aggiornaSegni(); aggiornaDisegni() } label: {
                        HStack(spacing: 5) {
                            Text("MAPPA " + v.uppercased()).font(Theme.mono(11, .heavy))
                            Image(systemName: "xmark.circle.fill")
                        }
                        .foregroundStyle(v == "attacco" ? Theme.red : Theme.cyan)
                        .padding(.horizontal, 10).frame(height: 32)
                        .background(Color.black.opacity(0.7), in: Capsule())
                    }
                    .accessibilityLabel("Torna alla mappa di tutte le squadre")
                }
                EmptyView()
                Spacer(minLength: 0)
                BarraRapida(usa: strumento) {
                    pannello = .strumenti
                    mostra("Tieni premuto uno strumento per metterlo in alto")
                }
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    tastoTondo("location.north.fill", Theme.red, rotazione: -ctl.rotazione) { ctl.nordInAlto() }
                        .accessibilityLabel("Nord in alto")
                    Button { haptic(); ctl.cambiaTreD() } label: {
                        Text(ctl.tre_d ? "2D" : "3D").font(Theme.mono(13, .heavy)).foregroundStyle(oliva)
                            .frame(width: 46, height: 46).background(Color.black.opacity(0.72), in: Circle())
                            .overlay(Circle().strokeBorder(Theme.stroke))
                    }
                }
            }
            .padding(.top, 8)
            .overlay(alignment: .bottom) {
                if let a = avviso {
                    Text(a).font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(olivaChiaro.opacity(0.55)))
                        .offset(y: 44)
                        .transition(.opacity)
                }
            }
            .padding(.top, 6)
            Spacer(minLength: 0)
            if let o = ctl.offline {
                ProgressView(value: Double(o.fatti), total: Double(o.totale)) {
                    Text("Scarico la zona: \(o.fatti)/\(o.totale)").font(Theme.mono(10, .bold))
                }
                .tint(oliva).padding(8).frame(maxWidth: 320)
                .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
            }
            HStack(alignment: .bottom, spacing: 14) {
                ScalaMappa(metriPerPunto: ctl.metriPerPunto)
                Text(location.location.map { coordTesto($0.coordinate) } ?? "in attesa del GPS")
                    .font(Theme.mono(11.5, .heavy)).foregroundStyle(.white)
                    .shadow(color: .black, radius: 2).lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Button {
                    haptic(.medium); ctl.cicloModo()
                    mostra(ctl.modo == .follow ? "Ti seguo · nord in alto" : (ctl.modo == .followWithHeading ? "Ti seguo · orientata sulla tua direzione" : "Mappa libera"))
                } label: {
                    Image(systemName: ctl.modo == .followWithHeading ? "location.north.line.fill" : (ctl.modo == .follow ? "location.fill" : "location"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(ctl.modo == .none ? Color.white : Color.black)
                        .frame(width: 50, height: 50)
                        .background(ctl.modo == .none ? Color.black.opacity(0.55) : olivaChiaro, in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(ctl.modo == .none ? 0.95 : 0), lineWidth: 2))
                        .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
                }
                .accessibilityLabel("Segui la mia posizione")
            }
            .padding(.leading, 12)
            .padding(.bottom, bordi.bottom)
        }
        .padding(.trailing, bordi.trailing)
        .animation(.spring(response: 0.3), value: avviso)
    }

    func tastoTondo(_ icona: String, _ colore: Color, rotazione: Double = 0, _ f: @escaping () -> Void) -> some View {
        Button { haptic(); f() } label: {
            Image(systemName: icona).font(.system(size: 18, weight: .bold)).foregroundStyle(colore)
                .rotationEffect(.degrees(rotazione))
                .frame(width: 46, height: 46).background(Color.black.opacity(0.72), in: Circle())
                .overlay(Circle().strokeBorder(Theme.stroke))
        }
    }

    func tastoBordo(_ icona: String, _ testo: String, _ colore: Color, _ f: @escaping () -> Void) -> some View {
        Button { haptic(); f() } label: {
            VStack(spacing: 2) {
                Image(systemName: icona).font(.system(size: 17, weight: .bold)).foregroundStyle(colore)
                Text(testo).font(.system(size: 8.5, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 48, height: 44)
        }
    }

    // MARK: selezione e menu circolare

    func seleziona(_ s: SelezioneMappa, _ c: CLLocationCoordinate2D) {
        haptic(.medium)
        // la mappa resta dov'è (tavola 12): si sposta solo se la Ruota non ci starebbe intorno al punto
        let m = MenuRadiale.raggio + 4
        if let p = ctl.punto(c), vistaMappa.width > 2 * m, !vistaMappa.insetBy(dx: m, dy: min(m, vistaMappa.height / 2 - 1)).contains(p) {
            ctl.vai(c, zoom: ctl.zoom)
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { selezione = s }
    }

    func coordSelezione(_ s: SelezioneMappa) -> CLLocationCoordinate2D? {
        switch s {
        case .punto(let id): return punti.first { $0.id == id }?.coordinate
        case .compagno(let id): return (compagni.first { $0.id == id } ?? store.squadra.first { $0.id == id })?.coordinate
        }
    }

    func titoloMenu(_ s: SelezioneMappa) -> String {
        switch s {
        case .punto(let id): return punti.first { $0.id == id }.map { numeroObj($0) ?? String($0.nome.prefix(3)) } ?? "?"
        case .compagno(let id): return (compagni.first { $0.id == id } ?? store.squadra.first { $0.id == id })?.callsign ?? "?"
        }
    }

    func coloreMenu(_ s: SelezioneMappa) -> Color {
        switch s {
        case .compagno: return Theme.cyan
        case .punto(let id): return punti.first { $0.id == id }.map { SegnapostoPunto(punto: $0).colore } ?? Theme.red
        }
    }

    /// Spicchi della Ruota (tavola 12), in senso orario da ore 12.
    func voci(_ s: SelezioneMappa) -> [VoceRadiale] {
        switch s {
        case .punto(let id):
            guard let p = punti.first(where: { $0.id == id }) else { return [] }
            let gp = GaraPoint(id: p.nome, lat: p.lat, lon: p.lon, kind: DatiEvento.kind(p.tipo), note: p.note ?? "")
            return [
                VoceRadiale(icona: Ic.mNaviga, testo: "Naviga", colore: oliva) { nav.target = gp; selezione = nil },
                VoceRadiale(icona: Ic.mResoconto, testo: "Resoconto", colore: oliva) { apri(.resoconto(id)) },
                VoceRadiale(icona: Ic.mVideo, testo: "Video", colore: Theme.cyan) { apri(.video(nil)) },
                VoceRadiale(icona: Ic.mMessaggi, testo: "Chat", colore: oliva) {
                    Task { try? await store.scrivi("📍 \(p.nome) · \(Geo.mgrs(p.coordinate))", jsoc, posizione: p.coordinate) }
                    apri(.chat(nil))
                },
                VoceRadiale(icona: Ic.mCondividi, testo: "Condividi", colore: oliva) { selezione = nil; condividiPunto(nome: p.nome, p.coordinate) },
                VoceRadiale(icona: Ic.mElimina, testo: "Elimina", colore: Theme.red, rosso: true) {
                    selezione = nil
                    daEliminare = p
                },
            ]
        case .compagno(let id):
            guard let c = compagni.first(where: { $0.id == id }) ?? store.squadra.first(where: { $0.id == id }) else { return [] }
            return [
                VoceRadiale(icona: Ic.mNaviga, testo: "Naviga", colore: oliva) {
                    nav.target = GaraPoint(id: c.callsign, lat: c.lat, lon: c.lon, kind: .recon, note: "Posizione di \(c.callsign)")
                    selezione = nil
                },
                VoceRadiale(icona: Ic.mInfo, testo: "Info", colore: oliva) { apri(.info(id)) },
                VoceRadiale(icona: Ic.mVideo, testo: "Video", colore: Theme.cyan) { apri(.video(c.callsign)) },
                VoceRadiale(icona: Ic.mMessaggi, testo: "Chat", colore: oliva) { apri(.chat(id)) },
                VoceRadiale(icona: Ic.mMisura, testo: "Misura", colore: oliva) {
                    misura = [location.location?.coordinate, c.coordinate].compactMap { $0 }; apri(.misura)
                },
                VoceRadiale(icona: Ic.mCentra, testo: "Centra", colore: oliva) { ctl.vai(c.coordinate); selezione = nil },
            ]
        }
    }

    func apri(_ p: PannelloMappa) {
        haptic()
        selezione = nil
        pannello = p
    }

    func numeroObj(_ p: JPunto) -> String? {
        guard p.obiettivo, let r = p.nome.range(of: #"\d+"#, options: .regularExpression) else { return nil }
        return String(p.nome[r])
    }

    func allegati(_ p: JPunto) -> [DocItem] {
        let chiave = (p.cartella?.isEmpty == false ? p.cartella! : p.nome).lowercased()
        let n = numeroObj(p)
        return docs.items.filter { d in
            let f = d.fascicolo.lowercased()
            return f.contains(chiave) || (n != nil && (f.hasPrefix("obj \(n!) ") || f.hasPrefix("obj \(n!)-") || f == "obj \(n!)"))
        }
    }

    // MARK: barra strumenti

    /// La colonna dei pulsanti si richiude da sola dopo qualche secondo senza tocchi.
    func nascondiPresto() {
        timerBarra?.cancel()
        timerBarra = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { barraVisibile = false }
        }
    }

    func barra(_ v: BarraStrumenti.Voce) {
        haptic()
        if barraVisibile { nascondiPresto() }
        switch v {
        case .esci: vaiAllaScheda(SchedaPrecedente.valore)
        case .impostazioni: pannello = pannello == .impostazioni ? nil : .impostazioni
        case .notte: withAnimation(.easeInOut(duration: 0.25)) { night.toggle() }
        case .punto: pannello = .nuovoPunto(ctl.centro.latitude, ctl.centro.longitude)
        case .misura:
            if pannello == .misura { salvaMisura(); pannello = nil; misura = [] } else { misura = []; pannello = .misura; mostra("Tieni premuto sulla mappa per aggiungere i punti") }
        case .squadra: pannello = pannello == .squadra ? nil : .squadra
        case .traccia:
            traccia.attiva.toggle()
            if traccia.attiva {
                mostra("Registrazione traccia avviata")
            } else {
                let t = traccia.testo
                ArchivioTracce.shared.aggiungi(traccia.punti)
                traccia.azzera()
                mostra("Traccia salvata nell'archivio personale · \(t)")
            }
        case .video:
            if case .video = pannello { pannello = nil } else { pannello = .video(nil) }
        case .livelli: pannello = pannello == .livelli ? nil : .livelli
        case .strumenti: pannello = pannello == .strumenti ? nil : .strumenti
        case .segnala: pannello = pannello == .segnala ? nil : .segnala
        case .messaggi:
            if case .chat = pannello { pannello = nil } else { pannello = .chat(nil) }
        case .sos: sosConferma = true
        }
    }

    /// rilievo e radar: li rimette anche dopo un cambio di stile
    func applicaLivelli() {
        ctl.voleRilievo = rilievo
        Task {
            ctl.voleRadar = radar ? await MeteoServizio.radar() : nil
            ctl.livelliExtra(rilievo: rilievo, radar: ctl.voleRadar)
        }
    }

    func controllaRecinti() {
        for a in Recinti.shared.controlla(io: location.location?.coordinate, ioNome: jsoc.utente?.callsign ?? "io", compagni: compagni) {
            mostra("⚠️ " + a)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            let n = UNMutableNotificationContent()
            n.title = "Recinto"; n.body = a; n.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: n, trigger: nil))
        }
    }

    func eliminaPunto() {
        guard let p = daEliminare else { return }
        daEliminare = nil
        Task {
            do {
                try await jsoc.cancellaPunto(p.id)
                await store.aggiorna(jsoc)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                mostra("\(p.nome) eliminato")
            } catch { mostra("Non eliminato: \(error.localizedDescription)") }
        }
    }

    func mandaSOS() {
        let c = location.location?.coordinate
        Task {
            do {
                try await store.scrivi("🆘 SOS da \(jsoc.utente?.callsign ?? "?")" + (c.map { " · " + Geo.mgrs($0) } ?? " · posizione non disponibile"), jsoc, posizione: c)
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                mostra("SOS inviato alla squadra")
            } catch { mostra("SOS NON inviato: \(error.localizedDescription)") }
        }
    }

    // MARK: strumenti del catalogo

    func strumento(_ s: Strumento) {
        switch s {
        case .vaiPunto: pannello = .coordinate
        case .seguiCompagno: pannello = .squadra
        case .traccia: barra(.traccia)
        case .distanza: pannello = nil; barra(.misura)
        case .proietta: proiezione = true
        case .punto: pannello = .nuovoPunto(ctl.centro.latitude, ctl.centro.longitude)
        case .chat: pannello = .chat(nil)
        case .video: pannello = .video(nil)
        case .sos: sosConferma = true
        case .segnala: pannello = .segnala
        case .triangolazione, .cifrari, .morse, .mirino: attrezzo = .cifrari
        case .qr: attrezzo = .raccolta
        case .offline, .importa, .immagine: pannello = .impostazioni
        case .griglia: griglia.toggle(); mostra(griglia ? "Griglia MGRS accesa" : "Griglia MGRS spenta")
        case .rotta: avviaModo(.rotta, .rotta, "Tocca la mappa per aggiungere le tappe")
        case .cerchi:
            cerchiCentro = location.location?.coordinate ?? ctl.centro
            avviaModo(.cerchi, .cerchi, "Tocca la mappa per spostare il centro")
        case .vista, .profilo:
            profiloA = nil
            avviaModo(.vista, .profilo, "Tocca il punto da guardare")
        case .linea, .area, .freccia, .recinto: avviaModo(.disegno(s.rawValue), .disegno(s.rawValue), "Tocca la mappa per aggiungere i punti")
        case .testo: avviaModo(.disegno("testo"), .disegno("testo"), "Tocca dove scrivere")
        case .simboli: pannello = .simboli
        case .noveRighe: pannello = .noveRighe
        case .salute: pannello = .salute
        case .pacchetti: pannello = .pacchetti
        case .lora: pannello = .lora
        case .meteo: pannello = .meteo
        case .cerca: pannello = .cerca
        case .rilievo: rilievo.toggle(); mostra(rilievo ? "Ombreggiatura del rilievo accesa" : "Ombreggiatura spenta")
        case .telecamere:
            telecamere.accese.toggle()
            mostra(telecamere.accese ? "Telecamere pubbliche accese: avvicinati a una zona" : "Telecamere spente")
        case .replay: pannello = .replay
        case .cronologia: pannello = .cronologia
        case .muroVideo: muroVideo = true
        case .vista360: raggiVista = []; pannello = .vista360
        case .medico: pannello = .medico
        case .balistica: pannello = .balistica
        case .droni: pannello = .droni
        case .livelli: pannello = .livelli
        case .sms:
            if MFMessageComposeViewController.canSendText(), let c = location.location?.coordinate {
                sms = "JSOC \(jsoc.utente?.callsign ?? "") \(Geo.mgrs(c)) \(Date().formatted(date: .omitted, time: .shortened)) https://maps.apple.com/?ll=\(c.latitude),\(c.longitude)"
            } else { mostra("SMS non disponibile o posizione assente") }
        case .stampa:
            mostra("Preparo il PDF…")
            Task {
                if let f = await StampaMappa.pdf(ctl: ctl, titolo: store.corrente?.nome ?? "Mappa", punti: punti) { condividi([f]) }
                else { mostra("Stampa non riuscita") }
            }
        }
    }

    // MARK: tasti volume

    func tastoVolume(_ verso: Int) {
        switch volume.funzione {
        case .stile:
            let t = StileMappa.allCases
            let i = (t.firstIndex(of: ctl.stile)! + verso + t.count) % t.count
            ctl.stile = t[i]
            mostra("Mappa: \(t[i].nome)")
        case .punti:
            let lista: [(SelezioneMappa, CLLocationCoordinate2D, String)] =
                punti.sorted { ($0.obiettivo ? 0 : 1, $0.nome) < ($1.obiettivo ? 0 : 1, $1.nome) }.map { (.punto($0.id), $0.coordinate, $0.nome) }
                + compagni.map { (.compagno($0.id), $0.coordinate, $0.callsign) }
            guard !lista.isEmpty else { mostra("Nessun punto nell'evento"); return }
            indiceVolume = (indiceVolume + verso + lista.count) % lista.count
            let x = lista[indiceVolume]
            seleziona(x.0, x.1)
            mostra("\(x.2) · \(indiceVolume + 1) di \(lista.count)")
        case .spenti: break
        }
    }

    func mostra(_ s: String) {
        avviso = s
        let questo = s
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { if avviso == questo { avviso = nil } }
    }

    func inquadraNavigazione() {
        guard let t = nav.target else { return }
        ctl.inquadra([location.location?.coordinate, t.coordinate].compactMap { $0 })
    }

    // MARK: pannelli

    @ViewBuilder
    func pannelloVista(_ p: PannelloMappa) -> some View {
        let chiudi = { pannello = nil }
        Group {
            switch p {
            case .resoconto(let id):
                if let x = punti.first(where: { $0.id == id }) {
                    // Fatto, Più vicini e Misura erano spicchi della vecchia Ruota: ora stanno nel resoconto
                    PannelloResoconto(punto: x, allegati: allegati(x), chiudi: chiudi,
                                      vicini: { pannello = .piuVicini(id) },
                                      misura: { misura = [location.location?.coordinate, x.coordinate].compactMap { $0 }; pannello = .misura })
                } else { PannelloVuoto(titolo: "Punto non trovato", chiudi: chiudi) }
            case .video(let nome): PannelloVideo(scelto: nome, chiudi: chiudi)
            case .naviga:
                if let t = nav.target {
                    NavPanel(target: t, landscape: true, onEdit: {}, onChange: { pannello = .squadra })
                } else { PannelloVuoto(titolo: "Nessuna navigazione", chiudi: chiudi) }
            case .squadra: PannelloSquadra(chiudi: chiudi) { c in pannello = nil; seleziona(.compagno(c.id), c.coordinate) }
            case .chat(let dest): PannelloChat(dest: dest, chiudi: chiudi).id(dest ?? -1)
            case .livelli: PannelloLivelli(ctl: ctl, griglia: $griglia, aree: $mostraAree, squadra: $mostraSquadra, chiudi: chiudi) {
                ctl.scaricaZona(punti.map(\.coordinate) + DatiEvento.aree.flatMap(\.coordinates) + [location.location?.coordinate].compactMap { $0 })
            }
            case .misura: PannelloMisura(punti: $misura, chiudi: { salvaMisura(); misura = []; chiudi() })
            case .info(let id): PannelloInfo(compagno: store.squadra.first { $0.id == id }, chiudi: chiudi)
            case .impostazioni: PannelloImpostazioni(ctl: ctl, griglia: $griglia, aree: $mostraAree, squadra: $mostraSquadra, chiudi: chiudi,
                                                     allinea: { img in carta = img; pannello = nil }) {
                ctl.scaricaZona(punti.map(\.coordinate) + DatiEvento.aree.flatMap(\.coordinates) + [location.location?.coordinate].compactMap { $0 })
            }
            case .strumenti: PannelloStrumenti(chiudi: chiudi, azione: strumento)
            case .nuovoPunto(let la, let lo): PannelloNuovoPunto(coordinata: CLLocationCoordinate2D(latitude: la, longitude: lo), chiudi: chiudi)
            case .segnala: PannelloSegnala(centroMappa: ctl.centro, chiudi: chiudi) { mostra($0) }
            case .disegno(let tipo): PannelloDisegno(tipo: tipo, vertici: $vertici, chiudi: chiudi) { mostra($0) }
            case .rotta: PannelloRotta(chiudi: chiudi) { mostra($0) }
            case .cerchi: PannelloCerchi(centro: $cerchiCentro, raggi: $cerchiRaggi, mio: location.location?.coordinate, centroMappa: ctl.centro, chiudi: chiudi) { mostra($0) }
            case .profilo: PannelloProfilo(da: location.location?.coordinate, a: profiloA, visibile: $lineaVista, chiudi: chiudi)
            case .simboli: PannelloSimboli(dove: ctl.centro, chiudi: chiudi) { mostra($0) }
            case .noveRighe: PannelloModulo(tipo: .noveRighe, dove: location.location?.coordinate, chiudi: chiudi) { mostra($0) }
            case .salute: PannelloModulo(tipo: .salute, dove: ctl.centro, chiudi: chiudi) { mostra($0) }
            case .pacchetti: PannelloPacchetti(chiudi: chiudi) { mostra($0) }
            case .lora: PannelloLoRa(chiudi: chiudi)
            case .meteo: PannelloMeteo(dove: ctl.centro, radar: $radar, chiudi: chiudi)
            case .cerca: PannelloCerca(vicino: location.location?.coordinate ?? ctl.centro, chiudi: chiudi) { c, n in
                ctl.vai(c, zoom: 15); mostra(n)
            }
            case .telecamera(let i):
                if i < telecamere.elenco.count { PannelloTelecamera(cam: telecamere.elenco[i], chiudi: chiudi) } else { PannelloVuoto(titolo: "Telecamera", chiudi: chiudi) }
            case .replay: PannelloReplay(istante: $replayT, tracce: $replayTracce, chiudi: chiudi)
            case .cronologia: PannelloCronologia(chiudi: chiudi) { ctl.vai($0) }
            case .vista360: PannelloVista360(da: ctl.centro, raggi: $raggiVista, chiudi: chiudi)
            case .piuVicini(let id):
                if let x = punti.first(where: { $0.id == id }) { PannelloPiuVicini(punto: x, chiudi: chiudi) { pannello = .chat($0) } }
                else { PannelloVuoto(titolo: "Punto non trovato", chiudi: chiudi) }
            case .medico: PannelloMedico(chiudi: chiudi)
            case .balistica: PannelloBalistica(chiudi: chiudi)
            case .droni: PannelloDroni(chiudi: chiudi) { ctl.vai($0) }
            case .coordinate: PannelloCoordinate(iniziale: location.location?.coordinate ?? ctl.centro, chiudi: chiudi) { c, crea in
                ctl.vai(c)
                if crea { pannello = .nuovoPunto(c.latitude, c.longitude) }
                else { nav.target = GaraPoint(id: "COORDINATE", lat: c.latitude, lon: c.longitude, kind: .mio, note: "") }
            }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(fondoPannello)
        .overlay(alignment: .trailing) { Rectangle().fill(oliva.opacity(0.3)).frame(width: 1) }
    }
}

struct CoordinataScelta: Identifiable { let id = UUID(); let c: CLLocationCoordinate2D }

/// Orientamenti permessi: la mappa li limita all'orizzontale (entrambi i lati, decide il telefono),
/// le altre schede li lasciano tutti. Niente lato forzato: era quello che faceva "impazzire" la rotazione.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientamenti: UIInterfaceOrientationMask = .allButUpsideDown
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientamenti
    }
}

func ruotaSchermo(_ m: UIInterfaceOrientationMask) {
    // sull'iPad la mappa funziona in entrambi i versi: non forzo la rotazione
    guard UIDevice.current.userInterfaceIdiom != .pad else { return }
    guard AppDelegate.orientamenti != m else { return }
    AppDelegate.orientamenti = m
    guard let s = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
    s.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    s.requestGeometryUpdate(.iOS(interfaceOrientations: m)) { _ in }
}

// MARK: - Barra strumenti (sinistra in orizzontale, in basso in verticale)

struct BarraStrumenti: View {
    enum Voce: CaseIterable { case esci, strumenti, segnala, squadra, messaggi, video, notte, impostazioni, sos, punto, misura, traccia, livelli }
    let verticale: Bool
    let attivo: PannelloMappa?
    let notte: Bool
    /// in orizzontale con l'isola le impostazioni stanno qui, sotto Notte
    var impostazioni = false
    var azione: (Voce) -> Void
    @ObservedObject private var tx = Trasmissione.shared

    var body: some View {
        let layout = verticale ? AnyLayout(VStackLayout(spacing: impostazioni ? 1 : 4)) : AnyLayout(HStackLayout(spacing: 0))
        layout {
            voce(.strumenti, "square.grid.2x2.fill", "Strumenti", on: attivo == .strumenti, colore: Theme.oliveBright)
            if verticale { Rectangle().fill(Theme.stroke).frame(width: 32, height: 1).padding(.vertical, 2) }
            // solo quello che serve subito sul campo; il resto è in Strumenti
            voce(.segnala, "exclamationmark.triangle", "Segnala", on: attivo == .segnala, colore: Theme.amber)
            voce(.squadra, "person.2.fill", "Squadra", on: attivo == .squadra, colore: Theme.cyan)
            voce(.messaggi, "bubble.left.and.bubble.right.fill", "Messaggi", on: chatAperta)
            voce(.video, tx.stato == .open ? "dot.radiowaves.left.and.right" : "video.fill", tx.stato == .open ? "IN ONDA" : "Video",
                 on: videoAperto, colore: tx.stato == .open ? Theme.red : Theme.olive)
            voce(.notte, notte ? "moon.fill" : "moon", "Notte", on: notte, colore: notte ? Night.red : Theme.dim)
            if verticale && impostazioni {
                voce(.impostazioni, attivo == .impostazioni ? "gearshape.fill" : "gearshape", "Mappa", on: attivo == .impostazioni, colore: Theme.oliveBright)
            }
            if verticale { Spacer(minLength: 0) }
            Button { azione(.esci) } label: {
                VStack(spacing: 1) {
                    Image(systemName: "house").font(.system(size: 15, weight: .semibold))
                    Text("App").font(.system(size: 8.5, weight: .semibold))
                }
                .foregroundStyle(Theme.dim).frame(width: 58, height: 38)
            }
            .accessibilityLabel("Torna all'app")
        }
        .padding(verticale ? .vertical : .horizontal, verticale ? 8 : 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(Theme.olive)
        .overlay(alignment: .top) {
            if !verticale { Rectangle().fill(Theme.stroke).frame(height: 1) }
        }
    }

    var videoAperto: Bool {
        if case .video = attivo { return true }
        return false
    }
    var chatAperta: Bool {
        if case .chat = attivo { return true }
        return false
    }

    func voce(_ v: Voce, _ icona: String, _ testo: String, on: Bool, colore: Color = Theme.olive) -> some View {
        Button { azione(v) } label: {
            VStack(spacing: 3) {
                Image(systemName: icona).font(.system(size: 18, weight: .semibold)).foregroundStyle(colore).frame(height: 20)
                Text(testo).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: 58, height: 42)
            .background(on ? Theme.olive.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: - Segnaposti

struct SegnapostoPunto: View {
    let punto: JPunto
    var scelto = false

    var colore: Color {
        if punto.fatto { return Color(white: 0.45) }
        switch punto.tipo {
        case "obj", "obiettivo": return Color(hex: 0xE5533F)   // rosso degli OBJ nelle tavole
        case "pericolo": return Theme.amber
        case "acqua": return Color(red: 0.3, green: 0.55, blue: 1)
        case "raduno", "base", "hotel", "parcheggio": return Theme.cyan
        case "ingresso": return Theme.green
        case "apo": return Color(red: 1, green: 0.5, blue: 0.85)
        case "waypoint", "recon": return Color(red: 0.72, green: 0.58, blue: 1)
        case "contatto": return .yellow
        default: return .white
        }
    }
    var glifo: String {
        switch punto.tipo {
        case "parcheggio": return "P"
        case "ingresso": return "IN"
        case "apo": return "A"
        case "waypoint", "recon": return "W"
        case "raduno": return "R"
        default: return ""
        }
    }
    var numero: String? {
        guard let r = punto.nome.range(of: #"\d+"#, options: .regularExpression) else { return nil }
        return String(punto.nome[r])
    }

    var body: some View {
        ZStack {
            if scelto {
                Circle().strokeBorder(Theme.oliveBright, lineWidth: 2.5).frame(width: 44, height: 44)
                Circle().strokeBorder(Theme.oliveBright.opacity(0.35), lineWidth: 1.5).frame(width: 60, height: 60)
            }
            if punto.obiettivo {
                RoundedRectangle(cornerRadius: 3).fill(colore).frame(width: 19, height: 19).rotationEffect(.degrees(45))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black, lineWidth: 2).rotationEffect(.degrees(45)))
                if punto.fatto {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .black)).foregroundStyle(.black)
                } else {
                    Text(numero ?? "").font(Theme.mono(10, .heavy)).foregroundStyle(.black)
                }
            } else if punto.tipo == "pericolo" {
                Triangolo().fill(colore).frame(width: 21, height: 18).overlay(Triangolo().stroke(Color.black, lineWidth: 1.5))
                Text("!").font(Theme.mono(11, .heavy)).foregroundStyle(.black).offset(y: 2)
            } else {
                Circle().fill(colore).frame(width: 19, height: 19).overlay(Circle().stroke(Color.black, lineWidth: 2))
                Text(glifo).font(Theme.mono(glifo.count > 1 ? 7.5 : 10, .heavy)).foregroundStyle(.black)
            }
            Text(punto.nome).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .shadow(color: .black, radius: 1).shadow(color: .black, radius: 2)
                .fixedSize()
                .offset(x: 18 + CGFloat(punto.nome.count) * 3.1, y: 0)
        }
        .frame(width: 60, height: 60)
        .contentShape(Circle())
    }
}

struct SegnapostoCompagno: View {
    let compagno: JCompagno
    let rotazioneMappa: Double
    var scelto = false

    var body: some View {
        let vecchio = compagno.eta > 300
        let colore = vecchio ? Color(white: 0.45) : Theme.cyan
        let dir = vecchio ? nil : (compagno.dir ?? ((compagno.vel ?? 0) > 0.5 ? compagno.rotta : nil))
        VStack(spacing: 1) {
            ZStack {
                if scelto { Circle().strokeBorder(Theme.oliveBright, lineWidth: 2.5).frame(width: 46, height: 46) }
                if let dir {
                    Triangolo().fill(colore).overlay(Triangolo().stroke(Color.black, lineWidth: 1))
                        .frame(width: 15, height: 12).offset(y: -15)
                        .rotationEffect(.degrees(dir - rotazioneMappa))
                }
                Circle().fill(colore).frame(width: 15, height: 15).overlay(Circle().stroke(Color.white, lineWidth: 2.2))
            }
            .frame(width: 46, height: 46)
            Text(vecchio ? "\(compagno.callsign) · \(Int(compagno.eta / 60))′" : compagno.callsign)
                .font(Theme.mono(10, .heavy)).foregroundStyle(vecchio ? Color(white: 0.7) : .white)
                .shadow(color: .black, radius: 1).shadow(color: .black, radius: 2).fixedSize()
        }
        .offset(y: 7)
        .contentShape(Rectangle())
    }
}

struct Triangolo: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct SegnapostoIo: View {
    let direzione: Double?
    let precisione: Double
    private let blu = Color(red: 0.2, green: 0.55, blue: 1)

    var body: some View {
        ZStack {
            Circle().fill(blu.opacity(0.12)).frame(width: max(30, min(300, precisione * 2)), height: max(30, min(300, precisione * 2)))
            if let direzione {
                Cono().fill(RadialGradient(colors: [blu.opacity(0.75), blu.opacity(0)], center: .bottom, startRadius: 0, endRadius: 62))
                    .frame(width: 70, height: 62).offset(y: -31)
                    .rotationEffect(.degrees(direzione))
            }
            Circle().fill(blu).frame(width: 17, height: 17).overlay(Circle().stroke(Color.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.5), radius: 3)
        }
    }
}

/// Spicchio di 70° con la punta in basso al centro.
struct Cono: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.maxY)
        p.move(to: c)
        p.addArc(center: c, radius: r.height, startAngle: .degrees(-125), endAngle: .degrees(-55), clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: - Sovrapposizioni disegnate (griglia MGRS, aree, misura, traccia, rotta)

struct Sovrapposizioni: View {
    @ObservedObject var ctl: MappaCtl
    let griglia: Bool
    let aree: [GaraArea]
    let misura: [CLLocationCoordinate2D]
    let traccia: [CLLocationCoordinate2D]
    let me: CLLocationCoordinate2D?
    let target: CLLocationCoordinate2D?

    var body: some View {
        let _ = ctl.giro
        Canvas { ctx, size in
            if griglia { disegnaGriglia(ctx, size) }
            for a in aree {
                let pts = a.coordinates.compactMap { ctl.punto($0) }
                guard pts.count >= 3 else { continue }
                var p = Path(); p.addLines(pts); p.closeSubpath()
                if a.interdetta {
                    ctx.fill(p, with: .color(Theme.red.opacity(0.2)))
                    ctx.stroke(p, with: .color(Theme.red.opacity(0.85)), lineWidth: 1.5)
                } else {
                    ctx.fill(p, with: .color(Theme.olive.opacity(0.05)))
                    ctx.stroke(p, with: .color(Theme.olive), style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                }
            }
            linea(ctx, traccia, Color(red: 1, green: 0.55, blue: 0.15), 3.5)
            if let me, let target, let a = ctl.punto(me), let b = ctl.punto(target) {
                var p = Path(); p.move(to: a); p.addLine(to: b)
                ctx.stroke(p, with: .color(.black), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                ctx.stroke(p, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                let r = 25 / ctl.metriPerPunto
                ctx.stroke(Path(ellipseIn: CGRect(x: b.x - r, y: b.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(Theme.oliveBright), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
            if misura.count >= 1 {
                linea(ctx, misura, Theme.amber, 2.5, tratteggio: [6, 4])
                var tot = 0.0
                for (i, c) in misura.enumerated() {
                    guard let s = ctl.punto(c) else { continue }
                    ctx.fill(Path(ellipseIn: CGRect(x: s.x - 5, y: s.y - 5, width: 10, height: 10)), with: .color(Theme.amber))
                    if i > 0 {
                        tot += Geo.distance(misura[i - 1], c)
                        let t = Text("\(Geo.formatDistance(tot)) · \(gradi3(Geo.bearing(misura[i - 1], c)))")
                            .font(Theme.mono(11, .heavy)).foregroundColor(.white)
                        ctx.draw(t, at: CGPoint(x: s.x, y: s.y - 16))
                    }
                }
            }
        }
    }

    func linea(_ ctx: GraphicsContext, _ c: [CLLocationCoordinate2D], _ colore: Color, _ w: CGFloat, tratteggio: [CGFloat] = []) {
        let pts = c.compactMap { ctl.punto($0) }
        guard pts.count >= 2 else { return }
        var p = Path(); p.addLines(pts)
        ctx.stroke(p, with: .color(.black.opacity(0.6)), style: StrokeStyle(lineWidth: w + 2.5, lineCap: .round, lineJoin: .round, dash: tratteggio))
        ctx.stroke(p, with: .color(colore), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round, dash: tratteggio))
    }

    /// Griglia UTM/MGRS: 100 m, 1 km o 10 km a seconda dello zoom, con le cifre MGRS ai bordi.
    func disegnaGriglia(_ ctx: GraphicsContext, _ size: CGSize) {
        guard let c = ctl.coordinata(CGPoint(x: size.width / 2, y: size.height / 2)) else { return }
        let mpp = ctl.metriPerPunto
        guard let passo = [100.0, 1000, 10000].first(where: { $0 / mpp >= 55 }) else { return }
        let base = UTM.fromLatLon(c.latitude, c.longitude)
        let angoli = [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)]
            .compactMap { ctl.coordinata($0) }
            .map { UTM.fromLatLon($0.latitude, $0.longitude) }
            .filter { $0.zone == base.zone }
        guard angoli.count == 4 else { return }
        let e0 = floor(angoli.map(\.easting).min()! / passo) * passo, e1 = angoli.map(\.easting).max()!
        let n0 = floor(angoli.map(\.northing).min()! / passo) * passo, n1 = angoli.map(\.northing).max()!
        guard (e1 - e0) / passo < 80, (n1 - n0) / passo < 80 else { return }
        func sc(_ e: Double, _ n: Double) -> CGPoint? {
            let (la, lo) = UTM.toLatLon(UTMCoord(zone: base.zone, north: base.north, easting: e, northing: n, band: base.band))
            return ctl.punto(CLLocationCoordinate2D(latitude: la, longitude: lo))
        }
        let stile = StrokeStyle(lineWidth: 1)
        let colore = GraphicsContext.Shading.color(Theme.olive.opacity(0.35))
        let cifre: (Double) -> String = { v in
            let k = Int((v / passo).rounded())
            return passo >= 10000 ? String(format: "%d", k % 10) : (passo >= 1000 ? String(format: "%02d", k % 100) : String(format: "%03d", k % 1000))
        }
        var e = e0
        while e <= e1 {
            if let a = sc(e, n0), let b = sc(e, n1) {
                var p = Path(); p.move(to: a); p.addLine(to: b)
                ctx.stroke(p, with: colore, style: stile)
                if let t = sc(e, n1 - (n1 - n0) * 0.0) {
                    let x = min(max(t.x, 14), size.width - 14)
                    ctx.draw(Text(cifre(e)).font(Theme.mono(9, .bold)).foregroundColor(Theme.olive.opacity(0.8)), at: CGPoint(x: x + 9, y: size.height - 10))
                }
            }
            e += passo
        }
        var n = n0
        while n <= n1 {
            if let a = sc(e0, n), let b = sc(e1, n) {
                var p = Path(); p.move(to: a); p.addLine(to: b)
                ctx.stroke(p, with: colore, style: stile)
                let y = min(max(a.y, 12), size.height - 12)
                ctx.draw(Text(cifre(n)).font(Theme.mono(9, .bold)).foregroundColor(Theme.olive.opacity(0.8)), at: CGPoint(x: size.width - 14, y: y - 7))
            }
            n += passo
        }
    }
}

// MARK: - HUD posizione e scala

struct PosizioneHUD: View {
    @EnvironmentObject var location: LocationService
    var body: some View {
        let l = location.location
        let dir = location.heading.map { gradi3($0 - (location.declinazione ?? 4.6)) }
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(l.map { Geo.mgrs($0.coordinate) } ?? "in attesa del GPS").font(Theme.mono(13, .heavy)).foregroundStyle(.white)
                Text(l.map { String(format: "± %.0f m · %@", $0.horizontalAccuracy, $0.verticalAccuracy > 0 ? String(format: "%.0f m", $0.altitude) : "quota —") } ?? "—")
                    .font(Theme.mono(10)).foregroundStyle(Theme.dim)
            }
            Rectangle().fill(Theme.stroke).frame(width: 1, height: 30)
            VStack(alignment: .trailing, spacing: 0) {
                Text(dir ?? "—").font(Theme.mono(19, .heavy)).foregroundStyle(Theme.oliveBright)
                Text("MAG").font(Theme.mono(8, .bold)).tracking(1).foregroundStyle(Theme.dim)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Color.black.opacity(0.84), in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Theme.stroke))
    }
}

struct ScalaMappa: View {
    let metriPerPunto: Double
    var body: some View {
        let target = metriPerPunto * 80
        let passi: [Double] = [10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000]
        let m = passi.last { $0 <= target } ?? 10
        // tavola 10: staffa bianca da 1,5 pt (senza lato in alto), sotto la distanza
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(.clear).frame(width: max(10, m / metriPerPunto), height: 7.5)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.testo).frame(height: 1.5) }
                .overlay(alignment: .leading) { Rectangle().fill(Theme.testo).frame(width: 1.5) }
                .overlay(alignment: .trailing) { Rectangle().fill(Theme.testo).frame(width: 1.5) }
                .shadow(color: .black.opacity(0.5), radius: 1.5)
            Text(m >= 1000 ? "\(Int(m / 1000)) km" : "\(Int(m)) m").font(Theme.mono(10, .heavy)).foregroundStyle(Theme.testo)
                .shadow(color: .black.opacity(0.6), radius: 2)
        }
    }
}

// MARK: - Menu circolare

struct VoceRadiale: Identifiable {
    let id = UUID()
    /// percorso SVG della tela (Ic.m…)
    let icona: String
    let testo: String
    let colore: Color
    /// spicchio rosso scuro (Elimina)
    var rosso = false
    let azione: () -> Void
}

/// LA RUOTA (tavola 12): menu circolare su obiettivi e operatori, centrato sul punto toccato.
/// Si apre a ventaglio dal centro, velata sulla mappa. Misure della tela (r 104/38, centro 31) ingrandite di 1,15.
struct MenuRadiale: View {
    let voci: [VoceRadiale]
    let centro: String
    let colore: Color
    /// centro della Ruota nello schermo
    let posizione: CGPoint
    static let scala: CGFloat = 1.15
    static let raggio: CGFloat = 104 * scala
    private let r: CGFloat = MenuRadiale.raggio          // raggio esterno degli spicchi
    private let ri: CGFloat = 38 * MenuRadiale.scala     // raggio interno (attorno al pallino centrale)
    /// tavola 11 (non ancora approvata): spicchi separati da fessure a lati paralleli
    @AppStorage("mappa.spicchiParalleli") private var paralleli = false
    /// apertura disegnata fotogramma per fotogramma: gli spicchi escono uno dopo l'altro ruotando da ore 12
    @State private var inizio = Date()
    @State private var finito = false
    private let durata = 0.34, scalino = 0.05

    var body: some View {
        // disegnata in un riquadro proprio, così il ventaglio ruota attorno al centro della Ruota
        let lato = 2 * (r + 6)
        let c = CGPoint(x: lato / 2, y: lato / 2)
        let k = Self.scala
        let ampiezza = 360.0 / Double(max(voci.count, 1))
        TimelineView(.animation(minimumInterval: nil, paused: finito)) { tl in
            let t = finito ? 10 : tl.date.timeIntervalSince(inizio)
            ZStack {
                ForEach(Array(voci.enumerated()), id: \.element.id) { i, v in
                    let q = Self.molla((t - scalino * Double(i)) / durata)
                    SpicchioRuota(voce: v, medio: -90 + Double(i) * ampiezza, ampiezza: ampiezza, ri: ri, ro: r, centro: c, paralleli: paralleli)
                        .rotationEffect(.degrees(-50 * (1 - min(q, 1))))
                        .scaleEffect(0.5 + 0.5 * q)
                        .opacity(min(1, q * 2.5))
                }
                let f = Self.morbido(t / 0.2)
                Text(centro).font(Theme.mono(15 * k, .heavy)).foregroundStyle(Color(hex: 0x111111))
                    .lineLimit(1).minimumScaleFactor(0.5).padding(5)
                    .frame(width: 62 * k, height: 62 * k)
                    .background(colore, in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 3 * k))
                    .scaleEffect(0.5 + 0.5 * f).opacity(f)
                    .position(c)
            }
            .frame(width: lato, height: lato)
        }
        .frame(width: lato, height: lato)
        .position(posizione)
        .onAppear {
            inizio = Date(); finito = false
            haptic(.light)
            DispatchQueue.main.asyncAfter(deadline: .now() + durata + scalino * Double(voci.count) + 0.5) { finito = true }
        }
    }

    /// 0→1 con frenata dolce
    static func morbido(_ x: Double) -> Double { let v = min(max(x, 0), 1); return 1 - pow(1 - v, 3) }
    /// 0→1 con un piccolo rimbalzo finale
    static func molla(_ x: Double) -> Double {
        let v = min(max(x, 0), 1)
        if v >= 1 { return 1 }
        let c1 = 1.4, c3 = c1 + 1
        return 1 + c3 * pow(v - 1, 3) + c1 * pow(v - 1, 2)
    }
}

struct BottoneRadiale: View {
    let voce: VoceRadiale
    var body: some View {
        Button { haptic(.medium); voce.azione() } label: {
            VStack(spacing: 2) {
                IconaTela(d: voce.icona, colore: voce.colore, lato: 18)
                Text(voce.testo).font(.system(size: 9, weight: .bold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(width: 56, height: 56)
            .background(Color(red: 0.06, green: 0.075, blue: 0.045).opacity(0.82), in: Circle())
            .overlay(Circle().strokeBorder(voce.colore.opacity(0.55)))
        }
        .buttonStyle(PressStyle())
    }
}

struct SchedaBreve: View {
    let titolo: String
    let etichetta: String
    let coloreEtichetta: Color
    let me: CLLocationCoordinate2D?
    let c: CLLocationCoordinate2D
    let riga: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(titolo).font(.system(size: 14, weight: .heavy)).lineLimit(1)
                Spacer(minLength: 4)
                Text(etichetta).font(Theme.mono(9, .heavy)).foregroundStyle(coloreEtichetta)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(coloreEtichetta.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            }
            if let me {
                HStack(spacing: 14) {
                    dato(Geo.formatDistance(Geo.distance(me, c)), "DISTANZA")
                    dato(gradi3(Geo.bearing(me, c)), "AZIMUT")
                }
            }
            Text(Geo.mgrs(c)).font(Theme.mono(10.5, .semibold)).foregroundStyle(Theme.dim)
            if !riga.isEmpty { Text(riga).font(.caption2).foregroundStyle(Theme.dim) }
        }
        .padding(12)
        .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(coloreEtichetta.opacity(0.4)))
    }

    func dato(_ v: String, _ e: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(Theme.mono(15, .heavy))
            Text(e).font(.system(size: 8.5, weight: .bold)).foregroundStyle(Theme.dim)
        }
    }
}

// MARK: - Pannelli della colonna

struct TestataPannello: View {
    let titolo: String
    var sotto: String? = nil
    var chiudi: () -> Void
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(titolo).font(.system(size: 16, weight: .heavy)).lineLimit(1)
                if let sotto { Text(sotto).font(Theme.mono(10.5)).foregroundStyle(Theme.dim).lineLimit(1) }
            }
            Spacer()
            Button(action: chiudi) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30).background(Color.white.opacity(0.08), in: Circle())
            }
            .accessibilityLabel("Chiudi")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
    }
}

struct EtichettaSezione: View {
    let testo: String
    var body: some View {
        Text(testo.uppercased()).font(Theme.mono(9.5, .heavy)).tracking(1.5).foregroundStyle(Theme.olive)
    }
}

struct PannelloVuoto: View {
    let titolo: String
    var chiudi: () -> Void
    var body: some View { TestataPannello(titolo: titolo, chiudi: chiudi) }
}

// MARK: resoconto OBJ

struct PannelloResoconto: View {
    let punto: JPunto
    let allegati: [DocItem]
    var chiudi: () -> Void
    var vicini: (() -> Void)? = nil
    var misura: (() -> Void)? = nil
    @EnvironmentObject var location: LocationService
    @EnvironmentObject var docs: DocStore
    @ObservedObject private var store = EventoStore.shared
    @State private var nota = ""
    @State private var ipotesi = false
    @State private var scrivendo = false
    @State private var foto: PhotosPickerItem?
    @State private var anteprima: URL?
    @State private var errore: String?
    @State private var resoconto = ""
    @State private var modificaResoconto = false

    var body: some View {
        let me = location.location?.coordinate
        VStack(spacing: 0) {
            TestataPannello(titolo: punto.nome,
                            sotto: Geo.mgrs(punto.coordinate) + (me.map { " · \(Geo.formatDistance(Geo.distance($0, punto.coordinate))) · \(gradi3(Geo.bearing($0, punto.coordinate)))" } ?? ""),
                            chiudi: chiudi)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(punto.fatto ? "FATTO" : "DA FARE").font(Theme.mono(9.5, .heavy))
                            .foregroundStyle(punto.fatto ? Theme.green : Theme.amber)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background((punto.fatto ? Theme.green : Theme.amber).opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                        Text(punto.tipo.uppercased()).font(Theme.mono(9.5, .heavy)).foregroundStyle(Theme.dim)
                        Spacer()
                        Button(punto.fatto ? "Riapri" : "Fatto") {
                            haptic(.medium)
                            Task { _ = try? await JsocClient.shared.aggiornaPunto(punto.id, ["stato": punto.fatto ? "da fare" : "fatto"]); await store.aggiorna(JsocClient.shared) }
                        }
                        .font(.caption.weight(.bold)).tint(Theme.green)
                        if let vicini { Button("Vicini", action: vicini).font(.caption.weight(.bold)).tint(Theme.cyan) }
                        if let misura { Button("Misura", action: misura).font(.caption.weight(.bold)).tint(Theme.olive) }
                        if store.corrente?.staff == true {
                            Button(modificaResoconto ? "Salva" : "Modifica") {
                                if modificaResoconto {
                                    Task { _ = try? await JsocClient.shared.aggiornaPunto(punto.id, ["resoconto": resoconto]); await store.aggiorna(JsocClient.shared) }
                                } else { resoconto = punto.resoconto ?? "" }
                                modificaResoconto.toggle()
                            }
                            .font(.caption.weight(.bold)).tint(Theme.olive)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        EtichettaSezione(testo: "Resoconto")
                        if modificaResoconto {
                            TextField("Resoconto dell'obiettivo", text: $resoconto, axis: .vertical).lineLimit(3...10)
                                .font(.system(size: 13)).padding(8).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 8))
                        } else {
                            let t = [punto.resoconto, punto.note].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
                            Text(t.isEmpty ? "Nessun resoconto." : t).font(.system(size: 13)).foregroundStyle(t.isEmpty ? Theme.dim : .white.opacity(0.92))
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        EtichettaSezione(testo: "Indagine · \((punto.indagine ?? []).count) note")
                        ForEach(punto.indagine ?? []) { n in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(n.testo).font(.system(size: 12.5))
                                Text("\(n.callsign ?? "?") · \(Date(timeIntervalSince1970: n.ts).formatted(date: .omitted, time: .shortened))\(n.ipotesi == 1 ? " · IPOTESI" : "")")
                                    .font(Theme.mono(9.5)).foregroundStyle(n.ipotesi == 1 ? Theme.amber : Theme.dim)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                        }
                        if scrivendo {
                            TextField("Nota per la squadra", text: $nota, axis: .vertical).lineLimit(2...6)
                                .font(.system(size: 13)).padding(8).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 8))
                            HStack {
                                Toggle("È un'ipotesi", isOn: $ipotesi).font(.caption).tint(Theme.amber)
                                Button("Invia") { inviaNota() }.buttonStyle(.borderedProminent).tint(Theme.olive).foregroundStyle(.black)
                                    .disabled(nota.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        EtichettaSezione(testo: "Allegati · \(allegati.count)")
                        if allegati.isEmpty {
                            Text("Nessun allegato. Lo staff li mette nella cartella \"\(punto.cartella?.isEmpty == false ? punto.cartella! : punto.nome)\" dei documenti dell'evento.")
                                .font(.caption).foregroundStyle(Theme.dim)
                        }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                            ForEach(allegati) { a in
                                Button { anteprima = a.url } label: { AllegatoTessera(item: a) }.buttonStyle(PressStyle())
                            }
                        }
                    }
                    if let errore { Text(errore).font(.caption).foregroundStyle(Theme.red) }
                }
                .padding(14)
            }
            HStack(spacing: 8) {
                Button {
                    haptic(.medium)
                    NavStore.shared.target = GaraPoint(id: punto.nome, lat: punto.lat, lon: punto.lon, kind: DatiEvento.kind(punto.tipo), note: punto.note ?? "")
                } label: { Label("Naviga", systemImage: "location.north.line.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(Theme.oliveBright).foregroundStyle(.black)
                Button { withAnimation { scrivendo.toggle() } } label: { Text("+ Nota") }
                    .buttonStyle(.bordered).tint(Theme.olive)
                PhotosPicker(selection: $foto, matching: .images) { Text("+ Foto") }
                    .buttonStyle(.bordered).tint(Theme.olive)
            }
            .font(.system(size: 13, weight: .bold))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
        }
        .quickLookPreview($anteprima)
        .onChange(of: foto) { item in
            guard let item else { return }
            Task {
                defer { foto = nil }
                guard let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d),
                      let jpg = img.ridotta(lato: 2000).jpegData(compressionQuality: 0.82), let ev = store.corrente?.id else { return }
                let cartella = punto.cartella?.isEmpty == false ? punto.cartella! : punto.nome
                let nome = "\(cartella)/Inviati/\(JsocClient.shared.utente?.callsign ?? "foto")-\(Int(Date().timeIntervalSince1970)).jpg"
                do { try await JsocClient.shared.caricaFile(ev, nome, dati: jpg); await docs.sync(JsocClient.shared, force: true) }
                catch { errore = error.localizedDescription }
            }
        }
    }

    func inviaNota() {
        let t = nota
        Task {
            do {
                _ = try await JsocClient.shared.indagine(punto.id, t, ipotesi: ipotesi)
                nota = ""; ipotesi = false; scrivendo = false
                await store.aggiorna(JsocClient.shared)
            } catch { errore = error.localizedDescription }
        }
    }
}

struct AllegatoTessera: View {
    let item: DocItem
    var body: some View {
        let ext = item.url.pathExtension.lowercased()
        VStack(alignment: .leading, spacing: 4) {
            if ["jpg", "jpeg", "png", "heic", "webp"].contains(ext), let img = UIImage(contentsOfFile: item.url.path) {
                Image(uiImage: img).resizable().scaledToFill().frame(height: 46).frame(maxWidth: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: ext == "pdf" ? "doc.richtext.fill" : (["mp3", "m4a", "wav"].contains(ext) ? "waveform" : (["mp4", "mov"].contains(ext) ? "film.fill" : "doc.fill")))
                    .font(.system(size: 20)).foregroundStyle(ext == "pdf" ? Theme.red : Theme.cyan).frame(height: 46)
            }
            Text(item.url.deletingPathExtension().lastPathComponent).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
        }
        .padding(5)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke))
    }
}

// MARK: video

struct PannelloVideo: View {
    let scelto: String?
    var chiudi: () -> Void
    @State private var flussi: [JFlusso] = []
    @State private var attivo: String?
    @State private var player: AVPlayer?
    @State private var errore: String?
    @State private var colonna = false
    @State private var intero = false
    @ObservedObject private var tx = Trasmissione.shared

    var body: some View {
        VStack(spacing: 0) {
            TestataPannello(titolo: "Video", sotto: attivo.map { "in visione: \($0)" } ?? "flussi della squadra", chiudi: chiudi)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.black)
                if let player {
                    VideoPlayer(player: player)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "video.slash").font(.title2).foregroundStyle(Theme.dim)
                        Text(attivo == nil ? "Scegli un flusso qui sotto" : "\(attivo!) non sta trasmettendo").font(.caption).foregroundStyle(Theme.dim)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let a = attivo, player != nil {
                    Text("LIVE · \(a)").font(Theme.mono(10, .heavy)).foregroundStyle(.black)
                        .padding(.horizontal, 7).padding(.vertical, 3).background(Theme.red, in: RoundedRectangle(cornerRadius: 5)).padding(8)
                }
            }
            .overlay(alignment: .topTrailing) {
                if player != nil {
                    HStack(spacing: 6) {
                        Button { haptic(); withAnimation(.spring(response: 0.3)) { colonna.toggle() } } label: {
                            Image(systemName: colonna ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                        }
                        Button { haptic(); intero = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    }
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .padding(8).background(.black.opacity(0.55), in: Capsule()).padding(8)
                }
            }
            .aspectRatio(colonna ? nil : 16 / 9, contentMode: .fit)
            .frame(maxHeight: colonna ? .infinity : nil)
            if !colonna {
            // flussi in una riga sola
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if flussi.isEmpty { Text(errore ?? "Nessun flusso").font(.caption).foregroundStyle(Theme.dim) }
                    ForEach(flussi) { f in
                        Button { guarda(f.nome) } label: {
                            HStack(spacing: 5) {
                                Circle().fill(f.pronto ? Theme.red : Theme.dim).frame(width: 7, height: 7)
                                Text(f.nome).font(.system(size: 12.5, weight: .bold))
                            }
                            .foregroundStyle(attivo == f.nome ? .black : (f.pronto ? .white : Theme.dim))
                            .padding(.horizontal, 11).frame(height: 32)
                            .background(attivo == f.nome ? Theme.red : Theme.surface2.opacity(0.8), in: Capsule())
                        }
                        .disabled(!f.pronto)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            Spacer(minLength: 0)
            MiaCamera(tx: tx).padding(.horizontal, 12).padding(.bottom, 10)
            }
        }
        .fullScreenCover(isPresented: $intero) {
            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()
                if let player { VideoPlayer(player: player).ignoresSafeArea() }
                if let a = attivo {
                    Text("LIVE · \(a)").font(Theme.mono(12, .heavy)).foregroundStyle(.black)
                        .padding(.horizontal, 9).padding(.vertical, 4).background(Theme.red, in: RoundedRectangle(cornerRadius: 6))
                        .padding(.top, 14).padding(.leading, 120)
                }
            }
            .indietro("Mappa") { intero = false }
        }
        .task {
            while !Task.isCancelled {
                do { flussi = try await JsocClient.shared.flussiVideo(); errore = nil }
                catch { errore = error.localizedDescription }
                if attivo == nil || player == nil, let s = scelto,
                   let f = flussi.first(where: { $0.nome.uppercased().hasPrefix(s.uppercased()) && $0.pronto }) {
                    if player == nil { guarda(f.nome) }
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        .onAppear { if let s = scelto { attivo = s } }
        .onDisappear { player?.pause() }
    }

    func guarda(_ nome: String) {
        player?.pause()
        attivo = nome
        guard let u = JsocClient.shared.videoURL(nome) else { return }
        let p = AVPlayer(url: u)
        p.automaticallyWaitsToMinimizeStalling = false
        p.agganciaAllaDiretta()
        player = p
        p.play()
    }
}

// MARK: squadra, chat, info

struct PannelloSquadra: View {
    var chiudi: () -> Void
    var scegli: (JCompagno) -> Void
    @ObservedObject private var store = EventoStore.shared
    @ObservedObject private var jsoc = JsocClient.shared
    @EnvironmentObject var location: LocationService

    var body: some View {
        let membri = store.corrente?.membri ?? []
        VStack(spacing: 0) {
            TestataPannello(titolo: "Squadra", sotto: "\(store.squadra.filter { $0.eta < 300 }.count) di \(membri.count) in mappa", chiudi: chiudi)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(membri) { m in
                        let pos = store.squadra.first { $0.id == m.id }
                        Button { if let pos, m.id != jsoc.utente?.id { scegli(pos) } } label: {
                            HStack(spacing: 10) {
                                StatusDot(on: pos.map { $0.eta < 300 } ?? false)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(m.callsign).font(Theme.mono(14, .heavy)).foregroundStyle(.white)
                                    Text(m.nome).font(.caption2).foregroundStyle(Theme.dim)
                                }
                                Spacer()
                                if let p = pos, let me = location.location?.coordinate, m.id != jsoc.utente?.id {
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text(Geo.formatDistance(Geo.distance(me, p.coordinate))).font(Theme.mono(13, .bold)).foregroundStyle(Theme.olive)
                                        Text(gradi3(Geo.bearing(me, p.coordinate))).font(Theme.mono(10)).foregroundStyle(Theme.dim)
                                    }
                                } else if m.id == jsoc.utente?.id {
                                    Text("tu").font(.caption2).foregroundStyle(Theme.dim)
                                } else {
                                    Text("non in mappa").font(.caption2).foregroundStyle(Theme.dim)
                                }
                            }
                            .padding(10).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .padding(12)
            }
        }
    }
}

struct PannelloChat: View {
    @State var dest: Int?
    var chiudi: () -> Void
    @ObservedObject private var store = EventoStore.shared
    @ObservedObject private var jsoc = JsocClient.shared

    var body: some View {
        let io = jsoc.utente?.id
        let altri = (store.corrente?.membri ?? []).filter { $0.id != io }
        VStack(spacing: 0) {
            TestataPannello(titolo: "Messaggi", sotto: store.corrente?.nome, chiudi: chiudi)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    scheda("Generale", nil, nonLetti: store.messaggi.filter { $0.dest == nil && $0.autore != io }.count)
                    ForEach(altri) { m in
                        scheda(m.callsign, m.id, nonLetti: store.messaggi.filter { $0.autore == m.id && $0.dest == io }.count)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
            MessaggiRapidi(dest: dest)
            ChatView(con: dest).id(dest ?? -1)
        }
    }

    func scheda(_ t: String, _ id: Int?, nonLetti: Int) -> some View {
        let on = dest == id
        return Button { haptic(); dest = id } label: {
            HStack(spacing: 5) {
                Image(systemName: id == nil ? "person.3.fill" : "person.fill").font(.system(size: 11))
                Text(t).font(.system(size: 13, weight: .bold)).lineLimit(1)
            }
            .foregroundStyle(on ? .black : .white)
            .padding(.horizontal, 12).frame(height: 32)
            .background(on ? Theme.olive : Theme.surface2.opacity(0.8), in: Capsule())
        }
    }
}

struct PannelloInfo: View {
    let compagno: JCompagno?
    var chiudi: () -> Void
    @EnvironmentObject var location: LocationService
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TestataPannello(titolo: compagno?.callsign ?? "Operatore", sotto: compagno?.nome, chiudi: chiudi)
            if let c = compagno {
                VStack(alignment: .leading, spacing: 10) {
                    riga("Posizione", Geo.mgrs(c.coordinate))
                    if let me = location.location?.coordinate {
                        riga("Distanza", Geo.formatDistance(Geo.distance(me, c.coordinate)))
                        riga("Azimut", gradi3(Geo.bearing(me, c.coordinate)))
                    }
                    riga("Guarda verso", c.dir.map { gradi3($0) } ?? "—")
                    riga("Velocità", (c.vel ?? 0) > 0.3 ? String(format: "%.1f km/h", (c.vel ?? 0) * 3.6) : "fermo")
                    riga("Batteria", c.batt.map { "\(Int($0 * 100))%" } ?? "—")
                    riga("Precisione GPS", c.acc.map { String(format: "± %.0f m", $0) } ?? "—")
                    riga("Aggiornato", c.eta < 60 ? "adesso" : "\(Int(c.eta / 60)) min fa")
                    riga("Squadra", c.squadra?.isEmpty == false ? c.squadra! : "—")
                }
                .padding(14)
            }
            Spacer()
        }
    }
    func riga(_ a: String, _ b: String) -> some View {
        HStack { Text(a).font(.caption).foregroundStyle(Theme.dim); Spacer(); Text(b).font(Theme.mono(13, .bold)) }
    }
}

// MARK: livelli



// MARK: misura

struct PannelloMisura: View {
    @Binding var punti: [CLLocationCoordinate2D]
    var chiudi: () -> Void

    var body: some View {
        let tratti = zip(punti, punti.dropFirst()).map { (Geo.distance($0, $1), Geo.bearing($0, $1)) }
        let tot = tratti.reduce(0) { $0 + $1.0 }
        VStack(spacing: 0) {
            TestataPannello(titolo: "Misura", sotto: "tieni premuto sulla mappa per aggiungere punti", chiudi: chiudi)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Geo.formatDistance(tot)).font(Theme.mono(30, .heavy)).foregroundStyle(Theme.oliveBright)
                    Text("\(tratti.count) tratti").font(.caption).foregroundStyle(Theme.dim)
                }
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(tratti.enumerated()), id: \.offset) { i, t in
                            HStack {
                                Text("\(i + 1)").font(Theme.mono(11, .bold)).foregroundStyle(Theme.dim).frame(width: 20)
                                Text(Geo.formatDistance(t.0)).font(Theme.mono(13, .bold))
                                Spacer()
                                Text("az \(gradi3(t.1)) · contro \(gradi3(t.1 + 180))").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                            }
                        }
                    }
                }
                HStack {
                    Button("Togli l'ultimo") { if !punti.isEmpty { punti.removeLast() } }.buttonStyle(.bordered).tint(Theme.olive)
                    Button("Azzera") { punti = [] }.buttonStyle(.bordered).tint(Theme.red)
                }
                .font(.caption.weight(.bold))
            }
            .padding(14)
        }
    }
}

// MARK: - Nuovo punto (condiviso con la squadra)

struct NuovoPuntoSheet: View {
    let coordinata: CLLocationCoordinate2D
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var store = EventoStore.shared
    @State private var nome = ""
    @State private var tipo = "punto"
    @State private var note = ""
    @State private var errore: String?

    var tipi: [(String, String)] {
        let base = [("punto", "Punto"), ("contatto", "Contatto"), ("pericolo", "Pericolo")]
        return store.corrente?.staff == true ? base + [("obj", "Obiettivo"), ("raduno", "Raduno"), ("acqua", "Acqua"), ("logistica", "Logistica")] : base
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { Text(Geo.mgrs(coordinata)).font(Theme.mono(14, .bold)) }
                TextField("Nome (es. OBJ 4 Deposito)", text: $nome)
                Picker("Tipo", selection: $tipo) { ForEach(tipi, id: \.0) { Text($0.1).tag($0.0) } }
                TextField("Note", text: $note, axis: .vertical).lineLimit(2...5)
                if store.corrente == nil { Text("Scegli prima un evento: i punti si condividono con la sua squadra.").foregroundStyle(Theme.amber) }
                if let errore { Text(errore).foregroundStyle(Theme.red) }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Nuovo punto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        guard let ev = store.corrente?.id else { return }
                        Task {
                            do {
                                _ = try await JsocClient.shared.creaPunto(ev, nome: nome.isEmpty ? tipo.capitalized : nome, tipo: tipo, coordinata, note: note)
                                await store.aggiorna(JsocClient.shared)
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                dismiss()
                            } catch { errore = error.localizedDescription }
                        }
                    }
                    .disabled(store.corrente == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}


/// La mia camera dentro la colonna video: anteprima piccola, IN ONDA, stop. La trasmissione continua
/// anche chiudendo la colonna o cambiando scheda; si ferma solo con Stop.
struct MiaCamera: View {
    @ObservedObject var tx: Trasmissione
    @State private var errore: String?
    @State private var avvio = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if tx.cameraAccesa {
                ZStack(alignment: .topLeading) {
                    MTHKViewRepresentable(previewSource: tx, videoGravity: .resizeAspectFill)
                        .frame(height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(tx.stato == .open ? "IN ONDA " + durata(ctx.date) : (tx.stato == .connecting ? "COLLEGAMENTO…" : "ANTEPRIMA"))
                            .font(Theme.mono(10, .heavy)).foregroundStyle(tx.stato == .open ? .black : .white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(tx.stato == .open ? Theme.red : Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
                            .padding(6)
                    }
                }
            }
            if let e = errore ?? tx.errore { Text(e).font(.caption).foregroundStyle(Theme.red) }
            HStack(spacing: 8) {
                if tx.stato == .closed {
                    Button { avvia() } label: {
                        Label(avvio ? "Avvio…" : "Trasmetti la mia camera", systemImage: "video.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.red).disabled(avvio)
                } else {
                    Button { Task { await tx.chiudi(); tx.fermaCamera() } } label: {
                        Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.red)
                    Button { tx.cambiaMuto() } label: { Image(systemName: tx.muto ? "mic.slash.fill" : "mic.fill") }
                        .buttonStyle(.bordered).tint(tx.muto ? Theme.red : Theme.olive)
                    Button { tx.gira() } label: { Image(systemName: "arrow.triangle.2.circlepath.camera") }
                        .buttonStyle(.bordered).tint(Theme.olive)
                }
            }
            .font(.system(size: 13, weight: .bold))
            if tx.stato == .closed { Text("Per trasmettere serve Tailscale acceso o il wifi del server.").font(.caption2).foregroundStyle(Theme.dim) }
        }
    }

    func durata(_ ora: Date) -> String {
        guard let i = tx.inizio else { return "" }
        let s = Int(ora.timeIntervalSince(i))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    func avvia() {
        errore = nil
        avvio = true
        Task {
            defer { avvio = false }
            do { tx.trasmettiJSOC(try await JsocClient.shared.videoPubblica()) }
            catch { errore = error.localizedDescription }
        }
    }
}


enum Attrezzo: String, Identifiable { case cifrari, raccolta; var id: String { rawValue } }

/// Rettangolo con gli angoli arrotondati solo a sinistra (colonna attaccata al bordo destro).
struct ArrotondatoSinistra: Shape {
    var r: CGFloat
    func path(in q: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: q.maxX, y: q.minY))
        p.addLine(to: CGPoint(x: q.minX + r, y: q.minY))
        p.addArc(center: CGPoint(x: q.minX + r, y: q.minY + r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(180), clockwise: true)
        p.addLine(to: CGPoint(x: q.minX, y: q.maxY - r))
        p.addArc(center: CGPoint(x: q.minX + r, y: q.maxY - r), radius: r, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        p.addLine(to: CGPoint(x: q.maxX, y: q.maxY))
        p.closeSubpath()
        return p
    }
}


/// Apertura a ventaglio della Ruota: angolo e raggio crescono insieme, così i pulsanti girano lungo l'arco.
struct Ventaglio: GeometryEffect {
    var progresso: Double
    let angolo: Double
    let raggio: CGFloat
    var animatableData: Double { get { progresso } set { progresso = newValue } }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let a = (-90 + (angolo + 90) * progresso) * .pi / 180
        let r = Double(raggio) * (0.25 + 0.75 * progresso)
        return ProjectionTransform(CGAffineTransform(translationX: CGFloat(cos(a) * r), y: CGFloat(sin(a) * r)))
    }
}


/// Settore circolare che parte da ore 12 e si allarga in senso orario.
struct Spicchio: Shape {
    var fine: Double
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        p.move(to: c)
        p.addArc(center: c, radius: r.width / 2, startAngle: .degrees(-90), endAngle: .degrees(-90 + fine), clockwise: false)
        p.closeSubpath()
        return p
    }
}


/// Uno spicchio della Ruota: settore di corona circolare con icona e nome, si tocca solo dentro la sua forma.
/// Icona e nome stanno a 70 pt (×1,15) dal centro, sull'asse dello spicchio; il nome va su due righe
/// o si rimpicciolisce invece di essere tagliato.
struct SpicchioRuota: View {
    let voce: VoceRadiale
    /// asse dello spicchio in gradi (0 = destra, -90 = ore 12)
    let medio: Double
    let ampiezza: Double
    let ri: CGFloat
    let ro: CGFloat
    let centro: CGPoint
    var paralleli = false

    var body: some View {
        let k = MenuRadiale.scala
        let forma = SettoreAnello(da: medio - ampiezza / 2, a: medio + ampiezza / 2, ri: ri, ro: ro, centro: centro,
                                  taglio: paralleli ? 4 * k : nil)
        let m = medio * .pi / 180
        let rb = 70 * k
        let b = CGPoint(x: centro.x + rb * CGFloat(cos(m)), y: centro.y + rb * CGFloat(sin(m)))
        // spazio per il nome: corda dello spicchio all'altezza della scritta, meno un margine
        let larghezza = max(40, 2 * (rb + 9 * k) * CGFloat(sin(ampiezza / 2 * .pi / 180)) - 10 * k)
        Button { haptic(.medium); voce.azione() } label: {
            ZStack {
                forma.fill(voce.rosso ? Color(red: 80 / 255, green: 22 / 255, blue: 16 / 255).opacity(0.82)
                                      : Color(red: 10 / 255, green: 12 / 255, blue: 8 / 255).opacity(0.80))
                forma.stroke(voce.colore.opacity(0.55), lineWidth: 1.2 * k)
                IconaTela(d: voce.icona, colore: voce.colore, lato: 18 * k, spessore: 2.2)
                    .position(x: b.x, y: b.y - 9.35 * k)
                Text(voce.testo).font(.system(size: 9.5 * k, weight: .bold)).foregroundStyle(Theme.testo)
                    .multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.6)
                    .frame(width: larghezza)
                    .fixedSize(horizontal: false, vertical: true)
                    .position(x: b.x, y: b.y + 9.35 * k)
            }
            .contentShape(forma)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(voce.testo)
    }
}

/// Settore di corona circolare. Fessure tra gli spicchi: 1,5° per lato (tavola 12) oppure,
/// con `taglio`, a lati paralleli distanti `taglio` dall'asse della fessura (tavola 11).
struct SettoreAnello: Shape {
    let da: Double
    let a: Double
    let ri: CGFloat
    let ro: CGFloat
    let centro: CGPoint
    var taglio: CGFloat? = nil
    var gradi: Double = 1.5

    func path(in rect: CGRect) -> Path {
        func g(_ r: CGFloat) -> Double {
            guard let t = taglio, r > 0 else { return gradi }
            return asin(Double(min(t / r, 0.95))) * 180 / .pi
        }
        var p = Path()
        p.addArc(center: centro, radius: ro, startAngle: .degrees(da + g(ro)), endAngle: .degrees(a - g(ro)), clockwise: false)
        p.addArc(center: centro, radius: ri, startAngle: .degrees(a - g(ri)), endAngle: .degrees(da + g(ri)), clockwise: true)
        p.closeSubpath()
        return p
    }
}

/// Colonna accanto all'isola dinamica (tavola 10): ora e collegamento sopra l'isola, GPS, direzione e quota sotto.
struct InfoIsola: View {
    var spazioIsola = true
    @EnvironmentObject var location: LocationService
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var traccia = Traccia.shared
    private static let ora: DateFormatter = { let f = DateFormatter(); f.dateFormat = "H:mm"; return f }()

    var body: some View {
        let l = location.location
        let prova = Anteprima.mappaAttiva
        GeometryReader { g in
            let cx = g.size.width / 2, cy = g.size.height / 2
            ZStack {
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    Text(Self.ora.string(from: ctx.date)).font(Theme.mono(11, .heavy)).foregroundStyle(Theme.testo)
                }
                .position(x: cx, y: cy - 160)
                HStack(spacing: 5) {
                    Circle().fill(jsoc.online ? Theme.green : Theme.amber).frame(width: 7, height: 7)
                    Text(jsoc.online ? "ONLINE" : "OFFLINE").font(Theme.mono(9.5, .bold))
                        .foregroundStyle(jsoc.online ? Color(hex: 0x8FD18A) : Theme.amber)
                }
                .position(x: cx, y: cy - 142)
                if traccia.attiva {
                    Text("● REC").font(Theme.mono(9.5, .heavy)).foregroundStyle(Theme.red).position(x: cx, y: cy - 126)
                }
                if let l, l.horizontalAccuracy >= 0 {
                    Text(String(format: "GPS ±%.0f", l.horizontalAccuracy))
                        .foregroundStyle(l.horizontalAccuracy <= 10 ? Theme.dim : Theme.amber)
                        .position(x: cx, y: cy + 85)
                } else if prova {
                    Text("GPS ±6").foregroundStyle(Theme.dim).position(x: cx, y: cy + 85)
                }
                if let h = location.heading {
                    Text("\(gradi3(h - (location.declinazione ?? 4.6))) \(Mission.cardinale(h))").foregroundStyle(Theme.olive)
                        .position(x: cx, y: cy + 107)
                } else if prova {
                    Text("058° NE").foregroundStyle(Theme.olive).position(x: cx, y: cy + 107)
                }
                if let l, l.verticalAccuracy > 0, !prova {
                    Text(String(format: "%.0f m", l.altitude)).foregroundStyle(Theme.dim).position(x: cx, y: cy + 128)
                } else if prova {
                    Text("85 m").foregroundStyle(Theme.dim).position(x: cx, y: cy + 128)
                }
            }
            .font(Theme.mono(11, .heavy))
        }
        .lineLimit(1).minimumScaleFactor(0.6)
    }
}

/// Pulsanti della colonna sinistra (tavola 10): posizioni e misure della tela, 62×44 pt ciascuno.
struct ColonnaTela: View {
    let attivo: PannelloMappa?
    let notte: Bool
    var azione: (BarraStrumenti.Voce) -> Void
    @ObservedObject private var tx = Trasmissione.shared

    var body: some View {
        GeometryReader { g in
            let h = g.size.height
            let inOnda = tx.stato == .open
            ZStack(alignment: .top) {
                voce(.strumenti, Ic.griglia, "Strumenti", Theme.olive, on: attivo == .strumenti).offset(y: 6)
                Rectangle().fill(Theme.olive.opacity(0.3)).frame(width: 32, height: 1).offset(y: 55)
                voce(.segnala, Ic.mSegnala, "Segnala", Theme.amber, on: attivo == .segnala).offset(y: 61)
                voce(.squadra, Ic.mSquadra, "Squadra", Theme.cyan, on: attivo == .squadra).offset(y: 105)
                voce(.messaggi, Ic.mMessaggi, "Messaggi", Theme.olive, on: chatAperta).offset(y: 149)
                voce(.video, Ic.mVideo, inOnda ? "IN ONDA" : "Video", inOnda ? Theme.red : Theme.olive, on: videoAperto).offset(y: 193)
                voce(.notte, Ic.mNotte, "Notte", notte ? Night.red : Color(hex: 0xD9D9D2), on: notte).offset(y: 237)
                Button { azione(.impostazioni) } label: {
                    IconaTela(d: Ic.mIngranaggio, colore: attivo == .impostazioni ? Theme.oliveBright : Theme.testo, lato: 22)
                        .frame(width: 33, height: 33)
                        .background(attivo == .impostazioni ? Theme.olive.opacity(0.2) : .clear, in: Circle())
                        .frame(width: 62, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Impostazioni mappa")
                .offset(y: h - 89 - 5.5)
                voce(.esci, Ic.casa, "App", Theme.dim, on: false).offset(y: h - 50)
                    .accessibilityLabel("Torna all'app")
            }
            .frame(width: g.size.width, height: h, alignment: .top)
        }
    }

    var videoAperto: Bool {
        if case .video = attivo { return true }
        return false
    }
    var chatAperta: Bool {
        if case .chat = attivo { return true }
        return false
    }

    func voce(_ v: BarraStrumenti.Voce, _ icona: String, _ testo: String, _ colore: Color, on: Bool) -> some View {
        Button { azione(v) } label: {
            VStack(spacing: 3) {
                IconaTela(d: icona, colore: colore, lato: 20)
                Text(testo).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.testo)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(width: 62, height: 44)
            .background {
                if on { RoundedRectangle(cornerRadius: 10).fill(Theme.olive.opacity(0.2)).padding(.horizontal, 3) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

/// Fila in alto con gli strumenti scelti dal pannello Strumenti (tenendoli premuti).
/// Tavola 10: nove caselle 40×39 pt a 10 pt l'una dall'altra; quelle libere sono tratteggiate con il "+".
struct BarraRapida: View {
    static let caselle = 9
    @AppStorage("mappa.rapidi") private var rapidi = ""
    var usa: (Strumento) -> Void
    var aggiungi: () -> Void

    var body: some View {
        let lista = Array(rapidi.split(separator: ",").compactMap { Strumento(rawValue: String($0)) }.prefix(Self.caselle))
        HStack(spacing: 10) {
            ForEach(lista) { s in
                Button { haptic(); usa(s) } label: {
                    VStack(spacing: 2) {
                        Image(systemName: s.icona).font(.system(size: 14, weight: .bold)).foregroundStyle(s == .sos ? Theme.red : Theme.oliveBright)
                        Text(String(s.nome.split(separator: " ").first ?? "")).font(.system(size: 7.5, weight: .bold)).foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .padding(.horizontal, 2)
                    .frame(width: 40, height: 39)
                    .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.stroke))
                }
                .buttonStyle(PressStyle())
                .contextMenu {
                    Button(role: .destructive) { BarraRapida.togli(s) } label: { Label("Togli dalla barra", systemImage: "pin.slash") }
                }
            }
            ForEach(lista.count..<Self.caselle, id: \.self) { _ in
                Button { haptic(); aggiungi() } label: {
                    IconaTela(d: Ic.piu, colore: Theme.dim, lato: 13)
                        .frame(width: 40, height: 39)
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.olive.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Aggiungi strumento alla barra")
            }
        }
    }

    static var elenco: [String] {
        (UserDefaults.standard.string(forKey: "mappa.rapidi") ?? "").split(separator: ",").map(String.init)
    }
    static func contiene(_ s: Strumento) -> Bool { elenco.contains(s.rawValue) }
    static func metti(_ s: Strumento) {
        var e = elenco
        guard !e.contains(s.rawValue), e.count < caselle else { return }
        e.append(s.rawValue)
        UserDefaults.standard.set(e.joined(separator: ","), forKey: "mappa.rapidi")
    }
    static func togli(_ s: Strumento) {
        UserDefaults.standard.set(elenco.filter { $0 != s.rawValue }.joined(separator: ","), forKey: "mappa.rapidi")
    }
}


/// Livello della batteria del telefono, sopra l'ora.
struct Batteria: View {
    @State private var livello = Batteria.leggi()
    @State private var carica = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: carica ? "battery.100.bolt" : icona).font(.system(size: 11, weight: .semibold))
            Text("\(livello)%").font(Theme.mono(9.5, .heavy))
        }
        .foregroundStyle(livello <= 15 && !carica ? Theme.red : (livello <= 30 && !carica ? Theme.amber : Color.white))
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in livello = Self.leggi() }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
            carica = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
            livello = Self.leggi()
        }
    }

    var icona: String {
        switch livello {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    static func leggi() -> Int {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let l = UIDevice.current.batteryLevel
        return l < 0 ? 100 : Int((l * 100).rounded())
    }
}


/// Rettangolo con i soli angoli destri arrotondati (colonna laterale verso la mappa).
struct ArrotondatoDestra: Shape {
    var r: CGFloat
    func path(in q: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: q.minX, y: q.minY))
        p.addLine(to: CGPoint(x: q.maxX - r, y: q.minY))
        p.addArc(center: CGPoint(x: q.maxX - r, y: q.minY + r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: q.maxX, y: q.maxY - r))
        p.addArc(center: CGPoint(x: q.maxX - r, y: q.maxY - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: q.minX, y: q.maxY))
        p.closeSubpath()
        return p
    }
}


/// Riempie l'angolo della mappa accanto alla colonna nera lasciando un arco: la mappa sembra una finestra con gli angoli tondi.
struct AngoloInverso: Shape {
    var alto: Bool
    func path(in q: CGRect) -> Path {
        var p = Path()
        let r = q.width
        if alto {
            p.move(to: CGPoint(x: q.minX, y: q.minY))
            p.addLine(to: CGPoint(x: q.minX + r, y: q.minY))
            p.addArc(center: CGPoint(x: q.minX + r, y: q.minY + r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(180), clockwise: true)
        } else {
            p.move(to: CGPoint(x: q.minX, y: q.maxY))
            p.addLine(to: CGPoint(x: q.minX, y: q.maxY - r))
            p.addArc(center: CGPoint(x: q.minX + r, y: q.maxY - r), radius: r, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        }
        p.closeSubpath()
        return p
    }
}


/// Quale mappa sto guardando: la personale (campi dell'associazione, i miei livelli) o quella di un evento.
struct ChipContestoMappa: View {
    @ObservedObject private var store = EventoStore.shared

    var body: some View {
        Menu {
            Button { haptic(); store.apriPersonale() } label: { Label("Mappa personale · campi JSOC", systemImage: "person.fill") }
            let miei = store.eventi.filter { $0.membro && $0.fase != 2 && !$0.proposto }
            if !miei.isEmpty {
                Section("Mappe degli eventi") {
                    ForEach(miei) { e in
                        Button { haptic(); store.scegli(e) } label: { Label(e.nome, systemImage: e.icona) }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: store.corrente == nil ? "person.fill" : "calendar")
                Text(store.corrente?.nome.uppercased() ?? "PERSONALE").lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .heavy))
            }
            .font(Theme.mono(11, .heavy)).foregroundStyle(.white)
            .padding(.horizontal, 10).frame(height: 32).frame(maxWidth: 190)
            .background(Color.black.opacity(0.72), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.olive.opacity(0.5)))
        }
        .accessibilityLabel("Cambia mappa")
    }
}
