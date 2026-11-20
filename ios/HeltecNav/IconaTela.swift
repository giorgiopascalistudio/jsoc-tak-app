import SwiftUI

/// Icona a tratto della tela: disegna lo stesso percorso SVG delle tavole (viewBox 24×24, tratto 2, estremi tondi).
/// Così le icone dell'app sono identiche a quelle approvate, invece di simboli di sistema "somiglianti".
struct IconaTela: View {
    let d: String
    var colore: Color = Theme.dim
    var lato: CGFloat = 18
    var spessore: CGFloat = 2
    var piena: Color? = nil

    var body: some View {
        let forma = PercorsoSVG(d: d)
        ZStack {
            if let piena { forma.fill(piena) }
            forma.stroke(colore, style: StrokeStyle(lineWidth: spessore * lato / 24, lineCap: .round, lineJoin: .round))
        }
        .frame(width: lato, height: lato)
        .accessibilityHidden(true)
    }
}

/// Icone usate nelle tavole (stessi percorsi)
enum Ic {
    static let campanella = "M6 8a6 6 0 0 1 12 0c0 7 3 8 3 8H3s3-1 3-8 M10 20a2 2 0 0 0 4 0"
    static let casa = "M3 11 12 3l9 8 M5 10v10h14V10"
    static let calendario = "M4 5h16v15H4Z M4 9h16 M8 3v4 M16 3v4"
    static let scudo = "M12 3 4 7v5c0 5 3.5 8 8 9 4.5-1 8-4 8-9V7Z"
    static let griglia = "M3 3h7v7H3Z M14 3h7v7h-7Z M3 14h7v7H3Z M14 14h7v7h-7Z"
    static let mappa = "M9 4 3 6v14l6-2 6 2 6-2V4l-6 2Z M9 4v14 M15 6v14"
    static let persona = "M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8Z M4 21c1-4 4-6 8-6s7 2 8 6"
    static let cuore = "M12 20s-8-5-8-11a4.5 4.5 0 0 1 8-2.8A4.5 4.5 0 0 1 20 9c0 6-8 11-8 11Z"
    static let carta = "M3 6h18v13H3Z M3 10h18 M7 15h4"
    static let scatola = "M3 7l9-4 9 4v10l-9 4-9-4Z M3 7l9 4 9-4 M12 11v10"
    static let ingranaggio = "M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z M19 12l2-1-1-3-2 .3-1.4-1.4L17 5l-3-1-1 2h-2l-1-2-3 1 .4 2L6 8.3 4 8l-1 3 2 1v0l-2 1 1 3 2-.3 1.4 1.4L7 19l3 1 1-2h2l1 2 3-1-.4-2 1.4-1.4 2 .3 1-3Z"
    static let dispositivi = "M4 4h11v16H4Z M17 8h3v12h-3 M9 17h1"
    static let documento = "M6 3h9l4 4v14H6Z M14 3v5h5 M9 13h6 M9 17h4"
    static let qr = "M3 3h7v7H3Z M14 3h7v7h-7Z M3 14h7v7H3Z M14 14h3v3h-3Z M20 14v7 M14 20h3"
    static let indietro = "M15 5l-7 7 7 7"
    static let avanti = "M9 5l7 7-7 7"
    static let sole = "M12 16a4 4 0 1 0 0-8 4 4 0 0 0 0 8Z M12 2v2 M12 20v2 M4.9 4.9l1.4 1.4 M17.7 17.7l1.4 1.4 M2 12h2 M20 12h2 M4.9 19.1l1.4-1.4 M17.7 6.3l1.4-1.4"
    static let sondaggio = "M4 20V10 M10 20V4 M16 20v-7 M22 20H2"
    static let invia = "M3 11l18-7-7 18-2-8Z"
    static let cassetta = "M7 4h10l3 5v11H4V9Z M4 9h16 M10 13h4"
    static let spunta = "M5 12l4 4 10-10"
    static let piu = "M12 5v14 M5 12h14"
    static let cerca = "M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14Z M20 20l-4-4"
}

