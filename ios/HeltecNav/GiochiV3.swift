import SwiftUI

// MARK: - Giochi e missioni (tavola 66): Prove pronte / Missioni / Da campo.
// Prove pronte: 9 tipi di prova, difficoltà, tempo, tentativi, "Avvia la prova" (partita di ProvePronte.swift).
// Missioni e Da campo aprono le schermate già esistenti (MissioniView, GiochiCampoView).

struct GiochiV3: View {
    @Environment(\.dismiss) private var chiudi
    @State private var scheda: Int
    @AppStorage("strum.prova.tipo") private var tipoRaw = TipoProva.fili.rawValue
    @AppStorage("strum.prova.difficolta") private var difficolta = 1
    @AppStorage("strum.prova.minuti") private var minuti = 5
    @AppStorage("strum.prova.tentativi") private var tentativi = 3
    @State private var partita = false

    /// iPad (tavola 70): nel pannello a destra di Strumenti, senza tasto indietro
    var pannello = false

    init(scheda: Int = 0, pannello: Bool = false) { _scheda = State(initialValue: scheda); self.pannello = pannello }

    /// i 9 riquadri della tavola → tipi di prova esistenti
    static let prove: [(TipoProva, String, String, String)] = [
        (.fili, "Disinnesca", "fili e regole", Ic.stFulmine),
        (.cifrario, "Cifrario", "decodifica il messaggio", Ic.stLucchetto),
        (.lucchetto, "Lucchetto", "trova il codice", Ic.stLucchetto),
        (.sequenza, "Enigma", "logica e indizi", Ic.stDomanda),
        (.labirinto, "Labirinto", "a due telefoni", Ic.stLabirinto),
        (.raggiungi, "Raggiungi", "il punto GPS", Ic.segnaposto),
        (.kim, "Memoria", "Kim a vista", Ic.stOrologio),
        (.calcolo, "Calcolo", "rapido sotto stress", Ic.stPiu),
        (.azimut, "Azimut", "punta la direzione", Ic.stAzimut),
    ]

    var tipo: TipoProva { TipoProva(rawValue: tipoRaw) ?? .fili }
    /// Facile / Media / Difficile / Estrema → livelli della partita (Estrema = Difficile con penalità doppia)
    var livello: LivelloProva { [.facile, .medio, .difficile, .difficile][min(max(difficolta, 0), 3)] }

    var body: some View {
        let _ = GuidaApp.segna("giochi")
        VStack(alignment: .leading, spacing: 0) {
            if pannello {
                Text("Giochi e missioni").font(.system(size: 30, weight: .black)).tracking(-0.6).foregroundStyle(Theme.testo)
                    .padding(.top, 2)
            } else {
            // intestazione: top 54, lati 14
            HStack(spacing: 8) {
                Button { chiudi() } label: {
                    IconaTela(d: Ic.indietro, colore: Theme.testo, lato: 18)
                        .frame(width: 42, height: 42).background(Theme.surface, in: Circle()).overlay(Circle().strokeBorder(Theme.stroke))
                }
                .accessibilityLabel("Indietro")
                Text("Giochi e missioni").font(.system(size: 24, weight: .black)).foregroundStyle(Theme.testo)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 7)
            }

            // corpo: top 108, lati 14, spazio 11
            SchedeTela(voci: ["Prove pronte", "Missioni", "Da campo"], scelta: $scheda)
                .padding(.horizontal, pannello ? 0 : 14).padding(.top, 12)

            switch scheda {
            case 0:
                ScrollView(showsIndicators: false) { provePronte.padding(.horizontal, pannello ? 0 : 14).padding(.top, 11).padding(.bottom, 30) }
            case 1:
                MissioniView().padding(.top, 4)
            default:
                GiochiCampoView().padding(.top, 4)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { if !pannello { ModuliAperti.shared.aperti += 1 } }        // tavola 66: senza la barra in basso
        .onDisappear { if !pannello { ModuliAperti.shared.aperti = max(0, ModuliAperti.shared.aperti - 1) } }
        .fullScreenCover(isPresented: $partita) {
            PartitaProva(tipi: [tipo], livello: livello, squadra: "", minuti: minuti, tentativi: tentativi, estrema: difficolta == 3) {
                partita = false
            }
        }
    }

    var provePronte: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Scegli il tipo di prova: la squadra la risolve a tempo. Ogni volta è diversa.")
                .font(.system(size: 12)).foregroundStyle(Theme.dim).lineSpacing(2.4)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
                ForEach(Self.prove, id: \.0) { p in riquadro(p) }
            }
            VStack(alignment: .leading, spacing: 5) {
                EtichettaCampo(testo: "Difficoltà")
                SceltaTela(voci: ["Facile", "Media", "Difficile", "Estrema"], scelta: $difficolta)
            }
            HStack(spacing: 8) {
                contatore("Tempo", valore: $minuti, unita: "min", da: 1, a: 60)
                contatore("Tentativi", valore: $tentativi, unita: "", da: 1, a: 9)
            }
            Button { haptic(.medium); partita = true } label: {
                Text("Avvia la prova").font(.system(size: 16, weight: .black)).foregroundStyle(Theme.scuro)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(Theme.amber, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressStyle())
            NavigationLink { ManualeProvaView() } label: {
                Text("Sono il manuale (secondo telefono)").font(.system(size: 12.5, weight: .heavy)).foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity).frame(height: 36)
            }
        }
    }

    func riquadro(_ p: (TipoProva, String, String, String)) -> some View {
        let on = p.0 == tipo
        return Button { haptic(.soft); tipoRaw = p.0.rawValue } label: {
            VStack(alignment: .leading, spacing: 0) {
                IconaTela(d: p.3, colore: Theme.amber, lato: 19)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 0) {
                    Text(p.1).font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.testo).lineLimit(1)
                    Text(p.2).font(.system(size: 10)).foregroundStyle(Theme.dim).lineLimit(1).truncationMode(.tail)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 84)
            .background(on ? Color(hex: 0x2A2210) : Theme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(on ? Theme.amber : Theme.stroke, lineWidth: on ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(p.1), \(p.2)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    func contatore(_ titolo: String, valore: Binding<Int>, unita: String, da: Int, a: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            EtichettaCampo(testo: titolo)
            HStack(spacing: 0) {
                Button { haptic(.soft); valore.wrappedValue = max(da, valore.wrappedValue - 1) } label: {
                    Text("−").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.testo).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Meno")
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(valore.wrappedValue)").font(Theme.mono(15, .heavy)).foregroundStyle(Theme.testo)
                    if !unita.isEmpty { Text(unita).font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.dim) }
                }
                .frame(maxWidth: .infinity)
                Button { haptic(.soft); valore.wrappedValue = min(a, valore.wrappedValue + 1) } label: {
                    Text("+").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.testo).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Più")
            }
            .frame(height: 46)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke))
        }
        .frame(maxWidth: .infinity)
    }
}
