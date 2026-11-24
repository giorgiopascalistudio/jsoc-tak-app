import SwiftUI
import AVFoundation
import AVKit
import ReplayKit
import HaishinKit
import SRTHaishinKit
import RTMPHaishinKit

// MARK: - Impostazioni video (come Larix: server MediaMTX con utente e password OTS)

enum VideoConf {
    static var host: String { UserDefaults.standard.string(forKey: "video.host") ?? "0.0.0.0" }
    static var callsign: String { UserDefaults.standard.string(forKey: "video.callsign") ?? "GREG" }
    static var utente: String { UserDefaults.standard.string(forKey: "video.utente") ?? callsign }
    static var password: String { Keychain.get("video.pass") ?? "" }
    static var configurato: Bool { !password.isEmpty }

    /// SRT verso MediaMTX: streamid = publish:<percorso>:<utente>:<password>
    static func url(percorso: String) -> URL? {
        var c = URLComponents()
        c.scheme = "srt"
        c.host = host
        c.port = 8890
        c.queryItems = [.init(name: "streamid", value: "publish:\(percorso):\(utente):\(password)"),
                        .init(name: "latency", value: "2000")]
        return c.url
    }

    /// Per l'estensione di trasmissione schermo (legge dal gruppo app).
    static func salvaPerSchermo() {
        Shared.defaults.set(url(percorso: callsign + "-TERMICO")?.absoluteString, forKey: "broadcast.url")
    }
}

// MARK: - Trasmissione fotocamera

@MainActor
final class Trasmissione: ObservableObject, MTHKViewRepresentable.PreviewSource {
    /// Una sola trasmissione per tutta l'app: continua mentre si usa la mappa o le altre schede.
    static let shared = Trasmissione()
    @Published private(set) var cameraAccesa = false
    @Published private(set) var stato: StreamSessionReadyState = .closed
    @Published private(set) var errore: String?
    @Published private(set) var kbps = 0
    @Published private(set) var inizio: Date?
    @Published var frontale = false
    @Published private(set) var muto = false
    @Published private(set) var torcia = false
    @Published var qualita = UserDefaults.standard.integer(forKey: "video.qualita")   // 0 bassa, 1 media, 2 alta

    let mixer = MediaMixer()
    private var session: (any StreamSession)?
    private var anteprima: MTHKView?
    private var pronto = false
    private var compiti: [Task<Void, Never>] = []

    init() {
        Task {
            await StreamSessionBuilderFactory.shared.register(SRTSessionFactory())
            await StreamSessionBuilderFactory.shared.register(RTMPSessionFactory())
        }
    }

    nonisolated func connect(to view: MTHKView) {
        Task { @MainActor in
            self.anteprima = view
            if self.pronto { await self.mixer.addOutput(view) }
        }
    }

