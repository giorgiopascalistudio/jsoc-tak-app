import SwiftUI
import MapKit

// MARK: - Home in una schermata: riproduce la tavola 29 (telefono, 390 pt) e la tavola 67 (iPad orizzontale).
// Le misure (pt), i colori e i testi sono quelli delle tavole della tela.

/// formattatori fissi: mai crearli dentro body (causa dei blocchi del 19-20/11)
enum FormatiHome {
    static let giornoLungo: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "EEEE d MMMM"; return f }()
    static let giornoBreve: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "EEE d MMM · HH:mm"; return f }()
    static let mese: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "LLLL"; return f }()
    static let meseAnno: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "LLLL yyyy"; return f }()
    static let ora: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "HH:mm"; return f }()
    static let giornoMese: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "d MMM"; return f }()
}

extension Notification.Name {
    static let apriNotifiche = Notification.Name("apriNotifiche")
    static let apriProfilo = Notification.Name("apriProfilo")
}

/// tavola: "Dom 22 nov · 08:30 · Campo Calimera · 12 partecipano"
func testoQuando(_ e: JEvento) -> String {
    var p: [String] = []
    if let d = e.dataInizio { p.append(FormatiHome.giornoBreve.string(from: d).prefix(1).uppercased() + FormatiHome.giornoBreve.string(from: d).dropFirst()) }
    if let l = e.luogo, !l.isEmpty { p.append(l) }
    if let n = e.n_si, n > 0 { p.append("\(n) partecipano") }
    return p.joined(separator: " · ")
}

/// tavola: "Iscrizioni entro domani alle 20:00"
func testoScadenza(_ e: JEvento) -> String? {
    guard let s = e.dataScadenza, !e.iscrizioniChiuse else { return nil }
    let cal = Calendar.current
    let giorno = cal.isDateInToday(s) ? "oggi" : cal.isDateInTomorrow(s) ? "domani" : FormatiHome.giornoMese.string(from: s)
    return "Iscrizioni entro \(giorno) alle \(FormatiHome.ora.string(from: s))"
}

