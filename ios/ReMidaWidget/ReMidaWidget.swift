import WidgetKit
import SwiftUI
import ActivityKit

@main
struct ReMidaWidgets: WidgetBundle {
    var body: some Widget {
        GaraHomeWidget()
        GaraLiveActivity()
    }
}

// MARK: - Pezzi comuni

struct Pallino: View {
    let stato: Int
    let nome: String
    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(stato == 1 ? Shared.ok : (stato == 0 ? Shared.ko : Color.gray)).frame(width: 7, height: 7)
            Text(nome).font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
    }
}

struct Freccia: View {
    let gradi: Double
    var body: some View {
        Image(systemName: "location.north.fill").rotationEffect(.degrees(gradi)).foregroundStyle(Shared.olive)
    }
}

// MARK: - Live Activity (Dynamic Island + schermata di blocco)

@available(iOS 16.1, *)
struct GaraLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReMidaActivityAttributes.self) { ctx in
            LockScreenView(s: ctx.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(Shared.olive)
        } dynamicIsland: { ctx in
            GaraLiveActivity.isola(ctx.state)
        }
    }

    static func isola(_ s: ReMidaActivityAttributes.ContentState) -> DynamicIsland {
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.evento).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        Text(timerInterval: Date()...max(Date(), s.eventoData), countsDown: true)
                            .font(.system(.title3, design: .monospaced).weight(.bold)).foregroundStyle(Shared.olive)
                            .monospacedDigit()
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 3) {
                        Pallino(stato: s.pc, nome: "PC")
                        Pallino(stato: s.server, nome: "SRV")
                        if !s.claude.isEmpty {
                            Text(s.claude == "lavora" ? "Claude…" : "Claude ✓").font(.system(size: 10, weight: .bold)).foregroundStyle(Shared.olive)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        if !s.obj.isEmpty {
                            HStack {
                                Freccia(gradi: s.objGradi)
                                Text(s.obj).font(.subheadline.weight(.bold)).lineLimit(1)
                                Spacer()
                                Text(s.objDist).font(.system(.subheadline, design: .monospaced).weight(.bold)).foregroundStyle(Shared.olive)
                            }
                        }
                        Text(s.utm).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Freccia(gradi: s.objGradi).font(.caption2)
                    Text(s.objDist.isEmpty ? "ORO" : s.objDist).font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Shared.olive)
                }
            } compactTrailing: {
                if s.eventoData.timeIntervalSinceNow < 3600 {
                    Text(timerInterval: Date()...max(Date(), s.eventoData), countsDown: true)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced)).monospacedDigit()
                        .frame(maxWidth: 52)
                } else {
                    Text(breve(s.eventoData)).font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
            } minimal: {
                Freccia(gradi: s.objGradi).font(.caption)
            }
            .keylineTint(Shared.olive)
    }
}

/// "3g 02h" o "2h 15m": per la Dynamic Island compatta quando manca più di un'ora.
func breve(_ d: Date) -> String {
    let s = max(0, Int(d.timeIntervalSinceNow))
    if s >= 86400 { return "\(s / 86400)g \(String(format: "%02d", (s % 86400) / 3600))h" }
    return "\(s / 3600)h \(String(format: "%02d", (s % 3600) / 60))m"
}

@available(iOS 16.1, *)
struct LockScreenView: View {
    let s: ReMidaActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RE MIDA · ORO 16").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(Shared.olive)
                Spacer()
                Pallino(stato: s.pc, nome: "PC")
                Pallino(stato: s.server, nome: "SRV")
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.evento).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text(timerInterval: Date()...max(Date(), s.eventoData), countsDown: true)
                        .font(.system(size: 26, weight: .bold, design: .monospaced)).monospacedDigit().foregroundStyle(.white)
                }
                Spacer()
                if !s.obj.isEmpty {
                    VStack(alignment: .trailing, spacing: 1) {
                        HStack(spacing: 4) { Freccia(gradi: s.objGradi); Text(s.objDist).font(.system(.headline, design: .monospaced)) }
                        Text(s.obj).font(.caption.weight(.semibold)).lineLimit(1)
                    }
                }
            }
            HStack {
                Text(s.utm).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                if !s.claude.isEmpty {
                    Text(s.claude == "lavora" ? "Claude sta lavorando" : "Risposta di Claude pronta")
                        .font(.caption2.weight(.bold)).foregroundStyle(Shared.olive)
                }
            }
        }
        .padding(14)
        .foregroundStyle(.white)
    }
}