    func avviaCamera() {
        guard !pronto else { return }
        Task {
            let s = AVAudioSession.sharedInstance()
            try? s.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetooth])
            try? s.setActive(true)
            try? await mixer.attachAudio(AVCaptureDevice.default(for: .audio))
            try? await mixer.attachVideo(AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: frontale ? .front : .back))
            await mixer.setVideoOrientation(Self.orientamentoSchermo())
            await mixer.startRunning()
            pronto = true
            cameraAccesa = true
            if let v = anteprima { await mixer.addOutput(v) }
        }
    }

    func fermaCamera() {
        Task {
            if stato != .closed { await chiudi() }
            await mixer.stopRunning()
            try? await mixer.attachAudio(nil)
            try? await mixer.attachVideo(nil)
            pronto = false
            cameraAccesa = false
        }
    }

    var dimensione: CGSize {
        let d = [CGSize(width: 480, height: 854), CGSize(width: 720, height: 1280), CGSize(width: 1080, height: 1920)][qualita]
        return Self.orientamentoSchermo() == .portrait ? d : CGSize(width: d.height, height: d.width)
    }

    static func orientamentoSchermo() -> AVCaptureVideoOrientation {
        let o = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.interfaceOrientation }.first ?? .portrait
        switch o {
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return .portrait
        }
    }

    /// Accende la camera (se serve) e trasmette all'indirizzo dato (JSOC TAK lo calcola da solo).
    func trasmettiJSOC(_ url: URL) {
        if !pronto { avviaCamera() }
        Task {
            try? await Task.sleep(nanoseconds: pronto ? 0 : 900_000_000)
            await mixer.setVideoOrientation(Self.orientamentoSchermo())
            trasmetti(url: url)
        }
    }
    var bitrate: Int { [600_000, 1_500_000, 3_500_000][qualita] }

    func trasmetti() {
        guard let url = VideoConf.url(percorso: VideoConf.callsign), VideoConf.configurato else {
            errore = "Imposta la password OTS nelle impostazioni video"
            return
        }
        trasmetti(url: url)
    }

    func trasmetti(url: URL) {
        guard stato == .closed else { return }
        errore = nil
        UserDefaults.standard.set(qualita, forKey: "video.qualita")
        Task {
            do {
                let s = try await StreamSessionBuilderFactory.shared.make(url).setMode(.publish).build()
                guard let s else { return }
                session = s
                var vs = await s.stream.videoSettings
                vs.videoSize = dimensione
                vs.bitRate = bitrate
                try? await s.stream.setVideoSettings(vs)
                await mixer.addOutput(s.stream)
                compiti.append(Task {
                    for await st in await s.readyState {
                        self.stato = st
                        if st == .open, self.inizio == nil { self.inizio = Date() }
                        if st == .closed { self.inizio = nil }
                    }
                })
                UIApplication.shared.isIdleTimerDisabled = true
                try await s.connect {
                    Task { @MainActor in self.errore = "Collegamento perso: riprovo…" }
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                self.errore = "Non riesco a collegarmi: \(error.localizedDescription)"
                self.stato = .closed
            }
        }
    }

    func chiudi() async {
        if let s = session {
            try? await s.close()
            await mixer.removeOutput(s.stream)
        }
        session = nil
        compiti.forEach { $0.cancel() }
        compiti = []
        stato = .closed
        inizio = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func gira() {
        frontale.toggle()
        let fronte = frontale
        Task {
            try? await mixer.attachVideo(AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: fronte ? .front : .back)) { unit in
                unit.isVideoMirrored = fronte
            }
        }
    }

    func cambiaMuto() {
        muto.toggle()
        Task {
            var st = await mixer.audioMixerSettings
            var tr = st.tracks[0] ?? .init()
            tr.isMuted = muto
            st.tracks[0] = tr
            await mixer.setAudioMixerSettings(st)
        }
    }

    func cambiaTorcia() {
        torcia.toggle()
        Task { await mixer.setTorchEnabled(torcia) }
    }
}

// MARK: - Schede video

struct VideoTab: View {
    @AppStorage("video.seg") private var seg = 0
    @State private var impostazioni = false

    var body: some View {
        let _ = GuidaApp.segna("video")
        VStack(spacing: 0) {
            Picker("", selection: $seg) {
                Text("Trasmetti").tag(0)
                Text("Squadra").tag(1)
                Text("Schermo").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.bottom, 6)
            switch seg {
            case 0: TrasmettiCameraView(impostazioni: $impostazioni)
            case 1: SquadraVideoView()
            default: SchermoView(impostazioni: $impostazioni)
            }
        }
        .sheet(isPresented: $impostazioni) { VideoImpostazioni() }
    }
}

