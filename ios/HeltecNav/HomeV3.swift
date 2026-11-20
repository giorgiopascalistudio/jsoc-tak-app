import SwiftUI
import MapKit

// MARK: - Home in una schermata (bozza 7 della tela): niente scorrimento.
// In alto saluto, campanella e profilo; poi il prossimo evento con conto alla rovescia, meteo e Partecipo;
// "Da fare" (max 3 + "altri N"); in basso calendario piccolo e mappa piccola affiancati, che aprono il dettaglio.

/// formattatori fissi: mai crearli dentro body (causa dei blocchi del 19-20/11)
enum FormatiHome {
    static let giornoLungo: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "EEEE d MMMM"; return f }()
    static let giornoBreve: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "EEE d MMM · HH:mm"; return f }()
    static let mese: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "LLLL"; return f }()
    static let scadenza: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "EEEE 'alle' HH:mm"; return f }()
}

struct HomeV3: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var store = EventoStore.shared
    @ObservedObject private var home = HomeModel.shared
    @State private var percorso: [JEvento] = []
    @State private var profilo = false
    @State private var notifiche = false
    @State private var calendario = false
    @State private var tuttiDaFare = false

    var body: some View {
        let _ = Contatori.disegno("HomeV3")
        NavigationStack(path: $percorso) {
            Group {
                if jsoc.collegato { contenuto } else { EntraView() }
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: JEvento.self) { EventoScheda(evento: $0) }
        }
        .sheet(isPresented: $profilo) { ProfiloTab() }
        .sheet(isPresented: $notifiche) { CentroNotifiche(apri: { e in notifiche = false; percorso.append(e) }) }
        .sheet(isPresented: $calendario) { CalendarioMese(apri: { e in calendario = false; percorso.append(e) }) }
        .sheet(isPresented: $tuttiDaFare) { ElencoDaFare(voci: daFare, chiudi: { tuttiDaFare = false }) }
        .task { await home.aggiorna() }
    }

    // MARK: contenuto: una colonna sul telefono, due colonne su iPad / in orizzontale

    var contenuto: some View {
        GeometryReader { g in
            let largo = g.size.width > 700 || g.size.width > g.size.height
            VStack(alignment: .leading, spacing: 12) {
                intestazione
                if largo {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 12) { prossimo; daFareBox(max: 4); Spacer(minLength: 0) }
                        VStack(spacing: 12) { calendarioPiccolo; mappaPiccola }.frame(width: min(440, g.size.width * 0.38))
                    }
                } else {
                    prossimo
                    daFareBox(max: 3)
                    HStack(spacing: 10) { calendarioPiccolo; mappaPiccola }
                        .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, largo ? 12 : 84)   // spazio per la barra in basso
        }
        .refreshable { await store.aggiorna(jsoc); await home.aggiorna() }
    }

    // MARK: intestazione

    var nonLette: Int { (home.dati?.avvisi ?? []).count + senzaRisposta.count }

    var intestazione: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(FormatiHome.giornoLungo.string(from: Date()).uppercased())
                    .font(.system(size: 12, weight: .heavy)).tracking(0.8).foregroundStyle(Theme.dim)
                Text("Ciao, \(jsoc.utente?.callsign ?? "")").font(.system(size: 30, weight: .black)).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer()
            Button { haptic(); notifiche = true } label: {
                Image(systemName: "bell").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(Theme.surface, in: Circle()).overlay(Circle().strokeBorder(Theme.stroke))
                    .overlay(alignment: .topTrailing) {
                        if nonLette > 0 {
                            Text("\(nonLette)").font(.system(size: 10.5, weight: .black)).foregroundStyle(.white)
                                .frame(minWidth: 18, minHeight: 18).background(Theme.red, in: Circle())
                                .overlay(Circle().strokeBorder(Theme.bg, lineWidth: 2)).offset(x: 3, y: -3)
                        }
                    }
            }
            .accessibilityLabel(nonLette > 0 ? "Notifiche, \(nonLette) nuove" : "Notifiche")
            Button { profilo = true } label: {
                FotoSocio(id: jsoc.utente?.id, iniziali: jsoc.utente?.callsign ?? "?", lato: 44)
            }
            .accessibilityLabel("Profilo")
        }
    }

    // MARK: prossimo evento

    var senzaRisposta: [JEvento] { store.eventi.filter { $0.fase != 2 && !$0.proposto && !$0.annullato && $0.mia_risposta == nil } }

    var prossimoEvento: JEvento? {
        store.eventi
            .filter { $0.fase != 2 && !$0.proposto && !$0.annullato && ($0.dataFine ?? $0.dataInizio ?? .distantPast) >= Date() }
            .min { ($0.dataInizio ?? .distantFuture) < ($1.dataInizio ?? .distantFuture) }
    }

    @ViewBuilder var prossimo: some View {
        if let e = prossimoEvento {
            SchedaProssimo(evento: e, apri: { percorso.append(e) })
        } else {
            VStack(spacing: 6) {
                Image(systemName: "calendar.badge.plus").font(.system(size: 26)).foregroundStyle(Theme.olive)
                Text("Nessun evento in programma").font(.system(size: 15, weight: .heavy))
                Button("Proponi un evento") { vaiAllaScheda(Schede.eventi) }.font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.oliveBright)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 22)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.stroke))
        }
    }

    // MARK: da fare

    struct VoceDaFare: Identifiable {
        let id: String; let icona: String; let colore: Color; let testo: String; let destra: String; let azione: () -> Void
    }

    var daFare: [VoceDaFare] {
        var v: [VoceDaFare] = []
        let d = home.dati
        if let p = d?.direttivo?.proposte, p > 0 {
            v.append(VoceDaFare(id: "proposte", icona: "checkmark.seal", colore: Theme.amber, testo: p == 1 ? "1 evento da approvare" : "\(p) eventi da approvare", destra: "approva") { vaiAllaScheda(Schede.eventi) })
        }
        for e in senzaRisposta.prefix(3) where e.id != prossimoEvento?.id {
            v.append(VoceDaFare(id: "ev\(e.id)", icona: "questionmark.circle", colore: Theme.amber, testo: e.nome, destra: "rispondi") { percorso.append(e) })
        }
        for (i, a) in (d?.avvisi ?? []).filter({ $0.tipo != "evento" }).enumerated() {
            let (ic, col, dx): (String, Color, String) = {
                let t = a.testo.lowercased()
                if t.contains("certificat") { return ("cross.case", Theme.red, "scade") }
                if t.contains("quota") { return ("creditcard", Theme.amber, "da pagare") }
                if a.tipo == "promemoria" { return ("bell.badge", Theme.amber, "promemoria") }
                return ("exclamationmark.triangle", Theme.red, "")
            }()
            v.append(VoceDaFare(id: "av\(i)", icona: ic, colore: col, testo: a.testo, destra: dx) {
                if let id = a.evento, let e = store.eventi.first(where: { $0.id == id }) { percorso.append(e) } else { vaiAllaScheda(Schede.associazione) }
            })
        }
        if let s = d?.sondaggi_aperti, s > 0 {
            v.append(VoceDaFare(id: "sondaggi", icona: "chart.bar", colore: Theme.cyan, testo: s == 1 ? "1 sondaggio aperto" : "\(s) sondaggi aperti", destra: "vota") { vaiAllaScheda(Schede.associazione) })
        }
        return v
    }

    func daFareBox(max n: Int) -> some View {
        let voci = daFare
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("DA FARE").font(.system(size: 11.5, weight: .heavy)).tracking(0.8).foregroundStyle(Theme.dim)
                Spacer()
                if voci.count > n {
                    Button("altri \(voci.count - n) ›") { tuttiDaFare = true }.font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.oliveBright)
                }
            }
            if voci.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
                    Text("Tutto in ordine").font(.system(size: 13.5, weight: .semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).frame(height: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            }
            ForEach(voci.prefix(n)) { RigaDaFare(voce: $0) }
        }
    }

    // MARK: calendario e mappa piccoli

    var calendarioPiccolo: some View {
        Button { haptic(); calendario = true } label: {
            MeseMini(eventi: store.eventi)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Calendario del mese, apri")
    }

    var mappaPiccola: some View {
        MappaHomeMini(eventi: store.eventi.filter { $0.fase != 2 && $0.stato != "proposto" })
    }
}

