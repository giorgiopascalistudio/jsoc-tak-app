import Foundation
import AVFoundation
import UIKit

// MARK: - Decodifica dei tempi (comune a microfono e luce)

/// Riceve "acceso/spento" con l'istante e ricava punti, linee, spazi tra lettere e parole.
/// La durata del punto si adatta da sola alla velocità di chi trasmette.
final class MorseTiming {
    private(set) var ditMs: Double = 90
    private var onSince: Double?
    private var offSince: Double = 0
    private var simbolo = ""
    private var testo = ""
    private var durate: [Double] = []   // ultimi toni, per stimare punto/linea

    var live: String { simbolo }
    var decoded: String { testo }
    var wpm: Int { Int((1200 / ditMs).rounded()) }

    func reset() { ditMs = 90; onSince = nil; offSince = 0; simbolo = ""; testo = ""; durate = [] }

    /// Cambio di stato. t in millisecondi.
    func edge(on: Bool, t: Double) {
        if on {
            guard onSince == nil else { return }
            onSince = t
        } else {
            guard let s = onSince else { return }
            onSince = nil
            offSince = t
            tono(t - s)
        }
    }

    /// Da chiamare spesso (anche senza cambi): chiude lettere e parole durante il silenzio.
    func tick(t: Double) {
        guard onSince == nil, offSince > 0 else { return }
        let silenzio = t - offSince
        if !simbolo.isEmpty, silenzio > ditMs * 2.2 { chiudiLettera() }
        if silenzio > ditMs * 5.5, !testo.isEmpty, testo.last != " " { testo.append(" ") }
    }

    private func tono(_ d: Double) {
        guard d > 12 else { return }   // disturbo
        durate.append(d)
        if durate.count > 24 { durate.removeFirst() }
        stimaPunto()
        simbolo.append(d < ditMs * 2 ? "." : "-")
        if simbolo.count > 7 { chiudiLettera() }
    }

    /// Divide le durate in due gruppi (punti e linee): il punto è la media del gruppo corto.
    private func stimaPunto() {
        guard durate.count >= 4 else { return }
        let s = durate.sorted()
        var best = (gap: 0.0, i: 0)
        for i in 1..<s.count where s[i] / s[i - 1] > best.gap { best = (s[i] / s[i - 1], i) }
        if best.gap > 1.8 {
            let corti = s[..<best.i], lunghi = s[best.i...]
            let dit = corti.reduce(0, +) / Double(corti.count)
            let dah = lunghi.reduce(0, +) / Double(lunghi.count)
            ditMs = max(25, min(600, (dit + dah / 3) / 2))
        } else {
            // tutti simili: o tutti punti o tutte linee; si decide rispetto alla stima attuale
            let m = s.reduce(0, +) / Double(s.count)
            ditMs = max(25, min(600, m < ditMs * 2 ? m : m / 3))
        }
    }

    private func chiudiLettera() {
        guard !simbolo.isEmpty else { return }
        testo.append(Self.lettera(simbolo))
        simbolo = ""
    }

    static let tabella: [String: String] = {
        var t = Dictionary(uniqueKeysWithValues: Cipher.morse.map { ($1, String($0)) })
        t[".-.-.-"] = "."; t["--..--"] = ","; t["..--.."] = "?"; t[".----."] = "'"; t["-.-.--"] = "!"; t["-..-."] = "/"
        t["-.--."] = "("; t["-.--.-"] = ")"; t[".-..."] = "&"; t["---..."] = ":"; t["-.-.-."] = ";"; t["-...-"] = "="
        t[".-.-."] = "+"; t["-....-"] = "-"; t[".-..-."] = "\""; t[".--.-."] = "@"; t["...---..."] = "SOS"
        return t
    }()

    static func lettera(_ s: String) -> String { tabella[s] ?? "[\(s)]" }
}

// MARK: - Soglia adattiva

/// Livello (qualsiasi unità) → acceso/spento con soglia che segue rumore e segnale, con isteresi e antirimbalzo.
struct Soglia {
    var rumore = 0.0, picco = 1.0, acceso = false
    var sensibilita = 0.5        // 0 = solo segnali forti, 1 = molto sensibile
    private var conferme = 0

    var valore: Double { rumore + (picco - rumore) * (0.65 - 0.35 * sensibilita) }

