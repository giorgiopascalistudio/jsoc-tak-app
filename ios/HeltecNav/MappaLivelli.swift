import SwiftUI
import MapLibre
import MapKit
import CoreLocation

// MARK: - Elementi disegnati sulla mappa (stesi a terra: li disegna il motore della mappa, non lo schermo)

struct ElementoLivello: Codable, Identifiable, Hashable {
    var id: String              // d<id> condiviso sul server · l<uuid> solo su questo telefono · a<n> area dell'evento · t… temporaneo
    var tipo: String            // linea, freccia, area, recinto, interdetta, zona, cerchi, testo, rotta, misura, traccia
    var coord: [[Double]]
    var testo: String = ""
    var colore: String = "#E8B24A"
    var raggi: [Double] = []
    var tratteggio = false
    var autore: String = ""

    var coordinate: [CLLocationCoordinate2D] { coord.map { .init(latitude: $0[0], longitude: $0[1]) } }

    var nomeTipo: String {
        ["linea": "Linea", "freccia": "Freccia", "area": "Area", "recinto": "Recinto", "interdetta": "Area interdetta",
         "zona": "Area dell'evento", "cerchi": "Cerchi di distanza", "testo": "Testo", "rotta": "Rotta",
         "misura": "Misura", "traccia": "Traccia"][tipo] ?? tipo.capitalized
    }
    var icona: String {
        switch tipo {
        case "linea": return "scribble"
        case "freccia": return "arrow.up.right"
        case "area", "zona": return "square.dashed"
        case "recinto": return "bell.badge"
        case "interdetta": return "nosign"
        case "cerchi": return "circle.circle"
        case "testo": return "textformat"
        case "rotta": return "point.3.connected.trianglepath.dotted"
        case "misura": return "ruler"
        default: return "point.bottomleft.forward.to.point.topright.scurvepath"
        }
    }
    var condiviso: Bool { id.hasPrefix("d") }
    var mio: Bool { id.hasPrefix("l") }

    static func da(_ d: JDisegno) -> ElementoLivello {
        ElementoLivello(id: "d\(d.id)", tipo: d.tipo, coord: d.coord, testo: d.testo ?? "",
                        colore: esadecimale(PannelloDisegno.colore(d.colore)), raggi: d.raggi ?? [],
                        tratteggio: d.tipo == "recinto", autore: d.callsign ?? "")
    }
}

func esadecimale(_ c: Color) -> String {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
    return String(format: "#%02X%02X%02X", Int(max(0, min(1, r)) * 255), Int(max(0, min(1, g)) * 255), Int(max(0, min(1, b)) * 255))
}

