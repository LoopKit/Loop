//
//  LoopGlanceWidget.swift
//  Loop Complications
//
//  The Sport glance as complications. The face editor asks for a slot's shape first, so there is one
//  widget per shape, each offering only its own options (GlanceOption); the option is an App Intent
//  parameter and each recommendation is its own face-editor choice. watchOS refreshes one complication
//  per app in the background, whatever the kinds, so the options pack what matters into one slot.
//
//  Style rules (learned on the wrist or in the simulator, 2026-09-30 – 10-09): plain-String descriptions; a
//  container background on every family; a corner's value rides its curved label (the face curves the
//  label, not the content); no titles — units label the values (112↗, 3m, 1.2U, 10g, +0.40U/h, →140); a
//  dash after 15 min; meaning is never carried by colour alone (tinted faces drop it); accent parts are
//  `widgetAccentable`; corner labels are drawn in capitals by watchOS.
//

import AppIntents
import os
import SwiftUI
import WidgetKit

struct GlanceMetricIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Loop Value"
    static let description = IntentDescription("Which of the glance's values this complication shows.")

    /// GlanceOption's raw value. A String, not an AppEnum: with an AppEnum parameter every face-editor
    /// recommendation rendered as the default (watchOS 26.5 simulator, 2026-10-04 — the intent arrived
    /// serialized, but App Intents resolved the parameter to nil).
    @Parameter(title: "Value")
    var metricID: String?

    func option(for shape: GlanceOption.Shape) -> GlanceOption { GlanceOption.chosen(metricID, for: shape) }

    init() {}

    init(option: GlanceOption) {
        self.metricID = option.rawValue
    }
}

struct GlanceEntry: TimelineEntry {
    let date: Date
    let option: GlanceOption
    let snapshot: GlanceComplicationSnapshot?
}

private let glanceWidgetLog = Logger(subsystem: "com.loopkit.Loop.Complications", category: "glance")

struct GlanceProvider: AppIntentTimelineProvider {
    let shape: GlanceOption.Shape

    func placeholder(in context: Context) -> GlanceEntry {
        GlanceEntry(date: Date(), option: GlanceOption.options(for: shape)[0], snapshot: .sample)
    }

    func snapshot(for configuration: GlanceMetricIntent, in context: Context) async -> GlanceEntry {
        let option = configuration.option(for: shape)
        glanceWidgetLog.notice("snapshot option=\(option.rawValue, privacy: .public) preview=\(context.isPreview, privacy: .public)")
        return GlanceEntry(date: Date(), option: option, snapshot: context.isPreview ? .sample : GlanceComplicationSnapshot.load())
    }

    /// Now, then each moment a value goes stale, the ring turns or an age ticks. New data comes by a reload.
    func timeline(for configuration: GlanceMetricIntent, in context: Context) async -> Timeline<GlanceEntry> {
        let now = Date()
        let option = configuration.option(for: shape)
        let snapshot = GlanceComplicationSnapshot.load()
        GlanceComplicationSnapshot.noteServed(option.rawValue, at: now)
        glanceWidgetLog.notice("timeline option=\(option.rawValue, privacy: .public)")
        let marks = (snapshot?.changeMoments(after: now) ?? []) + (snapshot?.loopAgeMarks(after: now) ?? [])
            + (snapshot?.bgAgeMarks(after: now) ?? [])
        let moments = [now] + Set(marks).sorted()
        return Timeline(entries: moments.map { GlanceEntry(date: $0, option: option, snapshot: snapshot) }, policy: .never)
    }

    /// watchOS has no widget configuration UI: each recommendation is a separate face-editor choice.
    func recommendations() -> [AppIntentRecommendation<GlanceMetricIntent>] {
        GlanceOption.options(for: shape).map { AppIntentRecommendation(intent: GlanceMetricIntent(option: $0), description: $0.title) }
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
    private var option: GlanceOption { entry.option }
    private var date: Date { entry.date }
    private var bgColor: Color { snapshot.range(at: date)?.color ?? .primary }

    var body: some View {
        content.complicationBackground()
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline:
            Text(snapshot.text(option.values, at: date, capitalised: true))
        case .accessoryCorner:
            holderIcon(size: 15).widgetLabel { cornerLabel }
        case .accessoryCircular:
            circular.widgetLabel { Text(snapshot.text(option.bezelValues, at: date, capitalised: true)) }
        case .accessoryRectangular:
            switch option {
            case .glance: glance
            case .balanced: balanced
            default: bigBG
            }
        default:
            Text(snapshot.bgWithTrend(at: date))
        }
    }

