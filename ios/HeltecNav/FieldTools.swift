import SwiftUI
import AVFoundation
import CoreBluetooth
import Accelerate
import UniformTypeIdentifiers

// MARK: - Scheda "Campo": strumenti tattici

struct CampoView: View {
    @State private var mirino = false
    @State private var telemetro = false
    @State private var proiezione = false

    var body: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                tool("Mirino", "camera.viewfinder", "Azimut, inclinazione, acquisizione per la triangolazione") { mirino = true }
                tool("Telemetro", "ruler", "Distanza dalla fotocamera con un'altezza nota") { telemetro = true }
                NavigationLink { BLEScannerView() } label: {
                    card("Bluetooth", "dot.radiowaves.left.and.right", "Trova dispositivi nascosti: caldo / freddo")
                }
                .buttonStyle(PressStyle())
                tool("Proiezione", "plus.viewfinder", "Da azimut e distanza alle coordinate") { proiezione = true }
            }
            Card(title: "Triangolazione", icon: "scope") { TriangView() }
        }
        .fullScreenCover(isPresented: $mirino) { MirinoView() }
        .fullScreenCover(isPresented: $telemetro) { TelemetroView() }
        .sheet(isPresented: $proiezione) { ProiezioneSheet(origineScelta: nil) { _, _ in } }
    }

    func tool(_ t: String, _ i: String, _ d: String, _ a: @escaping () -> Void) -> some View {
        Button { haptic(); a() } label: { card(t, i, d) }.buttonStyle(PressStyle())
    }

    func card(_ t: String, _ i: String, _ d: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: i).font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.olive)
            Text(t).font(.headline).foregroundStyle(.white)
            Text(d).font(.caption).foregroundStyle(Theme.dim).multilineTextAlignment(.leading).lineLimit(3)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface2))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 0.75))
    }
}

// MARK: - Telemetro

