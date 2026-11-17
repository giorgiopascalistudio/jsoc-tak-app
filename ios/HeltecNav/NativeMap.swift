import SwiftUI
import MapKit
import CoreLocation

// MARK: - Dati per la mappa

extension Gara {
    /// Prefisso del fascicolo della biblioteca collegato a un punto (es. "FF08", "FF12", "1 ").
    static func fascicoloPrefix(_ p: GaraPoint) -> String? {
        let id = p.id.uppercased()
        if id.hasPrefix("RECON") || id.hasPrefix("WP ") { return "FF12" }
        if id.hasPrefix("HOTEL") || id.hasPrefix("PALAZZETTO") { return "1 " }
        if let r = id.range(of: #"(OBJ|INGRESSO( EST| OVEST)?|FF)\s?(\d+)"#, options: .regularExpression) {
            let num = id[r].components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }.last ?? 0
            return String(format: "FF%02d", num)
        }
        if id.hasPrefix("DELITTO") || id.hasPrefix("OSPEDALE") { return "FF01" }
        return nil
    }

    /// Percorso della squadra dal GPX della biblioteca (si aggiorna se cambia il file).
    static func percorsoGPX() -> [CLLocationCoordinate2D] {
        let url = DocStore.root.appendingPathComponent("0 Generale/3 Percorso/Op Re Mida.gpx")
        guard let data = try? Data(contentsOf: url) else { return [] }
        let p = GPXReader()
        let x = XMLParser(data: data)
        x.delegate = p
        x.parse()
        return p.punti
    }
}

final class GPXReader: NSObject, XMLParserDelegate {
    var punti: [CLLocationCoordinate2D] = []
    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?, qualifiedName: String?,
                attributes a: [String: String] = [:]) {
        guard el == "trkpt" || el == "rtept", let la = a["lat"].flatMap(Double.init), let lo = a["lon"].flatMap(Double.init) else { return }
        punti.append(.init(latitude: la, longitude: lo))
    }
}

extension DocStore {
    func fascicolo(prefix: String) -> Fascicolo? { fascicoli.first { $0.name.hasPrefix(prefix) } }
}

// MARK: - Scheda mappa (nativa + Google 3D)

struct MapTab: View {
    var body: some View {
        NavigationStack {
            MappaTattica()
                .toolbar(.hidden, for: .navigationBar)
                .toolbar(.hidden, for: .tabBar)
        }
    }
}

final class PuntoAnnotation: NSObject, MKAnnotation {
    let punto: GaraPoint
    let fatto: Bool
    var coordinate: CLLocationCoordinate2D { punto.coordinate }
    var title: String? { punto.id }
    init(_ p: GaraPoint, fatto: Bool) { punto = p; self.fatto = fatto }
}

/// Compagno di squadra sulla mappa (posizione dal server JSOC TAK).
final class CompagnoAnnotation: NSObject, MKAnnotation {
    let compagno: JCompagno
    var coordinate: CLLocationCoordinate2D { compagno.coordinate }
    var title: String? { compagno.callsign }
    var subtitle: String? {
        let m = Int(compagno.eta / 60)
        return m < 1 ? "adesso" : "\(m) min fa"
    }
    init(_ c: JCompagno) { compagno = c }
}

final class MapControl: ObservableObject {
    weak var map: MKMapView?
    @Published var tracking: MKUserTrackingMode = .none
    @Published var satellite = true
    @Published var tre_d = true
    /// Centro della mappa (per il mirino "punto qui").
    @Published var centro = CLLocationCoordinate2D(latitude: 43.99, longitude: 12.38)
    private var offline: CachedTileOverlay?
    private var proiettato: MKPointAnnotation?
    private var navLinea: MKPolyline?
    private var navCerchio: MKCircle?

    /// Linea bianca da me al punto e cerchio di 25 m attorno al punto.
    func aggiornaNav(me: CLLocationCoordinate2D?, target: GaraPoint?) {
        guard let map else { return }
        if let l = navLinea { map.removeOverlay(l); navLinea = nil }
        guard let t = target else {
            if let c = navCerchio { map.removeOverlay(c); navCerchio = nil }
            return
        }
        if navCerchio?.coordinate.latitude != t.lat || navCerchio?.coordinate.longitude != t.lon {
            if let c = navCerchio { map.removeOverlay(c) }
            let c = MKCircle(center: t.coordinate, radius: 25)
            c.title = "nav"
            map.addOverlay(c, level: .aboveLabels)
            navCerchio = c
        }
        if let me {
            let l = MKPolyline(coordinates: [me, t.coordinate], count: 2)
            l.title = "nav"
            map.addOverlay(l, level: .aboveLabels)
            navLinea = l
        }
    }

