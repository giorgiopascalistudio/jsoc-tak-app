import SwiftUI
import UserNotifications

// MARK: - Associazione: segreteria, documenti automatici, scadenze, direttivo, prestiti, assicurazione

struct JDomanda: Codable, Identifiable {
    let id: Int
    let utente: Int
    let anno: Int?
    let tipo: String?
    let dati: DatiDomanda
    var firma: String? = nil
    let stato: String
    let creata: Double?
    var decisa: Double? = nil
    var note: String? = nil
    var pdf: String? = nil
    var callsign: String? = nil
    var minore: Bool { tipo == "minorenne" }
}

struct JRicevuta: Codable, Identifiable {
    let id: Int; let anno: Int; let numero: Int; let data: String?; let utente: Int?; let intestatario: String; let cf: String?
    let importo: Double; let causale: String; let metodo: String?; let annullata: Int?; let pdf: String?; var callsign: String? = nil
    var dati: ModelliPDF.DatiRicevuta {
        .init(numero: numero, anno: anno, data: data ?? oggiISO(), intestatario: intestatario, cf: cf ?? "", importo: importo,
              causale: causale, metodo: metodo ?? "contanti", annullata: (annullata ?? 0) != 0)
    }
}

struct JScadenza: Codable, Identifiable {
    var id: String { tipo + titolo + (data ?? "") }
    let tipo: String; let titolo: String; let data: String?; let giorni: Int?; let testo: String?; let utente: Int?; let callsign: String?; let azione: String?
}

struct JAdempimento: Codable, Identifiable { let id: Int; let titolo: String; let scadenza: String; let note: String?; let fatto: [String: String] }

struct JDelibera: Codable, Hashable { var testo: String; var esito: String; var favorevoli: Int; var contrari: Int; var astenuti: Int }
struct JRiunione: Codable, Identifiable {
    let id: Int; var data: String?; var ora: String?; var luogo: String?; var odg: [String]; var presenti: [Int]; var delibere: [JDelibera]
    var varie: String?; let stato: String; let numero: Int?; let pdf: String?
}
struct JMembroCD: Codable, Identifiable, Hashable { let id: Int; let callsign: String; let nome: String?; let carica: String? }
struct JRiunioni: Codable { let riunioni: [JRiunione]; let membri: [JMembroCD] }

struct JPrestito: Codable, Identifiable {
    let id: Int; let materiale: Int; let utente: Int; let quantita: Double?; let dal: String?; let al: String?; let reso: String?
    let note: String?; let materiale_nome: String; let callsign: String
}

/// carica il PDF nei documenti dell'associazione
func caricaPDF(_ percorso: String, _ d: Data) async throws { try await JsocClient.shared.caricaDati(percorso, dati: d) }

func firmaDaBase64(_ s: String?) -> UIImage? {
    guard let s, let i = s.range(of: "base64,") else { return nil }
    return Data(base64Encoded: String(s[i.upperBound...])).flatMap { UIImage(data: $0) }
}

// MARK: - Domanda di iscrizione (la compila il socio o l'aspirante)

struct DomandaIscrizioneView: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var doc = DocAssoc.shared
    @State private var d = DatiDomanda()
    @State private var nascita = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var nascitaGen = Calendar.current.date(byAdding: .year, value: -45, to: Date()) ?? Date()
    @State private var tratti: [[CGPoint]] = []
    @State private var mie: [JDomanda] = []
    @State private var anteprima: DocumentoPronto?
    @State private var errore: String?
    @State private var inviata = false
    @State private var lavoro = false

    var eta: Int { Calendar.current.dateComponents([.year], from: nascita, to: Date()).year ?? 30 }
    var minore: Bool { eta < 18 }
    var firma: UIImage? { FirmaPad.immagine(tratti) }

    var body: some View {
        Form {
            if !mie.isEmpty {
                Section("Le tue domande") {
                    ForEach(mie) { x in
                        HStack {
                            Text("Anno \(x.anno.map(String.init) ?? "")").font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Etichetta(testo: x.stato.uppercased(), colore: x.stato == "accettata" ? Theme.green : (x.stato == "respinta" ? Theme.red : Theme.amber))
                        }
                    }
                }
            }
            Section { Text("Compila la domanda: l'app prepara il modulo dell'associazione già firmato e lo manda al Consiglio Direttivo.").font(.footnote).foregroundStyle(Theme.dim) }
                .listRowBackground(Color.clear)
            Section(minore ? "Dati del minore" : "Dati anagrafici") {
                TextField("Nome e cognome", text: $d.nome)
                DatePicker("Data di nascita", selection: $nascita, in: ...Date(), displayedComponents: .date)
                HStack { TextField("Luogo di nascita", text: $d.luogo_nascita); TextField("Prov.", text: $d.provincia_nascita).frame(width: 60) }
                TextField("Codice fiscale", text: $d.cf).textInputAutocapitalization(.characters).autocorrectionDisabled()
                if eta < 13 { Label("Sotto i 13 anni non è possibile il tesseramento FIGT", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.red) }
            }
            Section("Residenza") {
                HStack { TextField("Comune", text: $d.comune); TextField("Prov.", text: $d.provincia).frame(width: 60) }
                HStack { TextField("Via", text: $d.via); TextField("N°", text: $d.civico).frame(width: 60) }
                TextField("CAP", text: $d.cap).keyboardType(.numberPad)
            }
            if minore {
                Section("Genitore / esercente la responsabilità") {
                    TextField("Nome e cognome del genitore", text: $d.genitore_nome)
                    DatePicker("Nato il", selection: $nascitaGen, in: ...Date(), displayedComponents: .date)
                    TextField("Luogo di nascita", text: $d.genitore_luogo)
                    TextField("Codice fiscale", text: $d.genitore_cf).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    TextField("Cellulare", text: $d.genitore_telefono).keyboardType(.phonePad)
                    TextField("E-mail", text: $d.genitore_email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                }
            } else {
                Section("Contatti") {
                    TextField("Cellulare", text: $d.telefono).keyboardType(.phonePad)
                    TextField("E-mail", text: $d.email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                }
            }
            Section("Salute") {
                TextField("Allergie (lascia vuoto se nessuna)", text: $d.allergie, axis: .vertical)
            }
            Section {
                Toggle(isOn: $d.accetta_statuto) { Text("Conosco e accetto lo Statuto e le deliberazioni degli organi sociali") }
                Toggle(isOn: $d.accetta_rischi) { Text("Ho letto e accetto la dichiarazione sui rischi del soft air e le polizze FIGT") }
                Toggle(isOn: $d.consenso_privacy) { Text("Acconsento al trattamento dei dati personali (obbligatorio)") }
                Toggle(isOn: $d.consenso_immagini) { Text("Autorizzo la pubblicazione di foto e video (facoltativo, revocabile)") }
                DisclosureGroup("Leggi i testi completi") {
                    Text("Il modulo riporta per intero: richiesta di ammissione, assunzione di responsabilità e conoscenza delle polizze FIGT, consenso al trattamento dei dati, autorizzazione alle immagini e la dichiarazione dei rischi (punti A–G). Premi «Anteprima» per leggerlo esattamente come verrà firmato.")
                        .font(.footnote).foregroundStyle(Theme.dim)
                }
            } header: { Text("Dichiarazioni e consensi") }
            Section {
                FirmaPad(tratti: $tratti).listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            } header: { Text(minore ? "Firma del genitore" : "Firma") } footer: { Text("La stessa firma va su ogni riga «Firma» del modulo.") }
            if let errore { Section { Text(errore).foregroundStyle(Theme.red) } }
            Section {
                Button { apriAnteprima() } label: { Label("Anteprima del modulo", systemImage: "doc.richtext") }
                Button { invia() } label: {
                    HStack { if lavoro { ProgressView() }; Label(inviata ? "Domanda inviata" : "Firma e invia la domanda", systemImage: inviata ? "checkmark.seal.fill" : "paperplane.fill") }
                }
                .disabled(lavoro || inviata || !pronta)
            }
        }
        .scrollContentBackground(.hidden).background(Theme.bg)
        .navigationTitle("Domanda di iscrizione \(doc.intest.annoAssociativo)")
        .task {
            await doc.carica()
            mie = (try? await jsoc.get("/api/domande")) ?? []
            mie = mie.filter { $0.utente == jsoc.utente?.id }
            if d.nome.isEmpty, let p = try? await jsoc.profilo() {
                d.nome = p.nome; d.email = p.email ?? ""; d.telefono = p.telefono ?? ""; d.cf = p.cf ?? ""; d.luogo_nascita = p.luogo_nascita ?? ""
                if let n = p.nascita, let dt = ISO8601DateFormatter.soloData(n) { nascita = dt }
            }
        }
        .sheet(item: $anteprima) { AnteprimaPDF(doc: $0) }
    }

    var pronta: Bool {
        !d.nome.isEmpty && d.cf.count >= 11 && d.accetta_statuto && d.accetta_rischi && d.consenso_privacy && !tratti.isEmpty
            && eta >= 13 && (!minore || (!d.genitore_nome.isEmpty && !d.genitore_cf.isEmpty))
    }

    func compila() -> DatiDomanda {
        var x = d
        x.nascita = oraISO(nascita)
        x.genitore_nascita = minore ? oraISO(nascitaGen) : ""
        x.data = oggiISO()
        x.cf = x.cf.uppercased(); x.genitore_cf = x.genitore_cf.uppercased()
        return x
    }

    func pdf(_ x: DatiDomanda) -> Data {
        ModelliPDF.domanda(x, minore: minore, firma: firma, firmaPresidente: nil, anno: doc.intest.annoAssociativo, intest: doc.intest, loghi: doc.loghi)
    }

    func apriAnteprima() { let x = compila(); anteprima = DocumentoPronto(titolo: "Domanda \(x.nome)", dati: pdf(x)) }

    func invia() {
        guard let f = firma, let png = f.pngData() else { errore = "Manca la firma"; return }
        lavoro = true; errore = nil
        let x = compila()
        Task {
            do {
                let r: JDomanda = try await jsoc.send("/api/domande", "POST", ["tipo": minore ? "minorenne" : "maggiorenne", "dati": x.json,
                                                                             "firma": "data:image/png;base64," + png.base64EncodedString()])
                try? await caricaPDF("/api/domande/\(r.id)/pdf", pdf(x))
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.spring()) { inviata = true; mie.insert(r, at: 0) }
            } catch { errore = error.localizedDescription }
            lavoro = false
        }
    }
}

