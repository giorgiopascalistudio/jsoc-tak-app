import SwiftUI
import QuickLook
import WebKit
import PDFKit
import UniformTypeIdentifiers

// MARK: - Modello

struct DocItem: Identifiable, Hashable {
    var id: String { rel }
    let url: URL
    let rel: String          // percorso nella biblioteca, es. "FF02 La Confraternita/1 Originali/OBJ 2.pdf"
    let fascicolo: String
    let group: String        // sottocartella dentro il fascicolo ("" = radice)
    var name: String { url.deletingPathExtension().lastPathComponent }
    var ext: String { url.pathExtension.lowercased() }
    var isImage: Bool { ["jpg", "jpeg", "png", "heic", "webp"].contains(ext) }
    var icon: String {
        switch ext {
        case "pdf": return "doc.richtext"
        case "html": return "globe"
        case "mp4", "mov", "m4v": return "film"
        case "m4a", "mp3", "wav", "caf", "aac": return "waveform"
        case "jpg", "jpeg", "png", "heic", "webp": return "photo"
        case "txt", "md": return "text.alignleft"
        case "gpx", "kml", "kmz": return "map"
        case "xlsx", "csv": return "tablecells"
        default: return "doc"
        }
    }
}

struct Fascicolo: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let riepilogo: URL?
    let groups: [(String, [DocItem])]
    var count: Int { groups.reduce(0) { $0 + $1.1.count } }

    var code: String { String(name.split(separator: " ").first ?? "") }
    var title: String {
        let parts = name.split(separator: " ", maxSplits: 1).map(String.init)
        if name.hasPrefix("FF"), parts.count == 2 { return parts[1] }
        if parts.count == 2, Int(parts[0]) != nil { return parts[1] }
        if name.hasPrefix("INT ") { return String(name.dropFirst(4)) }
        return name
    }
    var badge: String {
        if name.hasPrefix("FF") { return code }
        if name.hasPrefix("INT") { return "INT" }
        return ""
    }
    var icon: String {
        if name.hasPrefix("FF11") { return "dollarsign.circle" }
        if name.hasPrefix("FF12") { return "binoculars" }
        if name.hasPrefix("FF") { return "scope" }
        if name.hasPrefix("0 ") { return "info.circle" }
        if name.hasPrefix("1 ") { return "building.2" }
        if name.hasPrefix("INT") { return "eye" }
        if name == "Inviati" { return "paperplane" }
        if name == "Da smistare" { return "tray.and.arrow.down" }
        if name == DocStore.importedName { return "iphone" }
        return "folder"
    }

    static func == (a: Fascicolo, b: Fascicolo) -> Bool { a.name == b.name && a.count == b.count }
    func hash(into h: inout Hasher) { h.combine(name) }
}

// MARK: - Biblioteca

/// Biblioteca della gara sul telefono (Documents/Biblioteca), copia di quella del PC/server.
/// Si aggiorna da sola quando la macchina è raggiungibile; quello che arriva di nuovo resta segnato come "novità".
@MainActor
final class DocStore: ObservableObject {
    static let importedName = "Importati sul telefono"

    @Published private(set) var fascicoli: [Fascicolo] = []
    @Published private(set) var items: [DocItem] = []
    @Published private(set) var syncing = false
    @Published private(set) var syncStatus = ""
    @Published private(set) var progress: (Int, Int)?
    @Published private(set) var novita: [String: Date] = [:]
    @Published var indexReady = false
    private var textIndex: [String: String] = [:]
    private var remote: [String: DocIndex.File] = [:]
    private var lastSync: Date?

