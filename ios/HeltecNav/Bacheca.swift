import SwiftUI

struct BachecaDati: Decodable {
    struct Nodo: Decodable, Identifiable, Hashable { let id, nome, tipo, nota, fascicolo, stato: String }
    struct Legame: Decodable, Hashable { let da, a, testo, stato: String }
    let aggiornato: String
    let nodi: [Nodo]
    let legami: [Legame]

    static func carica() -> BachecaDati? {
        let u = DocStore.root.appendingPathComponent("INT Intelligence in gara/_bacheca.json")
        guard let d = try? Data(contentsOf: u) else { return nil }
        return try? JSONDecoder().decode(BachecaDati.self, from: d)
    }

    static func colore(_ tipo: String) -> Color {
        switch tipo {
        case "famiglia": return Theme.olive
        case "persona": return Theme.cyan
        case "vittima": return Theme.red
        case "luogo": return Theme.amber
        case "prova": return Color(red: 0.75, green: 0.60, blue: 0.95)
        case "codice": return Color(red: 0.95, green: 0.85, blue: 0.55)
        default: return .gray
        }
    }
    static func icona(_ tipo: String) -> String {
        switch tipo {
        case "famiglia": return "crown"
        case "persona": return "person.fill"
        case "vittima": return "cross.case.fill"
        case "luogo": return "mappin"
        case "prova": return "magnifyingglass"
        case "codice": return "key.fill"
        default: return "circle"
        }
    }
}

/// Disposizione a molle (force-directed), calcolata una volta.
enum Layout {
    static func calcola(_ b: BachecaDati, size: CGFloat) -> [String: CGPoint] {
        let ids = b.nodi.map(\.id)
        let n = ids.count
        guard n > 0 else { return [:] }
        let c = Double(size) / 2, r = Double(size) * 0.35
        var pos: [CGPoint] = []
        for i in 0..<n {
            let a: Double = Double(i) / Double(n) * 2 * Double.pi
            let x: Double = c + cos(a) * r
            let y: Double = c + sin(a) * r
            pos.append(CGPoint(x: x, y: y))
        }
        let index = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        let edges = b.legami.compactMap { l -> (Int, Int)? in
            guard let a = index[l.da], let c = index[l.a] else { return nil }
            return (a, c)
        }
        let k = Double(size) / sqrt(Double(n)) * 0.75
        var temp = Double(size) / 8
        for _ in 0..<350 {
            var ddx = [Double](repeating: 0, count: n), ddy = [Double](repeating: 0, count: n)
            for i in 0..<n {
                for j in (i + 1)..<max(i + 1, n) {
                    let dx = Double(pos[i].x - pos[j].x), dy = Double(pos[i].y - pos[j].y)
                    let d = max(1, sqrt(dx * dx + dy * dy)), f = k * k / d
                    ddx[i] += dx / d * f; ddy[i] += dy / d * f
                    ddx[j] -= dx / d * f; ddy[j] -= dy / d * f
                }
            }
            for (a, c) in edges {
                let dx = Double(pos[a].x - pos[c].x), dy = Double(pos[a].y - pos[c].y)
                let d = max(1, sqrt(dx * dx + dy * dy)), f = d * d / k
                ddx[a] -= dx / d * f; ddy[a] -= dy / d * f
                ddx[c] += dx / d * f; ddy[c] += dy / d * f
            }
            for i in 0..<n {
                // gravità verso il centro (tiene insieme i nodi isolati)
                ddx[i] += (Double(size) / 2 - Double(pos[i].x)) * 0.02
                ddy[i] += (Double(size) / 2 - Double(pos[i].y)) * 0.02
                let l = max(0.01, sqrt(ddx[i] * ddx[i] + ddy[i] * ddy[i]))
                pos[i].x += CGFloat(ddx[i] / l * min(l, temp))
                pos[i].y += CGFloat(ddy[i] / l * min(l, temp))
                pos[i].x = min(size - 60, max(60, pos[i].x))
                pos[i].y = min(size - 30, max(30, pos[i].y))
            }
            temp *= 0.985
        }
        return Dictionary(uniqueKeysWithValues: zip(ids, pos))
    }
}

