import Foundation
import CoreLocation
import SwiftUI

struct GaraPoint: Identifiable, Hashable {
    let id: String
    let lat: Double
    let lon: Double
    let kind: Kind
    let note: String

    enum Kind { case hotel, obj, ipotesi, logistica, acqua, recon, mio }

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    var color: Color {
        switch kind {
        case .hotel: return Theme.cyan
        case .obj: return Theme.red
        case .ipotesi: return .yellow
        case .logistica: return .white
        case .acqua: return .blue
        case .recon: return Color(red: 0.70, green: 0.55, blue: 0.95)
        case .mio: return Color(red: 1.0, green: 0.48, blue: 0.85)
        }
    }
}

struct GaraArea: Identifiable, Decodable {
    var id: String { nome }
    let nome: String
    let tipo: String
    let punti: [[Double]]
    var coordinates: [CLLocationCoordinate2D] { punti.map { .init(latitude: $0[0], longitude: $0[1]) } }
    var interdetta: Bool { tipo == "interdetta" }
}

struct TimelineEvent: Identifiable {
    let id = UUID()
    let date: Date
    let title: String
    let detail: String
}

enum Gara {
    /// Punti e aree dell'evento attivo (dal server JSOC TAK, con copia sul telefono).
    static var points: [GaraPoint] { DatiEvento.punti }
    static var areas: [GaraArea] { DatiEvento.aree }

    static func date(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = day; c.hour = h; c.minute = m
        c.timeZone = TimeZone(identifier: "Europe/Rome")
        return Calendar(identifier: .gregorian).date(from: c) ?? Date()
    }

    static let timeline: [TimelineEvent] = []

    /// Percorso scelto dalla squadra per la Fase FERRO (09/11): codice, nome breve, punto.
    struct Tappa: Identifiable, Hashable { let code: String; let nome: String; let punto: String; var id: String { code } }
    static let percorso: [Tappa] = []
    static func point(_ id: String) -> GaraPoint? { points.first { $0.id == id } }

    static let codes: [(String, String)] = []
}
