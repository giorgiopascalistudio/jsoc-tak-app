import HaishinKit
import ReplayKit
import SRTHaishinKit
import VideoToolbox

/// Trasmissione dello schermo verso MediaMTX (SRT), come la modalità schermo di Larix.
/// L'indirizzo (con utente e password) lo scrive l'app nel gruppo condiviso.
final class SampleHandler: RPBroadcastSampleHandler, @unchecked Sendable {
    private var session: (any StreamSession)?
    private let mixer = MediaMixer(captureSessionMode: .manual, multiTrackAudioMixingEnabled: true)
    private var serveConfigurazione = true

    override init() {
        super.init()
        Task { await StreamSessionBuilderFactory.shared.register(SRTSessionFactory()) }
    }

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        let d = UserDefaults(suiteName: "group.com.giorgiopascali.heltecnav")
        guard let s = d?.string(forKey: "broadcast.url"), let url = URL(string: s) else {
            finishBroadcastWithError(NSError(domain: "ReMida", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Apri Re Mida › Raccolta › Video e imposta la password OTS, poi riprova."]))
            return
        }
        Task {
            do {
                // registrazione del protocollo prima di creare la sessione
                await StreamSessionBuilderFactory.shared.register(SRTSessionFactory())
                session = try await StreamSessionBuilderFactory.shared.make(url).setMode(.publish).build()
                var vs = await mixer.videoMixerSettings
                vs.mode = .passthrough
                await mixer.setVideoMixerSettings(vs)
                // ReplayKit ha poca memoria: coda video corta
                await session?.stream.setVideoInputBufferCounts(5)
                await mixer.startRunning()
                if let session {
                    await mixer.addOutput(session.stream)
                    try? await session.connect {}
                }
            } catch {
                finishBroadcastWithError(error)
            }
        }
    }

    override func broadcastFinished() {
        Task {
            try? await session?.close()
            await mixer.stopRunning()
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with type: RPSampleBufferType) {
        switch type {
        case .video:
            if serveConfigurazione, let dim = sampleBuffer.formatDescription?.dimensions {
                serveConfigurazione = false
                Task {
                    // schermo ridotto a metà: meno banda su rete cellulare
                    if var v = await session?.stream.videoSettings {
                        v.videoSize = .init(width: CGFloat(dim.width / 2), height: CGFloat(dim.height / 2))
                        v.bitRate = 1_200_000
                        v.profileLevel = kVTProfileLevel_H264_Baseline_AutoLevel as String
                        try? await session?.stream.setVideoSettings(v)
                    }
                }
            }
            Task { await mixer.append(sampleBuffer) }
        case .audioMic:
            if sampleBuffer.dataReadiness == .ready { Task { await mixer.append(sampleBuffer, track: 0) } }
        case .audioApp:
            if sampleBuffer.dataReadiness == .ready { Task { await mixer.append(sampleBuffer, track: 1) } }
        @unknown default:
            break
        }
    }
}
