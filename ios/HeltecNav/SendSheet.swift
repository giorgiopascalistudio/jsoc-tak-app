import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation

extension Notification.Name {
    /// Chiede all'app di aprire la chat con Claude (dopo un invio).
    static let openClaude = Notification.Name("remida.openClaude")
    /// Claude ha finito un lavoro: conviene riaggiornare la biblioteca.
    static let claudeFinished = Notification.Name("remida.claudeFinished")
}

/// Un file pronto da mandare: copia locale in Documents/Server/Uscita (o un file della Raccolta).
struct Outgoing: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let temporary: Bool
    var icon: String { DocItem(url: url, rel: name, fascicolo: "", group: "").icon }
}

/// Manda foto, video, audio o documenti al PC (o al server se il PC è spento) perché Claude li analizzi.
struct SendSheet: View {
    var fascicolo: String? = nil
    var preset: [Outgoing] = []
    var presetNote = ""

    @EnvironmentObject var client: ServerClient
    @EnvironmentObject var claude: ClaudeModel
    @EnvironmentObject var docs: DocStore
    @EnvironmentObject var log: FieldLog
    @EnvironmentObject var location: LocationService
    @Environment(\.dismiss) var dismiss

    @State private var files: [Outgoing] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var camera = false
    @StateObject private var recorder = Recorder()
    @State private var target = ""
    @State private var note = ""
    @State private var analyze = true
    @State private var busy = false
    @State private var loading = false
    @State private var error: String?