    mutating func passo(_ v: Double, inizializzato: Bool) -> Bool {
        if !inizializzato { rumore = v; picco = v * 1.5 + 1e-6 }
        if acceso { picco = max(v, picco * 0.995 + v * 0.005) } else { rumore = rumore * 0.98 + v * 0.02 }
        picco = max(picco, rumore * 1.6 + 1e-9)
        let s = valore
        let nuovo = acceso ? v > s * 0.85 : v > s * 1.1   // isteresi
        if nuovo != acceso { conferme += 1 } else { conferme = 0 }
        if conferme >= 2 { acceso = nuovo; conferme = 0 }
        return acceso
    }
}

// MARK: - Ascolto dal microfono

final class MorseAudioListener: ObservableObject {
    @Published var running = false
    @Published var livello = 0.0      // 0…1 per la barra
    @Published var frequenza = 0.0
    @Published var acceso = false
    @Published var testo = ""
    @Published var simboli = ""
    @Published var wpm = 0
    @Published var errore: String?
    var frequenzaFissa: Double? = nil
    var sensibilita = 0.5

    private let engine = AVAudioEngine()
    private let timing = MorseTiming()
    private var soglia = Soglia()
    private var init0 = false
    private var campioni: [Float] = []        // per la ricerca della frequenza
    private var blocco: [Float] = []
    private var tempo = 0.0                   // ms
    private var sr = 48000.0
    private var freqBloccata = 0.0
    private var ultimaRicerca = 0.0
    private var ultimoUI = 0.0

    func toggle() { running ? stop() : start() }

    func start() {
        AVAudioSession.sharedInstance().requestRecordPermission { ok in
            DispatchQueue.main.async { ok ? self.avvia() : (self.errore = "Permesso microfono negato") }
        }
    }

    private func avvia() {
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
            try s.setActive(true)
            let input = engine.inputNode
            let fmt = input.outputFormat(forBus: 0)
            sr = fmt.sampleRate
            timing.reset(); soglia = Soglia(); init0 = false; campioni = []; blocco = []; tempo = 0
            freqBloccata = frequenzaFissa ?? 0
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
                guard let self, let ch = buf.floatChannelData?[0] else { return }
                self.elabora(Array(UnsafeBufferPointer(start: ch, count: Int(buf.frameLength))))
            }
            engine.prepare()
            try engine.start()
            running = true; errore = nil; testo = ""; simboli = ""
        } catch {
            errore = "Microfono non disponibile: \(error.localizedDescription)"
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        livello = 0; acceso = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func clear() { timing.reset(); testo = ""; simboli = "" }

    // thread audio
    private func elabora(_ x: [Float]) {
        campioni.append(contentsOf: x)
        if campioni.count > 4096 { campioni.removeFirst(campioni.count - 4096) }
        if frequenzaFissa == nil, tempo - ultimaRicerca > 150, campioni.count == 4096 {
            ultimaRicerca = tempo
            cercaFrequenza()
        } else if let f = frequenzaFissa { freqBloccata = f }
        blocco.append(contentsOf: x)
        let n = max(64, Int(sr * 0.005))   // blocchi da 5 ms
        while blocco.count >= n {
            let b = Array(blocco[0..<n]); blocco.removeFirst(n)
            tempo += 1000 * Double(n) / sr
            let v = freqBloccata > 0 ? Double(goertzel(b, freqBloccata)) : 0
            soglia.sensibilita = sensibilita
            let on = soglia.passo(v, inizializzato: init0); init0 = true
            timing.edge(on: on, t: tempo)
            timing.tick(t: tempo)
            if tempo - ultimoUI > 50 {
                ultimoUI = tempo
                let liv = min(1, v / max(soglia.picco, 1e-9))
                let (t, s, w, f) = (timing.decoded, timing.live, timing.wpm, freqBloccata)
                DispatchQueue.main.async {
                    self.livello = liv; self.acceso = on; self.testo = t; self.simboli = s; self.wpm = w; self.frequenza = f
                }
            }
        }
    }

    /// Cerca il tono più forte tra 300 e 2000 Hz e lo blocca se spicca bene sul resto.
    private func cercaFrequenza() {
        let w = Array(campioni.suffix(2048))
        var best = (f: 0.0, m: Float(0)), somma: Float = 0, n = 0
        var f = 300.0
        while f <= 2000 {
            let m = goertzel(w, f)
            somma += m; n += 1
            if m > best.m { best = (f, m) }
            f += 20
        }
        let media = somma / Float(max(n, 1))
        if best.m > media * 6 {
            // affina ±20 Hz
            var fine = best
            for df in stride(from: -20.0, through: 20.0, by: 4) {
                let m = goertzel(w, best.f + df)
                if m > fine.m { fine = (best.f + df, m) }
            }
            if freqBloccata == 0 || abs(fine.f - freqBloccata) > 30 { freqBloccata = fine.f }
        }
    }

    private func goertzel(_ x: [Float], _ f: Double) -> Float {
        let k = 2 * cos(2 * Double.pi * f / sr)
        var s1 = 0.0, s2 = 0.0
        for v in x { let s = Double(v) + k * s1 - s2; s2 = s1; s1 = s }
        let p = s1 * s1 + s2 * s2 - k * s1 * s2
        return Float(sqrt(max(p, 0)) / Double(x.count))
    }
}