// MARK: - Widget Home

struct GaraEntry: TimelineEntry {
    let date: Date
    let evento: Shared.Evento?
    let snap: Shared.Snapshot?
}

struct GaraProvider: TimelineProvider {
    func placeholder(in context: Context) -> GaraEntry {
        GaraEntry(date: Date(), evento: Shared.prossimo(), snap: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (GaraEntry) -> Void) {
        completion(GaraEntry(date: Date(), evento: Shared.prossimo(), snap: Shared.loadSnapshot()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<GaraEntry>) -> Void) {
        // una voce per ogni evento in arrivo, così il widget passa da solo al successivo
        let now = Date()
        var dates = [now] + Shared.timeline.map(\.date).filter { $0 > now }.prefix(6)
        dates = Array(Set(dates)).sorted()
        let snap = Shared.loadSnapshot()
        let entries = dates.map { d in GaraEntry(date: d, evento: Shared.prossimo(d), snap: snap) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }
}

struct GaraHomeView: View {
    @Environment(\.widgetFamily) var family
    let e: GaraEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("RE MIDA").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(Shared.olive)
                Spacer()
                if let s = e.snap {
                    Pallino(stato: s.pc, nome: "PC")
                    Pallino(stato: s.server, nome: "SRV")
                }
            }
            if let ev = e.evento {
                Text(ev.title).font(.caption.weight(.semibold)).lineLimit(2)
                Text(ev.date, style: .timer).font(.system(size: family == .systemSmall ? 20 : 26, weight: .bold, design: .monospaced))
                    .foregroundStyle(Shared.olive).monospacedDigit()
            } else {
                Text("Gara conclusa").font(.headline)
            }
            Spacer(minLength: 0)
            if let s = e.snap, !s.obj.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "scope").foregroundStyle(Shared.olive)
                    Text(s.obj).font(.caption2.weight(.semibold)).lineLimit(1)
                    if family != .systemSmall { Spacer(); Text("\(s.objDist) \(s.objDir)").font(.system(size: 11, design: .monospaced)) }
                }
                if family != .systemSmall {
                    Text(s.utm).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
    }
}

struct GaraHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ReMidaGara", provider: GaraProvider()) { e in
            if #available(iOS 17.0, *) {
                GaraHomeView(e: e).containerBackground(Color.black, for: .widget)
            } else {
                GaraHomeView(e: e)
            }
        }
        .configurationDisplayName("Re Mida")
        .description("Countdown di gara, prossimo OBJ e stato di PC e server.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}


// MARK: - Versione per Apple Watch (Smart Stack), da iOS 18 / watchOS 11

@available(iOS 18.0, *)
struct GaraLiveActivityOrologio: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReMidaActivityAttributes.self) { ctx in
            SchermataAdattiva(s: ctx.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(Shared.olive)
        } dynamicIsland: { ctx in
            GaraLiveActivity.isola(ctx.state)
        }
    }
}

@available(iOS 18.0, *)
struct SchermataAdattiva: View {
    @Environment(\.activityFamily) var famiglia
    let s: ReMidaActivityAttributes.ContentState
    var body: some View {
        if famiglia == .small { OrologioView(s: s) } else { LockScreenView(s: s) }
    }
}

/// Quello che si vede sull'orologio: OBJ, distanza e direzione, timer che scorre, UTM, PC/server.
@available(iOS 16.1, *)
struct OrologioView: View {
    let s: ReMidaActivityAttributes.ContentState
    var finestra: Bool { s.evento.contains("finestra") }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(s.obj.split(separator: " ").first.map(String.init) ?? "ORO")
                    .font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundStyle(Shared.olive)
                Freccia(gradi: s.objGradi).font(.system(size: 13))
                Text(s.objDist).font(.system(size: 14, weight: .bold, design: .monospaced))
                Spacer(minLength: 0)
                Pallino(stato: s.pc, nome: "")
                Pallino(stato: s.server, nome: "")
            }
            Text(timerInterval: Date()...max(Date(), s.eventoData), countsDown: true)
                .font(.system(size: 26, weight: .heavy, design: .monospaced)).monospacedDigit()
                .foregroundStyle(finestra ? Color(red: 0.92, green: 0.64, blue: 0.28) : .white)
            Text(finestra ? s.evento : s.evento).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                .foregroundStyle(.secondary)
            Text(s.utm.replacingOccurrences(of: "UTM ", with: "")).font(.system(size: 11, weight: .semibold, design: .monospaced))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
    }
}
