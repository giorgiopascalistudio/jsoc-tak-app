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
    static func gruppo(_ n: Int) -> UIImage {
        let lato: CGFloat = n >= 10 ? 27 : 23     // tavola 10: cerchio r 10 con bordo 1,5
        return UIGraphicsImageRenderer(size: CGSize(width: lato, height: lato)).image { _ in
            let r = CGRect(x: 1.5, y: 1.5, width: lato - 3, height: lato - 3)
            UIColor(Theme.red).withAlphaComponent(0.94).setFill()
            let p = UIBezierPath(ovalIn: r); p.fill()
            UIColor(white: 0.043, alpha: 1).setStroke(); p.lineWidth = 1.5; p.stroke()
            let t = (n >= 60 ? "60+" : "+\(n)") as NSString
            let att: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 9, weight: .heavy), .foregroundColor: UIColor(white: 0.067, alpha: 1)]
            let s = t.size(withAttributes: att)
            t.draw(at: CGPoint(x: (lato - s.width) / 2, y: (lato - s.height) / 2), withAttributes: att)
        }
    }

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
            UIColor(white: 0.043, alpha: 1).setStroke()
            switch s.forma {
            case .rombo:
                // tavola 10: quadrato di 16 pt ruotato di 45°, bordo 1,5
                let d: CGFloat = 8 * 1.41421
                let p = UIBezierPath()
                p.move(to: CGPoint(x: c.x, y: c.y - d)); p.addLine(to: CGPoint(x: c.x + d, y: c.y))
                p.addLine(to: CGPoint(x: c.x, y: c.y + d)); p.addLine(to: CGPoint(x: c.x - d, y: c.y)); p.close()
                p.lineWidth = 1.5; p.fill(); p.stroke()
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
                    // tavola 10: freccia orientata (M0 -10 7 8 0 4 -7 8Z), la ruota il livello della mappa
                    let f = UIBezierPath()
                    f.move(to: CGPoint(x: c.x, y: c.y - 10)); f.addLine(to: CGPoint(x: c.x + 7, y: c.y + 8))
                    f.addLine(to: CGPoint(x: c.x, y: c.y + 4)); f.addLine(to: CGPoint(x: c.x - 7, y: c.y + 8)); f.close()
                    f.lineWidth = 1.2; f.lineJoinStyle = .round; f.fill(); f.stroke()
                } else {
                    let p = UIBezierPath(ovalIn: CGRect(x: c.x - 8, y: c.y - 8, width: 16, height: 16))
                    UIColor.white.setStroke(); p.lineWidth = 2.5; p.fill(); p.stroke()
                }
            }
            if !s.glifo.isEmpty {
                let f = UIFont.monospacedSystemFont(ofSize: s.forma == .rombo ? 7.5 : (s.glifo.count > 2 ? 7 : (s.glifo.count > 1 ? 8 : 10.5)), weight: .heavy)
                let a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: UIColor(white: 0.067, alpha: 1)]
                let t = (s.glifo as NSString).size(withAttributes: a)
                (s.glifo as NSString).draw(at: CGPoint(x: c.x - t.width / 2, y: c.y - t.height / 2 + (s.forma == .triangolo ? 3 : 0)), withAttributes: a)
            }
        }
    }

    /// Etichetta come immagine (testo bianco con alone nero): funziona anche offline, senza font scaricati.
    static func etichetta(_ testo: String) -> UIImage {
        // tavola 10: 10,5 pt pesante, bianco con alone nero al 70% largo 3 pt
        let f = UIFont.systemFont(ofSize: 10.5, weight: .heavy)
        let a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: UIColor.white]
        let t = (testo as NSString).size(withAttributes: a)
        let size = CGSize(width: ceil(t.width) + 8, height: ceil(t.height) + 6)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let g = ctx.cgContext
            g.setTextDrawingMode(.stroke)
            g.setLineWidth(3.5)
            g.setLineJoin(.round)
            let nero = UIColor.black.withAlphaComponent(0.7)
            let alone: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: nero, .strokeColor: nero, .strokeWidth: 3 / 10.5 * 100]
            (testo as NSString).draw(at: CGPoint(x: 4, y: 3), withAttributes: alone)
            g.setTextDrawingMode(.fill)
            (testo as NSString).draw(at: CGPoint(x: 4, y: 3), withAttributes: a)
        }
    }
}