struct HomeV3: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var store = EventoStore.shared
    @ObservedObject private var home = HomeModel.shared
    @Environment(\.horizontalSizeClass) private var classe
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
        .onReceive(NotificationCenter.default.publisher(for: .apriNotifiche)) { _ in notifiche = true }
        .onReceive(NotificationCenter.default.publisher(for: .apriProfilo)) { _ in profilo = true }
        .task { await home.aggiorna() }
    }

    @ViewBuilder var contenuto: some View {
        if classe == .regular { contenutoIPad } else { contenutoTelefono }
    }

    // MARK: telefono (tavola 29)

    var contenutoTelefono: some View {
        VStack(alignment: .leading, spacing: 0) {
            // intestazione: top 54 (7 sotto la barra di stato), lati 18
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(FormatiHome.giornoLungo.string(from: Date()).uppercased())
                        .font(.system(size: 11, weight: .heavy)).tracking(0.88).foregroundStyle(Theme.dim)
                    Text("Ciao, \(jsoc.utente?.callsign ?? "")").font(.system(size: 28, weight: .black)).tracking(-0.56)
                        .foregroundStyle(Theme.testo).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer()
                HStack(spacing: 10) {
                    TastoCampanella(numero: nonLette, lato: 42) { haptic(); notifiche = true }
                    Button { profilo = true } label: { Avatar(lato: 42, bordo: 2, testo: 14) }.accessibilityLabel("Profilo")
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 7)
            // corpo: top 112, lati 14, spazio 12
            VStack(alignment: .leading, spacing: 12) {
                SchedaProssimo(evento: prossimoEvento, grande: false, apri: apriProssimo)
                daFareTelefono
                HStack(spacing: 10) {
                    Button { haptic(); calendario = true } label: { MeseMini(eventi: store.eventi) }
                        .buttonStyle(PressStyle()).accessibilityLabel("Apri il calendario")
                    MappaHomeMini(eventi: eventiFuturi, grande: false)
                }
                .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 62)      // tavola: il corpo finisce 96 pt dal fondo (34 sono la barretta di sistema)
        }
    }

    // MARK: iPad (tavola 67): due colonne, la barra di navigazione è la colonna a sinistra

    var contenutoIPad: some View {
        GeometryReader { g in
            let largo = g.size.width > g.size.height
            let destra = largo ? min(400, g.size.width * 0.36) : 0
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(FormatiHome.giornoLungo.string(from: Date()).uppercased())
                            .font(.system(size: 12, weight: .heavy)).tracking(0.96).foregroundStyle(Theme.dim)
                        Text("Ciao, \(jsoc.utente?.callsign ?? "")").font(.system(size: 30, weight: .black)).tracking(-0.6).foregroundStyle(Theme.testo)
                    }
                    SchedaProssimo(evento: prossimoEvento, grande: true, apri: apriProssimo)
                    if largo { daFareIPad } else {
                        daFareIPad.fixedSize(horizontal: false, vertical: true)
                        HStack(alignment: .top, spacing: 14) { calendarioIPad; MappaHomeMini(eventi: eventiFuturi, grande: true) }.frame(maxHeight: .infinity)
                    }
                }
                if largo {
                    VStack(spacing: 12) {
                        Color.clear.frame(height: 52)
                        calendarioIPad
                        MappaHomeMini(eventi: eventiFuturi, grande: true)
                    }
                    .frame(width: destra)
                }
            }
            .padding(.leading, 30).padding(.trailing, 24).padding(.top, 26).padding(.bottom, 22)
        }
    }

    // MARK: dati

    var nonLette: Int { (home.dati?.avvisi ?? []).count + senzaRisposta.count }
    var senzaRisposta: [JEvento] { store.eventi.filter { $0.fase != 2 && !$0.proposto && !$0.annullato && $0.mia_risposta == nil } }
    var eventiFuturi: [JEvento] { store.eventi.filter { $0.fase != 2 && $0.stato != "proposto" } }
    var prossimoEvento: JEvento? {
        store.eventi
            .filter { $0.fase != 2 && !$0.proposto && !$0.annullato && ($0.dataFine ?? $0.dataInizio ?? .distantPast) >= Date() }
            .min { ($0.dataInizio ?? .distantFuture) < ($1.dataInizio ?? .distantFuture) }
    }
    func apriProssimo() { if let e = prossimoEvento { percorso.append(e) } else { vaiAllaScheda(Schede.eventi) } }

    struct VoceDaFare: Identifiable {
        let id: String; let icona: String; let colore: Color; let testo: String; let destra: String; let azione: () -> Void
    }

    var daFare: [VoceDaFare] {
        var v: [VoceDaFare] = []
        let d = home.dati
        if let p = d?.direttivo?.proposte, p > 0 {
            v.append(VoceDaFare(id: "proposte", icona: Ic.spunta, colore: Theme.amber, testo: p == 1 ? "1 evento da approvare" : "\(p) eventi da approvare", destra: "approva") { vaiAllaScheda(Schede.eventi) })
        }
        // icone come le tavole: quota = carta, certificato = cartellina (telefono) o cuore (iPad), sondaggio = barre, avviso = aereo di carta
        let avvisi = (d?.avvisi ?? []).filter { $0.tipo != "evento" }
        for (i, a) in avvisi.enumerated() {
            let t = a.testo.lowercased()
            let (ic, col, dx): (String, Color, String) =
                a.tipo == "certificato" || t.contains("certificat") ? (classe == .regular ? Ic.cuore : Ic.cartellina, Theme.red, "scade") :
                a.tipo == "quota" || t.contains("quota") ? (Ic.cartaTonda, Theme.amber, "da pagare") :
                a.tipo == "tessera" ? (Ic.carta, Theme.amber, "scade") :
                a.tipo == "sondaggio" ? (Ic.sondaggio, Theme.cyan, "vota") :
                a.tipo == "promemoria" ? (Ic.calendario, Theme.amber, "rispondi") : (Ic.invia, Theme.amber, "Ho letto")
            v.append(VoceDaFare(id: "av\(i)", icona: ic, colore: col, testo: a.testo, destra: a.destra ?? dx) {
                if let id = a.evento, let e = store.eventi.first(where: { $0.id == id }) { percorso.append(e) } else { vaiAllaScheda(Schede.associazione) }
            })
        }
        // server vecchio (prima della 0.19): solo il numero dei sondaggi
        if let s = d?.sondaggi_aperti, s > 0, !avvisi.contains(where: { $0.tipo == "sondaggio" }) {
            v.append(VoceDaFare(id: "sondaggi", icona: Ic.sondaggio, colore: Theme.cyan, testo: s == 1 ? "Sondaggio aperto" : "\(s) sondaggi aperti", destra: "vota") { vaiAllaScheda(Schede.associazione) })
        }
        for e in senzaRisposta where e.id != prossimoEvento?.id && !avvisi.contains(where: { $0.evento == e.id }) {
            v.append(VoceDaFare(id: "ev\(e.id)", icona: Ic.calendario, colore: Theme.amber, testo: e.nome, destra: "rispondi") { percorso.append(e) })
        }
        return v
    }

    // tavola 29: "DA FARE" + "altri N ›", righe 44 pt
    var daFareTelefono: some View {
        let voci = daFare
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("DA FARE").font(.system(size: 11.5, weight: .heavy)).tracking(0.69).foregroundStyle(Theme.dim)
                Spacer()
                if voci.count > 3 {
                    Button("altri \(voci.count - 3) ›") { tuttiDaFare = true }.font(.system(size: 11.5, weight: .bold)).foregroundStyle(Theme.oliveBright)
                }
            }
            .padding(.horizontal, 2)
            if voci.isEmpty { RigaDaFare(voce: VoceDaFare(id: "ok", icona: Ic.spunta, colore: Theme.green, testo: "Tutto in ordine", destra: "") {}) }
            ForEach(voci.prefix(3)) { RigaDaFare(voce: $0) }
        }
    }

    // tavola 67: riquadro con titolo e righe più grandi
    var daFareIPad: some View {
        let voci = daFare
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("DA FARE").font(.system(size: 12, weight: .heavy)).tracking(0.72).foregroundStyle(Theme.dim)
                Spacer()
                Button("tutto ›") { tuttiDaFare = true }.font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.oliveBright)
            }
            .padding(.bottom, 2)
            if voci.isEmpty { RigaDaFare(voce: VoceDaFare(id: "ok", icona: Ic.spunta, colore: Theme.green, testo: "Tutto in ordine", destra: "") {}, grande: true) }
            ForEach(voci.prefix(6)) { RigaDaFare(voce: $0, grande: true) }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.stroke))
    }

    var calendarioIPad: some View {
        Button { haptic(); calendario = true } label: { MeseIPad(eventi: store.eventi, prossimo: prossimoEvento) }
            .buttonStyle(PressStyle()).accessibilityLabel("Apri il calendario")
    }
}

