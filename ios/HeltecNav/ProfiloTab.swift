import SwiftUI
import PhotosUI

// MARK: - Scheda Profilo

/// Moduli dei miei dati e della salute (dai riquadri del Profilo). Da rifare sulle tavole 33-36.
struct MieiDatiView: View {
    var salute = false
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var store = EventoStore.shared
    @EnvironmentObject var night: NightMode
    @State private var p: JProfilo?
    @State private var errore: String?
    @State private var salvato = false
    @State private var foto: PhotosPickerItem?
    @State private var versioneFoto = 0
    @State private var certificato = Date()
    @State private var haCertificato = false
    @State private var invito = false
    @State private var collega = false
    @State private var esci = false

    var body: some View {
        Group {
            if jsoc.collegato { contenuto } else { EntraView() }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(salute ? "Salute" : "I miei dati")
        .sheet(isPresented: $invito) { InvitoSheet() }
        .sheet(isPresented: $collega) { InvitoSheet(dispositivo: true) }
    }

    var contenuto: some View {
        Form {
            if let errore { Section { Text(errore).foregroundStyle(Theme.red) } }
            if p != nil {
                if !salute { Section("I miei dati") {
                    TextField("Nome e cognome", text: bind(\.nome))
                    TextField("Email", text: bindOpt(\.email)).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    TextField("Telefono", text: bindOpt(\.telefono)).keyboardType(.phonePad)
                    TextField("Data di nascita (AAAA-MM-GG)", text: bindOpt(\.nascita))
                    TextField("Luogo di nascita", text: bindOpt(\.luogo_nascita))
                    TextField("Codice fiscale", text: bindOpt(\.cf)).textInputAutocapitalization(.characters)
                    TextField("Indirizzo", text: bindOpt(\.indirizzo))
                } }
                if salute { Section("Certificato medico") {
                    Toggle("Ho il certificato", isOn: $haCertificato.animation())
                    if haCertificato {
                        DatePicker("Scade il", selection: $certificato, displayedComponents: .date)
                    }
                }
                Section("Emergenza") {
                    TextField("Gruppo sanguigno", text: bindOpt(\.gruppo_sanguigno))
                    TextField("Contatto di emergenza (nome e telefono)", text: bindOpt(\.emergenza))
                    TextField("Note (allergie, farmaci)", text: bindOpt(\.note_profilo), axis: .vertical)
                } }
                Section {
                    Button(salvato ? "Salvato ✓" : "Salva i miei dati") { salva() }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(PrimaryButtonStyle())
                }
                .listRowBackground(Color.clear)
            }
        }
        .listaJSOC()
        .task { await carica() }
        .refreshable { await carica() }
        .onChange(of: foto) { item in
            guard let item else { return }
            Task {
                if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d),
                   let jpg = img.ridotta(lato: 600).jpegData(compressionQuality: 0.8) {
                    do { try await jsoc.caricaDati("/api/profilo/foto", dati: jpg); versioneFoto += 1 }
                    catch { errore = error.localizedDescription }
                }
                foto = nil
            }
        }
        .confirmationDialog("Uscire da JSOC TAK su questo telefono?", isPresented: $esci, titleVisibility: .visible) {
            Button("Esci", role: .destructive) { jsoc.esci() }
        } message: { Text("Per rientrare servirà un nuovo invito.") }
    }

    // MARK: tessera digitale