func oraISO(_ d: Date) -> String { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d) }
extension ISO8601DateFormatter {
    static func soloData(_ s: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }
}

// MARK: - Domande ricevute (direttivo)

struct DomandeView: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var doc = DocAssoc.shared
    @State private var domande: [JDomanda] = []
    @State private var aperta: JDomanda?
    @State private var anteprima: DocumentoPronto?
    @State private var errore: String?

    var body: some View {
        List {
            if domande.isEmpty { Text("Nessuna domanda di iscrizione.").foregroundStyle(Theme.dim).listRowBackground(Theme.surface) }
            ForEach(["inviata", "accettata", "respinta"], id: \.self) { st in
                let l = domande.filter { $0.stato == st }
                if !l.isEmpty {
                    Section(st == "inviata" ? "Da valutare" : (st == "accettata" ? "Accettate" : "Respinte")) {
                        ForEach(Array(l.enumerated()), id: \.element.id) { i, x in
                            Button { apri(x) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(x.dati.nome).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                        Text("\(x.callsign ?? "") · \(x.minore ? "minorenne · " : "")\(x.creata.map { Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .omitted) } ?? "")")
                                            .font(.caption).foregroundStyle(Theme.dim)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.dim)
                                }
                            }
                            .comparsa(i)
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            if let errore { Text(errore).foregroundStyle(Theme.red) }
        }
        .scrollContentBackground(.hidden).background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Domande di iscrizione")
        .task { await doc.carica(); await carica() }
        .refreshable { await carica() }
        .sheet(item: $aperta) { x in DettaglioDomanda(domanda: x) { await carica() } }
    }

    func carica() async { domande = (try? await jsoc.get("/api/domande")) ?? [] }
    func apri(_ x: JDomanda) { Task { aperta = (try? await jsoc.get("/api/domande/\(x.id)")) ?? x } }
}

struct DettaglioDomanda: View {
    let domanda: JDomanda
    var aggiorna: () async -> Void
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var doc = DocAssoc.shared
    @State private var anteprima: DocumentoPronto?
    @State private var note = ""
    @State private var errore: String?
    @State private var chiedi = false

    var x: DatiDomanda { domanda.dati }

    var body: some View {
        NavigationStack {
            Form {
                Section("Richiedente") {
                    riga("Nome", x.nome); riga("Nato", "\(x.luogo_nascita) (\(x.provincia_nascita)) il \(dataIta(x.nascita))"); riga("Codice fiscale", x.cf)
                    riga("Residenza", "\(x.via) \(x.civico), \(x.cap) \(x.comune) (\(x.provincia))"); riga("Telefono", x.telefono); riga("E-mail", x.email)
                    riga("Allergie", x.allergie.isEmpty ? "nessuna" : x.allergie)
                }
                if domanda.minore {
                    Section("Genitore") { riga("Nome", x.genitore_nome); riga("Codice fiscale", x.genitore_cf); riga("Telefono", x.genitore_telefono) }
                }
                Section("Consensi") {
                    riga("Statuto", x.accetta_statuto ? "accettato" : "no"); riga("Rischi", x.accetta_rischi ? "accettati" : "no")
                    riga("Privacy", x.consenso_privacy ? "sì" : "no"); riga("Foto e video", x.consenso_immagini ? "sì" : "no")
                }
                Section {
                    if let f = firmaDaBase64(domanda.firma) { Image(uiImage: f).resizable().scaledToFit().frame(height: 70).padding(6).background(Color.white, in: RoundedRectangle(cornerRadius: 8)) }
                    Button { anteprima = DocumentoPronto(titolo: "Domanda \(x.nome)", dati: pdf(conPresidente: domanda.stato == "accettata")) } label: { Label("Vedi il modulo firmato", systemImage: "doc.richtext") }
                }
                if domanda.stato == "inviata" {
                    Section {
                        TextField("Note (facoltative)", text: $note)
                        if doc.firmaPresidente == nil { Label("La firma del presidente non è salvata: impostala in Dati dell'associazione", systemImage: "signature").font(.footnote).foregroundStyle(Theme.amber) }
                        Button { esito("accettata") } label: { Label("Accetta: diventa socio", systemImage: "checkmark.seal.fill") }.tint(Theme.green)
                        Button(role: .destructive) { chiedi = true } label: { Label("Respingi", systemImage: "xmark.octagon") }
                    } footer: { Text("Accettando: i dati passano nella scheda del socio, entra nel libro soci e viene creata la quota dell'anno da incassare.") }
                } else {
                    Section { riga("Esito", domanda.stato); if let n = domanda.note, !n.isEmpty { riga("Note", n) } }
                }
                if let errore { Section { Text(errore).foregroundStyle(Theme.red) } }
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle(x.nome).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
            .confirmationDialog("Respingere la domanda?", isPresented: $chiedi, titleVisibility: .visible) {
                Button("Respingi", role: .destructive) { esito("respinta") }
            }
            .sheet(item: $anteprima) { AnteprimaPDF(doc: $0) }
        }
    }

    func riga(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) { Text(k).foregroundStyle(Theme.dim).frame(width: 110, alignment: .leading); Text(v).textSelection(.enabled) }.font(.system(size: 14))
    }

    func pdf(conPresidente: Bool) -> Data {
        ModelliPDF.domanda(x, minore: domanda.minore, firma: firmaDaBase64(domanda.firma), firmaPresidente: conPresidente ? doc.firmaPresidente : nil,
                           anno: domanda.anno ?? doc.intest.annoAssociativo, intest: doc.intest, loghi: doc.loghi)
    }

    func esito(_ e: String) {
        Task {
            do {
                let _: JDomanda = try await JsocClient.shared.send("/api/domande/\(domanda.id)/esito", "POST", ["esito": e, "note": note])
                if e == "accettata" { try? await caricaPDF("/api/domande/\(domanda.id)/pdf", pdf(conPresidente: true)) }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                await aggiorna(); dismiss()
            } catch { errore = error.localizedDescription }
        }
    }
}

// MARK: - Ricevute numerate

struct RicevuteView: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var doc = DocAssoc.shared
    @ObservedObject private var perm = PermessiStore.shared
    @State private var anno = Calendar.current.component(.year, from: Date())
    @State private var ricevute: [JRicevuta] = []
    @State private var nuova = false
    @State private var anteprima: DocumentoPronto?
    @State private var errore: String?

    var gestisce: Bool { perm.puo("cassa") }

    var body: some View {
        List {
            if gestisce {
                Section {
                    Picker("Anno", selection: $anno) { ForEach((2019...Calendar.current.component(.year, from: Date()) + 1).reversed(), id: \.self) { Text(String($0)).tag($0) } }
                    let tot = ricevute.filter { ($0.annullata ?? 0) == 0 }.reduce(0) { $0 + $1.importo }
                    HStack { Text("\(ricevute.count) ricevute"); Spacer(); Text("€ \(euroTesto(tot))").font(Theme.mono(14, .bold)) }
                }
                .listRowBackground(Theme.surface)
            }
            if ricevute.isEmpty { Text(gestisce ? "Nessuna ricevuta nell'anno." : "Non hai ancora ricevute.").foregroundStyle(Theme.dim).listRowBackground(Theme.surface) }
            Section {
                ForEach(Array(ricevute.enumerated()), id: \.element.id) { i, r in
                    Button { mostra(r) } label: {
                        HStack {
                            Text("\(r.numero)/\(r.anno)").font(Theme.mono(13, .heavy)).foregroundStyle(Theme.oliveBright).frame(width: 64, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.intestatario).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(.white).strikethrough((r.annullata ?? 0) != 0)
                                Text("\(dataIta(r.data)) · \(r.causale)").font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                            }
                            Spacer()
                            Text("€ \(euroTesto(r.importo))").font(Theme.mono(13, .bold)).foregroundStyle((r.annullata ?? 0) != 0 ? Theme.dim : .white)
                        }
                    }
                    .comparsa(i)
                    .swipeActions {
                        if gestisce && (r.annullata ?? 0) == 0 {
                            Button(role: .destructive) { annulla(r) } label: { Label("Annulla", systemImage: "xmark") }
                        }
                    }
                }
            }
            .listRowBackground(Theme.surface)
            if let errore { Text(errore).foregroundStyle(Theme.red) }
        }
        .scrollContentBackground(.hidden).background(Theme.bg.ignoresSafeArea())
        .navigationTitle(gestisce ? "Ricevute" : "Le mie ricevute")
        .toolbar { if gestisce { Button { nuova = true } label: { Image(systemName: "plus.circle.fill") } } }
        .task(id: anno) { await doc.carica(); await carica() }
        .refreshable { await carica() }
        .sheet(isPresented: $nuova) { NuovaRicevutaSheet { r in Task { await carica(); mostra(r, salva: true) } } }
        .sheet(item: $anteprima) { AnteprimaPDF(doc: $0) }
    }

    func carica() async { ricevute = (try? await jsoc.get("/api/ricevute?anno=\(anno)")) ?? [] }

    func mostra(_ r: JRicevuta, salva: Bool = false) {
        let d = ModelliPDF.ricevuta(r.dati, firma: doc.firmaPresidente, intest: doc.intest, loghi: doc.loghi)
        if salva { Task { try? await caricaPDF("/api/ricevute/\(r.id)/pdf", d) } }
        anteprima = DocumentoPronto(titolo: "Ricevuta \(r.numero)-\(r.anno)", dati: d, salva: { try await caricaPDF("/api/ricevute/\(r.id)/pdf", d) })
    }

    func annulla(_ r: JRicevuta) {
        Task {
            do { let _: JOk = try await jsoc.send("/api/ricevute/\(r.id)/annulla", "POST", [String: Any]()); await carica() }
            catch { errore = error.localizedDescription }
        }
    }
}

