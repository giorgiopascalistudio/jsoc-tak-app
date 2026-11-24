import SwiftUI
import PhotosUI

/// Cifrari. "Decifra" prova da solo tutti i metodi (anche a più strati) e mette in cima il più probabile;
/// "Catena" applica a mano più passaggi in fila, ognuno in cifratura o decifratura.
struct CipherTab: View {
    enum Strumento: String, CaseIterable, Identifiable {
        case decifra = "Decifra", catena = "Catena", morse = "Morse", binario = "Binario", audio = "Audio", campo = "Campo"
        var id: String { rawValue }
        var icona: String {
            switch self {
            case .decifra: return "wand.and.stars"
            case .catena: return "link"
            case .morse: return "waveform"
            case .binario: return "01.square"
            case .audio: return "waveform.path.ecg"
            case .campo: return "scope"
            }
        }
    }

    @AppStorage("cipher.strumento") private var strumentoRaw = Strumento.decifra.rawValue
    @AppStorage("cipher.input") private var input = ""
    @StateObject private var chain = ChainModel()
    @State private var mirino = false
    @FocusState private var editing: Bool

    var strumento: Strumento { Strumento(rawValue: strumentoRaw) ?? .decifra }

    var body: some View {
        let _ = GuidaApp.segna("cifrari")
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 5) {
                    ForEach(Strumento.allCases) { s in
                        Button {
                            haptic(.soft)
                            withAnimation(.easeInOut(duration: 0.2)) { strumentoRaw = s.rawValue }
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: s.icona).font(.system(size: 17, weight: .semibold))
                                Text(s.rawValue).font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(strumento == s ? Color.black : Theme.gold)
                            .background(strumento == s ? Theme.gold : Theme.card, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding(.horizontal).padding(.vertical, 8)

                ScrollView {
                    VStack(spacing: 12) {
                        switch strumento {
                        case .decifra:
                            DecifraView(input: $input, editing: $editing) { passi in
                                chain.steps = passi
                                strumentoRaw = Strumento.catena.rawValue
                            }
                        case .catena: ChainView(input: $input, editing: $editing, chain: chain)
                        case .morse: MorseView(input: $input, vaiADecifra: { strumentoRaw = Strumento.decifra.rawValue })
                        case .binario: BinarioView(input: $input, editing: $editing)
                        case .audio: AudioLabView()
                        case .campo: CampoView()
                        }
                    }
                    .padding(.horizontal).padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(Theme.bg.ignoresSafeArea())
            }
            .navigationTitle("Strumenti")
            .nightToggle()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fine") { editing = false; UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
            }
        }
    }
}

// MARK: - Riquadro di ingresso (incolla, foto, OCR)

struct InputCard: View {
    @Binding var input: String
    var editing: FocusState<Bool>.Binding
    var placeholder: String
    @State private var camera = false
    @State private var photo: PhotosPickerItem?
    @State private var leggo = false

    var body: some View {
        Card {
            HStack {
                Text("\(input.count) caratteri").font(.caption2).foregroundStyle(Theme.dim)
                Spacer()
                Button { if let s = UIPasteboard.general.string { input = s } } label: { Image(systemName: "doc.on.clipboard") }
                Button { camera = true } label: { Image(systemName: "camera") }
                PhotosPicker(selection: $photo, matching: .images) { Image(systemName: "photo") }
                Button(role: .destructive) { input = "" } label: { Image(systemName: "xmark.circle") }
            }
            .buttonStyle(.bordered).controlSize(.small)
            TextEditor(text: $input)
                .font(Theme.mono(16))
                .frame(minHeight: 84, maxHeight: 180)
                .scrollContentBackground(.hidden)
                .focused(editing)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .overlay(alignment: .topLeading) {
                    if input.isEmpty {
                        Text(placeholder).font(.footnote).foregroundStyle(Theme.dim)
                            .padding(.top, 8).padding(.leading, 4).allowsHitTesting(false)
                    }
                }
            if leggo { ProgressView("Leggo il testo dalla foto…") }
        }
        .sheet(isPresented: $camera) { CameraPicker { img in leggi(img) }.ignoresSafeArea() }
        .onChange(of: photo) { item in
            guard let item else { return }
            Task {
                if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) { leggi(img) }
                photo = nil
            }
        }
    }

    func leggi(_ img: UIImage) {
        leggo = true
        Task {
            let t = await OCR.text(from: img)
            await MainActor.run { input = t; leggo = false }
        }
    }
}

