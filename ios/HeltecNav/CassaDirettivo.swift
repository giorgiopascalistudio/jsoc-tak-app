import SwiftUI
import PhotosUI

// MARK: - Nuovo movimento di cassa (tavola 50) e spesa da approvare (tavola 51).
// Misure, colori e testi delle tavole Movimento10 e ApprovaSpesa10 della tela.

/// lettura dello scontrino con l'OCR del telefono: totale, negozio, data
enum LetturaScontrino {
    struct Esito { var importo: Double?; var negozio: String?; var data: Date? }

    static func leggi(_ testo: String) -> Esito {
        let righe = testo.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        func importi(_ s: String) -> [Double] {
            let re = try? NSRegularExpression(pattern: "(\\d{1,5})[,.](\\d{2})(?!\\d)")
            let ns = s as NSString
            return (re?.matches(in: s, range: NSRange(location: 0, length: ns.length)) ?? []).compactMap {
                Double(ns.substring(with: $0.range(at: 1)) + "." + ns.substring(with: $0.range(at: 2)))
            }
        }
        var e = Esito()
        // il totale: riga con TOTALE (o quella dopo), altrimenti l'importo più alto
        for (i, r) in righe.enumerated() where r.uppercased().contains("TOTALE") || r.uppercased().contains("TOTAL") {
            if let v = importi(r).last ?? (i + 1 < righe.count ? importi(righe[i + 1]).first : nil) { e.importo = v; break }
        }
        if e.importo == nil { e.importo = righe.flatMap(importi).max() }
        e.negozio = righe.first { r in r.filter(\.isLetter).count >= 4 && importi(r).isEmpty }.map { r in
            r.lowercased().split(separator: " ").prefix(3).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        }
        if let re = try? NSRegularExpression(pattern: "(\\d{1,2})[/.-](\\d{1,2})[/.-](\\d{2,4})"),
           let m = re.firstMatch(in: testo, range: NSRange(location: 0, length: (testo as NSString).length)) {
            let ns = testo as NSString
            var a = Int(ns.substring(with: m.range(at: 3))) ?? 0
            if a < 100 { a += 2000 }
            e.data = Calendar.current.date(from: DateComponents(year: a, month: Int(ns.substring(with: m.range(at: 2))), day: Int(ns.substring(with: m.range(at: 1)))))
        }
        return e
    }
}

/// importo scritto col tastierino ("38,50") ↔ numero
func cifreInNumero(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }
func numeroInCifre(_ v: Double) -> String { String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",") }

// MARK: - Nuovo movimento (tavola 50)

struct NuovoMovimentoV3: View {
    var fatto: () -> Void = {}
    @Environment(\.dismiss) private var chiudi
    @ObservedObject private var store = EventoStore.shared
    @State private var tipo = 1
    @State private var cifre = ""
    @State private var categoria = 0
    @State private var conto = 0
    @State private var contoA = 1
    @State private var data = Date()
    @State private var socio: JSocioLibro?
    @State private var soci: [JSocioLibro] = []
    @State private var evento: (id: Int, nome: String, data: Date)?
    @State private var eventoToccato = false
    @State private var foto: UIImage?
    @State private var fotoScelta: PhotosPickerItem?
    @State private var fotocamera = false
    @State private var lettura: String?
    @State private var calendario = false
    @State private var lavoro = false
    @State private var errore: String?
    @State private var scontrinoFinto = false