// MARK: - Ascolto della luce (fotocamera)

final class MorseLightListener: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var running = false
    @Published var livello = 0.0
    @Published var acceso = false
    @Published var testo = ""
    @Published var simboli = ""
    @Published var wpm = 0
    @Published var errore: String?
    var sensibilita = 0.5
    let session = AVCaptureSession()
    private let coda = DispatchQueue(label: "morse.luce")
    private let timing = MorseTiming()
    private var soglia = Soglia()
    private var init0 = false
    private var t0: Double?
    private var ultimoUI = 0.0
    private var configurata = false

    func toggle() { running ? stop() : start() }

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            DispatchQueue.main.async {
                guard ok else { self.errore = "Permesso fotocamera negato"; return }
                self.coda.async { self.avvia() }
            }
        }
    }

    private func avvia() {
        if !configurata {
            guard let d = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let inp = try? AVCaptureDeviceInput(device: d) else {
                DispatchQueue.main.async { self.errore = "Fotocamera non disponibile" }; return
            }
            session.beginConfiguration()
            session.sessionPreset = .vga640x480
            if session.canAddInput(inp) { session.addInput(inp) }
            let out = AVCaptureVideoDataOutput()
            out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            out.alwaysDiscardsLateVideoFrames = true
            out.setSampleBufferDelegate(self, queue: coda)
            if session.canAddOutput(out) { session.addOutput(out) }
            session.commitConfiguration()
            // 60 fps se possibile, esposizione bloccata dopo l'avvio così la luce non viene "compensata"
            if (try? d.lockForConfiguration()) != nil {
                if let r = d.activeFormat.videoSupportedFrameRateRanges.first, r.maxFrameRate >= 60 {
                    d.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 60)
                    d.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 60)
                }
                d.unlockForConfiguration()
            }
            configurata = true
        }
        timing.reset(); soglia = Soglia(); init0 = false; t0 = nil
        session.startRunning()
        DispatchQueue.main.async { self.running = true; self.errore = nil; self.testo = ""; self.simboli = "" }
        coda.asyncAfter(deadline: .now() + 1.0) {
            if let d = (self.session.inputs.first as? AVCaptureDeviceInput)?.device, (try? d.lockForConfiguration()) != nil {
                if d.isExposureModeSupported(.locked) { d.exposureMode = .locked }
                d.unlockForConfiguration()
            }
        }
    }

    func stop() {
        coda.async {
            self.session.stopRunning()
            if let d = (self.session.inputs.first as? AVCaptureDeviceInput)?.device, (try? d.lockForConfiguration()) != nil {
                if d.isExposureModeSupported(.continuousAutoExposure) { d.exposureMode = .continuousAutoExposure }
                d.unlockForConfiguration()
            }
        }
        running = false; acceso = false; livello = 0
    }

    func clear() { coda.async { self.timing.reset() }; testo = ""; simboli = "" }

    func captureOutput(_ o: AVCaptureOutput, didOutput sb: CMSampleBuffer, from c: AVCaptureConnection) {
        guard let px = CMSampleBufferGetImageBuffer(sb) else { return }
        let ts = CMSampleBufferGetPresentationTimeStamp(sb).seconds * 1000
        if t0 == nil { t0 = ts }
        let t = ts - (t0 ?? ts)
        CVPixelBufferLockBaseAddress(px, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(px, 0) else { return }
        let w = CVPixelBufferGetWidthOfPlane(px, 0), h = CVPixelBufferGetHeightOfPlane(px, 0)
        let row = CVPixelBufferGetBytesPerRowOfPlane(px, 0)
        let p = base.assumingMemoryBound(to: UInt8.self)
        // luminosità del quadrato centrale (dove punta il mirino): media dei pixel più chiari
        let lato = min(w, h) / 5
        let x0 = w / 2 - lato / 2, y0 = h / 2 - lato / 2
        var somma = 0, n = 0, massimo = 0
        var y = y0
        while y < y0 + lato {
            var x = x0
            while x < x0 + lato {
                let v = Int(p[y * row + x]); somma += v; n += 1; if v > massimo { massimo = v }
                x += 2
            }
            y += 2
        }
        let v = Double(somma) / Double(max(n, 1)) * 0.5 + Double(massimo) * 0.5
        soglia.sensibilita = sensibilita
        let on = soglia.passo(v, inizializzato: init0); init0 = true
        timing.edge(on: on, t: t)
        timing.tick(t: t)
        if t - ultimoUI > 50 {
            ultimoUI = t
            let liv = min(1, max(0, (v - soglia.rumore) / max(soglia.picco - soglia.rumore, 1)))
            let (tx, s, wp) = (timing.decoded, timing.live, timing.wpm)
            DispatchQueue.main.async { self.livello = liv; self.acceso = on; self.testo = tx; self.simboli = s; self.wpm = wp }
        }
    }
}

