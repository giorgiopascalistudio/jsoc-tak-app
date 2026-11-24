import SwiftUI
import CoreLocation

// MARK: - Coordinate (tavola 65): incolli qualsiasi formato → lo riconosce, mostra lo stesso punto in tutti i formati
// con il tasto copia, poi In mappa / Naviga / Invia. Conversioni: UTM.swift, Geo.mgrs, Coordinate.mgrs.

enum FormatiCoordinate {
    struct Riconosciuto { let punto: CLLocationCoordinate2D; let formato: String }

    // MARK: lettura di qualsiasi formato

    static func riconosci(_ testo: String) -> Riconosciuto? {
        let t = testo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if let c = plusCode(t) { return .init(punto: c, formato: "Plus code") }
        if let c = Coordinate.mgrs(t) { return .init(punto: c, formato: "MGRS") }
        if let u = UTM.parse(t) {
            let (la, lo) = UTM.toLatLon(u)
            return .init(punto: .init(latitude: la, longitude: lo), formato: "UTM")
        }
        return numerico(t)
    }

    /// gradi decimali, gradi e minuti, gradi minuti secondi (con N/S/E/W/O o segno meno)
    static func numerico(_ testo: String) -> Riconosciuto? {
        var t = testo.uppercased()
        // "40,2731 18,1447": virgola decimale
        if !t.contains("."), let re = try? NSRegularExpression(pattern: #"^\s*-?\d+,\d+\s+-?\d+,\d+\s*$"#),
           re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil {
            t = t.replacingOccurrences(of: ",", with: ".")
        }
        guard let re = try? NSRegularExpression(pattern: #"(-?)(\d+(?:\.\d+)?)"#) else { return nil }
        let ns = t as NSString
        let trovati = re.matches(in: t, range: NSRange(location: 0, length: ns.length))
        var numeri: [(Double, Bool, Int)] = []      // valore, negativo, posizione
        for m in trovati {
            guard let v = Double(ns.substring(with: m.range(at: 2))) else { continue }
            numeri.append((v, m.range(at: 1).length > 0, m.range.location))
        }
        // emisferi: lettere isolate N S E W O
        var lettere: [Character] = []
        let a = Array(t)
        for i in a.indices where "NSEWO".contains(a[i]) {
            let prima: Character = i > 0 ? a[i - 1] : " "
            let dopo: Character = i + 1 < a.count ? a[i + 1] : " "
            if !prima.isLetter && !dopo.isLetter { lettere.append(a[i]) }
        }
        let formato: String
        var lat: Double, lon: Double
        func gm(_ a: ArraySlice<(Double, Bool, Int)>) -> Double {
            var v = 0.0, k = 1.0
            for n in a { v += n.0 / k; k *= 60 }
            return a.first?.1 == true ? -v : v
        }
        switch numeri.count {
        case 2: formato = "gradi decimali"; lat = gm(numeri[0..<1]); lon = gm(numeri[1..<2])
        case 4: formato = "gradi e minuti"; lat = gm(numeri[0..<2]); lon = gm(numeri[2..<4])
        case 6: formato = "gradi, minuti e secondi"; lat = gm(numeri[0..<3]); lon = gm(numeri[3..<6])
        default: return nil
        }
        if lettere.contains("S") { lat = -abs(lat) }
        if lettere.contains("W") || lettere.contains("O") { lon = -abs(lon) }
        guard abs(lat) <= 90, abs(lon) <= 180 else { return nil }
        return .init(punto: .init(latitude: lat, longitude: lon), formato: formato)
    }

    // MARK: Plus code (Open Location Code, codici completi a 10 cifre)

    static let alfabetoOLC = Array("23456789CFGHJMPQRVWX")

    static func plusCode(_ c: CLLocationCoordinate2D) -> String {
        var la = Int(((min(max(c.latitude, -90), 89.9999999) + 90) * 8000).rounded(.down))
        var lo = Int(((c.longitude + 180).truncatingRemainder(dividingBy: 360) * 8000).rounded(.down))
        var cifre: [Character] = []
        for _ in 0..<5 {
            cifre.insert(alfabetoOLC[lo % 20], at: 0); lo /= 20
            cifre.insert(alfabetoOLC[la % 20], at: 0); la /= 20
        }
        let s = String(cifre)
        return String(s.prefix(8)) + "+" + String(s.suffix(2))
    }

    static func plusCode(_ testo: String) -> CLLocationCoordinate2D? {
        let s = testo.uppercased().replacingOccurrences(of: " ", with: "")
        guard let re = try? NSRegularExpression(pattern: #"^([23456789CFGHJMPQRVWX]{8})\+([23456789CFGHJMPQRVWX]{2})$"#),
              re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil else { return nil }
        let cifre = Array(s.replacingOccurrences(of: "+", with: ""))
        var la = 0.0, lo = 0.0, passo = 20.0
        for i in 0..<5 {
            guard let a = alfabetoOLC.firstIndex(of: cifre[2 * i]), let b = alfabetoOLC.firstIndex(of: cifre[2 * i + 1]) else { return nil }
            la += Double(a) * passo; lo += Double(b) * passo
            if i < 4 { passo /= 20 }
        }
        return .init(latitude: la - 90 + passo / 2, longitude: lo - 180 + passo / 2)
    }

    // MARK: scrittura

    static func gradiMinuti(_ v: Double) -> String {
        let a = abs(v)
        var d = Int(a)
        var m = ((a - Double(d)) * 60 * 1000).rounded() / 1000
        if m >= 60 { d += 1; m = 0 }
        return (v < 0 ? "-" : "") + "\(d)°" + String(format: "%06.3f", m)
    }

    static func gms(_ v: Double) -> String {
        let a = abs(v)
        var tot = Int((a * 3600).rounded())
        let d = tot / 3600; tot %= 3600
        return (v < 0 ? "-" : "") + String(format: "%d°%02d'%02d\"", d, tot / 60, tot % 60)
    }

    /// righe della tavola: MGRS, UTM, Gradi dec., Gradi e min., G M S, Plus code
    static func righe(_ c: CLLocationCoordinate2D) -> [(String, String)] {
        [("MGRS", Geo.mgrs(c)),
         ("UTM", UTM.fromLatLon(c.latitude, c.longitude).text),
         ("Gradi dec.", String(format: "%.5f, %.5f", c.latitude, c.longitude)),
         ("Gradi e min.", gradiMinuti(c.latitude) + " " + gradiMinuti(c.longitude)),
         ("G M S", gms(c.latitude) + " " + gms(c.longitude)),
         ("Plus code", plusCode(c))]
    }

    static func testoDaInviare(_ c: CLLocationCoordinate2D) -> String {
        "MGRS \(Geo.mgrs(c))\n" + String(format: "%.5f, %.5f", c.latitude, c.longitude)
            + String(format: "\nhttps://maps.apple.com/?ll=%.6f,%.6f", c.latitude, c.longitude)
    }
}

struct CoordinateV3: View {
    @EnvironmentObject private var location: LocationService
    @Environment(\.dismiss) private var chiudi
    @State private var scheda = 1
    @State private var testo = Anteprima.attiva ? Anteprima.coordinateEsempio : (UserDefaults.standard.string(forKey: "strum.coord.testo") ?? "")
    @State private var da = ""
    @State private var luogo: String?
    @State private var copiato: String?
    @FocusState private var fuoco: Int?
    /// iPad (tavola 70): nel pannello a destra di Strumenti, senza tasto indietro
    var pannello = false

    init(pannello: Bool = false) { self.pannello = pannello }

    /// punto mostrato nelle righe e usato dai tre tasti
    var punto: CLLocationCoordinate2D? {
        switch scheda {
        case 0: return location.location?.coordinate
        default: return FormatiCoordinate.riconosci(testo)?.punto
        }
    }
    var partenza: CLLocationCoordinate2D? {
        da.isEmpty ? location.location?.coordinate : FormatiCoordinate.riconosci(da)?.punto
    }

    var body: some View {
        if pannello { corpoPannello } else { corpoTelefono }
    }

    /// iPad (tavola 70): titolo 30, spazio 12, righe senza intestazione e senza G M S
    var corpoPannello: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Coordinate").font(.system(size: 30, weight: .black)).tracking(-0.6).foregroundStyle(Theme.testo)
                    .padding(.top, 2)
                SchedeTela(voci: ["Dove sono", "Converti", "Distanza"], scelta: $scheda)
                switch scheda {
                case 0: doveSono
                case 1: campo("Incolla o scrivi", $testo, 1)
                default:
                    campo("Da (vuoto = dove sono)", $da, 2)
                    campo("A", $testo, 1)
                }
                if scheda == 2, let a = partenza, let b = punto { distanza(a, b) }
                if let p = punto {
                    VStack(spacing: 0) {
                        ForEach(Array(FormatiCoordinate.righe(p).filter { $0.0 != "G M S" }.enumerated()), id: \.offset) { i, r in
                            riga(r.0, r.1, evidenzia: i == 0)
                        }
                    }
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                tasti
            }
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboardSeVa()
        .background(Theme.bg)
        .onChange(of: testo) { UserDefaults.standard.set($0, forKey: "strum.coord.testo") }
        .task(id: punto.map { String(format: "%.4f,%.4f", $0.latitude, $0.longitude) } ?? "") { await cercaLuogo() }
    }

    var corpoTelefono: some View {
        VStack(alignment: .leading, spacing: 0) {
            // intestazione: top 54, lati 14
            HStack(spacing: 8) {
                Button { chiudi() } label: {
                    IconaTela(d: Ic.indietro, colore: Theme.testo, lato: 18)
                        .frame(width: 42, height: 42).background(Theme.surface, in: Circle()).overlay(Circle().strokeBorder(Theme.stroke))
                }
                .accessibilityLabel("Indietro")
                Text("Coordinate").font(.system(size: 24, weight: .black)).foregroundStyle(Theme.testo)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 7)

            ScrollView(showsIndicators: false) {
                // corpo: top 108, lati 14, spazio 11
                VStack(alignment: .leading, spacing: 11) {
                    SchedeTela(voci: ["Dove sono", "Converti", "Distanza"], scelta: $scheda)
                    switch scheda {
                    case 0: doveSono
                    case 1: campo("Incolla o scrivi", $testo, 1)
                    default:
                        campo("Da (vuoto = dove sono)", $da, 2)
                        campo("A", $testo, 1)
                    }
                    if scheda == 2, let a = partenza, let b = punto { distanza(a, b) }
                    if let p = punto { formati(p) }
                    tasti
                }
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 30)
            }
            .scrollDismissesKeyboardSeVa()
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { ModuliAperti.shared.aperti += 1 }        // tavola 65: senza la barra in basso
        .onDisappear { ModuliAperti.shared.aperti = max(0, ModuliAperti.shared.aperti - 1) }
        .onChange(of: testo) { UserDefaults.standard.set($0, forKey: "strum.coord.testo") }
        .task(id: punto.map { String(format: "%.4f,%.4f", $0.latitude, $0.longitude) } ?? "") { await cercaLuogo() }
    }

    // MARK: campo con riconoscimento

    func campo(_ etichetta: String, _ t: Binding<String>, _ id: Int) -> some View {
        let r = FormatiCoordinate.riconosci(t.wrappedValue)
        return VStack(alignment: .leading, spacing: 0) {
            EtichettaCampo(testo: etichetta).padding(.bottom, 4)
            RiquadroCampo(attivo: fuoco == id || r != nil) {
                TextField("", text: t, prompt: Text("MGRS, UTM, gradi, plus code…").foregroundColor(Theme.dim.opacity(0.6)))
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.testo)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .focused($fuoco, equals: id)
                if !pannello { Button {
                    haptic()
                    if let s = UIPasteboard.general.string { t.wrappedValue = s.trimmingCharacters(in: .whitespacesAndNewlines) }
                } label: { IconaTela(d: Ic.stAppunti, colore: Theme.olive, lato: 17) }
                .accessibilityLabel("Incolla") }
            }
            if let r {
                NotaCampo(testo: "Riconosciuto: \(r.formato)" + (id == 1 && luogo != nil ? " · vicino a \(luogo!)" : ""),
                          colore: Theme.oliveBright, icona: Ic.spunta)
            } else if !t.wrappedValue.isEmpty {
                NotaCampo(testo: "Formato non riconosciuto", colore: Theme.red)
            }
        }
    }

    var doveSono: some View {
        VStack(alignment: .leading, spacing: 0) {
            EtichettaCampo(testo: "La mia posizione").padding(.bottom, 4)
            RiquadroCampo(attivo: location.location != nil, auto: true) {
                Text(location.location == nil ? "In attesa del GPS…" : "GPS ±\(Int(location.location?.horizontalAccuracy ?? 0)) m")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.testo2)
                Spacer()
                IconaTela(d: Ic.stCoordinate, colore: Theme.olive, lato: 17)
            }
            if let l = luogo { NotaCampo(testo: "Vicino a \(l)", colore: Theme.oliveBright, icona: Ic.spunta) }
        }
    }