// MARK: - pezzi comuni

/// avatar della tavola: cerchio con bordo verde, iniziali o foto
struct Avatar: View {
    @ObservedObject private var jsoc = JsocClient.shared
    var lato: CGFloat = 42
    var bordo: CGFloat = 2
    var testo: CGFloat = 14
    var body: some View {
        FotoSocio(id: jsoc.utente?.id, iniziali: jsoc.utente?.callsign ?? "?", lato: lato)
            .overlay(Circle().strokeBorder(Theme.olive, lineWidth: bordo))
    }
}

struct TastoCampanella: View {
    let numero: Int
    var lato: CGFloat = 42
    let azione: () -> Void
    var body: some View {
        Button(action: azione) {
            IconaTela(d: Ic.campanella, colore: Theme.testo, lato: lato * 0.45)
                .frame(width: lato, height: lato)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.stroke))
                .overlay(alignment: .topTrailing) {
                    if numero > 0 {
                        Text("\(numero)").font(.system(size: 10.5, weight: .black)).foregroundStyle(.white)
                            .padding(.horizontal, 4).frame(minWidth: 18, minHeight: 18)
                            .background(Theme.red, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.bg, lineWidth: 2))
                            .offset(x: 2, y: -2)
                    }
                }
        }
        .accessibilityLabel(numero > 0 ? "Notifiche, \(numero) non lette" : "Notifiche")
    }
}