    /// Inquadra me e il punto insieme.
    func inquadra(_ a: CLLocationCoordinate2D?, _ b: CLLocationCoordinate2D) {
        guard let map else { return }
        if tracking != .none { map.setUserTrackingMode(.none, animated: false); tracking = .none }
        var r = MKMapRect(origin: MKMapPoint(b), size: MKMapSize(width: 1, height: 1))
        if let a { r = r.union(MKMapRect(origin: MKMapPoint(a), size: MKMapSize(width: 1, height: 1))) }
        let minimo = 300 * MKMapPointsPerMeterAtLatitude(b.latitude)
        if r.size.width < minimo { r = r.insetBy(dx: -(minimo - r.size.width) / 2, dy: 0) }
        if r.size.height < minimo { r = r.insetBy(dx: 0, dy: -(minimo - r.size.height) / 2) }
        map.setVisibleMapRect(r, edgePadding: .init(top: 70, left: 50, bottom: 50, right: 70), animated: true)
    }

    func applicaOffline(_ on: Bool) {
        guard let map else { return }
        if on, offline == nil {
            let o = CachedTileOverlay()
            map.insertOverlay(o, at: 0, level: .aboveRoads)
            offline = o
        } else if !on, let o = offline {
            map.removeOverlay(o)
            offline = nil
        }
    }

    func mostra(_ c: CLLocationCoordinate2D, titolo: String) {
        guard let map else { return }
        if let p = proiettato { map.removeAnnotation(p) }
        let a = MKPointAnnotation()
        a.coordinate = c
        a.title = titolo
        map.addAnnotation(a)
        proiettato = a
        map.setCenter(c, animated: true)
    }

    func centraSuDiMe() {
        guard let map else { return }
        let next: MKUserTrackingMode = tracking == .none ? .follow : (tracking == .follow ? .followWithHeading : .none)
        map.setUserTrackingMode(next, animated: true)
        tracking = next
    }

    func inquadraArea() {
        guard let map else { return }
        let ops = map.overlays.compactMap { $0 as? MKPolygon }.first { $0.title == "operativa" }
        if let r = ops?.boundingMapRect {
            map.setVisibleMapRect(r, edgePadding: .init(top: 90, left: 30, bottom: 120, right: 70), animated: true)
        }
    }

    func applicaStile() {
        guard let map else { return }
        if #available(iOS 16.0, *) {
            map.preferredConfiguration = satellite
                ? MKHybridMapConfiguration(elevationStyle: tre_d ? .realistic : .flat)
                : MKStandardMapConfiguration(elevationStyle: tre_d ? .realistic : .flat, emphasisStyle: .muted)
        }
        let cam = map.camera.copy() as! MKMapCamera
        cam.pitch = tre_d ? 55 : 0
        map.setCamera(cam, animated: true)
    }
}

struct EditorRichiesta: Identifiable {
    let id = UUID()
    var modifica: GaraPoint? = nil
    var coord: CLLocationCoordinate2D? = nil
    var scheda: PuntoEditor.Scheda = .utm
}

struct NativeMapScreen: View {
    @EnvironmentObject var location: LocationService
    @EnvironmentObject var mission: Mission
    @EnvironmentObject var log: FieldLog
    @StateObject private var ctl = MapControl()
    @ObservedObject private var tiles = OfflineTiles.shared
    @ObservedObject private var nav = NavStore.shared
    @ObservedObject private var store = EventoStore.shared
    @ObservedObject private var jsoc = JsocClient.shared
    @State private var scelto: GaraPoint?
    @State private var proiezione = false
    @State private var editor: EditorRichiesta?
    @State private var mirino = false
    @State private var mirinoPer: GaraPoint?
    @AppStorage("mappa.recon") private var mostraRecon = true
    @AppStorage("mappa.ipotesi") private var mostraIpotesi = true
    /// Quota di schermo della mappa in verticale e del cruscotto in orizzontale (si trascina il divisore).
    @AppStorage("nav.mappaV") private var mappaV = 0.5
    @AppStorage("nav.pannelloO") private var pannelloO = 0.46
    @State private var trascinaInizio: Double?