func coloreEsa(_ h: String) -> UIColor {
    let s = h.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard s.count == 6, let v = UInt32(s, radix: 16) else { return .systemYellow }
    return UIColor(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}

/// Punto a una distanza e un azimut da c (sfera, abbastanza preciso per i cerchi di distanza).
func puntoVerso(_ c: CLLocationCoordinate2D, metri: Double, azimut: Double) -> CLLocationCoordinate2D {
    let R = 6_371_000.0, d = metri / R, b = azimut * .pi / 180
    let la = c.latitude * .pi / 180, lo = c.longitude * .pi / 180
    let la2 = asin(sin(la) * cos(d) + cos(la) * sin(d) * cos(b))
    let lo2 = lo + atan2(sin(b) * sin(d) * cos(la), cos(d) - sin(la) * sin(la2))
    return .init(latitude: la2 * 180 / .pi, longitude: lo2 * 180 / .pi)
}

// MARK: - Archivio dei livelli: gruppi, sottogruppi, nascosti, nomi

@MainActor
final class Livelli: ObservableObject {
    static let shared = Livelli()
    @Published private(set) var miei: [ElementoLivello] = []
    @Published private(set) var nascosti: Set<String> = []            // id elemento, oppure "g:<percorso gruppo>"
    @Published private(set) var gruppi: [String: String] = [:]         // id elemento → "Gruppo/Sottogruppo"
    @Published private(set) var nomi: [String: String] = [:]
    @Published private(set) var creati: [String] = []                  // gruppi creati a mano (anche vuoti)
    @Published private(set) var versione = 0
    private let d = UserDefaults.standard
    /// ogni mappa ha i suoi livelli: "p" = personale, "e<id>" = evento
    @Published private(set) var chiave = "p"

    init() {
        // i livelli di prima (uno solo per tutte le mappe) diventano quelli della mappa personale
        for k in ["miei", "nascosti", "gruppi", "nomi", "creati"] where d.object(forKey: "livelli.\(k)") != nil && d.object(forKey: "livelli.p.\(k)") == nil {
            d.set(d.object(forKey: "livelli.\(k)"), forKey: "livelli.p.\(k)")
            d.removeObject(forKey: "livelli.\(k)")
        }
        carica()
    }

    private func k(_ s: String) -> String { "livelli.\(chiave).\(s)" }

    private func carica() {
        miei = (d.data(forKey: k("miei")).flatMap { try? JSONDecoder().decode([ElementoLivello].self, from: $0) }) ?? []
        nascosti = Set(d.stringArray(forKey: k("nascosti")) ?? [])
        gruppi = (d.dictionary(forKey: k("gruppi")) as? [String: String]) ?? [:]
        nomi = (d.dictionary(forKey: k("nomi")) as? [String: String]) ?? [:]
        creati = d.stringArray(forKey: k("creati")) ?? []
    }

    func contesto(_ c: String) {
        guard c != chiave else { return }
        chiave = c
        carica()
        versione &+= 1
    }

    private func salva() {
        if let x = try? JSONEncoder().encode(miei) { d.set(x, forKey: k("miei")) }
        d.set(Array(nascosti), forKey: k("nascosti"))
        d.set(gruppi, forKey: k("gruppi"))
        d.set(nomi, forKey: k("nomi"))
        d.set(creati, forKey: k("creati"))
        versione &+= 1
    }

    /// Tutti gli elementi dell'evento (condivisi + aree) e quelli salvati su questo telefono.
    func tutti(_ disegni: [JDisegno], aree: [GaraArea]) -> [ElementoLivello] {
        let za = aree.enumerated().map { i, a in
            ElementoLivello(id: "a\(i)", tipo: a.interdetta ? "interdetta" : "zona", coord: a.punti, testo: a.nome,
                            colore: esadecimale(a.interdetta ? Theme.red : Theme.olive), tratteggio: !a.interdetta)
        }
        return za + disegni.map(ElementoLivello.da) + miei
    }

    func nome(_ e: ElementoLivello) -> String { nomi[e.id] ?? (e.testo.isEmpty ? e.nomeTipo : e.testo) }

    func gruppo(_ e: ElementoLivello) -> String {
        if let g = gruppi[e.id] { return g }
        if e.id.hasPrefix("a") { return "Aree dell'evento" }
        return e.condiviso ? "Condivisi" : "Miei"
    }

    func gruppoNascosto(_ percorso: String) -> Bool {
        let parti = percorso.split(separator: "/").map(String.init)
        return (1...max(parti.count, 1)).contains { n in nascosti.contains("g:" + parti.prefix(n).joined(separator: "/")) }
    }
    func visibile(_ e: ElementoLivello) -> Bool { !nascosti.contains(e.id) && !gruppoNascosto(gruppo(e)) }

    func cambia(_ e: ElementoLivello) {
        if nascosti.contains(e.id) { nascosti.remove(e.id) } else { nascosti.insert(e.id) }
        salva()
    }
    func cambiaGruppo(_ percorso: String) {
        let k = "g:" + percorso
        if nascosti.contains(k) { nascosti.remove(k) } else { nascosti.insert(k) }
        salva()
    }
    func rinomina(_ e: ElementoLivello, _ n: String) {
        let t = n.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { nomi.removeValue(forKey: e.id) } else { nomi[e.id] = t }
        salva()
    }
    func sposta(_ e: ElementoLivello, in percorso: String) {
        let p = Self.pulisci(percorso)
        guard !p.isEmpty else { return }
        gruppi[e.id] = p
        if !creati.contains(p) { creati.append(p) }
        salva()
    }
    func creaGruppo(_ percorso: String) {
        let p = Self.pulisci(percorso)
        guard !p.isEmpty, !creati.contains(p) else { return }
        creati.append(p); salva()
    }
    /// Toglie il gruppo: i suoi elementi tornano nel gruppo di sopra (o in quello di partenza).
    func eliminaGruppo(_ percorso: String) {
        let sopra = percorso.split(separator: "/").dropLast().joined(separator: "/")
        for (k, v) in gruppi where v == percorso || v.hasPrefix(percorso + "/") {
            if sopra.isEmpty { gruppi.removeValue(forKey: k) } else { gruppi[k] = sopra }
        }
        creati.removeAll { $0 == percorso || $0.hasPrefix(percorso + "/") }
        nascosti = nascosti.filter { !($0 == "g:" + percorso || $0.hasPrefix("g:" + percorso + "/")) }
        salva()
    }
    func rinominaGruppo(_ percorso: String, _ nuovo: String) {
        let n = Self.pulisci(nuovo)
        guard !n.isEmpty, n != percorso else { return }
        func sostituisci(_ v: String) -> String { v == percorso ? n : (v.hasPrefix(percorso + "/") ? n + v.dropFirst(percorso.count) : v) }
        gruppi = gruppi.mapValues(sostituisci)
        creati = creati.map(sostituisci)
        nascosti = Set(nascosti.map { $0.hasPrefix("g:") ? "g:" + sostituisci(String($0.dropFirst(2))) : $0 })
        if !creati.contains(n) { creati.append(n) }
        salva()
    }

    func aggiungi(_ e: ElementoLivello) { miei.append(e); salva() }

    /// Elimina: dal telefono se è tuo, dal server (per tutta la squadra) se è condiviso.
    func elimina(_ e: ElementoLivello) async throws {
        if e.mio {
            miei.removeAll { $0.id == e.id }
        } else if e.condiviso, let id = Int(e.id.dropFirst()) {
            try await JsocClient.shared.cancellaDisegno(id)
            await EventoStore.shared.aggiorna(JsocClient.shared)
        }
        nomi.removeValue(forKey: e.id); gruppi.removeValue(forKey: e.id); nascosti.remove(e.id)
        salva()
    }

    /// Tutti i percorsi dei gruppi, padri compresi, in ordine.
    func percorsi(_ el: [ElementoLivello]) -> [String] {
        var s = Set(creati)
        for e in el { s.insert(gruppo(e)) }
        for p in Array(s) {
            let parti = p.split(separator: "/")
            for n in 1..<max(parti.count, 1) { s.insert(parti.prefix(n).joined(separator: "/")) }
        }
        return s.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func pulisci(_ p: String) -> String {
        p.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "/")
    }
}

// MARK: - Disegno nel motore della mappa

enum ImmaginiLivelli {
    static func punta(_ col: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 22, height: 22)).image { _ in
            let p = UIBezierPath()
            p.move(to: CGPoint(x: 11, y: 1)); p.addLine(to: CGPoint(x: 20, y: 19)); p.addLine(to: CGPoint(x: 11, y: 15)); p.addLine(to: CGPoint(x: 2, y: 19)); p.close()
            col.setFill(); p.fill()
            UIColor.black.withAlphaComponent(0.6).setStroke(); p.lineWidth = 1.2; p.stroke()
        }
    }
    static func pallino(_ col: UIColor, _ testo: String = "") -> UIImage {
        let lato: CGFloat = testo.isEmpty ? 10 : 20
        return UIGraphicsImageRenderer(size: CGSize(width: lato, height: lato)).image { _ in
            let p = UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: lato - 2, height: lato - 2))
            col.setFill(); p.fill()
            UIColor.black.withAlphaComponent(0.7).setStroke(); p.lineWidth = 1.2; p.stroke()
            if !testo.isEmpty {
                let a: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 10, weight: .heavy), .foregroundColor: UIColor.black]
                let s = (testo as NSString).size(withAttributes: a)
                (testo as NSString).draw(at: CGPoint(x: (lato - s.width) / 2, y: (lato - s.height) / 2), withAttributes: a)
            }
        }
    }
    static func scritta(_ testo: String, _ col: UIColor) -> UIImage {
        let a: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 11, weight: .heavy), .foregroundColor: col]
        let t = (testo as NSString).size(withAttributes: a)
        let size = CGSize(width: ceil(t.width) + 10, height: ceil(t.height) + 6)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.black.withAlphaComponent(0.66).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 5).fill()
            (testo as NSString).draw(at: CGPoint(x: 5, y: 3), withAttributes: a)
        }
    }
}

