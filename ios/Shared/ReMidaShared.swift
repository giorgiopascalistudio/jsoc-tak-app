import Foundation
import SwiftUI
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

/// Cose in comune tra l'app e il widget (Dynamic Island, schermata di blocco, Home).
enum Shared {
    static let appGroup = "group.com.giorgiopascali.heltecnav"
    /// Se il gruppo app non è disponibile (firma con Apple ID gratuito) si ripiega sulle preferenze normali.
    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    static let olive = Color(red: 0.604, green: 0.682, blue: 0.357)       // #9AAE5B
    static let oliveDark = Color(red: 0.33, green: 0.38, blue: 0.19)
    static let ok = Color(red: 0.45, green: 0.85, blue: 0.45)
    static let ko = Color(red: 0.95, green: 0.35, blue: 0.30)

    struct Evento { let date: Date; let title: String; let detail: String }

    static func date(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = day; c.hour = h; c.minute = m
        c.timeZone = TimeZone(identifier: "Europe/Rome")
        return Calendar(identifier: .gregorian).date(from: c) ?? Date()
    }

    // Dalla "Timeline - OP. RE MIDA.pdf" (31/10) + chat/forum
    static let timeline: [Evento] = [
        .init(date: date(6, 23, 59), title: "Scadenza domande forum", detail: "Ultimo giorno per i dubbi sul forum."),
        .init(date: date(9, 21), title: "Briefing online", detail: "Lunedì 09/11."),
        .init(date: date(13, 14), title: "Check-in con Eros", detail: "14:00–14:30 bar hotel ARIA. FALLO + ORO in una frase. Check-in AQUA con ≥4 operatori."),
        .init(date: date(13, 15), title: "Finestre FASE STAGNO", detail: "Inizio finestre fase Stagno."),
        .init(date: date(13, 15, 30), title: "FASE PIOMBO", detail: "Poi si continua."),
        .init(date: date(14, 0, 30), title: "Riposo", detail: "Notte in hotel."),
        .init(date: date(14, 6), title: "Colazione", detail: "Partire entro le 06:45."),
        .init(date: date(14, 7, 30), title: "Infiltrazione FERRO", detail: "QR code all'infiltrazione."),
        .init(date: date(14, 8), title: "Inizio OBJ Fase FERRO", detail: "Finestre fino alle 19:40."),
        .init(date: date(14, 19, 40), title: "Ultima finestra OBJ", detail: ""),
        .init(date: date(14, 21), title: "Esfiltrazione massima", detail: "QR code. Poi operatività a tempo indefinito."),
        .init(date: date(14, 21, 15), title: "In auto", detail: "Assetto tattico, ASG in custodia. Codice della strada = squalifica."),
        .init(date: date(15, 7), title: "Rientro in hotel", detail: "Fascia 07–08. Colazione e a disposizione HQ fino alle 11."),
        .init(date: date(15, 11), title: "Debriefing", detail: "11–14, pranzo alle 13."),
        .init(date: date(15, 15), title: "Premiazioni", detail: ""),
    ]

    static func prossimo(_ now: Date = Date()) -> Evento? { timeline.first { $0.date > now } }

    // istantanea scritta dall'app e letta dal widget Home
    struct Snapshot: Codable {
        var obj = ""          // "FF06 Deposito stupefacenti"
        var objDist = ""      // "1,2 km"
        var objDir = ""       // "NE 42°"
        var utm = ""
        var pc = -1           // 1 ok, 0 non risponde, -1 non collegato
        var server = -1
        var claude = ""       // "" | "lavora" | "fatto"
        var ora = Date()
    }

    static func saveSnapshot(_ s: Snapshot) {
        if let d = try? JSONEncoder().encode(s) { defaults.set(d, forKey: "widget.snapshot") }
    }
    static func loadSnapshot() -> Snapshot? {
        guard let d = defaults.data(forKey: "widget.snapshot") else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: d)
    }
}

