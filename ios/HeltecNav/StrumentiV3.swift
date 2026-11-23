import SwiftUI

// MARK: - Strumenti (tavola 64): usati di recente, legenda, 12 riquadri uguali colorati per categoria.
// Tieni premuto un riquadro = lo metti nella barra rapida della mappa.

/// uno dei 12 strumenti della tavola
struct VoceStrumento: Identifiable, Hashable {
    enum Categoria { case campo, intelligence, giochi }
    let id: String
    let titolo: String
    let sotto: String
    let icona: String
    let categoria: Categoria
    var rosso = false
    /// voce corrispondente nella barra rapida della mappa (rawValue di `Strumento`), se c'è
    var rapido: String? = nil

    var colore: Color {
        if rosso { return Theme.red }
        switch categoria {
        case .campo: return Theme.olive
        case .intelligence: return Theme.cyan
        case .giochi: return Theme.amber
        }
    }

    static let tutte: [VoceStrumento] = [
        .init(id: "coordinate", titolo: "Coordinate", sotto: "converti e condividi", icona: Ic.stCoordinate, categoria: .campo, rapido: "vaiPunto"),
        .init(id: "mirino", titolo: "Mirino", sotto: "azimut con la bussola", icona: Ic.stMirino, categoria: .campo, rapido: "mirino"),
        .init(id: "triangolazione", titolo: "Triangolazione", sotto: "da 2-3 rilevamenti", icona: Ic.stTriangolo, categoria: .campo, rapido: "triangolazione"),
        .init(id: "telemetro", titolo: "Telemetro", sotto: "distanza dalla foto", icona: Ic.stTelemetro, categoria: .campo, rapido: "distanza"),
        .init(id: "balistica", titolo: "Balistica BB", sotto: "caduta e volo", icona: Ic.stBalistica, categoria: .campo, rapido: "balistica"),
        .init(id: "soccorso", titolo: "Primo soccorso", sotto: "MARCH passo passo", icona: Ic.stCroce, categoria: .campo, rosso: true, rapido: "medico"),
        .init(id: "cifrari", titolo: "Cifrari", sotto: "Cesare, Morse, Vigenère", icona: Ic.stLucchetto, categoria: .intelligence, rapido: "cifrari"),
        .init(id: "raccolta", titolo: "Raccolta", sotto: "foto, audio, QR", icona: Ic.fotocamera, categoria: .intelligence, rapido: "qr"),
        .init(id: "archivio", titolo: "Archivio", sotto: "tracce e punti miei", icona: Ic.stArchivio, categoria: .campo, rapido: "cronologia"),
        .init(id: "prove", titolo: "Prove pronte", sotto: "bomba, enigmi, quiz", icona: Ic.stFulmine, categoria: .giochi),
        .init(id: "missioni", titolo: "Missioni", sotto: "fasi, indizi, QR", icona: Ic.stBandiera, categoria: .giochi),
        .init(id: "dacampo", titolo: "Giochi da campo", sotto: "bandiera, nucleare", icona: Ic.stFiamma, categoria: .giochi),
    ]

    static func con(_ id: String) -> VoceStrumento? { tutte.first { $0.id == id } }

    /// la schermata vera dello strumento (quelle già esistenti; Coordinate e Giochi rifatte sulle tavole 65-66)
    @ViewBuilder var vista: some View {
        switch id {
        case "coordinate": CoordinateV3()
        case "mirino": MirinoView().strumentoClassico(titolo)
        case "triangolazione": TriangView().strumentoClassico(titolo)
        case "telemetro": TelemetroView().strumentoClassico(titolo)
        case "balistica": PannelloBalistica(chiudi: {}).strumentoClassico(titolo)
        case "soccorso": PannelloMedico(chiudi: {}).strumentoClassico(titolo)
        case "cifrari": CipherTab().strumentoClassico(titolo)
        case "raccolta": KitTab().strumentoClassico(titolo)
        case "archivio": ArchivioPersonaleView().strumentoClassico(titolo)
        case "prove": GiochiV3(scheda: 0)
        case "missioni": GiochiV3(scheda: 1)
        default: GiochiV3(scheda: 2)
        }
    }
}