/// Si inquadra un oggetto di altezza nota e si portano le due linee alla base e alla cima:
/// la distanza viene dall'angolo sotteso (campo visivo reale della fotocamera, con lo zoom).
struct TelemetroView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var cam = RangeCamera()
    @State private var top: CGFloat = 0.38
    @State private var bottom: CGFloat = 0.62
    @AppStorage("telemetro.h") private var altezza = 1.75

    let preset: [(String, Double)] = [("Persona", 1.75), ("Porta", 2.10), ("Auto", 1.50), ("Finestra", 1.20), ("Piano casa", 3.0), ("Palo luce", 8.0)]

    var body: some View {
        GeometryReader { g in
            let h = g.size.height
            ZStack {
                CameraPreview(session: cam.session).ignoresSafeArea()
                linea(y: top * h, label: "CIMA") { top = min(max(0.02, $0 / h), bottom - 0.01) }
                linea(y: bottom * h, label: "BASE") { bottom = max(min(0.98, $0 / h), top + 0.01) }
                VStack {
                    VStack(spacing: 4) {
                        Text(distanza(h).map { String(format: "%.0f m", $0) } ?? "—")
                            .font(.system(size: 46, weight: .heavy, design: .monospaced)).numericTransition()
                        Text(String(format: "angolo %.2f° · %.1f mil · oggetto %.2f m · zoom %.0fx", angolo(h) * 180 / .pi,
                                    angolo(h) * 6400 / (2 * .pi), altezza, cam.zoom))
                            .font(Theme.mono(11))
                    }
                    .padding(12).background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.top, 10)
                    Spacer()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(preset, id: \.0) { p in
                                Button("\(p.0) \(String(format: "%.2f", p.1))") { altezza = p.1 }
                                    .font(.caption.weight(.semibold)).buttonStyle(.bordered)
                                    .tint(altezza == p.1 ? Theme.olive : .white)
                            }
                        }
                        .padding(.horizontal)
                    }
                    HStack {
                        Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 50, height: 50) }
                            .background(.black.opacity(0.6), in: Circle())
                        Stepper(String(format: "Altezza %.2f m", altezza), value: $altezza, in: 0.1...50, step: 0.05)
                            .padding(.horizontal, 10).padding(.vertical, 6).background(.black.opacity(0.6), in: Capsule())
                        ForEach([1.0, 2.0, 5.0], id: \.self) { z in
                            Button("\(Int(z))x") { cam.setZoom(z) }.font(.caption.weight(.bold))
                                .frame(width: 40, height: 40).background(cam.zoom == z ? Theme.olive : .black.opacity(0.6), in: Circle())
                                .foregroundStyle(cam.zoom == z ? .black : .white)
                        }
                    }
                    .padding()
                }
                .foregroundStyle(.white)
            }
        }
        .onAppear { cam.start() }
        .onDisappear { cam.stop() }
    }

    func linea(y: CGFloat, label: String, move: @escaping (CGFloat) -> Void) -> some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Theme.olive).frame(height: 2).shadow(color: .black, radius: 2)
            Text(label).font(Theme.mono(11, .bold)).padding(4).background(Theme.olive, in: Capsule()).foregroundStyle(.black).padding(.leading, 12)
        }
        .frame(height: 44)
        .contentShape(Rectangle())
        .position(x: UIScreen.main.bounds.width / 2, y: y)
        .gesture(DragGesture().onChanged { move($0.location.y) })
    }

    /// Angolo sotteso tra le due linee (radianti), con la focale ricavata dal campo visivo verticale.
    func angolo(_ h: CGFloat) -> Double {
        let fov = cam.fovVerticale                    // radianti, già diviso per lo zoom
        let f = Double(h / 2) / tan(fov / 2)
        let a1 = atan(Double(h / 2 - top * h) / f), a2 = atan(Double(h / 2 - bottom * h) / f)
        return abs(a1 - a2)
    }

    func distanza(_ h: CGFloat) -> Double? {
        let a = angolo(h)
        guard a > 0.0005 else { return nil }
        return altezza / (2 * tan(a / 2))
    }
}

final class RangeCamera: ObservableObject {
    let session = AVCaptureSession()
    @Published var zoom: Double = 1
    @Published var fovVerticale: Double = 60 * .pi / 180
    private var device: AVCaptureDevice?
    private var baseFov: Double = 60
    private let q = DispatchQueue(label: "telemetro.cam")

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            guard ok else { return }
            self.q.async {
                if self.device == nil {
                    guard let d = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                          let i = try? AVCaptureDeviceInput(device: d) else { return }
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .hd1920x1080
                    if self.session.canAddInput(i) { self.session.addInput(i) }
                    self.session.commitConfiguration()
                    self.device = d
                    // il campo visivo dichiarato è sul lato lungo del sensore: in verticale è quello verticale
                    self.baseFov = Double(d.activeFormat.videoFieldOfView)
                    DispatchQueue.main.async { self.aggiornaFov() }
                }
                self.session.startRunning()
            }
        }
    }

    func setZoom(_ z: Double) {
        guard let d = device else { return }
        let zz = min(z, Double(d.activeFormat.videoMaxZoomFactor))
        q.async {
            try? d.lockForConfiguration()
            d.videoZoomFactor = CGFloat(zz)
            d.unlockForConfiguration()
            DispatchQueue.main.async { self.zoom = zz; self.aggiornaFov() }
        }
    }

    private func aggiornaFov() {
        let half = baseFov * .pi / 360
        fovVerticale = 2 * atan(tan(half) / zoom)
    }

    func stop() { q.async { self.session.stopRunning() } }
}

// MARK: - Scanner Bluetooth (caldo / freddo)

final class BLEScanner: NSObject, ObservableObject, CBCentralManagerDelegate {
    struct Dev: Identifiable {
        let id: UUID
        var nome: String
        var rssi: Double
        var visto: Date
        var dati: String
        var storia: [Double] = []
    }
    @Published var devs: [UUID: Dev] = [:]
    @Published var stato = "Avvio…"
    private var cm: CBCentralManager?