    static let conti = [("cassa", "Cassa contanti"), ("banca", "Banca"), ("paypal", "PayPal")]
    static let categorieUscita = [("materiale", "Materiale"), ("campo e manutenzione", "Campo"), ("tesseramenti e polizze", "Quote FIGT"),
                                  ("trasporti", "Trasferte"), ("altro", "Altro"), ("gare e tornei", "Gare"), ("pallini", "Pallini"),
                                  ("rimborsi", "Rimborsi"), ("eventi e logistica", "Eventi"), ("affiliazione", "Affiliazione"), ("banca e oneri", "Banca")]
    static let categorieEntrata = [("quote associative", "Quote"), ("tesseramenti e polizze", "Quote FIGT"), ("contributi soci per eventi", "Eventi"),
                                   ("pallini", "Pallini"), ("donazioni ed erogazioni liberali", "Donazioni"), ("sponsorizzazioni", "Sponsor"), ("altro", "Altro")]
    var categorie: [(String, String)] { tipo == 0 ? Self.categorieEntrata : Self.categorieUscita }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // intestazione: Annulla · titolo 17 al centro · Salva
            HStack {
                Button("Annulla") { chiudi() }.font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.dim).frame(height: 36).padding(.horizontal, 4)
                Spacer()
                Button { Task { await salva() } } label: {
                    Text(lavoro ? "…" : "Salva").font(.system(size: 13.5, weight: .black)).foregroundStyle(Theme.scuro)
                        .padding(.horizontal, 14).frame(height: 36)
                        .background(Theme.olive.opacity(cifreInNumero(cifre) ?? 0 > 0 ? 1 : 0.45), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .disabled(lavoro || (cifreInNumero(cifre) ?? 0) <= 0)
            }
            .overlay { Text("Nuovo movimento").font(.system(size: 17, weight: .heavy)).foregroundStyle(Theme.testo).allowsHitTesting(false) }
            .padding(.horizontal, 14).padding(.top, 7)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    SceltaTela(voci: ["Entrata", "Uscita", "Giroconto"], scelta: $tipo)
                    importo
                    if tipo != 2 {
                        VStack(alignment: .leading, spacing: 5) {
                            EtichettaCampo(testo: "Categoria")
                            ScrollView(.horizontal) {
                                HStack(spacing: 6) {
                                    ForEach(categorie.indices, id: \.self) { i in
                                        Button { haptic(.soft); categoria = i } label: { ChipDir(testo: categorie[i].1, scelto: categoria == i, pieno: Theme.amber) }.buttonStyle(.plain)
                                    }
                                }
                            }
                            .scrollIndicators(.hidden)
                        }
                    }
                    sceltaConto(tipo == 2 ? "Da" : "Conto", $conto)
                    if tipo == 2 { sceltaConto("A", $contoA) }
                    HStack(alignment: .top, spacing: 8) {
                        campoData
                        if tipo != 2 { campoSocio }
                    }
                    if tipo != 2 { campoEvento }
                    if tipo == 1, let v = cifreInNumero(cifre), v > 100 {
                        NotaCampo(testo: "Sopra 100 € serve l'ok del Presidente", colore: Theme.amber)
                    }
                    if let errore { Text(errore).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.red) }
                    tastierino
                }
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .paginaDir()
        .onChange(of: tipo) { _ in categoria = 0 }
        .onChange(of: data) { _ in if !eventoToccato && !Anteprima.attiva { proponiEvento() } }
        .onChange(of: fotoScelta) { item in
            guard let item else { return }
            Task { if let d = try? await item.loadTransferable(type: Data.self), let i = UIImage(data: d) { await usaFoto(i) } }
        }
        .sheet(isPresented: $fotocamera) { CameraPicker { i in Task { await usaFoto(i) } }.ignoresSafeArea() }
        .sheet(isPresented: $calendario) {
            VStack {
                DatePicker("Data", selection: $data, displayedComponents: .date).datePickerStyle(.graphical).tint(Theme.olive).padding()
                Button("Fatto") { calendario = false }.font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.oliveBright)
            }
            .presentationDetents([.medium])
            .background(Theme.bg.ignoresSafeArea())
        }
        .task { await carica() }
    }

    // MARK: importo (mono 34) e scontrino

    var testoImporto: String {
        let v = cifre.isEmpty ? "0" : cifre
        return (tipo == 1 ? "− " : tipo == 0 ? "+ " : "") + v + " €"
    }

    var importo: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(testoImporto).font(Theme.mono(34, .heavy))
                    .foregroundStyle(tipo == 1 ? Theme.red : tipo == 0 ? Theme.oliveBright : Theme.testo)
                    .lineLimit(1).minimumScaleFactor(0.5)
                if let lettura {
                    HStack(spacing: 4) {
                        IconaTela(d: Ic.spunta, colore: Theme.oliveBright, lato: 12)
                        Text("letto dallo scontrino · " + lettura).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.oliveBright).lineLimit(1)
                    }
                } else if tipo != 2 {
                    Text("Fotografa lo scontrino: leggo importo, negozio e data").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.dim).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if tipo != 2 {
                Menu {
                    Button { fotocamera = true } label: { Label("Fotografa lo scontrino", systemImage: "camera") }
                    PhotosPicker(selection: $fotoScelta, matching: .images) { Label("Scegli dalle foto", systemImage: "photo") }
                    if foto != nil { Button(role: .destructive) { foto = nil; lettura = nil } label: { Label("Togli la ricevuta", systemImage: "trash") } }
                } label: {
                    if foto != nil || scontrinoFinto { ScontrinoDir(foto: foto) } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.olive.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .frame(width: 52, height: 66)
                            .overlay(IconaTela(d: Ic.fotocamera, colore: Theme.olive, lato: 20))
                    }
                }
                .accessibilityLabel("Ricevuta o scontrino")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Theme.stroke))
    }

    func sceltaConto(_ titolo: String, _ scelta: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            EtichettaCampo(testo: titolo)
            HStack(spacing: 6) {
                ForEach(Self.conti.indices, id: \.self) { i in
                    Button { haptic(.soft); scelta.wrappedValue = i } label: { ChipDir(testo: Self.conti[i].1, scelto: scelta.wrappedValue == i, pieno: Theme.olive) }.buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: data, pagato da, evento (campi 46)

    var campoData: some View {
        VStack(alignment: .leading, spacing: 4) {
            EtichettaCampo(testo: "Data")
            Button { calendario = true } label: {
                RiquadroCampo {
                    Text(FormatiDir.giornoMeseAnno.string(from: data)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.testo)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    IconaTela(d: Ic.calendario, colore: Theme.olive, lato: 17)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    var campoSocio: some View {
        VStack(alignment: .leading, spacing: 4) {
            EtichettaCampo(testo: tipo == 0 ? "Versato da" : "Pagato da")
            Menu {
                Button("Associazione (nessun socio)") { socio = nil }
                ForEach(soci.filter { $0.attivo == 1 }) { s in Button(s.callsign) { socio = s } }
            } label: {
                RiquadroCampo {
                    Text(socio.map { $0.callsign + (tipo == 1 ? " · rimborso" : "") } ?? "Associazione")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.testo).lineLimit(2).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    IconaTela(d: Ic.persona, colore: Theme.olive, lato: 17)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    var campoEvento: some View {
        VStack(alignment: .leading, spacing: 4) {
            EtichettaCampo(testo: "Evento collegato")
            Menu {
                Button("Nessun evento") { evento = nil; eventoToccato = true }
                ForEach(eventiVicini, id: \.id) { e in
                    Button(e.nome + (e.dataInizio.map { " · " + FormatiHome.giornoMese.string(from: $0) } ?? "")) {
                        evento = (e.id, e.nome, e.dataInizio ?? data); eventoToccato = true
                    }
                }
            } label: {
                RiquadroCampo {
                    Text(evento.map { $0.nome + " · " + FormatiHome.giornoMese.string(from: $0.data) } ?? "Nessun evento")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(evento == nil ? Theme.dim : Theme.testo).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    IconaTela(d: Ic.calendario, colore: Theme.olive, lato: 17)
                }
            }
            if evento != nil && !eventoToccato { NotaCampo(testo: "Proposto: l'evento più vicino alla data") }
        }
    }

    /// eventi ordinati per distanza dalla data del movimento
    var eventiVicini: [JEvento] {
        store.eventi.filter { $0.dataInizio != nil }
            .sorted { abs($0.dataInizio!.timeIntervalSince(data)) < abs($1.dataInizio!.timeIntervalSince(data)) }
            .prefix(15).map { $0 }
    }

    func proponiEvento() {
        guard let e = eventiVicini.first, let d = e.dataInizio, abs(d.timeIntervalSince(data)) < 10 * 86400 else { evento = nil; return }
        evento = (e.id, e.nome, d)
    }

    // MARK: tastierino (3 colonne, tasti 46)

    var tastierino: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", ",", "0", "⌫"], id: \.self) { k in
                Button { premi(k) } label: {
                    Text(k).font(Theme.mono(19, .heavy)).foregroundStyle(Theme.testo)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(k == "⌫" ? "Cancella" : k == "," ? "Virgola" : k)
            }
        }
    }

    func premi(_ k: String) {
        haptic(.soft)
        switch k {
        case "⌫": if !cifre.isEmpty { cifre.removeLast() }
        case ",": if !cifre.contains(",") { cifre = (cifre.isEmpty ? "0" : cifre) + "," }
        default:
            if let v = cifre.firstIndex(of: ","), cifre.distance(from: v, to: cifre.endIndex) > 2 { return }
            if cifre == "0" { cifre = k } else if cifre.count < 8 { cifre += k }
        }
    }

    // MARK: dati

    func usaFoto(_ i: UIImage) async {
        foto = i
        let e = LetturaScontrino.leggi(await OCR.text(from: i))
        if let v = e.importo, cifre.isEmpty || cifreInNumero(cifre) == 0 { cifre = numeroInCifre(v) }
        if let d = e.data { data = d }
        var p: [String] = []
        if let n = e.negozio { p.append(n) }
        if let d = e.data { p.append(FormatiHome.giornoMese.string(from: d)) }
        lettura = e.importo == nil ? nil : p.joined(separator: " · ")
    }

    func carica() async {
        if Anteprima.attiva {
            let a = Anteprima.dirMovimento
            cifre = a.cifre; data = a.data; lettura = a.lettura; scontrinoFinto = true
            socio = a.socio; soci = [a.socio]; evento = a.evento
            return
        }
        soci = (try? await JsocClient.shared.libroSoci()) ?? []
        proponiEvento()
    }

    func salva() async {
        guard let v = cifreInNumero(cifre), v > 0 else { return }
        if Anteprima.attiva { chiudi(); return }
        lavoro = true; defer { lavoro = false }
        let t = ["entrata", "uscita", "giroconto"][tipo]
        let cat = tipo == 2 ? "giroconto" : categorie[min(categoria, categorie.count - 1)].0
        var c: [String: Any] = ["tipo": t, "importo": v, "categoria": cat, "conto": Self.conti[conto].0, "data": isoGiorno(data),
                                "natura": "istituzionale", "destinazione": "",
                                "descrizione": lettura ?? (tipo == 2 ? "Giroconto" : categorie[min(categoria, categorie.count - 1)].1)]
        if tipo == 2 { c["conto_a"] = Self.conti[contoA].0 }
        c["utente"] = tipo == 2 ? NSNull() : (socio.map { $0.id as Any } ?? NSNull())
        c["evento"] = tipo == 2 ? NSNull() : (evento.map { $0.id as Any } ?? NSNull())
        do {
            let m = try await JsocClient.shared.nuovoMovimento2(c)
            if let img = foto, let jpg = img.ridotta(lato: 1800).jpegData(compressionQuality: 0.75) {
                try await JsocClient.shared.caricaDati("/api/cassa2/\(m.id)/ricevuta", dati: jpg)
            }
            haptic(.medium); fatto(); chiudi()
        } catch { errore = erroreGentile(error) }
    }
}

// MARK: - Spesa da approvare (tavola 51)

struct ApprovaSpesaV3: View {
    let spesa: JSpesaProposta
    var fatto: () -> Void = {}
    @Environment(\.dismiss) private var chiudi
    @ObservedObject private var perm = PermessiStore.shared
    @State private var conto = 0
    @State private var foto: UIImage?
    @State private var fotoGrande = false
    @State private var chiediMotivo = false
    @State private var motivo = ""
    @State private var lavoro = false
    @State private var esito: String?
    @State private var riuscito = false

    var proponente: String { spesa.callsign ?? "il socio" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TestataDir(titolo: "Spesa da approvare")
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    scheda
                    VStack(alignment: .leading, spacing: 5) {
                        EtichettaCampo(testo: "Se approvi, paga da")
                        SceltaTela(voci: NuovoMovimentoV3.conti.map(\.1), scelta: $conto)
                    }
                    HStack(spacing: 8) {
                        Button { chiediMotivo = true } label: {
                            Text("Rifiuta").font(.system(size: 15, weight: .black)).foregroundStyle(Theme.red)
                                .frame(maxWidth: .infinity).frame(height: 52)
                                .background(Theme.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Theme.red.opacity(0.5)))
                        }
                        .buttonStyle(PressStyle())
                        Button { Task { await decidi(true) } } label: {
                            Text(lavoro ? "…" : "Approva").font(.system(size: 15, weight: .black)).foregroundStyle(Theme.scuro)
                                .frame(maxWidth: .infinity).frame(height: 52)
                                .background(Theme.olive, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        }
                        .buttonStyle(PressStyle())
                    }
                    .disabled(lavoro)
                    Text("Approvata: diventa un movimento in cassa con numero progressivo e la ricevuta allegata; \(proponente) riceve la notifica e il rimborso compare nei suoi pagamenti. Rifiutata: va scritto il motivo, che arriva a chi l'ha proposta. Sopra 100 € serve l'ok del Presidente.")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.dim).multilineTextAlignment(.center).lineSpacing(2.7)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .paginaDir()
        .alert("Perché la rifiuti?", isPresented: $chiediMotivo) {
            TextField("Motivo (lo riceve \(proponente))", text: $motivo)
            Button("Annulla", role: .cancel) {}
            Button("Rifiuta", role: .destructive) { Task { await decidi(false) } }.disabled(motivo.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: { Text("Il motivo è obbligatorio e arriva a chi l'ha proposta.") }
        .alert(esito ?? "", isPresented: Binding(get: { esito != nil }, set: { if !$0 { esito = nil } })) {
            Button("OK") { if riuscito { fatto(); chiudi() } }
        }
        .sheet(isPresented: $fotoGrande) {
            if let foto { Image(uiImage: foto).resizable().scaledToFit().padding().background(Color.black.ignoresSafeArea()) }
        }
        .task {
            if spesa.ricevuta == true, !Anteprima.attiva,
               let d = try? await JsocClient.shared.scaricaDati("/api/spese-proposte/\(spesa.id)/ricevuta") { foto = UIImage(data: d) }
        }
    }

    // MARK: scheda della spesa (bordo ambra, scontrino 64×84, importo mono 30, righe 112)

    var scheda: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { if foto != nil { fotoGrande = true } } label: {
                    ScontrinoDir(foto: foto, larghezza: 64, altezza: 84, righe: [1, 0.7, 1, 0.5, 0.8])
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 5) {
                        TagDir(testo: spesa.stato == "presidente" ? "OK PRESIDENTE" : "IN ATTESA", colore: Theme.amber)
                        TagDir(testo: (spesa.tipo ?? "rimborso").uppercased(), colore: Theme.cyan)
                    }
                    Text(euroIT(spesa.importo)).font(Theme.mono(30, .heavy)).foregroundStyle(Theme.testo).lineLimit(1).minimumScaleFactor(0.6).padding(.top, 4)
                    if let d = spesa.descrizione, !d.isEmpty { Text(d).font(.system(size: 12.5)).foregroundStyle(Theme.testo2).lineLimit(2) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            riga("Proposta da") {
                (Text(spesa.callsign ?? "—").font(Theme.mono(13, .bold)) + Text(quando.map { " · " + $0 } ?? ""))
            }
            riga("Negozio e data") { Text([spesa.negozio, giorno(spesa.data, anno: true)].compactMap { $0 }.joined(separator: " · ").ifEmpty("—")) }
            riga("Categoria") { Text((spesa.categoria ?? "—").prefix(1).uppercased() + (spesa.categoria ?? "").dropFirst()) }
            riga("Evento") { Text([spesa.evento_nome, giorno(spesa.evento_inizio, anno: false)].compactMap { $0 }.joined(separator: " · ").ifEmpty("—")) }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.amber.opacity(0.4)))
    }

    func riga(_ t: String, @ViewBuilder _ v: () -> Text) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(t).foregroundStyle(Theme.dim).frame(width: 112, alignment: .leading)
            v().foregroundStyle(Theme.testo).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 13, weight: .bold))
        .padding(.horizontal, 12).padding(.vertical, 9)
        .overlay(alignment: .top) { Rectangle().fill(Theme.olive.opacity(0.12)).frame(height: 1) }
    }

    /// "ieri 19:40", "oggi 9:05", "18 nov 19:40"
    var quando: String? {
        guard let ts = spesa.ts else { return nil }
        let d = Date(timeIntervalSince1970: ts), cal = Calendar.current
        let ora = FormatiHome.ora.string(from: d)
        if cal.isDateInToday(d) { return "oggi " + ora }
        if cal.isDateInYesterday(d) { return "ieri " + ora }
        return FormatiHome.giornoMese.string(from: d) + " " + ora
    }

    func giorno(_ s: String?, anno: Bool) -> String? {
        guard let d = JEvento.data(s) else { return nil }
        return (anno ? FormatiDir.giornoMeseAnno : FormatiHome.giornoMese).string(from: d)
    }

    func decidi(_ approva: Bool) async {
        haptic(.medium)
        if Anteprima.attiva { esito = approva ? "Approvata: movimento U-2026-031 in cassa." : "Rifiutata: \(proponente) riceve il motivo."; return }
        lavoro = true
        do {
            let r = try await JsocClient.shared.esitoSpesa(spesa.id, approva: approva, conto: NuovoMovimentoV3.conti[conto].0, motivo: motivo)
            lavoro = false
            if let e = r.errore { esito = e; return }
            riuscito = true
            if approva {
                let soloPresidente = spesa.importo > 100 && perm.p?.carica != "presidente"
                esito = r.stato == "presidente" || (r.numero == nil && soloPresidente)
                    ? "Sopra 100 €: la spesa aspetta l'ok del Presidente."
                    : "Approvata" + (r.numero.map { ": movimento \($0) in cassa." } ?? ".")
            } else {
                esito = "Rifiutata: \(proponente) riceve il motivo."
            }
        } catch {
            lavoro = false
            esito = erroreGentile(error)
        }
    }
}