    // MARK: lo stesso punto in tutti i formati

    func formati(_ p: CLLocationCoordinate2D) -> some View {
        VStack(spacing: 0) {
            Text("LO STESSO PUNTO IN TUTTI I FORMATI").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 9)
            ForEach(Array(FormatiCoordinate.righe(p).enumerated()), id: \.offset) { i, r in
                riga(r.0, r.1, evidenzia: i == 0)
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Theme.stroke))
    }

    @ViewBuilder func riga(_ nome: String, _ valore: String, evidenzia: Bool = false) -> some View {
        if pannello { rigaPannello(nome, valore, evidenzia: evidenzia) } else { rigaTelefono(nome, valore, evidenzia: evidenzia) }
    }

    /// riga della tavola 70: nome 96 pt, valore mono 15, icona copia 16 senza riquadro
    func rigaPannello(_ nome: String, _ valore: String, evidenzia: Bool) -> some View {
        HStack(spacing: 12) {
            Text(nome).font(.system(size: 12, weight: .heavy)).foregroundStyle(evidenzia ? Theme.oliveBright : Theme.dim)
                .frame(width: 96, alignment: .leading)
            Text(valore).font(Theme.mono(15, .heavy)).foregroundStyle(Theme.testo)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            Button {
                UIPasteboard.general.string = valore
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                copiato = nome
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { if copiato == nome { copiato = nil } }
            } label: {
                IconaTela(d: copiato == nome ? Ic.spunta : Ic.stCopia, colore: copiato == nome ? Theme.oliveBright : Theme.dim, lato: 16)
                    .frame(width: 28, height: 20).contentShape(Rectangle())
            }
            .accessibilityLabel("Copia \(nome)")
        }
        .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 11)
        .overlay(alignment: .top) { Rectangle().fill(Theme.olive.opacity(0.12)).frame(height: 1) }
    }

    func rigaTelefono(_ nome: String, _ valore: String, evidenzia: Bool) -> some View {
        HStack(spacing: 10) {
            Text(nome).font(.system(size: 11, weight: .heavy)).foregroundStyle(evidenzia ? Theme.oliveBright : Theme.dim)
                .frame(width: 78, alignment: .leading)
            Text(valore).font(Theme.mono(13.5, .heavy)).foregroundStyle(Theme.testo)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            Button {
                UIPasteboard.general.string = valore
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                copiato = nome
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { if copiato == nome { copiato = nil } }
            } label: {
                IconaTela(d: copiato == nome ? Ic.spunta : Ic.stCopia, colore: copiato == nome ? Theme.oliveBright : Theme.testo, lato: 14)
                    .frame(width: 32, height: 32)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.olive.opacity(0.25)))
            }
            .accessibilityLabel("Copia \(nome)")
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .overlay(alignment: .top) { Rectangle().fill(Theme.olive.opacity(0.12)).frame(height: 1) }
    }

    func distanza(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> some View {
        let d = CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        let az = Geo.bearing(a, b)
        return VStack(spacing: 0) {
            Text("DISTANZA E DIREZIONE").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 9)
            riga("Distanza", Geo.formatDistance(d), evidenzia: true)
            riga("Azimut", String(format: "%03.0f° · %.0f mils", az, az * 6400 / 360))
            riga("Ritorno", String(format: "%03.0f°", (az + 180).truncatingRemainder(dividingBy: 360)))
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Theme.stroke))
    }

    // MARK: In mappa · Naviga · Invia

    @ViewBuilder var tasti: some View {
        if pannello { tastiPannello } else { tastiTelefono }
    }

    /// tavola 70: tre tasti uguali alti 48, angoli 14, solo testo
    var tastiPannello: some View {
        HStack(spacing: 8) {
            Button { inMappa(naviga: false) } label: { tastoPannello("In mappa", pieno: true) }.buttonStyle(PressStyle())
            Button { inMappa(naviga: true) } label: { tastoPannello("Naviga", pieno: false) }.buttonStyle(PressStyle())
            if let p = punto {
                ShareLink(item: FormatiCoordinate.testoDaInviare(p)) { tastoPannello("Invia", pieno: false) }.buttonStyle(PressStyle())
            } else {
                tastoPannello("Invia", pieno: false)
            }
        }
        .disabled(punto == nil)
        .opacity(punto == nil ? 0.5 : 1)
    }

    func tastoPannello(_ t: String, pieno: Bool) -> some View {
        Text(t).font(.system(size: 14.5, weight: pieno ? .black : .heavy)).foregroundStyle(pieno ? Theme.scuro : Theme.testo)
            .frame(maxWidth: .infinity).frame(height: 48)
            .background(pieno ? Theme.olive : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(pieno ? Color.clear : Theme.testo.opacity(0.18)))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    var tastiTelefono: some View {
        HStack(spacing: 7) {
            Button { inMappa(naviga: false) } label: { etichettaTasto("In mappa", Ic.segnaposto, pieno: true) }
                .buttonStyle(PressStyle())
            Button { inMappa(naviga: true) } label: { etichettaTasto("Naviga", Ic.stNaviga, pieno: false) }
                .buttonStyle(PressStyle())
            if let p = punto {
                ShareLink(item: FormatiCoordinate.testoDaInviare(p)) { etichettaTasto("Invia", Ic.stInvia, pieno: false) }
                    .buttonStyle(PressStyle())
            } else {
                etichettaTasto("Invia", Ic.stInvia, pieno: false)
            }
        }
        .disabled(punto == nil)
        .opacity(punto == nil ? 0.5 : 1)
    }

    func etichettaTasto(_ t: String, _ icona: String, pieno: Bool) -> some View {
        HStack(spacing: 6) {
            IconaTela(d: icona, colore: pieno ? Theme.scuro : Theme.testo, lato: 16)
            Text(t).font(.system(size: 13, weight: .black)).foregroundStyle(pieno ? Theme.scuro : Theme.testo)
        }
        .frame(maxWidth: .infinity).frame(height: 48)
        .background(pieno ? Theme.olive : Theme.surface2, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    /// mette il punto tra i "punti miei" (li disegna la mappa) e apre la mappa; con Naviga lo rende anche il bersaglio
    func inMappa(naviga: Bool) {
        guard let p = punto else { return }
        haptic()
        let store = NavStore.shared
        let esistente = store.miei.first { abs($0.lat - p.latitude) < 1e-6 && abs($0.lon - p.longitude) < 1e-6 }
        let mio = esistente ?? store.salva(PuntoMio(nome: "COORD", lat: p.latitude, lon: p.longitude, tipo: "wp",
                                                    nota: "da Strumenti › Coordinate"))
        if naviga { store.target = mio.punto }
        MappaTattica.centroInSospeso = p
        vaiAllaScheda(Schede.mappa)
        NotificationCenter.default.post(name: .mappaCentra, object: nil)
    }

    func cercaLuogo() async {
        guard let p = punto else { luogo = nil; return }
        do {
            let pl = try await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: p.latitude, longitude: p.longitude),
                                                                  preferredLocale: Locale(identifier: "it_IT"))
            guard let f = pl.first, let citta = f.locality ?? f.subAdministrativeArea else { luogo = nil; return }
            // sigla della provincia: dal geocoder se è già di 2 lettere, altrimenti dall'elenco ISTAT dei comuni
            let sigla = f.subAdministrativeArea.flatMap { $0.count == 2 ? $0 : nil } ?? ComuniIT.trova(citta)?.sigla
            luogo = sigla.map { "\(citta) (\($0))" } ?? citta
        } catch { luogo = nil }
    }
}

extension View {
    /// iOS 16+: la tastiera si chiude scorrendo
    @ViewBuilder func scrollDismissesKeyboardSeVa() -> some View {
        self.scrollDismissesKeyboard(.interactively)
    }
}
