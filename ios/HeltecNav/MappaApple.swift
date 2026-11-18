import SwiftUI
import MapKit

/// Mappa Apple (edifici 3D, terreno realistico) come stile in più. Stessi segnaposti, tocchi e strumenti
/// della mappa principale; niente offline e niente mappe importate (Apple non lo permette).
final class SegnoAnnotation: NSObject, MKAnnotation {
    let segno: SegnoMappa
    var coordinate: CLLocationCoordinate2D { segno.coord }
    init(_ s: SegnoMappa) { segno = s }
}

final class SegnoAppleView: MKAnnotationView {
    let icona = UIImageView()
    let etichetta = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        addSubview(icona); addSubview(etichetta)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configura(_ s: SegnoMappa, rotazioneMappa: Double) {
        let i = DisegnoSegni.icona(s), e = DisegnoSegni.etichetta(s.etichetta)
        icona.image = i
        etichetta.image = e
        let w = i.size.width - 4 + e.size.width
        frame = CGRect(x: 0, y: 0, width: w, height: max(i.size.height, e.size.height))
        icona.frame = CGRect(x: 0, y: (frame.height - i.size.height) / 2, width: i.size.width, height: i.size.height)
        etichetta.frame = CGRect(x: i.size.width - 4, y: (frame.height - e.size.height) / 2, width: e.size.width, height: e.size.height)
        centerOffset = CGPoint(x: (w - i.size.width) / 2, y: 0)        // l'icona resta sul punto esatto
        // mai raggruppati né nascosti: ogni punto resta sempre sulla mappa
        displayPriority = .required
        clusteringIdentifier = nil
        ruota(s, rotazioneMappa)
    }

    func ruota(_ s: SegnoMappa, _ rotazioneMappa: Double) {
        icona.transform = s.rotazione.map { CGAffineTransform(rotationAngle: CGFloat(($0 - rotazioneMappa) * .pi / 180)) } ?? .identity
    }
}

struct MappaApple: UIViewRepresentable {
    @ObservedObject var ctl: MappaCtl
    var tocco: (CGPoint, CLLocationCoordinate2D) -> Void
    var mira: (UIGestureRecognizer.State, CGPoint) -> Void

    func makeCoordinator() -> Coord { Coord(self) }