// MARK: - Decifra (automatico, a più strati)

struct DecifraView: View {
    @Binding var input: String
    var editing: FocusState<Bool>.Binding
    var apriInCatena: ([ChainStep]) -> Void
    @EnvironmentObject var log: FieldLog
    @EnvironmentObject var location: LocationService
    @AppStorage("cipher.chiavi") private var chiaviExtra = ""
    @State private var letture: [Lettura] = []
    @State private var tutte = false
    @State private var calcolo: Task<Void, Never>?
    @State private var lavoro = false
    @State private var aperta: Lettura.ID?
    @State private var info: Op?

    @Environment(\.verticalSizeClass) var vsc

    var chiavi: [String] {
        Cipher.gameKeys + chiaviExtra.uppercased().components(separatedBy: CharacterSet.letters.inverted).filter { $0.count >= 2 }
    }

    var body: some View {
        Group {
            if vsc == .compact {
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 12) { ingresso }.frame(maxWidth: .infinity)
                    VStack(spacing: 12) { risultati }.frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 12) { ingresso; risultati }
            }
        }
        .onAppear { ricalcola() }
        .onChange(of: input) { _ in ricalcola() }
        .onChange(of: chiaviExtra) { _ in ricalcola() }
        .sheet(item: $info) { OpInfoSheet(op: $0) }
    }

    @ViewBuilder var ingresso: some View {
        InputCard(input: $input, editing: editing,
                  placeholder: "Incolla o scrivi il messaggio: provo tutto io, anche più cifrature una sopra l'altra (Base64, esadecimale, Morse, numeri, Cesare, Vigenère con le chiavi di gara, trasposizioni…)")
        Card(title: "Chiavi provate") {
            Text(Cipher.gameKeys.joined(separator: " · ")).font(.caption).foregroundStyle(Theme.dim)
            TextField("Altre chiavi (separate da spazio)", text: $chiaviExtra).font(Theme.mono(14)).textFieldStyle(.roundedBorder)
                .autocorrectionDisabled().textInputAutocapitalization(.characters)
        }
    }

    @ViewBuilder var risultati: some View {
            if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if lavoro { HStack { ProgressView(); Text("Provo le combinazioni…").font(.caption).foregroundStyle(Theme.dim) } }
                let mostrate = tutte ? Array(letture.prefix(300)) : Array(letture.prefix(8))
                ForEach(Array(mostrate.enumerated()), id: \.element.id) { i, l in
                    letturaCard(l, prima: i == 0)
                }
                if letture.count > 8 {
                    Button(tutte ? "Mostra meno" : "Mostra altre letture (\(min(letture.count, 300)))") { tutte.toggle() }.font(.footnote)
                }
                DisclosureGroup("Frequenze delle lettere") {
                    Text(Cipher.frequencies(input)).font(Theme.mono(11)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.footnote).padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            }
    }

    func letturaCard(_ l: Lettura, prima: Bool) -> some View {
        let espansa = aperta == l.id || prima
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(l.metodo).font(.caption.weight(.bold)).foregroundStyle(prima ? Color.black : Theme.gold)
                Spacer()
                if !l.parole.isEmpty {
                    Text(l.parole.prefix(3).joined(separator: " ")).font(.caption2.weight(.semibold))
                        .foregroundStyle(prima ? Color.black.opacity(0.7) : Theme.green)
                }
            }
            Text(l.testo).font(Theme.mono(prima ? 17 : 14, prima ? .bold : .regular))
                .foregroundStyle(prima ? Color.black : Color.white)
                .lineLimit(espansa ? nil : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if espansa {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        Button { copyToClipboard(l.testo) } label: { Label("Copia", systemImage: "doc.on.doc") }
                        Button { input = l.testo } label: { Label("Usa", systemImage: "arrow.up") }
                        if !l.passi.isEmpty {
                            Button { apriInCatena(l.passi) } label: { Label("Catena", systemImage: "link") }
                        }
                        ForEach(Array(Set(l.passi.map(\.op))), id: \.self) { op in
                            Button { info = op } label: { Label(op.titolo, systemImage: "info.circle") }
                        }
                        Button { log.add(.testo, "\(l.metodo): \(l.testo.prefix(500))", at: location.location) } label: {
                            Label("Registra", systemImage: "tray.and.arrow.down")
                        }
                    }
                }
                .font(.caption).buttonStyle(.bordered).tint(prima ? .black : Theme.gold)
            }
        }
        .padding(12)
        .background(prima ? Theme.gold : Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { aperta = aperta == l.id ? nil : l.id } }
    }

    func ricalcola() {
        calcolo?.cancel()
        let t = input, k = chiavi
        calcolo = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            lavoro = true
            let r = await Task.detached(priority: .userInitiated) { AutoDecode.tutte(t, chiavi: k) }.value
            if Task.isCancelled { return }
            letture = r
            tutte = false
            lavoro = false
        }
    }
}

