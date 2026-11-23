import SwiftUI
import PhotosUI

// MARK: - Proponi / modifica / duplica evento (tavola 42). Due schede: "Cosa e quando" (tavola) e "Iscrizioni".

struct NuovoEventoV3: View {
    var modifica: JEvento? = nil
    /// duplica: parte da questo evento, una settimana dopo
    var base: JEvento? = nil
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var location: LocationService
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var store = EventoStore.shared
    @State private var scheda = 0
    @State private var foto: PhotosPickerItem?
    @State private var copertina: UIImage?
    @State private var tipo = "allenamento"
    @State private var nome = ""
    @State private var nomeToccato = false
    @State private var inizio = NuovoEventoV3.domenica(8, 30)
    @State private var fine = NuovoEventoV3.domenica(13, 0)
    @State private var luogo = ""
    @State private var lat: Double?
    @State private var lon: Double?
    @State private var note = ""
    @State private var interno = 0
    // iscrizioni
    @State private var conScadenza = 0
    @State private var scadenza = Calendar.current.date(byAdding: .day, value: 5, to: Date()) ?? Date()
    @State private var conPosti = 0
    @State private var posti = 12
    @State private var quota = ""
    @State private var domande: [String] = []
    @State private var nuovaDomanda = ""
    @State private var nascosto = 0
    @State private var pacchetto: Int?
    @State private var pacchetti: [JPacchetto] = []
    // fogli
    @State private var sceltaGiorno = false
    @State private var sceltaOrario = false
    @State private var sceltaScadenza = false
    @State private var lavoro = false
    @State private var errore: String?
    @State private var pronto = false
    @FocusState private var fuocoLuogo: Bool

    /// prossima domenica alle ore indicate
    static func domenica(_ h: Int, _ m: Int) -> Date {
        let cal = Calendar.current
        var d = cal.startOfDay(for: Date())
        repeat { d = cal.date(byAdding: .day, value: 1, to: d) ?? d } while cal.component(.weekday, from: d) != 1
        return cal.date(bySettingHour: h, minute: m, second: 0, of: d) ?? d
    }

    var direttivo: Bool { jsoc.utente?.direttivo == true }
    static let tipi: [(String, String, Color)] = [("gara", "Gara", Theme.red), ("allenamento", "Allenam.", Theme.olive),
                                                  ("riunione", "Riunione", Theme.cyan), ("altro", "Assoc.", Theme.amber)]

