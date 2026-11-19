import SwiftUI
import PDFKit

// MARK: - Documenti FIGT: copia sul server dell'area download, cercabile parola per parola

struct JDocFIGT: Codable, Identifiable, Hashable {
    var id: String { percorso }
    let titolo: String; let categoria: String; let file: String; let url: String; let percorso: String
    var pagine: Int? = nil; var kb: Int? = nil
}
struct JCatalogoFIGT: Codable { let aggiornato: String?; let documenti: [JDocFIGT] }
struct JRisultatoFIGT: Codable, Identifiable, Hashable {
    var id: String { "\(percorso)#\(pagina)" }
    let titolo: String; let categoria: String; let percorso: String; let pagina: Int; let estratto: String
}

struct DocumentoAperto: Identifiable {
    let id = UUID()
    let titolo: String
    let dati: Data
    let nome: String
    let pagina: Int
    let cerca: String
}

struct DocumentiFIGTView: View {
    @ObservedObject private var jsoc = JsocClient.shared
    @State private var catalogo: JCatalogoFIGT?
    @State private var cerca = ""
    @State private var risultati: [JRisultatoFIGT] = []
    @State private var cercando = false
    @State private var aperto: DocumentoAperto?
    @State private var caricando: String?
    @State private var errore: String?

    var categorie: [String] { Array(Set((catalogo?.documenti ?? []).map(\.categoria))).sorted() }

    var body: some View {
        List {
            if cerca.trimmingCharacters(in: .whitespaces).count >= 2 {
                Section {
                    if cercando { HStack { ProgressView(); Text("Cerco nei documenti…").foregroundStyle(Theme.dim) } }
                    else if risultati.isEmpty { Text("Nessun risultato per «\(cerca)».").foregroundStyle(Theme.dim) }
                    ForEach(Array(risultati.enumerated()), id: \.element.id) { i, r in
                        Button { apri(r.percorso, r.titolo, pagina: r.pagina) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(r.titolo).font(.system(size: 14.5, weight: .bold)).foregroundStyle(.white).lineLimit(2)
                                    Spacer()
                                    Text("pag. \(r.pagina)").font(Theme.mono(11, .bold)).foregroundStyle(Theme.oliveBright)
                                }
                                if !r.estratto.isEmpty { evidenziato(r.estratto).font(.system(size: 12.5)).foregroundStyle(Theme.dim).lineLimit(4) }
                                if caricando == r.percorso { ProgressView() }
                            }
                        }
                        .comparsa(i)
                    }
                } header: { Text(cercando ? "" : "\(risultati.count) risultati") }
                .listRowBackground(Theme.surface)
            } else {
                Section {
                    Text("Regolamenti, statuto, polizze, moduli e tabelle FIGT copiati sul server dell'associazione: cerca una parola (es. «delega», «infortunio», «crono», «penalità») e apri la pagina giusta.")
                        .font(.footnote).foregroundStyle(Theme.dim)
                    if let a = catalogo?.aggiornato { Text("Aggiornati dal sito FIGT il \(dataIta(String(a.prefix(10))))").font(.caption2).foregroundStyle(Theme.dim) }
                }
                .listRowBackground(Color.clear)
                ForEach(categorie, id: \.self) { c in
                    Section(c) {
                        ForEach((catalogo?.documenti ?? []).filter { $0.categoria == c }) { d in
                            Button { apri(d.percorso, d.titolo, pagina: 1) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: d.file.lowercased().hasSuffix(".pdf") ? "doc.richtext.fill" : "doc.fill").foregroundStyle(Theme.oliveBright)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(d.titolo).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
                                        Text([d.pagine.map { "\($0) pagine" }, d.kb.map { "\($0) KB" }].compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption2).foregroundStyle(Theme.dim)
                                    }
                                    Spacer()
                                    if caricando == d.percorso { ProgressView() }
                                }
                            }
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
                if catalogo != nil && (catalogo?.documenti.isEmpty ?? true) {
                    Text("I documenti non sono ancora stati copiati: il server li scarica dal sito FIGT, riprova tra qualche minuto.").foregroundStyle(Theme.dim).listRowBackground(Theme.surface)
                }
            }
            if let errore { Text(errore).foregroundStyle(Theme.red) }
        }
        .scrollContentBackground(.hidden).background(Theme.bg.ignoresSafeArea())
        .searchable(text: $cerca, prompt: "Cerca nei documenti FIGT")
        .navigationTitle("Documenti FIGT")
        .task { catalogo = try? await jsoc.get("/api/figt") }
        .refreshable { catalogo = try? await jsoc.get("/api/figt") }
        .task(id: cerca) {
            let q = cerca.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2 else { risultati = []; return }
            cercando = true
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            let e = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
            risultati = (try? await jsoc.get("/api/figt/cerca?q=\(e)")) ?? []
            cercando = false
        }
        .sheet(item: $aperto) { d in LettoreFIGT(doc: d) }
    }

    func evidenziato(_ t: String) -> Text {
        let parole = cerca.lowercased().split(separator: " ").map(String.init).filter { $0.count >= 2 }
        var out = Text("")
        for w in t.split(separator: " ", omittingEmptySubsequences: false) {
            let s = String(w)
            let trovata = parole.contains { s.lowercased().folding(options: .diacriticInsensitive, locale: nil).contains($0.folding(options: .diacriticInsensitive, locale: nil)) }
            out = out + (trovata ? Text(s + " ").bold().foregroundColor(Theme.amber) : Text(s + " "))
        }
        return out
    }

    func apri(_ percorso: String, _ titolo: String, pagina: Int) {
        caricando = percorso
        Task {
            do {
                let d = try await jsoc.scaricaDati("/api/associazione/file/" + percorsoURL(percorso))
                aperto = DocumentoAperto(titolo: titolo, dati: d, nome: String(percorso.split(separator: "/").last ?? "documento"), pagina: pagina, cerca: cerca)
                errore = nil
            } catch { errore = error.localizedDescription }
            caricando = nil
        }
    }
}

