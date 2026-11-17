import Foundation

/// Terminale del server: ogni comando è un "lavoro" sul server che continua anche se il telefono perde la rete.
@MainActor
final class TerminalModel: ObservableObject {
    struct Block: Identifiable, Codable {
        var id = UUID()
        let cmd: String
        let dir: String
        var output: [String] = []
        var exitCode: Int?
        var running = true
    }

    @Published var blocks: [Block] = []
    @Published var cwd = "~"
    @Published var error: String?
    @Published var target: Target = .server
    private var job: String?
    private var jobTarget: Target = .server
    private var task: Task<Void, Never>?

    var running: Bool { job != nil }

    static let quick: [(String, String)] = [
        ("Servizi TAK", "systemctl --no-pager -l status opentakserver eud_handler_ssl cot_parser tak-bot | grep -E '●|Active'"),
        ("Log TAK", "tail -n 40 ~/ots/logs/eud_handler_ssl.log"),
        ("Log bot HQI", "journalctl -u tak-bot -n 40 --no-pager"),
        ("Tailscale", "tailscale status; tailscale funnel status"),
        ("Disco/RAM", "df -h / && free -h"),
        ("Riavvia TAK", "sudo systemctl restart opentakserver eud_handler_ssl eud_handler cot_parser && echo riavviati"),
        ("Riavvia bot", "sudo systemctl restart tak-bot && echo riavviato"),
    ]

    func run(_ cmd: String, client: ServerClient) {
        let c = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty, job == nil else { return }
        if c == "clear" { blocks.removeAll(); return }
        blocks.append(Block(cmd: c, dir: cwd))
        if blocks.count > 60 { blocks.removeFirst(blocks.count - 60) }
        error = nil
        let t = target
        jobTarget = t
        task = Task {
            do {
                let j = try await client.runCommand(c, on: t)
                job = j
                var from = 0
                while !Task.isCancelled {
                    let p: JobPage<String>
                    do { p = try await client.page(j, from: from, on: t) } catch {
                        // rete persa: il comando continua sul server, riprovo
                        self.error = error.localizedDescription
                        try? await Task.sleep(nanoseconds: 2_000_000_000); continue
                    }
                    self.error = nil
                    from += p.righe.count
                    if !blocks.isEmpty { blocks[blocks.count - 1].output += p.righe }
                    cwd = p.cartella.replacingOccurrences(of: "/home/giorgio", with: "~")
                        .replacingOccurrences(of: "C:\\Users\\redde", with: "~")
                        .replacingOccurrences(of: "/c/Users/redde", with: "~")
                    if p.fine {
                        if !blocks.isEmpty { blocks[blocks.count - 1].exitCode = p.codice; blocks[blocks.count - 1].running = false }
                        break
                    }
                    try? await Task.sleep(nanoseconds: 600_000_000)
                }
            } catch {
                self.error = error.localizedDescription
                if !blocks.isEmpty { blocks[blocks.count - 1].running = false }
            }
            job = nil
        }
    }

    func stop(client: ServerClient) {
        guard let j = job else { return }
        let t = jobTarget
        Task { await client.stop(j, on: t) }
    }
}

/// Claude Code sul PC (o sul server se il PC è spento): stessa memoria, comandato dal telefono.
/// Ogni conversazione appartiene a una macchina: se il PC non risponde si apre una conversazione sul server.
@MainActor
final class ClaudeModel: ObservableObject {
    struct Item: Identifiable, Codable, Hashable {
        var id = UUID()
        let kind: String   // tu | file | testo | strumento | esito | errore | info
        let text: String
    }

    @Published var items: [Item] = []
    @Published var session: String?
    @Published var target: Target = .pc
    @Published var running = false
    @Published var netError: String?
    private var job: String?
    private var from = 0

    private let file: URL = {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Server")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("claude.json")
    }()

    private struct Saved: Codable { var items: [Item]; var session: String?; var job: String?; var from: Int; var target: Target? }

    init() {
        if let d = try? Data(contentsOf: file), let s = try? JSONDecoder().decode(Saved.self, from: d) {
            items = s.items; session = s.session; job = s.job; from = s.from; target = s.target ?? .server
        }
    }

    private func save() {
        let s = Saved(items: Array(items.suffix(400)), session: session, job: job, from: from, target: target)
        try? JSONEncoder().encode(s).write(to: file, options: .atomic)
    }

    /// Se l'app era stata chiusa durante una risposta, riprende a leggerla.
    func resumeIfNeeded(client: ServerClient) {
        if job != nil && !running { follow(client: client) }
    }

    /// Sceglie la macchina: se la conversazione è su una macchina che ora non risponde, ne apre una nuova sull'altra.
    private func pickTarget(_ client: ServerClient) {
        let b = client.brain
        guard b != target else { return }
        if session != nil {
            items.append(Item(kind: "info", text: "\(target.label) non risponde: continuo su \(b.label) (nuova conversazione)."))
            session = nil
        }
        target = b
    }

