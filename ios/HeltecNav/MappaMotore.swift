import SwiftUI
import MapLibre
import CoreLocation
import MapKit

// MARK: - Stili della mappa (fonti libere, raster)

enum StileMappa: String, CaseIterable, Identifiable {
    case topoScuro, topoChiaro, satellite, ibrida, apple, appleSat
    var id: String { rawValue }
    /// stili disegnati da Apple (MapKit): edifici e terreno 3D, solo con la rete
    var apple: Bool { self == .apple || self == .appleSat }

    var nome: String {
        switch self {
        case .topoScuro: return "Topo scura"
        case .topoChiaro: return "Topo chiara"
        case .satellite: return "Satellite"
        case .ibrida: return "Ibrida"
        case .apple: return "Apple 3D"
        case .appleSat: return "Apple satellite 3D"
        }
    }
    var icona: String {
        switch self {
        case .topoScuro: return "mountain.2.fill"
        case .topoChiaro: return "mountain.2"
        case .satellite: return "globe.europe.africa.fill"
        case .ibrida: return "square.stack.3d.up.fill"
        case .apple: return "building.2.fill"
        case .appleSat: return "building.2.crop.circle.fill"
        }
    }
    var successivo: StileMappa {
        let t = Self.allCases
        return t[(t.firstIndex(of: self)! + 1) % t.count]
    }

    private static let topo = "https://tile.opentopomap.org/{z}/{x}/{y}.png"
    private static let esri = "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
    private static let nomi = "https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}"

    /// Stile MapLibre (JSON) salvato su file: serve un indirizzo anche per le mappe offline.
    var url: URL {
        let f = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("stili", isDirectory: true)
        try? FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        let u = f.appendingPathComponent("\(rawValue).json")
        try? json.data(using: .utf8)?.write(to: u, options: .atomic)
        return u
    }

    private func sorgente(_ id: String, _ tiles: String, max: Int, attr: String) -> String {
        """
        "\(id)": {"type": "raster", "tiles": ["\(tiles)"], "tileSize": 256, "maxzoom": \(max), "attribution": "\(attr)"}
        """
    }

