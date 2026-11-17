import Foundation
import CoreBluetooth
import CoreLocation
import SwiftUI

/// LoRa con gli Heltec (firmware Meshtastic) via Bluetooth: messaggi e posizioni anche senza rete.
/// Protocollo pubblico Meshtastic (protobuf) scritto a mano, solo i campi che servono.
final class LoRaMesh: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = LoRaMesh()

    struct Nodo: Identifiable { let id: UInt32; var nome: String; var lat: Double?; var lon: Double?; var ts: Date?
        var coordinate: CLLocationCoordinate2D? { lat.flatMap { la in lon.map { CLLocationCoordinate2D(latitude: la, longitude: $0) } } } }
    struct Messaggio: Identifiable { let id = UUID(); let da: String; let testo: String; let ts: Date; let mio: Bool }

    @Published var stato = "Spento"
    @Published var trovati: [CBPeripheral] = []
    @Published var collegato: CBPeripheral?
    @Published var nodi: [UInt32: Nodo] = [:]
    @Published var messaggi: [Messaggio] = []
    @Published var mandaPosizione = UserDefaults.standard.bool(forKey: "lora.posizione") {
        didSet { UserDefaults.standard.set(mandaPosizione, forKey: "lora.posizione") }
    }
    var mioNodo: UInt32 = 0
    var ultimaPosizione: CLLocation?

    private var central: CBCentralManager?
    private var toRadio: CBCharacteristic?
    private var fromRadio: CBCharacteristic?
    private var timer: Timer?

    static let servizio = CBUUID(string: "6BA1B218-15A8-461F-9FA8-5DCAE273EAFD")
    static let cToRadio = CBUUID(string: "F75C76D2-129E-4DAD-A1DD-7866124401E7")
    static let cFromRadio = CBUUID(string: "2C55E69E-4993-11ED-B878-0242AC120002")
    static let cFromRadioVecchio = CBUUID(string: "8BA2BCC2-EE02-4A55-A531-C525C5E454D5")
    static let cFromNum = CBUUID(string: "ED9DA18C-A800-4F66-A670-AA7547E34453")

    // MARK: Bluetooth

    func cerca() {
        if central == nil { central = CBCentralManager(delegate: self, queue: nil); stato = "Accendo il Bluetooth…"; return }
        avviaRicerca()
    }

    private func avviaRicerca() {
        guard central?.state == .poweredOn else { return }
        trovati = []
        stato = "Cerco gli Heltec…"
        central?.scanForPeripherals(withServices: [Self.servizio])
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, self.collegato == nil else { return }
            self.central?.stopScan()
            self.stato = self.trovati.isEmpty ? "Nessun Heltec trovato (Bluetooth acceso sul dispositivo?)" : "Scegli il dispositivo"
        }
    }

    func collega(_ p: CBPeripheral) {
        central?.stopScan()
        stato = "Mi collego a \(p.name ?? "Heltec")…"
        p.delegate = self
        central?.connect(p)
    }

    func scollega() {
        if let p = collegato { central?.cancelPeripheralConnection(p) }
        collegato = nil; toRadio = nil; fromRadio = nil
        timer?.invalidate(); timer = nil
        stato = "Scollegato"
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        if c.state == .poweredOn { avviaRicerca() } else { stato = "Bluetooth non disponibile" }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        if !trovati.contains(where: { $0.identifier == p.identifier }) { trovati.append(p) }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        collegato = p
        stato = "Collegato a \(p.name ?? "Heltec"), leggo la rete…"
        p.discoverServices([Self.servizio])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        stato = "Collegamento non riuscito: \(error?.localizedDescription ?? "")"
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        collegato = nil
        stato = "Heltec scollegato"
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] where s.uuid == Self.servizio { p.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for c in s.characteristics ?? [] {
            switch c.uuid {
            case Self.cToRadio: toRadio = c
            case Self.cFromRadio, Self.cFromRadioVecchio: fromRadio = c
            case Self.cFromNum: p.setNotifyValue(true, for: c)
            default: break
            }
        }
        // chiedo la configurazione (nodi, mio numero): poi leggo FromRadio finché è vuoto
        var m = Pb()
        m.varint(3, UInt64(UInt32.random(in: 1...UInt32.max)))
        scrivi(m.dati)
        leggi()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.posizionePeriodica() }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        if c.uuid == Self.cFromNum { leggi(); return }
        guard c.uuid == Self.cFromRadio || c.uuid == Self.cFromRadioVecchio, let d = c.value else { return }
        if d.isEmpty {
            if stato.hasPrefix("Collegato") || stato.hasPrefix("Mi collego") { stato = "Rete LoRa pronta · \(nodi.count) nodi" }
            return
        }
        interpreta(d)
        leggi()
    }

    private func leggi() {
        guard let p = collegato, let f = fromRadio else { return }
        p.readValue(for: f)
    }

    private func scrivi(_ d: Data) {
        guard let p = collegato, let t = toRadio else { return }
        p.writeValue(d, for: t, type: .withResponse)
    }

    // MARK: invio

    /// Messaggio di testo a tutta la rete LoRa (canale primario).
    func invia(_ testo: String) {
        var dataPb = Pb()
        dataPb.varint(1, 1)                       // TEXT_MESSAGE_APP
        dataPb.bytes(2, Data(testo.utf8))
        inviaPacchetto(dataPb.dati)
        messaggi.append(Messaggio(da: "io", testo: testo, ts: Date(), mio: true))
    }

    func inviaPosizione(_ l: CLLocation) {
        var pos = Pb()
        pos.fixed32(1, UInt32(bitPattern: Int32(l.coordinate.latitude * 1e7)))
        pos.fixed32(2, UInt32(bitPattern: Int32(l.coordinate.longitude * 1e7)))
        pos.varint(3, UInt64(bitPattern: Int64(Int32(l.altitude))))
        pos.fixed32(4, UInt32(Date().timeIntervalSince1970))
        var dataPb = Pb()
        dataPb.varint(1, 3)                       // POSITION_APP
        dataPb.bytes(2, pos.dati)
        inviaPacchetto(dataPb.dati)
    }

    private func posizionePeriodica() {
        if mandaPosizione, let l = ultimaPosizione { inviaPosizione(l) }
    }

    private func inviaPacchetto(_ decoded: Data) {
        var pkt = Pb()
        pkt.fixed32(2, 0xFFFF_FFFF)              // a tutti
        pkt.bytes(4, decoded)
        pkt.fixed32(6, UInt32.random(in: 1...UInt32.max))
        pkt.varint(9, 3)                          // hop_limit
        var to = Pb()
        to.bytes(1, pkt.dati)
        scrivi(to.dati)
    }

    // MARK: ricezione

    private func interpreta(_ d: Data) {
        let f = Pb.leggi(d)
        if let my = f[3]?.first?.bytes { mioNodo = UInt32(Pb.leggi(my)[1]?.first?.varint ?? 0) }
        if let ni = f[4]?.first?.bytes { nodoInfo(ni) }
        if let pkt = f[2]?.first?.bytes { pacchetto(pkt) }
    }

    private func nodoInfo(_ d: Data) {
        let f = Pb.leggi(d)
        let num = UInt32(f[1]?.first?.varint ?? 0)
        var n = nodi[num] ?? Nodo(id: num, nome: String(format: "!%08x", num), lat: nil, lon: nil, ts: nil)
        if let u = f[2]?.first?.bytes {
            let uf = Pb.leggi(u)
            if let s = uf[3]?.first?.bytes.flatMap({ String(data: $0, encoding: .utf8) }), !s.isEmpty { n.nome = s }
            if let l = uf[2]?.first?.bytes.flatMap({ String(data: $0, encoding: .utf8) }), !l.isEmpty { n.nome = l }
        }
        if let p = f[3]?.first?.bytes { posizione(p, &n) }
        if num != 0 && num != mioNodo { nodi[num] = n }
    }

    private func posizione(_ d: Data, _ n: inout Nodo) {
        let pf = Pb.leggi(d)
        if let la = pf[1]?.first?.fixed32, let lo = pf[2]?.first?.fixed32, la != 0 || lo != 0 {
            n.lat = Double(Int32(bitPattern: la)) / 1e7
            n.lon = Double(Int32(bitPattern: lo)) / 1e7
            n.ts = Date()
        }
    }

    private func pacchetto(_ d: Data) {
        let f = Pb.leggi(d)
        let da = f[1]?.first?.fixed32 ?? 0
        guard let dec = f[4]?.first?.bytes else { return }
        let df = Pb.leggi(dec)
        let porta = df[1]?.first?.varint ?? 0
        guard let payload = df[2]?.first?.bytes else { return }
        var n = nodi[da] ?? Nodo(id: da, nome: String(format: "!%08x", da), lat: nil, lon: nil, ts: nil)
        switch porta {
        case 1:
            let t = String(data: payload, encoding: .utf8) ?? ""
            messaggi.append(Messaggio(da: n.nome, testo: t, ts: Date(), mio: false))
            NotificationCenter.default.post(name: .loraMessaggio, object: nil, userInfo: ["testo": "\(n.nome): \(t)"])
        case 3:
            posizione(payload, &n)
        case 4:
            let uf = Pb.leggi(payload)
            if let l = uf[2]?.first?.bytes.flatMap({ String(data: $0, encoding: .utf8) }), !l.isEmpty { n.nome = l }
        default: break
        }
        if da != mioNodo && da != 0 { nodi[da] = n }
    }
}

