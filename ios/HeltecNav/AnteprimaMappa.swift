import Foundation
import CoreLocation

/// Dati di prova della mappa tattica per le anteprime sul simulatore (tavole 10-12).
/// Si accendono con `-anteprima.dati YES -debug.mappa.dati YES`; `-debug.mappa.ruota YES` apre anche la Ruota su OBJ 03.
/// Le posizioni ricalcano la tavola: simulatore a 40.2503,18.2789 (il pallino), scala 30 m per punto (2 km = 66 pt).
extension Anteprima {
    static var mappaAttiva: Bool { attiva && UserDefaults.standard.bool(forKey: "debug.mappa.dati") }
    static var ruotaAperta: Bool { mappaAttiva && UserDefaults.standard.bool(forKey: "debug.mappa.ruota") }

    /// punto della tavola (x, y in pt) → coordinata, con il pallino della posizione in (392, 313)
    private static func daTavola(_ x: Double, _ y: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 40.2503 + (313 - y) * 30 / 111_320, longitude: 18.2789 + (x - 392) * 30 / 84_970)
    }

    /// centro e zoom della mappa come nella tavola (centro della parte visibile, a destra della colonna)
    static var centroMappa: CLLocationCoordinate2D { daTavola(483.5, 195) }
    static let zoomMappa = 10.96

    static var puntiMappa: [JPunto] {
        func obj(_ id: Int, _ nome: String, _ x: Double, _ y: Double) -> JPunto {
            let c = daTavola(x, y)
            return JPunto(id: id, evento: 101, nome: nome, tipo: "obj", lat: c.latitude, lon: c.longitude, note: nil, autore: nil, stato: "da fare")
        }
        return [obj(2, "OBJ 02 bank", 410, 150), obj(5, "OBJ 05 nebula", 444, 136),
                obj(4, "OBJ 04 shadow", 452, 172), obj(3, "OBJ 03 master", 428, 196)]
    }

    static var compagniMappa: [JCompagno] {
        let c = daTavola(600, 250)
        return [JCompagno(id: 7, callsign: "FALCO", nome: "Marco", squadra: nil, lat: c.latitude, lon: c.longitude,
                          acc: 5, rotta: nil, vel: nil, batt: 0.8, dir: 340, ts: Date().timeIntervalSince1970)]
    }
}
