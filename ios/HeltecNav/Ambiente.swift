import SwiftUI
import Foundation

// MARK: - Radio e contatti della direzione gara

struct RadioCard: View {
    @EnvironmentObject var mission: Mission

    static let lpdObj: [(String, Int)] = [("FF01", 3), ("FF02", 5), ("FF03", 7), ("FF04", 21), ("FF05", 9),
                                          ("FF06", 11), ("FF07", 13), ("FF08", 15), ("FF09", 17), ("FF10", 19)]
    static func mhz(_ ch: Int) -> String { String(format: "%.3f", 433.075 + Double(ch - 1) * 0.025) }

    var body: some View {
        Card(title: "Radio e contatti", icon: "antenna.radiowaves.left.and.right") {
            HStack(spacing: 10) {
                canale("Squadra", 60, enfasi: true)
                canale("Squadra 2", 61, enfasi: true)
                canale("Direzione", 69, enfasi: false)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                ForEach(Self.lpdObj, id: \.0) { o in
                    let prossimo = mission.prossima?.code == o.0 || mission.finestra?.code == o.0
                    VStack(spacing: 1) {
                        Text(o.0).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(prossimo ? .black : Theme.dim)
                        Text("\(o.1)").font(Theme.mono(15, .bold)).foregroundStyle(prossimo ? .black : .white)
                    }
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(prossimo ? Theme.olive : Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            HStack(spacing: 10) {
                chiama("DE 1", "3357246313")
                chiama("DE 2", "3477025705")
            }
        }
    }

    func canale(_ t: String, _ ch: Int, enfasi: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t.uppercased()).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(Theme.dim)
            Text("LPD \(ch)").font(Theme.mono(17, .bold)).foregroundStyle(enfasi ? Theme.olive : .white)
            Text(Self.mhz(ch) + " MHz").font(Theme.mono(10)).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func chiama(_ t: String, _ n: String) -> some View {
        Link(destination: URL(string: "tel:\(n)")!) {
            Label("\(t) · \(n.prefix(3)) \(n.dropFirst(3))", systemImage: "phone.fill")
                .font(.caption.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(Theme.olive.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(Theme.olive)
        }
    }
}

// MARK: - Sole, luna, meteo

enum Astro {
    static let lat = 43.98, lon = 12.38

    /// Alba/tramonto (e crepuscoli) con l'algoritmo NOAA. zenith: 90.833 sole, 96 civile, 102 nautico.
    static func sole(_ giorno: Date, zenith: Double, alba: Bool) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let N = Double(cal.ordinality(of: .day, in: .year, for: giorno) ?? 1)
        let lngHour = lon / 15
        let t = N + ((alba ? 6 : 18) - lngHour) / 24
        let M = 0.9856 * t - 3.289
        var L = M + 1.916 * sin(M * .pi / 180) + 0.020 * sin(2 * M * .pi / 180) + 282.634
        L = L.truncatingRemainder(dividingBy: 360); if L < 0 { L += 360 }
        var RA = atan(0.91764 * tan(L * .pi / 180)) * 180 / .pi
        RA = RA.truncatingRemainder(dividingBy: 360); if RA < 0 { RA += 360 }
        RA += floor(L / 90) * 90 - floor(RA / 90) * 90
        RA /= 15
        let sinDec = 0.39782 * sin(L * .pi / 180), cosDec = cos(asin(sinDec))
        let cosH = (cos(zenith * .pi / 180) - sinDec * sin(lat * .pi / 180)) / (cosDec * cos(lat * .pi / 180))
        guard cosH <= 1, cosH >= -1 else { return nil }
        var H = alba ? 360 - acos(cosH) * 180 / .pi : acos(cosH) * 180 / .pi
        H /= 15
        var UT = H + RA - 0.06571 * t - 6.622 - lngHour
        UT = UT.truncatingRemainder(dividingBy: 24); if UT < 0 { UT += 24 }
        let inizio = cal.startOfDay(for: giorno)
        return inizio.addingTimeInterval(UT * 3600)
    }

    /// Età della luna (giorni) e frazione illuminata.
    static func luna(_ d: Date) -> (eta: Double, luce: Double, nome: String, simbolo: String) {
        let sinodico = 29.530588853
        let nuova = Date(timeIntervalSince1970: 947182440)     // 6/1/2000 18:14 UTC
        var eta = d.timeIntervalSince(nuova) / 86400
        eta = eta.truncatingRemainder(dividingBy: sinodico); if eta < 0 { eta += sinodico }
        let luce = (1 - cos(2 * .pi * eta / sinodico)) / 2
        let fasi = [("Luna nuova", "moonphase.new.moon"), ("Falce crescente", "moonphase.waxing.crescent"),
                    ("Primo quarto", "moonphase.first.quarter"), ("Gibbosa crescente", "moonphase.waxing.gibbous"),
                    ("Luna piena", "moonphase.full.moon"), ("Gibbosa calante", "moonphase.waning.gibbous"),
                    ("Ultimo quarto", "moonphase.last.quarter"), ("Falce calante", "moonphase.waning.crescent")]
        let f = fasi[Int((eta / sinodico * 8).rounded()) % 8]
        return (eta, luce, f.0, f.1)
    }
}

struct MeteoOra: Codable, Identifiable {
    var id: Date { ora }
    let ora: Date
    let temp: Double
    let pioggia: Int
    let vento: Double
    let nuvole: Int
    let codice: Int

    var icona: String {
        switch codice {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

@MainActor
final class Meteo: ObservableObject {
    static let shared = Meteo()
    @Published var ore: [MeteoOra] = []
    @Published var aggiornato: Date?

    init() {
        if let d = UserDefaults.standard.data(forKey: "meteo.cache"), let o = try? JSONDecoder().decode([MeteoOra].self, from: d) {
            ore = o
            aggiornato = UserDefaults.standard.object(forKey: "meteo.ora") as? Date
        }
    }

    func carica() async {
        if let a = aggiornato, Date().timeIntervalSince(a) < 1800 { return }
        let s = "https://api.open-meteo.com/v1/forecast?latitude=\(Astro.lat)&longitude=\(Astro.lon)&hourly=temperature_2m,precipitation_probability,wind_speed_10m,cloud_cover,weather_code&timezone=Europe%2FRome&forecast_days=7"
        struct R: Decodable {
            struct H: Decodable {
                let time: [String]; let temperature_2m: [Double]; let precipitation_probability: [Int?]
                let wind_speed_10m: [Double]; let cloud_cover: [Int]; let weather_code: [Int]
            }
            let hourly: H
        }
        guard let u = URL(string: s), let res = try? await URLSession.shared.data(from: u),
              let r = try? JSONDecoder().decode(R.self, from: res.0) else { return }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.timeZone = TimeZone(identifier: "Europe/Rome")
        let h = r.hourly
        ore = h.time.indices.compactMap { i in
            guard let t = f.date(from: h.time[i]) else { return nil }
            return MeteoOra(ora: t, temp: h.temperature_2m[i], pioggia: h.precipitation_probability[i] ?? 0,
                            vento: h.wind_speed_10m[i], nuvole: h.cloud_cover[i], codice: h.weather_code[i])
        }
        aggiornato = Date()
        if let e = try? JSONEncoder().encode(ore) { UserDefaults.standard.set(e, forKey: "meteo.cache") }
        UserDefaults.standard.set(aggiornato, forKey: "meteo.ora")
    }
}

struct AmbienteCard: View {
    @ObservedObject private var meteo = Meteo.shared
    @State private var giorno = 0

    let giorni: [(String, Date)] = [("Ven 13", Shared.date(13, 12)), ("Sab 14", Shared.date(14, 12)), ("Dom 15", Shared.date(15, 12))]

    var body: some View {
        Card(title: "Sole, luna e meteo", icon: "sun.and.horizon",
             trailing: meteo.aggiornato.map { "agg. " + $0.formatted(date: .omitted, time: .shortened) }) {
            Picker("", selection: $giorno) {
                ForEach(giorni.indices, id: \.self) { Text(giorni[$0].0).tag($0) }
            }
            .pickerStyle(.segmented)
            let g = giorni[giorno].1
            let l = Astro.luna(Shared.date(Calendar.current.component(.day, from: g), 23))
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    riga("sunrise.fill", "Alba", Astro.sole(g, zenith: 90.833, alba: true))
                    riga("sunset.fill", "Tramonto", Astro.sole(g, zenith: 90.833, alba: false))
                    riga("moon.haze", "Buio civile", Astro.sole(g, zenith: 96, alba: false))
                    riga("moon.stars", "Buio nautico", Astro.sole(g, zenith: 102, alba: false))
                }
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: l.simbolo).font(.system(size: 38)).foregroundStyle(Theme.olive)
                    Text(l.nome).font(.caption.weight(.semibold))
                    Text(String(format: "%.0f%% illuminata", l.luce * 100)).font(Theme.mono(11)).foregroundStyle(Theme.dim)
                }
            }
            let ore = meteo.ore.filter { Calendar.current.isDate($0.ora, inSameDayAs: g) }
            if ore.isEmpty {
                Text(meteo.ore.isEmpty ? "Meteo non ancora scaricato (serve rete)" : "Previsioni per questo giorno non ancora disponibili")
                    .font(.caption).foregroundStyle(Theme.dim)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ore.filter { Calendar.current.component(.hour, from: $0.ora) % 2 == 0 }) { o in
                            VStack(spacing: 4) {
                                Text(o.ora.formatted(.dateTime.hour())).font(Theme.mono(10)).foregroundStyle(Theme.dim)
                                Image(systemName: o.icona).symbolRenderingMode(.multicolor).font(.system(size: 18))
                                Text(String(format: "%.0f°", o.temp)).font(Theme.mono(13, .bold))
                                Text("\(o.pioggia)%").font(Theme.mono(10)).foregroundStyle(o.pioggia >= 50 ? Theme.cyan : Theme.dim)
                                Text(String(format: "%.0f", o.vento)).font(Theme.mono(9)).foregroundStyle(Theme.dim)
                            }
                            .frame(width: 44)
                            .padding(.vertical, 6)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
                Text("pioggia % · vento km/h · zona Torriana").font(.system(size: 10)).foregroundStyle(Theme.dim)
            }
        }
        .task { await meteo.carica() }
    }

    func riga(_ icon: String, _ t: String, _ d: Date?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).symbolRenderingMode(.multicolor).frame(width: 20)
            Text(t).font(.caption).foregroundStyle(Theme.dim).frame(width: 82, alignment: .leading)
            Text(d.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—").font(Theme.mono(13, .bold))
        }
    }
}