struct NuovaRicevutaSheet: View {
    var fatto: (JRicevuta) -> Void
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var doc = DocAssoc.shared
    @State private var soci: [JProfilo] = []
    @State private var socio: Int?
    @State private var intestatario = ""
    @State private var cf = ""
    @State private var importo = ""
    @State private var causale = ""
    @State private var metodo = "contanti"
    @State private var data = Date()
    @State private var quota = true
    @State private var cassa = true
    @State private var errore: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Da chi") {
                    Picker("Socio", selection: $socio) {
                        Text("Altro (sponsor, esterno…)").tag(Int?.none)
                        ForEach(soci) { s in Text("\(s.callsign) · \(s.nome)").tag(Int?.some(s.id)) }
                    }
                    if socio == nil {
                        TextField("Intestatario", text: $intestatario)
                        TextField("Codice fiscale / P. IVA", text: $cf).textInputAutocapitalization(.characters)
                    }
                }
                Section("Cosa") {
                    Toggle("È la quota associativa", isOn: $quota)
                    TextField("Importo €", text: $importo).keyboardType(.decimalPad)
                    TextField("Causale", text: $causale)
                    Picker("Pagamento", selection: $metodo) {
                        Text("Contanti").tag("contanti"); Text("Bonifico").tag("bonifico"); Text("POS / carta").tag("pos"); Text("PayPal").tag("paypal")
                    }
                    DatePicker("Data", selection: $data, displayedComponents: .date)
                }
                Section { Toggle("Registra l'entrata nel fondo cassa", isOn: $cassa) }
                    footer: { Text("Il numero della ricevuta è progressivo per anno. Se è la quota, il socio risulta in regola.") }
                if let errore { Section { Text(errore).foregroundStyle(Theme.red) } }
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("Nuova ricevuta").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Emetti") { emetti() }.disabled(Double(importo.replacingOccurrences(of: ",", with: ".")) == nil || causale.isEmpty) }
            }
            .task {
                soci = ((try? await jsoc.soci())?.soci ?? []).filter { ($0.attivo ?? 1) == 1 }
                if importo.isEmpty { importo = euroTesto(doc.intest.quota ?? 50) }
                if causale.isEmpty { causale = "Quota associativa anno \(doc.intest.annoAssociativo)" }
            }
            .onChange(of: quota) { q in
                causale = q ? "Quota associativa anno \(doc.intest.annoAssociativo)" : ""
                if q { importo = euroTesto(doc.intest.quota ?? 50) }
            }
        }
    }

    func emetti() {
        var b: [String: Any] = ["importo": Double(importo.replacingOccurrences(of: ",", with: ".")) ?? 0, "causale": causale, "metodo": metodo,
                                "data": oraISO(data), "quota": quota, "registra_cassa": cassa, "anno_quota": doc.intest.annoAssociativo]
        if let socio { b["utente"] = socio } else { b["intestatario"] = intestatario; b["cf"] = cf }
        Task {
            do { let r: JRicevuta = try await jsoc.send("/api/ricevute", "POST", b); fatto(r); dismiss() }
            catch { errore = error.localizedDescription }
        }
    }
}

