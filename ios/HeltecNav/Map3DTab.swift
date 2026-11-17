import SwiftUI
import WebKit
import CoreLocation

/// Mappa 3D: la pagina CesiumJS del server (3D fotorealistico Google dal ponte /3d/root.json, punti e aree di gara)
/// con sopra la posizione e la direzione del telefono, mandate alla pagina con REMIDA.me(...).
/// Serve il server raggiungibile (Tailscale acceso).
struct Map3DTab: View {
    @EnvironmentObject var location: LocationService
    @EnvironmentObject var night: NightMode
    @AppStorage("map3d.url") private var urlText = ""
    @StateObject private var web = Map3DModel()
    @State private var settings = false

    var body: some View {
        ZStack(alignment: .top) {
            Map3DWebView(model: web, url: URL(string: urlText) ?? URL(string: "about:blank")!)
                .ignoresSafeArea(edges: [.top, .horizontal])

            if web.loading {
                ProgressView("Carico il 3D…").padding(12).background(.black.opacity(0.7), in: Capsule()).padding(.top, 60)
            }
            if let err = web.error {
                VStack(spacing: 10) {
                    Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(Theme.red)
                    Text("Server 3D non raggiungibile").font(.headline)
                    Text("Accendi Tailscale e riprova.\n\(err)").font(.footnote).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                    Button("Riprova") { web.reload() }.buttonStyle(.borderedProminent).tint(Theme.gold)
                }
                .padding(20).background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16)).padding(.top, 120)
            }

            HStack {
                NightToolbarButton().background(.black.opacity(0.6), in: Circle()).padding(.leading, 12).padding(.top, 8)
                Spacer()
                Button { settings = true } label: {
                    Image(systemName: "gearshape").padding(10).background(.black.opacity(0.6), in: Circle())
                }
                .padding(.trailing, 12).padding(.top, 8)
            }
        }
        .background(Color.black)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true   // schermo acceso mentre guardi la mappa
            push()
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onReceive(location.$location) { _ in push() }
        .onReceive(location.$heading) { h in
            if let h { web.js("window.REMIDA&&REMIDA.dir(\(h))") }
        }
        .onChange(of: web.ready) { _ in push(); web.applyNight(night.on) }
        .onChange(of: night.on) { on in web.applyNight(on) }
        .sheet(isPresented: $settings) {
            NavigationStack {
                Form {
                    Section("Indirizzo della pagina 3D") {
                        TextField("URL", text: $urlText).font(Theme.mono(13)).autocorrectionDisabled().textInputAutocapitalization(.never)
                        Button("Ripristina predefinito") { urlText = "" }
                    }
                    Section {
                        Button("Ricarica la pagina") { web.reload(); settings = false }
                    } footer: {
                        Text("La pagina e i punti li aggiorna il server (genera_vista3d.py). Il 3D arriva in streaming: serve rete e Tailscale.")
                    }
                }
                .navigationTitle("Mappa 3D")
                .toolbar { Button("Fine") { settings = false } }
            }
        }
    }

    private func push() {
        guard web.ready, let l = location.location else { return }
        let dir = location.heading ?? -1
        web.js(String(format: "window.REMIDA&&REMIDA.me(%.7f,%.7f,%.1f,%.1f)", l.coordinate.latitude, l.coordinate.longitude,
                      max(0, l.horizontalAccuracy), dir))
    }
}

final class Map3DModel: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var loading = true
    @Published var ready = false
    @Published var error: String?
    weak var view: WKWebView?
    private var lastHeading = Date.distantPast

    func js(_ code: String) {
        guard ready else { return }
        // la direzione arriva molte volte al secondo: al massimo 5 aggiornamenti al secondo
        if code.contains("REMIDA.dir") {
            guard Date().timeIntervalSince(lastHeading) > 0.2 else { return }
            lastHeading = Date()
        }
        view?.evaluateJavaScript(code, completionHandler: nil)
    }

    func applyNight(_ on: Bool) {
        if let v = view { Night.apply(to: v, on: on) }
    }

    func reload() {
        error = nil
        loading = true
        ready = false
        view?.reload()
    }

    func webView(_ w: WKWebView, didStartProvisionalNavigation n: WKNavigation!) {
        loading = true
        error = nil
    }

    func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
        loading = false
        ready = true
    }

    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) {
        loading = false
        ready = false
        error = e.localizedDescription
    }

    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) {
        loading = false
        error = e.localizedDescription
    }
}

struct Map3DWebView: UIViewRepresentable {
    let model: Map3DModel
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.userContentController.addUserScript(Night.userScript())
        let w = WKWebView(frame: .zero, configuration: cfg)
        w.isOpaque = false
        w.backgroundColor = .black
        w.scrollView.isScrollEnabled = false
        w.scrollView.bounces = false
        w.navigationDelegate = model
        model.view = w
        w.load(URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 20))
        context.coordinator.url = url
        return w
    }

    func updateUIView(_ w: WKWebView, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.url = url
            model.ready = false
            w.load(URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 20))
        }
    }

    func makeCoordinator() -> Coord { Coord() }
    final class Coord { var url: URL? }
}
