import SwiftUI
import AVFoundation
import CoreMotion

/// Mirino: fotocamera con azimut vero (bussola del telefono, già corretta per la declinazione),
/// inclinazione, acquisizione azimut per la triangolazione e misura dell'angolo tra due direzioni.
struct MirinoView: View {
    @EnvironmentObject var location: LocationService
    @EnvironmentObject var ril: Rilevamenti
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cam = CameraBox()
    @StateObject private var motion = Inclinazione()
    @State private var angoloA: Double?
    @State private var flash = false
    @State private var ultimo: String?

    var heading: Double? { location.heading }

    var body: some View {
        ZStack {
            CameraPreview(session: cam.session).ignoresSafeArea()
            if flash { Color.white.opacity(0.35).ignoresSafeArea() }
            // croce
            ZStack {
                Rectangle().fill(Theme.gold).frame(width: 2, height: 70)
                Rectangle().fill(Theme.gold).frame(width: 70, height: 2)
                Circle().stroke(Theme.gold, lineWidth: 2).frame(width: 34, height: 34)
            }
            .shadow(color: .black, radius: 2)

            VStack {
                Nastro(heading: heading ?? 0).frame(height: 52).padding(.top, 8)
                HStack(alignment: .firstTextBaseline) {
                    Text(heading.map { String(format: "%03.0f°", $0) } ?? "---°").font(Theme.mono(44, .bold))
                    Text(heading.map { cardinale($0) } ?? "").font(Theme.mono(20, .bold)).foregroundStyle(Theme.gold)
                }
                .shadow(color: .black, radius: 3)
                HStack(spacing: 14) {
                    Label(String(format: "%+.0f°", motion.pitch), systemImage: "angle").font(Theme.mono(14))
                    if location.headingAccuracy >= 0 {
                        Text(String(format: "± %.0f°", location.headingAccuracy)).font(Theme.mono(14))
                            .foregroundStyle(location.headingAccuracy > 15 ? Theme.red : Theme.green)
                    }
                    if let l = location.location { Text(String(format: "GPS ± %.0f m", l.horizontalAccuracy)).font(Theme.mono(14)) }
                }
                .shadow(color: .black, radius: 3)
                if location.headingAccuracy > 15 {
                    Text("Bussola imprecisa: muovi il telefono a 8 e allontanati da metallo/auto")
                        .font(.caption).padding(6).background(Theme.red.opacity(0.8), in: Capsule())
                }
                if let a = angoloA {
                    Text(String(format: "A bloccato a %03.0f° · angolo attuale %.1f°", a, differenza(a, heading ?? a)))
                        .font(Theme.mono(13)).padding(6).background(.black.opacity(0.6), in: Capsule())
                }
                if let u = ultimo { Text(u).font(.caption).padding(6).background(.black.opacity(0.6), in: Capsule()) }
                Spacer()
                HStack(spacing: 12) {
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 50, height: 50) }
                        .background(.black.opacity(0.6), in: Circle())
                    Spacer()
                    Button {
                        if let a = angoloA, let h = heading {
                            let d = differenza(a, h)
                            ril.angoli.insert(d, at: 0)
                            ultimo = String(format: "Angolo salvato: %.1f° (per Snellius)", d)
                            angoloA = nil
                        } else { angoloA = heading }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        Text(angoloA == nil ? "Angolo: A" : "Angolo: B").font(.footnote.bold()).frame(height: 50).padding(.horizontal, 14)
                    }
                    .background(.black.opacity(0.6), in: Capsule())
                    Button {
                        guard let h = heading, let c = location.location?.coordinate else { return }
                        ril.add(c, h)
                        ultimo = String(format: "Azimut %.1f° acquisito (Triangolazione → Azimut)", h)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        withAnimation(.easeOut(duration: 0.15)) { flash = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { flash = false }
                    } label: {
                        Label("ACQUISISCI", systemImage: "scope").font(.headline).frame(height: 56).padding(.horizontal, 18)
                    }
                    .foregroundStyle(.black).background(Theme.gold, in: Capsule())
                }
                .padding()
            }
            .foregroundStyle(.white)
        }
        .onAppear { cam.start(); motion.start() }
        .onDisappear { cam.stop(); motion.stop() }
    }

    func differenza(_ a: Double, _ b: Double) -> Double {
        var d = abs(b - a).truncatingRemainder(dividingBy: 360)
        if d > 180 { d = 360 - d }
        return d
    }

    func cardinale(_ h: Double) -> String {
        ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSO", "SO", "OSO", "O", "ONO", "NO", "NNO"][Int((h + 11.25) / 22.5) % 16]
    }
}

/// Bussola a nastro (come nei mirini): tacche ogni 5°, numeri ogni 30°.
struct Nastro: View {
    let heading: Double
    var body: some View {
        Canvas { ctx, size in
            let pxPerDeg = size.width / 90       // 90° visibili
            let mid = size.width / 2
            for d in stride(from: Int(heading) - 50, through: Int(heading) + 50, by: 1) where d % 5 == 0 {
                let x = mid + (Double(d) - heading) * pxPerDeg
                let lungo = d % 30 == 0
                var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: lungo ? 18 : 9))
                ctx.stroke(p, with: .color(.white), lineWidth: lungo ? 2 : 1)
                if lungo {
                    let v = ((d % 360) + 360) % 360
                    let nome = [0: "N", 90: "E", 180: "S", 270: "O"][v] ?? "\(v)"
                    ctx.draw(Text(nome).font(Theme.mono(13, .bold)).foregroundColor(v % 90 == 0 ? Theme.gold : .white),
                             at: CGPoint(x: x, y: 32))
                }
            }
            var t = Path(); t.move(to: CGPoint(x: mid - 7, y: size.height)); t.addLine(to: CGPoint(x: mid + 7, y: size.height))
            t.addLine(to: CGPoint(x: mid, y: size.height - 10)); t.closeSubpath()
            ctx.fill(t, with: .color(Theme.gold))
        }
        .background(.black.opacity(0.45))
    }
}

final class Inclinazione: ObservableObject {
    @Published var pitch = 0.0
    private let m = CMMotionManager()
    func start() {
        guard m.isDeviceMotionAvailable else { return }
        m.deviceMotionUpdateInterval = 1.0 / 20
        m.startDeviceMotionUpdates(to: .main) { [weak self] d, _ in
            guard let g = d?.gravity else { return }
            // la fotocamera guarda lungo -z: alzo sopra l'orizzonte = asin(g.z)
            self?.pitch = asin(max(-1, min(1, g.z))) * 180 / .pi
        }
    }
    func stop() { m.stopDeviceMotionUpdates() }
}

final class CameraBox: ObservableObject {
    let session = AVCaptureSession()
    private let q = DispatchQueue(label: "mirino.cam")
    private var pronto = false

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            guard ok else { return }
            self.q.async {
                if !self.pronto {
                    guard let d = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                          let i = try? AVCaptureDeviceInput(device: d) else { return }
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .high
                    if self.session.canAddInput(i) { self.session.addInput(i) }
                    self.session.commitConfiguration()
                    self.pronto = true
                }
                self.session.startRunning()
            }
        }
    }

    func stop() { q.async { self.session.stopRunning() } }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.layer2.session = session
        v.layer2.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ v: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var layer2: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