// MARK: - Scadenzario (con promemoria sul telefono)

struct ScadenzarioView: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var perm = PermessiStore.shared
    @State private var voci: [JScadenza] = []
    @State private var caricato = false
    @AppStorage("scadenze.promemoria") private var promemoria = false

    var gruppi: [(String, [JScadenza], Color)] {
        [("Scaduto", voci.filter { ($0.giorni ?? 1) < 0 }, Theme.red),
         ("Entro 30 giorni", voci.filter { if let g = $0.giorni { return g >= 0 && g <= 30 }; return false }, Theme.amber),
         ("Più avanti", voci.filter { ($0.giorni ?? -1) > 30 }, Theme.olive),
         ("Da sistemare", voci.filter { $0.giorni == nil }, Theme.cyan)].filter { !$0.1.isEmpty }
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: $promemoria) { Label("Promemoria sul telefono", systemImage: "bell.badge.fill") }
                    .tint(Theme.olive)
                    .onChange(of: promemoria) { on in if on { programma() } else { UNUserNotificationCenter.current().removeAllPendingNotificationRequests() } }
                if PermessiStore.shared.gestione {
                    NavigationLink { AdempimentiView() } label: { Label("Adempimenti dell'associazione", systemImage: "calendar.badge.clock") }
                }
            } footer: { Text("Avviso una settimana prima e il giorno della scadenza.") }
            .listRowBackground(Theme.surface)
            if caricato && voci.isEmpty {
                Section { Label("Tutto in regola", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.green) }.listRowBackground(Theme.surface)
            }
            ForEach(gruppi, id: \.0) { g in
                Section {
                    ForEach(Array(g.1.enumerated()), id: \.element.id) { i, v in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: icona(v.tipo)).foregroundStyle(g.2).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(v.titolo).font(.system(size: 14.5, weight: .semibold))
                                if let t = v.testo, !t.isEmpty { Text(t).font(.caption).foregroundStyle(Theme.dim) }
                            }
                            Spacer()
                            if let d = v.data {
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(dataIta(d)).font(Theme.mono(12, .bold))
                                    if let gg = v.giorni { Text(gg < 0 ? "\(-gg) gg fa" : (gg == 0 ? "oggi" : "tra \(gg) gg")).font(.caption2).foregroundStyle(g.2) }
                                }
                            }
                        }
                        .comparsa(i)
                    }
                } header: { Text("\(g.0) · \(g.1.count)") }
                .listRowBackground(Theme.surface)
            }
        }
        .scrollContentBackground(.hidden).background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Scadenzario")
        .task { await carica() }
        .refreshable { await carica() }
    }

    func icona(_ t: String) -> String {
        ["certificato": "cross.case.fill", "quota": "eurosign.circle.fill", "figt": "shield.lefthalf.filled", "domanda": "person.badge.plus",
         "adempimento": "calendar.badge.exclamationmark", "prestito": "shippingbox.fill"][t] ?? "clock"
    }

    func carica() async {
        voci = (try? await jsoc.get("/api/scadenzario")) ?? []
        caricato = true
        if promemoria { programma() }
    }

    func programma() {
        let c = UNUserNotificationCenter.current()
        c.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
            guard ok else { return }
            c.removeAllPendingNotificationRequests()
            for v in voci {
                guard let d = v.data, let g = v.giorni, g >= 0, let giorno = ISO8601DateFormatter.soloData(d) else { continue }
                for anticipo in [7, 0] where g >= anticipo {
                    guard let quando = Calendar.current.date(byAdding: .day, value: -anticipo, to: giorno) else { continue }
                    var comp = Calendar.current.dateComponents([.year, .month, .day], from: quando); comp.hour = 9
                    let n = UNMutableNotificationContent()
                    n.title = anticipo == 0 ? "Scade oggi" : "Scade tra \(anticipo) giorni"
                    n.body = v.titolo
                    n.sound = .default
                    c.add(UNNotificationRequest(identifier: "scad-\(v.id)-\(anticipo)", content: n,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: comp, repeats: false)))
                }
            }
        }
    }
}

