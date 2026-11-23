import SwiftUI

// MARK: - Commenti dell'evento (tavola 41): bolle, giorni, risposta citata, barra di scrittura in basso.

extension JsocClient {
    /// come commentaEvento, con il commento a cui si risponde (il server può ignorarlo)
    func commentaEventoV3(_ ev: Int, _ t: String, rispostaA: Int?) async throws -> [JCommentoEvento] {
        var b: [String: Any] = ["testo": t]
        if let rispostaA { b["risposta_a"] = rispostaA }
        return try await send("/api/eventi/\(ev)/commenti", "POST", b)
    }
}

/// rettangolo con angoli diversi (le bolle hanno un angolo stretto verso chi scrive); iOS 16 non ha UnevenRoundedRectangle
struct AngoliTela: Shape {
    var tl: CGFloat, tr: CGFloat, br: CGFloat, bl: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + tl, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY))
        p.addArc(center: CGPoint(x: r.maxX - tr, y: r.minY + tr), radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br))
        p.addArc(center: CGPoint(x: r.maxX - br, y: r.maxY - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX + bl, y: r.maxY))
        p.addArc(center: CGPoint(x: r.minX + bl, y: r.maxY - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + tl))
        p.addArc(center: CGPoint(x: r.minX + tl, y: r.minY + tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

struct CommentiEventoV3: View {
    let evento: JEvento
    @ObservedObject private var jsoc = JsocClient.shared
    @Environment(\.dismiss) private var dismiss
    @State private var commenti: [JCommentoEvento] = []
    @State private var testo = ""
    @State private var rispondiA: JCommentoEvento?
    @State private var modifica: JCommentoEvento?
    @State private var testoModifica = ""
    @State private var errore: String?
    @State private var fotoNonPronta = false
    @FocusState private var fuoco: Bool

    var io: Int? { jsoc.utente?.id }

    var body: some View {
        GeometryReader { g in
            let sotto = g.safeAreaInsets.bottom
            VStack(spacing: 0) {
                intestazione
                ScrollViewReader { sv in
                    ScrollView {
                        VStack(spacing: 10) {
                            Spacer(minLength: 0)
                            ForEach(righe, id: \.0) { r in
                                if let k = r.2 { bolla(k).id(r.0) } else {
                                    Text(r.1).font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.dim).frame(maxWidth: .infinity)
                                }
                            }
                            if commenti.isEmpty {
                                Text("Nessun commento. Scrivi per primo: orari, passaggi in auto, domande.")
                                    .font(.system(size: 12.5)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                            }
                            if let errore { Text(errore).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.red) }
                            Text("Tieni premuto un commento: rispondi · modifica · elimina")
                                .font(.system(size: 10.5)).foregroundStyle(Theme.dim).frame(maxWidth: .infinity).id("fondo")
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: max(0, g.size.height - 160), alignment: .bottom)
                        .padding(.top, 12).padding(.bottom, 26)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: commenti.count) { _ in withAnimation { sv.scrollTo("fondo", anchor: .bottom) } }
                    .onAppear { sv.scrollTo("fondo", anchor: .bottom) }
                }
                barra.padding(.bottom, sotto > 60 ? 8 : max(0, 26 - sotto))
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { ModuliAperti.shared.aperti += 1 }
        .onDisappear { ModuliAperti.shared.aperti = max(0, ModuliAperti.shared.aperti - 1); segnaVisti() }
        .task { await carica() }
        .alert("Modifica commento", isPresented: Binding(get: { modifica != nil }, set: { if !$0 { modifica = nil } })) {
            TextField("Commento", text: $testoModifica)
            Button("Salva") { if let k = modifica { esegui { try await jsoc.modificaCommentoEvento(k.id, testoModifica) } } }
            Button("Annulla", role: .cancel) {}
        }
        .alert("Foto nei commenti", isPresented: $fotoNonPronta) { Button("OK", role: .cancel) {} } message: {
            Text("Le foto nei commenti arrivano con il prossimo aggiornamento del server. Intanto puoi caricarle in Documenti.")
        }
    }

    /// intestazione: indietro 42, titolo 24, nome dell'evento a destra
    var intestazione: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                IconaTela(d: Ic.indietro, colore: Theme.testo, lato: 18)
                    .frame(width: 42, height: 42).background(Theme.surface, in: Circle()).overlay(Circle().strokeBorder(Theme.stroke))
            }
            .accessibilityLabel("Indietro")
            Text("Commenti").font(.system(size: 24, weight: .black)).foregroundStyle(Theme.testo)
            Spacer()
            Text(evento.nome).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.dim).lineLimit(1)
        }
        .padding(.horizontal, 14).padding(.top, 7)
    }

    /// commenti in ordine, con i separatori dei giorni (IERI · OGGI · 12 NOVEMBRE)
    var righe: [(String, String, JCommentoEvento?)] {
        var out: [(String, String, JCommentoEvento?)] = []
        let cal = Calendar.current
        var ultimo: Date?
        for k in commenti.sorted(by: { $0.ts < $1.ts }) {
            let d = Date(timeIntervalSince1970: k.ts)
            let g = cal.startOfDay(for: d)
            if ultimo != g {
                ultimo = g
                let t = cal.isDateInToday(d) ? "OGGI" : (cal.isDateInYesterday(d) ? "IERI" : FormatiEventi.giornoCompleto.string(from: d).uppercased())
                out.append(("g\(g.timeIntervalSince1970)", t, nil))
            }
            out.append(("k\(k.id)", "", k))
        }
        return out
    }

    @ViewBuilder func bolla(_ k: JCommentoEvento) -> some View {
        let mio = k.autore == io
        let citato = k.risposta_a.flatMap { id in commenti.first { $0.id == id } }
        let contenuto = VStack(alignment: .leading, spacing: 0) {
            if !mio {
                Text(k.callsign ?? "?").font(Theme.mono(11, .heavy)).foregroundStyle(Theme.oliveBright)
            }
            if let c = citato {
                Text("\(c.callsign ?? "?") · \(primaFrase(c.testo))").font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(1)
                    .padding(.leading, 7)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.cyan).frame(width: 2) }
                    .padding(.top, 3).padding(.bottom, 5)
            }
            Text(k.testo).font(.system(size: 13.5)).foregroundStyle(Theme.testo).lineSpacing(2.5).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                if k.modificato != nil { Text("modificato ·").font(.system(size: 10)).foregroundStyle(Theme.dim) }
                Text(FormatiEventi.ora.string(from: Date(timeIntervalSince1970: k.ts))).font(.system(size: 10)).foregroundStyle(Theme.dim)
            }
            .padding(.top, 3)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .fixedSize(horizontal: false, vertical: true)
        HStack(alignment: .bottom, spacing: 9) {
            if mio {
                Spacer(minLength: 0)
                contenuto
                    .background(Color(hex: 0x3A4A24), in: AngoliTela(tl: 16, tr: 16, br: 5, bl: 16))
                    .frame(maxWidth: 288, alignment: .trailing)
                    .contextMenu { menu(k, mio: true) }
            } else {
                TondoIniziali(testo: inizialiCommento(k.callsign), lato: 32)
                contenuto
                    .background(Theme.surface, in: AngoliTela(tl: 16, tr: 16, br: 16, bl: 5))
                    .overlay(AngoliTela(tl: 16, tr: 16, br: 16, bl: 5).stroke(Theme.olive.opacity(0.2), lineWidth: 1))
                    .frame(maxWidth: 288, alignment: .leading)
                    .contextMenu { menu(k, mio: false) }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder func menu(_ k: JCommentoEvento, mio: Bool) -> some View {
        Button { rispondiA = k; fuoco = true } label: { Label("Rispondi", systemImage: "arrowshape.turn.up.left") }
        if mio { Button { testoModifica = k.testo; modifica = k } label: { Label("Modifica", systemImage: "pencil") } }
        if mio || jsoc.utente?.direttivo == true {
            Button(role: .destructive) { esegui { try await jsoc.cancellaCommentoEvento(k.id) } } label: { Label("Elimina", systemImage: "trash") }
        }
    }

    func primaFrase(_ t: String) -> String {
        if let i = t.firstIndex(where: { ".?!".contains($0) }) { return String(t[...i]) }
        return t
    }

    /// barra in basso: foto 44 · campo 44 · invia 44 (lati 12, spazio 8)
    var barra: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let r = rispondiA {
                HStack(spacing: 6) {
                    Text("Rispondi a \(r.callsign ?? "?") · \(primaFrase(r.testo))").font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(1)
                        .padding(.leading, 7).overlay(alignment: .leading) { Rectangle().fill(Theme.cyan).frame(width: 2) }
                    Spacer()
                    Button { rispondiA = nil } label: { IconaTela(d: Ic.croce, colore: Theme.dim, lato: 14) }
                }
                .padding(.horizontal, 16)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button { haptic(); fotoNonPronta = true } label: {
                    IconaTela(d: Ic.fotocamera, colore: Theme.testo, lato: 18)
                        .frame(width: 44, height: 44).background(Theme.surface, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.olive.opacity(0.25)))
                }
                .accessibilityLabel("Allega foto")
                ZStack(alignment: .leading) {
                    if testo.isEmpty { Text("Scrivi un commento…").font(.system(size: 14)).foregroundStyle(Color(hex: 0x7D8470)) }
                    TextField("", text: $testo, axis: .vertical)
                        .font(.system(size: 14)).foregroundStyle(Theme.testo).lineLimit(1...4).focused($fuoco)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(minHeight: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.olive.opacity(0.25)))
                Button { invia() } label: {
                    IconaTela(d: Ic.inviaCommento, colore: Theme.scuro, lato: 18)
                        .frame(width: 44, height: 44).background(Theme.olive, in: Circle())
                }
                .accessibilityLabel("Invia")
                .disabled(testo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
        }
    }

    func invia() {
        let t = testo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        testo = ""
        let r = rispondiA?.id
        rispondiA = nil
        esegui { try await jsoc.commentaEventoV3(evento.id, t, rispostaA: r) }
    }

    func esegui(_ f: @escaping () async throws -> [JCommentoEvento]) {
        haptic()
        guard !Anteprima.attiva else { return }
        Task {
            do { let r = try await f(); withAnimation(.spring(response: 0.3)) { commenti = r }; errore = nil; segnaVisti() }
            catch { errore = error.localizedDescription }
        }
    }

    func carica() async {
        if Anteprima.attiva { commenti = Anteprima.commentiEvento(evento.id); return }
        if let k = try? await jsoc.commentiEvento(evento.id) { commenti = k }
        segnaVisti()
    }

    /// i commenti visti non contano più come "nuovi" nella scheda dell'evento
    func segnaVisti() {
        guard !Anteprima.attiva, let m = commenti.map(\.ts).max() else { return }
        UserDefaults.standard.set(m, forKey: "eventi.commentiVisti.\(evento.id)")
    }
}