struct BachecaView: View {
    @EnvironmentObject var docs: DocStore
    @State private var dati: BachecaDati?
    @State private var pos: [String: CGPoint] = [:]
    @State private var scelto: String?
    @State private var tipi: Set<String> = []
    @State private var scala: CGFloat = 0.55
    @GestureState private var pinch: CGFloat = 1
    @State private var spost: CGSize = .zero
    @GestureState private var drag: CGSize = .zero
    @State private var elenco = false
    let size: CGFloat = 1100
    let tuttiTipi = ["famiglia", "persona", "vittima", "luogo", "prova", "codice"]

    var visibili: [BachecaDati.Nodo] { (dati?.nodi ?? []).filter { tipi.isEmpty || tipi.contains($0.tipo) } }
    var vicini: Set<String> {
        guard let s = scelto, let d = dati else { return [] }
        return Set(d.legami.filter { $0.da == s || $0.a == s }.flatMap { [$0.da, $0.a] })
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tuttiTipi, id: \.self) { t in
                        let on = tipi.isEmpty || tipi.contains(t)
                        Button {
                            withAnimation(.spring(response: 0.3)) { if tipi.contains(t) { tipi.remove(t) } else { tipi.insert(t) } }
                        } label: {
                            Label(t.capitalized, systemImage: BachecaDati.icona(t)).font(.caption.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(BachecaDati.colore(t).opacity(on ? 0.25 : 0.06), in: Capsule())
                                .foregroundStyle(on ? BachecaDati.colore(t) : Theme.dim)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .padding(.horizontal).padding(.vertical, 8)
            }
            if dati == nil {
                Spacer()
                Text("Bacheca non ancora presente: arriva con la biblioteca.").foregroundStyle(Theme.dim)
                Spacer()
            } else if elenco {
                lista
            } else {
                lavagna
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Bacheca indizi")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Picker("", selection: $elenco) {
                Image(systemName: "point.3.connected.trianglepath.dotted").tag(false)
                Image(systemName: "list.bullet").tag(true)
            }
            .pickerStyle(.segmented).frame(width: 100)
        }
        .task(id: docs.items.count) {
            guard let d = BachecaDati.carica() else { return }
            let p = await Task.detached { Layout.calcola(d, size: 1100) }.value
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) { dati = d; pos = p }
        }
    }

    var lavagna: some View {
        GeometryReader { g in
            let s = scala * pinch
            let ox = spost.width + drag.width, oy = spost.height + drag.height
            let cx = g.size.width / 2, cy = g.size.height / 2
            let half = size / 2
            // dalla posizione nel grafico allo schermo: lo zoom allarga le distanze, le etichette restano leggibili
            let sp: (CGPoint) -> CGPoint = { p in CGPoint(x: cx + (p.x - half) * s + ox, y: cy + (p.y - half) * s + oy) }
            ZStack {
                Canvas { ctx, _ in
                    guard let d = dati else { return }
                    let vis = Set(visibili.map(\.id))
                    for l in d.legami where vis.contains(l.da) && vis.contains(l.a) {
                        guard let a0 = pos[l.da], let b0 = pos[l.a] else { continue }
                        let a = sp(a0), b = sp(b0)
                        var p = Path(); p.move(to: a); p.addLine(to: b)
                        let attivo = scelto == nil || l.da == scelto || l.a == scelto
                        let alfa: Double = attivo ? (scelto == nil ? 0.35 : 0.9) : 0.07
                        ctx.stroke(p, with: .color(Theme.olive.opacity(alfa)),
                                   style: StrokeStyle(lineWidth: attivo && scelto != nil ? 2 : 1, dash: l.stato == "ipotesi" ? [6, 5] : []))
                        if scelto != nil && attivo && !l.testo.isEmpty {
                            ctx.draw(Text(l.testo).font(.system(size: 11, weight: .semibold)).foregroundColor(.white),
                                     at: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - 8))
                        }
                    }
                }
                ForEach(visibili) { nodo in
                    if let p = pos[nodo.id] {
                        let attivo = scelto == nil || vicini.contains(nodo.id)
                        chip(nodo, evidenziato: scelto == nodo.id)
                            .opacity(attivo ? 1 : 0.18)
                            .position(sp(p))
                            .onTapGesture {
                                haptic()
                                withAnimation(.spring(response: 0.35)) { scelto = scelto == nodo.id ? nil : nodo.id }
                            }
                    }
                }
            }
            .frame(width: g.size.width, height: g.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(DragGesture().updating($drag) { v, st, _ in st = v.translation }
                .onEnded { v in spost.width += v.translation.width; spost.height += v.translation.height })
            .simultaneousGesture(MagnificationGesture().updating($pinch) { v, st, _ in st = v }
                .onEnded { v in scala = min(3, max(0.2, scala * v)) })
            .onAppear {
                // all'apertura si vede tutta la rete
                scala = min(g.size.width, g.size.height) / size * 1.05
            }
            .overlay(alignment: .bottom) {
                if let id = scelto, let n = dati?.nodi.first(where: { $0.id == id }) {
                    dettaglio(n).padding(12).transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 8) {
                    Text("agg. \(dati?.aggiornato ?? "")").font(Theme.mono(10)).foregroundStyle(Theme.dim)
                    Button {
                        withAnimation(.spring()) { spost = .zero; scala = min(g.size.width, g.size.height) / size * 1.05 }
                    } label: { Image(systemName: "arrow.up.left.and.down.right.magnifyingglass").font(.caption) }
                }
                .padding(8)
            }
        }
    }

    func chip(_ n: BachecaDati.Nodo, evidenziato: Bool) -> some View {
        let c = BachecaDati.colore(n.tipo)
        return HStack(spacing: 5) {
            Image(systemName: BachecaDati.icona(n.tipo)).font(.system(size: 11, weight: .bold))
            Text(n.nome).font(.system(size: 13, weight: .semibold)).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.surface2, in: Capsule())
        .overlay(Capsule().strokeBorder(c, style: StrokeStyle(lineWidth: evidenziato ? 2.5 : 1, dash: n.stato == "ipotesi" ? [4, 3] : [])))
        .foregroundStyle(c)
        .shadow(color: evidenziato ? c.opacity(0.6) : .clear, radius: 8)
        .scaleEffect(evidenziato ? 1.15 : 1)
    }

    func dettaglio(_ n: BachecaDati.Nodo) -> some View {
        let legami = (dati?.legami ?? []).filter { $0.da == n.id || $0.a == n.id }
        let nome = { (id: String) in dati?.nodi.first { $0.id == id }?.nome ?? id }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: BachecaDati.icona(n.tipo)).foregroundStyle(BachecaDati.colore(n.tipo))
                Text(n.nome).font(.headline)
                if n.stato == "ipotesi" { Text("IPOTESI").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(Theme.amber) }
                Spacer()
                Button { withAnimation { scelto = nil } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.dim) }
            }
            Text(n.nota).font(.caption).foregroundStyle(.white.opacity(0.85))
            ForEach(legami, id: \.self) { l in
                let altro = l.da == n.id ? l.a : l.da
                Button { withAnimation(.spring(response: 0.35)) { scelto = altro } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch").font(.caption2)
                        Text(nome(altro)).font(.caption.weight(.semibold))
                        if !l.testo.isEmpty { Text("· \(l.testo)").font(.caption2).foregroundStyle(Theme.dim) }
                    }
                    .foregroundStyle(l.stato == "ipotesi" ? Theme.amber : Theme.olive)
                }
            }
            if let f = docs.fascicolo(prefix: n.fascicolo), !n.fascicolo.isEmpty {
                NavigationLink { FascicoloView(name: f.name) } label: { Label("Apri \(f.name)", systemImage: "folder.fill") }
                    .font(.caption.weight(.bold)).buttonStyle(.borderedProminent).tint(Theme.olive).foregroundStyle(.black)
            }
        }
        .padding(14)
        .frame(maxWidth: 560)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 0.75))
    }

    var lista: some View {
        List {
            ForEach(tuttiTipi.filter { tipi.isEmpty || tipi.contains($0) }, id: \.self) { t in
                let ns = (dati?.nodi ?? []).filter { $0.tipo == t }
                if !ns.isEmpty {
                    Section(t.capitalized) {
                        ForEach(ns) { n in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(n.nome).font(.subheadline.weight(.bold)).foregroundStyle(BachecaDati.colore(n.tipo))
                                    if n.stato == "ipotesi" { Text("IPOTESI").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(Theme.amber) }
                                }
                                Text(n.nota).font(.caption).foregroundStyle(Theme.dim)
                            }
                            .listRowBackground(Theme.surface)
                            .onTapGesture { elenco = false; withAnimation { scelto = n.id } }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}