struct AdempimentiView: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @State private var lista: [JAdempimento] = []
    @State private var modifica: JAdempimento?
    @State private var nuovo = false
    let anno = String(Calendar.current.component(.year, from: Date()))

    var body: some View {
        List {
            Section { Text("Scadenze fisse di ogni anno. Spunta quando l'hai fatta: sparisce dallo scadenzario fino all'anno dopo.").font(.footnote).foregroundStyle(Theme.dim) }
                .listRowBackground(Color.clear)
            ForEach(lista) { a in
                HStack {
                    Button { segna(a) } label: {
                        Image(systemName: a.fatto[anno] != nil ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(a.fatto[anno] != nil ? Theme.green : Theme.dim)
                    }
                    .buttonStyle(.borderless)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.titolo).font(.system(size: 14.5, weight: .semibold))
                        Text("entro il \(a.scadenza.split(separator: "-").reversed().joined(separator: "/"))" + ((a.note ?? "").isEmpty ? "" : " · \(a.note ?? "")"))
                            .font(.caption).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    Button { modifica = a } label: { Image(systemName: "pencil") }.buttonStyle(.borderless)
                }
                .swipeActions { Button(role: .destructive) { elimina(a) } label: { Label("Elimina", systemImage: "trash") } }
                .listRowBackground(Theme.surface)
            }
        }
        .scrollContentBackground(.hidden).background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Adempimenti")
        .toolbar { Button { nuovo = true } label: { Image(systemName: "plus.circle.fill") } }
        .task { lista = (try? await jsoc.get("/api/adempimenti")) ?? [] }
        .sheet(isPresented: $nuovo) { AdempimentoSheet(a: nil) { lista = $0 } }
        .sheet(item: $modifica) { a in AdempimentoSheet(a: a) { lista = $0 } }
    }

    func segna(_ a: JAdempimento) {
        haptic()
        Task { if let r: [JAdempimento] = try? await jsoc.send("/api/adempimenti/\(a.id)/fatto", "POST", ["anno": Int(anno) ?? 0, "fatto": a.fatto[anno] == nil]) { withAnimation { lista = r } } }
    }
    func elimina(_ a: JAdempimento) { Task { if let r: [JAdempimento] = try? await jsoc.send("/api/adempimenti/\(a.id)", "DELETE", [String: Any]()) { lista = r } } }
}

struct AdempimentoSheet: View {
    let a: JAdempimento?
    var fatto: ([JAdempimento]) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var titolo = ""
    @State private var data = Date()
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Cosa fare", text: $titolo)
                DatePicker("Entro il (ogni anno)", selection: $data, displayedComponents: .date)
                TextField("Note", text: $note)
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle(a == nil ? "Nuovo adempimento" : "Modifica").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        let mmdd = String(oraISO(data).suffix(5))
                        Task {
                            let r: [JAdempimento]? = try? await JsocClient.shared.send(a.map { "/api/adempimenti/\($0.id)" } ?? "/api/adempimenti", a == nil ? "POST" : "PUT",
                                                                                         ["titolo": titolo, "scadenza": mmdd, "note": note])
                            if let r { fatto(r) }
                            dismiss()
                        }
                    }
                    .disabled(titolo.isEmpty)
                }
            }
            .onAppear {
                guard let a else { return }
                titolo = a.titolo; note = a.note ?? ""
                if let d = ISO8601DateFormatter.soloData("\(Calendar.current.component(.year, from: Date()))-\(a.scadenza)") { data = d }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Riunioni del Consiglio Direttivo e verbali

struct RiunioniView: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var doc = DocAssoc.shared
    @State private var dati: JRiunioni?
    @State private var apri: JRiunione?
    @State private var nuova = false
    @State private var anteprima: DocumentoPronto?

    var body: some View {
        List {
            Section { Text("Ordine del giorno, presenti, delibere con i voti: alla chiusura l'app scrive il verbale numerato e lo salva nei documenti.").font(.footnote).foregroundStyle(Theme.dim) }
                .listRowBackground(Color.clear)
            ForEach(Array((dati?.riunioni ?? []).enumerated()), id: \.element.id) { i, r in
                Button { if r.stato == "chiusa" { pdf(r) } else { apri = r } } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.numero.map { "Verbale n. \($0)" } ?? "Riunione in preparazione").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                            Text("\(dataIta(r.data)) · \(r.odg.count) punti · \(r.delibere.count) delibere").font(.caption).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        Etichetta(testo: r.stato == "chiusa" ? "CHIUSO" : "BOZZA", colore: r.stato == "chiusa" ? Theme.green : Theme.amber)
                    }
                }
                .comparsa(i)
                .listRowBackground(Theme.surface)
            }
        }
        .scrollContentBackground(.hidden).background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Consiglio Direttivo")
        .toolbar { Button { nuova = true } label: { Image(systemName: "plus.circle.fill") } }
        .task { await doc.carica(); await carica() }
        .refreshable { await carica() }
        .sheet(isPresented: $nuova) { RiunioneEditor(riunione: nil, membri: dati?.membri ?? []) { dati = $0 } }
        .sheet(item: $apri) { r in RiunioneEditor(riunione: r, membri: dati?.membri ?? []) { dati = $0 } }
        .sheet(item: $anteprima) { AnteprimaPDF(doc: $0) }
    }

    func carica() async { dati = try? await jsoc.get("/api/riunioni") }

    func pdf(_ r: JRiunione) {
        let d = RiunioneEditor.documento(r, membri: dati?.membri ?? [], doc: doc)
        anteprima = DocumentoPronto(titolo: "Verbale CD \(dataIta(r.data))", dati: d, salva: { try await caricaPDF("/api/riunioni/\(r.id)/pdf", d) })
    }
}

