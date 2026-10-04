//
//  LoopGlanceWidget.swift
//  Loop Complications
//
//  The Sport glance as ONE configurable complication: the metric is an App Intent parameter, and each
//  preset in `recommendations()` appears in the face editor as its own choice ("Loop · IOB", …). One
//  view per family covers every face. Adding a metric is one enum case plus its strings below.
//
//  Style rules (each learned on the wrist or in the simulator, 2026-09-30 – 10-01): plain-String
//  descriptions; a container background on every family; a corner's value rides its curved label with
//  an empty tip (the face curves the label, not the content); no units; a dash after 15 min; meaning is
//  never carried by colour alone (tinted faces drop it); accent parts are `widgetAccentable`.
//

import AppIntents
import SwiftUI
import WidgetKit

extension GlanceMetric: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Value"
    static let caseDisplayRepresentations: [GlanceMetric: DisplayRepresentation] = [
        .bg: "BG",
        .bgEventual: "BG → Eventual",
        .eventual: "Eventual BG",
        .iob: "IOB",
        .cob: "COB",
        .iobCob: "IOB · COB",
        .temp: "Temp Basal",
        .loop: "Loop Status",
        .override: "Override",
        .glance: "Glance",
    ]
}

struct GlanceMetricIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Loop Value"
    static let description = IntentDescription("Which of the glance's values this complication shows.")

    @Parameter(title: "Value", default: .bgEventual)
    var metric: GlanceMetric

    init() {}

    init(metric: GlanceMetric) {
        self.metric = metric
    }
}

struct GlanceEntry: TimelineEntry {
    let date: Date
    let metric: GlanceMetric
    let snapshot: GlanceComplicationSnapshot?
}

struct GlanceProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> GlanceEntry {
        GlanceEntry(date: Date(), metric: .bgEventual, snapshot: .sample)
    }

    func snapshot(for configuration: GlanceMetricIntent, in context: Context) async -> GlanceEntry {
        GlanceEntry(date: Date(), metric: configuration.metric,
                    snapshot: context.isPreview ? .sample : GlanceComplicationSnapshot.load())
    }

    /// Now, then each moment a value goes stale or the ring turns. New data comes by a reload.
    func timeline(for configuration: GlanceMetricIntent, in context: Context) async -> Timeline<GlanceEntry> {
        let now = Date()
        let snapshot = GlanceComplicationSnapshot.load()
        let moments = [now] + (snapshot?.changeMoments(after: now) ?? [])
        return Timeline(entries: moments.map { GlanceEntry(date: $0, metric: configuration.metric, snapshot: snapshot) },
                        policy: .never)
    }

    /// watchOS has no widget configuration UI: each recommendation is a separate face-editor choice.
    func recommendations() -> [AppIntentRecommendation<GlanceMetricIntent>] {
        GlanceMetric.allCases.map { AppIntentRecommendation(intent: GlanceMetricIntent(metric: $0), description: $0.title) }
    }
}

extension GlanceComplicationSnapshot.BGRange {
    /// The glance's colours for the reading.
    var color: Color {
        switch self {
        case .inRange: return Color(red: 0.298, green: 0.851, blue: 0.392)
        case .high: return .yellow
        case .low: return Color(red: 1, green: 59 / 255, blue: 48 / 255)
        }
    }
}

// MARK: - Views

struct GlanceComplicationView: View {
    let entry: GlanceEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: GlanceComplicationSnapshot { entry.snapshot ?? GlanceComplicationSnapshot() }
    private var metric: GlanceMetric { entry.metric }
    private var date: Date { entry.date }
    private var bgColor: Color { snapshot.range(at: date)?.color ?? .primary }

    var body: some View {
        content.complicationBackground()
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline:
            if metric == .loop, let loopDate = snapshot.loopDate {
                Text(snapshot.line(.bg, at: date) + " · ") + Text(loopDate, style: .relative)
            } else {
                Text(snapshot.line(metric, at: date))
            }
        case .accessoryCorner:
            corner
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            metric == .glance ? AnyView(miniGlance) : AnyView(rectangular)
        default:
            Text(snapshot.value(metric, at: date))
        }
    }

    // The tip stays empty except for the loop ring, which is information rather than decoration.
    @ViewBuilder private var corner: some View {
        let label = Text(snapshot.line(metric, at: date, corner: true))
        switch metric {
        case .loop:
            Circle()
                .strokeBorder(snapshot.freshness(at: date).color, lineWidth: 3)
                .widgetAccentable()
                .widgetLabel { label.font(.system(size: 22, weight: .bold, design: .rounded)) }
        case .bg:
            Color.clear.widgetLabel { label.font(.system(size: 22, weight: .bold, design: .rounded)) }
        default:
            Color.clear.widgetLabel { label }
        }
    }

    @ViewBuilder private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if metric == .loop || metric == .glance {
                Circle()
                    .strokeBorder(snapshot.freshness(at: date).color, lineWidth: 3)
                    .widgetAccentable()
            }
            VStack(spacing: -1) {
                if metric == .glance {
                    Text(snapshot.value(.bg, at: date))
                        .font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(bgColor)
                    Text(snapshot.iob(at: date) ?? GlanceComplicationSnapshot.dash).font(.system(size: 11, weight: .medium))
                } else if metric == .bg || metric == .loop {
                    Text(snapshot.value(metric, at: date))
                        .font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(bgColor)
                    Text(snapshot.trend(at: date)).font(.system(size: 12, weight: .medium))
                } else {
                    Text(snapshot.caption(metric)).font(.system(size: 11, weight: .medium)).widgetAccentable()
                    Text(snapshot.value(metric, at: date))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                }
            }
            .minimumScaleFactor(0.5).lineLimit(1)
            .padding(4)
        }
    }

    private var loopAge: some View {
        Group {
            if let loopDate = snapshot.loopDate {
                Text(loopDate, style: .relative)
            } else {
                Text(GlanceComplicationSnapshot.dash)
            }
        }
        .font(.caption2)
        .foregroundStyle(snapshot.freshness(at: date).color)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(metric.title).font(.headline).widgetAccentable()
            Text(metric == .override ? snapshot.value(.override, at: date) : snapshot.line(metric, at: date))
                .font(.body).minimumScaleFactor(0.6).lineLimit(1)
            loopAge
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The glance in three lines: BG → eventual, the loop's numbers, then override and loop age.
    private var miniGlance: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(snapshot.bgWithTrend(at: date)).font(.headline).foregroundStyle(bgColor).widgetAccentable()
                Text(snapshot.miniGlanceEventual(at: date)).font(.headline)
                Spacer(minLength: 0)
                // Who holds the pod, by shape rather than colour (tinted faces drop colour).
                Text(snapshot.watchHasPod ? "⌚︎" : "📱").font(.caption2)
            }
            Text(snapshot.miniGlanceNumbers(at: date))
                .font(.caption).minimumScaleFactor(0.6).lineLimit(1)
            HStack(spacing: 4) {
                if let label = snapshot.overrideLabel {
                    Text(label).font(.caption2).lineLimit(1)
                }
                loopAge
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LoopGlanceWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: GlanceComplicationKind.kind, intent: GlanceMetricIntent.self, provider: GlanceProvider()) { entry in
            GlanceComplicationView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("Loop Glance", comment: "Watch complication name: values from the Sport glance"))
        .description(NSLocalizedString("A value from Loop's glance: glucose, eventual, IOB, COB, temp basal, loop status or override.", comment: "Watch complication description: Loop Glance"))
        .supportedFamilies([.accessoryInline, .accessoryCorner, .accessoryCircular, .accessoryRectangular])
    }
}