// MARK: - Trasmissione (suono, torcia, vibrazione)

final class MorseTransmitter: ObservableObject {
    @Published var playing = false
    @Published var corrente = -1     // indice del simbolo in trasmissione
    var suono = true, torcia = false, vibrazione = false
    var wpm = 12.0
    var frequenza = 700.0

    private let engine = AVAudioEngine()
    private var nodo: AVAudioSourceNode?
    private var gate = false
    private var fase = 0.0
    private var task: Task<Void, Never>?

    func play(_ morse: String) {
        stop()
        playing = true
        let unit = 1.2 / wpm   // secondi per punto
        if suono { avviaAudio() }
        task = Task { [weak self] in
            guard let self else { return }
            let simboli = Array(morse)
            for (i, c) in simboli.enumerated() {
                if Task.isCancelled { break }
                await MainActor.run { self.corrente = i }
                switch c {
                case ".", "·": await self.segnale(unit)
                case "-", "—", "_": await self.segnale(unit * 3)
                case " ": try? await Task.sleep(nanoseconds: UInt64(unit * 2 * 1e9))   // +1 già fatto dopo il simbolo = 3
                case "/": try? await Task.sleep(nanoseconds: UInt64(unit * 4 * 1e9))   // con gli spazi intorno = 7
                default: break
                }
            }
            await MainActor.run { self.stop() }
        }
    }

    private func segnale(_ durata: Double) async {
        acceso(true)
        try? await Task.sleep(nanoseconds: UInt64(durata * 1e9))
        acceso(false)
        try? await Task.sleep(nanoseconds: UInt64(1.2 / wpm * 1e9))
    }

    private func acceso(_ on: Bool) {
        gate = on && suono
        if torcia, let d = AVCaptureDevice.default(for: .video), d.hasTorch, (try? d.lockForConfiguration()) != nil {
            if on { try? d.setTorchModeOn(level: 1.0) } else { d.torchMode = .off }
            d.unlockForConfiguration()
        }
        if on && vibrazione { DispatchQueue.main.async { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() } }
    }

    private func avviaAudio() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default)
        try? s.setActive(true)
        let fmt = engine.outputNode.inputFormat(forBus: 0)
        let sr = fmt.sampleRate
        let mono = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        var amp = 0.0
        let n = AVAudioSourceNode(format: mono) { [unowned self] _, _, frames, abl in
            let buf = UnsafeMutableAudioBufferListPointer(abl)
            let inc = 2 * Double.pi * self.frequenza / sr
            for i in 0..<Int(frames) {
                let target = self.gate ? 0.5 : 0.0
                amp += (target - amp) * 0.005          // rampa morbida, niente click
                let v = Float(sin(self.fase) * amp)
                self.fase += inc
                if self.fase > 2 * .pi { self.fase -= 2 * .pi }
                for b in buf { b.mData?.assumingMemoryBound(to: Float.self)[i] = v }
            }
            return noErr
        }
        nodo = n
        engine.attach(n)
        engine.connect(n, to: engine.mainMixerNode, format: mono)
        try? engine.start()
    }

    func stop() {
        task?.cancel(); task = nil
        gate = false
        if engine.isRunning { engine.stop() }
        if let n = nodo { engine.detach(n); nodo = nil }
        if let d = AVCaptureDevice.default(for: .video), d.hasTorch, d.torchMode == .on, (try? d.lockForConfiguration()) != nil {
            d.torchMode = .off; d.unlockForConfiguration()
        }
        playing = false; corrente = -1
    }
}
