import SwiftUI

// MARK: - Colori e caratteri
//
// Nero OLED con un filo di verde, accento verde oliva (stile patch ricamata), testo bianco.
// I numeri e le coordinate sempre in monospaziato; titoli di sezione in maiuscoletto spaziato.

enum Theme {
    /// Accento principale (il nome resta "gold" per compatibilità col codice esistente): verde oliva.
    static let gold = Color(red: 0.604, green: 0.682, blue: 0.357)            // #9AAE5B
    static let olive = gold
    static let oliveBright = Color(red: 0.74, green: 0.82, blue: 0.48)
    static let oliveDeep = Color(red: 0.20, green: 0.24, blue: 0.11)
    static let red = Color(red: 0.95, green: 0.36, blue: 0.30)
    static let amber = Color(red: 0.92, green: 0.64, blue: 0.28)
    static let cyan = Color(red: 0.45, green: 0.78, blue: 0.86)
    static let green = Color(red: 0.45, green: 0.85, blue: 0.45)
    static let bg = Color(red: 0.020, green: 0.024, blue: 0.016)
    static let surface = Color(red: 0.060, green: 0.068, blue: 0.050)
    static let surface2 = Color(red: 0.090, green: 0.102, blue: 0.075)
    static let stroke = Color(red: 0.604, green: 0.682, blue: 0.357).opacity(0.22)
    static let card = surface
    static let dim = Color.white.opacity(0.58)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Titolo di sezione: icona + maiuscoletto spaziato.
struct SectionLabel: View {
    let text: String
    var icon: String? = nil
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: 11, weight: .bold)) }
            Text(text.uppercased()).font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(1.6)
            Spacer(minLength: 0)
            if let trailing { Text(trailing).font(Theme.mono(11, .semibold)).foregroundStyle(Theme.dim) }
        }
        .foregroundStyle(Theme.olive)
    }
}

/// Riquadro base: superficie scura, bordo sottile verde, angoli continui.
struct Card<Content: View>: View {
    var title: String? = nil
    var icon: String? = nil
    var trailing: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { SectionLabel(text: title, icon: icon, trailing: trailing) }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Theme.surface2, Theme.surface], startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 0.75))
    }
}

// MARK: - Interazione

/// Pulsante che si "preme": leggero rimpicciolimento e vibrazione.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Pulsante pieno verde oliva (azione principale).
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.black)
            .padding(.vertical, 12).padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.olive))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
}

// MARK: - Animazioni

/// Comparsa a cascata: dissolvenza + piccola salita, sfalsata per indice. Rispetta "Riduci movimento".
struct Reveal: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) var reduce
    @State private var shown = !ConfigApp.animazioni

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduce ? 0 : 14)
            .onAppear {
                guard !shown else { return }
                withAnimation(reduce ? .none : .spring(response: 0.5, dampingFraction: 0.85).delay(Double(index) * 0.05)) { shown = true }
            }
    }
}

extension View {
    func reveal(_ index: Int = 0) -> some View { modifier(Reveal(index: index)) }

    /// Cifre che scorrono (iOS 17); su iOS 16 cambiano normalmente.
    @ViewBuilder func numericTransition() -> some View {
        if #available(iOS 17.0, *) { self.contentTransition(.numericText()) } else { self }
    }
}

/// Pallino di stato; se acceso pulsa piano.
struct StatusDot: View {
    let on: Bool?
    var size: CGFloat = 9
    @Environment(\.accessibilityReduceMotion) var reduce
    @State private var pulse = false

    var color: Color { on == true ? Theme.green : (on == false ? Theme.red : .gray) }

    var body: some View {
        ZStack {
            if on == true && !reduce {
                Circle().fill(color.opacity(0.35)).frame(width: size, height: size)
                    .scaleEffect(pulse ? 2.4 : 1).opacity(pulse ? 0 : 0.8)
            }
            Circle().fill(color).frame(width: size, height: size)
                .shadow(color: color.opacity(0.7), radius: on == true ? 4 : 0)
        }
        .frame(width: size * 2.4, height: size * 2.4)
        .onAppear { withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true } }
    }
}

/// Barra di misura (CPU, RAM, disco, batteria) con riempimento animato.
struct MeterBar: View {
    let label: String
    let value: Double        // 0...1
    let text: String
    var warnAt: Double = 0.85
    var inverted = false     // per la batteria: poco = male

    var bad: Bool { inverted ? value < 1 - warnAt : value > warnAt }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption2).foregroundStyle(Theme.dim)
                Spacer()
                Text(text).font(Theme.mono(11, .semibold)).foregroundStyle(bad ? Theme.red : .white).numericTransition()
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(bad ? Theme.red : Theme.olive)
                        .frame(width: max(4, g.size.width * min(1, max(0, value))))
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: value)
                }
            }
            .frame(height: 5)
        }
    }
}