    /// The reading bold, the other values beside it, the age smallest.
    private var cornerLabel: Text {
        option.values.reduce(Text("")) { label, value in
            guard let part = snapshot.text(value, at: date, capitalised: true) else { return label }
            let piece: Text
            switch value {
            case .bg: piece = Text(part).font(.system(size: 22, weight: .bold, design: .rounded))
            case .age: piece = Text(" " + part).font(.system(size: 15, weight: .medium, design: .rounded))
            default: piece = Text(" " + part).font(.system(size: 18, weight: .semibold, design: .rounded))
            }
            return label + piece
        }
    }

    /// The loop's ring, the reading, and one more value beneath.
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Circle()
                .strokeBorder(snapshot.freshness(at: date).color, lineWidth: 3)
                .widgetAccentable()
            VStack(spacing: -1) {
                Text(snapshot.bgWithTrend(at: date))
                    .font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(bgColor)
                if let second = option.values.dropFirst().first, let text = snapshot.text(second, at: date) {
                    Text(text).font(.system(size: 13, weight: .medium, design: .rounded))
                }
            }
            .lineLimit(1)
            .padding(4)
        }
    }

    private var ageAndHolder: some View {
        HStack(spacing: 3) {
            holderIcon(size: 12)
            Text(snapshot.text(.age, at: date) ?? "")
                .font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
        }
        .lineLimit(1).fixedSize()
    }

    /// Bigger: the reading as large as the slot allows, who holds the pod and the reading's age beside it.
    private var bigBG: some View {
        HStack(spacing: 4) {
            holderIcon(size: 15)
            Text(snapshot.bgWithTrend(at: date))
                .font(.system(size: 60, weight: .semibold, design: .rounded))
                .foregroundStyle(bgColor).widgetAccentable()
                .minimumScaleFactor(0.3).lineLimit(1)
                .frame(maxWidth: .infinity)
            Text(snapshot.text(.age, at: date) ?? "")
                .font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                .lineLimit(1).fixedSize()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Between: the reading large, IOB and COB beneath.
    private var balanced: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.bgWithTrend(at: date))
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .foregroundStyle(bgColor).widgetAccentable()
                Spacer(minLength: 4)
                ageAndHolder
            }
            Text(snapshot.text([.iob, .cob], at: date))
                .font(.system(size: 20, weight: .medium, design: .rounded))
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// More: every value of the glance in three lines.
    private var glance: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(snapshot.text([.bg, .eventual], at: date)).font(.headline).foregroundStyle(bgColor).widgetAccentable()
                Spacer(minLength: 4)
                ageAndHolder
            }
            Text(snapshot.text([.iob, .cob, .temp], at: date))
                .font(.system(size: 15, weight: .medium, design: .rounded))
            Text(snapshot.text(.override, at: date) ?? "")
                .font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Who holds the pod: the watch (a loan) or the phone. By shape, not colour, so tinted faces keep it.
    private func holderIcon(size: CGFloat) -> some View {
        Image(systemName: snapshot.watchHasPod ? "applewatch" : "iphone")
            .font(.system(size: size, weight: .semibold)).foregroundStyle(.secondary)
    }
}

/// One widget per shape (a widget takes no parameters, so each shape is its own small type).
protocol LoopGlanceWidget: Widget {
    static var shape: GlanceOption.Shape { get }
}

extension LoopGlanceWidget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: GlanceComplicationKind.kind(Self.shape), intent: GlanceMetricIntent.self,
                               provider: GlanceProvider(shape: Self.shape)) { entry in
            GlanceComplicationView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("Loop Glance", comment: "Watch complication name: values from the Sport glance"))
        .description(NSLocalizedString("The reading, with insulin, carbs, its age and more as the slot allows.", comment: "Watch complication description: the Sport glance"))
        .supportedFamilies([Self.family])
    }

    private static var family: WidgetFamily {
        switch shape {
        case .corner: return .accessoryCorner
        case .inline: return .accessoryInline
        case .circular: return .accessoryCircular
        case .rectangular: return .accessoryRectangular
        }
    }
}

struct LoopGlanceCornerWidget: LoopGlanceWidget { static let shape = GlanceOption.Shape.corner }
struct LoopGlanceInlineWidget: LoopGlanceWidget { static let shape = GlanceOption.Shape.inline }
struct LoopGlanceCircularWidget: LoopGlanceWidget { static let shape = GlanceOption.Shape.circular }
struct LoopGlanceRectangularWidget: LoopGlanceWidget { static let shape = GlanceOption.Shape.rectangular }
