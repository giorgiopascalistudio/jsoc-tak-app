import SwiftUI
import AVFoundation
import Vision
import Speech
import Photos

// MARK: OCR (sul telefono, senza rete)

enum OCR {
    static func text(from image: UIImage) async -> String {
        guard let cg = image.cgImage else { return "" }
        return await withCheckedContinuation { cont in
            let req = VNRecognizeTextRequest { r, _ in
                let lines = (r.results as? [VNRecognizedTextObservation])?.compactMap { $0.topCandidates(1).first?.string } ?? []
                cont.resume(returning: lines.joined(separator: "\n"))
            }
            req.recognitionLevel = .accurate
            req.recognitionLanguages = ["it-IT", "en-US"]
            req.usesLanguageCorrection = false   // i cifrati non vanno "corretti"
            let orientation = CGImagePropertyOrientation(image.imageOrientation)
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: cg, orientation: orientation).perform([req]) }
                catch { cont.resume(returning: "") }
            }
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

// MARK: Fotocamera di sistema

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: Scanner QR / codici a barre

struct CodeScanner: UIViewControllerRepresentable {
    var onCode: (String, String) -> Void

    func makeUIViewController(context: Context) -> ScannerVC {
        let vc = ScannerVC()
        vc.onCode = onCode
        return vc
    }

    func updateUIViewController(_ vc: ScannerVC, context: Context) {}

    final class ScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: ((String, String) -> Void)?
        private let session = AVCaptureSession()
        private var preview: AVCaptureVideoPreviewLayer?
        private var last = ""

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let dev = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: dev),
                  session.canAddInput(input) else { return }
            session.addInput(input)
            let out = AVCaptureMetadataOutput()
            guard session.canAddOutput(out) else { return }
            session.addOutput(out)
            out.setMetadataObjectsDelegate(self, queue: .main)
            let wanted: [AVMetadataObject.ObjectType] = [.qr, .ean13, .ean8, .code128, .code39, .code93, .dataMatrix, .aztec, .pdf417, .upce, .itf14]
            out.metadataObjectTypes = wanted.filter { out.availableMetadataObjectTypes.contains($0) }
            let p = AVCaptureVideoPreviewLayer(session: session)
            p.videoGravity = .resizeAspectFill
            view.layer.addSublayer(p)
            preview = p
            DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.bounds
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            DispatchQueue.global(qos: .userInitiated).async { [session] in session.stopRunning() }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objs: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard let o = objs.first as? AVMetadataMachineReadableCodeObject, let s = o.stringValue, s != last else { return }
            last = s
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onCode?(s, o.type.rawValue.components(separatedBy: ".").last ?? "")
        }
    }
}

// MARK: Registratore + trascrizione

final class Recorder: NSObject, ObservableObject {
    @Published var recording = false
    @Published var elapsed: TimeInterval = 0
    @Published var level: Float = 0
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private(set) var currentFile: String?

    func start() {
        AVAudioSession.sharedInstance().requestRecordPermission { ok in
            DispatchQueue.main.async { if ok { self.begin() } }
        }
    }

    private func begin() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try? s.setActive(true)
        let name = FieldLog.newFileName("m4a")
        let url = FieldLog.dir.appendingPathComponent(name)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100,
                                       AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
        guard let r = try? AVAudioRecorder(url: url, settings: settings) else { return }
        r.isMeteringEnabled = true
        r.record()
        recorder = r
        currentFile = name
        recording = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let r = self.recorder else { return }
            r.updateMeters()
            self.elapsed = r.currentTime
            self.level = max(0, (r.averagePower(forChannel: 0) + 60) / 60)
        }
    }

    /// Ferma e restituisce il nome del file.
    func stop() -> String? {
        recorder?.stop()
        timer?.invalidate()
        recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        defer { currentFile = nil }
        return currentFile
    }
}

enum Transcriber {
    static func transcribe(_ url: URL) async -> String {
        let auth = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard auth == .authorized, let rec = SFSpeechRecognizer(locale: Locale(identifier: "it-IT")) else {
            return "Trascrizione non autorizzata"
        }
        let req = SFSpeechURLRecognitionRequest(url: url)
        if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        req.shouldReportPartialResults = false
        return await withCheckedContinuation { c in
            var done = false
            rec.recognitionTask(with: req) { r, err in
                guard !done else { return }
                if let r, r.isFinal { done = true; c.resume(returning: r.bestTranscription.formattedString) }
                else if err != nil { done = true; c.resume(returning: "Trascrizione non riuscita") }
            }
        }
    }
}

// MARK: Varie

enum Torch {
    static func toggle() -> Bool {
        guard let d = AVCaptureDevice.default(for: .video), d.hasTorch, (try? d.lockForConfiguration()) != nil else { return false }
        defer { d.unlockForConfiguration() }
        if d.torchMode == .on { d.torchMode = .off; return false }
        try? d.setTorchModeOn(level: 1.0)
        return true
    }
}

enum PhotoSaver {
    static func save(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { s in
            guard s == .authorized || s == .limited else { return }
            PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: image) }
        }
    }
}
