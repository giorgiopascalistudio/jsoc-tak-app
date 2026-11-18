import SwiftUI
import CoreLocation

// MARK: - Barra di stato fissata in alto

struct BarraStato: View {
    @ObservedObject var ctl: MappaCtl
    let offlineOk: Bool
    @EnvironmentObject var location: LocationService
    @ObservedObject private var store = EventoStore.shared
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var traccia = Traccia.shared

    var body: some View {
        let l = location.location
        let membri = store.corrente?.membri?.count ?? 0
        let attivi = store.squadra.filter { $0.eta < 300 && $0.id != jsoc.utente?.id }.count
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Circle().fill(jsoc.online ? Theme.green : Theme.amber).frame(width: 7, height: 7)
                Text((store.corrente?.nome ?? "NESSUN EVENTO").uppercased()).foregroundStyle(Theme.oliveBright).lineLimit(1)
            }
            Text(l.map { coordTesto($0.coordinate) } ?? "in attesa del GPS").foregroundStyle(.white)
            if let l, l.verticalAccuracy > 0 { Text(String(format: "%.0f m", l.altitude)).foregroundStyle(Theme.dim) }
            if let h = location.heading {
                Text("\(gradi3(h - (location.declinazione ?? 4.6))) \(Mission.cardinale(h))").foregroundStyle(Theme.oliveBright)
            }
            if let l { Text(String(format: "GPS ±%.0f", l.horizontalAccuracy)).foregroundStyle(l.horizontalAccuracy <= 10 ? Theme.dim : Theme.amber) }
            Spacer(minLength: 4)
            if traccia.attiva { Text("● REC " + traccia.testo).foregroundStyle(Theme.red) }
            if membri > 0 { Text("SQUADRA \(attivi)/\(max(membri - 1, 0))").foregroundStyle(Theme.cyan) }
            if offlineOk { Text("OFFLINE ✓").foregroundStyle(Theme.green) }
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                Text(ctx.date.formatted(date: .omitted, time: .shortened)).foregroundStyle(.white)
            }
        }
        .font(Theme.mono(11, .bold))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 14)
        .frame(height: 30)
    }
}

// MARK: - Impostazioni della mappa

struct PannelloImpostazioni: View {
    @ObservedObject var ctl: MappaCtl
    @Binding var griglia: Bool
    @Binding var aree: Bool
    @Binding var squadra: Bool
    var chiudi: () -> Void
    var allinea: (UIImage) -> Void
    var scarica: () -> Void
    @AppStorage("mappa.coordinate") private var formato = "mgrs"
    @ObservedObject private var volume = VolumeTasti.shared
    @ObservedObject private var store = EventoStore.shared
    @EnvironmentObject var night: NightMode

