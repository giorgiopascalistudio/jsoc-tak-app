import Foundation

enum Datum: Int, CaseIterable, Identifiable {
    case wgs84 = 0, ed50 = 1
    var id: Int { rawValue }
    var label: String { self == .wgs84 ? "WGS84 / ETRS89" : "ED50 (vecchie IGM)" }
    var a: Double { self == .wgs84 ? 6378137.0 : 6378388.0 }
    var f: Double { self == .wgs84 ? 1 / 298.257223563 : 1 / 297.0 }
}

struct UTMCoord {
    var zone: Int
    var north: Bool
    var easting: Double
    var northing: Double
    var band: Character = " "

    var text: String { String(format: "%d%@ %06.0f %07.0f", zone, String(band), easting, northing) }
}

/// UTM con le serie di Snyder (errore < 1 mm nella fascia, verificato con pyproj).
/// ED50 → WGS84 con i parametri EPSG:1311 (media europea, errore ~1–3 m in Italia).
enum UTM {
    private static let k0 = 0.9996
    private static let bands = Array("CDEFGHJKLMNPQRSTUVWXX")

    static func band(forLatitude lat: Double) -> Character {
        bands[max(0, min(20, Int(floor((lat + 80) / 8))))]
    }

    static func fromLatLon(_ lat: Double, _ lon: Double) -> UTMCoord {
        let a = Datum.wgs84.a, f = Datum.wgs84.f
        let e2 = f * (2 - f), ep2 = e2 / (1 - e2)
        var zone = Int(floor((lon + 180) / 6)) + 1
        if lat >= 56 && lat < 64 && lon >= 3 && lon < 12 { zone = 32 }
        zone = max(1, min(60, zone))
        let phi = lat * .pi / 180
        let lam = (lon - Double((zone - 1) * 6 - 180 + 3)) * .pi / 180
        let sp = sin(phi), cp = cos(phi), tp = tan(phi)
        let N = a / sqrt(1 - e2 * sp * sp), T = tp * tp, C = ep2 * cp * cp, A = cp * lam
        let M = a * ((1 - e2 / 4 - 3 * e2 * e2 / 64 - 5 * pow(e2, 3) / 256) * phi
            - (3 * e2 / 8 + 3 * e2 * e2 / 32 + 45 * pow(e2, 3) / 1024) * sin(2 * phi)
            + (15 * e2 * e2 / 256 + 45 * pow(e2, 3) / 1024) * sin(4 * phi)
            - (35 * pow(e2, 3) / 3072) * sin(6 * phi))
        let x = k0 * N * (A + (1 - T + C) * pow(A, 3) / 6 + (5 - 18 * T + T * T + 72 * C - 58 * ep2) * pow(A, 5) / 120)
        let y = k0 * (M + N * tp * (A * A / 2 + (5 - T + 9 * C + 4 * C * C) * pow(A, 4) / 24
            + (61 - 58 * T + T * T + 600 * C - 330 * ep2) * pow(A, 6) / 720))
        return UTMCoord(zone: zone, north: lat >= 0, easting: x + 500000,
                        northing: lat < 0 ? y + 10_000_000 : y, band: band(forLatitude: lat))
    }

    /// Restituisce latitudine e longitudine WGS84.
    static func toLatLon(_ u: UTMCoord, datum: Datum = .wgs84) -> (Double, Double) {
        let a = datum.a, f = datum.f
        let e2 = f * (2 - f), ep2 = e2 / (1 - e2)
        let x = u.easting - 500000
        let y = u.north ? u.northing : u.northing - 10_000_000
        let mu = y / k0 / (a * (1 - e2 / 4 - 3 * e2 * e2 / 64 - 5 * pow(e2, 3) / 256))
        let e1 = (1 - sqrt(1 - e2)) / (1 + sqrt(1 - e2))
        let p1 = mu + (3 * e1 / 2 - 27 * pow(e1, 3) / 32) * sin(2 * mu)
            + (21 * e1 * e1 / 16 - 55 * pow(e1, 4) / 32) * sin(4 * mu)
            + (151 * pow(e1, 3) / 96) * sin(6 * mu) + (1097 * pow(e1, 4) / 512) * sin(8 * mu)
        let s1 = sin(p1), c1 = cos(p1), t1 = tan(p1)
        let N1 = a / sqrt(1 - e2 * s1 * s1), T1 = t1 * t1, C1 = ep2 * c1 * c1
        let R1 = a * (1 - e2) / pow(1 - e2 * s1 * s1, 1.5), D = x / (N1 * k0)
        let lat = p1 - (N1 * t1 / R1) * (D * D / 2 - (5 + 3 * T1 + 10 * C1 - 4 * C1 * C1 - 9 * ep2) * pow(D, 4) / 24
            + (61 + 90 * T1 + 298 * C1 + 45 * T1 * T1 - 252 * ep2 - 3 * C1 * C1) * pow(D, 6) / 720)
        let lon = (D - (1 + 2 * T1 + C1) * pow(D, 3) / 6
            + (5 - 2 * C1 + 28 * T1 - 3 * C1 * C1 + 8 * ep2 + 24 * T1 * T1) * pow(D, 5) / 120) / c1
        let latDeg = lat * 180 / .pi
        let lonDeg = Double((u.zone - 1) * 6 - 180 + 3) + lon * 180 / .pi
        return datum == .ed50 ? ed50ToWgs84(latDeg, lonDeg) : (latDeg, lonDeg)
    }

    private static func ed50ToWgs84(_ lat: Double, _ lon: Double) -> (Double, Double) {
        let src = Datum.ed50, dst = Datum.wgs84
        let es = src.f * (2 - src.f), p = lat * .pi / 180, l = lon * .pi / 180
        let N = src.a / sqrt(1 - es * sin(p) * sin(p))
        let X = N * cos(p) * cos(l) - 87, Y = N * cos(p) * sin(l) - 98, Z = N * (1 - es) * sin(p) - 121
        let ed = dst.f * (2 - dst.f), r = hypot(X, Y)
        var lat2 = atan2(Z, r * (1 - ed))
        for _ in 0..<6 {
            let N2 = dst.a / sqrt(1 - ed * sin(lat2) * sin(lat2))
            lat2 = atan2(Z + ed * N2 * sin(lat2), r)
        }
        return (lat2 * 180 / .pi, atan2(Y, X) * 180 / .pi)
    }

    /// Riconosce "33T 657154 4553444", "33 657154 4553444", "33N E657154 N4553444" ecc.
    /// La lettera è la fascia di latitudine (C–M sud, N–X nord); senza lettera vale l'emisfero nord.
    static func parse(_ text: String) -> UTMCoord? {
        let pattern = #"(\d{1,2})\s*([C-HJ-NP-Xc-hj-np-x])?[\s,;]+E?\s*(\d{5,7}(?:[.,]\d+)?)\s*m?[\s,;]+N?\s*(\d{6,8}(?:[.,]\d+)?)"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func group(_ i: Int) -> String? {
            Range(m.range(at: i), in: text).map { String(text[$0]).replacingOccurrences(of: ",", with: ".") }
        }
        guard let zone = group(1).flatMap(Int.init), (1...60).contains(zone),
              let e = group(3).flatMap(Double.init), let n = group(4).flatMap(Double.init),
              (100_000...900_000).contains(e) else { return nil }
        let band = group(2)?.uppercased().first
        return UTMCoord(zone: zone, north: band.map { $0 >= "N" } ?? true, easting: e, northing: n, band: band ?? " ")
    }
}
