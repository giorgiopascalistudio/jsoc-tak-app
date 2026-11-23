import SwiftUI
import Vision

// MARK: - Il socio propone una spesa: riproduce la tavola SpesaSocio10 (390 pt).
// Foto dello scontrino (l'app legge importo, negozio e data), per cosa, categoria,
// "L'hai pagata tu?" (Rimborsami / Offro io / Da pagare), evento collegato.
// Entra in cassa solo dopo l'approvazione del direttivo (POST /api/cassa/proposte).

extension JsocClient {
    /// proposta di spesa del socio: resta "in attesa" finché il direttivo non la approva o rifiuta
    func proponiSpesa(_ corpo: [String: Any]) async throws { let _: JOk = try await send("/api/cassa/proposte", "POST", corpo) }
}

/// Valori iniziali della proposta (anteprime: come la tavola)
struct BozzaSpesa {
    var importo = ""
    var negozio: String?
    var data: Date?
    var letto = false              // importo/negozio/data letti dallo scontrino
    var perCosa = ""
    var categoria = 0
    var pagamento = 0
    var evento: String?            // testo mostrato quando non c'è l'evento vero (anteprime)
}

struct SpesaSocioView: View {
    static let categorie = ["Materiale", "Campo", "Trasferte", "Altro"]
    static let pagamenti = ["Rimborsami", "Offro io", "Da pagare"]
    static let codiciPagamento = ["rimborso", "offerta", "da_pagare"]

    @Environment(\.dismiss) private var chiudi
    @ObservedObject private var store = EventoStore.shared
    @State private var b = VistaSocio.prova ? Anteprima.Socio.spesa : BozzaSpesa()
    @State private var foto: UIImage?
    @State private var evento: JEvento?
    @State private var eventoScelto = false
    @State private var fotocamera = false
    @State private var leggo = false
    @State private var invio = false
    @State private var errore: String?