/// Un simbolo da mettere sulla mappa (punta di freccia, scritta, numero di tappa): immagine + rotazione rispetto al nord.
struct SimboloLivello {
    let coord: CLLocationCoordinate2D
    let nome: String
    let immagine: () -> UIImage
    var rot: Double = 0
    var ruota = false
}

/// Scompone gli elementi in linee, aree e simboli: lo usano sia MapLibre sia la mappa Apple.
struct FormeLivelli {
    var linee: [(c: [CLLocationCoordinate2D], col: String, w: Double, tratto: Bool)] = []
    var aree: [(c: [CLLocationCoordinate2D], col: String, op: Double, tratto: Bool)] = []
    var cerchi: [(c: CLLocationCoordinate2D, r: Double, col: String)] = []
    var simboli: [SimboloLivello] = []

    init(_ el: [ElementoLivello]) {
        for e in el {
            let c = e.coordinate
            guard let primo = c.first else { continue }
            let col = e.colore, ui = coloreEsa(col)
            switch e.tipo {
            case "area", "recinto", "interdetta", "zona":
                guard c.count >= 3 else { continue }
                aree.append((c, col, e.tipo == "zona" ? 0.05 : 0.16, e.tratteggio || e.tipo == "recinto" || e.tipo == "zona"))
                let t = e.tipo == "recinto" ? "⚠ " + (e.testo.isEmpty ? "RECINTO" : e.testo) : e.testo
                if !t.isEmpty {
                    let cx = c.map(\.latitude).reduce(0, +) / Double(c.count), cy = c.map(\.longitude).reduce(0, +) / Double(c.count)
                    simboli.append(SimboloLivello(coord: .init(latitude: cx, longitude: cy), nome: "liv-t-\(t)-\(col)") { ImmaginiLivelli.scritta(t, ui) })
                }
            case "cerchi":
                for r in e.raggi {
                    cerchi.append((primo, r, col))
                    let t = r >= 1000 ? String(format: "%.1f km", r / 1000) : "\(Int(r)) m"
                    simboli.append(SimboloLivello(coord: puntoVerso(primo, metri: r, azimut: 0), nome: "liv-t-\(t)-\(col)") { ImmaginiLivelli.scritta(t, ui) })
                }
                simboli.append(SimboloLivello(coord: primo, nome: "liv-p-\(col)") { ImmaginiLivelli.pallino(ui) })
            case "testo":
                let t = e.testo.isEmpty ? "testo" : e.testo
                simboli.append(SimboloLivello(coord: primo, nome: "liv-t-\(t)-\(col)") { ImmaginiLivelli.scritta(t, ui) })
            default:
                guard c.count >= 2 else { continue }
                linee.append((c, col, e.tipo == "traccia" ? 3.5 : 3, e.tratteggio || e.tipo == "misura"))
                if e.tipo == "freccia", let a = c.dropLast().last, let b = c.last {
                    simboli.append(SimboloLivello(coord: b, nome: "liv-f-\(col)", immagine: { ImmaginiLivelli.punta(ui) },
                                                  rot: Geo.bearing(a, b), ruota: true))
                }
                if e.tipo == "rotta" {
                    for (i, p) in c.enumerated() {
                        simboli.append(SimboloLivello(coord: p, nome: "liv-n-\(i + 1)-\(col)") { ImmaginiLivelli.pallino(ui, "\(i + 1)") })
                    }
                }
                if e.tipo == "misura" {
                    var tot = 0.0
                    for i in 1..<c.count {
                        tot += Geo.distance(c[i - 1], c[i])
                        let t = "\(Geo.formatDistance(tot)) · \(gradi3(Geo.bearing(c[i - 1], c[i])))"
                        simboli.append(SimboloLivello(coord: c[i], nome: "liv-t-\(t)-\(col)") { ImmaginiLivelli.scritta(t, ui) })
                    }
                    for p in c { simboli.append(SimboloLivello(coord: p, nome: "liv-p-\(col)") { ImmaginiLivelli.pallino(ui) }) }
                } else if !e.testo.isEmpty, e.tipo != "rotta", e.tipo != "traccia" {
                    simboli.append(SimboloLivello(coord: c[c.count / 2], nome: "liv-t-\(e.testo)-\(col)") { ImmaginiLivelli.scritta(e.testo, ui) })
                }
            }
        }
    }
}