    var json: String {
        let attrTopo = "© OpenStreetMap, SRTM · stile © OpenTopoMap (CC-BY-SA)"
        let attrEsri = "Esri, Maxar, Earthstar Geographics"
        var sorgenti: [String] = []
        var livelli: [String] = [##"{"id": "fondo", "type": "background", "paint": {"background-color": "#10140c"}}"##]
        switch self {
        case .topoScuro:
            sorgenti.append(sorgente("topo", Self.topo, max: 17, attr: attrTopo))
            // scurita e virata verso l'oliva per stare con il resto dell'app
            livelli.append(#"{"id": "topo", "type": "raster", "source": "topo", "paint": {"raster-brightness-min": 0.92, "raster-brightness-max": 0.06, "raster-hue-rotate": 180, "raster-saturation": -0.35, "raster-contrast": 0.12}}"#)
        case .topoChiaro, .apple, .appleSat:
            sorgenti.append(sorgente("topo", Self.topo, max: 17, attr: attrTopo))
            livelli.append(#"{"id": "topo", "type": "raster", "source": "topo"}"#)
        case .satellite:
            sorgenti.append(sorgente("sat", Self.esri, max: 19, attr: attrEsri))
            livelli.append(#"{"id": "sat", "type": "raster", "source": "sat"}"#)
        case .ibrida:
            sorgenti.append(sorgente("sat", Self.esri, max: 19, attr: attrEsri))
            sorgenti.append(sorgente("nomi", Self.nomi, max: 19, attr: attrEsri))
            livelli.append(#"{"id": "sat", "type": "raster", "source": "sat"}"#)
            livelli.append(#"{"id": "nomi", "type": "raster", "source": "nomi"}"#)
        }
        return """
        {"version": 8, "name": "\(nome)", "sources": {\(sorgenti.joined(separator: ","))}, "layers": [\(livelli.joined(separator: ","))]}
        """
    }
}

// MARK: - Controllo della mappa

@MainActor
final class MappaCtl: ObservableObject {
    weak var mappa: MLNMapView?
    /// mappa Apple quando lo stile è Apple 3D
    weak var mk: MKMapView?
    /// cambia a ogni movimento della mappa: le sovrapposizioni SwiftUI si ridisegnano
    @Published var giro = 0
    @Published var stile: StileMappa = StileMappa(rawValue: UserDefaults.standard.string(forKey: "mappa.stile") ?? "") ?? .topoScuro {
        didSet {
            UserDefaults.standard.set(stile.rawValue, forKey: "mappa.stile")
            if stile.apple { configuraApple() } else { mappa?.styleURL = stile.url }
        }
    }
    /// nessuno · segue me col nord in alto · segue me orientata sulla direzione (come ATAK North Up / Track Up)
    @Published var modo: MLNUserTrackingMode = .none
    var segui: Bool { modo != .none }
    var segni: [SegnoMappa] = []
    var voleRilievo = true
    var voleRadar: String?
    var immaginiFatte = Set<String>()
    @Published var tre_d = false
    @Published var rotazione: Double = 0
    @Published var zoom: Double = 14
    @Published var centro = CLLocationCoordinate2D(latitude: 41.9, longitude: 12.5)
    @Published var offline: (fatti: Int, totale: Int)?
    @Published var esitoOffline = UserDefaults.standard.string(forKey: "mappa.offline.esito") ?? ""

    func punto(_ c: CLLocationCoordinate2D) -> CGPoint? {
        if let k = mk { return k.convert(c, toPointTo: k) }
        guard let m = mappa else { return nil }
        return m.convert(c, toPointTo: m)
    }
    func coordinata(_ p: CGPoint) -> CLLocationCoordinate2D? {
        if let k = mk { return k.convert(p, toCoordinateFrom: k) }
        guard let m = mappa else { return nil }
        return m.convert(p, toCoordinateFrom: m)
    }
    var metriPerPunto: Double {
        if let k = mk, k.bounds.width > 0 {
            return k.visibleMapRect.size.width / Double(k.bounds.width) / MKMapPointsPerMeterAtLatitude(k.centerCoordinate.latitude)
        }
        guard let m = mappa else { return 10 }
        return m.metersPerPoint(atLatitude: m.centerCoordinate.latitude)
    }

    func vai(_ c: CLLocationCoordinate2D, zoom z: Double? = nil) {
        if let k = mk {
            if k.userTrackingMode != .none { k.setUserTrackingMode(.none, animated: false); modo = .none }
            let lato = max(150, 40_075_016 * cos(c.latitude * .pi / 180) / pow(2, z ?? max(zoom, 16)) * Double(k.bounds.width) / 256)
            let cam = MKMapCamera(lookingAtCenter: c, fromDistance: lato * 1.4, pitch: tre_d ? 60 : 0, heading: k.camera.heading)
            k.setCamera(cam, animated: true)
            return
        }
        guard let m = mappa else { return }
        if modo != .none { m.setUserTrackingMode(.none, animated: false); modo = .none }
        m.setCenter(c, zoomLevel: z ?? max(m.zoomLevel, 15), animated: true)
    }

    func inquadra(_ punti: [CLLocationCoordinate2D], margine: UIEdgeInsets = UIEdgeInsets(top: 60, left: 50, bottom: 60, right: 50)) {
        if let k = mk, !punti.isEmpty {
            var r = MKMapRect.null
            for p in punti { r = r.union(MKMapRect(origin: MKMapPoint(p), size: MKMapSize(width: 1, height: 1))) }
            k.setVisibleMapRect(r, edgePadding: margine, animated: true)
            return
        }
        guard let m = mappa, !punti.isEmpty else { return }
        if modo != .none { m.setUserTrackingMode(.none, animated: false); modo = .none }
        if punti.count == 1 { vai(punti[0]); return }
        var sw = punti[0], ne = punti[0]
        for p in punti {
            sw.latitude = min(sw.latitude, p.latitude); sw.longitude = min(sw.longitude, p.longitude)
            ne.latitude = max(ne.latitude, p.latitude); ne.longitude = max(ne.longitude, p.longitude)
        }
        let cam = m.cameraThatFitsCoordinateBounds(MLNCoordinateBounds(sw: sw, ne: ne), edgePadding: margine)
        m.setCamera(cam, animated: true)
    }

    func nordInAlto() {
        if let k = mk { let c = k.camera.copy() as! MKMapCamera; c.heading = 0; k.setCamera(c, animated: true); return }
        mappa?.setDirection(0, animated: true)
    }

    /// La parte di mappa coperta da barre e pannelli non conta: centro, "segui" e inquadrature usano solo quella visibile.
    func margini(_ vista: CGRect, _ schermo: CGSize) {
        guard let m = mappa else { return }
        let ins = UIEdgeInsets(top: vista.minY, left: vista.minX,
                               bottom: max(0, schermo.height - vista.maxY), right: max(0, schermo.width - vista.maxX))
        if m.contentInset != ins { m.setContentInset(ins, animated: true, completionHandler: nil) }
    }

    func cambiaTreD() {
        if let k = mk {
            tre_d.toggle()
            let c = k.camera.copy() as! MKMapCamera
            c.pitch = tre_d ? 60 : 0
            k.setCamera(c, animated: true)
            return
        }
        guard let m = mappa else { return }
        tre_d.toggle()
        let cam = m.camera
        cam.pitch = tre_d ? 55 : 0
        m.setCamera(cam, animated: true)
    }

    func seguiMe(_ c: CLLocationCoordinate2D?) { cicloModo() }

    /// Tasto in basso a destra: libera → segue (nord in alto) → segue orientata sulla direzione → libera.
    func cicloModo() {
        if let k = mk {
            let nuovo: MKUserTrackingMode = k.userTrackingMode == .none ? .follow : (k.userTrackingMode == .follow ? .followWithHeading : .none)
            k.setUserTrackingMode(nuovo, animated: true)
            modo = nuovo == .follow ? .follow : (nuovo == .followWithHeading ? .followWithHeading : .none)
            return
        }
        guard let m = mappa else { return }
        let nuovo: MLNUserTrackingMode = modo == .none ? .follow : (modo == .follow ? .followWithHeading : .none)
        if nuovo != .none, m.zoomLevel < 14 { m.setZoomLevel(15, animated: false) }
        m.setUserTrackingMode(nuovo, animated: true, completionHandler: nil)
        modo = nuovo
    }

    func aggiornaDaMappa() {
        if let k = mk {
            giro &+= 1
            rotazione = k.camera.heading
            zoom = log2(MKMapSize.world.width / max(k.visibleMapRect.size.width, 1) * Double(k.bounds.width) / 256)
            centro = k.centerCoordinate
            return
        }
        guard let m = mappa else { return }
        giro &+= 1
        rotazione = m.direction
        zoom = m.zoomLevel
        centro = m.centerCoordinate
    }

    // MARK: mappe offline

    /// Scarica lo stile attuale attorno ai punti dati (margine 2 km), zoom 10-17.
    func scaricaZona(_ punti: [CLLocationCoordinate2D]) {
        guard !stile.apple else { esitoOffline = "La mappa Apple non si può scaricare: scegli una topo o il satellite"; return }
        guard !punti.isEmpty else { esitoOffline = "Nessun punto dell'evento da scaricare"; return }
        var sw = punti[0], ne = punti[0]
        for p in punti {
            sw.latitude = min(sw.latitude, p.latitude); sw.longitude = min(sw.longitude, p.longitude)
            ne.latitude = max(ne.latitude, p.latitude); ne.longitude = max(ne.longitude, p.longitude)
        }
        let dLat = 2000 / 111_000.0, dLon = 2000 / (111_000.0 * cos(sw.latitude * .pi / 180))
        sw.latitude -= dLat; sw.longitude -= dLon; ne.latitude += dLat; ne.longitude += dLon
        let regione = MLNTilePyramidOfflineRegion(styleURL: stile.url, bounds: MLNCoordinateBounds(sw: sw, ne: ne),
                                                  fromZoomLevel: 10, toZoomLevel: stile == .topoScuro || stile == .topoChiaro ? 17 : 18)
        let ctx = Data("\(stile.nome) · \(Date().formatted(date: .abbreviated, time: .shortened))".utf8)
        offline = (0, 1)
        MLNOfflineStorage.shared.addPack(for: regione, withContext: ctx) { [weak self] pack, errore in
            Task { @MainActor in
                guard let self else { return }
                if let errore { self.offline = nil; self.esitoOffline = "Errore: \(errore.localizedDescription)"; return }
                pack?.resume()
            }
        }
    }

    func avvioOffline() {
        NotificationCenter.default.addObserver(forName: NSNotification.Name.MLNOfflinePackProgressChanged, object: nil, queue: .main) { [weak self] n in
            guard let pack = n.object as? MLNOfflinePack else { return }
            let p = pack.progress
            Task { @MainActor in
                guard let self else { return }
                if pack.state == .complete {
                    self.offline = nil
                    let mb = Double(p.countOfBytesCompleted) / 1_048_576
                    self.esitoOffline = String(format: "Zona scaricata · %d tessere · %.0f MB", p.countOfResourcesCompleted, mb)
                    UserDefaults.standard.set(self.esitoOffline, forKey: "mappa.offline.esito")
                } else {
                    self.offline = (Int(p.countOfResourcesCompleted), Int(max(p.countOfResourcesExpected, 1)))
                }
            }
        }
    }
}

// MARK: - Vista MapLibre

struct MappaLibre: UIViewRepresentable {
    @ObservedObject var ctl: MappaCtl
    var tocco: (CGPoint, CLLocationCoordinate2D) -> Void
    var mira: (UIGestureRecognizer.State, CGPoint) -> Void

    func makeCoordinator() -> Coord { Coord(self) }

    func makeUIView(context: Context) -> MLNMapView {
        let m = MLNMapView(frame: .zero, styleURL: ctl.stile.url)
        m.delegate = context.coordinator
        m.showsUserLocation = true
        m.showsUserHeadingIndicator = true
        m.tintColor = UIColor(red: 0.2, green: 0.55, blue: 1, alpha: 1)
        m.compassView.isHidden = true
        m.logoView.isHidden = true
        m.attributionButtonPosition = .bottomLeft
        m.attributionButton.tintColor = UIColor(white: 0.7, alpha: 0.6)
        m.maximumZoomLevel = 19
        m.backgroundColor = UIColor(red: 0.063, green: 0.078, blue: 0.047, alpha: 1)
        let ultimo = UserDefaults.standard.array(forKey: "mappa.centro") as? [Double]
        let c = ultimo.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) } ?? CLLocationCoordinate2D(latitude: 41.9, longitude: 12.5)
        m.setCenter(c, zoomLevel: ultimo?.count == 3 ? ultimo![2] : 6, animated: false)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coord.tocca(_:)))
        for g in m.gestureRecognizers ?? [] where (g as? UITapGestureRecognizer)?.numberOfTapsRequired == 2 { tap.require(toFail: g) }
        m.addGestureRecognizer(tap)
        let lp = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coord.premi(_:)))
        lp.minimumPressDuration = 0.55
        m.addGestureRecognizer(lp)
        ctl.mappa = m
        ctl.avvioOffline()
        return m
    }