    var punti: [GaraPoint] {
        nav.tutti.filter { p in
            (mostraRecon || p.kind != .recon) && (mostraIpotesi || p.kind != .ipotesi)
        }
    }

    var body: some View {
        GeometryReader { g in
            let target = nav.target
            let land = g.size.width > g.size.height
            let panelW: CGFloat = target != nil && land ? g.size.width * CGFloat(pannelloO) : 0
            let mapH: CGFloat = target != nil && !land ? g.size.height * CGFloat(mappaV) : g.size.height
            ZStack(alignment: .topLeading) {
                mappa(land: land)
                    .frame(width: g.size.width - panelW, height: mapH)
                    .clipped()
                    .offset(x: panelW)
                if let t = target {
                    NavPanel(target: t, landscape: land,
                             onEdit: { editor = .init(modifica: t) },
                             onChange: { editor = .init(scheda: .cerca) })
                        .frame(width: land ? panelW : g.size.width, height: land ? g.size.height : g.size.height - mapH)
                        .background(Color.black.ignoresSafeArea(edges: land ? [.leading, .bottom] : [.bottom]))
                        .offset(y: land ? 0 : mapH)
                        .transition(.move(edge: land ? .leading : .bottom))
                    divisore(land: land, size: g.size)
                        .offset(x: land ? panelW - CGFloat(22) : g.size.width / 2 - CGFloat(30),
                                y: land ? g.size.height / 2 - CGFloat(30) : mapH - CGFloat(22))
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: scelto)
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: nav.target)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            if UserDefaults.standard.bool(forKey: "mappa.nuovoPunto") {
                UserDefaults.standard.set(false, forKey: "mappa.nuovoPunto")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { editor = .init(coord: location.location?.coordinate ?? ctl.centro) }
            }
            ctl.applicaOffline(tiles.usa)
            location.seguiOrientamento(nav.target != nil)
            ctl.aggiornaNav(me: location.location?.coordinate, target: nav.target)
            // solo per le anteprime dal simulatore: -debug.editor utm|cerca
            if let e = UserDefaults.standard.string(forKey: "debug.editor"), editor == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    editor = .init(coord: e == "utm" ? CLLocationCoordinate2D(latitude: 43.99427, longitude: 12.38523) : nil,
                                   scheda: e == "cerca" ? .cerca : .utm)
                }
            }
        }
        .onChange(of: tiles.usa) { ctl.applicaOffline($0) }
        .onChange(of: nav.target) { t in
            location.seguiOrientamento(t != nil)
            ctl.aggiornaNav(me: location.location?.coordinate, target: t)
            if let t {
                scelto = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ctl.inquadra(location.location?.coordinate, t.coordinate) }
            }
        }
        .onChange(of: location.location) { l in
            if nav.target != nil { ctl.aggiornaNav(me: l?.coordinate, target: nav.target) }
        }
        .sheet(isPresented: $proiezione) {
            ProiezioneSheet(origineScelta: scelto) { c, t in ctl.mostra(c, titolo: t) }
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $editor) { r in
            PuntoEditor(modifica: r.modifica, coordIniziale: r.coord, scheda: r.scheda) { m in
                mirinoPer = m
                withAnimation { mirino = true }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            location.seguiOrientamento(false)
        }
    }

    func mappa(land: Bool) -> some View {
        let navOn = nav.target != nil
        return ZStack(alignment: .topTrailing) {
            NativeMapView(ctl: ctl, punti: punti, fatti: mission.fatti, target: nav.target?.id,
                          compagni: store.squadra.filter { $0.id != jsoc.utente?.id }, firmaAree: DatiEvento.firma,
                          direzione: location.heading,
                          scelto: $scelto) { coord in
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                editor = .init(coord: coord)
            }
            .ignoresSafeArea(edges: navOn && land ? [.top, .trailing] : [.top, .horizontal])

            VStack(spacing: 10) {
                NightToolbarButton().background(.ultraThinMaterial, in: Circle())
                MapButton(icon: ctl.tracking == .followWithHeading ? "location.north.line.fill"
                          : (ctl.tracking == .follow ? "location.fill" : "location")) { ctl.centraSuDiMe() }
                MapButton(icon: "plus") { editor = .init(coord: ctl.centro) }
                if navOn {
                    MapButton(icon: "arrow.up.left.and.down.right.magnifyingglass") {
                        if let t = nav.target { ctl.inquadra(location.location?.coordinate, t.coordinate) }
                    }
                } else {
                    MapButton(icon: ctl.tre_d ? "view.3d" : "view.2d") { ctl.tre_d.toggle(); ctl.applicaStile() }
                    MapButton(icon: "scope") { ctl.inquadraArea() }
                    MapButton(icon: "plus.viewfinder") { proiezione = true }
                }
                Menu {
                    Button { ctl.satellite.toggle(); ctl.applicaStile() } label: {
                        Label(ctl.satellite ? "Mappa normale" : "Satellite", systemImage: ctl.satellite ? "map" : "globe.europe.africa.fill")
                    }
                    if navOn {
                        Button { ctl.tre_d.toggle(); ctl.applicaStile() } label: { Label(ctl.tre_d ? "Vista 2D" : "Vista 3D", systemImage: "view.3d") }
                        Button { proiezione = true } label: { Label("Proietta un punto", systemImage: "plus.viewfinder") }
                    }
                    Toggle("Recon e waypoint", isOn: $mostraRecon)
                    Toggle("Contatti e pericoli", isOn: $mostraIpotesi)
                    Section("Senza rete") {
                        Toggle("Satellite offline", isOn: $tiles.usa)
                        if tiles.running {
                            Button("Ferma download (\(tiles.done)/\(tiles.total))") { tiles.ferma() }
                        } else {
                            Button("Scarica mappe offline (~100 MB)") { tiles.scarica() }
                        }
                        Text(tiles.esito)
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease").mapButtonLook()
                }
            }
            .padding(.trailing, 12).padding(.top, navOn && land ? 12 : 54)

            if navOn {
                NavHUD()
                    .padding(.leading, 10).padding(.top, land ? 12 : 54)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            if mirino { mirinoView }

            VStack {
                Spacer()
                if tiles.running {
                    HStack(spacing: 10) {
                        ProgressView(value: Double(tiles.done), total: Double(max(1, tiles.total))).tint(Theme.olive)
                        Text("Mappe offline \(tiles.done)/\(tiles.total)").font(Theme.mono(11, .semibold))
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.horizontal, 60)
                }
                if let p = scelto, !mirino {
                    PuntoCard(punto: p, chiudi: { withAnimation(.spring()) { scelto = nil } },
                              modifica: { editor = .init(modifica: $0) })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.horizontal, 12).padding(.bottom, 10)
                        .frame(maxWidth: 520)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Mirino al centro della mappa per scegliere un punto spostando la mappa.
    var mirinoView: some View {
        let c = ctl.centro
        let me = location.location?.coordinate
        return ZStack {
            Image(systemName: "plus")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(Theme.amber)
                .shadow(color: .black, radius: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            VStack {
                Spacer()
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Coordinate.utmText(c)).font(Theme.mono(12, .heavy)).foregroundStyle(.white)
                        if let me {
                            Text("da te \(Geo.formatDistance(Geo.distance(me, c))) · az \(gradi3(Geo.bearing(me, c) - (location.declinazione ?? 4.6))) magn.")
                                .font(Theme.mono(10.5, .semibold)).foregroundStyle(Theme.dim)
                        } else {
                            Text("sposta la mappa sotto il mirino").font(Theme.mono(10.5, .semibold)).foregroundStyle(Theme.dim)
                        }
                    }
                    Spacer(minLength: 4)
                    Button("Annulla") { withAnimation { mirino = false } }
                        .buttonStyle(.bordered).tint(Theme.dim)
                    Button("Usa qui") {
                        withAnimation { mirino = false }
                        editor = .init(modifica: mirinoPer, coord: c)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.olive).foregroundStyle(.black)
                }
                .font(Theme.mono(12, .heavy))
                .padding(12)
                .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.olive))
                .padding(.horizontal, 10).padding(.bottom, 10)
            }
        }
    }

    /// Maniglia per dare più spazio alla mappa o al cruscotto.
    func divisore(land: Bool, size: CGSize) -> some View {
        Capsule().fill(Color(red: 0.31, green: 0.35, blue: 0.24))
            .frame(width: land ? 5 : 44, height: land ? 44 : 5)
            .frame(width: land ? 44 : 60, height: land ? 60 : 44)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { v in
                        if trascinaInizio == nil { trascinaInizio = land ? pannelloO : mappaV }
                        let base = trascinaInizio ?? 0.5
                        if land { pannelloO = min(0.62, max(0.36, base + v.translation.width / size.width)) }
                        else { mappaV = min(0.72, max(0.3, base + v.translation.height / size.height)) }
                    }
                    .onEnded { _ in trascinaInizio = nil; haptic() }
            )
    }
}