extension MappaCtl {
    /// Da chiamare a ogni cambiamento: ridisegna solo se qualcosa è cambiato davvero.
    func impostaDisegni(_ el: [ElementoLivello]) {
        guard el != disegniMappa else { return }
        disegniMappa = el
        if mk != nil { applicaDisegniApple() } else { applicaDisegniLibre() }
    }

    func applicaDisegniLibre() {
        guard let m = mappa, let st = m.style else { return }
        let f = FormeLivelli(disegniMappa)
        var forme: [MLNShape] = []
        for l in f.linee {
            var c = l.c
            let x = MLNPolylineFeature(coordinates: &c, count: UInt(c.count))
            x.attributes = ["k": "l", "colore": l.col, "w": l.w, "tratto": l.tratto]
            forme.append(x)
        }
        for a in f.aree {
            var c = a.c + [a.c[0]]
            let x = MLNPolygonFeature(coordinates: &c, count: UInt(c.count))
            x.attributes = ["k": "a", "colore": a.col, "op": a.op]
            forme.append(x)
            let b = MLNPolylineFeature(coordinates: &c, count: UInt(c.count))
            b.attributes = ["k": "l", "colore": a.col, "w": 2.5, "tratto": a.tratto]
            forme.append(b)
        }
        for k in f.cerchi {
            var c = (0...72).map { puntoVerso(k.c, metri: k.r, azimut: Double($0) * 5) }
            let x = MLNPolylineFeature(coordinates: &c, count: UInt(c.count))
            x.attributes = ["k": "l", "colore": k.col, "w": 2.2, "tratto": true]
            forme.append(x)
        }
        for s in f.simboli {
            if !immaginiFatte.contains(s.nome) || st.image(forName: s.nome) == nil {
                st.setImage(s.immagine(), forName: s.nome); immaginiFatte.insert(s.nome)
            }
            let x = MLNPointFeature()
            x.coordinate = s.coord
            x.attributes = ["k": "s", "img": s.nome, "rot": s.rot]
            forme.append(x)
        }
        let insieme = MLNShapeCollectionFeature(shapes: forme)
        if let src = st.source(withIdentifier: "livelli-disegni") as? MLNShapeSource { src.shape = insieme; return }
        let src = MLNShapeSource(identifier: "livelli-disegni", shape: insieme, options: nil)
        st.addSource(src)
        let sotto = st.layer(withIdentifier: "segni-etichette")
        func metti(_ l: MLNStyleLayer) { if let sotto { st.insertLayer(l, below: sotto) } else { st.addLayer(l) } }

        let ri = MLNFillStyleLayer(identifier: "liv-riempimenti", source: src)
        ri.predicate = NSPredicate(format: "k == 'a'")
        ri.fillColor = NSExpression(forKeyPath: "colore")
        ri.fillOpacity = NSExpression(forKeyPath: "op")
        metti(ri)
        let bo = MLNLineStyleLayer(identifier: "liv-bordi", source: src)
        bo.predicate = NSPredicate(format: "k == 'l'")
        bo.lineColor = NSExpression(forConstantValue: UIColor.black.withAlphaComponent(0.5))
        bo.lineWidth = NSExpression(forConstantValue: 5)
        bo.lineCap = NSExpression(forConstantValue: "round"); bo.lineJoin = NSExpression(forConstantValue: "round")
        metti(bo)
        let pi = MLNLineStyleLayer(identifier: "liv-linee", source: src)
        pi.predicate = NSPredicate(format: "k == 'l' AND tratto == NO")
        pi.lineColor = NSExpression(forKeyPath: "colore")
        pi.lineWidth = NSExpression(forKeyPath: "w")
        pi.lineCap = NSExpression(forConstantValue: "round"); pi.lineJoin = NSExpression(forConstantValue: "round")
        metti(pi)
        let tr = MLNLineStyleLayer(identifier: "liv-tratti", source: src)
        tr.predicate = NSPredicate(format: "k == 'l' AND tratto == YES")
        tr.lineColor = NSExpression(forKeyPath: "colore")
        tr.lineWidth = NSExpression(forKeyPath: "w")
        tr.lineDashPattern = NSExpression(forConstantValue: [2.2, 1.6])
        metti(tr)
        let si = MLNSymbolStyleLayer(identifier: "liv-simboli", source: src)
        si.predicate = NSPredicate(format: "k == 's'")
        si.iconImageName = NSExpression(forKeyPath: "img")
        si.iconRotation = NSExpression(forKeyPath: "rot")
        si.iconRotationAlignment = NSExpression(forConstantValue: "map")
        si.iconPitchAlignment = NSExpression(forConstantValue: "map")
        si.iconAllowsOverlap = NSExpression(forConstantValue: true)
        si.iconIgnoresPlacement = NSExpression(forConstantValue: true)
        metti(si)
    }

