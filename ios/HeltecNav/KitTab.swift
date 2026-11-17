import SwiftUI
import QuickLook

struct KitTab: View {
    @EnvironmentObject var log: FieldLog
    @EnvironmentObject var location: LocationService
    @StateObject private var recorder = Recorder()
    @State private var scanning = false
    @State private var camera = false
    @State private var noteOpen = false
    @State private var note = ""
    @State private var torchOn = false
    @State private var preview: URL?
    @State private var lastScan: String?
    @State private var transcribing: UUID?
    @AppStorage("raccolta.seg") private var seg = 0
    @State private var sendEntry: LogEntry?
    @State private var sendNew = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $seg) {
                    Text("Raccolta").tag(0)
                    Text("Claude").tag(1)
                    Text("Video").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal).padding(.vertical, 6)
                if seg == 1 {
                    ClaudeSection()
                } else if seg == 2 {
                    VideoTab()
                } else {
                    raccolta
                }
            }
            .navigationTitle(seg == 1 ? "Claude" : (seg == 2 ? "Video" : "Raccolta"))
            .nightToggle()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if seg == 0 {
                    Button { sendNew = true } label: { Image(systemName: "paperclip") }
                    ShareLink(item: log.report()) { Image(systemName: "square.and.arrow.up") }
                }
            }
            .sheet(isPresented: $sendNew) { SendSheet() }
            .sheet(item: $sendEntry) { e in
                SendSheet(preset: log.url(e).map { [Outgoing(url: $0, name: $0.lastPathComponent, temporary: false)] } ?? [],
                          presetNote: e.text)
            }
        }
    }

    var raccolta: some View {
            List {
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                        tool("QR / codici", "qrcode.viewfinder") { scanning = true }
                        tool("Foto", "camera") { camera = true }
                        tool(recorder.recording ? String(format: "Stop %.0fs", recorder.elapsed) : "Registra",
                             recorder.recording ? "stop.circle.fill" : "mic", tint: recorder.recording ? Theme.red : Theme.gold) {
                            toggleRecording()
                        }
                        tool("Nota", "square.and.pencil") { note = ""; noteOpen = true }
                        tool("Segna qui", "mappin.and.ellipse") {
                            log.add(.punto, "Posizione \(Date().formatted(date: .omitted, time: .shortened))", at: location.location)
                        }
                        tool(torchOn ? "Torcia ON" : "Torcia", torchOn ? "flashlight.on.fill" : "flashlight.off.fill") {
                            torchOn = Torch.toggle()
                        }
                    }
                    .buttonStyle(.plain)
                    if recorder.recording {
                        ProgressView(value: Double(recorder.level)).tint(Theme.red)
                    }
                }
                .listRowBackground(Color.clear)

                Section("Registro (\(log.entries.count))") {
                    if log.entries.isEmpty {
                        Text("Foto, audio, QR e note finiscono qui con ora e coordinate.").foregroundStyle(Theme.dim)
                    }
                    ForEach(log.entries) { e in
                        row(e)
                            .contentShape(Rectangle())
                            .onTapGesture { if let u = log.url(e) { preview = u } else { copyToClipboard(e.text) } }
                            .swipeActions {
                                Button(role: .destructive) { log.delete(e) } label: { Label("Elimina", systemImage: "trash") }
                                Button { copyToClipboard(e.text) } label: { Label("Copia", systemImage: "doc.on.doc") }
                                if log.url(e) != nil {
                                    Button { sendEntry = e } label: { Label("Claude", systemImage: "paperplane") }.tint(Theme.cyan)
                                }
                            }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .sheet(isPresented: $scanning) { scannerSheet }
            .sheet(isPresented: $camera) {
                CameraPicker { img in savePhoto(img) }.ignoresSafeArea()
            }
            .alert("Nota", isPresented: $noteOpen) {
                TextField("Testo", text: $note)
                Button("Salva") { if !note.isEmpty { log.add(.nota, note, at: location.location) } }
                Button("Annulla", role: .cancel) {}
            }
            .quickLookPreview($preview, in: log.entries.compactMap { log.url($0) })
    }

    var scannerSheet: some View {
        ZStack(alignment: .bottom) {
            CodeScanner { value, type in
                lastScan = value
                log.add(.qr, "[\(type)] \(value)", at: location.location)
            }
            .ignoresSafeArea()
            VStack(spacing: 8) {
                Text(lastScan ?? "Inquadra un QR code o un codice a barre")
                    .font(Theme.mono(14)).multilineTextAlignment(.center).textSelection(.enabled)
                HStack {
                    if let s = lastScan {
                        Button("Copia") { copyToClipboard(s) }
                        if let u = URL(string: s), u.scheme?.hasPrefix("http") == true { Link("Apri", destination: u) }
                    }
                    Button("Chiudi") { scanning = false; lastScan = nil }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
    }

    func tool(_ title: String, _ icon: String, tint: Color = Theme.gold, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 26, weight: .semibold)).foregroundStyle(tint)
                Text(title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    func row(_ e: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: e.icon).foregroundStyle(Theme.gold).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(e.text).font(.subheadline).lineLimit(4)
                HStack {
                    Text(e.date.formatted(.dateTime.day().month().hour().minute().second()))
                    if let c = e.coordinate { Text(Geo.mgrs(c)) }
                }
                .font(Theme.mono(10)).foregroundStyle(Theme.dim)
                if e.kind == .audio, let u = log.url(e) {
                    Button(transcribing == e.id ? "Trascrivo…" : "Trascrivi") { transcribe(e, u) }
                        .font(.caption).buttonStyle(.bordered).disabled(transcribing != nil)
                }
            }
        }
    }

    func toggleRecording() {
        if recorder.recording {
            if let f = recorder.stop() {
                log.add(.audio, "Registrazione \(Int(recorder.elapsed)) s", file: f, at: location.location)
            }
        } else {
            recorder.start()
        }
    }

    func savePhoto(_ img: UIImage) {
        let name = FieldLog.newFileName("jpg")
        if let d = img.jpegData(compressionQuality: 0.85) {
            try? d.write(to: FieldLog.dir.appendingPathComponent(name))
        }
        PhotoSaver.save(img)
        log.add(.foto, "Foto", file: name, at: location.location)
        let id = log.entries.first?.id
        Task {
            let t = await OCR.text(from: img)
            guard !t.isEmpty else { return }
            await MainActor.run {
                if var e = log.entries.first(where: { $0.id == id }) {
                    e.text = "Foto · testo letto: " + t.replacingOccurrences(of: "\n", with: " ")
                    log.update(e)
                }
            }
        }
    }

    func transcribe(_ e: LogEntry, _ url: URL) {
        transcribing = e.id
        Task {
            let t = await Transcriber.transcribe(url)
            await MainActor.run {
                var x = e
                x.text = "Audio: " + t
                log.update(x)
                transcribing = nil
            }
        }
    }
}
