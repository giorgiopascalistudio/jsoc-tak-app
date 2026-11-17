import SwiftUI
import WebKit
import PDFKit
import CoreImage

/// Modalità notturna nero/rosso, solo manuale. Tutta l'interfaccia passa in rosso (si moltiplica per il rosso:
/// il nero resta nero, il bianco diventa rosso), i PDF si invertono (fondo nero, testo rosso), le pagine web e
/// la mappa 3D ricevono un filtro rosso, e la luminosità dello schermo scende.
@MainActor
final class NightMode: ObservableObject {
    static let red = Night.red
    static let uiRed = Night.uiRed

    @Published private(set) var on: Bool
    private var savedBrightness: CGFloat?

    init() {
        on = UserDefaults.standard.bool(forKey: "night.on")
        applyAppearance()
    }

    /// Cambia la luminosità notturna mentre la notte è accesa.
    func impostaLuce(_ v: Double) {
        UserDefaults.standard.set(v, forKey: "night.luce")
        if on { UIScreen.main.brightness = CGFloat(v) }
        objectWillChange.send()
    }

    func toggle() {
        on.toggle()
        UserDefaults.standard.set(on, forKey: "night.on")
        let screen = UIScreen.main
        if on {
            savedBrightness = screen.brightness
            screen.brightness = min(screen.brightness, CGFloat(Night.luce))
        } else if let b = savedBrightness {
            screen.brightness = b
        }
        applyAppearance()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Barre di sistema (UIKit): titoli e icone in rosso o normali.
    private func applyAppearance() {
        let fg: UIColor = on ? Self.uiRed : .white
        let olive = UIColor(red: 0.604, green: 0.682, blue: 0.357, alpha: 1)
        let bar = UIColor(red: 0.020, green: 0.024, blue: 0.016, alpha: 0.92)
        let nav = UINavigationBarAppearance()
        nav.configureWithDefaultBackground()
        nav.backgroundEffect = UIBlurEffect(style: .systemChromeMaterialDark)
        nav.backgroundColor = on ? .black : bar
        nav.shadowColor = on ? .clear : olive.withAlphaComponent(0.18)
        nav.titleTextAttributes = [.foregroundColor: fg]
        nav.largeTitleTextAttributes = [.foregroundColor: fg, .font: UIFont.systemFont(ofSize: 32, weight: .heavy)]
        // in cima alla pagina la barra è trasparente (come le app Apple), diventa vetro solo scorrendo
        let bordo = UINavigationBarAppearance()
        bordo.configureWithTransparentBackground()
        bordo.titleTextAttributes = nav.titleTextAttributes
        bordo.largeTitleTextAttributes = nav.largeTitleTextAttributes
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = bordo
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().compactScrollEdgeAppearance = bordo
        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        tab.backgroundEffect = UIBlurEffect(style: .systemChromeMaterialDark)
        tab.backgroundColor = on ? .black : bar
        tab.shadowColor = on ? .clear : olive.withAlphaComponent(0.18)
        if !on {
            for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
                item.normal.iconColor = UIColor.white.withAlphaComponent(0.45)
                item.normal.titleTextAttributes = [.foregroundColor: UIColor.white.withAlphaComponent(0.45)]
                item.selected.iconColor = olive
                item.selected.titleTextAttributes = [.foregroundColor: olive]
            }
        }
        if on {
            for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
                item.normal.iconColor = Self.uiRed.withAlphaComponent(0.55)
                item.normal.titleTextAttributes = [.foregroundColor: Self.uiRed.withAlphaComponent(0.55)]
                item.selected.iconColor = Self.uiRed
                item.selected.titleTextAttributes = [.foregroundColor: Self.uiRed]
            }
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UISegmentedControl.appearance().selectedSegmentTintColor = on ? Self.uiRed.withAlphaComponent(0.45) : olive.withAlphaComponent(0.55)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: fg], for: .normal)
        for scene in UIApplication.shared.connectedScenes {
            for w in (scene as? UIWindowScene)?.windows ?? [] { w.tintColor = on ? Self.uiRed : olive }
        }
    }
}