    func applicaDisegniApple() {
        guard let m = mk else { return }
        m.removeOverlays(m.overlays.filter { $0 is LineaLivello || $0 is AreaLivello || $0 is CerchioLivello })
        m.removeAnnotations(m.annotations.filter { $0 is SimboloAnnotation })
        let f = FormeLivelli(disegniMappa)
        var o: [MKOverlay] = []
        for l in f.linee {
            let x = LineaLivello(coordinates: l.c, count: l.c.count)
            x.colore = coloreEsa(l.col); x.w = l.w; x.tratto = l.tratto
            o.append(x)
        }
        for a in f.aree {
            let x = AreaLivello(coordinates: a.c, count: a.c.count)
            x.colore = coloreEsa(a.col); x.op = a.op; x.tratto = a.tratto
            o.append(x)
        }
        for k in f.cerchi {
            let x = CerchioLivello(center: k.c, radius: k.r)
            x.colore = coloreEsa(k.col)
            o.append(x)
        }
        m.addOverlays(o, level: .aboveRoads)
        m.addAnnotations(f.simboli.map { SimboloAnnotation($0) })
    }
}

// MARK: - Mappa Apple: forme stese sul terreno

final class LineaLivello: MKPolyline { var colore = UIColor.systemYellow; var w = 3.0; var tratto = false }
final class AreaLivello: MKPolygon { var colore = UIColor.systemYellow; var op = 0.16; var tratto = false }
final class CerchioLivello: MKCircle { var colore = UIColor.systemYellow }

