import SwiftUI

/// Guida dell'app: ogni schermata importante ha la sua mini-guida (2-3 schede), che compare solo la prima volta che
/// la apri. «Non mostrare più la guida» le spegne tutte; da Strumenti/Profilo si possono rimettere.
/// I testi sono gli stessi di Android: guida/guida.json → GuidaTesti.swift (node guida/genera.js).
@MainActor
final class GuidaApp: ObservableObject {
    static let shared = GuidaApp()
    @Published var aperta: String?
    private var coda: [String] = []
    private var segnate: Set<String> = []
    private let d = UserDefaults.standard

    var mai: Bool { d.bool(forKey: "guida.mai") }

    /// Da chiamare nel `body` di una schermata (`let _ = GuidaApp.segna("cassa")`): non scrive lo stato
    /// mentre si disegna (rimanda al giro dopo) e lo fa una volta sola per schermata.
    nonisolated static func segna(_ chiave: String) {
        DispatchQueue.main.async { GuidaApp.shared.entra(chiave) }
    }

    func entra(_ k: String) {
        guard !Anteprima.attiva, !segnate.contains(k) else { return }
        segnate.insert(k)
        guard !mai, !d.bool(forKey: "guida.vista." + k), GuidaTesti.testi[k] != nil else { return }
        if aperta == nil { aperta = k } else if aperta != k, !coda.contains(k) { coda.append(k) }
    }

    func rivedi(_ k: String) { aperta = k }

    /// tutte le guide come la prima volta
    func ricomincia() {
        d.set(false, forKey: "guida.mai")
        for k in GuidaTesti.testi.keys { d.removeObject(forKey: "guida.vista." + k) }
        segnate.removeAll()
    }

    func chiudi(_ k: String, mai nonPiu: Bool) {
        d.set(true, forKey: "guida.vista." + k)
        if nonPiu { d.set(true, forKey: "guida.mai"); coda.removeAll(); aperta = nil; return }
        aperta = coda.isEmpty ? nil : coda.removeFirst()
    }
}

/// Le schede della guida, sopra tutta l'app.
struct GuidaSopra: View {
    @ObservedObject private var g = GuidaApp.shared
    var body: some View {
        if let k = g.aperta, let passi = GuidaTesti.testi[k] {
            SchedeGuida(chiave: k, passi: passi).id(k)
        }
    }
}

private struct SchedeGuida: View {
    let chiave: String
    let passi: [(String, String)]
    @State private var i = 0
    @State private var nonPiu = GuidaApp.shared.mai

    var body: some View {
        let p = passi[min(i, passi.count - 1)]
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea().onTapGesture {}
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("GUIDA · \(i + 1)/\(passi.count)").font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(1.4)
                        .foregroundStyle(Theme.oliveBright)
                    Spacer()
                    Button("Salta") { GuidaApp.shared.chiudi(chiave, mai: nonPiu) }
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.dim)
                }
                Text(p.0).font(.system(size: 21, weight: .black)).foregroundStyle(Theme.testo).padding(.top, 10)
                Text(p.1).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.testo2)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                HStack(spacing: 6) {
                    ForEach(0..<passi.count, id: \.self) { k in
                        Capsule().fill(k == i ? Theme.olive : Theme.stroke).frame(width: k == i ? 18 : 7, height: 7)
                    }
                }
                .frame(maxWidth: .infinity).padding(.top, 16)
                Button { nonPiu.toggle() } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6).fill(nonPiu ? Theme.olive : .clear)
                            RoundedRectangle(cornerRadius: 6).stroke(nonPiu ? Theme.olive : Theme.dim, lineWidth: 2)
                            if nonPiu { Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.barra) }
                        }
                        .frame(width: 22, height: 22)
                        Text("Non mostrare più la guida").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.testo)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain).padding(.top, 16)
                HStack(spacing: 10) {
                    if i > 0 {
                        Button { i -= 1 } label: { tasto("Indietro", pieno: false) }.buttonStyle(.plain)
                    }
                    Button {
                        if i == passi.count - 1 { GuidaApp.shared.chiudi(chiave, mai: nonPiu) } else { i += 1 }
                    } label: { tasto(i == passi.count - 1 ? "Ho capito" : "Avanti", pieno: true) }.buttonStyle(.plain)
                }
                .padding(.top, 12)
            }
            .padding(20)
            .frame(maxWidth: 440)
            .background(RoundedRectangle(cornerRadius: 22).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.olive.opacity(0.5), lineWidth: 1))
            .padding(20)
        }
        .transition(.opacity)
    }

    private func tasto(_ t: String, pieno: Bool) -> some View {
        Text(t).font(.system(size: 15, weight: .heavy)).foregroundStyle(pieno ? Theme.barra : Theme.testo)
            .frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(RoundedRectangle(cornerRadius: 14).fill(pieno ? Theme.olive : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(pieno ? Theme.olive : Theme.stroke, lineWidth: 1))
    }
}

/// Tasti per rivedere le guide (Strumenti e Profilo).
struct RivediGuida: View {
    var body: some View {
        VStack(spacing: 8) {
            Button { GuidaApp.shared.ricomincia(); GuidaApp.shared.rivedi("strumenti") } label: {
                Label("Mostra di nuovo la guida in tutte le schermate", systemImage: "questionmark.circle")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.oliveBright)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
            }
            .buttonStyle(.plain)
        }
    }
}