// MARK: - Scheda del prossimo evento (tavola 29: alto 92; tavola 67: alto 150, nome e tasti sulla stessa riga)

struct SchedaProssimo: View {
    let evento: JEvento?
    let grande: Bool
    let apri: () -> Void
    @ObservedObject private var home = HomeModel.shared
    @State private var meteo: String?
    @State private var invio = false

    var body: some View {
        if let e = evento { scheda(e) } else { vuota }
    }

    var vuota: some View {
        VStack(spacing: 6) {
            Text("Nessun evento in programma").font(.system(size: 16, weight: .heavy)).foregroundStyle(Theme.testo)
            Button("Proponi un evento ›") { vaiAllaScheda(Schede.eventi) }.font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.oliveBright)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.olive.opacity(0.3)))
    }

    func scheda(_ e: JEvento) -> some View {
        VStack(spacing: 0) {
            Button(action: apri) { copertina(e) }.buttonStyle(.plain)
                .accessibilityLabel("Prossimo evento \(e.nome), apri la scheda")
            if grande {
                HStack(spacing: 16) {
                    Button(action: apri) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(e.nome).font(.system(size: 24, weight: .black)).foregroundStyle(Theme.testo).lineLimit(1)
                            Text([testoQuando(e), testoScadenza(e)?.lowercased()].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 13.5)).foregroundStyle(Theme.dim).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    tasto("Partecipo", primario: true, on: e.mia_risposta == "si", altezza: 48, carattere: 14.5) { rispondi(e, "si") }.fixedSize()
                    tasto("Non partecipo", primario: false, on: e.mia_risposta == "no", altezza: 48, carattere: 14.5) { rispondi(e, "no") }.fixedSize()
                }
                .padding(.horizontal, 18).padding(.vertical, 16)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Button(action: apri) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(e.nome).font(.system(size: 18, weight: .black)).tracking(-0.18).foregroundStyle(Theme.testo).lineLimit(1)
                            Text(testoQuando(e)).font(.system(size: 12)).foregroundStyle(Theme.dim).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: 8) {
                        tasto("Partecipo", primario: true, on: e.mia_risposta == "si", altezza: 44, carattere: 14) { rispondi(e, "si") }
                        tasto("Non partecipo", primario: false, on: e.mia_risposta == "no", altezza: 44, carattere: 14) { rispondi(e, "no") }
                    }
                    .padding(.top, 12)
                    Text(piede(e)).font(.system(size: 10.5, weight: .bold)).foregroundStyle(Theme.amber)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity).padding(.top, 8)
                }
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 14)
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.olive.opacity(0.3)))
        .task(id: e.id) { await caricaMeteo(e) }
    }

    /// parte alta: fondo verde scuro con curve di livello (o la copertina dell'evento), etichetta, conto alla rovescia, meteo
    func copertina(_ e: JEvento) -> some View {
        ZStack(alignment: .topLeading) {
            Color(hex: 0x26301A)
            CurveCopertina().stroke(Theme.oliveBright.opacity(0.2), lineWidth: 1.5)
            if e.copertina != nil {
                CopertinaEvento(evento: e, altezza: grande ? 150 : 92)
                LinearGradient(colors: [Color.black.opacity(0.35), .clear, Color.black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
            }
            Text("PROSSIMO · \(e.nomeTipo)").font(Theme.mono(9.5, .heavy)).foregroundStyle(Theme.oliveBright)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Theme.bg.opacity(0.7), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.olive.opacity(0.4)))
                .padding(.leading, grande ? 18 : 14).padding(.top, grande ? 14 : 12)
            ContoAllaRovescia(data: e.dataInizio, grande: grande)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, grande ? 18 : 14).padding(.top, grande ? 12 : 10)
            if let m = meteo {
                HStack(spacing: 6) {
                    IconaTela(d: Ic.sole, colore: Theme.amber, lato: 15)
                    Text(m)
                }
                .font(.system(size: grande ? 13 : 11.5, weight: .bold)).foregroundStyle(Color(hex: 0xE4E7DA))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, grande ? 18 : 14).padding(.bottom, grande ? 14 : 10)
            }
        }
        .frame(height: grande ? 150 : 92)
        .clipped()
    }

    func piede(_ e: JEvento) -> String {
        if let r = e.mia_risposta { return r == "si" ? "Partecipi · tocca la scheda per i dettagli" : "Hai risposto · tocca la scheda per cambiare" }
        if let s = testoScadenza(e) { return "\(s) · tocca la scheda per i dettagli" }
        return "Tocca la scheda per i dettagli"
    }

    func tasto(_ t: String, primario: Bool, on: Bool, altezza: CGFloat, carattere: CGFloat, _ f: @escaping () -> Void) -> some View {
        Button { haptic(.medium); f() } label: {
            HStack(spacing: 5) {
                if on { Image(systemName: "checkmark").font(.system(size: carattere - 1, weight: .black)) }
                Text(t).font(.system(size: carattere, weight: primario ? .black : .heavy))
            }
            .padding(.horizontal, grande ? 18 : 0)
            .frame(maxWidth: grande ? nil : .infinity).frame(height: altezza)
            .foregroundStyle(primario ? Theme.scuro : Theme.testo)
            .background(primario ? Theme.olive : Color.clear, in: RoundedRectangle(cornerRadius: grande ? 14 : 13, style: .continuous))
            .overlay {
                if !primario {
                    RoundedRectangle(cornerRadius: grande ? 14 : 13, style: .continuous)
                        .strokeBorder(on ? Theme.red : Theme.testo.opacity(0.18), lineWidth: on ? 2 : 1)
                }
            }
            .opacity(invio ? 0.5 : 1)
        }
        .buttonStyle(PressStyle())
        .disabled(invio || (evento?.iscrizioniChiuse ?? false))
    }

    func rispondi(_ e: JEvento, _ r: String) {
        invio = true
        Task { await home.rispondi(e.id, r); invio = false }
    }

    /// tavola: "14° · vento 12 km/h · pioggia 10%"
    func caricaMeteo(_ e: JEvento) async {
        guard let la = e.lat, let lo = e.lon,
              let r = try? await MeteoServizio.carica(CLLocationCoordinate2D(latitude: la, longitude: lo)) else { return }
        let mm = r.1.prefix(12).map(\.pioggia).max() ?? 0
        meteo = String(format: "%.0f° · vento %.0f km/h · pioggia %.0f%%", r.0.temp, r.0.vento, min(100, mm * 40))
    }
}