final class SimboloAnnotation: NSObject, MKAnnotation {
    let simbolo: SimboloLivello
    let immagine: UIImage
    var coordinate: CLLocationCoordinate2D { simbolo.coord }
    init(_ s: SimboloLivello) { simbolo = s; immagine = s.immagine() }
}

final class SimboloAppleView: MKAnnotationView {
    private let img = UIImageView()
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        addSubview(img)
        displayPriority = .required
        collisionMode = .none
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError() }

    func configura(_ a: SimboloAnnotation, rotazioneMappa: Double) {
        img.image = a.immagine
        frame = CGRect(origin: .zero, size: a.immagine.size)
        img.frame = bounds
        ruota(a, rotazioneMappa)
    }
    func ruota(_ a: SimboloAnnotation, _ rotazioneMappa: Double) {
        img.transform = a.simbolo.ruota ? CGAffineTransform(rotationAngle: CGFloat((a.simbolo.rot - rotazioneMappa) * .pi / 180)) : .identity
    }
}

enum DisegniApple {
    static func renderer(_ o: MKOverlay) -> MKOverlayRenderer? {
        if let l = o as? LineaLivello {
            let r = MKPolylineRenderer(polyline: l)
            r.strokeColor = l.colore; r.lineWidth = l.w; r.lineCap = .round; r.lineJoin = .round
            if l.tratto { r.lineDashPattern = [8, 6] }
            return r
        }
        if let a = o as? AreaLivello {
            let r = MKPolygonRenderer(polygon: a)
            r.fillColor = a.colore.withAlphaComponent(a.op); r.strokeColor = a.colore; r.lineWidth = 2.5
            if a.tratto { r.lineDashPattern = [10, 6] }
            return r
        }
        if let c = o as? CerchioLivello {
            let r = MKCircleRenderer(circle: c)
            r.strokeColor = c.colore; r.lineWidth = 2.2; r.lineDashPattern = [7, 5]
            return r
        }
        return nil
    }
}