#if canImport(ActivityKit) && os(iOS)
@available(iOS 16.1, *)
struct ReMidaActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var evento: String
        var eventoData: Date
        var obj: String          // codice + nome breve, es. "FF06 Stupefacenti"
        var objDist: String
        var objGradi: Double     // direzione rispetto al nord (per la freccia)
        var utm: String
        var pc: Int
        var server: Int
        var claude: String
    }
    var squadra: String
}
#endif

// MARK: - Tabella di marcia (dal GPX della squadra: 3,5 km/h, +10' ogni 100 m di salita, 5' attesa + durata OBJ)

struct TappaMarcia: Codable, Hashable, Identifiable {
    let code: String
    let nome: String
    let lat: Double
    let lon: Double
    let arrivo: Int      // minuti dalla mezzanotte di sabato 14/11
    let fine: Int
    var id: String { code }

    static func ora(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }

    /// Durata della finestra di ingaggio dai book (minuti).
    static func durata(_ code: String) -> Int {
        switch code { case "FF01": return 25; case "FF05": return 15; default: return 20 }
    }
}

extension Shared {
    static let marcia: [TappaMarcia] = [
        .init(code: "FF08", nome: "Fossa comune", lat: 43.969052, lon: 12.366239, arrivo: 551, fine: 576),
        .init(code: "FF06", nome: "Deposito stupefacenti", lat: 43.962817, lon: 12.37074, arrivo: 606, fine: 631),
        .init(code: "FF10", nome: "Lab chimico Alfa", lat: 43.960165, lon: 12.386998, arrivo: 655, fine: 680),
        .init(code: "FF07", nome: "Lab chimico Bravo", lat: 43.966964, lon: 12.385453, arrivo: 708, fine: 733),
        .init(code: "FF05", nome: "Mercato nero", lat: 43.978459, lon: 12.379874, arrivo: 784, fine: 804),
        .init(code: "FF09", nome: "Stazione di estrazione", lat: 43.981052, lon: 12.380657, arrivo: 812, fine: 837),
        .init(code: "FF02", nome: "La Confraternita", lat: 43.985614, lon: 12.383699, arrivo: 863, fine: 888),
        .init(code: "FF01", nome: "Villa Valdrago", lat: 43.994406, lon: 12.381142, arrivo: 924, fine: 954),
        .init(code: "FF03", nome: "Eliporto", lat: 43.996776, lon: 12.384006, arrivo: 990, fine: 1015),
    ]

    /// Ritardo (+) o anticipo (−) in minuti rispetto alla tabella, dall'ultimo OBJ fatto.
    static func scarto(fatti: [String: Date]) -> Int? {
        let cal = Calendar(identifier: .gregorian)
        guard let ultimo = marcia.last(where: { fatti[$0.code] != nil }), let t = fatti[ultimo.code] else { return nil }
        let c = cal.dateComponents(in: TimeZone(identifier: "Europe/Rome")!, from: t)
        let minuti = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return minuti - ultimo.fine
    }
}

/// Quello che l'iPhone manda all'orologio (WatchConnectivity, applicationContext).
struct StatoOrologio: Codable {
    var fatti: [String: Date] = [:]
    var finestraCode: String?
    var finestraInizio: Date?
    var finestraFine: Date?
    var pc = -1
    var server = -1
    var claude = ""
    var evento = ""
    var eventoData = Date()
    var meteoTemp: Double?
    var meteoPioggia: Int?
    var meteoIcona = "cloud"
    var meteoVento: Double?
    var notte = false
    var inizioPercorso: Date?
    var io = "GREG"
    var operatori: [OperatoreOrologio] = []
    var aggiornato = Date()
}

struct OperatoreOrologio: Codable, Hashable, Identifiable {
    let cs: String
    let lat: Double
    let lon: Double
    let collegato: Bool
    var id: String { cs }
}
