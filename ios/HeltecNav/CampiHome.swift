import SwiftUI
import MapKit

// MARK: - Campi dell'associazione (dal server: GET /api/campi)

struct JCampo: Codable, Identifiable { let id: String; let nome: String; let lat: Double; let lon: Double; let ettari: Double?; let poly: [[Double]] }
struct JSede: Codable { let nome: String; let lat: Double; let lon: Double }
struct JCampi: Codable { let sede: JSede?; let campi: [JCampo] }

@MainActor
final class CampiStore: ObservableObject {
    static let shared = CampiStore()
    @Published private(set) var dati: JCampi?
    private let chiave = "jsoc.campi"

    init() {
        if let d = UserDefaults.standard.data(forKey: chiave) { dati = try? JSONDecoder().decode(JCampi.self, from: d) }
    }

    func aggiorna() async {
        guard JsocClient.shared.collegato, let c: JCampi = try? await JsocClient.shared.get("/api/campi") else { return }
        dati = c
        if let d = try? JSONEncoder().encode(c) { UserDefaults.standard.set(d, forKey: chiave) }
        if EventoStore.shared.inPersonale { EventoStore.shared.apriPersonale() }
    }

    /// i campi come aree della mappa personale
    var aree: [GaraArea] {
        (dati?.campi ?? []).map { GaraArea(nome: $0.nome, tipo: "campo", punti: $0.poly) }
    }
}

/// Riquadro della Home: campi con i confini, sede e luoghi dei prossimi eventi. Non si tocca dentro:
/// il tocco apre la Mappa vera (le posizioni dei membri qui non compaiono mai).
struct MappaHomeBox: View {
    let eventi: [JEvento]
    @ObservedObject private var campi = CampiStore.shared

    var body: some View {
        let _ = Contatori.disegno("MappaHomeBox")
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CAMPI ED EVENTI").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.dim)
                Spacer()
                Text("\(campi.dati?.campi.count ?? 0) campi").font(.system(size: 10)).foregroundStyle(Theme.dim)
            }
            Button { EventoStore.shared.apriPersonale(); vaiAllaScheda(Schede.mappa) } label: {
                ZStack(alignment: .bottomTrailing) {
                    MappaStatica(campi: campi.dati, eventi: eventi)
                        .allowsHitTesting(false)
                    Label("Apri la mappa", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Theme.olive, in: Capsule()).padding(10)
                }
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Mappa dei campi ed eventi, apri la mappa")
        }
        .task { await campi.aggiorna() }
    }
}

private final class PuntoHome: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D; let title: String?; let colore: UIColor; let icona: String
    init(_ c: CLLocationCoordinate2D, _ t: String, _ col: UIColor, _ i: String) { coordinate = c; title = t; colore = col; icona = i }
}

private struct MappaStatica: UIViewRepresentable {
    let campi: JCampi?
    let eventi: [JEvento]

    func makeUIView(context: Context) -> MKMapView {
        let m = MKMapView()
        m.delegate = context.coordinator
        m.isScrollEnabled = false; m.isZoomEnabled = false; m.isRotateEnabled = false; m.isPitchEnabled = false
        m.showsUserLocation = false
        m.overrideUserInterfaceStyle = .dark
        m.pointOfInterestFilter = .excludingAll
        m.mapType = .hybrid
        return m
    }

    func updateUIView(_ m: MKMapView, context: Context) {
        let firma = "\(campi?.campi.map(\.id) ?? [])|\(eventi.map(\.id))"
        guard context.coordinator.firma != firma else { return }
        context.coordinator.firma = firma
        m.removeOverlays(m.overlays); m.removeAnnotations(m.annotations)
        var tutti: [CLLocationCoordinate2D] = []
        for c in campi?.campi ?? [] {
            var pts = c.poly.compactMap { $0.count == 2 ? CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) : nil }
            if pts.count >= 3 { m.addOverlay(MKPolygon(coordinates: &pts, count: pts.count)) }
            let cc = CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon)
            m.addAnnotation(PuntoHome(cc, c.nome, UIColor(Theme.olive), "scope"))
            tutti.append(cc)
        }
        if let s = campi?.sede {
            let cc = CLLocationCoordinate2D(latitude: s.lat, longitude: s.lon)
            m.addAnnotation(PuntoHome(cc, "Sede", .white, "house.fill")); tutti.append(cc)
        }
        for e in eventi where e.lat != nil && e.lon != nil {
            let cc = CLLocationCoordinate2D(latitude: e.lat!, longitude: e.lon!)
            m.addAnnotation(PuntoHome(cc, e.nome, UIColor(e.colore), "calendar")); tutti.append(cc)
        }
        guard !tutti.isEmpty else { return }
        let la = tutti.map(\.latitude), lo = tutti.map(\.longitude)
        let r = MKCoordinateRegion(center: .init(latitude: (la.min()! + la.max()!) / 2, longitude: (lo.min()! + lo.max()!) / 2),
                                   span: .init(latitudeDelta: max(0.05, (la.max()! - la.min()!) * 1.35), longitudeDelta: max(0.05, (lo.max()! - lo.min()!) * 1.35)))
        m.setRegion(r, animated: false)
    }

    func makeCoordinator() -> Coord { Coord() }

    final class Coord: NSObject, MKMapViewDelegate {
        var firma = ""
        func mapView(_ m: MKMapView, rendererFor o: MKOverlay) -> MKOverlayRenderer {
            guard let p = o as? MKPolygon else { return MKOverlayRenderer(overlay: o) }
            let r = MKPolygonRenderer(polygon: p)
            r.fillColor = UIColor(Theme.olive).withAlphaComponent(0.28)
            r.strokeColor = UIColor(Theme.olive); r.lineWidth = 2
            return r
        }
        func mapView(_ m: MKMapView, viewFor a: MKAnnotation) -> MKAnnotationView? {
            guard let p = a as? PuntoHome else { return nil }
            let v = MKMarkerAnnotationView(annotation: p, reuseIdentifier: nil)
            v.markerTintColor = p.colore
            v.glyphImage = UIImage(systemName: p.icona)
            v.titleVisibility = .adaptive
            v.displayPriority = .required
            v.clusteringIdentifier = nil
            return v
        }
    }
}