struct TrasmettiCameraView: View {
    @Binding var impostazioni: Bool
    @ObservedObject private var tx = Trasmissione.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            MTHKViewRepresentable(previewSource: tx, videoGravity: .resizeAspectFill)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 10)
            VStack(spacing: 10) {
                HStack {
                    statoPill
                    Spacer()
                    Button { impostazioni = true } label: { Image(systemName: "gearshape.fill").mapButtonLook() }
                }
                .padding(.horizontal, 22).padding(.top, 10)
                Spacer()
                if let e = tx.errore {
                    Text(e).font(.caption.weight(.semibold)).padding(8)
                        .background(Theme.red.opacity(0.85), in: Capsule()).foregroundStyle(.white)
                }
                if tx.stato == .closed {
                    Picker("Qualità", selection: $tx.qualita) {
                        Text("Bassa · rete scarsa").tag(0); Text("Media").tag(1); Text("Alta").tag(2)
                    }
                    .pickerStyle(.segmented).padding(.horizontal, 22)
                }
                HStack(spacing: 18) {
                    tasto(tx.muto ? "mic.slash.fill" : "mic.fill", attivo: !tx.muto) { tx.cambiaMuto() }
                    tasto("arrow.triangle.2.circlepath.camera", attivo: true) { tx.gira() }
                    Button {
                        haptic(.medium)
                        if tx.stato == .closed { tx.trasmetti() } else { Task { await tx.chiudi() } }
                    } label: {
                        ZStack {
                            Circle().strokeBorder(.white, lineWidth: 4).frame(width: 78, height: 78)
                            RoundedRectangle(cornerRadius: tx.stato == .closed ? 30 : 8, style: .continuous)
                                .fill(Theme.red)
                                .frame(width: tx.stato == .closed ? 60 : 32, height: tx.stato == .closed ? 60 : 32)
                                .animation(.spring(response: 0.3), value: tx.stato)
                        }
                    }
                    tasto(tx.torcia ? "flashlight.on.fill" : "flashlight.off.fill", attivo: tx.torcia) { tx.cambiaTorcia() }
                    tasto("info.circle", attivo: true) { impostazioni = true }
                }
                .padding(.bottom, 18)
            }
        }
        .onAppear { tx.avviaCamera() }
        .onDisappear { if tx.stato == .closed { tx.fermaCamera() } }
    }

    var statoPill: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(spacing: 6) {
                StatusDot(on: tx.stato == .open ? true : (tx.stato == .connecting ? nil : false), size: 8)
                switch tx.stato {
                case .open:
                    Text("IN ONDA · \(VideoConf.callsign)").font(.system(size: 12, weight: .heavy, design: .monospaced))
                    if let i = tx.inizio {
                        let s = Int(ctx.date.timeIntervalSince(i))
                        Text(String(format: "%02d:%02d", s / 60, s % 60)).font(Theme.mono(12)).monospacedDigit()
                    }
                case .connecting: Text("COLLEGAMENTO…").font(.system(size: 12, weight: .heavy, design: .monospaced))
                default: Text("PRONTO · \(VideoConf.callsign)").font(.system(size: 12, weight: .heavy, design: .monospaced))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .foregroundStyle(tx.stato == .open ? Theme.red : .white)
        }
    }

    func tasto(_ icon: String, attivo: Bool, _ a: @escaping () -> Void) -> some View {
        Button { haptic(); a() } label: {
            Image(systemName: icon).font(.system(size: 20, weight: .semibold))
                .frame(width: 50, height: 50)
                .background(.ultraThinMaterial, in: Circle())
                .foregroundStyle(attivo ? .white : Theme.red)
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: - Video della squadra (letti dal server tramite la console)

struct Flusso: Decodable, Identifiable, Hashable {
    let nome: String
    let pronto: Bool
    let tracce: [String]
    let lettori: Int
    var id: String { nome }
}

extension ServerClient {
    func flussi() async throws -> [Flusso] {
        guard configured(.server), let url = URL(string: (urls[.server] ?? "") + "/video/flussi") else { throw ServerFailure.notConfigured(.server) }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(tokens[.server] ?? "")", forHTTPHeaderField: "Authorization")
        let (d, r) = try await URLSession.shared.data(for: req)
        guard (r as? HTTPURLResponse)?.statusCode == 200 else { throw ServerFailure.http((r as? HTTPURLResponse)?.statusCode ?? 0, "flussi") }
        return try JSONDecoder().decode([Flusso].self, from: d)
    }

    func hlsURL(_ nome: String) -> URL? {
        let p = nome.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? nome
        return URL(string: "\(urls[.server] ?? "")/video/hls/\(tokens[.server] ?? "")/\(p)/index.m3u8")
    }
}

struct SquadraVideoView: View {
    @EnvironmentObject var client: ServerClient
    @State private var flussi: [Flusso] = []
    @State private var errore: String?
    @State private var guarda: Flusso?

    var body: some View {
        List {
            if let errore { Text(errore).font(.caption).foregroundStyle(Theme.red).listRowBackground(Theme.surface) }
            Section("In onda") {
                let on = flussi.filter(\.pronto)
                if on.isEmpty { Text("Nessun video attivo ora").foregroundStyle(Theme.dim).listRowBackground(Theme.surface) }
                ForEach(on) { f in
                    Button { guarda = f } label: { riga(f) }.listRowBackground(Theme.surface)
                }
            }
            Section("Spenti") {
                ForEach(flussi.filter { !$0.pronto }) { f in riga(f).opacity(0.5).listRowBackground(Theme.surface) }
            }
        }
        .scrollContentBackground(.hidden)
        .refreshable { await carica() }
        .task { while !Task.isCancelled { await carica(); try? await Task.sleep(nanoseconds: 5_000_000_000) } }
        .fullScreenCover(item: $guarda) { f in PlayerFlusso(flusso: f) }
    }

    func riga(_ f: Flusso) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(f.pronto ? Theme.red.opacity(0.2) : Theme.surface2).frame(width: 44, height: 44)
                Image(systemName: f.nome.contains("TERMICO") ? "thermometer.medium" : (f.nome.contains("DRONE") ? "airplane" : "video.fill"))
                    .foregroundStyle(f.pronto ? Theme.red : Theme.dim)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(f.nome).font(.headline).foregroundStyle(.white)
                Text(f.pronto ? (f.tracce.joined(separator: " · ") + " · \(f.lettori) spettatori") : "spento")
                    .font(.caption).foregroundStyle(Theme.dim)
            }
            Spacer()
            if f.pronto { Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(Theme.olive) }
        }
    }

    func carica() async {
        do { flussi = try await client.flussi().filter { $0.nome != "startup" }; errore = nil }
        catch { errore = "Server non raggiungibile per l'elenco video" }
    }
}