// MARK: - Catena (cifra e decifra a mano, più passaggi)

@MainActor
final class ChainModel: ObservableObject {
    @Published var steps: [ChainStep] = [] { didSet { save() } }

    init() {
        if let s = UserDefaults.standard.data(forKey: "chain.steps"), let v = try? JSONDecoder().decode([ChainStep].self, from: s) {
            steps = v
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(steps) { UserDefaults.standard.set(d, forKey: "chain.steps") }
    }
}

struct ChainView: View {
    @Binding var input: String
    var editing: FocusState<Bool>.Binding
    @ObservedObject var chain: ChainModel
    @EnvironmentObject var log: FieldLog
    @EnvironmentObject var location: LocationService
    @State private var picking = false
    @State private var info: Op?

    var body: some View {
        let outputs = Chain.run(chain.steps, input)
        VStack(spacing: 12) {
            InputCard(input: $input, editing: editing,
                      placeholder: "Testo di partenza. Aggiungi i passaggi sotto: ognuno lavora sul risultato del precedente.")
            ForEach(Array(chain.steps.enumerated()), id: \.element.id) { i, st in
                stepCard(i, outputs[i])
            }
            Button { picking = true } label: {
                Label(chain.steps.isEmpty ? "Aggiungi il primo passaggio" : "Aggiungi un passaggio", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Theme.gold).foregroundStyle(.black)
            if !chain.steps.isEmpty {
                Card(title: "Risultato finale") {
                    Text(outputs.last ?? "").font(Theme.mono(16, .semibold)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Button { copyToClipboard(outputs.last ?? "") } label: { Label("Copia", systemImage: "doc.on.doc") }
                        Button { input = outputs.last ?? input; chain.steps = [] } label: { Label("Usa come testo", systemImage: "arrow.up") }
                        Button { log.add(.testo, chain.steps.map(\.etichetta).joined(separator: " → ") + ": " + String((outputs.last ?? "").prefix(500)), at: location.location) } label: {
                            Label("Registra", systemImage: "tray.and.arrow.down")
                        }
                    }
                    .buttonStyle(.bordered).font(.caption)
                    Button("Inverti la catena (per decifrare ciò che hai cifrato)") { invertiCatena() }.font(.caption)
                    Button("Svuota catena", role: .destructive) { chain.steps = [] }.font(.caption)
                }
            }
        }
        .sheet(isPresented: $picking) {
            OpPicker { op in chain.steps.append(ChainStep(op: op, encode: false, params: op.defaultParams)) }
        }
        .sheet(item: $info) { OpInfoSheet(op: $0) }
    }

    func invertiCatena() {
        chain.steps = chain.steps.reversed().map { var s = $0; if !s.op.unSoloVerso { s.encode.toggle() }; s.id = UUID(); return s }
    }

    @ViewBuilder
    func stepCard(_ i: Int, _ out: String) -> some View {
        let st = chain.steps[i]
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(i + 1)").font(Theme.mono(13, .bold)).foregroundStyle(.black)
                    .frame(width: 24, height: 24).background(Theme.gold, in: Circle())
                Text(st.op.titolo).font(.subheadline.weight(.bold))
                Button { info = st.op } label: { Image(systemName: "info.circle") }
                Spacer()
                Menu {
                    if i > 0 { Button("Sposta su") { chain.steps.swapAt(i, i - 1) } }
                    if i < chain.steps.count - 1 { Button("Sposta giù") { chain.steps.swapAt(i, i + 1) } }
                    Button("Duplica") { var c = st; c.id = UUID(); chain.steps.insert(c, at: i + 1) }
                    Button("Elimina", role: .destructive) { chain.steps.remove(at: i) }
                } label: { Image(systemName: "ellipsis.circle").font(.title3) }
            }
            if !st.op.unSoloVerso {
                Picker("", selection: binding(i, \.encode)) {
                    Text("Decifra / decodifica").tag(false)
                    Text("Cifra / codifica").tag(true)
                }
                .pickerStyle(.segmented)
            }
            if let label = st.op.usaN {
                Stepper("\(label): \(st.params.n)", value: binding(i, \.params.n), in: st.op == .affine ? 1...25 : (st.op == .baseConv ? 2...36 : 1...30))
                    .font(.caption)
            }
            if let label = st.op.usaN2 {
                Stepper("\(label): \(st.params.n2)", value: binding(i, \.params.n2), in: st.op == .baseConv ? 2...36 : 0...30).font(.caption)
            }
            if let label = st.op.usaChiave {
                TextField(label, text: binding(i, \.params.key)).font(Theme.mono(14)).textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled().textInputAutocapitalization(.characters)
                if [.vigenere, .beaufort, .autokey, .keyword, .playfair, .bifid, .columnar, .polybius].contains(st.op) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(Cipher.gameKeys, id: \.self) { k in
                            Button(k) { chain.steps[i].params.key = k }.font(.caption2).buttonStyle(.bordered)
                        } }
                    }
                }
            }
            if st.op.usaAlfabeto {
                Picker("Alfabeto", selection: binding(i, \.params.alfabeto)) {
                    ForEach(Alfabeto.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Text(out.isEmpty ? "—" : out).font(Theme.mono(14)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8).background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    func binding<T>(_ i: Int, _ kp: WritableKeyPath<ChainStep, T>) -> Binding<T> {
        Binding(get: { i < chain.steps.count ? chain.steps[i][keyPath: kp] : ChainStep(op: .reverse, encode: false, params: OpParams())[keyPath: kp] },
                set: { if i < chain.steps.count { chain.steps[i][keyPath: kp] = $0 } })
    }
}

// MARK: - Scelta del metodo e spiegazioni

struct OpPicker: View {
    var onPick: (Op) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var query = ""
    @State private var info: Op?

    var body: some View {
        NavigationStack {
            List {
                ForEach(OpCategoria.allCases) { cat in
                    let ops = Op.lista(cat).filter { query.isEmpty || $0.titolo.localizedCaseInsensitiveContains(query) }
                    if !ops.isEmpty {
                        Section(cat.rawValue) {
                            ForEach(ops) { op in
                                HStack {
                                    Button { onPick(op); dismiss() } label: {
                                        Text(op.titolo).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    Button { info = op } label: { Image(systemName: "info.circle").foregroundStyle(Theme.gold) }
                                        .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Cerca un metodo")
            .navigationTitle("Metodi (\(Op.allCases.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Chiudi") { dismiss() } }
            .sheet(item: $info) { OpInfoSheet(op: $0) }
        }
    }
}

struct OpInfoSheet: View {
    let op: Op
    @Environment(\.dismiss) var dismiss

    var body: some View {
        let s = op.spiegazione
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(op.categoria.rawValue.uppercased()).font(.caption.weight(.heavy)).foregroundStyle(Theme.gold)
                    sezione("Come funziona", s.come)
                    if s.esempio != "—" { sezione("Esempio", s.esempio, mono: true) }
                    sezione("Quando sospettarlo", s.indizi)
                    if op.unSoloVerso {
                        Text("Si usa in un solo verso (o cifrare e decifrare sono la stessa cosa).").font(.caption).foregroundStyle(Theme.dim)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(op.titolo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Chiudi") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }

    func sezione(_ t: String, _ body: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t).font(.subheadline.weight(.bold))
            Text(body).font(mono ? Theme.mono(14) : .body).textSelection(.enabled)
        }
    }
}

extension String {
    func leftPad(_ n: Int, _ c: Character = "0") -> String { count >= n ? self : String(repeating: c, count: n - count) + self }
}

// MARK: - Binario

struct BinarioView: View {
    @Binding var input: String
    var editing: FocusState<Bool>.Binding
    @AppStorage("bin.bit") private var bit = 8

    var eBinario: Bool { !input.isEmpty && input.allSatisfy { "01 \n".contains($0) } }

    var output: String {
        if eBinario {
            let b = input.filter { $0 == "0" || $0 == "1" }
            // con gli spazi: ogni gruppo è un carattere; senza: blocchi da "bit"
            let gruppi = input.contains(" ") ? input.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
                : stride(from: 0, to: b.count, by: bit).map { i in String(Array(b)[i..<min(i + bit, b.count)]) }
            let testo = gruppi.compactMap { g -> String? in
                guard let v = Int(g, radix: 2) else { return nil }
                if bit == 5 || (g.count <= 5 && v >= 1 && v <= 26) { return String(Cipher.letter(v - 1, upper: true)) }  // 5 bit: A=1
                return v < 128 ? String(Character(UnicodeScalar(UInt8(v)))) : "?"
            }.joined()
            let numeri = gruppi.compactMap { Int($0, radix: 2) }.map(String.init).joined(separator: " ")
            return "\(testo)\n\nNumeri: \(numeri)"
        }
        return input.utf8.map { String($0, radix: 2).leftPad(bit == 5 ? 8 : bit) }.joined(separator: " ")
            + "\n\nDecimale: " + input.utf8.map(String.init).joined(separator: " ")
            + "\nEsadecimale: " + input.utf8.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    var body: some View {
        Card(title: eBinario ? "Binario → testo" : "Testo → binario") {
            TextEditor(text: $input).font(Theme.mono(16)).frame(minHeight: 80, maxHeight: 140)
                .scrollContentBackground(.hidden).focused(editing)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
            Picker("Bit", selection: $bit) {
                Text("8 bit").tag(8); Text("7 bit").tag(7); Text("5 bit (A=1)").tag(5)
            }
            .pickerStyle(.segmented)
            HStack(spacing: 8) {
                tasto("0") { input.append("0") }
                tasto("1") { input.append("1") }
                tasto("spazio") { input.append(" ") }
                tasto("⌫") { if !input.isEmpty { input.removeLast() } }
            }
        }
        Card(title: "Risultato") {
            Text(output).font(Theme.mono(15, .semibold)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            Button { copyToClipboard(output.components(separatedBy: "\n").first ?? output) } label: { Label("Copia", systemImage: "doc.on.doc") }
                .buttonStyle(.bordered).font(.footnote)
        }
    }

    func tasto(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(action: { a(); UIImpactFeedbackGenerator(style: .light).impactOccurred() }) {
            Text(t).font(Theme.mono(20, .bold)).frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.bordered).tint(Theme.gold)
    }
}