extension Notification.Name { static let loraMessaggio = Notification.Name("jsoc.loraMessaggio") }

// MARK: - Protobuf minimo (varint, 32 bit, byte)

struct Pb {
    var dati = Data()

    mutating func chiave(_ campo: Int, _ tipo: Int) { varintGrezzo(UInt64(campo << 3 | tipo)) }
    mutating func varintGrezzo(_ v: UInt64) {
        var x = v
        while x >= 0x80 { dati.append(UInt8(x & 0x7F) | 0x80); x >>= 7 }
        dati.append(UInt8(x))
    }
    mutating func varint(_ campo: Int, _ v: UInt64) { chiave(campo, 0); varintGrezzo(v) }
    mutating func fixed32(_ campo: Int, _ v: UInt32) {
        chiave(campo, 5)
        withUnsafeBytes(of: v.littleEndian) { dati.append(contentsOf: $0) }
    }
    mutating func bytes(_ campo: Int, _ b: Data) { chiave(campo, 2); varintGrezzo(UInt64(b.count)); dati.append(b) }

    enum Valore { case v(UInt64), f32(UInt32), f64(UInt64), b(Data)
        var varint: UInt64? { if case .v(let x) = self { return x }; return nil }
        var fixed32: UInt32? { if case .f32(let x) = self { return x }; return nil }
        var bytes: Data? { if case .b(let x) = self { return x }; return nil }
    }