/// Funzioni senza stato (usabili anche fuori dal thread principale).
enum Night {
    static let red = Color(red: 0.85, green: 0, blue: 0)
    /// Filtro della notte: rosso ma con un po' di verde e blu, così la mappa resta leggibile.
    static var filtro: Color { Color(red: 1, green: 0.30 * intensitaVerde, blue: 0.22 * intensitaVerde) }
    static var intensitaVerde: Double { 1 - (UserDefaults.standard.object(forKey: "night.rosso") as? Double ?? 0.5) }
    /// Luminosità massima dello schermo di notte (0,05–1).
    static var luce: Double { UserDefaults.standard.object(forKey: "night.luce") as? Double ?? 0.35 }
    static let uiRed = UIColor(red: 0.85, green: 0, blue: 0, alpha: 1)

    // MARK: web

    static let webScript = """
    (function(on){var id='remida-night';var s=document.getElementById(id);
    if(!on){if(s)s.remove();return;}
    if(!s){s=document.createElement('style');s.id=id;(document.head||document.documentElement).appendChild(s);}
    s.textContent='html{filter:grayscale(1) brightness(.85)!important;background:#000!important}'+
    'html::after{content:"";position:fixed;inset:0;background:#d00;mix-blend-mode:multiply;pointer-events:none;z-index:2147483647}';
    })
    """

    static func apply(to web: WKWebView, on: Bool) {
        web.evaluateJavaScript(webScript + "(\(on));", completionHandler: nil)
    }

    /// Script che applica il filtro a ogni pagina caricata, letto all'avvio della pagina.
    static func userScript() -> WKUserScript {
        let on = UserDefaults.standard.bool(forKey: "night.on")
        return WKUserScript(source: webScript + "(\(on));", injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    // MARK: immagini e PDF

    private static let ci = CIContext()

    /// invert = true per documenti (carta bianca -> nero, testo -> rosso); false per foto (foto in rosso).
    static func redden(_ image: UIImage, invert: Bool) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let f = CIFilter(name: "CIColorMatrix")!
        f.setValue(CIImage(cgImage: cg), forKey: kCIInputImageKey)
        let k: CGFloat = invert ? -0.85 : 0.85
        f.setValue(CIVector(x: 0.299 * k, y: 0.587 * k, z: 0.114 * k, w: 0), forKey: "inputRVector")
        f.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
        f.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
        f.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        f.setValue(CIVector(x: invert ? 0.85 : 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
        guard let out = f.outputImage, let res = ci.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: res, scale: image.scale, orientation: image.imageOrientation)
    }

    /// PDF ridisegnato pagina per pagina in rosso su nero (si perde la selezione del testo, resta lo zoom).
    static func nightPDF(from url: URL, maxPages: Int = 80) async -> PDFDocument? {
        await Task.detached(priority: .userInitiated) { () -> PDFDocument? in
            let src: PDFDocument?
            if ["jpg", "jpeg", "png", "heic", "webp"].contains(url.pathExtension.lowercased()) {
                guard let img = UIImage(contentsOfFile: url.path), let red = redden(img, invert: false),
                      let page = PDFPage(image: red) else { return nil }
                let d = PDFDocument(); d.insert(page, at: 0); return d
            }
            src = PDFDocument(url: url)
            guard let src else { return nil }
            let out = PDFDocument()
            for i in 0..<min(src.pageCount, maxPages) {
                guard let p = src.page(at: i) else { continue }
                let box = p.bounds(for: .cropBox)
                let scale = 1600 / max(box.width, box.height)
                let img = p.thumbnail(of: CGSize(width: box.width * scale, height: box.height * scale), for: .cropBox)
                if let red = redden(img, invert: true), let np = PDFPage(image: red) {
                    out.insert(np, at: out.pageCount)
                }
            }
            return out
        }.value
    }
}

/// Visore notturno per PDF e immagini.
struct NightDocView: View {
    let url: URL
    @Environment(\.dismiss) var dismiss
    @State private var doc: PDFDocument?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let doc {
                    PDFKitView(document: doc).ignoresSafeArea(edges: .bottom)
                } else if failed {
                    Text("Non riesco ad aprirlo in modalità notturna.").foregroundStyle(NightMode.red)
                } else {
                    ProgressView().tint(NightMode.red)
                }
            }
            .navigationTitle(url.deletingPathExtension().lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
        }
        .task {
            doc = await Night.nightPDF(from: url)
            failed = doc == nil
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.backgroundColor = .black
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.pageShadowsEnabled = false
        v.document = document
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {}
}

