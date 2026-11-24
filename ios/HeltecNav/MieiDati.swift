import SwiftUI
import MapKit
import ContactsUI
import UniformTypeIdentifiers

// MARK: - I miei dati (tavole 33-34) e Salute (tavole 35-36), senza scorrere, campi automatici.

// MARK: pezzi dei moduli della tela

/// etichetta sopra il campo: 11 pt, maiuscolo, grigio
struct EtichettaCampo: View {
    let testo: String
    var destra: String? = nil
    var azioneDestra: (() -> Void)? = nil
    var body: some View {
        HStack {
            Text(testo.uppercased()).font(.system(size: 11, weight: .heavy)).tracking(0.44).foregroundStyle(Theme.dim)
            Spacer()
            if let destra {
                Button(destra) { azioneDestra?() }.font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.oliveBright)
            }
        }
        .padding(.horizontal, 2)
    }
}

/// riquadro del campo: alto 46, angoli 12; "auto" = compilato dall'app (fondo più scuro, testo grigio)
struct RiquadroCampo<C: View>: View {
    var attivo = false
    var auto = false
    @ViewBuilder var contenuto: () -> C
    var body: some View {
        HStack(spacing: 8) { contenuto() }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(auto ? Color(hex: 0x11150D) : Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(attivo ? Theme.olive : Theme.stroke))
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(attivo ? Theme.olive.opacity(0.18) : .clear).padding(-3))
    }
}

/// nota sotto il campo: 10,5 pt
struct NotaCampo: View {
    let testo: String
    var colore: Color = Theme.dim
    var icona: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let icona { IconaTela(d: icona, colore: colore, lato: 12) }
            Text(testo).font(.system(size: 10.5, weight: .bold)).foregroundStyle(colore)
        }
        .padding(.horizontal, 2).padding(.top, 4)
    }
}

/// campo di testo della tela
struct CampoTesto: View {
    let etichetta: String
    @Binding var testo: String
    var icona: String? = nil
    var tastiera: UIKeyboardType = .default
    var maiuscole: TextInputAutocapitalization = .words
    var mono = false
    var auto = false
    @FocusState private var fuoco: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            EtichettaCampo(testo: etichetta)
            RiquadroCampo(attivo: fuoco, auto: auto) {
                TextField("", text: $testo)
                    .font(mono ? Theme.mono(15, .semibold) : .system(size: 15, weight: .semibold))
                    .foregroundStyle(auto ? Theme.testo2 : Theme.testo)
                    .keyboardType(tastiera).textInputAutocapitalization(maiuscole).autocorrectionDisabled()
                    .focused($fuoco)
                if let icona { IconaTela(d: icona, colore: Theme.dim, lato: 18) }
            }
        }
    }
}