/// lettore: PDF aperto alla pagina trovata con le parole evidenziate; gli altri formati si condividono/aprono altrove
struct LettoreFIGT: View {
    let doc: DocumentoAperto
    @Environment(\.dismiss) var dismiss

    var file: URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(doc.nome)
        try? doc.dati.write(to: u)
        return u
    }
    var pdf: Bool { doc.nome.lowercased().hasSuffix(".pdf") }

    var body: some View {
        NavigationStack {
            Group {
                if pdf {
                    PDFPagina(dati: doc.dati, pagina: doc.pagina, cerca: doc.cerca).ignoresSafeArea(edges: .bottom)
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "doc.fill").font(.system(size: 54)).foregroundStyle(Theme.oliveBright)
                        Text("Questo file (\(doc.nome)) si apre con un'altra app: usa Condividi → Apri in…").multilineTextAlignment(.center).foregroundStyle(Theme.dim)
                        ShareLink(item: file) { Label("Apri o condividi", systemImage: "square.and.arrow.up") }.buttonStyle(PrimaryButtonStyle()).frame(maxWidth: 300)
                    }
                    .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.bg)
                }
            }
            .navigationTitle(doc.titolo).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { ShareLink(item: file) { Image(systemName: "square.and.arrow.up") } }
            }
        }
    }
}

struct PDFPagina: UIViewRepresentable {
    let dati: Data
    let pagina: Int
    let cerca: String

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.backgroundColor = UIColor(white: 0.12, alpha: 1)
        guard let d = PDFDocument(data: dati) else { return v }
        v.document = d
        // evidenzia le parole cercate e va alla pagina del risultato
        let parole = cerca.split(separator: " ").map(String.init).filter { $0.count >= 3 }
        var trovati: [PDFSelection] = []
        for w in parole { trovati += d.findString(w, withOptions: [.caseInsensitive, .diacriticInsensitive]) }
        trovati.forEach { $0.color = UIColor.systemYellow.withAlphaComponent(0.6) }
        v.highlightedSelections = trovati
        DispatchQueue.main.async {
            if let p = d.page(at: max(0, min(pagina - 1, d.pageCount - 1))) {
                if let primo = trovati.first(where: { $0.pages.contains(p) }) { v.go(to: primo) } else { v.go(to: p) }
            }
        }
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {}
}