/// Interprete dei percorsi SVG (M L H V C S Q T A Z, maiuscole e minuscole) → Path di SwiftUI, scalato sul riquadro.
struct PercorsoSVG: Shape {
    let d: String

    func path(in r: CGRect) -> Path {
        let k = min(r.width, r.height) / 24
        var p = Path()
        var t = Tokens(d)
        var cur = CGPoint.zero, start = CGPoint.zero, ctrl: CGPoint? = nil
        var cmd: Character = "M"
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + x * k, y: r.minY + y * k) }
        while let c = t.comando() ?? (t.haNumero() ? cmd : nil) {
            cmd = c
            let rel = c.isLowercase
            let base = rel ? cur : .zero
            switch c.uppercased() {
            case "M":
                guard let x = t.num(), let y = t.num() else { return p }
                cur = CGPoint(x: base.x + x, y: base.y + y); start = cur
                p.move(to: pt(cur.x, cur.y)); ctrl = nil
                cmd = rel ? "l" : "L"            // le coppie successive sono linee
            case "L":
                guard let x = t.num(), let y = t.num() else { return p }
                cur = CGPoint(x: base.x + x, y: base.y + y); p.addLine(to: pt(cur.x, cur.y)); ctrl = nil
            case "H":
                guard let x = t.num() else { return p }
                cur.x = (rel ? cur.x : 0) + x; p.addLine(to: pt(cur.x, cur.y)); ctrl = nil
            case "V":
                guard let y = t.num() else { return p }
                cur.y = (rel ? cur.y : 0) + y; p.addLine(to: pt(cur.x, cur.y)); ctrl = nil
            case "C":
                guard let x1 = t.num(), let y1 = t.num(), let x2 = t.num(), let y2 = t.num(), let x = t.num(), let y = t.num() else { return p }
                let c1 = CGPoint(x: base.x + x1, y: base.y + y1), c2 = CGPoint(x: base.x + x2, y: base.y + y2)
                cur = CGPoint(x: base.x + x, y: base.y + y)
                p.addCurve(to: pt(cur.x, cur.y), control1: pt(c1.x, c1.y), control2: pt(c2.x, c2.y)); ctrl = c2
            case "S":
                guard let x2 = t.num(), let y2 = t.num(), let x = t.num(), let y = t.num() else { return p }
                let c1 = ctrl.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let c2 = CGPoint(x: base.x + x2, y: base.y + y2)
                cur = CGPoint(x: base.x + x, y: base.y + y)
                p.addCurve(to: pt(cur.x, cur.y), control1: pt(c1.x, c1.y), control2: pt(c2.x, c2.y)); ctrl = c2
            case "Q":
                guard let x1 = t.num(), let y1 = t.num(), let x = t.num(), let y = t.num() else { return p }
                let c1 = CGPoint(x: base.x + x1, y: base.y + y1)
                cur = CGPoint(x: base.x + x, y: base.y + y)
                p.addQuadCurve(to: pt(cur.x, cur.y), control: pt(c1.x, c1.y)); ctrl = c1
            case "T":
                guard let x = t.num(), let y = t.num() else { return p }
                let c1 = ctrl.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                cur = CGPoint(x: base.x + x, y: base.y + y)
                p.addQuadCurve(to: pt(cur.x, cur.y), control: pt(c1.x, c1.y)); ctrl = c1
            case "A":
                guard let rx = t.num(), let ry = t.num(), let rot = t.num(), let la = t.flag(), let sw = t.flag(), let x = t.num(), let y = t.num() else { return p }
                let fine = CGPoint(x: base.x + x, y: base.y + y)
                arco(&p, da: cur, a: fine, rx: rx, ry: ry, rot: rot, grande: la, orario: sw, pt: pt)
                cur = fine; ctrl = nil
            case "Z":
                p.closeSubpath(); cur = start; ctrl = nil
            default:
                return p
            }
        }
        return p
    }

    /// arco ellittico SVG convertito in curve di Bézier (W3C, implementazione per punto finale)
    private func arco(_ p: inout Path, da a: CGPoint, a b: CGPoint, rx: Double, ry: Double, rot: Double, grande: Bool, orario: Bool,
                      pt: (Double, Double) -> CGPoint) {
        var rx = abs(rx), ry = abs(ry)
        if rx == 0 || ry == 0 || a == b { p.addLine(to: pt(b.x, b.y)); return }
        let phi = rot * .pi / 180, cs = cos(phi), sn = sin(phi)
        let dx = (a.x - b.x) / 2, dy = (a.y - b.y) / 2
        let x1 = cs * dx + sn * dy, y1 = -sn * dx + cs * dy
        let lam = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lam > 1 { rx *= lam.squareRoot(); ry *= lam.squareRoot() }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var co = (max(0, num / den)).squareRoot()
        if grande == orario { co = -co }
        let cxp = co * rx * y1 / ry, cyp = -co * ry * x1 / rx
        let cx = cs * cxp - sn * cyp + (a.x + b.x) / 2, cy = sn * cxp + cs * cyp + (a.y + b.y) / 2
        func ang(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let s = ux * vy - uy * vx < 0 ? -1.0 : 1.0
            let d = (ux * vx + uy * vy) / ((ux * ux + uy * uy).squareRoot() * (vx * vx + vy * vy).squareRoot())
            return s * acos(min(1, max(-1, d)))
        }
        let t1 = ang(1, 0, (x1 - cxp) / rx, (y1 - cyp) / ry)
        var dt = ang((x1 - cxp) / rx, (y1 - cyp) / ry, (-x1 - cxp) / rx, (-y1 - cyp) / ry)
        if !orario && dt > 0 { dt -= 2 * .pi } else if orario && dt < 0 { dt += 2 * .pi }
        let n = Int(ceil(abs(dt) / (.pi / 2)))
        let passo = dt / Double(n)
        let kk = 4.0 / 3.0 * tan(passo / 4)
        var th = t1
        for _ in 0..<n {
            let c1 = cos(th), s1 = sin(th), c2 = cos(th + passo), s2 = sin(th + passo)
            func e(_ x: Double, _ y: Double) -> CGPoint { pt(cx + cs * rx * x - sn * ry * y, cy + sn * rx * x + cs * ry * y) }
            p.addCurve(to: e(c2, s2), control1: e(c1 - kk * s1, s1 + kk * c1), control2: e(c2 + kk * s2, s2 - kk * c2))
            th += passo
        }
    }

    /// lettore dei comandi e dei numeri del percorso
    private struct Tokens {
        let ch: [Character]
        var i = 0
        init(_ s: String) { ch = Array(s) }
        mutating func salta() { while i < ch.count, ch[i] == " " || ch[i] == "," || ch[i] == "\n" { i += 1 } }
        mutating func comando() -> Character? {
            salta()
            guard i < ch.count, ch[i].isLetter else { return nil }
            defer { i += 1 }
            return ch[i]
        }
        mutating func haNumero() -> Bool { salta(); return i < ch.count && (ch[i].isNumber || ch[i] == "-" || ch[i] == "." || ch[i] == "+") }
        mutating func num() -> Double? {
            salta()
            var s = ""
            var punto = false
            if i < ch.count, ch[i] == "-" || ch[i] == "+" { s.append(ch[i]); i += 1 }
            while i < ch.count {
                let c = ch[i]
                if c.isNumber { s.append(c); i += 1 }
                else if c == "." && !punto { punto = true; s.append(c); i += 1 }
                else { break }
            }
            return Double(s)
        }
        /// i flag degli archi possono essere attaccati: "0 1 0 1 5" o "011"
        mutating func flag() -> Bool? {
            salta()
            guard i < ch.count, ch[i] == "0" || ch[i] == "1" else { return nil }
            defer { i += 1 }
            return ch[i] == "1"
        }
    }
}