// MARK: - Scheda del prossimo evento

struct SchedaProssimo: View {
    let evento: JEvento
    let apri: () -> Void
    @ObservedObject private var home = HomeModel.shared
    @State private var meteo: MeteoAdesso?
    @State private var pioggia: Double?
    @State private var invio = false

    var body: some View {
        let e = evento
        VStack(spacing: 0) {
            Button(action: apri) {
                ZStack(alignment: .topLeading) {
                    CopertinaEvento(evento: e, altezza: 96)
                    LinearGradient(colors: [.clear, Theme.surface.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                    HStack(alignment: .top) {
                        Text("PROSSIMO · \(e.nomeTipo)").font(Theme.mono(9.5, .heavy)).foregroundStyle(Theme.oliveBright)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Theme.bg.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.olive.opacity(0.5)))
                        Spacer()
                        ContoAllaRovescia(data: e.dataInizio)
                    }
                    .padding(12)
                    if let m = meteo {
                        HStack(spacing: 5) {
                            Image(systemName: "sun.max").foregroundStyle(Theme.amber)
                            Text(String(format: "%.0f° · vento %.0f km/h", m.temp, m.vento) + (pioggia.map { String(format: " · pioggia %.0f%%", $0) } ?? ""))
                        }
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .padding(12).frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
                .frame(height: 96).clipped()
                VStack(alignment: .leading, spacing: 3) {
                    Text(e.nome).font(.system(size: 20, weight: .black)).lineLimit(1).minimumScaleFactor(0.8)
                    Text(sottotitolo).font(.system(size: 12.5)).foregroundStyle(Theme.dim).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.top, 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Prossimo evento: \(e.nome), apri la scheda")

            HStack(spacing: 8) {
                tasto("Partecipo", on: e.mia_risposta == "si", pieno: true) { rispondi("si") }
                tasto("Non partecipo", on: e.mia_risposta == "no", pieno: false) { rispondi("no") }
            }
            .padding(.horizontal, 14).padding(.top, 10)
            Text(piede).font(.system(size: 11, weight: .bold)).foregroundStyle(e.mia_risposta == nil ? Theme.amber : Theme.dim)
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 14).padding(.vertical, 9)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.stroke))
        .task(id: e.id) { await caricaMeteo() }
    }

    var sottotitolo: String {
        var p: [String] = []
        if let d = evento.dataInizio { p.append(FormatiHome.giornoBreve.string(from: d)) }
        if let l = evento.luogo, !l.isEmpty { p.append(l) }
        if let n = evento.n_si, n > 0 { p.append("\(n) partecipano") }
        return p.joined(separator: " · ")
    }

    var piede: String {
        if let r = evento.mia_risposta {
            return r == "si" ? "Partecipi · tocca la scheda per i dettagli" : "Hai risposto · tocca la scheda per cambiare"
        }
        if let s = evento.dataScadenza, !evento.iscrizioniChiuse {
            return "Iscrizioni entro \(FormatiHome.scadenza.string(from: s)) · tocca la scheda per i dettagli"
        }
        return "Rispondi · tocca la scheda per i dettagli"
    }

    func tasto(_ t: String, on: Bool, pieno: Bool, _ f: @escaping () -> Void) -> some View {
        Button { haptic(.medium); f() } label: {
            HStack(spacing: 6) {
                if on { Image(systemName: "checkmark").font(.system(size: 13, weight: .black)) }
                Text(t).font(.system(size: 15, weight: .heavy))
            }
            .frame(maxWidth: .infinity).frame(height: 48)
            .foregroundStyle(pieno ? Color(red: 0.06, green: 0.08, blue: 0.05) : .white)
            .background(pieno ? Theme.olive : Theme.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on && !pieno ? Theme.red : Theme.stroke, lineWidth: on && !pieno ? 2 : 1))
            .opacity(invio ? 0.5 : 1)
        }
        .buttonStyle(PressStyle())
        .disabled(invio || evento.iscrizioniChiuse)
    }

    func rispondi(_ r: String) {
        invio = true
        Task { await home.rispondi(evento.id, r); invio = false }
    }

    func caricaMeteo() async {
        guard let la = evento.lat, let lo = evento.lon else { return }
        if let r = try? await MeteoServizio.carica(CLLocationCoordinate2D(latitude: la, longitude: lo)) {
            meteo = r.0
            let ore = r.1
            // pioggia: millimetri previsti nelle prossime ore → indicazione semplice
            let mm = ore.prefix(12).map(\.pioggia).max() ?? 0
            pioggia = min(100, mm * 40)
        }
    }
}

/// "1g 22h alla partenza" (si aggiorna ogni minuto)
struct ContoAllaRovescia: View {
    let data: Date?
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            if let d = data, d > ctx.date {
                let s = Int(d.timeIntervalSince(ctx.date))
                let g = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
                VStack(alignment: .trailing, spacing: 0) {
                    Text(g > 0 ? "\(g)g \(h)h" : "\(h)h \(m)m").font(Theme.mono(22, .heavy)).foregroundStyle(.white)
                    Text("alla partenza").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                }
            } else if data != nil {
                Text("IN CORSO").font(Theme.mono(13, .heavy)).foregroundStyle(Theme.green)
            }
        }
    }
}