/// due o più scelte a tocco: fondo #1a2013, scelta piena verde (tavola: SESSO, TIPO)
struct SceltaTela: View {
    let voci: [String]
    @Binding var scelta: Int
    var body: some View {
        HStack(spacing: 0) {
            ForEach(voci.indices, id: \.self) { i in
                Button { haptic(.soft); scelta = i } label: {
                    Text(voci[i]).font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(i == scelta ? Theme.scuro : Theme.testo2)
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .background(i == scelta ? Theme.olive : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke))
    }
}

/// schede in alto (Anagrafica / Contatti e residenza): scelta chiara su fondo #151a10
struct SchedeTela: View {
    let voci: [String]
    @Binding var scelta: Int
    var body: some View {
        HStack(spacing: 0) {
            ForEach(voci.indices, id: \.self) { i in
                Button { haptic(.soft); withAnimation(.easeOut(duration: 0.15)) { scelta = i } } label: {
                    Text(voci[i]).font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(i == scelta ? Theme.scuro : Theme.testo2)
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .background(i == scelta ? Theme.testo : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.stroke))
    }
}

/// intestazione dei moduli: indietro, titolo 24, "Salva" verde
struct IntestazioneModulo: View {
    let titolo: String
    var salvato = false
    let salva: () -> Void
    @Environment(\.dismiss) private var chiudi
    var body: some View {
        HStack(spacing: 8) {
            Button { chiudi() } label: {
                IconaTela(d: Ic.indietro, colore: Theme.testo, lato: 18)
                    .frame(width: 42, height: 42).background(Theme.surface, in: Circle()).overlay(Circle().strokeBorder(Theme.stroke))
            }
            .accessibilityLabel("Indietro")
            Text(titolo).font(.system(size: 24, weight: .black)).foregroundStyle(Theme.testo)
            Spacer()
            Button(action: salva) {
                Text(salvato ? "Salvato ✓" : "Salva").font(.system(size: 13.5, weight: .black)).foregroundStyle(Theme.scuro)
                    .padding(.horizontal, 14).frame(height: 36)
                    .background(Theme.olive, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
        }
        .padding(.horizontal, 14).padding(.top, 7)
    }
}

// MARK: comuni italiani (ISTAT) e codice fiscale

enum ComuniIT {
    struct Comune: Hashable { let nome: String; let sigla: String; let catastale: String; let cap: String }
    /// ordinati per popolazione: i suggerimenti propongono prima i comuni grandi
    static let tutti: [Comune] = {
        guard let u = Bundle.main.url(forResource: "comuni", withExtension: "json"), let d = try? Data(contentsOf: u),
              let a = try? JSONSerialization.jsonObject(with: d) as? [[String]] else { return [] }
        return a.compactMap { $0.count >= 4 ? Comune(nome: $0[0], sigla: $0[1], catastale: $0[2], cap: $0[3]) : nil }
    }()

    static func cerca(_ t: String, max: Int = 4) -> [Comune] {
        let q = t.trimmingCharacters(in: .whitespaces).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard q.count >= 2 else { return [] }
        var inizio: [Comune] = []
        for c in tutti where c.nome.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).hasPrefix(q) {
            inizio.append(c); if inizio.count >= max { break }
        }
        return inizio
    }

    static func trova(_ nome: String?, sigla: String? = nil) -> Comune? {
        guard let n = nome?.trimmingCharacters(in: .whitespaces), !n.isEmpty else { return nil }
        return tutti.first { $0.nome.caseInsensitiveCompare(n) == .orderedSame && (sigla == nil || sigla!.isEmpty || $0.sigla == sigla) }
    }
}

enum CodiceFiscale {
    private static func lettere(_ s: String) -> [Character] {
        Array(s.folding(options: [.diacriticInsensitive], locale: .current).uppercased().filter { $0.isLetter && $0.isASCII })
    }
    private static func vocale(_ c: Character) -> Bool { "AEIOU".contains(c) }

    private static func parte(_ s: String, nome: Bool) -> String {
        let l = lettere(s)
        let cons = l.filter { !vocale($0) }, voc = l.filter { vocale($0) }
        if nome && cons.count >= 4 { return String([cons[0], cons[2], cons[3]]) }
        return String((cons + voc + ["X", "X", "X"]).prefix(3))
    }

    /// codice fiscale italiano (senza i casi di omocodia)
    static func calcola(nome: String, cognome: String, nascita: Date, femmina: Bool, catastale: String) -> String? {
        guard !nome.isEmpty, !cognome.isEmpty, catastale.count == 4 else { return nil }
        let cal = Calendar(identifier: .gregorian)
        let k = cal.dateComponents([.year, .month, .day], from: nascita)
        guard let y = k.year, let m = k.month, let d = k.day else { return nil }
        let mesi = Array("ABCDEHLMPRST")
        var cf = parte(cognome, nome: false) + parte(nome, nome: true)
        cf += String(format: "%02d", y % 100) + String(mesi[m - 1]) + String(format: "%02d", d + (femmina ? 40 : 0)) + catastale.uppercased()
        let dispari: [Character: Int] = ["0": 1, "1": 0, "2": 5, "3": 7, "4": 9, "5": 13, "6": 15, "7": 17, "8": 19, "9": 21,
            "A": 1, "B": 0, "C": 5, "D": 7, "E": 9, "F": 13, "G": 15, "H": 17, "I": 19, "J": 21, "K": 2, "L": 4, "M": 18, "N": 20,
            "O": 11, "P": 3, "Q": 6, "R": 8, "S": 12, "T": 14, "U": 16, "V": 10, "W": 22, "X": 25, "Y": 24, "Z": 23]
        var somma = 0
        for (i, c) in cf.enumerated() {
            if i % 2 == 0 { somma += dispari[c] ?? 0 }
            else { somma += c.isNumber ? Int(String(c))! : Int(c.asciiValue! - 65) }
        }
        return cf + String(Character(UnicodeScalar(65 + somma % 26)!))
    }
}

// MARK: - Modulo

struct MieiDatiView: View {
    var salute = false
    /// iPad: modulo nel pannello a destra del Profilo (tavola IPadProfilo13), senza "indietro", campi affiancati
    var pannello = false
    @ObservedObject private var jsoc = JsocClient.shared
    @State private var scheda = UserDefaults.standard.integer(forKey: "debug.scheda")
    @State private var salvato = false
    @State private var errore: String?
    // anagrafica
    @State private var nome = ""
    @State private var cognome = ""
    @State private var sesso = 0
    @State private var nascita = Calendar.current.date(from: DateComponents(year: 1990, month: 1, day: 1)) ?? Date()
    @State private var comune = ""
    @State private var comuneScelto: ComuniIT.Comune?
    @State private var cf = ""
    @State private var cfAMano = false
    @State private var ruotaAperta = UserDefaults.standard.string(forKey: "debug.modulo") == "dati"  // tavola 33: rotella aperta
    // contatti
    @State private var prefisso = "+39"
    @State private var telefono = ""
    @State private var email = ""
    @State private var via = ""
    @State private var cap = ""
    @State private var citta = ""
    @State private var provincia = ""
    @StateObject private var indirizzi = CompletaIndirizzi()
    // salute
    @State private var tipoCertificato = 0
    @State private var scadenza: Date?
    @State private var scegliScadenza = false
    @State private var fileCertificato = false
    @State private var fotocamera = false
    @State private var importaFile = false
    @State private var gruppo = ""
    @State private var contattoNome = ""
    @State private var contattoRelazione = "madre"
    @State private var contattoTelefono = ""
    @State private var rubrica = false
    @State private var allergie: Set<String> = []
    @State private var altraAllergia = false
    @State private var nuovaAllergia = ""
    @State private var farmaci = ""
    @State private var visibili = true

    var body: some View {
        VStack(spacing: 0) {
            if pannello { intestazionePannello } else {
                IntestazioneModulo(titolo: salute ? "Salute" : "I miei dati", salvato: salvato) { salva() }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: pannello ? 12 : 11) {
                    SchedeTela(voci: salute ? ["Certificato", "Emergenza"] : ["Anagrafica", "Contatti e residenza"], scelta: $scheda)
                    if let errore { Text(errore).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.red) }
                    if salute {
                        if scheda == 0 { certificato } else { emergenza }
                    } else {
                        if scheda == 0 { anagrafica } else { contatti }
                    }
                }
                .padding(.horizontal, pannello ? 0 : 14).padding(.top, 12).padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { if !pannello { ModuliAperti.shared.aperti += 1 } }   // tavole 33-36: senza la barra in basso
        .onDisappear { if !pannello { ModuliAperti.shared.aperti = max(0, ModuliAperti.shared.aperti - 1) } }
        .task { await carica() }
        .sheet(isPresented: $fotocamera) { CameraPicker { img in carica(img.ridotta(lato: 1800).jpegData(compressionQuality: 0.8), "image/jpeg") }.ignoresSafeArea() }
        .fileImporter(isPresented: $importaFile, allowedContentTypes: [.pdf, .image]) { r in
            if case .success(let u) = r, u.startAccessingSecurityScopedResource() {
                defer { u.stopAccessingSecurityScopedResource() }
                carica(try? Data(contentsOf: u), u.pathExtension.lowercased() == "pdf" ? "application/pdf" : "image/jpeg")
            }
        }
        .sheet(isPresented: $rubrica) { SceltaContatto { n, t in contattoNome = n; contattoTelefono = t; salvato = false } }
        .alert("Altra allergia", isPresented: $altraAllergia) {
            TextField("Scrivi", text: $nuovaAllergia)
            Button("Aggiungi") { let a = nuovaAllergia.trimmingCharacters(in: .whitespaces); if !a.isEmpty { allergie.insert(a); allergie.remove("Nessuna") }; nuovaAllergia = "" }
            Button("Annulla", role: .cancel) {}
        }
    }

    /// iPad: titolo 30 e "Salva" alto 40 (tavola IPadProfilo13)
    var intestazionePannello: some View {
        HStack(alignment: .bottom) {
            Text(salute ? "Salute" : "I miei dati").font(.system(size: 30, weight: .black)).tracking(-0.6).foregroundStyle(Theme.testo)
            Spacer()
            Button { salva() } label: {
                Text(salvato ? "Salvato ✓" : "Salva").font(.system(size: 14.5, weight: .black)).foregroundStyle(Theme.scuro)
                    .padding(.horizontal, 18).frame(height: 40)
                    .background(Theme.olive, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.top, 26)
    }

    // MARK: tavola 33 · Anagrafica (iPad: data e comune affiancati)

    var anagrafica: some View {
        VStack(alignment: .leading, spacing: pannello ? 12 : 11) {
            HStack(spacing: pannello ? 12 : 8) {
                CampoTesto(etichetta: "Nome", testo: $nome.cambia { aggiornaCF() })
                CampoTesto(etichetta: "Cognome", testo: $cognome.cambia { aggiornaCF() })
            }
            VStack(alignment: .leading, spacing: 5) {
                EtichettaCampo(testo: "Sesso")
                SceltaTela(voci: ["Maschio", "Femmina"], scelta: $sesso.cambia { aggiornaCF() })
            }
            if pannello {
                HStack(alignment: .top, spacing: 12) { campoNascita; campoComune }
                if ruotaAperta { RuotaData(data: $nascita.cambia { aggiornaCF() }) }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    campoNascita
                    if ruotaAperta {
                        RuotaData(data: $nascita.cambia { aggiornaCF() }).padding(.top, 2)
                    }
                }
                campoComune
            }
            campoCF
        }
    }

    var campoNascita: some View {
        VStack(alignment: .leading, spacing: 4) {
            EtichettaCampo(testo: "Data di nascita")
            Button { withAnimation(.easeOut(duration: 0.2)) { ruotaAperta.toggle() } } label: {
                RiquadroCampo(attivo: ruotaAperta) {
                    Text(testoNascita).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.testo).lineLimit(1)
                    Spacer()
                    IconaTela(d: Ic.calendario, colore: pannello ? Theme.olive : Theme.dim, lato: pannello ? 17 : 18)
                }
            }
            .buttonStyle(.plain)
        }
    }

    var campoComune: some View {
            VStack(alignment: .leading, spacing: 0) {
                CampoTesto(etichetta: "Comune di nascita", testo: $comune.cambia { comuneScelto = ComuniIT.trova(comune); aggiornaCF() }, icona: Ic.cerca)
                let proposte = comuneScelto == nil ? ComuniIT.cerca(comune) : []
                if !proposte.isEmpty {
                    ElencoProposte(righe: proposte.map { ("\($0.nome) (\($0.sigla))", "\($0.cap) · codice \($0.catastale)") }) { i in
                        comuneScelto = proposte[i]; comune = "\(proposte[i].nome) (\(proposte[i].sigla))"; aggiornaCF()
                    }
                }
                if !pannello { NotaCampo(testo: "Scrivi le prime lettere: ti propone i comuni") }
            }
    }

    var campoCF: some View {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    EtichettaCampo(testo: "Codice fiscale")
                    RiquadroCampo(auto: !cfAMano) {
                        TextField("", text: $cf.cambia { cfAMano = true })
                            .font(Theme.mono(15, .semibold)).foregroundStyle(cfAMano ? Theme.testo : Theme.testo2)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        IconaTela(d: Ic.bacchetta, colore: pannello ? Theme.oliveBright : Theme.dim, lato: pannello ? 17 : 18)
                    }
                }
                NotaCampo(testo: cfAMano ? "Scritto a mano · tocca la bacchetta per ricalcolare" : "Calcolato dai dati sopra · tocca per correggere",
                          colore: Theme.oliveBright, icona: Ic.spunta)
                    .onTapGesture { if cfAMano { cfAMano = false; aggiornaCF() } }
            }
    }

    var testoNascita: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "d MMMM yyyy"
        let anni = Calendar.current.dateComponents([.year], from: nascita, to: Date()).year ?? 0
        return "\(f.string(from: nascita)) · \(anni) anni"
    }

    func aggiornaCF() {
        salvato = false
        guard !cfAMano, let c = comuneScelto ?? ComuniIT.trova(comune.components(separatedBy: " (").first) else { return }
        if let x = CodiceFiscale.calcola(nome: nome, cognome: cognome, nascita: nascita, femmina: sesso == 1, catastale: c.catastale) { cf = x }
    }

    // MARK: tavola 34 · Contatti e residenza

    var telefonoValido: Bool { telefono.filter(\.isNumber).count >= (prefisso == "+39" ? 9 : 6) }
    var emailValida: Bool { email.range(of: #"^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$"#, options: .regularExpression) != nil }

    var contatti: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    EtichettaCampo(testo: "Telefono")
                    RiquadroCampo {
                        Menu {
                            ForEach([("IT", "+39"), ("SM", "+378"), ("CH", "+41"), ("FR", "+33"), ("DE", "+49"), ("ES", "+34"), ("GB", "+44"), ("US", "+1")], id: \.1) { p in
                                Button("\(p.0) \(p.1)") { prefisso = p.1; salvato = false }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("\(siglaPrefisso) \(prefisso)").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.testo)
                                IconaTela(d: Ic.giu, colore: Theme.dim, lato: 12)
                            }
                            .padding(.horizontal, 8).frame(height: 30)
                            .background(Color(hex: 0x2A3320), in: RoundedRectangle(cornerRadius: 8))
                        }
                        TextField("", text: $telefono.cambia { salvato = false }).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.testo).keyboardType(.phonePad)
                        IconaTela(d: Ic.telefono, colore: Theme.dim, lato: 18)
                    }
                }
                if !telefono.isEmpty { NotaCampo(testo: telefonoValido ? "Numero valido" : "Numero troppo corto", colore: telefonoValido ? Theme.oliveBright : Theme.amber, icona: telefonoValido ? Ic.spunta : nil) }
            }
            VStack(alignment: .leading, spacing: 0) {
                CampoTesto(etichetta: "Email", testo: $email.cambia { salvato = false }, icona: Ic.posta, tastiera: .emailAddress, maiuscole: .never)
                if !email.isEmpty { NotaCampo(testo: emailValida ? "Indirizzo valido" : "Controlla l'indirizzo", colore: emailValida ? Theme.oliveBright : Theme.amber, icona: emailValida ? Ic.spunta : nil) }
            }
            VStack(alignment: .leading, spacing: 0) {
                CampoTesto(etichetta: "Via e numero civico", testo: $via.cambia { indirizzi.cerca(via); salvato = false }, icona: Ic.cerca)
                if !indirizzi.risultati.isEmpty {
                    ElencoProposte(righe: indirizzi.risultati.prefix(3).map { ($0.title, $0.subtitle.replacingOccurrences(of: ", Italia", with: "")) }, icona: Ic.segnaposto) { i in
                        let r = indirizzi.risultati[i]
                        via = r.title
                        indirizzi.dettagli(r) { c, ci, p in cap = c; citta = ci; provincia = p }
                        indirizzi.risultati = []
                    }
                } else if Anteprima.attiva && UserDefaults.standard.string(forKey: "debug.modulo") == "dati" {
                    // solo anteprime: le proposte di Apple Mappe non si possono fingere, mostro quelle della tavola 34
                    ElencoProposte(righe: [("Via Roma 12", "73100 Lecce LE"), ("Via Roma 12", "73010 Surbo LE"), ("Viale Roma 12", "73020 Cavallino LE")], icona: Ic.segnaposto) { _ in }
                }
            }
            HStack(spacing: 8) {
                // tavola 34: CAP 100, città il resto, provincia 78
                CampoTesto(etichetta: "CAP", testo: $cap, mono: true, auto: true).frame(width: 100)
                CampoTesto(etichetta: "Città", testo: $citta, auto: true).frame(maxWidth: .infinity)
                CampoTesto(etichetta: "Prov.", testo: $provincia, maiuscole: .characters, auto: true).frame(width: 78)
            }
            HStack(spacing: 4) {
                IconaTela(d: Ic.spunta, colore: Theme.oliveBright, lato: 12)
                Text("CAP, città e provincia compilati dalla via scelta").font(.system(size: 10.5, weight: .bold)).foregroundStyle(Theme.oliveBright)
            }
            .padding(.horizontal, 2).padding(.top, -5)
        }
    }

    /// tavola 35: icona del calendario rossa quando mancano 30 giorni o meno
    var scadenzaVicina: Bool {
        guard let s = scadenza else { return false }
        return (Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: s).day ?? 0) <= 30
    }

    var siglaPrefisso: String { ["+39": "IT", "+378": "SM", "+41": "CH", "+33": "FR", "+49": "DE", "+34": "ES", "+44": "GB", "+1": "US"][prefisso] ?? "" }

    // MARK: tavola 35 · Certificato

    var certificato: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 5) {
                EtichettaCampo(testo: "Tipo")
                SceltaTela(voci: ["Non agonistico", "Agonistico"], scelta: $tipoCertificato.cambia { salvato = false })
            }
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    EtichettaCampo(testo: "Scadenza")
                    Button { scegliScadenza.toggle() } label: {
                        RiquadroCampo(attivo: scegliScadenza) {
                            Text(scadenza.map { FormatiHome.giornoLungoAnno.string(from: $0) } ?? "Scegli la data").font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(scadenza == nil ? Theme.dim : Theme.testo)
                            Spacer()
                            IconaTela(d: Ic.calendario, colore: scadenzaVicina ? Theme.red : Theme.dim, lato: 18)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if scegliScadenza {
                    DatePicker("", selection: Binding(get: { scadenza ?? Date() }, set: { scadenza = $0; salvato = false }), displayedComponents: .date)
                        .datePickerStyle(.graphical).labelsHidden().tint(Theme.olive)
                        .padding(8).background(Color(hex: 0x11150D), in: RoundedRectangle(cornerRadius: 14))
                        .padding(.top, 6)
                }
                if let s = scadenza {
                    let g = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: s).day ?? 0
                    NotaCampo(testo: g < 0 ? "Scaduto da \(-g) giorni · rinnovalo" : "Tra \(g) giorni · ti avviso 30 e 7 giorni prima",
                              colore: g <= 30 ? Theme.red : Theme.dim)
                }
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach([1.0, 0.7, 1.0, 0.5], id: \.self) { w in
                        RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xB5B19F)).frame(width: 44 * w, height: 4)
                    }
                    Spacer()
                }
                .padding(.vertical, 10).padding(.horizontal, 8)
                .frame(width: 60, height: 78, alignment: .topLeading)
                .background(Color(hex: 0xE9E6DA), in: RoundedRectangle(cornerRadius: 8))
                .opacity(fileCertificato ? 1 : 0.35)
                VStack(alignment: .leading, spacing: 3) {
                    Text(fileCertificato ? "Certificato caricato" : "Nessun certificato caricato").font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.testo)
                    Text("Il direttivo lo vede per il tesseramento FIGT.").font(.system(size: 11.5)).foregroundStyle(Theme.dim).lineSpacing(2)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke))
            HStack(spacing: 8) {
                tasto(Ic.fotocamera, "Fotografa") { fotocamera = true }
                tasto(Ic.scatola, "Da file / PDF") { importaFile = true }
            }
        }
    }

    func tasto(_ ic: String, _ t: String, _ f: @escaping () -> Void) -> some View {
        Button(action: f) {
            HStack(spacing: 7) { IconaTela(d: ic, colore: Theme.testo, lato: 16); Text(t).font(.system(size: 13, weight: .heavy)) }
                .foregroundStyle(Theme.testo)
                .frame(maxWidth: .infinity).frame(height: 46)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.olive.opacity(0.25)))
        }
        .buttonStyle(PressStyle())
    }

    // MARK: tavola 36 · Emergenza

    static let gruppi = ["A+", "A−", "B+", "B−", "AB+", "AB−", "0+", "0−"]
    static let allergieComuni = ["Nessuna", "Penicillina", "Insetti", "Lattice", "Asma", "Diabete"]

    var emergenza: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 5) {
                EtichettaCampo(testo: "Gruppo sanguigno", destra: "non lo so") { gruppo = ""; salvato = false }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
                    ForEach(Self.gruppi, id: \.self) { g in
                        let on = gruppo == g
                        Button { haptic(.soft); gruppo = g; salvato = false } label: {
                            Text(g).font(Theme.mono(12.5, .heavy)).foregroundStyle(on ? .white : Theme.testo)
                                .frame(maxWidth: .infinity).frame(height: 40)
                                .background(on ? Theme.red : Theme.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(on ? .clear : Theme.olive.opacity(0.25)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                EtichettaCampo(testo: "Contatto di emergenza")
                HStack(spacing: 10) {
                    Text(iniziali(contattoNome)).font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.testo)
                        .frame(width: 40, height: 40).background(Color(hex: 0x2A3320), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            TextField("Nome", text: $contattoNome.cambia { salvato = false }).font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.testo).fixedSize()
                            Menu {
                                ForEach(["madre", "padre", "coniuge", "compagno/a", "fratello", "sorella", "figlio/a", "amico/a", "altro"], id: \.self) { r in
                                    Button(r) { contattoRelazione = r; salvato = false }
                                }
                            } label: { Text("\(contattoRelazione) ▾").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.oliveBright) }
                        }
                        TextField("Telefono", text: $contattoTelefono.cambia { salvato = false }).font(.system(size: 12)).foregroundStyle(Theme.dim).keyboardType(.phonePad)
                    }
                    Spacer(minLength: 0)
                    Button { rubrica = true } label: {
                        HStack(spacing: 6) { IconaTela(d: Ic.libro, colore: Theme.testo, lato: 14); Text("Rubrica").font(.system(size: 12, weight: .heavy)) }
                            .foregroundStyle(Theme.testo).padding(.horizontal, 11).frame(height: 34)
                            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.olive.opacity(0.25)))
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke))
            }
            VStack(alignment: .leading, spacing: 5) {
                EtichettaCampo(testo: "Allergie")
                FlussoCapsule(spazio: 6) {
                    ForEach(Self.allergieComuni + allergie.filter { !Self.allergieComuni.contains($0) }.sorted(), id: \.self) { a in
                        let on = allergie.contains(a)
                        Button {
                            haptic(.soft)
                            if a == "Nessuna" { allergie = on ? [] : ["Nessuna"] }
                            else { if on { allergie.remove(a) } else { allergie.insert(a); allergie.remove("Nessuna") } }
                            salvato = false
                        } label: { capsula(a, on: on) }
                        .buttonStyle(.plain)
                    }
                    Button { altraAllergia = true } label: { capsula("+ altro", on: false) }.buttonStyle(.plain)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                CampoTesto(etichetta: "Farmaci che prendo", testo: $farmaci.cambia { salvato = false }, maiuscole: .sentences)
                NotaCampo(testo: "Facoltativo")
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Visibili a chi è in campo con me").font(.system(size: 13.5, weight: .heavy)).foregroundStyle(Theme.testo)
                    Text("Spento = li vede solo il direttivo").font(.system(size: 11.5)).foregroundStyle(Theme.dim)
                }
                Spacer()
                Toggle("", isOn: $visibili.cambia { salvato = false }).labelsHidden().tint(Theme.olive)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke))
        }
    }

    func capsula(_ t: String, on: Bool) -> some View {
        Text(t).font(.system(size: 13, weight: .heavy)).foregroundStyle(on ? Theme.scuro : Theme.testo2)
            .padding(.horizontal, 13).frame(height: 36)
            .background(on ? Theme.amber : Theme.surface2, in: Capsule())
            .overlay(Capsule().strokeBorder(on ? .clear : Theme.olive.opacity(0.25)))
    }

    func iniziali(_ s: String) -> String {
        let p = s.split(separator: " ").prefix(2).compactMap(\.first)
        return p.isEmpty ? "?" : String(p).uppercased()
    }

    // MARK: carica e salva

    func carica() async {
        var p: JProfilo?
        if Anteprima.attiva { p = Anteprima.profilo } else { p = try? await jsoc.profilo() }
        guard let p else { errore = "Profilo non disponibile"; return }
        // nome e cognome: il server tiene il nome intero in "nome" e il cognome a parte
        let pieno = p.nome.trimmingCharacters(in: .whitespaces)
        if let c = p.cognome, !c.isEmpty {
            cognome = c
            nome = pieno.hasSuffix(c) ? String(pieno.dropLast(c.count)).trimmingCharacters(in: .whitespaces) : pieno
        } else {
            let parti = pieno.split(separator: " ")
            nome = parti.dropLast().joined(separator: " ").ifEmpty(pieno)
            cognome = parti.count > 1 ? String(parti.last!) : ""
        }
        sesso = p.sesso == "F" ? 1 : 0
        if let n = p.nascita, let d = JEvento.data(n) { nascita = d }
        if let l = p.luogo_nascita, !l.isEmpty {
            comuneScelto = ComuniIT.trova(l, sigla: p.provincia_nascita)
            comune = comuneScelto.map { "\($0.nome) (\($0.sigla))" } ?? l
        }
        cf = p.cf ?? ""
        if !cf.isEmpty, let c = comuneScelto,
           CodiceFiscale.calcola(nome: nome, cognome: cognome, nascita: nascita, femmina: sesso == 1, catastale: c.catastale) != cf.uppercased() { cfAMano = true }
        let tel = p.telefono ?? ""
        if tel.hasPrefix("+"), let sp = tel.firstIndex(of: " ") { prefisso = String(tel[..<sp]); telefono = String(tel[sp...]).trimmingCharacters(in: .whitespaces) }
        else { telefono = tel }
        email = p.email ?? ""
        via = p.indirizzo ?? ""; cap = p.cap ?? ""; citta = p.citta ?? ""; provincia = p.provincia ?? ""
        tipoCertificato = p.certificato_tipo == "agonistico" ? 1 : 0
        scadenza = JEvento.data(p.certificato_scadenza)
        fileCertificato = !(p.certificato_file ?? "").isEmpty
        gruppo = (p.gruppo_sanguigno ?? "").replacingOccurrences(of: "-", with: "−")
        let em = (p.emergenza ?? "").components(separatedBy: "|")
        if em.count >= 3 { contattoNome = em[0]; contattoRelazione = em[1]; contattoTelefono = em[2] }
        else if let e = p.emergenza, !e.isEmpty {
            // vecchio formato "Nome +39 ..." : separo il numero
            if let r = e.range(of: #"\+?[0-9][0-9 ]{5,}$"#, options: .regularExpression) { contattoNome = String(e[..<r.lowerBound]).trimmingCharacters(in: .whitespaces); contattoTelefono = String(e[r]) }
            else { contattoNome = e }
        }
        allergie = Set((p.allergie ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        farmaci = p.farmaci ?? ""
        visibili = p.emergenza_visibile != "0"
        salvato = false
    }

    func salva() {
        let n = nome.trimmingCharacters(in: .whitespaces), c = cognome.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { errore = "Scrivi il nome"; return }
        var campi: [String: Any] = [
            "nome": [n, c].filter { !$0.isEmpty }.joined(separator: " "), "cognome": c, "sesso": sesso == 1 ? "F" : "M",
            "nascita": FormatoGiorno.f.string(from: nascita), "cf": cf.uppercased(),
            "telefono": telefono.isEmpty ? "" : "\(prefisso) \(telefono)", "email": email.trimmingCharacters(in: .whitespaces),
            "indirizzo": via, "cap": cap, "citta": citta, "provincia": provincia.uppercased(),
            "certificato_tipo": tipoCertificato == 1 ? "agonistico" : "non agonistico",
            "certificato_scadenza": scadenza.map { FormatoGiorno.f.string(from: $0) } ?? "",
            "gruppo_sanguigno": gruppo.replacingOccurrences(of: "−", with: "-"),
            "emergenza": contattoNome.isEmpty ? "" : "\(contattoNome)|\(contattoRelazione)|\(contattoTelefono)",
            "allergie": allergie.sorted().joined(separator: ", "), "farmaci": farmaci, "emergenza_visibile": visibili ? "1" : "0",
        ]
        if let k = comuneScelto { campi["luogo_nascita"] = k.nome; campi["provincia_nascita"] = k.sigla }
        else if !comune.isEmpty { campi["luogo_nascita"] = comune }
        guard !Anteprima.attiva else { salvato = true; return }
        Task {
            do {
                _ = try await jsoc.salvaProfilo(campi)
                salvato = true; errore = nil
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                await HomeModel.shared.aggiorna()
            } catch { errore = error.localizedDescription }
        }
    }

    func carica(_ dati: Data?, _ tipo: String) {
        guard let dati, !Anteprima.attiva else { fileCertificato = true; return }
        Task {
            do {
                var r = try jsoc.richiestaPubblica("/api/profilo/certificato", "PUT")
                r.setValue(tipo, forHTTPHeaderField: "Content-Type")
                let (_, resp) = try await URLSession.shared.upload(for: r, from: dati)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw JsocErrore.server("caricamento non riuscito") }
                fileCertificato = true; errore = nil
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch { errore = error.localizedDescription }
        }
    }
}

// MARK: - aiuti

extension Binding {
    /// esegue qualcosa quando il valore cambia (per ricalcolare il codice fiscale ecc.)
    func cambia(_ f: @escaping () -> Void) -> Binding<Value> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0; f() })
    }
}