/// Anello di avanzamento animato.
struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
            Circle().trim(from: 0, to: progress)
                .stroke(Theme.olive, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.7, dampingFraction: 0.8), value: progress)
        }
    }
}

/// Radar: cerchi concentrici e un fascio che ruota piano (sfondo del countdown).
struct RadarView: View {
    @Environment(\.accessibilityReduceMotion) var reduce
    @State private var angle = 0.0

    var body: some View {
        ZStack {
            ForEach(1..<5) { i in
                Circle().stroke(Theme.olive.opacity(0.10), lineWidth: 0.8).scaleEffect(Double(i) / 4)
            }
            Rectangle().fill(Theme.olive.opacity(0.08)).frame(width: 0.8)
            Rectangle().fill(Theme.olive.opacity(0.08)).frame(height: 0.8)
            Circle()
                .fill(AngularGradient(colors: [Theme.olive.opacity(0.0), Theme.olive.opacity(0.0), Theme.olive.opacity(0.28)],
                                      center: .center))
                .rotationEffect(.degrees(angle))
        }
        .onAppear {
            guard !reduce else { return }
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { angle = 360 }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Luna fissa nella barra in alto a sinistra di ogni scheda.
struct NightToolbarButton: View {
    @EnvironmentObject var night: NightMode
    var body: some View {
        Button { withAnimation(.easeInOut(duration: 0.25)) { night.toggle() } } label: {
            Image(systemName: night.on ? "moon.fill" : "moon")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(night.on ? Night.red : Theme.olive)
                .frame(width: 32, height: 32)
        }
        .accessibilityLabel(night.on ? "Disattiva modalità notturna" : "Attiva modalità notturna")
    }
}

extension View {
    /// Aggiunge la luna in alto a sinistra.
    func nightToggle() -> some View {
        toolbar { ToolbarItem(placement: .navigationBarLeading) { NightToolbarButton() } }
    }
}

/// Avviso quando PC e server non rispondono (di solito Tailscale spento sull'iPhone).
struct TailscaleBanner: View {
    @EnvironmentObject var client: ServerClient
    @State private var prova = false

    var body: some View {
        if client.nessunoRisponde {
            VStack(alignment: .leading, spacing: 8) {
                Label("PC e server non rispondono", systemImage: "network.slash").font(.subheadline.weight(.bold))
                Text("Quasi sempre è **Tailscale spento** sull'iPhone: aprilo e accendilo. Consiglio: in Tailscale attiva \"VPN On Demand\" così si ricollega da solo quando cambi rete.")
                    .font(.caption).foregroundStyle(.white.opacity(0.85))
                HStack {
                    Link(destination: URL(string: "https://apps.apple.com/app/tailscale/id1470499037")!) {
                        Label("Apri Tailscale", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.olive).foregroundStyle(.black)
                    Button {
                        prova = true
                        Task { await client.probe(force: true); prova = false }
                    } label: { prova ? AnyView(ProgressView()) : AnyView(Label("Riprova", systemImage: "arrow.clockwise")) }
                    .buttonStyle(.bordered).tint(.white)
                }
                .font(.caption.weight(.bold))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.red.opacity(0.22), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.red.opacity(0.6), lineWidth: 1))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}


// MARK: - Comparsa animata delle sezioni

/// Le card entrano una dopo l'altra: salgono, si ingrandiscono e si accendono (indice = ordine di entrata).
/// interruttori decisi dal server (arrivano con /api/stato all'avvio): si cambiano senza ricompilare
enum ConfigApp {
    /// comparsa a cascata di schede e righe (pesante)
    static var animazioni: Bool { UserDefaults.standard.object(forKey: "cfg.animazioni") as? Bool ?? true }
    /// passaggio tra sezioni e pastiglia della barra (leggero)
    static var schede: Bool { UserDefaults.standard.object(forKey: "cfg.schede") as? Bool ?? true }
}

struct Comparsa: ViewModifier {
    let indice: Int
    @State private var visibile = !ConfigApp.animazioni
    @Environment(\.accessibilityReduceMotion) private var riduci

    func body(content: Content) -> some View {
        content
            // solo opacità e spostamento: sfocatura e zoom costano troppo da ridisegnare (scatti)
            .opacity(visibile ? 1 : 0)
            .offset(y: visibile || riduci ? 0 : 14)
            .onAppear {
                guard !visibile else { return }
                withAnimation(.easeOut(duration: 0.32).delay(riduci ? 0 : Double(min(indice, 8)) * 0.04)) { visibile = true }
            }
    }
}

extension View {
    func comparsa(_ indice: Int = 0) -> some View { modifier(Comparsa(indice: indice)) }
}
