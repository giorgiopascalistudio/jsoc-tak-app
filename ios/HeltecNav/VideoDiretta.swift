import AVFoundation

/// Tiene i video HLS attaccati alla diretta: AVPlayer di suo parte qualche segmento indietro e,
/// a ogni piccolo blocco della rete, accumula ritardo (si arrivava a quasi un minuto).
/// Ogni 2 s controlla la distanza dalla fine del flusso e, se supera `massimo`, salta a 1 s dalla fine.
extension AVPlayer {
    private static var osservatori = [ObjectIdentifier: Any]()

    func agganciaAllaDiretta(massimo: Double = 4) {
        if let item = currentItem {
            item.preferredForwardBufferDuration = 1
            if #available(iOS 13.0, *) {
                item.automaticallyPreservesTimeOffsetFromLive = false
                item.configuredTimeOffsetFromLive = CMTime(seconds: 1, preferredTimescale: 600)
            }
        }
        let chiave = ObjectIdentifier(self)
        if let vecchio = Self.osservatori[chiave] { removeTimeObserver(vecchio) }
        Self.osservatori[chiave] = addPeriodicTimeObserver(forInterval: CMTime(seconds: 2, preferredTimescale: 600), queue: .main) { [weak self] ora in
            guard let self, let item = self.currentItem, let r = item.seekableTimeRanges.last?.timeRangeValue else { return }
            let fine = CMTimeGetSeconds(CMTimeRangeGetEnd(r))
            guard fine.isFinite, fine - CMTimeGetSeconds(ora) > massimo else { return }
            self.seek(to: CMTime(seconds: fine - 1, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .positiveInfinity)
            if self.rate == 0 { self.play() }
        }
    }

    func staccaDallaDiretta() {
        let chiave = ObjectIdentifier(self)
        if let vecchio = Self.osservatori.removeValue(forKey: chiave) { removeTimeObserver(vecchio) }
    }
}
