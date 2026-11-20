import SwiftUI

// MARK: - Profilo senza scorrere: riproduce la tavola 32 (390 pt).
// Tessera con QR, completezza, 8 riquadri uguali (2 colonne, alti 100), "Esci da questo telefono".

struct ProfiloTab: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @Environment(\.dismiss) private var chiudi
    @State private var p: JProfilo?
    @State private var s: JSchedaSocio?
    @State private var attrezzi: Int?
    @State private var qr = false
    @State private var esci = false
    @State private var dispositivo = false

    var body: some View {
        let _ = Contatori.disegno("ProfiloTab")
        NavigationStack {
            Group {
                if jsoc.collegato { contenuto } else { EntraView() }
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $qr) { QRAppello() }
        .sheet(isPresented: $dispositivo) { InvitoSheet(dispositivo: true) }
        .task { await carica() }
    }

    var contenuto: some View {
        VStack(alignment: .leading, spacing: 0) {
            // intestazione: indietro, "Profilo" 24, "Fine"
            HStack(spacing: 8) {
                Button { chiudi() } label: {
                    IconaTela(d: Ic.indietro, colore: Theme.testo, lato: 18)
                        .frame(width: 42, height: 42).background(Theme.surface, in: Circle()).overlay(Circle().strokeBorder(Theme.stroke))
                }
                .accessibilityLabel("Indietro")
                Text("Profilo").font(.system(size: 24, weight: .black)).foregroundStyle(Theme.testo)
                Spacer()
                Button("Fine") { chiudi() }.font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.oliveBright).frame(height: 36).padding(.horizontal, 12)
            }
            .padding(.horizontal, 14).padding(.top, 7)

            VStack(alignment: .leading, spacing: 11) {
                tessera
                completezza
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(riquadri, id: \.titolo) { r in
                        NavigationLink { r.vista().background(Theme.bg.ignoresSafeArea()) } label: { RiquadroProfilo(r: r) }
                            .buttonStyle(PressStyle())
                    }
                }
                Button { esci = true } label: {
                    Text("Esci da questo telefono").font(.system(size: 13.5, weight: .heavy)).foregroundStyle(Theme.red)
                        .frame(maxWidth: .infinity).frame(height: 40)
                }
            }
            .padding(.horizontal, 14).padding(.top, 12)
            Spacer(minLength: 0)
        }
        .confirmationDialog("Uscire da JSOC TAK su questo telefono?", isPresented: $esci, titleVisibility: .visible) {
            Button("Esci", role: .destructive) { jsoc.esci() }
        } message: { Text("Per rientrare servirà un nuovo invito.") }
    }

    // MARK: tessera (tavola: fondo #1d2416, bordo verde 35%, avatar 58, sigla mono 19, QR bianco 48)

    var tessera: some View {
        HStack(spacing: 12) {
            FotoSocio(id: jsoc.utente?.id, iniziali: jsoc.utente?.callsign ?? "?", lato: 58)
                .overlay(Circle().strokeBorder(Theme.olive, lineWidth: 2))
            VStack(alignment: .leading, spacing: 0) {
                Text(jsoc.utente?.callsign ?? "").font(Theme.mono(19, .heavy)).foregroundStyle(Theme.testo)
                Text(sottotitolo).font(.system(size: 12)).foregroundStyle(Theme.testo2).lineLimit(1).padding(.top, 1)
                HStack(spacing: 5) {
                    ForEach(etichette, id: \.0) { Etichetta(testo: $0.0, colore: $0.1) }
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
            Button { qr = true } label: {
                IconaTela(d: Ic.qr, colore: Theme.scuro, lato: 26)
                    .frame(width: 48, height: 48).background(Theme.testo, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .accessibilityLabel("Mostra il QR per l'appello")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color(hex: 0x1D2416), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.olive.opacity(0.35)))
    }

    var sottotitolo: String {
        var t = p?.nome ?? jsoc.utente?.nome ?? ""
        if let a = s?.ammesso, a.count >= 4 { t += " · socio dal \(a.prefix(4))" }
        return t
    }

    var etichette: [(String, Color)] {
        var e: [(String, Color)] = [((s?.carica ?? jsoc.utente?.ruolo ?? "socio").uppercased(), Theme.oliveBright)]
        let anno = Calendar.current.component(.year, from: Date())
        if let t = s?.tesseramenti?.first(where: { $0.anno == anno || $0.anno == anno + 1 }) {
            e.append(("FIGT \(t.anno) · " + (t.intranet == 1 ? "ASSICURATO" : "NON ASSICURATO"), t.intranet == 1 ? Theme.cyan : Theme.amber))
        }
        return e
    }

    // MARK: completezza (tavola: "Profilo completo all'85%" + "manca: indirizzo ›", barra ambra)

    var campiMancanti: [String] {
        guard let p else { return [] }
        let c: [(String, String?)] = [("email", p.email), ("telefono", p.telefono), ("data di nascita", p.nascita), ("luogo di nascita", p.luogo_nascita),
                                      ("codice fiscale", p.cf), ("indirizzo", p.indirizzo), ("certificato", p.certificato_scadenza),
                                      ("gruppo sanguigno", p.gruppo_sanguigno), ("contatto di emergenza", p.emergenza)]
        return c.filter { ($0.1 ?? "").isEmpty }.map(\.0)
    }

    @ViewBuilder var completezza: some View {
        if p != nil {
            let manca = campiMancanti
            let perc = Int((Double(9 - manca.count) / 9 * 100).rounded())
            NavigationLink { MieiDatiView() } label: {
                VStack(spacing: 7) {
                    HStack {
                        Text(manca.isEmpty ? "Profilo completo" : "Profilo completo " + (perc == 1 || perc == 11 || String(perc).hasPrefix("8") ? "all'" : "al ") + "\(perc)%")
                            .font(.system(size: 12.5, weight: .heavy)).foregroundStyle(Theme.testo)
                        Spacer()
                        if let m = manca.first { Text("manca: \(m) ›").font(.system(size: 12.5, weight: .heavy)).foregroundStyle(Theme.amber) }
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(hex: 0x2A3120))
                            Capsule().fill(manca.isEmpty ? Theme.olive : Theme.amber).frame(width: g.size.width * CGFloat(perc) / 100)
                        }
                    }
                    .frame(height: 6)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder((manca.isEmpty ? Theme.olive : Theme.amber).opacity(0.35)))
            }
            .buttonStyle(PressStyle())
        }
    }

    // MARK: riquadri

    struct Riquadro {
        let icona: String; let colore: Color; let titolo: String; let sotto: String
        var segno: String? = nil; var coloreSegno: Color = Theme.dim; var bordo: Color? = nil
        let vista: () -> AnyView
    }

    var riquadri: [Riquadro] {
        let id = jsoc.utente?.id ?? 0
        let gc = p?.giorniCertificato
        let quotaDaPagare = p?.quote?.contains { $0.pagata != 1 } ?? false
        let anno = Calendar.current.component(.year, from: Date()) + 1
        let datiMancanti = campiMancanti.filter { !["certificato", "gruppo sanguigno", "contatto di emergenza"].contains($0) }.count
        let disp = s?.dispositivi?.count ?? 0
        var salute: (String?, Color) = (nil, Theme.dim)
        if let g = gc { salute = g < 0 ? ("scaduto", Theme.red) : g <= 30 ? ("scade \(g) g", Theme.red) : (nil, Theme.dim) } else { salute = ("manca", Theme.red) }
        return [
            Riquadro(icona: Ic.persona, colore: Theme.olive, titolo: "I miei dati", sotto: "Anagrafica, contatti, residenza",
                     segno: datiMancanti > 0 ? "\(datiMancanti) da fare" : nil, coloreSegno: Theme.amber, bordo: datiMancanti > 0 ? Theme.amber : nil) { AnyView(MieiDatiView()) },
            Riquadro(icona: Ic.cuore, colore: Theme.red, titolo: "Salute", sotto: "Certificato, emergenza",
                     segno: salute.0, coloreSegno: salute.1, bordo: salute.0 != nil ? Theme.red : nil) { AnyView(MieiDatiView(salute: true)) },
            Riquadro(icona: Ic.carta, colore: Theme.amber, titolo: "Quote e presenze",
                     sotto: "Quota \(anno) · \(s?.statistiche?.presenze ?? 0) presenze",
                     segno: quotaDaPagare ? "da pagare" : nil, coloreSegno: Theme.amber, bordo: quotaDaPagare ? Theme.amber : nil) { AnyView(SchedaSocioView(id: id)) },
            Riquadro(icona: Ic.scudo, colore: Theme.cyan, titolo: "Attrezzatura", sotto: attrezzi.map { "\($0) oggetti" } ?? "ASG e accessori") { AnyView(AttrezzaturaView()) },
            Riquadro(icona: Ic.scatola, colore: Theme.cyan, titolo: "Archivio", sotto: "Tracce e pacchetti") { AnyView(ArchivioPersonaleView()) },
            Riquadro(icona: Ic.ingranaggio, colore: Theme.dim, titolo: "Impostazioni", sotto: "Posizione, notte, server") { AnyView(ImpostazioniProfilo()) },
            Riquadro(icona: Ic.dispositivi, colore: Theme.dim, titolo: "Dispositivi", sotto: (s?.dispositivi ?? []).compactMap(\.nome).prefix(2).joined(separator: " · ").ifEmpty("Collega iPad o orologio"),
                     segno: disp > 0 ? "\(disp)" : nil) { AnyView(DispositiviProfilo()) },
            Riquadro(icona: Ic.documento, colore: Theme.oliveBright, titolo: "Documenti", sotto: "Tessera, certificato, assicurazione") { AnyView(SchedaSocioView(id: id)) },
        ]
    }

    func carica() async {
        guard jsoc.collegato, !Anteprima.attiva else {
            if Anteprima.attiva { p = Anteprima.profilo; s = Anteprima.scheda; attrezzi = 15 }
            return
        }
        p = try? await jsoc.profilo()
        if let id = jsoc.utente?.id { s = try? await jsoc.schedaSocio(id) }
    }
}