    nonisolated static var docsDir: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    /// Documenti dell'evento attivo: Documents/JSOC/eventi/<id>/documenti
    nonisolated static var root: URL {
        let id = UserDefaults.standard.integer(forKey: "jsoc.evento")
        let d = docsDir.appendingPathComponent("JSOC/eventi/\(id)/documenti", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private var eventoCaricato = UserDefaults.standard.integer(forKey: "jsoc.evento")
    static var importDir: URL {
        let d = docsDir.appendingPathComponent("Importati")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private static var stateDir: URL {
        let d = docsDir.appendingPathComponent("Server")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private var remoteFile: URL { Self.stateDir.appendingPathComponent("evento_\(eventoCaricato)_indice.json") }
    private var novitaFile: URL { Self.stateDir.appendingPathComponent("evento_\(eventoCaricato)_novita.json") }

    init() {
        caricaStato()
        reload()
    }

    private func caricaStato() {
        remote = [:]; novita = [:]
        if let d = try? Data(contentsOf: remoteFile), let r = try? JSONDecoder().decode([String: DocIndex.File].self, from: d) { remote = r }
        if let d = try? Data(contentsOf: novitaFile), let n = try? JSONDecoder().decode([String: Date].self, from: d) { novita = n }
        syncStatus = UserDefaults.standard.string(forKey: "bib.status.\(eventoCaricato)") ?? "Non ancora scaricati"
    }

    /// L'evento attivo è cambiato: si passa alla sua cartella.
    func cambiaEvento() {
        let id = UserDefaults.standard.integer(forKey: "jsoc.evento")
        guard id != eventoCaricato else { return }
        eventoCaricato = id
        lastSync = nil
        caricaStato()
        reload()
    }

    static func hidden(_ name: String) -> Bool {
        name.hasPrefix(".") || name.hasPrefix("_") || name.hasSuffix(".tmp")
    }
    static func assetFolder(_ name: String) -> Bool { name.lowercased().hasPrefix("img") }

    func reload() {
        let fm = FileManager.default
        var all: [DocItem] = []
        var out: [Fascicolo] = []
        let tops = ((try? fm.contentsOfDirectory(atPath: Self.root.path)) ?? [])
            .map { Self.root.appendingPathComponent($0, isDirectory: true) }
            .filter { u in
                var isDir: ObjCBool = false
                return fm.fileExists(atPath: u.path, isDirectory: &isDir) && isDir.boolValue && !Self.hidden(u.lastPathComponent)
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        for top in tops {
            let name = top.lastPathComponent
            var riepilogo: URL?
            var groups: [String: [DocItem]] = [:]
            let e = fm.enumerator(atPath: top.path)
            while let relInTop = e?.nextObject() as? String {
                let u = top.appendingPathComponent(relInTop)
                let comp = u.lastPathComponent
                var isDir: ObjCBool = false
                fm.fileExists(atPath: u.path, isDirectory: &isDir)
                if isDir.boolValue {
                    if Self.hidden(comp) || Self.assetFolder(comp) { e?.skipDescendants() }
                    continue
                }
                if Self.hidden(comp) { continue }
                if relInTop == "riepilogo.md" { riepilogo = u; continue }
                let dir = (relInTop as NSString).deletingLastPathComponent
                let item = DocItem(url: u, rel: name + "/" + relInTop, fascicolo: name, group: dir)
                groups[dir, default: []].append(item)
                all.append(item)
            }
            let sorted = groups.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { k in
                (k, groups[k]!.sorted { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending })
            }
            if riepilogo != nil || !sorted.isEmpty || ["Inviati", "Da smistare"].contains(name) {
                out.append(Fascicolo(name: name, riepilogo: riepilogo, groups: sorted))
            }
        }
        let imported = ((try? fm.contentsOfDirectory(at: Self.importDir, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { DocItem(url: $0, rel: Self.importedName + "/" + $0.lastPathComponent, fascicolo: Self.importedName, group: "") }
        if !imported.isEmpty {
            out.append(Fascicolo(name: Self.importedName, riepilogo: nil, groups: [("", imported)]))
            all += imported
        }
        fascicoli = out
        items = all
        rebuildIndex()
    }

    func fascicolo(_ name: String) -> Fascicolo? { fascicoli.first { $0.name == name } }
    var nomiFascicoli: [String] { fascicoli.map(\.name).filter { $0 != Self.importedName && $0 != "Inviati" && $0 != "Da smistare" } }

    // MARK: novità

    func isNew(_ item: DocItem) -> Bool { novita[item.rel] != nil }
    func newCount(_ f: Fascicolo) -> Int { novita.keys.filter { $0.hasPrefix(f.name + "/") }.count }
    var newItems: [DocItem] {
        items.filter { novita[$0.rel] != nil }.sorted { (novita[$0.rel] ?? .distantPast) > (novita[$1.rel] ?? .distantPast) }
    }

    func markRead(_ item: DocItem) {
        guard novita.removeValue(forKey: item.rel) != nil else { return }
        saveNovita()
    }
    func markRead(fascicolo f: Fascicolo, riepilogo: Bool) {
        if riepilogo, novita.removeValue(forKey: f.name + "/riepilogo.md") != nil { saveNovita() }
    }
    func markAllRead() { novita.removeAll(); saveNovita() }
    func riepilogoIsNew(_ f: Fascicolo) -> Bool { novita[f.name + "/riepilogo.md"] != nil }
    private func saveNovita() { try? JSONEncoder().encode(novita).write(to: novitaFile, options: .atomic) }

    // MARK: sincronizzazione

    /// Scarica dal server JSOC TAK i documenti nuovi o cambiati dell'evento attivo e toglie quelli spariti.
    func sync(_ j: JsocClient, force: Bool = false) async {
        cambiaEvento()
        guard !syncing else { return }
        if !force, let l = lastSync, Date().timeIntervalSince(l) < 60 { return }
        let ev = eventoCaricato
        guard j.collegato, ev != 0 else { setStatus("Entra con l'invito e scegli un evento"); return }
        syncing = true
        defer { syncing = false; progress = nil }
        let lista: [JFile]
        do { lista = try await j.documenti(ev) } catch {
            setStatus("Non aggiornati: server non raggiungibile"); return
        }
        guard ev == eventoCaricato else { return }
        let idx = (file: lista.map { DocIndex.File(p: $0.percorso, s: $0.dim, m: Int($0.agg)) }, ())
        let fm = FileManager.default
        var todo: [DocIndex.File] = []
        var newRemote: [String: DocIndex.File] = [:]
        for f in idx.file {
            let local = Self.root.appendingPathComponent(f.p)
            let size = (try? local.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
            if let k = remote[f.p], k == f, size == f.s { newRemote[f.p] = f; continue }
            if remote[f.p] == nil, size == f.s { newRemote[f.p] = f; continue }
            todo.append(f)
        }
        var fails = 0
        let now = Date()
        // righe di "## Novità" prima dell'aggiornamento, per avvisare solo di quelle nuove
        let primaVolta = remote.isEmpty
        var righePrima: [String: Set<String>] = [:]
        for f in todo where f.p.hasSuffix("/riepilogo.md") {
            let txt = (try? String(contentsOf: Self.root.appendingPathComponent(f.p), encoding: .utf8)) ?? ""
            righePrima[f.p] = Set(Avvisi.righeNovita(txt))
        }
        var scaricati: [String] = []
        for (i, f) in todo.enumerated() {
            progress = (i + 1, todo.count)
            do {
                let tmp = try await j.scaricaFile(ev, f.p)
                let dst = Self.root.appendingPathComponent(f.p)
                try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.removeItem(at: dst)
                try fm.moveItem(at: tmp, to: dst)
                newRemote[f.p] = f
                novita[f.p] = now
                scaricati.append(f.p)
            } catch { fails += 1 }
        }
        if !primaVolta && !scaricati.isEmpty { avvisa(scaricati, righePrima) }
        // via quello che sulla macchina non c'è più
        let wanted = Set(idx.file.map(\.p))
        var removed = 0
        let e = fm.enumerator(atPath: Self.root.path)
        var toDelete: [URL] = []
        while let rel = e?.nextObject() as? String {
            let u = Self.root.appendingPathComponent(rel)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: u.path, isDirectory: &isDir)
            if isDir.boolValue { continue }
            if !wanted.contains(rel) { toDelete.append(u); novita.removeValue(forKey: rel) }
        }
        for u in toDelete { try? fm.removeItem(at: u); removed += 1 }
        removeEmptyDirs(Self.root)
        remote = newRemote
        try? JSONEncoder().encode(remote).write(to: remoteFile, options: .atomic)
        saveNovita()
        lastSync = Date()
        let hh = Date().formatted(date: .omitted, time: .shortened)
        var s = "Aggiornati alle \(hh)"
        if !todo.isEmpty { s += " · \(todo.count - fails) nuovi" }
        if removed > 0 { s += " · \(removed) tolti" }
        if fails > 0 { s += " · \(fails) non scaricati" }
        setStatus(s)
        if !todo.isEmpty || removed > 0 { reload() }
    }

    /// Notifica: righe nuove dei riepilogo.md, altrimenti quanti documenti nuovi per fascicolo.
    private func avvisa(_ scaricati: [String], _ righePrima: [String: Set<String>]) {
        var novitaPerFasc: [(String, [String])] = []
        var altri: [String: Int] = [:]
        for p in scaricati where p.hasSuffix("/riepilogo.md") {
            let txt = (try? String(contentsOf: Self.root.appendingPathComponent(p), encoding: .utf8)) ?? ""
            let vecchie = righePrima[p] ?? []
            let nuove = Avvisi.righeNovita(txt).filter { !vecchie.contains($0) }
            if !nuove.isEmpty { novitaPerFasc.append((String(p.split(separator: "/").first ?? ""), nuove)) }
        }
        let conNovita = Set(novitaPerFasc.map(\.0))
        for p in scaricati where !p.hasSuffix("/riepilogo.md") {
            let parti = p.split(separator: "/").map(String.init)
            guard let fasc = parti.first, !conNovita.contains(fasc), !parti.contains(where: { Self.hidden($0) }) else { continue }
            altri[fasc, default: 0] += 1
        }
        Avvisi.shared.notifica(novita: novitaPerFasc, altri: altri)
    }

    private func removeEmptyDirs(_ dir: URL) {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] {
            let d = dir.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: d.path, isDirectory: &isDir), isDir.boolValue else { continue }
            removeEmptyDirs(d)
            if ((try? fm.contentsOfDirectory(atPath: d.path)) ?? ["x"]).isEmpty { try? fm.removeItem(at: d) }
        }
    }

    private func setStatus(_ s: String) {
        syncStatus = s
        UserDefaults.standard.set(s, forKey: "bib.status.\(eventoCaricato)")
    }

    // MARK: file importati sul telefono

    func importFile(_ url: URL) {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        let dest = Self.importDir.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: url, to: dest)
        reload()
    }

    func delete(_ item: DocItem) {
        guard item.fascicolo == Self.importedName else { return }
        try? FileManager.default.removeItem(at: item.url)
        reload()
    }

    // MARK: ricerca nel testo

    private func rebuildIndex() {
        let list = items + fascicoli.compactMap { f in
            f.riepilogo.map { DocItem(url: $0, rel: f.name + "/riepilogo.md", fascicolo: f.name, group: "") }
        }
        indexReady = false
        Task.detached(priority: .utility) {
            var idx: [String: String] = [:]
            for item in list {
                switch item.ext {
                case "pdf": idx[item.rel] = PDFDocument(url: item.url)?.string ?? ""
                case "txt", "md", "csv", "gpx", "kml": idx[item.rel] = (try? String(contentsOf: item.url)) ?? ""
                case "html":
                    let h = (try? String(contentsOf: item.url)) ?? ""
                    idx[item.rel] = h.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                default: break
                }
            }
            await MainActor.run {
                self.textIndex = idx
                self.searchItems = list
                self.indexReady = true
            }
        }
    }
    private var searchItems: [DocItem] = []

    /// Righe dei documenti che contengono la parola cercata.
    func search(_ q: String) -> [(DocItem, [String])] {
        let query = q.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else { return [] }
        return searchItems.compactMap { item in
            guard let text = textIndex[item.rel] else { return nil }
            let lines = text.components(separatedBy: .newlines)
                .filter { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
                .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "**", with: "") }
            return lines.isEmpty ? nil : (item, Array(lines.prefix(4)))
        }
    }
}

// MARK: - Schede

struct DocsTab: View {
    @EnvironmentObject var docs: DocStore
    @EnvironmentObject var client: ServerClient
    @State private var query = ""
    @State private var importing = false
    @State private var opening: DocItem?
    @State private var path: [String] = UserDefaults.standard.string(forKey: "debug.fascicolo").map { [$0] } ?? []
    @State private var bacheca = UserDefaults.standard.bool(forKey: "debug.bacheca")

    /// Tocco su una notifica: apre il fascicolo indicato.
    private func apriDaNotifica() {
        let d = UserDefaults.standard
        guard let f = d.string(forKey: "docs.apri") else { return }
        d.removeObject(forKey: "docs.apri")
        if docs.fascicolo(f) != nil { path = [f] }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    HStack(spacing: 10) {
                        if docs.syncing {
                            ProgressView()
                            if let p = docs.progress { Text("Scarico \(p.0) di \(p.1)…").font(.caption) }
                            else { Text("Controllo novità…").font(.caption) }
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Theme.gold)
                            Text(docs.syncStatus).font(.caption).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        Button("Aggiorna") { Task { await docs.sync(JsocClient.shared, force: true) } }
                            .font(.caption.weight(.semibold)).disabled(docs.syncing)
                    }
                }
                if !query.isEmpty {
                    Section("Nel testo") {
                        let hits = docs.search(query)
                        if hits.isEmpty { Text(docs.indexReady ? "Nessun risultato" : "Indicizzazione…").foregroundStyle(Theme.dim) }
                        ForEach(hits, id: \.0.id) { hit in
                            Button { open(hit.0) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(hit.0.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                    Text(hit.0.fascicolo).font(.caption2).foregroundStyle(Theme.gold)
                                    ForEach(hit.1, id: \.self) { l in
                                        Text(l).font(.caption).foregroundStyle(Theme.dim).lineLimit(2)
                                    }
                                }
                            }
                        }
                    }
                }
                let nuovi = docs.newItems
                if query.isEmpty && !nuovi.isEmpty {
                    Section {
                        ForEach(nuovi.prefix(12)) { item in
                            Button { open(item) } label: {
                                HStack {
                                    Image(systemName: item.icon).foregroundStyle(Theme.cyan).frame(width: 22)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.name).foregroundStyle(.white).lineLimit(2)
                                        Text(item.fascicolo).font(.caption2).foregroundStyle(Theme.gold)
                                    }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("Novità (\(nuovi.count))")
                            Spacer()
                            Button("Segna tutto letto") { docs.markAllRead() }.font(.caption2)
                        }
                    }
                }
                Section {
                    NavigationLink { BachecaView() } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8).fill(Theme.olive.opacity(0.18)).frame(width: 44, height: 44)
                                Image(systemName: "point.3.connected.trianglepath.dotted").foregroundStyle(Theme.olive)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Bacheca indizi").font(.headline).foregroundStyle(.white)
                                Text("Persone, famiglie, luoghi, prove e codici collegati").font(.caption).foregroundStyle(Theme.dim)
                            }
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
                Section("Fascicoli") {
                    ForEach(docs.fascicoli.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { f in
                        NavigationLink(value: f.name) { FascicoloRow(f: f) }
                            .listRowBackground(Theme.surface)
                    }
                }
            }
            .searchable(text: $query, prompt: "Cerca nei nomi e nel testo")
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: docs.fascicoli)
            .navigationTitle("Documenti")
            .nightToggle()
            .navigationDestination(for: String.self) { name in FascicoloView(name: name) }
            .navigationDestination(isPresented: $bacheca) { BachecaView() }
            .toolbar {
                Button { importing = true } label: { Image(systemName: "square.and.arrow.down") }
            }
            .refreshable { await docs.sync(JsocClient.shared, force: true) }
            .task { await docs.sync(JsocClient.shared) }
            .onAppear { apriDaNotifica() }
            .onReceive(NotificationCenter.default.publisher(for: .openDocs)) { _ in
                DispatchQueue.main.async { apriDaNotifica() }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { r in
                if case .success(let urls) = r { urls.forEach { docs.importFile($0) } }
            }
            .docOpener($opening)
        }
    }

    func open(_ item: DocItem) {
        docs.markRead(item)
        opening = item
    }
}

struct FascicoloRow: View {
    @EnvironmentObject var docs: DocStore
    let f: Fascicolo

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Theme.card).frame(width: 44, height: 44)
                if f.badge.isEmpty {
                    Image(systemName: f.icon).foregroundStyle(Theme.gold)
                } else {
                    Text(f.badge).font(Theme.mono(12, .bold)).foregroundStyle(Theme.gold)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(f.title).font(.headline).foregroundStyle(.white)
                Text(subtitle).font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
            }
            Spacer()
            let n = docs.newCount(f)
            if n > 0 {
                Text("\(n)").font(.caption2.weight(.bold)).padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Theme.cyan, in: Capsule()).foregroundStyle(.black)
            }
        }
    }

    var subtitle: String {
        if let r = f.riepilogo, let text = try? String(contentsOf: r) {
            let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            if lines.count > 1, !lines[1].hasPrefix("#") {
                return lines[1].replacingOccurrences(of: "**", with: "")
            }
        }
        return "\(f.count) file"
    }
}

