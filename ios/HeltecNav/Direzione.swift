import UIKit
import MapKit

/// Segnaposto con la direzione: cono (io) o freccia (compagni) che punta dove guarda l'operatore,
/// corretto per la rotazione della mappa. Sotto, il callsign.
final class DirezioneView: MKAnnotationView {
    static let idIo = "io", idCompagno = "compagno"

    private let cono = CAShapeLayer()
    private let freccia = CAShapeLayer()
    private let punto = CAShapeLayer()
    private let bordo = CAShapeLayer()
    private let etichetta = UILabel()
    private let lato: CGFloat = 76
    private var colore = UIColor.systemBlue

    /// direzione in gradi dal nord vero (nil = sconosciuta)
    var direzione: Double? { didSet { aggiornaRotazione() } }
    /// rotazione della mappa (camera.heading)
    var rotazioneMappa: Double = 0 { didSet { aggiornaRotazione() } }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: lato, height: lato)
        backgroundColor = .clear
        let c = CGPoint(x: lato / 2, y: lato / 2)

        // cono: spicchio di 70° lungo 36 pt
        let p = UIBezierPath()
        p.move(to: c)
        p.addArc(withCenter: c, radius: 36, startAngle: -.pi / 2 - .pi * 35 / 180, endAngle: -.pi / 2 + .pi * 35 / 180, clockwise: true)
        p.close()
        cono.path = p.cgPath
        cono.frame = bounds
        layer.addSublayer(cono)

        // freccia: triangolo davanti al pallino
        let f = UIBezierPath()
        f.move(to: CGPoint(x: c.x, y: c.y - 25))
        f.addLine(to: CGPoint(x: c.x - 8, y: c.y - 10))
        f.addLine(to: CGPoint(x: c.x + 8, y: c.y - 10))
        f.close()
        freccia.path = f.cgPath
        freccia.frame = bounds
        freccia.strokeColor = UIColor.black.withAlphaComponent(0.6).cgColor
        freccia.lineWidth = 1
        layer.addSublayer(freccia)

        bordo.path = UIBezierPath(ovalIn: CGRect(x: c.x - 11, y: c.y - 11, width: 22, height: 22)).cgPath
        bordo.fillColor = UIColor.white.cgColor
        bordo.shadowColor = UIColor.black.cgColor
        bordo.shadowOpacity = 0.5
        bordo.shadowRadius = 3
        bordo.shadowOffset = .zero
        layer.addSublayer(bordo)
        punto.path = UIBezierPath(ovalIn: CGRect(x: c.x - 8, y: c.y - 8, width: 16, height: 16)).cgPath
        layer.addSublayer(punto)

        etichetta.font = .monospacedSystemFont(ofSize: 11, weight: .heavy)
        etichetta.textColor = .white
        etichetta.textAlignment = .center
        etichetta.layer.shadowColor = UIColor.black.cgColor
        etichetta.layer.shadowOpacity = 1
        etichetta.layer.shadowRadius = 2
        etichetta.layer.shadowOffset = .zero
        etichetta.frame = CGRect(x: -20, y: lato / 2 + 12, width: lato + 40, height: 14)
        addSubview(etichetta)
        clipsToBounds = false
        displayPriority = .required
        collisionMode = .circle
    }

    required init?(coder: NSCoder) { fatalError() }

    /// io: cono blu; compagno: freccia del colore della squadra; vecchio: grigio
    func configura(io: Bool, colore: UIColor, testo: String?, direzione: Double?, rotazioneMappa: Double) {
        self.colore = colore
        punto.fillColor = colore.cgColor
        cono.isHidden = !io
        freccia.isHidden = io
        cono.fillColor = colore.withAlphaComponent(0.32).cgColor
        freccia.fillColor = colore.cgColor
        etichetta.text = testo
        etichetta.isHidden = testo == nil
        self.rotazioneMappa = rotazioneMappa
        self.direzione = direzione
    }

    private func aggiornaRotazione() {
        let visibile = direzione != nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let a = CGFloat(((direzione ?? 0) - rotazioneMappa) * .pi / 180)
        cono.setAffineTransform(CGAffineTransform(rotationAngle: a))
        freccia.setAffineTransform(CGAffineTransform(rotationAngle: a))
        cono.opacity = visibile ? 1 : 0
        freccia.opacity = visibile ? 1 : 0
        CATransaction.commit()
    }
}
