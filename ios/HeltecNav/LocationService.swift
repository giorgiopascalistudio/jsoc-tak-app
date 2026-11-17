import Foundation
import CoreLocation
import CoreMotion
import UIKit

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var heading: Double?
    @Published var headingAccuracy: Double = -1
    @Published var pressureKPa: Double?
    @Published var relAltitude: Double?
    @Published var authorized = false
    /// Declinazione magnetica (vero - magnetico) letta dalla bussola del telefono; nil finché non c'è.
    @Published var declinazione: Double?

    private let manager = CLLocationManager()
    private let altimeter = CMAltimeter()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 2
        manager.headingFilter = 2
        manager.headingOrientation = .portrait
        // resta viva col telefono bloccato: serve per le notifiche delle novità (niente push con l'Apple ID gratuito)
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }

    /// In background meno precisione (batteria); in primo piano la migliore.
    func sfondo(_ inBackground: Bool) {
        manager.desiredAccuracy = inBackground ? kCLLocationAccuracyNearestTenMeters : kCLLocationAccuracyBest
        manager.distanceFilter = inBackground ? 10 : 2
    }

    func start() {
        manager.requestAlwaysAuthorization()
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] d, _ in
                guard let d else { return }
                self?.pressureKPa = d.pressure.doubleValue
                self?.relAltitude = d.relativeAltitude.doubleValue
            }
        }
    }

    func requestAlways() { manager.requestAlwaysAuthorization() }

    /// Durante la navigazione la bussola segue la rotazione del telefono (verticale/orizzontale).
    /// Fuori dalla navigazione resta in verticale perché il mirino fa i conti così.
    private var osservaOrientamento: NSObjectProtocol?
    func seguiOrientamento(_ on: Bool) {
        if on {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            aggiornaOrientamento()
            if osservaOrientamento == nil {
                osservaOrientamento = NotificationCenter.default.addObserver(
                    forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                        self?.aggiornaOrientamento()
                    }
            }
        } else {
            if let o = osservaOrientamento { NotificationCenter.default.removeObserver(o) }
            osservaOrientamento = nil
            manager.headingOrientation = .portrait
        }
    }

    private func aggiornaOrientamento() {
        switch UIDevice.current.orientation {
        case .landscapeLeft: manager.headingOrientation = .landscapeLeft
        case .landscapeRight: manager.headingOrientation = .landscapeRight
        case .portraitUpsideDown: manager.headingOrientation = .portraitUpsideDown
        case .portrait: manager.headingOrientation = .portrait
        default: break   // a faccia in su o in giù: resta l'ultimo
        }
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        let s = m.authorizationStatus
        authorized = s == .authorizedAlways || s == .authorizedWhenInUse
        if authorized { m.startUpdatingLocation() }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        location = locs.last
    }

    private var ultimaBussola = Date.distantPast

    /// Ogni cambio pubblicato ridisegna l'app: al massimo ~8 volte al secondo e solo se la direzione cambia davvero.
    func locationManager(_ m: CLLocationManager, didUpdateHeading h: CLHeading) {
        let nuovo = h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading
        let diff = abs(((nuovo - (heading ?? -999)) + 540).truncatingRemainder(dividingBy: 360) - 180)
        let ora = Date()
        guard heading == nil || (diff >= 2 && ora.timeIntervalSince(ultimaBussola) > 0.12) || ora.timeIntervalSince(ultimaBussola) > 2 else { return }
        ultimaBussola = ora
        heading = nuovo
        if h.trueHeading >= 0, h.magneticHeading >= 0 {
            var d = h.trueHeading - h.magneticHeading
            if d > 180 { d -= 360 } else if d < -180 { d += 360 }
            if abs(d) < 30, abs(d - (declinazione ?? 999)) > 0.3 { declinazione = d }
        }
        if abs(h.headingAccuracy - headingAccuracy) > 3 { headingAccuracy = h.headingAccuracy }
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}

    // MARK: utilità

    var coordText: String {
        guard let c = location?.coordinate else { return "nessuna posizione" }
        return Geo.describe(c)
    }
}

enum Geo {
    static func describe(_ c: CLLocationCoordinate2D) -> String {
        let u = UTM.fromLatLon(c.latitude, c.longitude)
        return String(format: "%.6f, %.6f\nUTM %@\nMGRS %@", c.latitude, c.longitude, u.text, mgrs(c))
    }

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    static func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let p1 = a.latitude * .pi / 180, p2 = b.latitude * .pi / 180
        let dl = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    static func formatDistance(_ d: Double) -> String {
        d < 1000 ? String(format: "%.0f m", d) : String(format: "%.2f km", d / 1000)
    }

    /// MGRS a 1 m (WGS84), griglia AA (schema standard per WGS84).
    static func mgrs(_ c: CLLocationCoordinate2D) -> String {
        let u = UTM.fromLatLon(c.latitude, c.longitude)
        let setCol = ["ABCDEFGH", "JKLMNPQR", "STUVWXYZ"]
        let setRow = ["ABCDEFGHJKLMNPQRSTUV", "FGHJKLMNPQRSTUVABCDE"]
        let set = (u.zone - 1) % 3
        let colLetters = Array(setCol[set])
        let rowLetters = Array(setRow[(u.zone - 1) % 2])
        let e100k = Int(floor(u.easting / 100_000))
        let n100k = Int(floor(u.northing / 100_000)) % 20
        guard e100k >= 1, e100k <= 8 else { return u.text }
        let col = colLetters[e100k - 1]
        let row = rowLetters[n100k]
        let e = Int(u.easting) % 100_000
        let n = Int(u.northing) % 100_000
        return String(format: "%d%@ %@%@ %05d %05d", u.zone, String(u.band), String(col), String(row), e, n)
    }
}
