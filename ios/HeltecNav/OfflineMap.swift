import Foundation
import MapKit

/// Satellite offline: tessere Esri World Imagery salvate in Documents/Tiles. Se una tessera c'è la usa
/// (anche senza rete), altrimenti la scarica e la conserva.
final class CachedTileOverlay: MKTileOverlay {
    static let dir: URL = {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Tiles/esri")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    static let template = "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"

    init() {
        super.init(urlTemplate: Self.template)
        canReplaceMapContent = true
        maximumZ = 19
        tileSize = CGSize(width: 256, height: 256)
    }

    static func file(_ z: Int, _ x: Int, _ y: Int) -> URL { dir.appendingPathComponent("\(z)/\(x)/\(y).jpg") }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let f = Self.file(path.z, path.x, path.y)
        if let d = try? Data(contentsOf: f) { result(d, nil); return }
        URLSession.shared.dataTask(with: url(forTilePath: path)) { data, resp, err in
            if let data, (resp as? HTTPURLResponse)?.statusCode == 200 {
                try? FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: f)
            }
            result(data, err)
        }.resume()
    }
}

/// Scarica in anticipo le tessere delle zone di gara.
@MainActor
final class OfflineTiles: ObservableObject {
    static let shared = OfflineTiles()
    @Published private(set) var running = false
    @Published private(set) var done = 0
    @Published private(set) var total = 0
    @Published private(set) var esito = ""
    @Published var usa: Bool { didSet { UserDefaults.standard.set(usa, forKey: "mappa.offline") } }
    private var task: Task<Void, Never>?

    init() {
        usa = UserDefaults.standard.bool(forKey: "mappa.offline")
        esito = UserDefaults.standard.string(forKey: "mappa.offline.esito") ?? "Non ancora scaricate"
    }

    struct Zona { let nome: String; let s, w, n, e: Double; let zMax: Int }
    static let zone: [Zona] = [
        .init(nome: "Area operativa Fase FERRO", s: 43.952, w: 12.352, n: 44.006, e: 12.405, zMax: 18),
        .init(nome: "Dintorni (Ripa Calbana, Torriana)", s: 43.945, w: 12.340, n: 44.012, e: 12.420, zMax: 16),
        .init(nome: "Rimini (hotel, delitti, ospedale)", s: 44.040, w: 12.555, n: 44.082, e: 12.600, zMax: 17),
        .init(nome: "Panoramica Rimini–San Marino", s: 43.88, w: 12.33, n: 44.10, e: 12.62, zMax: 13),
    ]

    static func tile(_ lat: Double, _ lon: Double, _ z: Int) -> (Int, Int) {
        let n = pow(2.0, Double(z))
        let x = Int((lon + 180) / 360 * n)
        let r = lat * .pi / 180
        let y = Int((1 - log(tan(r) + 1 / cos(r)) / .pi) / 2 * n)
        return (x, y)
    }

    static func elenco() -> [(Int, Int, Int)] {
        var out: [(Int, Int, Int)] = []
        var visti = Set<String>()
        for zona in zone {
            for z in 10...zona.zMax {
                let (x0, y0) = tile(zona.n, zona.w, z), (x1, y1) = tile(zona.s, zona.e, z)
                for x in min(x0, x1)...max(x0, x1) {
                    for y in min(y0, y1)...max(y0, y1) where visti.insert("\(z)/\(x)/\(y)").inserted {
                        out.append((z, x, y))
                    }
                }
            }
        }
        return out
    }

    var dimensioneMB: Double {
        let e = FileManager.default.enumerator(at: CachedTileOverlay.dir, includingPropertiesForKeys: [.fileSizeKey])
        var tot = 0
        while let u = e?.nextObject() as? URL { tot += (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        return Double(tot) / 1_048_576
    }

    func scarica() {
        guard !running else { return }
        let lista = Self.elenco()
        total = lista.count
        done = 0
        running = true
        task = Task {
            var falliti = 0
            await withTaskGroup(of: Bool.self) { g in
                var i = 0
                func prossima() -> Bool {
                    guard i < lista.count else { return false }
                    let (z, x, y) = lista[i]; i += 1
                    g.addTask {
                        let f = CachedTileOverlay.file(z, x, y)
                        if FileManager.default.fileExists(atPath: f.path) { return true }
                        let s = CachedTileOverlay.template.replacingOccurrences(of: "{z}", with: "\(z)")
                            .replacingOccurrences(of: "{y}", with: "\(y)").replacingOccurrences(of: "{x}", with: "\(x)")
                        guard let u = URL(string: s), let res = try? await URLSession.shared.data(from: u),
                              (res.1 as? HTTPURLResponse)?.statusCode == 200 else { return false }
                        let d = res.0
                        try? FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
                        return (try? d.write(to: f)) != nil
                    }
                    return true
                }
                for _ in 0..<8 { _ = prossima() }
                for await ok in g {
                    if Task.isCancelled { g.cancelAll(); break }
                    done += 1
                    if !ok { falliti += 1 }
                    _ = prossima()
                }
            }
            running = false
            esito = "\(done - falliti) tessere · \(String(format: "%.0f", dimensioneMB)) MB" + (falliti > 0 ? " · \(falliti) mancanti (riprova)" : " · complete")
            UserDefaults.standard.set(esito, forKey: "mappa.offline.esito")
            if falliti == 0 { usa = true }
        }
    }

    func ferma() { task?.cancel() }
}