    var body: some View {
        VStack(spacing: 0) {
            TestataPannello(titolo: "Impostazioni e mappe", chiudi: chiudi)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("JSOC TAK \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · versione \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "")")
                        .font(Theme.mono(10, .bold)).foregroundStyle(Theme.dim)
                    EtichettaSezione(testo: "Mappa")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                        ForEach(StileMappa.allCases) { s in
                            Button { haptic(); ctl.stile = s } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: s.icona).font(.system(size: 15)).foregroundStyle(ctl.stile == s ? Theme.oliveBright : Theme.dim)
                                    Text(s.nome).font(.system(size: 12.5, weight: .bold)).foregroundStyle(.white)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10).frame(height: 40)
                                .background(Theme.surface2.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ctl.stile == s ? Theme.olive : Theme.stroke, lineWidth: ctl.stile == s ? 2 : 1))
                            }
                        }
                    }
                    HStack {
                        Button { scarica() } label: { Label("Scarica la zona", systemImage: "arrow.down.circle.fill") }
                            .buttonStyle(.borderedProminent).tint(Theme.olive).foregroundStyle(.black).disabled(ctl.offline != nil)
                        if !ctl.esitoOffline.isEmpty { Text(ctl.esitoOffline).font(.caption2).foregroundStyle(Theme.dim).lineLimit(2) }
                    }
                    if let o = ctl.offline { ProgressView(value: Double(o.fatti), total: Double(o.totale)).tint(Theme.olive) }
                    SezioneMappeImportate(allinea: allinea) { MappeImportate.shared.applica(ctl.mappa) }

                    EtichettaSezione(testo: "Sulla mappa")
                    Toggle("Griglia MGRS", isOn: $griglia)
                    Toggle("Aree dell'evento", isOn: $aree)
                    Toggle("Squadra", isOn: $squadra)

                    EtichettaSezione(testo: "Coordinate")
                    Picker("Coordinate", selection: $formato) {
                        Text("MGRS").tag("mgrs"); Text("UTM").tag("utm"); Text("Gradi").tag("dd"); Text("G° P′ S″").tag("dms")
                    }
                    .pickerStyle(.segmented)

                    EtichettaSezione(testo: "Tasti volume")
                    Picker("Tasti volume", selection: $volume.funzione) {
                        Text("Scorrono i punti").tag(VolumeTasti.Funzione.punti)
                        Text("Cambiano mappa").tag(VolumeTasti.Funzione.stile)
                        Text("Volume").tag(VolumeTasti.Funzione.spenti)
                    }
                    .pickerStyle(.segmented)
                    Text("Su e giù tenuti insieme: SOS (3 secondi per annullare).").font(.caption2).foregroundStyle(Theme.dim)

                    EtichettaSezione(testo: "Notte")
                    Toggle("Modalità notte (rosso)", isOn: Binding(get: { night.on }, set: { if $0 != night.on { night.toggle() } }))
                    HStack {
                        Image(systemName: "sun.min").foregroundStyle(Theme.dim)
                        Slider(value: Binding(get: { Night.luce }, set: { night.impostaLuce($0) }), in: 0.05...1)
                        Image(systemName: "sun.max.fill").foregroundStyle(Theme.dim)
                    }

                    EtichettaSezione(testo: "Posizione")
                    Toggle("Condividi posizione e direzione", isOn: $store.condividiPosizione)
                }
                .tint(Theme.olive)
                .font(.system(size: 14))
                .padding(14)
            }
        }
    }
}

// MARK: - Croce di mira

struct CroceMira: View {
    let punto: CGPoint
    let testo: String

    var body: some View {
        ZStack {
            Circle().strokeBorder(Theme.amber, lineWidth: 2).frame(width: 46, height: 46)
            Rectangle().fill(Theme.amber).frame(width: 2, height: 64)
            Rectangle().fill(Theme.amber).frame(width: 64, height: 2)
            Circle().fill(Theme.amber).frame(width: 5, height: 5)
            Text(testo).font(Theme.mono(12, .heavy)).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 7))
                .fixedSize()
                .offset(y: -50)
            Text("rilascia per segnare").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.amber)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.black.opacity(0.7), in: Capsule())
                .fixedSize()
                .offset(y: 46)
        }
        .shadow(color: .black, radius: 2)
        .position(punto)
    }
}

// MARK: - Coordinate: inserimento ordinato in ogni formato

struct PannelloCoordinate: View {
    let iniziale: CLLocationCoordinate2D
    var chiudi: () -> Void
    var usa: (CLLocationCoordinate2D, Bool) -> Void   // (coordinata, crea punto?)
    @State private var formato = UserDefaults.standard.string(forKey: "mappa.coordinate") ?? "mgrs"
    // MGRS
    @State private var zona = ""
    @State private var quadrato = ""
    @State private var est = ""
    @State private var nord = ""
    // UTM
    @State private var utmZona = ""
    @State private var utmEst = ""
    @State private var utmNord = ""
    // gradi
    @State private var lat = ""
    @State private var lon = ""
    // G P S
    @State private var gLat = ""
    @State private var pLat = ""
    @State private var sLat = ""
    @State private var nordSud = "N"
    @State private var gLon = ""
    @State private var pLon = ""
    @State private var sLon = ""
    @State private var estOvest = "E"