/// tre curve di livello leggere (come la tavola)
struct CurveCopertina: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let sx = r.width / 362, sy = r.height / 92
        for (y0, y1, y2, y3, y4) in [(70.0, 50.0, 78.0, 58.0, 46.0), (84, 66, 90, 72, 62), (52, 38, 60, 42, 30)] {
            p.move(to: CGPoint(x: 0, y: y0 * sy))
            p.addCurve(to: CGPoint(x: 170 * sx, y: y3 * sy), control1: CGPoint(x: 60 * sx, y: y1 * sy), control2: CGPoint(x: 110 * sx, y: y2 * sy))
            p.addQuadCurve(to: CGPoint(x: r.width, y: y4 * sy), control: CGPoint(x: 280 * sx, y: (y3 - 28) * sy))
        }
        return p
    }
}

/// "1g 22h / alla partenza" (si aggiorna ogni minuto)
struct ContoAllaRovescia: View {
    let data: Date?
    var grande = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            if let d = data, d > ctx.date {
                let s = Int(d.timeIntervalSince(ctx.date))
                let g = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
                VStack(alignment: .trailing, spacing: 2) {
                    Text(g > 0 ? "\(g)g \(h)h" : "\(h)h \(m)m").font(Theme.mono(grande ? 30 : 22, .heavy)).foregroundStyle(Theme.testo)
                    Text("alla partenza").font(.system(size: grande ? 11 : 10, weight: .bold)).foregroundStyle(Theme.testo2)
                }
            } else if data != nil {
                Text("IN CORSO").font(Theme.mono(grande ? 20 : 15, .heavy)).foregroundStyle(Theme.green)
            }
        }
    }
}