struct RiunioneEditor: View {
    let riunione: JRiunione?
    let membri: [JMembroCD]
    var fatto: (JRiunioni) -> Void
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var doc = DocAssoc.shared
    @State private var data = Date()
    @State private var ora = Date()
    @State private var luogo = ""
    @State private var odg: [String] = []
    @State private var nuovoPunto = ""
    @State private var presenti: Set<Int> = []
    @State private var delibere: [JDelibera] = []
    @State private var varie = ""
    @State private var errore: String?
    @State private var chiudi = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Quando e dove") {
                    DatePicker("Data", selection: $data, displayedComponents: .date)
                    DatePicker("Ora", selection: $ora, displayedComponents: .hourAndMinute)
                    TextField("Luogo (es. sede, online)", text: $luogo)
                }
                Section("Ordine del giorno") {
                    ForEach(Array(odg.enumerated()), id: \.offset) { i, p in Text("\(i + 1). \(p)") }
                        .onDelete { odg.remove(atOffsets: $0) }
                    HStack { TextField("Nuovo punto", text: $nuovoPunto); Button("Aggiungi") { if !nuovoPunto.isEmpty { odg.append(nuovoPunto); nuovoPunto = "" } } }
                }
                Section("Presenti") {
                    ForEach(membri) { m in
                        Button {
                            if presenti.contains(m.id) { presenti.remove(m.id) } else { presenti.insert(m.id) }
                        } label: {
                            HStack {
                                Text("\(m.callsign) · \(m.nome ?? "")").foregroundStyle(.white)
                                if let c = m.carica, !c.isEmpty { Text(NomiAssoc.carica(c)).font(.caption).foregroundStyle(Theme.dim) }
                                Spacer()
                                Image(systemName: presenti.contains(m.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(presenti.contains(m.id) ? Theme.green : Theme.dim)
                            }
                        }
                    }
                }
                Section("Delibere") {
                    ForEach(delibere.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Testo della delibera", text: $delibere[i].testo, axis: .vertical)
                            Picker("Esito", selection: $delibere[i].esito) { Text("Approvata").tag("approvata"); Text("Respinta").tag("respinta") }.pickerStyle(.segmented)
                            Stepper("Favorevoli: \(delibere[i].favorevoli)", value: $delibere[i].favorevoli, in: 0...50)
                            Stepper("Contrari: \(delibere[i].contrari)", value: $delibere[i].contrari, in: 0...50)
                            Stepper("Astenuti: \(delibere[i].astenuti)", value: $delibere[i].astenuti, in: 0...50)
                        }
                    }
                    .onDelete { delibere.remove(atOffsets: $0) }
                    Button { delibere.append(JDelibera(testo: "", esito: "approvata", favorevoli: presenti.count, contrari: 0, astenuti: 0)) } label: { Label("Aggiungi delibera", systemImage: "plus") }
                }
                Section("Varie ed eventuali") { TextField("Altro discusso", text: $varie, axis: .vertical).lineLimit(2...8) }
                if let errore { Section { Text(errore).foregroundStyle(Theme.red) } }
                if riunione != nil {
                    Section { Button { chiudi = true } label: { Label("Chiudi e firma il verbale", systemImage: "signature") } }
                        footer: { Text("Dopo la chiusura il verbale prende il numero progressivo e non si modifica più.") }
                }
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle(riunione == nil ? "Nuova riunione" : "Riunione").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salva") { salva(poi: false) } }
            }
            .confirmationDialog("Chiudere il verbale?", isPresented: $chiudi, titleVisibility: .visible) {
                Button("Chiudi e salva il PDF") { salva(poi: true) }
            }
            .onAppear {
                guard let r = riunione else { presenti = Set(membri.map(\.id)); return }
                if let d = ISO8601DateFormatter.soloData(r.data ?? "") { data = d }
                if let o = r.ora, o.count == 5, let h = Int(o.prefix(2)), let mi = Int(o.suffix(2)) { ora = Calendar.current.date(bySettingHour: h, minute: mi, second: 0, of: Date()) ?? ora }
                luogo = r.luogo ?? ""; odg = r.odg; presenti = Set(r.presenti); delibere = r.delibere; varie = r.varie ?? ""
            }
        }
    }

    var corpo: [String: Any] {
        ["data": oraISO(data), "ora": oraHHmm(ora), "luogo": luogo, "odg": odg, "presenti": Array(presenti),
         "delibere": delibere.map { ["testo": $0.testo, "esito": $0.esito, "favorevoli": $0.favorevoli, "contrari": $0.contrari, "astenuti": $0.astenuti] }, "varie": varie]
    }

    func salva(poi chiudere: Bool) {
        Task {
            do {
                var r: JRiunioni = try await JsocClient.shared.send(riunione.map { "/api/riunioni/\($0.id)" } ?? "/api/riunioni", riunione == nil ? "POST" : "PUT", corpo)
                if chiudere, let id = riunione?.id {
                    r = try await JsocClient.shared.send("/api/riunioni/\(id)/chiudi", "POST", [String: Any]())
                    if let chiusa = r.riunioni.first(where: { $0.id == id }) {
                        try? await caricaPDF("/api/riunioni/\(id)/pdf", Self.documento(chiusa, membri: membri, doc: doc))
                    }
                }
                fatto(r); dismiss()
            } catch { errore = error.localizedDescription }
        }
    }

    @MainActor static func documento(_ r: JRiunione, membri: [JMembroCD], doc: DocAssoc) -> Data {
        let nome: (JMembroCD) -> String = { m in "\(m.nome ?? m.callsign)" + ((m.carica ?? "").isEmpty ? "" : " (\(NomiAssoc.carica(m.carica ?? "")))") }
        let dati = ModelliPDF.DatiRiunione(numero: r.numero, data: r.data ?? oggiISO(), ora: r.ora ?? "", luogo: r.luogo ?? "", odg: r.odg,
                                           presenti: membri.filter { r.presenti.contains($0.id) }.map(nome),
                                           assenti: membri.filter { !r.presenti.contains($0.id) }.map(nome),
                                           delibere: r.delibere.map { (testo: $0.testo, esito: $0.esito, fav: $0.favorevoli, con: $0.contrari, ast: $0.astenuti) },
                                           varie: r.varie ?? "")
        return ModelliPDF.verbaleDirettivo(dati, firma: doc.firmaPresidente, intest: doc.intest, loghi: doc.loghi)
    }
}

// MARK: - Stampe ufficiali