struct MapButton: View {
    let icon: String
    let action: () -> Void
    var body: some View {
        Button { haptic(); action() } label: { Image(systemName: icon).mapButtonLook() }
            .buttonStyle(PressStyle())
    }
}

extension Image {
    func mapButtonLook() -> some View {
        self.font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.olive)
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 0.75))
    }
}

/// Scheda del punto toccato: distanza, direzione, UTM, nota e collegamento al fascicolo.
struct PuntoCard: View {
    let punto: GaraPoint
    var chiudi: () -> Void
    var modifica: ((GaraPoint) -> Void)? = nil
    @EnvironmentObject var location: LocationService
    @EnvironmentObject var docs: DocStore

    var body: some View {
        let u = UTM.fromLatLon(punto.lat, punto.lon)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Circle().fill(punto.color).frame(width: 10, height: 10).padding(.top, 5)
                Text(punto.id).font(.headline)
                Spacer()
                Button(action: chiudi) { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(Theme.dim) }
            }
            if let me = location.location?.coordinate {
                let d = Geo.distance(me, punto.coordinate), b = Geo.bearing(me, punto.coordinate)
                HStack(spacing: 14) {
                    Label(Geo.formatDistance(d), systemImage: "ruler").font(Theme.mono(14, .bold))
                    Label(Mission.cardinale(b) + String(format: " %.0f°", b), systemImage: "location.north.line")
                        .font(Theme.mono(14, .bold))
                }
                .foregroundStyle(Theme.olive)
            }
            Text(u.text).font(Theme.mono(13)).foregroundStyle(Theme.dim).textSelection(.enabled)
            Text(punto.note).font(.caption).foregroundStyle(.white.opacity(0.85)).lineLimit(5)
            HStack {
                if let pre = Gara.fascicoloPrefix(punto), let f = docs.fascicolo(prefix: pre) {
                    NavigationLink { FascicoloView(name: f.name) } label: {
                        Label("Fascicolo", systemImage: "folder.fill")
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.olive).foregroundStyle(.black)
                }
                Button { copyToClipboard(u.text) } label: { Label("UTM", systemImage: "doc.on.doc") }
                    .buttonStyle(.bordered).tint(Theme.olive)
                if let modifica {
                    Button { modifica(punto) } label: { Label("Modifica", systemImage: "pencil") }
                        .buttonStyle(.bordered).tint(Theme.olive)
                }
                Button {
                    haptic(.medium)
                    NavStore.shared.target = punto
                } label: { Label("Naviga", systemImage: "location.north.line.fill") }
                    .buttonStyle(.borderedProminent).tint(Theme.olive).foregroundStyle(.black)
                    .contextMenu {
                        Button {
                            let item = MKMapItem(placemark: MKPlacemark(coordinate: punto.coordinate))
                            item.name = punto.id
                            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                        } label: { Label("Apri in Mappe di Apple", systemImage: "map") }
                    }
            }
            .font(.caption.weight(.semibold))
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 0.75))
    }
}

