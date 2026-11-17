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
        collisionMode = .circle
    }
    required init?(coder: NSCoder) { fatalError() }

    func configura(_ s: SegnoMappa, rotazioneMappa: Double) {
        let i = DisegnoSegni.icona(s), e = DisegnoSegni.etichetta(s.etichetta)
        icona.image = i
        etichetta.image = e
        frame = CGRect(x: 0, y: 0, width: i.size.width, height: i.size.height)
        icona.frame = bounds
        etichetta.frame = CGRect(x: i.size.width - 4, y: (i.size.height - e.size.height) / 2, width: e.size.width, height: e.size.height)
        displayPriority = s.priorita == 0 ? .required : .defaultHigh
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
        return m
    }

    func updateUIView(_ m: MKMapView, context: Context) { context.coordinator.parent = self }

    static func dismantleUIView(_ m: MKMapView, coordinator: Coord) {
        Task { @MainActor in if coordinator.parent.ctl.mk === m { coordinator.parent.ctl.mk = nil } }
    }

    final class Coord: NSObject, MKMapViewDelegate {
        var parent: MappaApple
        init(_ p: MappaApple) { parent = p }

        @objc func tocca(_ g: UITapGestureRecognizer) {
            guard let m = g.view as? MKMapView else { return }
            let p = g.location(in: m)
            parent.tocco(p, m.convert(p, toCoordinateFrom: m))
        }
        @objc func premi(_ g: UILongPressGestureRecognizer) {
            guard let m = g.view as? MKMapView else { return }
            m.isScrollEnabled = !(g.state == .began || g.state == .changed)
            parent.mira(g.state, g.location(in: m))
        }

        func mapView(_ m: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let a = annotation as? SegnoAnnotation else { return nil }   // la mia posizione: quella di Apple
            let v = m.dequeueReusableAnnotationView(withIdentifier: "segno", for: a) as! SegnoAppleView
            v.configura(a.segno, rotazioneMappa: m.camera.heading)
            return v
        }

        func mapViewDidChangeVisibleRegion(_ m: MKMapView) {
            let h = m.camera.heading
            for a in m.annotations {
                if let s = a as? SegnoAnnotation, s.segno.rotazione != nil, let v = m.view(for: s) as? SegnoAppleView { v.ruota(s.segno, h) }
            }
            Task { @MainActor in self.parent.ctl.aggiornaDaMappa() }
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
