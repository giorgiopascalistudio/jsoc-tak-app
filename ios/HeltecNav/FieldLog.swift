import Foundation
import CoreLocation

struct LogEntry: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case foto, audio, qr, nota, punto, testo }

    var id = UUID()
    var date = Date()
    var kind: Kind
    var text: String
    var file: String? = nil
    var lat: Double? = nil
    var lon: Double? = nil

    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lon else { return nil }
        return .init(latitude: lat, longitude: lon)
    }

    var icon: String {
        switch kind {
        case .foto: return "camera"
        case .audio: return "waveform"
        case .qr: return "qrcode"
        case .nota: return "note.text"
        case .punto: return "mappin"
        case .testo: return "text.viewfinder"
        }
    }
}

/// Registro di tutto quello che si raccoglie sul campo (file in Documents/Raccolta, visibili anche dall'app File).
final class FieldLog: ObservableObject {
    @Published private(set) var entries: [LogEntry] = []

    static var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Raccolta")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private var file: URL { Self.dir.appendingPathComponent("registro.json") }

    init() {
        if let d = try? Data(contentsOf: file), let e = try? JSONDecoder().decode([LogEntry].self, from: d) {
            entries = e
        }
    }

    func add(_ kind: LogEntry.Kind, _ text: String, file: String? = nil, at loc: CLLocation?) {
        var e = LogEntry(kind: kind, text: text, file: file)
        e.lat = loc?.coordinate.latitude
        e.lon = loc?.coordinate.longitude
        entries.insert(e, at: 0)
        save()
    }

    func update(_ e: LogEntry) {
        guard let i = entries.firstIndex(where: { $0.id == e.id }) else { return }
        entries[i] = e
        save()
    }

    func delete(_ e: LogEntry) {
        if let f = e.file { try? FileManager.default.removeItem(at: Self.dir.appendingPathComponent(f)) }
        entries.removeAll { $0.id == e.id }
        save()
    }

    func url(_ e: LogEntry) -> URL? { e.file.map { Self.dir.appendingPathComponent($0) } }

    static func newFileName(_ ext: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return "\(f.string(from: Date())).\(ext)"
    }

    /// Rapporto testuale da mandare all'HQ o in chat.
    func report() -> String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM HH:mm"
        return entries.reversed().map { e in
            var s = "[\(f.string(from: e.date))] \(e.kind.rawValue.uppercased()): \(e.text)"
            if let c = e.coordinate {
                let u = UTM.fromLatLon(c.latitude, c.longitude)
                s += String(format: " @ %.6f,%.6f (UTM %@)", c.latitude, c.longitude, u.text)
            }
            return s
        }.joined(separator: "\n")
    }

    private func save() {
        if let d = try? JSONEncoder().encode(entries) { try? d.write(to: file, options: .atomic) }
    }
}