extension MappaCtl {
    static let livelliToccabili = ["segni-punti", "segni-punti-g", "segni-gruppi", "segni-compagni"]

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
        func elemento(_ x: SegnoMappa) -> MLNPointFeature {
            let f = MLNPointFeature()
            f.coordinate = x.coord
            f.attributes = ["chiave": x.chiave, "tipo": x.chiave.hasPrefix("c") ? "c" : "p",
                            "icona": x.nomeIcona, "etichetta": x.nomeEtichetta,
                            "rot": x.rotazione ?? 0, "prio": x.priorita]
            return f
        }
        // i punti dell'evento si raggruppano quando si toccherebbero; compagni, telecamere ecc. restano sempre visibili
        let sciolti = MLNShapeCollectionFeature(shapes: segni.filter { !$0.chiave.hasPrefix("p") }.map(elemento))
        let evento = MLNShapeCollectionFeature(shapes: segni.filter { $0.chiave.hasPrefix("p") }.map(elemento))
        if let a = st.source(withIdentifier: "segni") as? MLNShapeSource,
           let b = st.source(withIdentifier: "segni-g") as? MLNShapeSource {
            a.shape = sciolti
            b.shape = evento
            return
        }
        if st.image(forName: "gruppo-2") == nil {
            for n in 2...60 { st.setImage(DisegnoSegni.gruppo(n), forName: "gruppo-\(n)") }
        }
        let src = MLNShapeSource(identifier: "segni", shape: sciolti, options: nil)
        st.addSource(src)
        let grp = MLNShapeSource(identifier: "segni-g", shape: evento,
                                 options: [.clustered: false])   // mai raggruppati: ogni punto resta visibile
        st.addSource(grp)

        func etichette(_ id: String, _ s: MLNShapeSource, _ filtro: NSPredicate?) {
            let et = MLNSymbolStyleLayer(identifier: id, source: s)
            et.predicate = filtro
            et.iconImageName = NSExpression(forKeyPath: "etichetta")
            et.iconAnchor = NSExpression(forConstantValue: "left")
            et.iconOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 9, dy: 0)))   // scritta a 13 pt dal centro
            et.iconAllowsOverlap = NSExpression(forConstantValue: false)
            et.symbolSortKey = NSExpression(forKeyPath: "prio")
            st.addLayer(et)
        }
        etichette("segni-etichette", src, nil)
        etichette("segni-etichette-g", grp, NSPredicate(format: "cluster != YES"))

        let pu = MLNSymbolStyleLayer(identifier: "segni-punti", source: src)
        pu.predicate = NSPredicate(format: "tipo == 'p'")
        pu.iconImageName = NSExpression(forKeyPath: "icona")
        pu.iconAllowsOverlap = NSExpression(forConstantValue: true)
        pu.iconIgnoresPlacement = NSExpression(forConstantValue: true)
        st.addLayer(pu)

        let pg = MLNSymbolStyleLayer(identifier: "segni-punti-g", source: grp)
        pg.predicate = NSPredicate(format: "cluster != YES")
        pg.iconImageName = NSExpression(forKeyPath: "icona")
        pg.iconAllowsOverlap = NSExpression(forConstantValue: true)
        pg.iconIgnoresPlacement = NSExpression(forConstantValue: true)
        st.addLayer(pg)

        var gradini: [NSNumber: String] = [:]
        for n in 3...60 { gradini[NSNumber(value: n)] = "gruppo-\(n)" }
        let gr = MLNSymbolStyleLayer(identifier: "segni-gruppi", source: grp)
        gr.predicate = NSPredicate(format: "cluster == YES")
        gr.iconImageName = NSExpression(format: "mgl_step:from:stops:(point_count, 'gruppo-2', %@)", gradini)
        gr.iconAllowsOverlap = NSExpression(forConstantValue: true)
        st.addLayer(gr)

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
        // tocco su un gruppo: la mappa si avvicina finché i punti si separano
        if let g = f.first(where: { $0 is MLNPointFeatureCluster }) {
            m.setCenter(g.coordinate, zoomLevel: min(m.zoomLevel + 2, 18), animated: true)
            return []
        }
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