struct RigaDaFare: View {
    let voce: HomeV3.VoceDaFare
    var grande = false
    var body: some View {
        let rosso = voce.colore == Theme.red
        Button { haptic(); voce.azione() } label: {
            HStack(spacing: grande ? 12 : 10) {
                IconaTela(d: voce.icona, colore: voce.colore, lato: grande ? 20 : 18)
                Text(voce.testo).font(.system(size: grande ? 14.5 : 13, weight: .bold)).foregroundStyle(Theme.testo).lineLimit(1)
                Spacer(minLength: 6)
                Text(voce.destra).font(.system(size: grande ? 12 : 10.5, weight: .heavy)).foregroundStyle(voce.colore)
            }
            .padding(.horizontal, grande ? 14 : 12)
            .frame(height: grande ? 46 : 44)
            .background(grande ? Theme.barra : (rosso ? Color(hex: 0x1C1411) : Theme.surface), in: RoundedRectangle(cornerRadius: grande ? 14 : 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: grande ? 14 : 13, style: .continuous)
                .strokeBorder(grande ? voce.colore.opacity(0.27) : (rosso ? Theme.red.opacity(0.35) : Theme.stroke)))
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

// MARK: - Calendario piccolo (tavola 29) e del riquadro iPad (tavola 67)

struct MeseMini: View {
    let eventi: [JEvento]
    var body: some View {
        let cal = Calendar(identifier: .iso8601)
        let oggi = Date()
        let inizio = cal.date(from: cal.dateComponents([.year, .month], from: oggi)) ?? oggi
        let giorni = cal.range(of: .day, in: .month, for: inizio)?.count ?? 30
        let vuoti = (cal.component(.weekday, from: inizio) + 5) % 7
        let delMese = eventi.filter { e in !e.proposto && (e.dataInizio.map { cal.isDate($0, equalTo: inizio, toGranularity: .month) } ?? false) }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(FormatiHome.mese.string(from: inizio).capitalized).font(.system(size: 12.5, weight: .heavy)).foregroundStyle(Theme.testo)
                Spacer()
                Text("\(delMese.count) eventi ›").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.dim)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 1) {
                ForEach(0..<7, id: \.self) { i in
                    Text(["L", "M", "M", "G", "V", "S", "D"][i]).font(.system(size: 8.5, weight: .heavy)).foregroundStyle(Theme.dim)
                }
                ForEach(0..<vuoti, id: \.self) { _ in Color.clear.frame(height: 19) }
                ForEach(1...giorni, id: \.self) { d in
                    let data = cal.date(byAdding: .day, value: d - 1, to: inizio) ?? inizio
                    let ev = eventi.first { $0.nelGiorno(data) && !$0.proposto }
                    let isOggi = cal.isDateInToday(data)
                    VStack(spacing: 1) {
                        Text("\(d)").font(Theme.mono(9.5, .heavy)).foregroundStyle(isOggi ? Theme.scuro : Theme.testo)
                        Circle().fill(isOggi ? Theme.scuro : (ev?.colore ?? .clear)).frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity).frame(height: 19)
                    .background(isOggi ? Theme.olive : .clear, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9).padding(.top, 10).padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke))
    }
}

struct MeseIPad: View {
    let eventi: [JEvento]
    let prossimo: JEvento?
    var body: some View {
        let cal = Calendar(identifier: .iso8601)
        let oggi = Date()
        let inizio = cal.date(from: cal.dateComponents([.year, .month], from: oggi)) ?? oggi
        let giorni = cal.range(of: .day, in: .month, for: inizio)?.count ?? 30
        let vuoti = (cal.component(.weekday, from: inizio) + 5) % 7
        let delMese = eventi.filter { e in !e.proposto && (e.dataInizio.map { cal.isDate($0, equalTo: inizio, toGranularity: .month) } ?? false) }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(FormatiHome.meseAnno.string(from: inizio).uppercased()).font(.system(size: 12, weight: .heavy)).tracking(0.72).foregroundStyle(Theme.dim)
                Spacer()
                Text("\(delMese.count) eventi ›").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.oliveBright)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 3) {
                ForEach(0..<7, id: \.self) { i in
                    Text(["L", "M", "M", "G", "V", "S", "D"][i]).font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.dim)
                }
                ForEach(0..<vuoti, id: \.self) { _ in Color.clear.frame(height: 38) }
                ForEach(1...giorni, id: \.self) { d in
                    let data = cal.date(byAdding: .day, value: d - 1, to: inizio) ?? inizio
                    let ev = eventi.first { $0.nelGiorno(data) && !$0.proposto }
                    let scelto = prossimo?.nelGiorno(data) ?? false
                    let isOggi = cal.isDateInToday(data)
                    VStack(spacing: 3) {
                        Text("\(d)").font(Theme.mono(13, .heavy)).foregroundStyle(scelto ? Theme.scuro : Theme.testo)
                        Circle().fill(ev != nil && !scelto ? ev!.colore : .clear).frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity).frame(height: 38)
                    .background(scelto ? Theme.olive : .clear, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isOggi && !scelto ? Theme.olive : .clear, lineWidth: 1.5))
                }
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.stroke))
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
                Text(FormatiHome.meseAnno.string(from: inizio).capitalized).font(.system(size: 16, weight: .heavy))
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
                            Text("\(d)").font(Theme.mono(13, .heavy)).foregroundStyle(scelto ? Theme.scuro : Theme.testo)
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

