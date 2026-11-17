import SwiftUI
import CoreLocation

/// Proiezione di un punto: da un'origine (la mia posizione, un punto di gara o coordinate scritte) con
/// azimut (gradi o millesimi NATO) e distanza ricava il punto di arrivo.
struct ProiezioneSheet: View {
    var origineScelta: GaraPoint?
    var mostra: (CLLocationCoordinate2D, String) -> Void
    @EnvironmentObject var location: LocationService
    @EnvironmentObject var log: FieldLog
    @Environment(\.dismiss) var dismiss
    @State private var origine = 0          // 0 io, 1 punto scelto, 2 coordinate
    @State private var coordTesto = ""
    @State private var azimut = ""
    @State private var millesimi = false
    @State private var distanza = ""

    var partenza: CLLocationCoordinate2D? {
        switch origine {
        case 0: return location.location?.coordinate
        case 1: return origineScelta?.coordinate
        default:
            if let u = UTM.parse(coordTesto) { let (la, lo) = UTM.toLatLon(u); return .init(latitude: la, longitude: lo) }
            let n = coordTesto.replacingOccurrences(of: ",", with: " ").split(separator: " ").compactMap { Double($0) }
            return n.count == 2 ? .init(latitude: n[0], longitude: n[1]) : nil
        }
    }

    var gradi: Double? {
        guard let v = Double(azimut.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return millesimi ? v * 360 / 6400 : v
    }

    var arrivo: CLLocationCoordinate2D? {
        guard let p = partenza, let g = gradi, let d = Double(distanza.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return Self.destinazione(p, gradi: g, metri: d)
    }

    static func destinazione(_ p: CLLocationCoordinate2D, gradi: Double, metri: Double) -> CLLocationCoordinate2D {
        let R = 6_371_008.8, d = metri / R, b = gradi * .pi / 180
        let la1 = p.latitude * .pi / 180, lo1 = p.longitude * .pi / 180
        let la2 = asin(sin(la1) * cos(d) + cos(la1) * sin(d) * cos(b))
        let lo2 = lo1 + atan2(sin(b) * sin(d) * cos(la1), cos(d) - sin(la1) * sin(la2))
        return .init(latitude: la2 * 180 / .pi, longitude: lo2 * 180 / .pi)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Da dove") {
                    Picker("Origine", selection: $origine) {
                        Text("La mia posizione").tag(0)
                        if origineScelta != nil { Text(origineScelta!.id).tag(1) }
                        Text("Coordinate").tag(2)
                    }
                    if origine == 2 {
                        TextField("UTM (33T 290013 4874586) o lat, lon", text: $coordTesto)
                            .font(Theme.mono(14)).autocorrectionDisabled().textInputAutocapitalization(.characters)
                    }
                    if let p = partenza {
                        Text(UTM.fromLatLon(p.latitude, p.longitude).text).font(Theme.mono(13)).foregroundStyle(Theme.dim)
                    } else {
                        Text("Origine non valida o GPS in attesa").font(.caption).foregroundStyle(Theme.red)
                    }
                }
                Section("Direzione e distanza") {
                    HStack {
                        TextField(millesimi ? "Azimut in millesimi (0–6400)" : "Azimut in gradi (0–360)", text: $azimut)
                            .keyboardType(.decimalPad).font(Theme.mono(16))
                        Picker("", selection: $millesimi) { Text("°").tag(false); Text("mil").tag(true) }
                            .pickerStyle(.segmented).frame(width: 110)
                    }
                    if origine == 0, let h = location.heading {
                        Button(String(format: "Usa la bussola: %.0f°", h)) { millesimi = false; azimut = String(format: "%.0f", h) }
                    }
                    TextField("Distanza in metri", text: $distanza).keyboardType(.decimalPad).font(Theme.mono(16))
                }
                if let a = arrivo {
                    Section("Punto ricavato") {
                        let u = UTM.fromLatLon(a.latitude, a.longitude)
                        Text(u.text).font(Theme.mono(20, .bold)).foregroundStyle(Theme.olive).textSelection(.enabled)
                        Text("MGRS " + Geo.mgrs(a)).font(Theme.mono(13))
                        Text(String(format: "%.6f, %.6f", a.latitude, a.longitude)).font(Theme.mono(13)).foregroundStyle(Theme.dim)
                        Button { mostra(a, "Proiezione \(azimut)\(millesimi ? " mil" : "°") \(distanza) m"); dismiss() } label: {
                            Label("Mostra sulla mappa", systemImage: "map")
                        }
                        Button { copyToClipboard(u.text) } label: { Label("Copia UTM", systemImage: "doc.on.doc") }
                        Button {
                            log.add(.punto, "Punto proiettato: \(azimut)\(millesimi ? " mil" : "°"), \(distanza) m",
                                    at: CLLocation(latitude: a.latitude, longitude: a.longitude))
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } label: { Label("Salva in Raccolta", systemImage: "tray.and.arrow.down") }
                    }
                }
            }
            .navigationTitle("Proiezione punto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Chiudi") { dismiss() } }
            .onAppear { if origineScelta != nil { origine = 1 } }
        }
    }
}