    func start() { if cm == nil { cm = CBCentralManager(delegate: self, queue: .main) } else { scan() } }
    func stop() { cm?.stopScan() }

    private func scan() {
        cm?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        stato = "Scansione in corso"
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn: scan()
        case .poweredOff: stato = "Bluetooth spento"
        case .unauthorized: stato = "Permesso Bluetooth negato (Impostazioni › Re Mida)"
        default: stato = "Bluetooth non disponibile"
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi RSSI: NSNumber) {
        let r = RSSI.doubleValue
        guard r < 0 && r > -110 else { return }
        let nome = (ad[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? "senza nome"
        var dati = ""
        if let m = ad[CBAdvertisementDataManufacturerDataKey] as? Data { dati = m.prefix(12).map { String(format: "%02X", $0) }.joined() }
        if let s = ad[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID], !s.isEmpty { dati += (dati.isEmpty ? "" : " · ") + s.map(\.uuidString).joined(separator: ",") }
        var d = devs[p.identifier] ?? Dev(id: p.identifier, nome: nome, rssi: r, visto: Date(), dati: dati)
        d.rssi = d.rssi * 0.7 + r * 0.3          // media mobile: segnale più stabile
        d.visto = Date()
        d.nome = nome
        if !dati.isEmpty { d.dati = dati }
        d.storia.append(d.rssi)
        if d.storia.count > 60 { d.storia.removeFirst() }
        devs[p.identifier] = d
    }

    /// Stima grossolana: potenza a 1 m = -59 dBm, esponente 2,5 (all'aperto/interni misti).
    static func metri(_ rssi: Double) -> Double { pow(10, (-59 - rssi) / 25) }
}

struct BLEScannerView: View {
    @StateObject private var ble = BLEScanner()
    @State private var filtro = ""
    @State private var soloConNome = false

    var lista: [BLEScanner.Dev] {
        ble.devs.values
            .filter { Date().timeIntervalSince($0.visto) < 20 }
            .filter { !soloConNome || $0.nome != "senza nome" }
            .filter { filtro.isEmpty || $0.nome.localizedCaseInsensitiveContains(filtro) || $0.dati.localizedCaseInsensitiveContains(filtro) }
            .sorted { $0.rssi > $1.rssi }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            List {
                Section {
                    Text(ble.stato).font(.caption).foregroundStyle(Theme.dim)
                    Toggle("Solo con nome", isOn: $soloConNome).tint(Theme.olive)
                } footer: {
                    Text("Tocca un dispositivo e muoviti: l'indicatore dice se ti avvicini. iOS non mostra gli indirizzi MAC, solo un identificativo.")
                }
                ForEach(lista) { d in
                    NavigationLink { BLECacciaView(ble: ble, id: d.id) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.nome).font(.subheadline.weight(.semibold))
                                if !d.dati.isEmpty { Text(d.dati).font(Theme.mono(10)).foregroundStyle(Theme.dim).lineLimit(1) }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(String(format: "%.0f dBm", d.rssi)).font(Theme.mono(13, .bold)).foregroundStyle(colore(d.rssi))
                                Text(String(format: "~%.0f m", BLEScanner.metri(d.rssi))).font(Theme.mono(10)).foregroundStyle(Theme.dim)
                            }
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
        }
        .searchable(text: $filtro, prompt: "Filtra per nome o dati")
        .navigationTitle("Bluetooth")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { ble.start() }
        .onDisappear { ble.stop() }
    }

    func colore(_ r: Double) -> Color { r > -60 ? Theme.red : (r > -75 ? Theme.amber : Theme.olive) }
}

struct BLECacciaView: View {
    @ObservedObject var ble: BLEScanner
    let id: UUID
    @State private var ultimoBattito = Date()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let d = ble.devs[id]
            let r = d?.rssi ?? -100
            let p = min(1, max(0, (r + 100) / 65))       // -100 → 0, -35 → 1
            let trend = tendenza(d?.storia ?? [])
            VStack(spacing: 18) {
                Text(d?.nome ?? "—").font(.title3.weight(.bold))
                ZStack {
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 18)
                    Circle().trim(from: 0, to: p)
                        .stroke(AngularGradient(colors: [Theme.olive, Theme.amber, Theme.red], center: .center),
                                style: StrokeStyle(lineWidth: 18, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.4), value: p)
                    VStack(spacing: 4) {
                        Text(p > 0.75 ? "CALDISSIMO" : p > 0.55 ? "CALDO" : p > 0.35 ? "TIEPIDO" : "FREDDO")
                            .font(.system(size: 22, weight: .heavy, design: .monospaced))
                            .foregroundStyle(p > 0.55 ? Theme.red : (p > 0.35 ? Theme.amber : Theme.olive))
                        Text(String(format: "%.0f dBm · ~%.1f m", r, BLEScanner.metri(r))).font(Theme.mono(14))
                        Label(trend > 1 ? "ti avvicini" : (trend < -1 ? "ti allontani" : "stabile"),
                              systemImage: trend > 1 ? "arrow.up.right" : (trend < -1 ? "arrow.down.right" : "arrow.right"))
                            .font(.caption.weight(.bold)).foregroundStyle(trend > 1 ? Theme.green : (trend < -1 ? Theme.red : Theme.dim))
                    }
                }
                .frame(width: 240, height: 240)
                if let dati = d?.dati, !dati.isEmpty { Text(dati).font(Theme.mono(11)).foregroundStyle(Theme.dim).padding(.horizontal) }
                Text("Ruota su te stesso lentamente: il segnale è più forte quando il telefono non ha il tuo corpo in mezzo.")
                    .font(.caption).foregroundStyle(Theme.dim).multilineTextAlignment(.center).padding(.horizontal, 30)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
            .onChange(of: ctx.date) { now in
                // vibrazione più frequente quando ci si avvicina
                let intervallo = 1.6 - 1.4 * p
                if now.timeIntervalSince(ultimoBattito) > intervallo {
                    ultimoBattito = now
                    UIImpactFeedbackGenerator(style: p > 0.55 ? .heavy : .light).impactOccurred()
                }
            }
        }
        .navigationTitle("Caccia")
        .navigationBarTitleDisplayMode(.inline)
    }