struct FascicoloView: View {
    @EnvironmentObject var docs: DocStore
    let name: String
    @State private var opening: DocItem?
    @State private var sending = false

    var body: some View {
        Group {
            if let f = docs.fascicolo(name) {
                List {
                    if let r = f.riepilogo {
                        Section {
                            MarkdownView(url: r).listRowBackground(Theme.surface)
                        } header: {
                            HStack {
                                Text("Riepilogo")
                                if docs.riepilogoIsNew(f) { Text("AGGIORNATO").foregroundStyle(Theme.cyan) }
                            }
                        }
                    }
                    ForEach(f.groups, id: \.0) { g in
                        Section(g.0.isEmpty ? "File" : g.0.replacingOccurrences(of: "/", with: " › ")) {
                            ForEach(g.1) { item in
                                Button { docs.markRead(item); opening = item } label: {
                                    HStack {
                                        Label(item.name, systemImage: item.icon).foregroundStyle(.white)
                                        Spacer()
                                        if docs.isNew(item) { Circle().fill(Theme.cyan).frame(width: 8, height: 8) }
                                    }
                                }
                                .swipeActions {
                                    if item.fascicolo == DocStore.importedName {
                                        Button(role: .destructive) { docs.delete(item) } label: { Label("Elimina", systemImage: "trash") }
                                    }
                                    ShareLink(item: item.url) { Label("Condividi", systemImage: "square.and.arrow.up") }
                                }
                            }
                        }
                    }
                    if f.count == 0 && f.riepilogo == nil {
                        Text("Vuoto per ora.").foregroundStyle(Theme.dim)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Theme.bg.ignoresSafeArea())
                .navigationTitle(f.badge.isEmpty ? f.title : "\(f.badge) \(f.title)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    Button { sending = true } label: { Image(systemName: "paperclip") }
                }
                .onDisappear { docs.markRead(fascicolo: f, riepilogo: true) }
                .sheet(isPresented: $sending) { SendSheet(fascicolo: f.name) }
                .docOpener($opening)
            } else {
                Text("Fascicolo non più presente.").foregroundStyle(Theme.dim)
            }
        }
    }
}

// MARK: - Riepilogo (Markdown semplice: titoli, elenchi, citazioni, grassetto)

struct MarkdownView: View {
    let url: URL