struct RigaDaFare: View {
    let voce: HomeV3.VoceDaFare
    var body: some View {
        Button { haptic(); voce.azione() } label: {
            HStack(spacing: 10) {
                Image(systemName: voce.icona).font(.system(size: 15, weight: .semibold)).foregroundStyle(voce.colore).frame(width: 22)
                Text(voce.testo).font(.system(size: 14, weight: .heavy)).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 6)
                Text(voce.destra).font(.system(size: 11.5, weight: .heavy)).foregroundStyle(voce.colore)
            }
            .padding(.horizontal, 12).frame(height: 44)
            .background(voce.colore == Theme.red ? Theme.red.opacity(0.08) : Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(voce.colore == Theme.red ? Theme.red.opacity(0.45) : Theme.stroke))
        }
        .buttonStyle(PressStyle())
    }
}

struct ElencoDaFare: View {
    let voci: [HomeV3.VoceDaFare]
    let chiudi: () -> Void
    var body: some View {
        NavigationStack {
            ScrollView { VStack(spacing: 8) { ForEach(voci) { v in RigaDaFare(voce: HomeV3.VoceDaFare(id: v.id, icona: v.icona, colore: v.colore, testo: v.testo, destra: v.destra) { chiudi(); v.azione() }) } }.padding(14) }
                .background(Theme.bg.ignoresSafeArea())
                .navigationTitle("Da fare").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi", action: chiudi) } }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Mese piccolo (nella Home) e calendario intero

struct MeseMini: View {
    let eventi: [JEvento]
    var body: some View {
        let cal = Calendar(identifier: .iso8601)
        let oggi = Date()
        let inizio = cal.date(from: cal.dateComponents([.year, .month], from: oggi)) ?? oggi
        let giorni = cal.range(of: .day, in: .month, for: inizio)?.count ?? 30
        let vuoti = (cal.component(.weekday, from: inizio) + 5) % 7
        let delMese = eventi.filter { e in e.dataInizio.map { cal.isDate($0, equalTo: inizio, toGranularity: .month) } ?? false }
        VStack(spacing: 4) {
            HStack {
                Text(FormatiHome.mese.string(from: inizio).capitalized).font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                Spacer()
                Text("\(delMese.count) eventi ›").font(.system(size: 10.5, weight: .bold)).foregroundStyle(Theme.dim)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 1) {
                ForEach(0..<7, id: \.self) { i in
                    Text(["L", "M", "M", "G", "V", "S", "D"][i]).font(.system(size: 8.5, weight: .heavy)).foregroundStyle(Theme.dim)
                }
                ForEach(0..<vuoti, id: \.self) { _ in Color.clear.frame(height: 17) }
                ForEach(1...giorni, id: \.self) { d in
                    let data = cal.date(byAdding: .day, value: d - 1, to: inizio) ?? inizio
                    let ev = eventi.first { $0.nelGiorno(data) && !$0.proposto }
                    let isOggi = cal.isDateInToday(data)
                    VStack(spacing: 1) {
                        Text("\(d)").font(Theme.mono(10, .heavy)).foregroundStyle(isOggi ? Color.black : .white)
                            .frame(width: 19, height: 15)
                            .background(isOggi ? Theme.olive : .clear, in: RoundedRectangle(cornerRadius: 5))
                        Circle().fill(ev?.colore ?? .clear).frame(width: 4, height: 4)
                    }
                    .frame(height: 20)
                }
            }
        }
    }
}

struct CalendarioMese: View {
    let apri: (JEvento) -> Void
    @ObservedObject private var store = EventoStore.shared
    @Environment(\.dismiss) private var chiudi
    @State private var mese = Date()
    @State private var giorno = Date()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                griglia
                Text(FormatiHome.giornoLungo.string(from: giorno).uppercased()).font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.dim)
                let ev = store.eventi.filter { $0.nelGiorno(giorno) }.sorted { ($0.dataInizio ?? .distantPast) < ($1.dataInizio ?? .distantPast) }
                if ev.isEmpty { Text("Nessun evento").font(.system(size: 13)).foregroundStyle(Theme.dim) }
                ScrollView { VStack(spacing: 8) { ForEach(ev) { e in Button { apri(e) } label: { RigaEventoV2(evento: e) }.buttonStyle(PressStyle()) } } }
            }
            .padding(14)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Calendario").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { chiudi() } } }
        }
        .preferredColorScheme(.dark)
    }

    var griglia: some View {
        let cal = Calendar(identifier: .iso8601)
        let inizio = cal.date(from: cal.dateComponents([.year, .month], from: mese)) ?? mese
        let giorni = cal.range(of: .day, in: .month, for: inizio)?.count ?? 30
        let vuoti = (cal.component(.weekday, from: inizio) + 5) % 7
        return VStack(spacing: 8) {
            HStack {
                Button { mese = cal.date(byAdding: .month, value: -1, to: mese) ?? mese } label: { Image(systemName: "chevron.left").frame(width: 44, height: 36) }
                    .accessibilityLabel("Mese precedente")
                Spacer()
                Text(inizio.formatted(.dateTime.month(.wide).year()).capitalized).font(.system(size: 16, weight: .heavy))
                Spacer()
                Button { mese = cal.date(byAdding: .month, value: 1, to: mese) ?? mese } label: { Image(systemName: "chevron.right").frame(width: 44, height: 36) }
                    .accessibilityLabel("Mese successivo")
            }
            .foregroundStyle(Theme.dim)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(0..<7, id: \.self) { i in Text(["L", "M", "M", "G", "V", "S", "D"][i]).font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.dim) }
                ForEach(0..<vuoti, id: \.self) { _ in Color.clear.frame(height: 42) }
                ForEach(1...giorni, id: \.self) { d in
                    let data = cal.date(byAdding: .day, value: d - 1, to: inizio) ?? inizio
                    let scelto = cal.isDate(data, inSameDayAs: giorno)
                    let colori = Array(store.eventi.filter { $0.nelGiorno(data) }.map(\.colore).prefix(3))
                    Button { haptic(.soft); giorno = data } label: {
                        VStack(spacing: 3) {
                            Text("\(d)").font(Theme.mono(13, .heavy)).foregroundStyle(scelto ? Color.black : .white)
                            HStack(spacing: 2) { ForEach(colori.indices, id: \.self) { i in Circle().fill(colori[i]).frame(width: 5, height: 5) } }.frame(height: 5)
                        }
                        .frame(maxWidth: .infinity).frame(height: 42)
                        .background(scelto ? Theme.olive : .clear, in: RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(cal.isDateInToday(data) && !scelto ? Theme.olive : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.stroke))
    }
}

// MARK: - Mappa piccola dei campi (apre la Mappa)

struct MappaHomeMini: View {
    let eventi: [JEvento]
    @ObservedObject private var campi = CampiStore.shared
    var body: some View {
        Button { haptic(); EventoStore.shared.apriPersonale(); vaiAllaScheda(Schede.mappa) } label: {
            ZStack(alignment: .topLeading) {
                MappaStatica(campi: campi.dati, eventi: eventi).allowsHitTesting(false)
                Text("Campi e luoghi").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                    .shadow(color: .black, radius: 3).padding(10)
                Text("\(campi.dati?.campi.count ?? 0) campi · sede · \(eventi.count) eventi ›")
                    .font(.system(size: 10.5, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Theme.bg.opacity(0.8), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Mappa dei campi e degli eventi, apri la mappa")
        .task { await campi.aggiorna() }
    }
}

// MARK: - Centro notifiche (dalla campanella)

struct CentroNotifiche: View {
    let apri: (JEvento) -> Void
    @ObservedObject private var store = EventoStore.shared
    @ObservedObject private var home = HomeModel.shared
    @Environment(\.dismiss) private var chiudi
    @AppStorage("notifiche.nascoste") private var nascosteTesto = ""
    @AppStorage("notifiche.lette") private var letteTesto = ""
    @State private var filtro = 0

    struct Voce: Identifiable { let id: String; let icona: String; let colore: Color; let titolo: String; let testo: String; let evento: JEvento? }

    var nascoste: Set<String> { Set(nascosteTesto.split(separator: "|").map(String.init)) }
    var lette: Set<String> { Set(letteTesto.split(separator: "|").map(String.init)) }

    var voci: [Voce] {
        var v: [Voce] = []
        for e in store.eventi where e.fase != 2 && !e.proposto && !e.annullato && e.mia_risposta == nil {
            v.append(Voce(id: "ev\(e.id)", icona: "calendar.badge.exclamationmark", colore: Theme.amber, titolo: e.nome, testo: "Non hai ancora risposto", evento: e))
        }
        for a in home.dati?.avvisi ?? [] {
            let e = a.evento.flatMap { id in store.eventi.first { $0.id == id } }
            v.append(Voce(id: "av" + a.testo.replacingOccurrences(of: "|", with: "/"), icona: a.tipo == "promemoria" ? "bell.badge" : "exclamationmark.triangle",
                          colore: a.tipo == "promemoria" ? Theme.amber : Theme.red, titolo: e?.nome ?? "Associazione", testo: a.testo, evento: e))
        }
        return v.filter { !nascoste.contains($0.id) && (filtro == 0 || !lette.contains($0.id)) }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Filtro", selection: $filtro) { Text("Tutte").tag(0); Text("Non lette").tag(1) }
                    .pickerStyle(.segmented).listRowBackground(Color.clear)
                if voci.isEmpty {
                    Text("Nessuna notifica").foregroundStyle(Theme.dim).listRowBackground(Color.clear)
                }
                ForEach(voci) { n in
                    Button {
                        segnaLetta(n.id)
                        if let e = n.evento { apri(e) }
                    } label: {
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: n.icona).foregroundStyle(n.colore).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(n.titolo).font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                                Text(n.testo).font(.system(size: 13)).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            if !lette.contains(n.id) { Circle().fill(Theme.oliveBright).frame(width: 8, height: 8).padding(.top, 5) }
                        }
                    }
                    .listRowBackground(Theme.surface)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { nascondi(n.id) } label: { Label("Elimina", systemImage: "trash") }
                    }
                    .swipeActions(edge: .leading) {
                        Button { segnaLetta(n.id) } label: { Label("Letta", systemImage: "checkmark") }.tint(Theme.olive)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Notifiche").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Segna tutte lette") { letteTesto = lette.union(voci.map(.id)).joined(separator: "|") }.disabled(voci.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { chiudi() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    func segnaLetta(_ id: String) { letteTesto = lette.union([id]).joined(separator: "|") }
    func nascondi(_ id: String) { nascosteTesto = nascoste.union([id]).joined(separator: "|") }
}