    static var outbox: URL {
        let d = DocStore.docsDir.appendingPathComponent("Server/Uscita")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(files) { f in
                        Label(f.name, systemImage: f.icon).lineLimit(2)
                    }
                    .onDelete { idx in
                        for i in idx where files[i].temporary { try? FileManager.default.removeItem(at: files[i].url) }
                        files.remove(atOffsets: idx)
                    }
                    if loading { HStack { ProgressView(); Text("Preparo…").font(.caption) } }
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .any(of: [.images, .videos])) {
                        Label("Foto o video dalla libreria", systemImage: "photo.on.rectangle")
                    }
                    Button { camera = true } label: { Label("Scatta foto o video", systemImage: "camera") }
                    Button { importing = true } label: { Label("File (PDF, audio, documenti…)", systemImage: "folder") }
                    Button { toggleRecording() } label: {
                        Label(recorder.recording ? String(format: "Ferma registrazione (%.0f s)", recorder.elapsed) : "Registra audio",
                              systemImage: recorder.recording ? "stop.circle.fill" : "mic")
                            .foregroundStyle(recorder.recording ? Theme.red : Theme.gold)
                    }
                } header: { Text("Cosa mandi") }

                Section("Riguarda") {
                    Picker("Fascicolo", selection: $target) {
                        Text("Non so / generale").tag("")
                        ForEach(docs.nomiFascicoli, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section {
                    TextField("Cosa è, dove l'hai trovato, cosa ti serve", text: $note, axis: .vertical).lineLimit(2...6)
                    Toggle("Fai analizzare a Claude", isOn: $analyze)
                } header: { Text("Nota") } footer: {
                    Text(client.brain == .pc ? "Va al PC di casa." : "Il PC non risponde: va al server.")
                        + Text(" Il file finisce nella biblioteca e Claude aggiorna il fascicolo; per TAK chiede conferma.")
                }
                if let error { Text(error).foregroundStyle(Theme.red).font(.footnote) }
            }
            .navigationTitle("Manda a Claude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { cleanup(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else {
                        Button("Invia") { Task { await send() } }.disabled(files.isEmpty || recorder.recording || loading)
                    }
                }
            }
            .onAppear {
                if files.isEmpty { files = preset }
                if note.isEmpty { note = presetNote }
                target = fascicolo ?? ""
            }
            .task { await client.probe() }
            .onChange(of: photoItems) { items in Task { await load(items) } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { r in
                if case .success(let urls) = r { for u in urls { addCopy(of: u) } }
            }
            .fullScreenCover(isPresented: $camera) {
                MediaCapture { image, movie in
                    if let image { addPhoto(image) }
                    if let movie { addCopy(of: movie, keepInRaccolta: true) }
                }
                .ignoresSafeArea()
            }
            .interactiveDismissDisabled(busy)
        }
    }

    // MARK: preparazione

    private func unique(_ name: String) -> URL {
        Self.outbox.appendingPathComponent(String(UUID().uuidString.prefix(6)) + "-" + name)
    }

    private func addCopy(of url: URL, keepInRaccolta: Bool = false) {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        let name = keepInRaccolta ? FieldLog.newFileName(url.pathExtension.isEmpty ? "mov" : url.pathExtension) : url.lastPathComponent
        if keepInRaccolta {
            let dst = FieldLog.dir.appendingPathComponent(name)
            try? FileManager.default.copyItem(at: url, to: dst)
            log.add(.foto, "Video", file: name, at: location.location)
            files.append(Outgoing(url: dst, name: name, temporary: false))
        } else {
            let dst = unique(name)
            try? FileManager.default.copyItem(at: url, to: dst)
            files.append(Outgoing(url: dst, name: name, temporary: true))
        }
    }

    private func addPhoto(_ img: UIImage) {
        let name = FieldLog.newFileName("jpg")
        let dst = FieldLog.dir.appendingPathComponent(name)
        try? img.jpegData(compressionQuality: 0.9)?.write(to: dst)
        log.add(.foto, "Foto per Claude", file: name, at: location.location)
        files.append(Outgoing(url: dst, name: name, temporary: false))
    }

    private func load(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        loading = true
        defer { loading = false; photoItems = [] }
        for item in items {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }),
               let m = try? await item.loadTransferable(type: PickedMovie.self) {
                files.append(Outgoing(url: m.url, name: m.url.lastPathComponent.components(separatedBy: "-").dropFirst().joined(separator: "-"),
                                      temporary: true))
            } else if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d),
                      let jpg = img.jpegData(compressionQuality: 0.9) {
                // HEIC -> JPEG: Claude legge jpg/png
                let name = FieldLog.newFileName("jpg")
                let dst = unique(name)
                try? jpg.write(to: dst)
                files.append(Outgoing(url: dst, name: name, temporary: true))
            }
        }
    }

    private func toggleRecording() {
        if recorder.recording {
            if let f = recorder.stop() {
                log.add(.audio, "Registrazione \(Int(recorder.elapsed)) s per Claude", file: f, at: location.location)
                files.append(Outgoing(url: FieldLog.dir.appendingPathComponent(f), name: f, temporary: false))
            }
        } else {
            recorder.start()
        }
    }

    private func cleanup() {
        for f in files where f.temporary { try? FileManager.default.removeItem(at: f.url) }
    }

    // MARK: invio

    private func send() async {
        busy = true
        error = nil
        defer { busy = false }
        var extra = note
        if let c = location.location?.coordinate {
            extra += (extra.isEmpty ? "" : "\n") + String(format: "Posizione del telefono all'invio: %.6f, %.6f", c.latitude, c.longitude)
        }
        let fasc = target.isEmpty ? nil : target
        if let e = await claude.sendFiles(files.map { ($0.url, $0.name) }, fascicolo: fasc, note: extra, analyze: analyze, client: client) {
            error = e
            return
        }
        cleanup()
        dismiss()
        NotificationCenter.default.post(name: .openClaude, object: nil)
    }
}

/// Video scelto dalla libreria: copiato in Uscita.
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { m in SentTransferredFile(m.url) } importing: { rec in
            let dst = SendSheet.outbox.appendingPathComponent(String(UUID().uuidString.prefix(6)) + "-" + rec.file.lastPathComponent)
            try FileManager.default.copyItem(at: rec.file, to: dst)
            return PickedMovie(url: dst)
        }
    }
}

/// Fotocamera di sistema con foto e video.
struct MediaCapture: UIViewControllerRepresentable {
    var onDone: (UIImage?, URL?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        p.videoQuality = .typeHigh
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: MediaCapture
        init(_ p: MediaCapture) { parent = p }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.onDone(info[.originalImage] as? UIImage, info[.mediaURL] as? URL)
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