    var body: some View {
        let blocks = Self.parse((try? String(contentsOf: url)) ?? "")
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                block(b)
            }
        }
        .padding(.vertical, 4)
        .textSelection(.enabled)
    }

    enum Block { case h1(String), h2(String), h3(String), bullet(String), number(String, String), quote(String), table(String), text(String) }

    static func parse(_ s: String) -> [Block] {
        var out: [Block] = []
        var pendingH2: Block?
        for raw in s.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            var b: Block
            if line.hasPrefix("### ") { b = .h3(String(line.dropFirst(4))) }
            else if line.hasPrefix("## ") {
                // le sezioni vuote non si mostrano
                pendingH2 = .h2(String(line.dropFirst(3))); continue
            }
            else if line.hasPrefix("# ") { b = .h1(String(line.dropFirst(2))) }
            else if line.hasPrefix("- ") || line.hasPrefix("* ") { b = .bullet(String(line.dropFirst(2))) }
            else if let m = line.range(of: #"^\d+\. "#, options: .regularExpression) {
                b = .number(String(line[m]).trimmingCharacters(in: .whitespaces), String(line[m.upperBound...]))
            }
            else if line.hasPrefix(">") { b = .quote(line.drop(while: { $0 == ">" || $0 == " " }).description) }
            else if line.hasPrefix("|") {
                if line.replacingOccurrences(of: "|", with: "").allSatisfy({ "-: ".contains($0) }) { continue }
                b = .table(line.trimmingCharacters(in: CharacterSet(charactersIn: "| ")).replacingOccurrences(of: " | ", with: "  ·  "))
            }
            else { b = .text(line) }
            if let h = pendingH2 { out.append(h); pendingH2 = nil }
            out.append(b)
        }
        return out
    }

    @ViewBuilder
    func block(_ b: Block) -> some View {
        switch b {
        case .h1(let t): Text(md(t)).font(.title3.weight(.bold)).foregroundStyle(Theme.gold)
        case .h2(let t): Text(t.uppercased()).font(.caption.weight(.heavy)).foregroundStyle(Theme.gold).padding(.top, 8)
        case .h3(let t): Text(md(t)).font(.subheadline.weight(.bold)).padding(.top, 4)
        case .bullet(let t):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(Theme.gold)
                Text(md(t)).font(.subheadline)
            }
        case .number(let n, let t):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(n).font(Theme.mono(13, .bold)).foregroundStyle(Theme.gold)
                Text(md(t)).font(.subheadline)
            }
        case .quote(let t):
            Text(md(t)).font(.subheadline.italic()).foregroundStyle(Theme.dim)
                .padding(.leading, 10).overlay(alignment: .leading) { Rectangle().fill(Theme.gold.opacity(0.5)).frame(width: 2) }
        case .table(let t): Text(md(t)).font(Theme.mono(11))
        case .text(let t): Text(md(t)).font(.subheadline)
        }
    }

    func md(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

// MARK: - Apertura dei file (giorno: Quick Look; notte: visore rosso)

extension View {
    func docOpener(_ item: Binding<DocItem?>) -> some View { modifier(DocOpener(item: item)) }
}

struct DocOpener: ViewModifier {
    @Binding var item: DocItem?
    @EnvironmentObject var night: NightMode
    @State private var quick: URL?
    @State private var nightDoc: DocItem?
    @State private var web: DocItem?

    func body(content: Content) -> some View {
        content
            .onChange(of: item) { i in
                guard let i else { return }
                item = nil
                if i.ext == "html" { web = i }
                else if night.on && (i.ext == "pdf" || i.isImage) { nightDoc = i }
                else { quick = i.url }
            }
            .quickLookPreview($quick)
            .fullScreenCover(item: $nightDoc) { d in NightDocView(url: d.url) }
            .fullScreenCover(item: $web) { d in
                NavigationStack {
                    WebView(url: d.url, night: night.on)
                        .ignoresSafeArea(edges: .bottom)
                        .navigationTitle(d.name)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { web = nil } } }
                }
            }
    }
}

struct WebView: UIViewRepresentable {
    let url: URL
    var night = false

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.addUserScript(Night.userScript())
        let w = WKWebView(frame: .zero, configuration: cfg)
        w.isOpaque = false
        w.backgroundColor = .black
        w.allowsBackForwardNavigationGestures = true
        w.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return w
    }

    func updateUIView(_ w: WKWebView, context: Context) { Night.apply(to: w, on: night) }
}