extension View {
    /// strumenti già esistenti: barra di navigazione di sistema col titolo
    func strumentoClassico(_ titolo: String) -> some View {
        self.background(Theme.bg.ignoresSafeArea())
            .navigationTitle(titolo).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
    }
}

/// strumenti usati di recente (i primi 3 compaiono in alto)
enum RecentiStrumenti {
    static let chiave = "strum.recenti"
    static var elenco: [String] {
        if let s = UserDefaults.standard.string(forKey: chiave), !s.isEmpty { return s.split(separator: ",").map(String.init) }
        return Anteprima.attiva ? Anteprima.strumentiRecenti : []
    }
    static func usa(_ id: String) {
        let e = ([id] + elenco.filter { $0 != id }).prefix(6)
        UserDefaults.standard.set(e.joined(separator: ","), forKey: chiave)
    }
}

/// barra rapida della mappa: stessa chiave e stesso limite (8) usati da `BarraRapida` in MappaTattica.swift
enum BarraRapidaStrumenti {
    static let chiave = "mappa.rapidi"
    static var elenco: [String] {
        (UserDefaults.standard.string(forKey: chiave) ?? "segnala,distanza,cerchi,meteo").split(separator: ",").map(String.init)
    }
    /// restituisce il messaggio da mostrare
    static func metti(_ v: VoceStrumento) -> String {
        guard let r = v.rapido else { return "\(v.titolo) non ha un tasto sulla mappa" }
        var e = elenco
        if e.contains(r) { return "\(v.titolo) è già nella barra rapida" }
        guard e.count < BarraRapida.caselle else { return "Barra rapida piena (\(BarraRapida.caselle)): togline uno dalla mappa" }
        e.append(r)
        UserDefaults.standard.set(e.joined(separator: ","), forKey: chiave)
        return "\(v.titolo) aggiunto alla barra rapida della mappa"
    }
}

struct StrumentiV3: View {
    @State private var percorso: [String] = {
        // anteprime: -debug.strum.apri coordinate|prove|missioni|dacampo|<id strumento>
        if let a = UserDefaults.standard.string(forKey: "debug.strum.apri"), VoceStrumento.con(a) != nil { return [a] }
        return []
    }()
    @State private var recenti = RecentiStrumenti.elenco
    @State private var cerca = false
    @State private var avviso: String?
    @State private var premuto: String?      // dopo una pressione lunga il tocco non apre lo strumento