    var risultato: CLLocationCoordinate2D? {
        switch formato {
        case "mgrs": return Coordinate.parse("\(zona) \(quadrato) \(est) \(nord)")
        case "utm": return Coordinate.parse("\(utmZona) \(utmEst) \(utmNord)")
        case "dd":
            guard let a = Double(lat.replacingOccurrences(of: ",", with: ".")), let b = Double(lon.replacingOccurrences(of: ",", with: ".")),
                  abs(a) <= 90, abs(b) <= 180 else { return nil }
            return .init(latitude: a, longitude: b)
        default:
            func v(_ g: String, _ p: String, _ s: String) -> Double? {
                guard let g = Double(g) else { return nil }
                return g + (Double(p) ?? 0) / 60 + (Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0) / 3600
            }
            guard let a = v(gLat, pLat, sLat), let b = v(gLon, pLon, sLon) else { return nil }
            return .init(latitude: nordSud == "N" ? a : -a, longitude: estOvest == "E" ? b : -b)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TestataPannello(titolo: "Coordinate", sotto: risultato.map { Geo.mgrs($0) } ?? "inserisci i valori", chiudi: chiudi)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("", selection: $formato) {
                        Text("MGRS").tag("mgrs"); Text("UTM").tag("utm"); Text("Gradi").tag("dd"); Text("G° P′ S″").tag("dms")
                    }
                    .pickerStyle(.segmented)
                    switch formato {
                    case "mgrs":
                        HStack(spacing: 6) {
                            casella("Zona", $zona, "33T", 64, .asciiCapable)
                            casella("Quadrato", $quadrato, "TJ", 64, .asciiCapable)
                        }
                        HStack(spacing: 6) {
                            casella("Est", $est, "90251", nil, .numberPad)
                            casella("Nord", $nord, "74842", nil, .numberPad)
                        }
                    case "utm":
                        casella("Zona e banda", $utmZona, "33T", 90, .asciiCapable)
                        HStack(spacing: 6) {
                            casella("Est (m)", $utmEst, "290251", nil, .numberPad)
                            casella("Nord (m)", $utmNord, "4874842", nil, .numberPad)
                        }
                    case "dd":
                        casella("Latitudine", $lat, "40.25094", nil, .numbersAndPunctuation)
                        casella("Longitudine", $lon, "18.31520", nil, .numbersAndPunctuation)
                    default:
                        rigaGPS("Latitudine", $gLat, $pLat, $sLat, $nordSud, ["N", "S"])
                        rigaGPS("Longitudine", $gLon, $pLon, $sLon, $estOvest, ["E", "O"])
                    }
                    if let r = risultato {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Geo.mgrs(r)).font(Theme.mono(14, .heavy)).foregroundStyle(Theme.oliveBright)
                            Text(String(format: "%.6f, %.6f", r.latitude, r.longitude)).font(Theme.mono(11)).foregroundStyle(Theme.dim)
                        }
                    }
                }
                .padding(14)
            }
            HStack(spacing: 8) {
                Button { if let r = risultato { usa(r, false) } } label: { Label("Naviga", systemImage: "location.north.line.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(Theme.oliveBright).foregroundStyle(.black)
                Button { if let r = risultato { usa(r, true) } } label: { Label("Crea punto", systemImage: "mappin").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).tint(Theme.olive)
            }
            .disabled(risultato == nil)
            .font(.system(size: 14, weight: .bold))
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .onAppear { precompila() }
    }

    func casella(_ t: String, _ b: Binding<String>, _ es: String, _ w: CGFloat?, _ k: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(t.uppercased()).font(Theme.mono(9, .heavy)).tracking(1).foregroundStyle(Theme.dim)
            TextField(es, text: b).keyboardType(k).textInputAutocapitalization(.characters).autocorrectionDisabled()
                .font(Theme.mono(17, .heavy))
                .padding(.horizontal, 10).frame(height: 42)
                .background(Theme.surface2.opacity(0.85), in: RoundedRectangle(cornerRadius: 9))
        }
        .frame(width: w)
        .frame(maxWidth: w == nil ? .infinity : w)
    }

    func rigaGPS(_ t: String, _ g: Binding<String>, _ p: Binding<String>, _ s: Binding<String>, _ e: Binding<String>, _ lati: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(t.uppercased()).font(Theme.mono(9, .heavy)).tracking(1).foregroundStyle(Theme.dim)
            HStack(spacing: 4) {
                campoCorto(g, "°"); campoCorto(p, "′"); campoCorto(s, "″")
                Picker("", selection: e) { ForEach(lati, id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).frame(width: 80)
            }
        }
    }

    func campoCorto(_ b: Binding<String>, _ u: String) -> some View {
        HStack(spacing: 1) {
            TextField("0", text: b).keyboardType(.decimalPad).font(Theme.mono(16, .heavy)).multilineTextAlignment(.trailing)
            Text(u).font(Theme.mono(15, .bold)).foregroundStyle(Theme.dim)
        }
        .padding(.horizontal, 8).frame(height: 42)
        .background(Theme.surface2.opacity(0.85), in: RoundedRectangle(cornerRadius: 9))
    }

    /// Parte dalla posizione attuale: si cambiano solo le cifre che servono.
    func precompila() {
        let m = Geo.mgrs(iniziale).split(separator: " ").map(String.init)
        if m.count == 4 { zona = m[0]; quadrato = m[1]; est = m[2]; nord = m[3] }
        let u = UTM.fromLatLon(iniziale.latitude, iniziale.longitude)
        utmZona = "\(u.zone)\(u.band)"; utmEst = String(format: "%.0f", u.easting); utmNord = String(format: "%.0f", u.northing)
        lat = String(format: "%.6f", iniziale.latitude); lon = String(format: "%.6f", iniziale.longitude)
        func gps(_ v: Double) -> (String, String, String) {
            let a = abs(v), g = Int(a), p = Int((a - Double(g)) * 60), s = (a - Double(g) - Double(p) / 60) * 3600
            return ("\(g)", "\(p)", String(format: "%.1f", s))
        }
        (gLat, pLat, sLat) = gps(iniziale.latitude); nordSud = iniziale.latitude >= 0 ? "N" : "S"
        (gLon, pLon, sLon) = gps(iniziale.longitude); estOvest = iniziale.longitude >= 0 ? "E" : "O"
    }
}