    func tendenza(_ s: [Double]) -> Double {
        guard s.count >= 12 else { return 0 }
        let a = s.suffix(6).reduce(0, +) / 6, b = s.suffix(12).prefix(6).reduce(0, +) / 6
        return a - b
    }
}

// MARK: - Audio: spettrogramma e decoder DTMF

struct AudioLabView: View {
    @EnvironmentObject var log: FieldLog
    @State private var importing = false
    @State private var file: URL?
    @State private var spettro: UIImage?
    @State private var durata: Double = 0
    @State private var sr: Double = 44100
    @State private var maxHz: Double = 0
    @State private var dtmf = ""
    @State private var lavoro = false
    @StateObject private var live = DTMFLive()

    var audioRaccolta: [LogEntry] { log.entries.filter { $0.kind == .audio } }

    var body: some View {
        VStack(spacing: 12) {
            Card(title: "Sorgente", icon: "waveform") {
                HStack {
                    Button { importing = true } label: { Label("File audio/video", systemImage: "folder") }
                    Menu {
                        ForEach(audioRaccolta) { e in
                            Button(e.text) { if let u = log.url(e) { analizza(u) } }
                        }
                    } label: { Label("Dalla Raccolta", systemImage: "tray") }
                    .disabled(audioRaccolta.isEmpty)
                }
                .buttonStyle(.bordered).tint(Theme.olive).font(.caption.weight(.semibold))
                if let file { Text(file.lastPathComponent).font(Theme.mono(11)).foregroundStyle(Theme.dim) }
            }
            if lavoro { ProgressView("Analizzo…").tint(Theme.olive) }
            if let img = spettro {
                Card(title: "Spettrogramma", icon: "chart.bar.xaxis",
                     trailing: String(format: "%.1f s · fino a %.0f Hz", durata, maxHz > 0 ? maxHz : sr / 2)) {
                    Picker("Frequenze", selection: $maxHz) {
                        Text("Tutte").tag(0.0); Text("8 kHz").tag(8000.0); Text("4 kHz").tag(4000.0); Text("2 kHz").tag(2000.0)
                    }
                    .pickerStyle(.segmented)
                    ScrollView(.horizontal) {
                        Image(uiImage: ritaglia(img))
                            .resizable().interpolation(.none)
                            .frame(width: max(320, CGFloat(img.size.width) * 1.2), height: 260)
                    }
                    .background(Color.black)
                    Text("Scritte o disegni nello spettro = messaggio nascosto. Linee orizzontali fisse = toni (es. DTMF, Morse).")
                        .font(.caption).foregroundStyle(Theme.dim)
                }
            }
            Card(title: "Toni telefonici (DTMF)", icon: "phone.badge.waveform") {
                if file != nil {
                    Text(dtmf.isEmpty ? "Nessun tono DTMF nel file" : dtmf).font(Theme.mono(22, .bold)).textSelection(.enabled)
                        .foregroundStyle(dtmf.isEmpty ? Theme.dim : Theme.olive)
                    if !dtmf.isEmpty { Button { copyToClipboard(dtmf) } label: { Label("Copia", systemImage: "doc.on.doc") }.font(.caption) }
                }
                Divider().background(Theme.stroke)
                HStack {
                    Button { live.attivo ? live.stop() : live.start() } label: {
                        Label(live.attivo ? "Ferma ascolto" : "Ascolta dal microfono", systemImage: live.attivo ? "stop.circle.fill" : "mic.fill")
                    }
                    .buttonStyle(.borderedProminent).tint(live.attivo ? Theme.red : Theme.olive)
                    Spacer()
                    if live.attivo { Text(live.tasto).font(Theme.mono(28, .heavy)).foregroundStyle(Theme.olive) }
                }
                if !live.sequenza.isEmpty {
                    Text(live.sequenza).font(Theme.mono(20, .bold)).textSelection(.enabled)
                    HStack {
                        Button("Copia") { copyToClipboard(live.sequenza) }
                        Button("Azzera", role: .destructive) { live.sequenza = "" }
                    }
                    .font(.caption)
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .movie, .mpeg4Movie, .quickTimeMovie]) { r in
            if case .success(let u) = r {
                let ok = u.startAccessingSecurityScopedResource()
                let dst = FileManager.default.temporaryDirectory.appendingPathComponent(u.lastPathComponent)
                try? FileManager.default.removeItem(at: dst)
                try? FileManager.default.copyItem(at: u, to: dst)
                if ok { u.stopAccessingSecurityScopedResource() }
                analizza(dst)
            }
        }
        .onDisappear { live.stop() }
    }

    func ritaglia(_ img: UIImage) -> UIImage {
        guard maxHz > 0, maxHz < sr / 2, let cg = img.cgImage else { return img }
        let frac = maxHz / (sr / 2)
        let h = Int(Double(cg.height) * frac)
        guard let c = cg.cropping(to: CGRect(x: 0, y: cg.height - h, width: cg.width, height: h)) else { return img }
        return UIImage(cgImage: c)
    }

    func analizza(_ u: URL) {
        file = u
        lavoro = true
        spettro = nil
        Task.detached(priority: .userInitiated) {
            let r = AudioAnalisi.carica(u)
            let img = r.map { AudioAnalisi.spettrogramma($0.0, sr: $0.1) }
            let toni = r.map { AudioAnalisi.dtmf($0.0, sr: $0.1) } ?? ""
            await MainActor.run {
                spettro = img ?? nil
                if let r { durata = Double(r.0.count) / r.1; sr = r.1 }
                dtmf = toni
                lavoro = false
            }
        }
    }
}

enum AudioAnalisi {
    /// Campioni mono float e frequenza di campionamento (anche dalla traccia audio di un video).
    static func carica(_ u: URL) -> ([Float], Double)? {
        if let f = try? AVAudioFile(forReading: u) {
            let fmt = f.processingFormat
            guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(min(f.length, 44100 * 600))),
                  (try? f.read(into: buf)) != nil, let ch = buf.floatChannelData else { return nil }
            let n = Int(buf.frameLength)
            return (Array(UnsafeBufferPointer(start: ch[0], count: n)), fmt.sampleRate)
        }
        // video: estraggo l'audio con AVAssetReader
        let asset = AVURLAsset(url: u)
        guard let track = asset.tracks(withMediaType: .audio).first, let reader = try? AVAssetReader(asset: asset) else { return nil }
        let sr = 44100.0
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false, AVNumberOfChannelsKey: 1, AVSampleRateKey: sr])
        reader.add(out)
        reader.startReading()
        var samples: [Float] = []
        while let sb = out.copyNextSampleBuffer(), let bb = CMSampleBufferGetDataBuffer(sb) {
            var len = 0
            var ptr: UnsafeMutablePointer<CChar>?
            CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &len, dataPointerOut: &ptr)
            if let ptr {
                ptr.withMemoryRebound(to: Float.self, capacity: len / 4) { samples.append(contentsOf: UnsafeBufferPointer(start: $0, count: len / 4)) }
            }
            if samples.count > Int(sr) * 600 { break }
        }
        return samples.isEmpty ? nil : (samples, sr)
    }

    static func spettrogramma(_ s: [Float], sr: Double) -> UIImage? {
        let n = 1024, half = n / 2
        guard s.count > n, let fft = vDSP.FFT(log2n: 10, radix: .radix2, ofType: DSPSplitComplex.self) else { return nil }
        let hop = max(128, (s.count - n) / 1800)
        let frames = (s.count - n) / hop
        let win = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
        var colonne: [[Float]] = []
        colonne.reserveCapacity(frames)
        var re = [Float](repeating: 0, count: half), im = [Float](repeating: 0, count: half)
        var mag = [Float](repeating: 0, count: half)
        for f in 0..<frames {
            let frame = vDSP.multiply(Array(s[(f * hop)..<(f * hop + n)]), win)
            re.withUnsafeMutableBufferPointer { rp in
                im.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    frame.withUnsafeBufferPointer { fp in
                        fp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                        }
                    }
                    let ingresso = split
                    fft.forward(input: ingresso, output: &split)
                    vDSP_zvabs(&split, 1, &mag, 1, vDSP_Length(half))
                }
            }
            colonne.append(mag.map { 20 * log10($0 + 1e-6) })
        }
        let maxDb = colonne.flatMap { $0 }.max() ?? 0
        let w = colonne.count, h = half
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for x in 0..<w {
            for y in 0..<h {
                let v = Double(max(0, min(1, (colonne[x][y] - (maxDb - 80)) / 80)))
                let i = ((h - 1 - y) * w + x) * 4
                // nero → verde oliva → giallo → bianco
                px[i] = UInt8(min(255, v < 0.6 ? v / 0.6 * 154 : 154 + (v - 0.6) / 0.4 * 101))
                px[i + 1] = UInt8(min(255, v < 0.6 ? v / 0.6 * 174 : 174 + (v - 0.6) / 0.4 * 81))
                px[i + 2] = UInt8(min(255, v < 0.6 ? v / 0.6 * 91 : 91 + (v - 0.6) / 0.4 * 164))
                px[i + 3] = 255
            }
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let cg: CGImage? = px.withUnsafeMutableBytes { ptr in
            CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        return cg.map { UIImage(cgImage: $0) }
    }

    static let basse: [Double] = [697, 770, 852, 941]
    static let alte: [Double] = [1209, 1336, 1477, 1633]
    static let tasti: [[Character]] = [["1", "2", "3", "A"], ["4", "5", "6", "B"], ["7", "8", "9", "C"], ["*", "0", "#", "D"]]

    static func goertzel(_ s: ArraySlice<Float>, _ f: Double, _ sr: Double) -> Double {
        let k = 2 * cos(2 * .pi * f / sr)
        var s1 = 0.0, s2 = 0.0
        for x in s { let s0 = Double(x) + k * s1 - s2; s2 = s1; s1 = s0 }
        return s1 * s1 + s2 * s2 - k * s1 * s2
    }

    /// Un tasto per blocco da 25 ms se una bassa e un'alta dominano; ripetizioni consecutive = un solo tasto.
    static func tasto(_ s: ArraySlice<Float>, sr: Double) -> Character? {
        let energia = s.reduce(0.0) { $0 + Double($1 * $1) } * Double(s.count) / 2
        guard energia > 1e-4 else { return nil }
        let lo = basse.map { goertzel(s, $0, sr) }, hi = alte.map { goertzel(s, $0, sr) }
        guard let li = lo.indices.max(by: { lo[$0] < lo[$1] }), let hi_ = hi.indices.max(by: { hi[$0] < hi[$1] }) else { return nil }
        let secL = lo.enumerated().filter { $0.offset != li }.map(\.element).max() ?? 0
        let secH = hi.enumerated().filter { $0.offset != hi_ }.map(\.element).max() ?? 0
        guard lo[li] > secL * 6, hi[hi_] > secH * 6, (lo[li] + hi[hi_]) > energia * 0.3 else { return nil }
        return tasti[li][hi_]
    }

    static func dtmf(_ s: [Float], sr: Double) -> String {
        let blocco = Int(sr * 0.025)
        guard s.count > blocco else { return "" }
        var out = "", ultimo: Character?, conta = 0
        for i in stride(from: 0, to: s.count - blocco, by: blocco) {
            let t = tasto(s[i..<(i + blocco)], sr: sr)
            if t == ultimo { conta += 1 } else { ultimo = t; conta = 1 }
            if conta == 2, let t { out.append(t) }
        }
        return out
    }
}

