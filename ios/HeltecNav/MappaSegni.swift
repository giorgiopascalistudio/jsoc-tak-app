import UIKit
import MapLibre
import CoreLocation

/// Un segnaposto disegnato DA MAPLIBRE (non sopra la mappa): così ruota e scorre insieme alla mappa,
/// le etichette che si sovrappongono spariscono da sole finché non si zooma, e i tocchi si leggono dalla mappa.
struct SegnoMappa: Equatable {
    enum Forma: String { case rombo, cerchio, triangolo, freccia, pallino, quadro, quadrato }
    let chiave: String          // "p12" punto, "c3" compagno
    let coord: CLLocationCoordinate2D
    let forma: Forma
    let colore: UIColor
    let glifo: String
    let etichetta: String
    let rotazione: Double?       // solo compagni: dove guardano (gradi dal nord)
    let priorita: Int            // 0 = vince le collisioni
    let scelto: Bool

    static func == (a: SegnoMappa, b: SegnoMappa) -> Bool {
        a.chiave == b.chiave && a.coord.latitude == b.coord.latitude && a.coord.longitude == b.coord.longitude
            && a.glifo == b.glifo && a.etichetta == b.etichetta && a.rotazione == b.rotazione && a.scelto == b.scelto
            && a.forma == b.forma && a.colore == b.colore
    }

    var nomeIcona: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, al: CGFloat = 0
        colore.getRed(&r, green: &g, blue: &b, alpha: &al)
        return "ic-\(forma.rawValue)-\(Int(r * 255))-\(Int(g * 255))-\(Int(b * 255))-\(glifo)-\(scelto ? 1 : 0)-\(rotazione == nil ? 0 : 1)"
    }
    var nomeEtichetta: String { "et-\(etichetta)" }
}

enum DisegnoSegni {
    static let scala = UIScreen.main.scale

    static func icona(_ s: SegnoMappa) -> UIImage {
        let lato: CGFloat = s.forma == .freccia ? 48 : 40
        return UIGraphicsImageRenderer(size: CGSize(width: lato, height: lato)).image { ctx in
            let c = CGPoint(x: lato / 2, y: lato / 2)
            let g = ctx.cgContext
            if s.scelto {
                g.setStrokeColor(UIColor(red: 0.74, green: 0.82, blue: 0.48, alpha: 1).cgColor)
                g.setLineWidth(3)
                g.strokeEllipse(in: CGRect(x: c.x - 18, y: c.y - 18, width: 36, height: 36))
            }
            g.setStrokeColor(UIColor.black.cgColor)
            g.setFillColor(s.colore.cgColor)
            switch s.forma {
            case .rombo:
                let p = UIBezierPath()
                p.move(to: CGPoint(x: c.x, y: c.y - 13)); p.addLine(to: CGPoint(x: c.x + 13, y: c.y))
                p.addLine(to: CGPoint(x: c.x, y: c.y + 13)); p.addLine(to: CGPoint(x: c.x - 13, y: c.y)); p.close()
                p.lineWidth = 2; p.fill(); p.stroke()
            case .triangolo:
                let p = UIBezierPath()
                p.move(to: CGPoint(x: c.x, y: c.y - 12)); p.addLine(to: CGPoint(x: c.x + 12, y: c.y + 9))
                p.addLine(to: CGPoint(x: c.x - 12, y: c.y + 9)); p.close()
                p.lineWidth = 1.8; p.fill(); p.stroke()
            case .cerchio:
                let p = UIBezierPath(ovalIn: CGRect(x: c.x - 10, y: c.y - 10, width: 20, height: 20))
                p.lineWidth = 2; p.fill(); p.stroke()
            case .quadro:
                let p = UIBezierPath(roundedRect: CGRect(x: c.x - 15, y: c.y - 10, width: 30, height: 20), cornerRadius: 2)
                p.lineWidth = 2; p.fill(); p.stroke()
            case .quadrato:
                let p = UIBezierPath(rect: CGRect(x: c.x - 12, y: c.y - 12, width: 24, height: 24))
                p.lineWidth = 2; p.fill(); p.stroke()
            case .pallino:
                let p = UIBezierPath(ovalIn: CGRect(x: c.x - 8, y: c.y - 8, width: 16, height: 16))
                UIColor.white.setStroke(); p.lineWidth = 2.5; p.fill(); p.stroke()
            case .freccia:
                if s.rotazione != nil {
                    let f = UIBezierPath()
                    f.move(to: CGPoint(x: c.x, y: c.y - 22)); f.addLine(to: CGPoint(x: c.x + 8, y: c.y - 9))
                    f.addLine(to: CGPoint(x: c.x - 8, y: c.y - 9)); f.close()
                    f.lineWidth = 1; f.fill(); f.stroke()
                }
                let p = UIBezierPath(ovalIn: CGRect(x: c.x - 8, y: c.y - 8, width: 16, height: 16))
                UIColor.white.setStroke(); p.lineWidth = 2.5; p.fill(); p.stroke()
            }
            if !s.glifo.isEmpty {
                let f = UIFont.monospacedSystemFont(ofSize: s.glifo.count > 2 ? 7 : (s.glifo.count > 1 ? 8 : 10.5), weight: .heavy)
                let a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: UIColor.black]
                let t = (s.glifo as NSString).size(withAttributes: a)
                (s.glifo as NSString).draw(at: CGPoint(x: c.x - t.width / 2, y: c.y - t.height / 2 + (s.forma == .triangolo ? 3 : 0)), withAttributes: a)
            }
        }
    }

    /// Etichetta come immagine (testo bianco con alone nero): funziona anche offline, senza font scaricati.
    static func etichetta(_ testo: String) -> UIImage {
        let f = UIFont.systemFont(ofSize: 12, weight: .bold)
        let a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: UIColor.white]
        let t = (testo as NSString).size(withAttributes: a)
        let size = CGSize(width: ceil(t.width) + 8, height: ceil(t.height) + 6)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let g = ctx.cgContext
            g.setTextDrawingMode(.stroke)
            g.setLineWidth(3.5)
            g.setLineJoin(.round)
            let alone: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: UIColor.black, .strokeColor: UIColor.black, .strokeWidth: 7]
            (testo as NSString).draw(at: CGPoint(x: 4, y: 3), withAttributes: alone)
            g.setTextDrawingMode(.fill)
            (testo as NSString).draw(at: CGPoint(x: 4, y: 3), withAttributes: a)
        }
    }
}