// MARK: - Catalogo strumenti (i "plugin")

enum Strumento: String, CaseIterable, Identifiable {
    case vaiPunto, seguiCompagno, traccia, rotta
    case distanza, proietta, triangolazione, cerchi, vista, profilo
    case punto, linea, area, freccia, testo, recinto, simboli
    case chat, video, sos, noveRighe, salute, pacchetti, segnala
    case cifrari, morse, qr, mirino
    case offline, griglia, importa, immagine, lora
    case cerca, vista360, balistica, replay, cronologia, muroVideo, sms, medico, meteo, rilievo, telecamere, stampa, droni

    var id: String { rawValue }

    var categoria: String {
        switch self {
        case .vaiPunto, .seguiCompagno, .traccia, .rotta: return "Navigazione"
        case .distanza, .proietta, .triangolazione, .cerchi, .vista, .profilo: return "Misure"
        case .punto, .linea, .area, .freccia, .testo, .recinto, .simboli: return "Disegno"
        case .chat, .video, .sos, .noveRighe, .salute, .pacchetti, .segnala: return "Squadra"
        case .cifrari, .morse, .qr, .mirino: return "Intelligence"
        case .offline, .griglia, .importa, .immagine, .lora: return "Mappe e rete"
        case .cerca: return "Navigazione"
        case .vista360, .balistica: return "Misure"
        case .replay, .cronologia, .muroVideo, .sms, .medico: return "Squadra"
        case .meteo, .rilievo, .telecamere, .stampa, .droni: return "Mappe e rete"
        }
    }

    var nome: String {
        switch self {
        case .vaiPunto: return "Vai a coordinate"
        case .seguiCompagno: return "Segui un compagno"
        case .traccia: return "Traccia"
        case .rotta: return "Rotta a tappe"
        case .distanza: return "Distanza e azimut"
        case .proietta: return "Proietta punto"
        case .triangolazione: return "Triangolazione"
        case .cerchi: return "Cerchi di distanza"
        case .vista: return "Linea di vista"
        case .profilo: return "Profilo altimetrico"
        case .punto: return "Punto"
        case .linea: return "Linea"
        case .area: return "Area"
        case .freccia: return "Freccia"
        case .testo: return "Testo"
        case .recinto: return "Recinto con avviso"
        case .simboli: return "Simboli tattici"
        case .chat: return "Chat"
        case .video: return "Video"
        case .sos: return "SOS"
        case .segnala: return "Segnala"
        case .noveRighe: return "Soccorso 9 righe"
        case .salute: return "Report SALUTE"
        case .pacchetti: return "Pacchetti missione"
        case .cifrari: return "Cifrari"
        case .morse: return "Morse"
        case .qr: return "QR, foto, audio"
        case .mirino: return "Mirino con azimut"
        case .offline: return "Zona offline"
        case .griglia: return "Griglia MGRS"
        case .importa: return "Importa mappe"
        case .immagine: return "Immagine o PDF sopra"
        case .lora: return "LoRa Heltec"
        case .cerca: return "Cerca luoghi"
        case .vista360: return "Visibilità 360°"
        case .balistica: return "Balistica BB"
        case .replay: return "Replay tracce"
        case .cronologia: return "Cronologia"
        case .muroVideo: return "Muro video"
        case .sms: return "Posizione via SMS"
        case .medico: return "Primo soccorso"
        case .meteo: return "Meteo e vento"
        case .rilievo: return "Ombreggiatura"
        case .telecamere: return "Telecamere pubbliche"
        case .stampa: return "Stampa PDF"
        case .droni: return "Droni (Remote ID)"
        }
    }