    func updateUIView(_ m: MLNMapView, context: Context) { context.coordinator.parent = self }

    final class Coord: NSObject, MLNMapViewDelegate {
        var parent: MappaLibre
        init(_ p: MappaLibre) { parent = p }

        @objc func tocca(_ g: UITapGestureRecognizer) {
            guard let m = g.view as? MLNMapView else { return }
            let p = g.location(in: m)
            parent.tocco(p, m.convert(p, toCoordinateFrom: m))
        }
        @objc func premi(_ g: UILongPressGestureRecognizer) {
            guard let m = g.view as? MLNMapView else { return }
            // mentre si mira la mappa sta ferma
            m.isScrollEnabled = !(g.state == .began || g.state == .changed)
            parent.mira(g.state, g.location(in: m))
        }

        func mapViewRegionIsChanging(_ m: MLNMapView) {
            Task { @MainActor in self.parent.ctl.aggiornaDaMappa() }
        }
        func mapView(_ m: MLNMapView, regionDidChangeAnimated animated: Bool) {
            let c = m.centerCoordinate, z = m.zoomLevel
            UserDefaults.standard.set([c.latitude, c.longitude, z], forKey: "mappa.centro")
            Task { @MainActor in self.parent.ctl.aggiornaDaMappa() }
        }
        func mapView(_ m: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            annotation is MLNUserLocation ? ConoUtente() : nil
        }
        func mapView(_ m: MLNMapView, didChange mode: MLNUserTrackingMode, animated: Bool) {
            Task { @MainActor in self.parent.ctl.modo = mode }
        }
        func mapView(_ m: MLNMapView, didFinishLoading style: MLNStyle) {
            Task { @MainActor in
                self.parent.ctl.immaginiFatte = []
                MappeImportate.shared.applica(m)
                self.parent.ctl.livelliExtra(rilievo: self.parent.ctl.voleRilievo, radar: self.parent.ctl.voleRadar)
                self.parent.ctl.applicaSegni()
                self.parent.ctl.aggiornaDaMappa()
            }
        }
    }
}