struct PlayerFlusso: View {
    let flusso: Flusso
    @EnvironmentObject var client: ServerClient
    @Environment(\.dismiss) var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let player { VideoPlayer(player: player).ignoresSafeArea() }
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").mapButtonLook() }
                Text(flusso.nome).font(.headline).padding(8).background(.ultraThinMaterial, in: Capsule())
            }
            .padding()
        }
        .onAppear {
            guard let u = client.hlsURL(flusso.nome) else { return }
            let p = AVPlayer(url: u)
            p.automaticallyWaitsToMinimizeStalling = false
            p.agganciaAllaDiretta()
            p.play()
            player = p
        }
        .onDisappear { player?.staccaDallaDiretta(); player?.pause() }
    }
}

// MARK: - Trasmissione schermo (estensione ReplayKit)

struct SchermoView: View {
    @Binding var impostazioni: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Card(title: "Trasmetti lo schermo", icon: "rectangle.on.rectangle") {
                    Text("Manda in onda tutto lo schermo come \(VideoConf.callsign)-TERMICO, anche mentre usi altre app (Mini Thermal Scope del visore Owlset, iTAK…). Continua finché non lo fermi dalla barra rossa in alto.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                    BroadcastPicker()
                        .frame(width: 84, height: 84)
                        .frame(maxWidth: .infinity)
                    Text("Tocca il cerchio, scegli **Re Mida** e premi **Avvia trasmissione**.").font(.caption).foregroundStyle(Theme.dim)
                    if !VideoConf.configurato {
                        Button("Prima imposta la password OTS") { impostazioni = true }.font(.caption.weight(.bold))
                    }
                }
            }
            .padding()
        }
        .onAppear { VideoConf.salvaPerSchermo() }
    }
}

struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let v = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 84, height: 84))
        v.preferredExtension = "com.giorgiopascali.heltecnav.broadcast"
        v.showsMicrophoneButton = true
        v.tintColor = UIColor(red: 0.95, green: 0.36, blue: 0.30, alpha: 1)
        return v
    }
    func updateUIView(_ v: RPSystemBroadcastPickerView, context: Context) {}
}

// MARK: - Impostazioni

struct VideoImpostazioni: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("video.callsign") private var callsign = "GREG"
    @AppStorage("video.utente") private var utente = ""
    @AppStorage("video.host") private var host = "0.0.0.0"
    @State private var password = Keychain.get("video.pass") ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nominativo (nome del flusso)", text: $callsign).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    TextField("Utente OTS (vuoto = nominativo)", text: $utente).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password OTS", text: $password)
                } header: { Text("Accesso") } footer: {
                    Text("Le stesse credenziali di Larix e del server TAK. La password resta nel portachiavi del telefono.")
                }
                Section("Server") {
                    TextField("Indirizzo", text: $host).font(Theme.mono(14)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("SRT porta 8890 · fotocamera: \(callsign) · schermo: \(callsign)-TERMICO").font(.caption).foregroundStyle(Theme.dim)
                }
            }
            .navigationTitle("Video")
            .toolbar {
                Button("Fatto") {
                    Keychain.set(password, for: "video.pass")
                    if utente.isEmpty { UserDefaults.standard.removeObject(forKey: "video.utente") }
                    VideoConf.salvaPerSchermo()
                    dismiss()
                }
            }
        }
    }
}