    var icona: String {
        switch self {
        case .vaiPunto: return "location.north.line.fill"
        case .seguiCompagno: return "person.line.dotted.person.fill"
        case .traccia: return "point.bottomleft.forward.to.point.topright.scurvepath"
        case .rotta: return "point.3.connected.trianglepath.dotted"
        case .distanza: return "ruler"
        case .proietta: return "plus.viewfinder"
        case .triangolazione: return "triangle"
        case .cerchi: return "circle.circle"
        case .vista: return "eye"
        case .profilo: return "chart.xyaxis.line"
        case .punto: return "mappin.and.ellipse"
        case .linea: return "scribble"
        case .area: return "square.dashed"
        case .freccia: return "arrow.up.right"
        case .testo: return "textformat"
        case .recinto: return "bell.badge"
        case .simboli: return "seal"
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .video: return "video.fill"
        case .sos: return "sos"
        case .segnala: return "exclamationmark.bubble.fill"
        case .noveRighe: return "cross.case.fill"
        case .salute: return "doc.text.magnifyingglass"
        case .pacchetti: return "shippingbox.fill"
        case .cifrari: return "lock.open.fill"
        case .morse: return "dot.radiowaves.left.and.right"
        case .qr: return "qrcode.viewfinder"
        case .mirino: return "scope"
        case .offline: return "arrow.down.circle.fill"
        case .griglia: return "grid"
        case .importa: return "square.and.arrow.down.on.square"
        case .immagine: return "photo.on.rectangle.angled"
        case .lora: return "antenna.radiowaves.left.and.right"
        case .cerca: return "magnifyingglass"
        case .vista360: return "eye.circle"
        case .balistica: return "target"
        case .replay: return "play.circle"
        case .cronologia: return "clock.arrow.circlepath"
        case .muroVideo: return "square.grid.2x2"
        case .sms: return "message.fill"
        case .medico: return "cross.case.fill"
        case .meteo: return "cloud.sun.rain.fill"
        case .rilievo: return "mountain.2.fill"
        case .telecamere: return "web.camera.fill"
        case .stampa: return "printer.fill"
        case .droni: return "airplane"
        }
    }

    var pronto: Bool { true }

    static var categorie: [String] { ["Navigazione", "Misure", "Disegno", "Squadra", "Intelligence", "Mappe e rete"] }
}

struct PannelloStrumenti: View {
    var chiudi: () -> Void
    var azione: (Strumento) -> Void

    var body: some View {
        VStack(spacing: 0) {
            TestataPannello(titolo: "Strumenti", sotto: "Tieni premuto uno strumento per metterlo nella barra in alto", chiudi: chiudi)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Strumento.categorie, id: \.self) { cat in
                        VStack(alignment: .leading, spacing: 6) {
                            EtichettaSezione(testo: cat)
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                                ForEach(Strumento.allCases.filter { $0.categoria == cat }) { s in
                                    Button { if s.pronto { haptic(); azione(s) } } label: { tessera(s) }
                                        .buttonStyle(PressStyle())
                                        .disabled(!s.pronto)
                                        .contextMenu {
                                            if BarraRapida.contiene(s) {
                                                Button(role: .destructive) { BarraRapida.togli(s) } label: { Label("Togli dalla barra in alto", systemImage: "pin.slash") }
                                            } else {
                                                Button { BarraRapida.metti(s) } label: { Label("Metti nella barra in alto", systemImage: "pin") }
                                            }
                                        }
                                }
                            }
                        }
                    }
                }
                .padding(14)
            }
        }
    }

    func tessera(_ s: Strumento) -> some View {
        HStack(spacing: 8) {
            Image(systemName: s.icona).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(s == .sos ? Theme.red : (s.pronto ? Theme.oliveBright : Theme.dim))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(s.nome).font(.system(size: 12, weight: .bold)).foregroundStyle(s.pronto ? .white : Theme.dim).lineLimit(1).minimumScaleFactor(0.8)
                if !s.pronto { Text("in arrivo").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.dim) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9).frame(height: 42)
        .background(s.pronto ? Theme.surface2 : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(s.pronto ? Theme.olive.opacity(0.4) : Theme.dim.opacity(0.35),
                                                                 style: StrokeStyle(lineWidth: 1, dash: s.pronto ? [] : [4, 3])))
    }
}