/// Ascolto dal vivo dei toni DTMF (microfono).
final class DTMFLive: ObservableObject {
    @Published var attivo = false
    @Published var tasto = ""
    @Published var sequenza = ""
    private let engine = AVAudioEngine()
    private var ultimo: Character?
    private var conta = 0

    func start() {
        AVAudioSession.sharedInstance().requestRecordPermission { ok in
            guard ok else { return }
            DispatchQueue.main.async { self.avvia() }
        }
    }

    private func avvia() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
        try? s.setActive(true)
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        let sr = fmt.sampleRate
        let blocco = AVAudioFrameCount(sr * 0.025)
        input.installTap(onBus: 0, bufferSize: blocco, format: fmt) { [weak self] buf, _ in
            guard let self, let ch = buf.floatChannelData else { return }
            let arr = Array(UnsafeBufferPointer(start: ch[0], count: Int(buf.frameLength)))
            let t = AudioAnalisi.tasto(arr[...], sr: sr)
            DispatchQueue.main.async {
                if t == self.ultimo { self.conta += 1 } else { self.ultimo = t; self.conta = 1 }
                self.tasto = t.map(String.init) ?? ""
                if self.conta == 2, let t { self.sequenza.append(t); haptic() }
            }
        }
        try? engine.start()
        attivo = true
    }

    func stop() {
        guard attivo else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        attivo = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