    func makeUIView(context: Context) -> MKMapView {
        let m = MKMapView()
        m.delegate = context.coordinator
        m.showsUserLocation = true
        m.showsCompass = false
        m.showsScale = false
        m.overrideUserInterfaceStyle = .dark
        m.register(SegnoAppleView.self, forAnnotationViewWithReuseIdentifier: "segno")
        m.register(GruppoAppleView.self, forAnnotationViewWithReuseIdentifier: "gruppo")
        m.register(ConoAppleView.self, forAnnotationViewWithReuseIdentifier: "io")
        m.register(SimboloAppleView.self, forAnnotationViewWithReuseIdentifier: "simbolo")
        context.coordinator.mappa = m
        context.coordinator.avviaBussola()
        let c = ctl.centro
        m.setRegion(MKCoordinateRegion(center: c, latitudinalMeters: 1500, longitudinalMeters: 1500), animated: false)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coord.tocca(_:)))
        m.addGestureRecognizer(tap)
        let lp = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coord.premi(_:)))
        lp.minimumPressDuration = 0.55
        m.addGestureRecognizer(lp)
        ctl.mk = m
        ctl.configuraApple()
        ctl.applicaSegniApple()
        ctl.applicaDisegniApple()
        return m
    }

    func updateUIView(_ m: MKMapView, context: Context) { context.coordinator.parent = self }

    static func dismantleUIView(_ m: MKMapView, coordinator: Coord) {
        Task { @MainActor in if coordinator.parent.ctl.mk === m { coordinator.parent.ctl.mk = nil } }
    }

    final class Coord: NSObject, MKMapViewDelegate, CLLocationManagerDelegate {
        var parent: MappaApple
        weak var mappa: MKMapView?
        private let bussola = CLLocationManager()
        private var direzione: Double?
        init(_ p: MappaApple) { parent = p }
        deinit { bussola.stopUpdatingHeading() }

        func avviaBussola() {
            guard CLLocationManager.headingAvailable() else { return }
            bussola.delegate = self
            bussola.headingFilter = 2
            bussola.startUpdatingHeading()
        }

        func locationManager(_ manager: CLLocationManager, didUpdateHeading h: CLHeading) {
            // la bussola va riferita a come è girato lo schermo (in orizzontale ruota di 90°)
            let o = mappa?.window?.windowScene?.interfaceOrientation
            let dev: CLDeviceOrientation = o == .landscapeLeft ? .landscapeRight : (o == .landscapeRight ? .landscapeLeft : (o == .portraitUpsideDown ? .portraitUpsideDown : .portrait))
            if manager.headingOrientation != dev { manager.headingOrientation = dev }
            direzione = h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading
            aggiornaCono()
        }

        func aggiornaCono() {
            guard let m = mappa, let v = m.view(for: m.userLocation) as? ConoAppleView else { return }
            v.dirigi(direzione.map { $0 - m.camera.heading })
        }

        @objc func tocca(_ g: UITapGestureRecognizer) {
            guard let m = g.view as? MKMapView else { return }
            let p = g.location(in: m)
            // tocco su un gruppo di punti: si avvicina finché si separano
            for case let gruppo as MKClusterAnnotation in m.annotations {
                let q = m.convert(gruppo.coordinate, toPointTo: m)
                if hypot(q.x - p.x, q.y - p.y) < 24 {
                    m.showAnnotations(gruppo.memberAnnotations, animated: true)
                    return
                }
            }
            parent.tocco(p, m.convert(p, toCoordinateFrom: m))
        }
        @objc func premi(_ g: UILongPressGestureRecognizer) {
            guard let m = g.view as? MKMapView else { return }
            m.isScrollEnabled = !(g.state == .began || g.state == .changed)
            parent.mira(g.state, g.location(in: m))
        }

        func mapView(_ m: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                let v = m.dequeueReusableAnnotationView(withIdentifier: "io", for: annotation) as! ConoAppleView
                v.dirigi(direzione.map { $0 - m.camera.heading })
                return v
            }
            if let s = annotation as? SimboloAnnotation {
                let v = m.dequeueReusableAnnotationView(withIdentifier: "simbolo", for: s) as! SimboloAppleView
                v.configura(s, rotazioneMappa: m.camera.heading)
                return v
            }
            if let g = annotation as? MKClusterAnnotation {
                let v = m.dequeueReusableAnnotationView(withIdentifier: "gruppo", for: g) as! GruppoAppleView
                v.mostra(g.memberAnnotations.count)
                return v
            }
            guard let a = annotation as? SegnoAnnotation else { return nil }
            let v = m.dequeueReusableAnnotationView(withIdentifier: "segno", for: a) as! SegnoAppleView
            v.configura(a.segno, rotazioneMappa: m.camera.heading)
            return v
        }

        func mapViewDidChangeVisibleRegion(_ m: MKMapView) {
            let h = m.camera.heading
            for a in m.annotations {
                if let s = a as? SegnoAnnotation, s.segno.rotazione != nil, let v = m.view(for: s) as? SegnoAppleView { v.ruota(s.segno, h) }
                if let s = a as? SimboloAnnotation, s.simbolo.ruota, let v = m.view(for: s) as? SimboloAppleView { v.ruota(s, h) }
            }
            aggiornaCono()
            Task { @MainActor in self.parent.ctl.aggiornaDaMappa() }
        }

        func mapView(_ m: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            DisegniApple.renderer(overlay) ?? MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ m: MKMapView, regionDidChangeAnimated animated: Bool) {
            let c = m.centerCoordinate
            UserDefaults.standard.set([c.latitude, c.longitude, 15.0], forKey: "mappa.centro")
            Task { @MainActor in self.parent.ctl.aggiornaDaMappa() }
        }

        func mapView(_ m: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
            Task { @MainActor in
                self.parent.ctl.modo = mode == .follow ? .follow : (mode == .followWithHeading ? .followWithHeading : .none)
            }
        }
    }
}