struct StampeView: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var doc = DocAssoc.shared
    @State private var anno = Calendar.current.component(.year, from: Date())
    @State private var anteprima: DocumentoPronto?
    @State private var errore: String?
    @State private var lavoro: String?
    @State private var assemblee: [JAssemblea] = []
    @State private var soci: [JProfilo] = []

    var body: some View {
        List {
            Section {
                Picker("Anno", selection: $anno) { ForEach((2019...Calendar.current.component(.year, from: Date()) + 1).reversed(), id: \.self) { Text(String($0)).tag($0) } }
            }
            .listRowBackground(Theme.surface)
            Section("Registri") {
                voce("books.vertical.fill", "Libro dei soci", "stampe") { ModelliPDF.libroSoci(try await jsoc.libroSoci(), intest: doc.intest, loghi: doc.loghi) }
                voce("person.text.rectangle.fill", "Elenco tesserati \(anno)", "stampe") { ModelliPDF.tesserati(try await jsoc.tesseramento(anno), intest: doc.intest, loghi: doc.loghi) }
                voce("checklist", "Registro presenze \(anno)", "stampe") { ModelliPDF.registro(try await jsoc.registroPresenze(anno), intest: doc.intest, loghi: doc.loghi) }
                voce("eurosign.circle.fill", "Rendiconto \(anno)", "stampe") { ModelliPDF.rendiconto(try await jsoc.rendiconto(anno), firma: doc.firmaPresidente, intest: doc.intest, loghi: doc.loghi) }
            }
            .listRowBackground(Theme.surface)
            if !assemblee.isEmpty {
                Section("Assemblee") {
                    ForEach(assemblee) { a in
                        voce("envelope.open.fill", "Convocazione · \(a.titolo)", "convocazioni") { ModelliPDF.convocazione(a, firma: doc.firmaPresidente, intest: doc.intest, loghi: doc.loghi) }
                        if !(a.verbale ?? "").isEmpty {
                            voce("doc.text.fill", "Verbale · \(a.titolo)", "assemblee") { ModelliPDF.verbaleAssemblea(a, firma: doc.firmaPresidente, intest: doc.intest, loghi: doc.loghi) }
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            }
            if !soci.isEmpty {
                Section("Attestato di iscrizione") {
                    ForEach(soci) { s in
                        voce("rosette", "\(s.callsign) · \(s.nome)", "stampe") {
                            ModelliPDF.attestato(nome: s.nome, callsign: s.callsign, nascita: s.nascita, luogo: s.luogo_nascita, anno: anno,
                                                 quotaPagata: (s.quota_pagata ?? 0) != 0, firma: doc.firmaPresidente, intest: doc.intest, loghi: doc.loghi)
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            }
            if let errore { Text(errore).foregroundStyle(Theme.red) }
        }
        .scrollContentBackground(.hidden).background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Stampe e documenti")
        .task {
            await doc.carica()
            assemblee = (try? await jsoc.assemblee()) ?? []
            soci = ((try? await jsoc.soci())?.soci ?? []).filter { ($0.attivo ?? 1) == 1 }
        }
        .sheet(item: $anteprima) { AnteprimaPDF(doc: $0) }
    }

    func voce(_ icona: String, _ titolo: String, _ cartella: String, _ crea: @escaping () async throws -> Data) -> some View {
        Button {
            lavoro = titolo
            Task {
                do {
                    let d = try await crea()
                    let nome = titolo.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "·", with: "-")
                    anteprima = DocumentoPronto(titolo: nome, dati: d, salva: {
                        let n = (nome + ".pdf").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "documento.pdf"
                        try await caricaPDF("/api/associazione/stampe/\(cartella)?nome=\(n)", d)
                    })
                    errore = nil
                } catch { errore = error.localizedDescription }
                lavoro = nil
            }
        } label: {
            HStack {
                Image(systemName: icona).foregroundStyle(Theme.oliveBright).frame(width: 26)
                Text(titolo).foregroundStyle(.white).lineLimit(1)
                Spacer()
                if lavoro == titolo { ProgressView() } else { Image(systemName: "doc.badge.arrow.up").foregroundStyle(Theme.dim) }
            }
        }
    }
}

// MARK: - Prestiti del materiale

struct PrestitiView: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var perm = PermessiStore.shared
    @State private var prestiti: [JPrestito] = []
    @State private var nuovo = false
    @State private var errore: String?

    var body: some View {
        List {
            let attivi = prestiti.filter { $0.reso == nil }, resi = prestiti.filter { $0.reso != nil }
            if prestiti.isEmpty { Text("Nessun prestito.").foregroundStyle(Theme.dim).listRowBackground(Theme.surface) }
            if !attivi.isEmpty {
                Section("In prestito · \(attivi.count)") { ForEach(attivi) { riga($0) } }.listRowBackground(Theme.surface)
            }
            if !resi.isEmpty {
                Section("Restituiti") { ForEach(resi.prefix(40)) { riga($0) } }.listRowBackground(Theme.surface)
            }
            if let errore { Text(errore).foregroundStyle(Theme.red) }
        }
        .scrollContentBackground(.hidden).background(Theme.bg.ignoresSafeArea())
        .navigationTitle(perm.puo("magazzino") ? "Prestiti del materiale" : "Il materiale che ho")
        .toolbar { if perm.puo("magazzino") { Button { nuovo = true } label: { Image(systemName: "plus.circle.fill") } } }
        .task { await carica() }
        .refreshable { await carica() }
        .sheet(isPresented: $nuovo) { NuovoPrestitoSheet { prestiti = $0 } }
    }

    func riga(_ p: JPrestito) -> some View {
        let scaduto = p.reso == nil && (giorniA(p.al) ?? 1) < 0
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(p.materiale_nome + ((p.quantita ?? 1) > 1 ? " ×\(Int(p.quantita ?? 1))" : "")).font(.system(size: 14.5, weight: .semibold))
                Text("\(p.callsign) · dal \(dataIta(p.dal))" + ((p.al ?? "").isEmpty ? "" : " al \(dataIta(p.al))") + (p.reso.map { " · reso \(dataIta($0))" } ?? ""))
                    .font(.caption).foregroundStyle(scaduto ? Theme.red : Theme.dim)
            }
            Spacer()
            if scaduto { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.red) }
        }
        .swipeActions {
            if perm.puo("magazzino") {
                if p.reso == nil { Button { azione("/api/prestiti/\(p.id)/rientro", "POST") } label: { Label("Rientrato", systemImage: "arrow.uturn.backward") }.tint(Theme.green) }
                Button(role: .destructive) { azione("/api/prestiti/\(p.id)", "DELETE") } label: { Label("Elimina", systemImage: "trash") }
            }
        }
    }

    func carica() async { prestiti = (try? await jsoc.get("/api/prestiti")) ?? [] }
    func azione(_ path: String, _ metodo: String) {
        Task {
            do { prestiti = try await jsoc.send(path, metodo, [String: Any]()) } catch { errore = error.localizedDescription }
        }
    }
}

struct NuovoPrestitoSheet: View {
    var fatto: ([JPrestito]) -> Void
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var jsoc = JsocClient.shared
    @State private var materiale: [JMateriale] = []
    @State private var soci: [JProfilo] = []
    @State private var mat: Int?
    @State private var socio: Int?
    @State private var quantita = 1
    @State private var conRientro = true
    @State private var al = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    @State private var note = ""
    @State private var errore: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Materiale", selection: $mat) {
                    Text("Scegli…").tag(Int?.none)
                    ForEach(materiale) { m in Text(m.nome).tag(Int?.some(m.id)) }
                }
                Picker("Socio", selection: $socio) {
                    Text("Scegli…").tag(Int?.none)
                    ForEach(soci) { s in Text("\(s.callsign) · \(s.nome)").tag(Int?.some(s.id)) }
                }
                Stepper("Quantità: \(quantita)", value: $quantita, in: 1...50)
                Toggle("Data di rientro", isOn: $conRientro)
                if conRientro { DatePicker("Entro il", selection: $al, displayedComponents: .date) }
                TextField("Note (stato, accessori)", text: $note)
                if let errore { Text(errore).foregroundStyle(Theme.red) }
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("Nuovo prestito").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Presta") {
                        Task {
                            do {
                                let r: [JPrestito] = try await jsoc.send("/api/prestiti", "POST", ["materiale": mat ?? 0, "utente": socio ?? 0, "quantita": quantita,
                                                                                                    "al": conRientro ? oraISO(al) : "", "note": note])
                                fatto(r); dismiss()
                            } catch { errore = error.localizedDescription }
                        }
                    }
                    .disabled(mat == nil || socio == nil)
                }
            }
            .task {
                materiale = (try? await jsoc.materiale()) ?? []
                soci = ((try? await jsoc.soci())?.soci ?? []).filter { ($0.attivo ?? 1) == 1 }
            }
        }
    }
}