// MARK: - Mappa piccola dei campi (tavola 29: "Campi e luoghi"; tavola 67: con "tocca per aprire la mappa")

struct MappaHomeMini: View {
    let eventi: [JEvento]
    var grande = false
    @ObservedObject private var campi = CampiStore.shared
    var body: some View {
        let piede = "\(campi.dati?.campi.count ?? 0) campi · sede · \(eventi.count) eventi" + (grande ? " · tocca per aprire la mappa ›" : " ›")
        Button { haptic(); EventoStore.shared.apriPersonale(); vaiAllaScheda(Schede.mappa) } label: {
            ZStack(alignment: .topLeading) {
                Color(hex: 0x2C3021)
                // mappa vera, toni del verde della tavola
                MappaStatica(campi: campi.dati, eventi: eventi, scura: true)
                    .allowsHitTesting(false)
                    .saturation(0.15)
                    .colorMultiply(Color(hex: 0xC4CCA6))
                Text("Campi e luoghi").font(.system(size: grande ? 14 : 12.5, weight: .heavy)).foregroundStyle(Theme.testo)
                    .shadow(color: .black, radius: 3, y: 1)
                    .padding(.leading, grande ? 14 : 10).padding(.top, grande ? 12 : 10)
                Text(piede).font(.system(size: grande ? 12 : 10.5, weight: .bold)).foregroundStyle(Theme.testo2)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity).frame(height: grande ? 32 : 26)
                    .background(Theme.bg.opacity(grande ? 0.8 : 0.78), in: RoundedRectangle(cornerRadius: grande ? 10 : 9))
                    .padding(grande ? 12 : 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: grande ? 20 : 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: grande ? 20 : 18, style: .continuous).strokeBorder(Theme.stroke))
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
                    Button("Segna tutte lette") { letteTesto = lette.union(voci.map { $0.id }).joined(separator: "|") }.disabled(voci.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { chiudi() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    func segnaLetta(_ id: String) { letteTesto = lette.union([id]).joined(separator: "|") }
    func nascondi(_ id: String) { nascosteTesto = nascoste.union([id]).joined(separator: "|") }
}