extension String {
    func ifEmpty(_ alt: String) -> String { isEmpty ? alt : self }
}

/// riquadro della tavola: 100 alto, angoli 16, icona in quadratino 32, segno in alto a destra, titolo 14 e sotto 11
struct RiquadroProfilo: View {
    let r: ProfiloTab.Riquadro
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                IconaTela(d: r.icona, colore: r.colore, lato: 18)
                    .frame(width: 32, height: 32).background(r.colore.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer()
                if let s = r.segno { Text(s).font(.system(size: 10, weight: .heavy)).foregroundStyle(r.coloreSegno) }
            }
            Spacer(minLength: 0)
            Text(r.titolo).font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.testo)
            Text(r.sotto).font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(1).padding(.top, 2)
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading).frame(height: 100)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(r.bordo?.opacity(0.4) ?? Theme.stroke))
    }
}

/// QR della tessera per l'appello all'ingresso del campo
struct QRAppello: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @Environment(\.dismiss) private var chiudi
    var body: some View {
        VStack(spacing: 18) {
            Text(jsoc.utente?.callsign ?? "").font(Theme.mono(28, .heavy)).foregroundStyle(Theme.testo)
            if let q = QR.immagine("JSOC:\(jsoc.utente?.id ?? 0):\(jsoc.utente?.callsign ?? "")", scala: 10) {
                Image(uiImage: q).interpolation(.none).resizable().frame(width: 260, height: 260)
                    .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 18))
            }
            Text("Mostra questo codice all'ingresso del campo per l'appello.").font(.system(size: 14)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            Button("Chiudi") { chiudi() }.font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.oliveBright)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
    }
}