    /// campo → valori (un messaggio protobuf qualsiasi, senza schema)
    static func leggi(_ d: Data) -> [Int: [Valore]] {
        var out: [Int: [Valore]] = [:]
        let b = [UInt8](d)
        var i = 0
        func vi() -> UInt64? {
            var r: UInt64 = 0, s: UInt64 = 0
            while i < b.count {
                let x = b[i]; i += 1
                r |= UInt64(x & 0x7F) << s
                if x & 0x80 == 0 { return r }
                s += 7
                if s > 63 { return nil }
            }
            return nil
        }
        while i < b.count {
            guard let k = vi() else { break }
            let campo = Int(k >> 3), tipo = Int(k & 7)
            switch tipo {
            case 0: guard let v = vi() else { return out }; out[campo, default: []].append(.v(v))
            case 1:
                guard i + 8 <= b.count else { return out }
                var v: UInt64 = 0; for j in 0..<8 { v |= UInt64(b[i + j]) << (8 * UInt64(j)) }
                i += 8; out[campo, default: []].append(.f64(v))
            case 2:
                guard let n = vi(), i + Int(n) <= b.count else { return out }
                out[campo, default: []].append(.b(Data(b[i..<i + Int(n)]))); i += Int(n)
            case 5:
                guard i + 4 <= b.count else { return out }
                var v: UInt32 = 0; for j in 0..<4 { v |= UInt32(b[i + j]) << (8 * UInt32(j)) }
                i += 4; out[campo, default: []].append(.f32(v))
            default: return out
            }
        }
        return out
    }
}