// MARK: - La mia posizione: pallino blu con il cono di visuale (dove punta il telefono)

final class ConoUtente: MLNUserLocationAnnotationView {
    private let precisione = CAShapeLayer()
    private let cono = CAGradientLayer()
    private let maschera = CAShapeLayer()
    private let punto = CAShapeLayer()
    private let lato: CGFloat = 150
    private let blu = UIColor(red: 0.2, green: 0.55, blue: 1, alpha: 1)

    override func update() {
        if frame.width != lato {
            frame = CGRect(x: 0, y: 0, width: lato, height: lato)
            costruisci()
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let c = CGPoint(x: lato / 2, y: lato / 2)
        // cerchio della precisione GPS (in metri, alla scala della mappa)
        if let m = mapView, let l = userLocation?.location, l.horizontalAccuracy > 0 {
            let r = min(lato / 2, max(10, CGFloat(l.horizontalAccuracy / m.metersPerPoint(atLatitude: l.coordinate.latitude))))
            precisione.path = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)).cgPath
        }
        // cono: direzione della bussola meno la rotazione della mappa
        if let h = userLocation?.heading, h.headingAccuracy >= 0 {
            let gradi = (h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading) - (mapView?.direction ?? 0)
            cono.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(gradi * .pi / 180)))
            cono.opacity = 1
        } else {
            cono.opacity = 0
        }
        CATransaction.commit()
    }

    private func costruisci() {
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        let b = CGRect(x: 0, y: 0, width: lato, height: lato)
        let c = CGPoint(x: lato / 2, y: lato / 2)
        precisione.frame = b
        precisione.fillColor = blu.withAlphaComponent(0.12).cgColor
        precisione.strokeColor = blu.withAlphaComponent(0.35).cgColor
        precisione.lineWidth = 1
        layer.addSublayer(precisione)

        cono.frame = b
        cono.type = .radial
        cono.colors = [blu.withAlphaComponent(0.8).cgColor, blu.withAlphaComponent(0).cgColor]
        cono.startPoint = CGPoint(x: 0.5, y: 0.5)
        cono.endPoint = CGPoint(x: 1, y: 1)
        let p = UIBezierPath()
        p.move(to: c)
        p.addArc(withCenter: c, radius: lato / 2 - 4, startAngle: CGFloat(-125 * Double.pi / 180), endAngle: CGFloat(-55 * Double.pi / 180), clockwise: true)
        p.close()
        maschera.frame = b
        maschera.path = p.cgPath
        cono.mask = maschera
        layer.addSublayer(cono)

        punto.frame = b
        punto.path = UIBezierPath(ovalIn: CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18)).cgPath
        punto.fillColor = blu.cgColor
        punto.strokeColor = UIColor.white.cgColor
        punto.lineWidth = 3
        punto.shadowColor = UIColor.black.cgColor
        punto.shadowOpacity = 0.5
        punto.shadowRadius = 3
        punto.shadowOffset = .zero
        layer.addSublayer(punto)
    }
}