// MARK: - Assicurazione e infortuni

struct AssicurazioneView: View {
    @ObservedObject private var doc = DocAssoc.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Card(title: "Copertura", icon: "shield.lefthalf.filled") {
                    Text("Ogni socio è assicurato tramite il tesseramento \(doc.intest.affiliazioni ?? "F.I.G.T."): la copertura è attiva solo dopo che il direttivo ha caricato il nominativo sull'Intranet FIGT (vedi Tesseramento).")
                        .font(.system(size: 13.5))
                    if let p = doc.intest.polizza, !p.isEmpty { Text(p).font(.system(size: 13.5)).foregroundStyle(Theme.oliveBright) }
                    if let l = doc.intest.polizza_link, let u = URL(string: l), !l.isEmpty {
                        Link(destination: u) { Label("Polizze e moduli sul sito FIGT", systemImage: "safari") }.tint(Theme.olive)
                    }
                }
                .comparsa(0)
                Card(title: "In caso di infortunio", icon: "cross.case.fill") {
                    passo(1, "Metti in sicurezza e presta soccorso; se serve chiama il 112/118. Ferma il gioco con il segnale convenuto.")
                    passo(2, "Avvisa subito il responsabile dell'evento e un membro del direttivo.")
                    passo(3, "Fatti refertare (pronto soccorso o medico): il referto con data e diagnosi è indispensabile.")
                    passo(4, "Annota luogo, ora, dinamica e testimoni (anche con una nota o una foto nell'app, nella chat dell'evento).")
                    passo(5, "La denuncia va fatta entro i termini indicati nella polizza (di solito pochi giorni) con il modulo FIGT: il direttivo ti aiuta a compilarla.")
                    passo(6, "Conserva ricevute di spese mediche, farmaci e trasporti: servono per il rimborso.")
                    Text("I termini esatti e i massimali sono quelli della polizza in vigore: controllali sul sito FIGT.").font(.caption).foregroundStyle(Theme.dim)
                }
                .comparsa(1)
            }
            .padding(16).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Assicurazione")
        .task { await doc.carica() }
    }

    func passo(_ n: Int, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(Theme.mono(12, .heavy)).foregroundStyle(.black).frame(width: 22, height: 22).background(Theme.red, in: Circle())
            Text(t).font(.system(size: 13.5)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Dati dell'associazione (carta intestata) e firma del presidente

struct IntestazioneView: View {
    @ObservedObject private var doc = DocAssoc.shared
    @ObservedObject private var perm = PermessiStore.shared
    @State private var i = JIntestazione()
    @State private var quota = ""
    @State private var tratti: [[CGPoint]] = []
    @State private var avviso: String?
    @State private var anteprima: DocumentoPronto?

    var presidente: Bool { ["presidente", "vicepresidente"].contains(perm.p?.carica ?? "") || (JsocClient.shared.utente?.direttivo == true && (perm.p?.carica ?? "").isEmpty) }

    var body: some View {
        Form {
            Section("Associazione") {
                campo("Nome", \.nome); campo("Sottotitolo", \.sottotitolo); campo("Codice fiscale", \.cf); campo("Affiliazioni", \.affiliazioni)
                Stepper("Anno associativo: \(String(i.anno ?? doc.intest.annoAssociativo))", value: Binding(get: { i.anno ?? doc.intest.annoAssociativo }, set: { i.anno = $0 }), in: 2020...2100)
            }
            Section("Sede e contatti (piè di pagina)") {
                campo("Indirizzo", \.indirizzo); campo("CAP, città (prov.)", \.citta); campo("Telefono / fax", \.telefono); campo("Cellulare", \.cellulare)
                campo("E-mail", \.email); campo("PEC", \.pec); campo("IBAN", \.iban)
            }
            Section("Iscrizione") {
                TextField("Quota annuale €", text: $quota).keyboardType(.decimalPad)
                campo("Certificato richiesto", \.certificato)
                Stepper("Giorni per consegnarlo: \(i.giorni_certificato ?? 15)", value: Binding(get: { i.giorni_certificato ?? 15 }, set: { i.giorni_certificato = $0 }), in: 1...90)
                campo("Presidente (nome)", \.presidente)
            }
            Section("Assicurazione") { campo("Polizza: compagnia, numero, massimali", \.polizza); campo("Link polizza", \.polizza_link) }
            Section {
                Button { salva() } label: { Label("Salva i dati", systemImage: "tray.and.arrow.down.fill") }
                Button { anteprima = DocumentoPronto(titolo: "Prova carta intestata", dati: ModelliPDF.attestato(nome: "Nome Cognome", callsign: "CALLSIGN", nascita: nil, luogo: nil, anno: i.annoAssociativo, quotaPagata: true, firma: doc.firmaPresidente, intest: i, loghi: doc.loghi)) } label: { Label("Prova la carta intestata", systemImage: "doc.richtext") }
                if let avviso { Text(avviso).foregroundStyle(Theme.oliveBright) }
            }
            if presidente {
                Section {
                    if let f = doc.firmaPresidente { Image(uiImage: f).resizable().scaledToFit().frame(height: 60).padding(6).background(Color.white, in: RoundedRectangle(cornerRadius: 8)) }
                    FirmaPad(tratti: $tratti).listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    Button { salvaFirma() } label: { Label("Salva la mia firma", systemImage: "signature") }.disabled(tratti.isEmpty)
                } header: { Text("Firma del presidente") } footer: { Text("Viene messa in automatico su ricevute, domande accettate, verbali e attestati. La vede solo il direttivo.") }
            }
        }
        .scrollContentBackground(.hidden).background(Theme.bg)
        .navigationTitle("Dati dell'associazione")
        .task { await doc.carica(forza: true); i = doc.intest; quota = euroTesto(i.quota ?? 50) }
        .sheet(item: $anteprima) { AnteprimaPDF(doc: $0) }
    }

    func campo(_ t: String, _ k: WritableKeyPath<JIntestazione, String?>) -> some View {
        TextField(t, text: Binding(get: { i[keyPath: k] ?? "" }, set: { i[keyPath: k] = $0 }))
    }

    func salva() {
        i.quota = Double(quota.replacingOccurrences(of: ",", with: ".")) ?? i.quota
        var b: [String: Any] = [:]
        if let d = try? JSONEncoder().encode(i), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { b = o }
        Task {
            do { let r: JIntestazione = try await JsocClient.shared.send("/api/associazione/intestazione", "PUT", b); doc.intest = r; avviso = "Salvato" }
            catch { avviso = error.localizedDescription }
        }
    }

    func salvaFirma() {
        guard let png = FirmaPad.immagine(tratti)?.pngData() else { return }
        Task {
            do { try await JsocClient.shared.caricaDati("/api/associazione/firma-presidente", dati: png); await doc.carica(forza: true); tratti = []; avviso = "Firma salvata" }
            catch { avviso = error.localizedDescription }
        }
    }
}