    var body: some View {
        let _ = Contatori.disegno("StrumentiV3")
        NavigationStack(path: $percorso) {
            contenuto
                .background(Theme.bg.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: String.self) { id in
                    if let v = VoceStrumento.con(id) { v.vista }
                }
        }
        .sheet(isPresented: $cerca) { CercaStrumento { v in cerca = false; apri(v) } }
        .overlay(alignment: .bottom) {
            if let a = avviso {
                Text(a).font(.system(size: 12.5, weight: .heavy)).foregroundStyle(Theme.scuro)
                    .padding(.horizontal, 14).frame(height: 36)
                    .background(Theme.oliveBright, in: Capsule())
                    .padding(.bottom, 92)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: a) { try? await Task.sleep(nanoseconds: 2_200_000_000); withAnimation { avviso = nil } }
            }
        }
        .animation(.spring(response: 0.3), value: avviso)
    }

    var contenuto: some View {
        VStack(alignment: .leading, spacing: 0) {
            // intestazione: top 54, lati 16, titolo 30 nero, cerca 42
            HStack {
                Text("Strumenti").font(.system(size: 30, weight: .black)).tracking(-0.6).foregroundStyle(Theme.testo)
                Spacer()
                Button { haptic(); cerca = true } label: {
                    IconaTela(d: Ic.cerca, colore: Theme.testo, lato: 18)
                        .frame(width: 42, height: 42).background(Theme.surface, in: Circle()).overlay(Circle().strokeBorder(Theme.stroke))
                }
                .accessibilityLabel("Cerca")
            }
            .padding(.horizontal, 16)
            .padding(.top, 7)

            ScrollView(showsIndicators: false) {
                // corpo: top 108, lati 14, spazio 12
                VStack(alignment: .leading, spacing: 12) {
                    if !recenti.isEmpty { usatiDiRecente }
                    legenda
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(VoceStrumento.tutte) { v in riquadro(v) }
                    }
                    Text("Tieni premuto uno strumento per metterlo nella barra rapida della mappa")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 90)
            }
        }
        .onAppear { recenti = RecentiStrumenti.elenco }
    }

    var usatiDiRecente: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("USATI DI RECENTE").font(.system(size: 11, weight: .heavy)).tracking(0.44).foregroundStyle(Theme.dim)
                .padding(.horizontal, 2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(recenti.prefix(3).compactMap(VoceStrumento.con)) { v in
                        Button { apri(v) } label: {
                            HStack(spacing: 6) {
                                IconaTela(d: v.icona, colore: v.colore, lato: 15)
                                Text(v.titolo).font(.system(size: 12.5, weight: .heavy)).foregroundStyle(Theme.testo).lineLimit(1)
                            }
                            .padding(.horizontal, 12).frame(height: 36)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(v.colore.opacity(0.333)))
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
        }
    }

    var legenda: some View {
        HStack(spacing: 14) {
            ForEach([("Da campo", Theme.olive), ("Intelligence", Theme.cyan), ("Giochi e missioni", Theme.amber)], id: \.0) { t in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(t.1).frame(width: 9, height: 9)
                    Text(t.0).font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.dim)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    func riquadro(_ v: VoceStrumento) -> some View {
        Button {
            if premuto == v.id { premuto = nil; return }
            apri(v)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                IconaTela(d: v.icona, colore: v.colore, lato: 19)
                    .frame(width: 34, height: 34)
                    .background(v.colore.opacity(0.133), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text(v.titolo).font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.testo)
                        .lineLimit(2).lineSpacing(-1).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(v.sotto).font(.system(size: 10)).foregroundStyle(Theme.dim).lineLimit(1).truncationMode(.tail)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 100)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
            premuto = v.id
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            avviso = BarraRapidaStrumenti.metti(v)
        })
        .accessibilityLabel("\(v.titolo), \(v.sotto)")
        .accessibilityHint("Tieni premuto per metterlo nella barra rapida della mappa")
    }

    func apri(_ v: VoceStrumento) {
        haptic()
        RecentiStrumenti.usa(v.id)
        percorso.append(v.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { recenti = RecentiStrumenti.elenco }
    }
}

/// ricerca tra i 12 strumenti
struct CercaStrumento: View {
    var scegli: (VoceStrumento) -> Void
    @State private var testo = ""
    @FocusState private var fuoco: Bool

    var risultati: [VoceStrumento] {
        let t = testo.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return VoceStrumento.tutte }
        return VoceStrumento.tutte.filter { $0.titolo.lowercased().contains(t) || $0.sotto.lowercased().contains(t) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RiquadroCampo(attivo: fuoco) {
                IconaTela(d: Ic.cerca, colore: Theme.dim, lato: 17)
                TextField("Cerca uno strumento", text: $testo)
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.testo)
                    .autocorrectionDisabled().focused($fuoco)
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(risultati) { v in
                        Button { scegli(v) } label: {
                            HStack(spacing: 10) {
                                IconaTela(d: v.icona, colore: v.colore, lato: 18)
                                    .frame(width: 34, height: 34)
                                    .background(v.colore.opacity(0.133), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(v.titolo).font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.testo)
                                    Text(v.sotto).font(.system(size: 11)).foregroundStyle(Theme.dim)
                                }
                                Spacer()
                                IconaTela(d: Ic.avanti, colore: Theme.dim, lato: 14)
                            }
                            .padding(10)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke))
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
        }
        .padding(14).padding(.top, 8)
        .background(Theme.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .onAppear { fuoco = true }
    }
}