// MARK: - Pannello LoRa

struct PannelloLoRa: View {
    @ObservedObject var lora = LoRaMesh.shared
    var chiudi: () -> Void
    @EnvironmentObject var location: LocationService
    @State private var testo = ""

    var body: some View {
        VStack(spacing: 0) {
            TestataPannello(titolo: "LoRa Heltec", sotto: lora.stato, chiudi: chiudi)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if lora.collegato == nil {
                        Button { lora.cerca() } label: { Label("Cerca gli Heltec", systemImage: "antenna.radiowaves.left.and.right").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent).tint(Theme.olive).foregroundStyle(.black)
                        ForEach(lora.trovati, id: \.identifier) { p in
                            Button { lora.collega(p) } label: {
                                HStack { Image(systemName: "dot.radiowaves.right"); Text(p.name ?? "Meshtastic"); Spacer(); Text("Collega").foregroundStyle(Theme.olive) }
                                    .font(.system(size: 13.5, weight: .bold)).padding(10)
                                    .background(Theme.surface2.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        Text("Funziona con il firmware Meshtastic sugli Heltec: posizioni e messaggi passano via radio, senza internet.").font(.caption2).foregroundStyle(Theme.dim)
                    } else {
                        Toggle("Manda la mia posizione ogni minuto", isOn: $lora.mandaPosizione).tint(Theme.olive).font(.system(size: 13.5))
                        HStack {
                            Button("Manda posizione ora") { if let l = location.location { lora.inviaPosizione(l) } }.buttonStyle(.bordered).tint(Theme.olive)
                            Spacer()
                            Button("Scollega") { lora.scollega() }.buttonStyle(.bordered).tint(Theme.red)
                        }
                        .font(.system(size: 12.5, weight: .bold))
                        EtichettaSezione(testo: "Nodi in rete · \(lora.nodi.count)")
                        ForEach(lora.nodi.values.sorted { $0.nome < $1.nome }) { n in
                            HStack {
                                Text(n.nome).font(Theme.mono(13, .bold))
                                Spacer()
                                if let c = n.coordinate, let me = location.location?.coordinate {
                                    Text("\(Geo.formatDistance(Geo.distance(me, c))) · \(gradi3(Geo.bearing(me, c)))").font(Theme.mono(11)).foregroundStyle(Theme.olive)
                                }
                                if let t = n.ts { Text(t.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(Theme.dim) }
                            }
                        }
                        EtichettaSezione(testo: "Messaggi via radio")
                        ForEach(lora.messaggi.suffix(30)) { m in
                            HStack(alignment: .top) {
                                Text(m.da).font(Theme.mono(11, .heavy)).foregroundStyle(m.mio ? Theme.dim : Theme.cyan)
                                Text(m.testo).font(.system(size: 13))
                            }
                        }
                    }
                }
                .padding(14)
            }
            if lora.collegato != nil {
                HStack {
                    TextField("Messaggio via LoRa (corto)", text: $testo).padding(9).background(Theme.surface2.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                    Button { lora.invia(testo); testo = "" } label: { Image(systemName: "paperplane.fill").font(.title3) }
                        .tint(Theme.olive).disabled(testo.isEmpty)
                }
                .padding(10)
            }
        }
        .onReceive(location.$location) { l in if let l { lora.ultimaPosizione = l } }
    }
}