    var body: some View {
        VStack(spacing: 0) {
            intestazione
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    SchedeTela(voci: ["Cosa e quando", "Iscrizioni"], scelta: $scheda)
                    if let errore { Text(errore).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.red) }
                    if scheda == 0 { cosaQuando } else { iscrizioni }
                }
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { ModuliAperti.shared.aperti += 1; riempi() }
        .onDisappear { ModuliAperti.shared.aperti = max(0, ModuliAperti.shared.aperti - 1) }
        .task { if modifica == nil && !Anteprima.attiva { pacchetti = (try? await jsoc.pacchetti()) ?? [] } }
        .onChange(of: foto) { f in
            Task { if let d = try? await f?.loadTransferable(type: Data.self), let i = UIImage(data: d) { copertina = i } }
        }
        .onChange(of: tipo) { _ in suggerisci() }
        .onChange(of: luogo) { _ in suggerisci() }
        .onChange(of: inizio) { _ in suggerisci() }
        .sheet(isPresented: $sceltaGiorno) { foglioGiorno }
        .sheet(isPresented: $sceltaOrario) { foglioOrario }
        .sheet(isPresented: $sceltaScadenza) { foglioScadenza }
    }

    /// intestazione: indietro 42, titolo 24, "Proponi" verde alto 36
    var intestazione: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                IconaTela(d: Ic.indietro, colore: Theme.testo, lato: 18)
                    .frame(width: 42, height: 42).background(Theme.surface, in: Circle()).overlay(Circle().strokeBorder(Theme.stroke))
            }
            .accessibilityLabel("Indietro")
            Text(modifica != nil ? "Modifica evento" : "Proponi evento").font(.system(size: 24, weight: .black)).foregroundStyle(Theme.testo)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer()
            Button { crea() } label: {
                Text(modifica != nil ? "Salva" : "Proponi").font(.system(size: 13.5, weight: .black)).foregroundStyle(Theme.scuro)
                    .padding(.horizontal, 14).frame(height: 36)
                    .background(Theme.olive, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .opacity(nome.trimmingCharacters(in: .whitespaces).isEmpty || lavoro ? 0.5 : 1)
            }
            .disabled(nome.trimmingCharacters(in: .whitespaces).isEmpty || lavoro)
        }
        .padding(.horizontal, 14).padding(.top, 7)
    }

    // MARK: Cosa e quando (tavola 42)

    var cosaQuando: some View {
        VStack(alignment: .leading, spacing: 11) {
            PhotosPicker(selection: $foto, matching: .images) {
                ZStack {
                    Color(hex: 0x26301A)
                    if let copertina { Image(uiImage: copertina).resizable().scaledToFill().frame(maxWidth: .infinity, maxHeight: 96).clipped().opacity(0.6) }
                    HStack(spacing: 10) {
                        IconaTela(d: Ic.fotocamera, colore: Theme.oliveBright, lato: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(copertina == nil ? "Foto di copertina" : "Cambia la foto").font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.testo)
                            Text("Scatta o scegli dalla galleria · facoltativa").font(.system(size: 11)).foregroundStyle(Theme.dim)
                        }
                    }
                }
                .frame(height: 96).frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.olive.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            }
            .buttonStyle(.plain)
            HStack(spacing: 6) {
                ForEach(Self.tipi, id: \.0) { t in
                    let on = tipo == t.0
                    Button { haptic(.soft); tipo = t.0 } label: {
                        VStack(spacing: 5) {
                            Circle().fill(t.2).frame(width: 10, height: 10)
                            Text(t.1).font(.system(size: 12.5, weight: .heavy)).foregroundStyle(on ? Theme.testo : Theme.testo2).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity).frame(height: 58)
                        .background(on ? Theme.olive.opacity(0.133) : Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? Theme.olive : Theme.stroke, lineWidth: on ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                CampoTesto(etichetta: "Nome", testo: Binding(get: { nome }, set: { nome = $0; nomeToccato = true }), maiuscole: .sentences)
                if !nomeToccato && !nome.isEmpty && modifica == nil { NotaCampo(testo: "Suggerito dal tipo e dal luogo · puoi cambiarlo") }
            }
            ColonnePesate(pesi: [1.25, 1], spazio: 8) {
                campoTocco("Giorno", giornoTesto, Ic.calendario) { sceltaGiorno = true }
                campoTocco("Orario", FormatiEventi.ora.string(from: inizio) + "–" + FormatiEventi.ora.string(from: fine), Ic.orologio) { sceltaOrario = true }
            }
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    EtichettaCampo(testo: "Luogo")
                    RiquadroCampo(attivo: fuocoLuogo) {
                        TextField("", text: $luogo).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.testo)
                            .textInputAutocapitalization(.words).focused($fuocoLuogo)
                        Button { usaPosizione() } label: { IconaTela(d: Ic.segnaposto, colore: Theme.olive, lato: 17) }
                            .accessibilityLabel("Usa la mia posizione")
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(luoghiNoti, id: \.0) { l in
                            chip(l.0, on: luogo == l.0) { luogo = l.0; lat = l.1; lon = l.2 }
                        }
                        chip("Altro luogo…", on: false) { luogo = ""; lat = nil; lon = nil; fuocoLuogo = true }
                    }
                }
                .padding(.top, 6)
            }
            VStack(alignment: .leading, spacing: 4) {
                EtichettaCampo(testo: "Descrizione")
                TextField("", text: $note, axis: .vertical)
                    .font(.system(size: 13.5)).foregroundStyle(Theme.testo2).lineSpacing(2.5).lineLimit(2...8)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(minHeight: 70, alignment: .topLeading)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke))
            }
            if tipo == "allenamento" || tipo == "gara" {
                VStack(alignment: .leading, spacing: 5) {
                    EtichettaCampo(testo: "Chi gioca · solo se è un allenamento")
                    SceltaTela(voci: ["Interno (Attacco/Difesa)", "Esterno (gara di altri)"], scelta: $interno)
                }
            }
        }
    }

    var giornoTesto: String {
        let s = FormatiEventi.giornoBreve.string(from: inizio)
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    func campoTocco(_ etichetta: String, _ valore: String, _ ic: String, _ f: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            EtichettaCampo(testo: etichetta)
            Button { haptic(.soft); f() } label: {
                RiquadroCampo {
                    Text(valore).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.testo).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    IconaTela(d: ic, colore: Theme.olive, lato: 17)
                }
            }
            .buttonStyle(.plain)
        }
    }

    func chip(_ t: String, on: Bool, _ f: @escaping () -> Void) -> some View {
        Button { haptic(.soft); f() } label: {
            Text(t).font(.system(size: 11.5, weight: .heavy)).foregroundStyle(on ? Theme.scuro : Theme.testo2)
                .padding(.horizontal, 10).frame(height: 32)
                .background(on ? Theme.olive : Theme.surface2, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? .clear : Theme.olive.opacity(0.25)))
        }
        .buttonStyle(.plain)
    }

    /// luoghi già usati negli eventi, i più frequenti prima (con le coordinate se ci sono)
    var luoghiNoti: [(String, Double?, Double?)] {
        if Anteprima.attiva { return Anteprima.luoghiEventi.map { n in (n, nil, nil) } }
        var conta: [String: (Int, Double?, Double?)] = [:]
        for e in store.eventi {
            guard let l = e.luogo?.trimmingCharacters(in: .whitespaces), !l.isEmpty else { continue }
            let c = conta[l]
            conta[l] = ((c?.0 ?? 0) + 1, c?.1 ?? e.lat, c?.2 ?? e.lon)
        }
        return conta.sorted { $0.value.0 > $1.value.0 }.prefix(3).map { ($0.key, $0.value.1, $0.value.2) }
    }

    func usaPosizione() {
        haptic()
        guard let c = location.location?.coordinate else { errore = "Posizione non disponibile"; return }
        lat = c.latitude; lon = c.longitude
        if luogo.isEmpty { luogo = "Qui" }
    }

    /// nome suggerito dal tipo, dal giorno e dal luogo finché non lo scrivi tu
    func suggerisci() {
        guard pronto, !nomeToccato, modifica == nil else { return }
        let g = Calendar.current.component(.weekday, from: inizio)
        let primo: String
        switch tipo {
        case "allenamento": primo = g == 1 ? "Domenicale" : (g == 7 ? "Sabato" : "Allenamento")
        case "gara": primo = "Gara"
        case "riunione": primo = "Riunione"
        default: primo = "Incontro"
        }
        let l = luogo.trimmingCharacters(in: .whitespaces)
        nome = l.isEmpty || l == "Qui" ? primo : "\(primo) \(l)"
    }

    // MARK: Iscrizioni (stessi pezzi della tela)

    var iscrizioni: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 4) {
                EtichettaCampo(testo: "Scadenza per rispondere")
                SceltaTela(voci: ["Nessuna", "Entro una data"], scelta: $conScadenza)
                if conScadenza == 1 {
                    Button { sceltaScadenza = true } label: {
                        RiquadroCampo {
                            Text(FormatiEventi.giornoBreve.string(from: scadenza).capitalized + " · " + FormatiEventi.ora.string(from: scadenza))
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.testo)
                            Spacer(minLength: 0)
                            IconaTela(d: Ic.calendario, colore: Theme.olive, lato: 17)
                        }
                    }
                    .buttonStyle(.plain).padding(.top, 4)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                EtichettaCampo(testo: "Posti")
                SceltaTela(voci: ["Liberi", "Limitati"], scelta: $conPosti)
                if conPosti == 1 {
                    RiquadroCampo {
                        Text("\(posti) posti").font(Theme.mono(15, .semibold)).foregroundStyle(Theme.testo)
                        Spacer()
                        tastino("−") { posti = max(1, posti - 1) }
                        tastino("+") { posti = min(200, posti + 1) }
                    }
                    .padding(.top, 4)
                    NotaCampo(testo: "Finiti i posti, chi risponde va in lista d'attesa")
                }
            }
            CampoTesto(etichetta: "Quota (€)", testo: $quota, tastiera: .decimalPad, mono: true)
            VStack(alignment: .leading, spacing: 4) {
                EtichettaCampo(testo: "Domande all'iscrizione")
                ForEach(domande, id: \.self) { d in
                    RiquadroCampo {
                        Text(d).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.testo).lineLimit(1)
                        Spacer()
                        Button { domande.removeAll { $0 == d } } label: { IconaTela(d: Ic.croce, colore: Theme.dim, lato: 14) }
                    }
                }
                RiquadroCampo {
                    TextField("", text: $nuovaDomanda, prompt: Text("Es. Porti l'auto? Quanti posti?").foregroundColor(Color(hex: 0x7D8470)))
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.testo)
                    Button {
                        let t = nuovaDomanda.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty && !domande.contains(t) { domande.append(t) }
                        nuovaDomanda = ""
                    } label: { IconaTela(d: Ic.piu, colore: Theme.olive, lato: 17) }
                }
            }
            if modifica == nil && !pacchetti.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    EtichettaCampo(testo: "Coordinate dall'archivio")
                    Menu {
                        Button("Nessuno") { pacchetto = nil }
                        ForEach(pacchetti) { p in Button("\(p.nome) · \(p.punti.count) punti") { pacchetto = p.id } }
                    } label: {
                        RiquadroCampo {
                            Text(pacchetti.first { $0.id == pacchetto }?.nome ?? "Nessuno").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.testo)
                            Spacer()
                            IconaTela(d: Ic.giu, colore: Theme.olive, lato: 17)
                        }
                    }
                    NotaCampo(testo: "I punti del pacchetto vengono copiati nella mappa del nuovo evento")
                }
            }
            if modifica == nil {
                VStack(alignment: .leading, spacing: 4) {
                    EtichettaCampo(testo: "Chi lo vede")
                    SceltaTela(voci: ["Tutti", "Solo io (nascosto)"], scelta: $nascosto)
                    NotaCampo(testo: nascosto == 1 ? "Nessuno lo vede finché non lo rendi visibile dalla sua scheda"
                              : (direttivo ? "Lo vedono subito tutti" : "Lo vedranno tutti dopo l'approvazione del direttivo"),
                              colore: nascosto == 0 && !direttivo ? Theme.amber : Theme.dim)
                }
            }
        }
    }

    func tastino(_ t: String, _ f: @escaping () -> Void) -> some View {
        Button { haptic(.soft); f() } label: {
            Text(t).font(.system(size: 18, weight: .heavy)).foregroundStyle(Theme.testo)
                .frame(width: 34, height: 32).background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: fogli data e ora

    var foglioGiorno: some View {
        NavigationStack {
            DatePicker("Giorno", selection: Binding(get: { inizio }, set: { sposta(giorno: $0) }), displayedComponents: .date)
                .datePickerStyle(.graphical).tint(Theme.olive).padding(.horizontal, 14)
                .environment(\.locale, Locale(identifier: "it_IT"))
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fatto") { sceltaGiorno = false } } }
                .navigationTitle("Giorno").navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    var foglioOrario: some View {
        NavigationStack {
            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("INIZIO").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.dim)
                    DatePicker("", selection: Binding(get: { inizio }, set: { n in let d = fine.timeIntervalSince(inizio); inizio = n; fine = n.addingTimeInterval(max(1800, d)) }),
                               displayedComponents: .hourAndMinute).datePickerStyle(.wheel).labelsHidden()
                }
                VStack(spacing: 2) {
                    Text("FINE").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.dim)
                    DatePicker("", selection: $fine, in: inizio..., displayedComponents: .hourAndMinute).datePickerStyle(.wheel).labelsHidden()
                }
            }
            .environment(\.locale, Locale(identifier: "it_IT"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fatto") { sceltaOrario = false } } }
            .navigationTitle("Orario").navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    var foglioScadenza: some View {
        NavigationStack {
            DatePicker("Entro il", selection: $scadenza, in: ...inizio, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical).tint(Theme.olive).padding(.horizontal, 14)
                .environment(\.locale, Locale(identifier: "it_IT"))
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fatto") { sceltaScadenza = false } } }
                .navigationTitle("Scadenza").navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
    }

    /// cambia il giorno tenendo gli orari
    func sposta(giorno g: Date) {
        let cal = Calendar.current
        func unisci(_ ora: Date) -> Date {
            let h = cal.dateComponents([.hour, .minute], from: ora)
            return cal.date(bySettingHour: h.hour ?? 0, minute: h.minute ?? 0, second: 0, of: g) ?? g
        }
        let durata = fine.timeIntervalSince(inizio)
        inizio = unisci(inizio)
        fine = inizio.addingTimeInterval(max(1800, durata))
    }

    // MARK: dati

    func riempi() {
        guard !pronto else { return }
        defer { pronto = true; if nome.isEmpty { suggerisci() } }
        if Anteprima.attiva && modifica == nil && base == nil {
            // tavola 42
            tipo = "allenamento"; nome = "Domenicale CQB"; luogo = "Campo Calimera"; interno = 0
            note = "Scenario CQB a squadre, ritrovo 8:00 al parcheggio. Portare acqua e pranzo al sacco."
            if let i = JEvento.data("2026-11-22T08:30"), let f = JEvento.data("2026-11-22T13:00") { inizio = i; fine = f }
            return
        }
        guard let e = modifica ?? base else { return }
        nome = e.nome; nomeToccato = true
        tipo = ["gara", "allenamento", "riunione"].contains(e.tipo) ? e.tipo : "altro"
        interno = e.interno == 0 ? 1 : 0
        if let i = e.dataInizio { inizio = i }
        if let f = e.dataFine { fine = f } else { fine = inizio.addingTimeInterval(4 * 3600) }
        if base != nil {
            let cal = Calendar.current
            inizio = cal.date(byAdding: .day, value: 7, to: inizio) ?? inizio
            fine = cal.date(byAdding: .day, value: 7, to: fine) ?? fine
        }
        luogo = e.luogo ?? ""; lat = e.lat; lon = e.lon; note = e.note ?? ""
        if let s = e.dataScadenza, modifica != nil { conScadenza = 1; scadenza = s }
        if let p = e.posti, p > 0 { conPosti = 1; posti = p }
        if let q = e.quota, q > 0 { quota = euroTela(q).replacingOccurrences(of: " €", with: "") }
        domande = e.domande ?? []
        nascosto = e.privato ? 1 : 0
    }

    func crea() {
        guard !Anteprima.attiva else { dismiss(); return }
        lavoro = true; errore = nil
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let giocaInterno = (tipo == "allenamento" || tipo == "gara") && interno == 0
        var campi: [String: Any] = ["nome": nome.trimmingCharacters(in: .whitespaces), "tipo": tipo,
                                    "inizio": f.string(from: inizio), "fine": f.string(from: fine),
                                    "luogo": luogo == "Qui" ? "" : luogo, "note": note, "interno": giocaInterno ? 1 : 0, "domande": domande,
                                    "nascosto": nascosto]
        if conScadenza == 1 { campi["scadenza"] = f.string(from: scadenza) }
        if conPosti == 1 { campi["posti"] = posti }
        let q = Double(quota.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        if let q, q > 0 { campi["quota"] = q }
        if let lat, let lon { campi["lat"] = lat; campi["lon"] = lon }
        let img = copertina
        if let m = modifica {
            campi.removeValue(forKey: "nascosto")
            if conScadenza == 0 { campi["scadenza"] = NSNull() }
            if conPosti == 0 { campi["posti"] = NSNull() }
            if q == nil || q == 0 { campi["quota"] = NSNull() }
            Task {
                do {
                    _ = try await jsoc.modificaEvento(m.id, campi)
                    if let img, let d = img.ridotta(lato: 1600).jpegData(compressionQuality: 0.75) { try? await jsoc.caricaDati("/api/eventi/\(m.id)/copertina", dati: d) }
                    await store.aggiorna(jsoc)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                } catch { errore = error.localizedDescription }
                lavoro = false
            }
            return
        }
        let pk = pacchetto
        Task {
            do {
                let e = try await jsoc.creaEvento(campi)
                if let pk { _ = try? await jsoc.usaPacchetto(pk, evento: e.id) }
                if let img, let d = img.ridotta(lato: 1600).jpegData(compressionQuality: 0.75) { try? await jsoc.caricaDati("/api/eventi/\(e.id)/copertina", dati: d) }
                await store.aggiorna(jsoc)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } catch { errore = error.localizedDescription }
            lavoro = false
        }
    }
}