// MARK: - MKMapView

struct NativeMapView: UIViewRepresentable {
    @ObservedObject var ctl: MapControl
    let punti: [GaraPoint]
    let fatti: Set<String>
    var target: String? = nil
    var compagni: [JCompagno] = []
    var firmaAree: String = ""
    var direzione: Double? = nil
    @Binding var scelto: GaraPoint?
    var onLongPress: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coord { Coord(self) }

    func makeUIView(context: Context) -> MKMapView {
        let m = MKMapView()
        m.delegate = context.coordinator
        m.showsUserLocation = true
        m.showsCompass = true
        m.showsScale = true
        m.pointOfInterestFilter = .excludingAll
        m.overrideUserInterfaceStyle = .dark
        m.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "p")
        ctl.map = m
        ctl.applicaStile()
        context.coordinator.aggiornaAree(m)
        // percorso della squadra
        let route = Gara.percorsoGPX()
        if route.count > 1 {
            let line = MKPolyline(coordinates: route, count: route.count)
            line.title = "percorso"
            m.addOverlay(line, level: .aboveLabels)
        }
        context.coordinator.aggiornaPunti(m)
        DispatchQueue.main.async { ctl.inquadraArea() }
        let lp = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coord.lungo(_:)))
        lp.minimumPressDuration = 0.6
        m.addGestureRecognizer(lp)
        return m
    }

    func updateUIView(_ m: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.aggiornaPunti(m)
        context.coordinator.aggiornaAree(m)
        context.coordinator.aggiornaCompagni(m)
        if let v = m.view(for: m.userLocation) as? DirezioneView {
            v.rotazioneMappa = m.camera.heading
            v.direzione = direzione
        }
    }

    final class Coord: NSObject, MKMapViewDelegate {
        var parent: NativeMapView
        private var firma = ""
        private var firmaAree: String?
        private var firmaCompagni = ""
        init(_ p: NativeMapView) { parent = p }

        /// Aree dell'evento: si ridisegnano quando cambia l'evento o arrivano aree nuove.
        func aggiornaAree(_ m: MKMapView) {
            guard firmaAree != parent.firmaAree else { return }
            let primaVolta = firmaAree == nil
            firmaAree = parent.firmaAree
            m.removeOverlays(m.overlays.filter { $0 is MKPolygon })
            for a in Gara.areas where a.coordinates.count >= 3 {
                let poly = MKPolygon(coordinates: a.coordinates, count: a.coordinates.count)
                poly.title = a.tipo
                m.addOverlay(poly)
            }
            if !primaVolta { DispatchQueue.main.async { self.parent.ctl.inquadraArea() } }
        }

        func aggiornaCompagni(_ m: MKMapView) {
            let f = parent.compagni.map { "\($0.id)\($0.lat)\($0.lon)\(Int($0.ts))" }.joined()
            guard f != firmaCompagni else { return }
            firmaCompagni = f
            m.removeAnnotations(m.annotations.filter { $0 is CompagnoAnnotation })
            m.addAnnotations(parent.compagni.map { CompagnoAnnotation($0) })
        }

        func aggiornaPunti(_ m: MKMapView) {
            let f = parent.punti.map { "\($0.id)\($0.lat)\($0.lon)" }.joined() + parent.fatti.sorted().joined() + (parent.target ?? "")
            guard f != firma else { return }
            firma = f
            m.removeAnnotations(m.annotations.filter { $0 is PuntoAnnotation })
            let codiceFatto = { (p: GaraPoint) -> Bool in
                guard p.kind == .obj, let c = Gara.fascicoloPrefix(p) else { return false }
                return self.parent.fatti.contains(c)
            }
            m.addAnnotations(parent.punti.map { PuntoAnnotation($0, fatto: codiceFatto($0)) })
        }

        @objc func lungo(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let m = g.view as? MKMapView else { return }
            parent.onLongPress(m.convert(g.location(in: m), toCoordinateFrom: m))
        }

        func mapView(_ m: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let p = annotation as? MKPointAnnotation {
                let v = MKMarkerAnnotationView(annotation: p, reuseIdentifier: "proiettato")
                v.markerTintColor = .systemOrange
                v.glyphImage = UIImage(systemName: "scope")
                v.titleVisibility = .visible
                return v
            }
            if annotation is MKUserLocation {
                let v = (m.dequeueReusableAnnotationView(withIdentifier: DirezioneView.idIo) as? DirezioneView)
                    ?? DirezioneView(annotation: annotation, reuseIdentifier: DirezioneView.idIo)
                v.annotation = annotation
                v.configura(io: true, colore: UIColor(red: 0.20, green: 0.55, blue: 1.0, alpha: 1), testo: nil,
                            direzione: parent.direzione, rotazioneMappa: m.camera.heading)
                v.canShowCallout = false
                return v
            }
            if let c = annotation as? CompagnoAnnotation {
                let v = (m.dequeueReusableAnnotationView(withIdentifier: DirezioneView.idCompagno) as? DirezioneView)
                    ?? DirezioneView(annotation: c, reuseIdentifier: DirezioneView.idCompagno)
                v.annotation = c
                let vecchio = c.compagno.eta > 300
                // direzione: bussola se c'e', altrimenti la rotta di marcia
                let dir = c.compagno.dir ?? ((c.compagno.vel ?? 0) > 0.5 ? c.compagno.rotta : nil)
                v.configura(io: false, colore: vecchio ? .gray : UIColor(Theme.cyan), testo: c.compagno.callsign,
                            direzione: vecchio ? nil : dir, rotazioneMappa: m.camera.heading)
                v.canShowCallout = true
                return v
            }
            guard let a = annotation as? PuntoAnnotation else { return nil }
            let v = m.dequeueReusableAnnotationView(withIdentifier: "p", for: a) as! MKMarkerAnnotationView
            v.markerTintColor = a.fatto ? .gray : UIColor(a.punto.color)
            v.glyphText = glifo(a.punto)
            let attivo = a.punto.id == parent.target
            v.titleVisibility = a.punto.kind == .obj || a.punto.kind == .mio || attivo ? .visible : .adaptive
            v.displayPriority = a.punto.kind == .obj || attivo ? .required : .defaultHigh
            if attivo { v.markerTintColor = UIColor(Theme.oliveBright) }
            return v
        }

        func glifo(_ p: GaraPoint) -> String? {
            if p.kind == .obj || p.id.hasPrefix("INGRESSO"), let c = Gara.fascicoloPrefix(p) {
                return p.id.hasPrefix("INGRESSO") ? "IN" : String(Int(c.dropFirst(2)) ?? 0)
            }
            if p.id.hasPrefix("RECON") { return "R" + (p.id.last.map(String.init) ?? "") }
            if p.kind == .mio { return "★" }
            if p.id.hasPrefix("WP") { return "W" + (p.id.last.map(String.init) ?? "") }
            switch p.kind {
            case .hotel: return "H"
            case .acqua: return "≈"
            default: return nil
            }
        }

        func mapView(_ m: MKMapView, didSelect view: MKAnnotationView) {
            guard let a = view.annotation as? PuntoAnnotation else { return }
            haptic()
            parent.scelto = a.punto
            m.deselectAnnotation(a, animated: false)
        }

        func mapViewDidChangeVisibleRegion(_ m: MKMapView) {
            // le frecce restano giuste anche quando la mappa ruota
            let h = m.camera.heading
            for a in m.annotations {
                if let v = m.view(for: a) as? DirezioneView, abs(v.rotazioneMappa - h) > 0.5 { v.rotazioneMappa = h }
            }
            let c = m.centerCoordinate
            DispatchQueue.main.async { self.parent.ctl.centro = c }
        }

        func mapView(_ m: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
            DispatchQueue.main.async { self.parent.ctl.tracking = mode }
        }

        func mapView(_ m: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let t = overlay as? MKTileOverlay { return MKTileOverlayRenderer(tileOverlay: t) }
            let olive = UIColor(red: 0.604, green: 0.682, blue: 0.357, alpha: 1)
            if let c = overlay as? MKCircle {
                let r = MKCircleRenderer(circle: c)
                r.fillColor = UIColor(Theme.oliveBright).withAlphaComponent(0.14)
                r.strokeColor = UIColor(Theme.oliveBright)
                r.lineWidth = 1.5
                r.lineDashPattern = [4, 4]
                return r
            }
            if let l = overlay as? MKPolyline, l.title == "nav" {
                let r = MKPolylineRenderer(polyline: l)
                r.strokeColor = .white
                r.lineWidth = 3
                r.lineCap = .round
                return r
            }
            if let p = overlay as? MKPolygon {
                let r = MKPolygonRenderer(polygon: p)
                if p.title == "interdetta" {
                    r.fillColor = UIColor.systemRed.withAlphaComponent(0.28)
                    r.strokeColor = UIColor.systemRed.withAlphaComponent(0.9)
                    r.lineWidth = 1.5
                } else {
                    r.fillColor = olive.withAlphaComponent(0.06)
                    r.strokeColor = olive
                    r.lineWidth = 2
                    r.lineDashPattern = [8, 5]
                }
                return r
            }
            if let l = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: l)
                r.strokeColor = UIColor(red: 1.0, green: 0.55, blue: 0.15, alpha: 0.95)
                r.lineWidth = 3.5
                r.lineCap = .round
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