    static let giornoMese: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "d MMM"; return f }()

    var body: some View {
        VStack(spacing: 0) {
            // intestazione: Annulla · "Proponi una spesa" 17 · Invia (alto 36)
            HStack {
                Button("Annulla") { chiudi() }.font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.dim)
                    .padding(.horizontal, 4).frame(height: 36)
                Spacer()
                Text("Proponi una spesa").font(.system(size: 17, weight: .heavy)).foregroundStyle(Theme.testo)
                Spacer()
                Button { invia() } label: {
                    Group { if invio { ProgressView().tint(Theme.scuro) } else { Text("Invia") } }
                        .font(.system(size: 13.5, weight: .black)).foregroundStyle(Theme.scuro)
                        .padding(.horizontal, 14).frame(height: 36)
                        .background(Theme.olive.opacity(puoInviare ? 1 : 0.45), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .disabled(!puoInviare || invio)
            }
            .padding(.horizontal, 14).padding(.top, 7)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 11) {
                    scontrino
                    if let errore { Text(errore).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.red) }
                    VStack(alignment: .leading, spacing: 0) {
                        CampoTesto(etichetta: "Per cosa", testo: $b.perCosa, maiuscole: .sentences)
                        NotaCampo(testo: "Scrivi in poche parole a cosa è servita")
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        EtichettaCampo(testo: "Categoria")
                        HStack(spacing: 6) {
                            ForEach(Self.categorie.indices, id: \.self) { i in capsula(i) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        EtichettaCampo(testo: "L'hai pagata tu?")
                        SceltaTela(voci: Self.pagamenti, scelta: $b.pagamento)
                    }
                    eventoCollegato
                    avvisoDirettivo
                }
                .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.bg.ignoresSafeArea())
        .sheet(isPresented: $fotocamera) {
            CameraPicker { img in foto = img; leggi(img) }.ignoresSafeArea()
        }
        .onAppear { if evento == nil && b.evento == nil { evento = eventoVicino(b.data ?? Date()) } }
    }

    var puoInviare: Bool { importo != nil && !b.perCosa.trimmingCharacters(in: .whitespaces).isEmpty }
    var importo: Double? { Double(b.importo.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")) }

    // MARK: scontrino: miniatura 56×72, importo mono 30, "dallo scontrino · negozio · data", rifai la foto

    var scontrino: some View {
        HStack(spacing: 12) {
            Button { fotocamera = true } label: { miniatura }.buttonStyle(.plain).accessibilityLabel("Fotografa lo scontrino")
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    TextField("0,00", text: $b.importo).keyboardType(.decimalPad).fixedSize()
                    Text(" €")
                }
                .font(Theme.mono(30, .heavy)).foregroundStyle(Theme.testo)
                if leggo {
                    Text("leggo lo scontrino…").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.dim)
                } else if b.letto {
                    HStack(spacing: 4) {
                        IconaTela(d: Ic.spunta, colore: Theme.oliveBright, lato: 12)
                        Text((["dallo scontrino"] + [b.negozio, b.data.map { Self.giornoMese.string(from: $0) }].compactMap { $0 }).joined(separator: " · "))
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.oliveBright).lineLimit(1)
                    }
                } else {
                    Text("Fotografa lo scontrino: leggo io importo e data").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.dim).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { fotocamera = true } label: {
                IconaTela(d: Ic.fotocamera, colore: Theme.testo, lato: 18)
                    .frame(width: 42, height: 42)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.olive.opacity(0.25)))
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Rifai la foto")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Theme.stroke))
    }

    @ViewBuilder var miniatura: some View {
        if let foto {
            Image(uiImage: foto).resizable().scaledToFill().frame(width: 56, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            // scontrino disegnato della tavola: carta #e9e6da, righe #b5b19f
            VStack(alignment: .leading, spacing: 5) {
                riga(1); riga(0.7); riga(1); riga(0.5); riga(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6).padding(.vertical, 8)
            .frame(width: 56, height: 72)
            .background(Color(hex: 0xE9E6DA), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    func riga(_ k: CGFloat) -> some View {
        Rectangle().fill(Color(hex: 0xB5B19F)).frame(width: 44 * k, height: 3)
    }

    // MARK: categoria: capsule alte 32, scelta ambra

    func capsula(_ i: Int) -> some View {
        let on = b.categoria == i
        return Button { haptic(.soft); b.categoria = i } label: {
            Text(Self.categorie[i]).font(.system(size: 12, weight: .heavy))
                .foregroundStyle(on ? Theme.scuro : Theme.testo2)
                .padding(.horizontal, 11).frame(height: 32)
                .background(on ? Theme.amber : Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? .clear : Theme.stroke))
        }
        .buttonStyle(.plain)
    }

    // MARK: evento collegato: proposto quello più vicino alla data dello scontrino

    var testoEvento: String {
        if let e = evento { return e.nome + (e.dataInizio.map { " · " + Self.giornoMese.string(from: $0) } ?? "") }
        return b.evento ?? "Nessun evento"
    }

    var eventoCollegato: some View {
        VStack(alignment: .leading, spacing: 4) {
            EtichettaCampo(testo: "Evento collegato")
            Menu {
                Button("Nessun evento") { evento = nil; b.evento = nil; eventoScelto = true }
                ForEach(store.eventi.filter { !$0.annullato }.sorted { ($0.dataInizio ?? .distantPast) > ($1.dataInizio ?? .distantPast) }.prefix(20), id: \.id) { e in
                    Button(e.nome + (e.dataInizio.map { " · " + Self.giornoMese.string(from: $0) } ?? "")) { evento = e; eventoScelto = true }
                }
            } label: {
                RiquadroCampo {
                    Text(testoEvento).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.testo).lineLimit(1)
                    Spacer()
                    IconaTela(d: Ic.calendario, colore: Theme.olive, lato: 17)
                }
            }
            .buttonStyle(.plain)
            NotaCampo(testo: eventoScelto ? "Scelto da te" : "Proposto: l'evento più vicino alla data").padding(.top, -4)
        }
    }

    func eventoVicino(_ d: Date) -> JEvento? {
        store.eventi.filter { !$0.annullato && $0.dataInizio != nil }
            .min { abs($0.dataInizio!.timeIntervalSince(d)) < abs($1.dataInizio!.timeIntervalSince(d)) }
    }

    // MARK: riquadro ambra in fondo

    var avvisoDirettivo: some View {
        HStack(alignment: .top, spacing: 10) {
            // nella tavola l'icona resta stretta (5,6 pt) accanto al testo lungo
            IconaTela(d: Ic.info, colore: Theme.amber, lato: 5.6).frame(height: 18)
            (Text("Va approvata dal direttivo.").fontWeight(.bold).foregroundColor(Theme.amber)
             + Text(" Finché non è approvata non entra in cassa. Ricevi una notifica quando la approvano o la rifiutano, e se hai chiesto il rimborso ti dicono quando e come.").foregroundColor(TelaSocio.nota))
                .font(.system(size: 12)).lineSpacing(3.2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(Theme.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.amber.opacity(0.4)))
    }

    // MARK: lettura dello scontrino

    func leggi(_ img: UIImage) {
        leggo = true
        Task {
            let e = await LettoreScontrino.leggi(img)
            leggo = false
            if let v = e.importo { b.importo = String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",") }
            b.negozio = e.negozio
            b.data = e.data
            b.letto = e.importo != nil
            if !eventoScelto { evento = eventoVicino(e.data ?? Date()) }
        }
    }

    // MARK: invio

    func invia() {
        guard let v = importo else { return }
        haptic()
        guard !Anteprima.attiva else { chiudi(); return }
        invio = true
        var c: [String: Any] = [
            "importo": v, "descrizione": b.perCosa.trimmingCharacters(in: .whitespaces),
            "categoria": Self.categorie[b.categoria].lowercased(), "pagamento": Self.codiciPagamento[b.pagamento],
            "data": isoGiorno(b.data ?? Date()),
        ]
        if let n = b.negozio { c["negozio"] = n }
        if let e = evento { c["evento"] = e.id }
        if let f = foto, let j = f.ridotta(lato: 1600).jpegData(compressionQuality: 0.7) { c["scontrino"] = j.base64EncodedString() }
        Task {
            defer { invio = false }
            do { try await JsocClient.shared.proponiSpesa(c); haptic(.medium); chiudi() }
            catch { errore = "Non riesco a inviarla: il server non accetta ancora le proposte di spesa. Riprova più tardi." }
        }
    }
}

// MARK: - Lettura dello scontrino (Vision, sul telefono)

enum LettoreScontrino {
    struct Esito { var importo: Double?; var negozio: String?; var data: Date? }

    static func leggi(_ img: UIImage) async -> Esito {
        guard let cg = img.ridotta(lato: 2000).cgImage else { return Esito() }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let req = VNRecognizeTextRequest()
                req.recognitionLevel = .accurate
                req.recognitionLanguages = ["it-IT", "en-US"]
                req.usesLanguageCorrection = false
                try? VNImageRequestHandler(cgImage: cg, orientation: .up).perform([req])
                let righe = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: analizza(righe))
            }
        }
    }

    static func numeri(_ s: String) -> [Double] {
        guard let re = try? NSRegularExpression(pattern: #"(\d{1,4})[.,](\d{2})(?!\d)"#) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { m in
            guard let a = Range(m.range(at: 1), in: s), let b = Range(m.range(at: 2), in: s) else { return nil }
            return Double("\(s[a]).\(s[b])")
        }
    }

    static func analizza(_ righe: [String]) -> Esito {
        var e = Esito()
        // importo: la riga del totale (o quella dopo), altrimenti il numero più grande
        for (i, r) in righe.enumerated() {
            let u = r.uppercased()
            guard u.contains("TOTALE") || u.contains("TOTAL") || u.contains("IMPORTO PAGATO") else { continue }
            if u.contains("SUBTOT") { continue }
            if let v = numeri(r).last ?? (i + 1 < righe.count ? numeri(righe[i + 1]).first : nil) { e.importo = v; break }
        }
        if e.importo == nil { e.importo = righe.flatMap(numeri).filter { $0 < 10000 }.max() }
        // data: gg/mm/aa(aa)
        if let re = try? NSRegularExpression(pattern: #"(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})"#) {
            for r in righe {
                guard let m = re.firstMatch(in: r, range: NSRange(r.startIndex..., in: r)),
                      let g = Range(m.range(at: 1), in: r).flatMap({ Int(r[$0]) }),
                      let mm = Range(m.range(at: 2), in: r).flatMap({ Int(r[$0]) }),
                      var a = Range(m.range(at: 3), in: r).flatMap({ Int(r[$0]) }) else { continue }
                if a < 100 { a += 2000 }
                if let d = Calendar.current.date(from: DateComponents(year: a, month: mm, day: g)), (1...12).contains(mm) { e.data = d; break }
            }
        }
        // negozio: la prima riga con parole vere
        e.negozio = righe.prefix(5).first { r in
            let lettere = r.filter(\.isLetter).count
            return lettere >= 3 && lettere * 2 > r.count && !r.uppercased().contains("DOCUMENTO")
        }.map { $0.capitalized.trimmingCharacters(in: .whitespaces) }
        return e
    }
}