// MARK: - Pannello Livelli

struct PannelloLivelli: View {
    @ObservedObject var ctl: MappaCtl
    @Binding var griglia: Bool
    @Binding var aree: Bool
    @Binding var squadra: Bool
    var chiudi: () -> Void
    var scarica: () -> Void
    @ObservedObject private var livelli = Livelli.shared
    @ObservedObject private var store = EventoStore.shared
    @State private var chiusi: Set<String> = []
    @State private var nuovoGruppo = ""
    @State private var rinominaEl: ElementoLivello?
    @State private var rinominaGr: String?
    @State private var testo = ""
    @State private var spostaEl: ElementoLivello?
    @State private var daEliminare: ElementoLivello?
    @State private var errore: String?

    var elementi: [ElementoLivello] { livelli.tutti(store.corrente?.disegni ?? DatiEvento.disegni, aree: DatiEvento.aree) }

    var body: some View {
        let el = elementi
        let percorsi = livelli.percorsi(el)
        VStack(spacing: 0) {
            TestataPannello(titolo: "Livelli", sotto: "\(el.count) elementi · tieni premuto per le opzioni", chiudi: chiudi)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    EtichettaSezione(testo: "Sopra la mappa")
                    Toggle("Griglia MGRS", isOn: $griglia).font(.system(size: 13, weight: .semibold))
                    Toggle("Squadra", isOn: $squadra).font(.system(size: 13, weight: .semibold))
                    Toggle("Disegni e aree", isOn: $aree).font(.system(size: 13, weight: .semibold))
                    if let errore { Text(errore).font(.caption).foregroundStyle(Theme.amber) }
                    EtichettaSezione(testo: "Gruppi")
                    ForEach(percorsi, id: \.self) { p in
                        if !nascostoDaChiuso(p) {
                            rigaGruppo(p, conta: el.filter { livelli.gruppo($0) == p || livelli.gruppo($0).hasPrefix(p + "/") }.count)
                            if !chiusi.contains(p) {
                                ForEach(el.filter { livelli.gruppo($0) == p }) { e in rigaElemento(e, livello: profondita(p) + 1) }
                            }
                        }
                    }
                    HStack {
                        TextField("Nuovo gruppo (es. Fase 1/Squadra A)", text: $nuovoGruppo)
                            .padding(9).background(Theme.surface2.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                        Button("Crea") { haptic(); livelli.creaGruppo(nuovoGruppo); nuovoGruppo = "" }
                            .buttonStyle(.bordered).tint(Theme.olive)
                    }
                    Text("Usa la barra / per i sottogruppi. I gruppi e ciò che nascondi valgono solo su questo telefono; eliminare un disegno condiviso lo toglie a tutta la squadra.")
                        .font(.caption2).foregroundStyle(Theme.dim)
                }
                .padding(14)
            }
        }
        .alert("Rinomina", isPresented: Binding(get: { rinominaEl != nil || rinominaGr != nil }, set: { if !$0 { rinominaEl = nil; rinominaGr = nil } })) {
            TextField("Nome", text: $testo)
            Button("Salva") {
                if let e = rinominaEl { livelli.rinomina(e, testo) }
                if let g = rinominaGr { livelli.rinominaGruppo(g, testo) }
                rinominaEl = nil; rinominaGr = nil
            }
            Button("Annulla", role: .cancel) { rinominaEl = nil; rinominaGr = nil }
        }
        .confirmationDialog("Sposta in", isPresented: Binding(get: { spostaEl != nil }, set: { if !$0 { spostaEl = nil } }), titleVisibility: .visible) {
            ForEach(percorsi, id: \.self) { p in
                Button(p) { if let e = spostaEl { livelli.sposta(e, in: p) }; spostaEl = nil }
            }
            Button("Annulla", role: .cancel) { spostaEl = nil }
        }
        .confirmationDialog("Eliminare \(daEliminare.map { livelli.nome($0) } ?? "")?",
                            isPresented: Binding(get: { daEliminare != nil }, set: { if !$0 { daEliminare = nil } }), titleVisibility: .visible) {
            Button(daEliminare?.condiviso == true ? "Elimina per tutta la squadra" : "Elimina", role: .destructive) {
                guard let e = daEliminare else { return }
                daEliminare = nil
                Task {
                    do { try await livelli.elimina(e); errore = nil } catch { errore = "Non eliminato: \(error.localizedDescription)" }
                }
            }
            Button("Annulla", role: .cancel) { daEliminare = nil }
        } message: {
            Text(daEliminare?.condiviso == true ? "È condiviso: sparisce dalla mappa di tutti." : "Sparisce da questo telefono.")
        }
    }

    func profondita(_ p: String) -> Int { p.split(separator: "/").count - 1 }
    func nascostoDaChiuso(_ p: String) -> Bool {
        let parti = p.split(separator: "/").map(String.init)
        guard parti.count > 1 else { return false }
        return (1..<parti.count).contains { chiusi.contains(parti.prefix($0).joined(separator: "/")) }
    }

    func rigaGruppo(_ p: String, conta: Int) -> some View {
        let spento = livelli.gruppoNascosto(p)
        return HStack(spacing: 8) {
            Button { withAnimation(.easeOut(duration: 0.2)) { if chiusi.contains(p) { chiusi.remove(p) } else { chiusi.insert(p) } } } label: {
                Image(systemName: chiusi.contains(p) ? "chevron.right" : "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.dim).frame(width: 16)
            }
            Image(systemName: "folder.fill").foregroundStyle(Theme.oliveBright.opacity(spento ? 0.4 : 1))
            Text(String(p.split(separator: "/").last ?? "")).font(.system(size: 13.5, weight: .heavy)).foregroundStyle(spento ? Theme.dim : .white)
            Text("\(conta)").font(Theme.mono(10, .bold)).foregroundStyle(Theme.dim)
            Spacer()
            Button { haptic(); livelli.cambiaGruppo(p) } label: {
                Image(systemName: spento ? "eye.slash" : "eye").font(.system(size: 15, weight: .semibold)).foregroundStyle(spento ? Theme.dim : Theme.oliveBright)
                    .frame(width: 34, height: 30)
            }
        }
        .padding(.leading, CGFloat(profondita(p)) * 16)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button { livelli.creaGruppo(p + "/Nuovo") } label: { Label("Nuovo sottogruppo", systemImage: "folder.badge.plus") }
            Button { testo = String(p); rinominaGr = p } label: { Label("Rinomina", systemImage: "pencil") }
            Button(role: .destructive) { livelli.eliminaGruppo(p) } label: { Label("Togli il gruppo (gli elementi restano)", systemImage: "folder.badge.minus") }
        }
    }

    func rigaElemento(_ e: ElementoLivello, livello: Int) -> some View {
        let acceso = !livelli.nascosti.contains(e.id)
        return HStack(spacing: 8) {
            Image(systemName: e.icona).font(.system(size: 13, weight: .bold)).foregroundStyle(Color(coloreEsa(e.colore))).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(livelli.nome(e)).font(.system(size: 13, weight: .semibold)).foregroundStyle(acceso ? .white : Theme.dim).lineLimit(1)
                Text(e.nomeTipo + (e.autore.isEmpty ? "" : " · \(e.autore)") + (e.mio ? " · solo mio" : ""))
                    .font(.system(size: 10)).foregroundStyle(Theme.dim).lineLimit(1)
            }
            Spacer()
            Button { haptic(); livelli.cambia(e) } label: {
                Image(systemName: acceso ? "eye" : "eye.slash").font(.system(size: 14, weight: .semibold)).foregroundStyle(acceso ? Theme.oliveBright : Theme.dim)
                    .frame(width: 34, height: 30)
            }
        }
        .padding(.leading, CGFloat(livello) * 16)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { ctl.inquadra(e.coordinate) }
        .contextMenu {
            Button { ctl.inquadra(e.coordinate) } label: { Label("Centra sulla mappa", systemImage: "scope") }
            Button { testo = livelli.nome(e); rinominaEl = e } label: { Label("Rinomina", systemImage: "pencil") }
            Button { spostaEl = e } label: { Label("Sposta in un gruppo", systemImage: "folder") }
            if !e.id.hasPrefix("a") {
                Button(role: .destructive) { daEliminare = e } label: { Label("Elimina", systemImage: "trash") }
            }
        }
    }
}