extension MappaCtl {
    /// stile Apple: standard 3D (edifici) o satellite 3D
    func configuraApple() {
        guard let m = mk else { return }
        if #available(iOS 16.0, *) {
            m.preferredConfiguration = stile == .appleSat
                ? MKHybridMapConfiguration(elevationStyle: .realistic)
                : MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .muted)
        }
        m.showsBuildings = true
        m.pointOfInterestFilter = .excludingAll
    }

    func applicaSegniApple() {
        guard let m = mk else { return }
        m.removeAnnotations(m.annotations.filter { $0 is SegnoAnnotation })
        m.addAnnotations(segni.map { SegnoAnnotation($0) })
    }

    func segniSottoApple(_ p: CGPoint) -> [String] {
        guard let m = mk else { return [] }
        return segni.map { s -> (String, CGFloat) in
            let q = m.convert(s.coord, toPointTo: m)
            return (s.chiave, hypot(q.x - p.x, q.y - p.y))
        }
        .filter { $0.1 < 26 }
        .sorted { $0.1 < $1.1 }
        .map(\.0)
    }
}


/// La mia posizione sulla mappa Apple: pallino con il cono della direzione (come sulle altre mappe).
final class ConoAppleView: MKAnnotationView {
    private let cono = UIImageView(image: ConoAppleView.immagine)
    private let punto = UIView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 130, height: 130)
        cono.frame = bounds
        addSubview(cono)
        punto.frame = CGRect(x: 56, y: 56, width: 18, height: 18)
        punto.layer.cornerRadius = 9
        punto.backgroundColor = UIColor(Theme.olive)
        punto.layer.borderColor = UIColor.white.cgColor
        punto.layer.borderWidth = 3
        punto.layer.shadowColor = UIColor.black.cgColor
        punto.layer.shadowOpacity = 0.5
        punto.layer.shadowRadius = 3
        addSubview(punto)
        displayPriority = .required
        zPriority = .max
        canShowCallout = false
    }
    required init?(coder: NSCoder) { fatalError() }

    func dirigi(_ gradi: Double?) {
        cono.isHidden = gradi == nil
        if let g = gradi { cono.transform = CGAffineTransform(rotationAngle: CGFloat(g * .pi / 180)) }
    }

    static let immagine: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 130, height: 130)).image { ctx in
        let c = CGPoint(x: 65, y: 65)
        let p = UIBezierPath()
        p.move(to: c)
        p.addArc(withCenter: c, radius: 63, startAngle: (-90 - 30) * .pi / 180, endAngle: (-90 + 30) * .pi / 180, clockwise: true)
        p.close()
        ctx.cgContext.addPath(p.cgPath)
        ctx.cgContext.clip()
        let col = UIColor(Theme.olive)
        if let g = CGGradient(colorsSpace: nil, colors: [col.withAlphaComponent(0.8).cgColor, col.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1]) {
            ctx.cgContext.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: 63, options: [])
        }
    }
}

/// Punti vicini raggruppati: pallino con il numero; toccandolo la mappa si avvicina.
final class GruppoAppleView: MKAnnotationView {
    private let testo = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        layer.cornerRadius = 15
        backgroundColor = UIColor(Theme.red).withAlphaComponent(0.92)
        layer.borderColor = UIColor.black.cgColor
        layer.borderWidth = 1.5
        testo.frame = bounds
        testo.textAlignment = .center
        testo.font = .monospacedSystemFont(ofSize: 12, weight: .heavy)
        testo.textColor = .black
        addSubview(testo)
        displayPriority = .defaultHigh
        collisionMode = .circle
    }
    required init?(coder: NSCoder) { fatalError() }

    func mostra(_ n: Int) { testo.text = "+\(n)" }
}