    var tesseraDigitale: some View {
        let u = p
        let gc = u?.giorniCertificato
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                PhotosPicker(selection: $foto, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        FotoSocio(id: jsoc.utente?.id, iniziali: jsoc.utente?.callsign ?? "?", lato: 78, aggiorna: versioneFoto)
                        Image(systemName: "camera.circle.fill").font(.title3).foregroundStyle(Theme.olive, .black)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(jsoc.utente?.callsign ?? "").font(.system(size: 26, weight: .heavy, design: .monospaced))
                    Text(u?.nome ?? jsoc.utente?.nome ?? "").font(.subheadline.weight(.semibold))
                    Text((jsoc.utente?.ruolo ?? "").uppercased()).font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(1.5)
                        .foregroundStyle(Theme.olive)
                }
                Spacer()
                Image("Stemma").resizable().scaledToFit().frame(width: 54, height: 54)
            }
            HStack(spacing: 14) {
                dato("TESSERA", u?.tessera?.isEmpty == false ? u!.tessera! : "—")
                dato("SCADE", dataIT(u?.tessera_scadenza))
                dato("CERTIFICATO", gc == nil ? "MANCA" : (gc! < 0 ? "SCADUTO" : dataIT(u?.certificato_scadenza)),
                     colore: gc == nil || gc! < 0 ? Theme.red : (gc! <= 30 ? Theme.amber : Theme.green))
            }
            if let qr = QR.immagine("JSOC:\(jsoc.utente?.id ?? 0):\(jsoc.utente?.callsign ?? "")", scala: 5) {
                HStack {
                    Image(uiImage: qr).interpolation(.none).resizable().frame(width: 74, height: 74)
                        .padding(5).background(.white, in: RoundedRectangle(cornerRadius: 8))
                    Text("Mostra questo codice all'ingresso del campo per l'appello.").font(.caption2).foregroundStyle(Theme.dim)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Theme.oliveDeep, Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.olive.opacity(0.5), lineWidth: 1))
        .padding(.vertical, 6)
    }

    func dato(_ t: String, _ v: String, colore: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1).foregroundStyle(Theme.dim)
            Text(v).font(Theme.mono(13, .bold)).foregroundStyle(colore).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // MARK: dati

    func bind(_ k: WritableKeyPath<JProfilo, String>) -> Binding<String> {
        Binding(get: { p?[keyPath: k] ?? "" }, set: { p?[keyPath: k] = $0; salvato = false })
    }
    func bindOpt(_ k: WritableKeyPath<JProfilo, String?>) -> Binding<String> {
        Binding(get: { p?[keyPath: k] ?? "" }, set: { p?[keyPath: k] = $0; salvato = false })
    }

    func carica() async {
        do {
            let x = try await jsoc.profilo()
            p = x; errore = nil
            if let s = x.certificato_scadenza, let d = JEvento.data(s) { certificato = d; haCertificato = true } else { haCertificato = false }
        } catch { errore = error.localizedDescription }
    }

    func salva() {
        guard let p else { return }
        var campi: [String: Any] = ["nome": p.nome]
        for (k, v) in [("email", p.email), ("telefono", p.telefono), ("nascita", p.nascita), ("luogo_nascita", p.luogo_nascita),
                       ("cf", p.cf), ("indirizzo", p.indirizzo), ("gruppo_sanguigno", p.gruppo_sanguigno),
                       ("emergenza", p.emergenza), ("note_profilo", p.note_profilo)] { campi[k] = v ?? "" }
        campi["certificato_scadenza"] = haCertificato ? isoGiorno(certificato) : ""
        Task {
            do {
                self.p = try await jsoc.salvaProfilo(campi)
                salvato = true; errore = nil
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                await HomeModel.shared.aggiorna()
            } catch { errore = error.localizedDescription }
        }
    }
}

struct ServerInfoView: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @ObservedObject private var store = EventoStore.shared

    var body: some View {
        List {
            HStack { Text("Stato"); Spacer(); StatusDot(on: jsoc.online); Text(jsoc.online ? "raggiungibile" : "non raggiungibile").foregroundStyle(Theme.dim) }
            VStack(alignment: .leading) {
                Text("Indirizzo").font(.caption).foregroundStyle(Theme.dim)
                Text(jsoc.indirizzo).font(Theme.mono(12)).textSelection(.enabled)
            }
            HStack { Text("Posizioni in attesa"); Spacer(); Text("\(store.inCoda)").font(Theme.mono(13, .bold)) }
            Text(store.stato).font(.caption).foregroundStyle(Theme.dim)
            Button("Aggiorna adesso") { Task { await store.aggiorna(jsoc) } }
        }
        .listaJSOC()
        .navigationTitle("Server")
    }
}

extension UIImage {
    func ridotta(lato: CGFloat) -> UIImage {
        let s = min(1, lato / max(size.width, size.height))
        guard s < 1 else { return self }
        let n = CGSize(width: size.width * s, height: size.height * s)
        return UIGraphicsImageRenderer(size: n).image { _ in draw(in: CGRect(origin: .zero, size: n)) }
    }
}