/// Impostazioni (dal riquadro): posizione, notte, server, orologio
struct ImpostazioniProfilo: View {
    @ObservedObject private var store = EventoStore.shared
    @EnvironmentObject var night: NightMode
    var body: some View {
        Form {
            Section {
                Toggle("Condividi posizione e direzione agli eventi", isOn: $store.condividiPosizione)
                Toggle("Modalità notturna (rosso)", isOn: Binding(get: { night.on }, set: { if $0 != night.on { night.toggle() } }))
                NavigationLink("Server e collegamento") { ServerInfoView() }
            }
        }
        .listaJSOC()
        .navigationTitle("Impostazioni")
    }
}

/// Dispositivi (dal riquadro): iPad con lo stesso profilo, orologio Garmin
struct DispositiviProfilo: View {
    @State private var collega = false
    var body: some View {
        Form {
            Section {
                Button { collega = true } label: { Label("Collega un altro dispositivo (iPad)", systemImage: "ipad.and.iphone") }
            } footer: { Text("Mostra un QR: lo inquadri dall'altro dispositivo ed entri con lo stesso profilo.") }
            OrologioGarminSezione()
        }
        .listaJSOC()
        .navigationTitle("Dispositivi")
        .sheet(isPresented: $collega) { InvitoSheet(dispositivo: true) }
    }
}