    func send(_ prompt: String, client: ServerClient) {
        let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty, !running else { return }
        items.append(Item(kind: "tu", text: p))
        running = true
        save()
        Task {
            await client.probe()
            pickTarget(client)
            do {
                job = try await client.askClaude(p, session: session, on: target)
                from = 0
                save()
                follow(client: client)
            } catch {
                items.append(Item(kind: "errore", text: error.localizedDescription))
                running = false
                save()
            }
        }
    }

    /// Manda uno o più file (foto, video, audio, PDF…). Un file solo: l'analisi parte sul server con il suo
    /// prompt. Più file: si caricano tutti e poi si chiede a Claude di guardarli insieme.
    func sendFiles(_ files: [(URL, String)], fascicolo: String?, note: String, analyze: Bool, client: ServerClient) async -> String? {
        guard !running else { return "Claude sta già lavorando: aspetta la fine o fermalo." }
        guard !files.isEmpty else { return nil }
        let total = files.reduce(Int64(0)) { $0 + Int64((try? $1.0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        let names = files.map(\.1).joined(separator: ", ")
        items.append(Item(kind: "file", text: "\(names) · \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
                          + (fascicolo.map { " · \($0)" } ?? "") + (note.isEmpty ? "" : "\n\(note)")))
        running = true
        save()
        await client.probe()
        pickTarget(client)
        let single = files.count == 1
        var paths: [String] = []
        do {
            for (url, name) in files {
                let r = try await client.send(file: url, name: name, fascicolo: fascicolo, note: note,
                                              analyze: analyze && single, session: session, on: target)
                paths.append(r.percorso)
                if let j = r.job { job = j; from = 0 }
            }
            items.append(Item(kind: "info", text: "salvat\(single ? "o" : "i") su \(target.label): " + paths.joined(separator: ", ")))
            if job != nil {
                save(); follow(client: client)
            } else if analyze && !single {
                let prompt = """
                [Dall'app Re Mida, in gara] Ti ho mandato \(paths.count) file insieme, nella biblioteca Re Mida \
                (sul PC Desktop\\RE_MIDA_BIBLIOTECA, sul server ~/ots/remida_docs): \(paths.joined(separator: "; ")).
                Fascicolo: \(fascicolo ?? "nessuno"). Nota: \(note.isEmpty ? "nessuna" : note).
                Analizzali insieme seguendo _ISTRUZIONI.md della biblioteca: collega gli indizi, archivia, aggiorna i \
                riepiloghi, niente TAK senza conferma. Rispondi breve, leggo dal telefono sul campo.
                """
                job = try await client.askClaude(prompt, session: session, on: target)
                from = 0
                save(); follow(client: client)
            } else {
                running = false; save()
                NotificationCenter.default.post(name: .claudeFinished, object: nil)
            }
            return nil
        } catch {
            items.append(Item(kind: "errore", text: "Invio non riuscito: \(error.localizedDescription)"))
            running = false
            save()
            return error.localizedDescription
        }
    }

    private func follow(client: ServerClient) {
        guard let j = job else { return }
        running = true
        let t = target
        Task {
            while true {
                let p: JobPage<ClaudeEvent>
                do { p = try await client.page(j, from: from, on: t) } catch ServerFailure.http(404, _) {
                    items.append(Item(kind: "info", text: "Risposta non più disponibile (\(t.label) riavviato?)."))
                    break
                } catch {
                    netError = error.localizedDescription
                    try? await Task.sleep(nanoseconds: 3_000_000_000); continue
                }
                netError = nil
                from += p.righe.count
                for e in p.righe { apply(e) }
                save()
                if p.fine { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            job = nil
            running = false
            save()
            NotificationCenter.default.post(name: .claudeFinished, object: nil)
        }
    }

    private func apply(_ e: ClaudeEvent) {
        switch e.t {
        case "sessione": session = e.s
        case "testo": items.append(Item(kind: "testo", text: e.s))
        case "strumento": items.append(Item(kind: "strumento", text: e.s))
        case "esito": items.append(Item(kind: e.errore == true ? "errore" : "esito", text: e.s))
        case "fine":
            if let s = e.sessione, !s.isEmpty { session = s }
            if e.errore == true { items.append(Item(kind: "errore", text: e.s.isEmpty ? "Claude si è fermato con un errore." : e.s)) }
            else { items.append(Item(kind: "info", text: "fatto in \(e.secondi ?? 0) s")) }
        default: break
        }
    }

    func stop(client: ServerClient) {
        guard let j = job else { return }
        let t = target
        Task { await client.stop(j, on: t) }
    }

    func newConversation(client: ServerClient) {
        guard !running else { return }
        items.removeAll(); session = nil; target = client.brain; save()
    }

    func open(_ s: ClaudeSession, on t: Target) {
        guard !running else { return }
        items = [Item(kind: "info", text: "Ripresa conversazione su \(t.label): \(s.titolo)")]
        session = s.id
        target = t
        save()
    }
}