// MARK: - Vai a coordinate

struct VaiCoordinateSheet: View {
    var scelto: (CLLocationCoordinate2D, String) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var testo = ""
    @State private var nome = ""

    var body: some View {
        let c = Coordinate.parse(testo)
        NavigationStack {
            Form {
                Section {
                    TextField("33T TJ 90251 74842 · 33T 290251 4874842 · 40.25, 18.31", text: $testo)
                        .font(Theme.mono(15, .bold)).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    TextField("Nome (facoltativo)", text: $nome)
                } footer: {
                    Text("Va bene MGRS, UTM o latitudine e longitudine.")
                }
                if let c {
                    Section("Riconosciuto") {
                        Text(Geo.mgrs(c)).font(Theme.mono(14, .bold))
                        Text(String(format: "%.5f, %.5f", c.latitude, c.longitude)).font(Theme.mono(12)).foregroundStyle(Theme.dim)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Vai a coordinate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Naviga") {
                        if let c { scelto(c, nome.isEmpty ? "COORDINATE" : nome.uppercased()); dismiss() }
                    }
                    .disabled(c == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}


// MARK: - Nuovo punto nella colonna (non a tutto schermo)

struct PannelloNuovoPunto: View {
    let coordinata: CLLocationCoordinate2D
    var chiudi: () -> Void
    @ObservedObject private var store = EventoStore.shared
    @State private var nome = ""
    @State private var tipo = "punto"
    @State private var note = ""
    @State private var errore: String?
    @State private var salvo = false

    var tipi: [(String, String, String)] {
        let base = [("punto", "Punto", "mappin"), ("contatto", "Contatto", "eye.fill"), ("pericolo", "Pericolo", "exclamationmark.triangle.fill")]
        let staff = [("obj", "Obiettivo", "diamond.fill"), ("raduno", "Raduno", "flag.fill"), ("waypoint", "Waypoint", "w.circle.fill"),
                     ("parcheggio", "Parcheggio", "p.circle.fill"), ("ingresso", "Ingresso", "arrow.right.circle.fill")]
        return store.corrente?.staff == true ? base + staff : base
    }

    var body: some View {
        VStack(spacing: 0) {
            TestataPannello(titolo: "Nuovo punto", sotto: coordTesto(coordinata), chiudi: chiudi)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Nome", text: $nome)
                        .font(.system(size: 15, weight: .semibold))
                        .padding(10).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
                        ForEach(tipi, id: \.0) { t in
                            Button { haptic(); tipo = t.0 } label: {
                                Label(t.1, systemImage: t.2).font(.system(size: 11.5, weight: .bold)).lineLimit(1)
                                    .frame(maxWidth: .infinity).frame(height: 34)
                                    .foregroundStyle(tipo == t.0 ? .black : .white)
                                    .background(tipo == t.0 ? Theme.olive : Theme.surface2, in: RoundedRectangle(cornerRadius: 9))
                            }
                        }
                    }
                    TextField("Note", text: $note, axis: .vertical).lineLimit(2...4)
                        .font(.system(size: 13)).padding(10).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                    if store.corrente == nil { Text("Scegli prima un evento: i punti si condividono con la sua squadra.").font(.caption).foregroundStyle(Theme.amber) }
                    if let errore { Text(errore).font(.caption).foregroundStyle(Theme.red) }
                }
                .padding(14)
            }
            HStack(spacing: 8) {
                Button("Annulla", action: chiudi).buttonStyle(.bordered).tint(Theme.dim)
                Button { salva() } label: { Text(salvo ? "Salvo…" : "Salva punto").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(Theme.olive).foregroundStyle(.black)
                    .disabled(store.corrente == nil || salvo)
            }
            .font(.system(size: 14, weight: .bold))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
        }
    }

    func salva() {
        guard let ev = store.corrente?.id else { return }
        salvo = true
        Task {
            defer { salvo = false }
            do {
                _ = try await JsocClient.shared.creaPunto(ev, nome: nome.isEmpty ? tipi.first { $0.0 == tipo }?.1 ?? "Punto" : nome, tipo: tipo, coordinata, note: note)
                await store.aggiorna(JsocClient.shared)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                chiudi()
            } catch { errore = error.localizedDescription }
        }
    }
}

// MARK: - Messaggi rapidi (un tocco, con la posizione)

struct MessaggiRapidi: View {
    let dest: Int?
    @EnvironmentObject var location: LocationService
    @ObservedObject private var store = EventoStore.shared
    @State private var inviato: String?
    static let frasi = ["In posizione", "Contatto!", "Mi muovo", "Fermo", "Ricevuto", "Serve supporto", "Obiettivo preso", "Rientro"]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Self.frasi, id: \.self) { f in
                    Button {
                        haptic(.medium)
                        Task {
                            try? await store.scrivi(f, JsocClient.shared, posizione: location.location?.coordinate, dest: dest)
                            inviato = f
                        }
                    } label: {
                        Text(f).font(.system(size: 12.5, weight: .bold)).foregroundStyle(inviato == f ? .black : .white)
                            .padding(.horizontal, 11).frame(height: 34)
                            .background(inviato == f ? Theme.olive : Theme.surface2, in: Capsule())
                            .overlay(Capsule().strokeBorder(f == "Contatto!" || f == "Serve supporto" ? Theme.amber.opacity(0.7) : Theme.stroke))
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
    }
}

// MARK: - Segnala: un tocco e il punto è sulla mappa di tutti

struct PannelloSegnala: View {
    let centroMappa: CLLocationCoordinate2D
    var chiudi: () -> Void
    var avviso: (String) -> Void
    @EnvironmentObject var location: LocationService
    @ObservedObject private var store = EventoStore.shared
    @State private var dove = 0       // 0 la mia posizione, 1 centro mappa
    @State private var nota = ""
    @State private var lavoro = false

    var body: some View {
        let c = dove == 0 ? (location.location?.coordinate ?? centroMappa) : centroMappa
        VStack(spacing: 0) {
            TestataPannello(titolo: "Segnala", sotto: coordTesto(c), chiudi: chiudi)
            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: $dove) {
                    Text("Dove sono io").tag(0)
                    Text("Centro mappa").tag(1)
                }
                .pickerStyle(.segmented)
                HStack(spacing: 8) {
                    grande("Contatto", "eye.fill", .yellow, "contatto", c)
                    grande("Pericolo", "exclamationmark.triangle.fill", Theme.amber, "pericolo", c)
                    grande("Punto", "mappin", Theme.olive, "punto", c)
                }
                TextField("Nota (facoltativa): quanti, cosa fanno…", text: $nota, axis: .vertical).lineLimit(1...3)
                    .font(.system(size: 13)).padding(10).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                Text("Il punto compare subito sulla mappa della squadra e in chat.").font(.caption2).foregroundStyle(Theme.dim)
                if store.corrente == nil { Text("Scegli prima un evento.").font(.caption).foregroundStyle(Theme.amber) }
            }
            .padding(14)
            Spacer(minLength: 0)
        }
    }

    func grande(_ t: String, _ icona: String, _ colore: Color, _ tipo: String, _ c: CLLocationCoordinate2D) -> some View {
        Button {
            guard let ev = store.corrente?.id, !lavoro else { return }
            lavoro = true
            haptic(.heavy)
            let ora = Date().formatted(date: .omitted, time: .shortened)
            let nome = "\(t.uppercased()) \(ora)"
            Task {
                defer { lavoro = false }
                do {
                    _ = try await JsocClient.shared.creaPunto(ev, nome: nome, tipo: tipo, c, note: nota)
                    try? await store.scrivi("\(t == "Contatto" ? "⚠️ " : "")\(t) \(Geo.mgrs(c))\(nota.isEmpty ? "" : " · " + nota)", JsocClient.shared, posizione: c)
                    await store.aggiorna(JsocClient.shared)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    avviso("\(t) segnalato alla squadra")
                    chiudi()
                } catch { avviso("Non inviato: \(error.localizedDescription)") }
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icona).font(.system(size: 24, weight: .bold)).foregroundStyle(colore)
                Text(t).font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).frame(height: 84)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(colore.opacity(0.6), lineWidth: 1.5))
        }
        .buttonStyle(PressStyle())
        .disabled(store.corrente == nil || lavoro)
    }
}
