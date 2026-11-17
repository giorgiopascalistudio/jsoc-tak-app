import SwiftUI
import AVFoundation
import MediaPlayer

/// Tasti volume come comandi della mappa: + = avanti, − = indietro.
/// iOS non dà un accesso diretto ai tasti: si osserva il volume e lo si rimette subito a metà
/// (con un MPVolumeView nascosto, così non compare nemmeno il riquadro del volume).
@MainActor
final class VolumeTasti: NSObject, ObservableObject {
    static let shared = VolumeTasti()

    enum Funzione: String, CaseIterable, Identifiable {
        case punti, stile, spenti
        var id: String { rawValue }
        var nome: String {
            switch self {
            case .punti: return "Scorrono i punti (OBJ e operatori)"
            case .stile: return "Cambiano lo stile della mappa"
            case .spenti: return "Volume normale"
            }
        }
    }

    @Published var funzione = Funzione(rawValue: UserDefaults.standard.string(forKey: "mappa.volume") ?? "") ?? .punti {
        didSet { UserDefaults.standard.set(funzione.rawValue, forKey: "mappa.volume") }
    }
    /// +1 o −1 a ogni pressione
    var azione: ((Int) -> Void)?
    /// su e giù tenuti premuti insieme
    var sos: (() -> Void)?
    private var ultimiSu: [Date] = []
    private var ultimiGiu: [Date] = []

    private var osservatore: NSKeyValueObservation?
    private let vista = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 10, height: 10))
    private var riposo: Float = 0.5
    private var ignora = false

    func avvia() {
        guard osservatore == nil else { return }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.ambient, options: [.mixWithOthers])
        try? s.setActive(true)
        if vista.superview == nil, let w = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first {
            vista.alpha = 0.01
            w.addSubview(vista)
        }
        riposo = min(max(s.outputVolume, 0.1), 0.9)
        if s.outputVolume <= 0.0 || s.outputVolume >= 1.0 { imposta(0.5) }
        osservatore = s.observe(\.outputVolume, options: [.old, .new]) { [weak self] _, v in
            guard let nuovo = v.newValue, let vecchio = v.oldValue else { return }
            Task { @MainActor in self?.cambiato(nuovo, vecchio) }
        }
    }

    func ferma() {
        osservatore?.invalidate()
        osservatore = nil
        vista.removeFromSuperview()
    }

    private func cambiato(_ nuovo: Float, _ vecchio: Float) {
        if ignora { ignora = false; return }
        guard abs(nuovo - vecchio) > 0.001 else { return }
        let ora = Date()
        if nuovo > vecchio { ultimiSu.append(ora) } else { ultimiGiu.append(ora) }
        ultimiSu.removeAll { ora.timeIntervalSince($0) > 1.3 }
        ultimiGiu.removeAll { ora.timeIntervalSince($0) > 1.3 }
        // tenendo premuti insieme su e giù arrivano scatti dei due tasti mescolati: 3 per tasto in 1,3 s = SOS
        if ultimiSu.count >= 3 && ultimiGiu.count >= 3 {
            ultimiSu = []; ultimiGiu = []
            sos?()
        } else if funzione != .spenti {
            azione?(nuovo > vecchio ? 1 : -1)
        }
        if funzione != .spenti { imposta(riposo) }
    }

    private func imposta(_ v: Float) {
        guard let slider = vista.subviews.compactMap({ $0 as? UISlider }).first else { return }
        ignora = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { slider.value = v }
    }
}