extension FormatiHome {
    static let giornoLungoAnno: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "d MMMM yyyy"; return f }()
}

/// elenco di proposte sotto un campo (comuni, indirizzi): righe 44, prima evidenziata
struct ElencoProposte: View {
    let righe: [(String, String)]
    var icona: String? = nil
    let scegli: (Int) -> Void
    var body: some View {
        VStack(spacing: 0) {
            ForEach(righe.indices, id: \.self) { i in
                Button { haptic(.soft); scegli(i) } label: {
                    HStack(spacing: 10) {
                        if let icona { IconaTela(d: icona, colore: i == 0 ? Theme.oliveBright : Theme.dim, lato: 16) }
                        Text(righe[i].0).font(.system(size: 13.5, weight: .bold)).foregroundStyle(Theme.testo).lineLimit(1)
                        Spacer()
                        Text(righe[i].1).font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(1)
                    }
                    .padding(.horizontal, 12).frame(height: 44)
                    .background(i == 0 ? Theme.olive.opacity(0.12) : .clear)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Theme.olive.opacity(0.14)).frame(height: 1) } }
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(hex: 0x1F2717), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.olive.opacity(0.3)))
        .padding(.top, 4)
    }
}

/// ruota della data (tavola 33): giorno · mese · anno, fascia verde al centro
struct RuotaData: View {
    @Binding var data: Date
    static let mesi = ["gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre"]
    var body: some View {
        let cal = Calendar(identifier: .gregorian)
        let k = cal.dateComponents([.year, .month, .day], from: data)
        let anno = Calendar.current.component(.year, from: Date())
        // tavola 33: 5 righe da 24, una sola fascia evidenziata, anni crescenti verso il basso
        GeometryReader { g in
            HStack(spacing: 0) {
                RulloTela(voci: Array(1...31).map(String.init), sel: (k.day ?? 1) - 1) { i in imposta(giorno: i + 1) }.frame(width: g.size.width / 3)
                RulloTela(voci: Self.mesi, sel: (k.month ?? 1) - 1) { i in imposta(mese: i + 1) }.frame(width: g.size.width / 3)
                RulloTela(voci: Array((anno - 90)...anno).map(String.init), sel: (k.year ?? anno) - (anno - 90)) { i in imposta(anno: anno - 90 + i) }.frame(width: g.size.width / 3)
            }
        }
        .frame(height: 123)
        .background(alignment: .center) { RoundedRectangle(cornerRadius: 9).fill(Color(hex: 0x2A3120)).frame(height: 36).padding(.horizontal, 8) }
        .background(Color(hex: 0x11150D), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    func imposta(giorno: Int? = nil, mese: Int? = nil, anno: Int? = nil) {
        let cal = Calendar(identifier: .gregorian)
        var k = cal.dateComponents([.year, .month, .day], from: data)
        if let anno { k.year = anno }
        if let mese { k.month = mese }
        if let giorno { k.day = giorno }
        // giorno che non esiste nel mese (31 febbraio): ultimo giorno del mese
        if let d = cal.date(from: DateComponents(year: k.year, month: k.month)), let n = cal.range(of: .day, in: .month, for: d)?.count, (k.day ?? 1) > n { k.day = n }
        if let d = cal.date(from: k) { data = d }
    }
}

/// un rullo della data come la tavola 33: scelto 17 nero pieno, vicini 15 attenuati, trascina e si aggancia alla riga
struct RulloTela: View {
    let voci: [String]
    let sel: Int
    let scegli: (Int) -> Void
    @State private var trascina: CGFloat = 0
    static let riga: CGFloat = 24

    var body: some View {
        // posizione "continua" durante il trascinamento
        let pos = min(max(CGFloat(sel) - trascina / Self.riga, 0), CGFloat(voci.count - 1))
        let da = max(0, Int(pos) - 3), a = min(voci.count - 1, Int(pos) + 3)
        ZStack {
            ForEach(Array(da...a), id: \.self) { i in
                let d = CGFloat(i) - pos
                Text(voci[i])
                    .font(.system(size: abs(d) < 0.5 ? 17 : 15, weight: abs(d) < 0.5 ? .heavy : .semibold))
                    .foregroundStyle(abs(d) < 0.5 ? Theme.testo : Theme.testo2.opacity(abs(d) < 1.5 ? 0.75 : 0.4))
                    .offset(y: d * Self.riga)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(DragGesture()
            .onChanged { trascina = $0.translation.height }
            .onEnded { v in
                let fine = Int((CGFloat(sel) - v.predictedEndTranslation.height / Self.riga).rounded())
                trascina = 0
                let n = min(max(fine, 0), voci.count - 1)
                if n != sel { UISelectionFeedbackGenerator().selectionChanged(); scegli(n) }
            })
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: sel)
        .accessibilityElement().accessibilityValue(voci[sel])
        .accessibilityAdjustableAction { a in
            if a == .increment, sel < voci.count - 1 { scegli(sel + 1) }
            if a == .decrement, sel > 0 { scegli(sel - 1) }
        }
    }
}

/// moduli a schermo intero aperti (I miei dati, Salute): finché ce n'è uno la barra in basso sparisce
final class ModuliAperti: ObservableObject {
    static let shared = ModuliAperti()
    @Published var aperti = 0
}

/// capsule che vanno a capo (allergie)
struct FlussoCapsule: SwiftUI.Layout {
    var spazio: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, riga: CGFloat = 0
        for s in subviews {
            let d = s.sizeThatFits(.unspecified)
            if x + d.width > w, x > 0 { x = 0; y += riga + spazio; riga = 0 }
            x += d.width + spazio; riga = max(riga, d.height)
        }
        return CGSize(width: w, height: y + riga)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, riga: CGFloat = 0
        for s in subviews {
            let d = s.sizeThatFits(.unspecified)
            if x + d.width > b.maxX, x > b.minX { x = b.minX; y += riga + spazio; riga = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(d))
            x += d.width + spazio; riga = max(riga, d.height)
        }
    }
}

/// completamento degli indirizzi con Apple Mappe (gratis, senza chiave): via → CAP, città, provincia
@MainActor
final class CompletaIndirizzi: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var risultati: [MKLocalSearchCompletion] = []
    private let c = MKLocalSearchCompleter()

    override init() {
        super.init()
        c.delegate = self
        c.resultTypes = .address
        c.region = MKCoordinateRegion(center: .init(latitude: 41.9, longitude: 12.5), span: .init(latitudeDelta: 12, longitudeDelta: 12))
    }

    func cerca(_ t: String) {
        if t.count < 4 { risultati = []; return }
        c.queryFragment = t
    }

    nonisolated func completerDidUpdateResults(_ cc: MKLocalSearchCompleter) {
        let r = cc.results
        Task { @MainActor in self.risultati = r }
    }

    func dettagli(_ r: MKLocalSearchCompletion, _ f: @escaping (String, String, String) -> Void) {
        MKLocalSearch(request: MKLocalSearch.Request(completion: r)).start { risposta, _ in
            guard let p = risposta?.mapItems.first?.placemark else { return }
            let citta = p.locality ?? ""
            var prov = p.subAdministrativeArea ?? ""
            if prov.count != 2 { prov = ComuniIT.trova(citta)?.sigla ?? prov }
            Task { @MainActor in f(p.postalCode ?? "", citta, prov) }
        }
    }
}

/// scelta di un contatto dalla rubrica (non chiede permessi: l'utente sceglie un solo contatto)
struct SceltaContatto: UIViewControllerRepresentable {
    let scelto: (String, String) -> Void
    @Environment(\.dismiss) private var chiudi
    func makeCoordinator() -> Coord { Coord(self) }
    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let p = CNContactPickerViewController()
        p.delegate = context.coordinator
        p.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        return p
    }
    func updateUIViewController(_ vc: CNContactPickerViewController, context: Context) {}
    final class Coord: NSObject, CNContactPickerDelegate {
        let parent: SceltaContatto
        init(_ p: SceltaContatto) { parent = p }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect c: CNContact) {
            let nome = [c.givenName, c.familyName.first.map { "\($0)." } ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
            parent.scelto(nome, c.phoneNumbers.first?.value.stringValue ?? "")
        }
    }
}