extension MappaCtl {
    static let livelliToccabili = ["segni-punti", "segni-compagni"]

    /// Aggiorna i segnaposti (solo se cambiano davvero).
    func impostaSegni(_ s: [SegnoMappa]) {
        guard s != segni else { return }
        segni = s
        if mk != nil { applicaSegniApple() } else { applicaSegni() }
    }

    /// Ridisegna sorgente e livelli (anche dopo un cambio di stile, che li cancella).
    func applicaSegni() {
        guard let m = mappa, let st = m.style else { return }
        for x in segni {
            if !immaginiFatte.contains(x.nomeIcona) || st.image(forName: x.nomeIcona) == nil {
                st.setImage(DisegnoSegni.icona(x), forName: x.nomeIcona); immaginiFatte.insert(x.nomeIcona)
            }
            if !immaginiFatte.contains(x.nomeEtichetta) || st.image(forName: x.nomeEtichetta) == nil {
                st.setImage(DisegnoSegni.etichetta(x.etichetta), forName: x.nomeEtichetta); immaginiFatte.insert(x.nomeEtichetta)
            }
        }
        let feats: [MLNPointFeature] = segni.map { x in
            let f = MLNPointFeature()
            f.coordinate = x.coord
            f.attributes = ["chiave": x.chiave, "tipo": x.chiave.hasPrefix("c") ? "c" : "p",
                            "icona": x.nomeIcona, "etichetta": x.nomeEtichetta,
                            "rot": x.rotazione ?? 0, "prio": x.priorita]
            return f
        }
        let forma = MLNShapeCollectionFeature(shapes: feats)
        if let src = st.source(withIdentifier: "segni") as? MLNShapeSource {
            src.shape = forma
            return
        }
        let src = MLNShapeSource(identifier: "segni", shape: forma, options: nil)
        st.addSource(src)

        let et = MLNSymbolStyleLayer(identifier: "segni-etichette", source: src)
        et.iconImageName = NSExpression(forKeyPath: "etichetta")
        et.iconAnchor = NSExpression(forConstantValue: "left")
        et.iconOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 13, dy: 0)))
        et.iconAllowsOverlap = NSExpression(forConstantValue: false)
        et.symbolSortKey = NSExpression(forKeyPath: "prio")
        st.addLayer(et)

        let pu = MLNSymbolStyleLayer(identifier: "segni-punti", source: src)
        pu.predicate = NSPredicate(format: "tipo == 'p'")
        pu.iconImageName = NSExpression(forKeyPath: "icona")
        pu.iconAllowsOverlap = NSExpression(forConstantValue: true)
        pu.iconIgnoresPlacement = NSExpression(forConstantValue: true)
        st.addLayer(pu)

        let co = MLNSymbolStyleLayer(identifier: "segni-compagni", source: src)
        co.predicate = NSPredicate(format: "tipo == 'c'")
        co.iconImageName = NSExpression(forKeyPath: "icona")
        co.iconRotation = NSExpression(forKeyPath: "rot")
        co.iconRotationAlignment = NSExpression(forConstantValue: "map")
        co.iconAllowsOverlap = NSExpression(forConstantValue: true)
        co.iconIgnoresPlacement = NSExpression(forConstantValue: true)
        st.addLayer(co)
    }

    /// Chiavi dei segnaposti sotto il dito (dalla mappa, quindi giuste anche ruotando e zoomando).
    func segniSotto(_ p: CGPoint) -> [String] {
        if mk != nil { return segniSottoApple(p) }
        guard let m = mappa else { return [] }
        let r = CGRect(x: p.x - 24, y: p.y - 24, width: 48, height: 48)
        let f = m.visibleFeatures(in: r, styleLayerIdentifiers: Set(Self.livelliToccabili))
        var visti = Set<String>(), out: [String] = []
        // dal più vicino al dito
        let ord = f.sorted { a, b in
            let pa = m.convert(a.coordinate, toPointTo: m), pb = m.convert(b.coordinate, toPointTo: m)
            return hypot(pa.x - p.x, pa.y - p.y) < hypot(pb.x - p.x, pb.y - p.y)
        }
        for x in ord {
            if let k = x.attribute(forKey: "chiave") as? String, !visti.contains(k) { visti.insert(k); out.append(k) }
        }
        return out
    }
}
