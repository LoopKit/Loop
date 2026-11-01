//
//  LoopComplications.swift
//  Loop Complications (watchOS widget extension)
//
//  Loop's watch complications on WidgetKit, replacing the ClockKit ones (ClockKit is deprecated and
//  current watchOS no longer takes new ClockKit complications). The same two as before:
//  "Loop Status" — the reading, its trend and the loop's freshness — and "Glucose Graph" — the
//  reading over the chart of recent and predicted glucose. The watch app publishes a
//  ComplicationSnapshot (with the graph's data) to the shared app group and asks WidgetKit to reload;
//  this extension only reads it, lays it out and draws the graph at its slot's size.
//

import SwiftUI
import WidgetKit

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: ComplicationSnapshot?
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(ComplicationEntry(date: Date(), snapshot: context.isPreview ? .sample : ComplicationSnapshot.load()))
    }

    /// Now, then each moment something visible changes on its own (the reading goes stale, the loop's
    /// colour turns). New data arrives by the watch app asking for a reload.
    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let now = Date()
        let snapshot = ComplicationSnapshot.load()
        let moments = [now] + (snapshot?.changeMoments(after: now) ?? [])
        completion(Timeline(entries: moments.map { ComplicationEntry(date: $0, snapshot: snapshot) }, policy: .never))
    }
}

// MARK: - Shared look

extension ComplicationSnapshot.Freshness {
    /// The watch app's colours: its "tint" asset, the warning yellow, the HIG red.
    var color: Color {
        switch self {
        case .fresh: return Color(red: 0.298, green: 0.851, blue: 0.392)
        case .aging: return .yellow
        case .stale: return Color(red: 1, green: 59 / 255, blue: 48 / 255)
        }
    }
}

extension View {
    /// watchOS 10+ draws a placeholder in place of any widget that does not declare a container
    /// background — every family except inline.
    func complicationBackground() -> some View {
        containerBackground(for: .widget) { Color.clear }
    }
}

// MARK: - Loop Status

struct LoopStatusView: View {
    let entry: ComplicationEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: ComplicationSnapshot { entry.snapshot ?? ComplicationSnapshot() }
    private var glucose: String { snapshot.glucose(at: entry.date) }
    private var trend: String { snapshot.trend(at: entry.date) }
    private var freshness: ComplicationSnapshot.Freshness { snapshot.freshness(at: entry.date) }

    var body: some View {
        content.complicationBackground()
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline:
            Text(snapshot.inline(at: entry.date))
        case .accessoryCorner:
            // The face curves the label along the bezel; the tip carries the loop's ring.
            Circle()
                .strokeBorder(freshness.color, lineWidth: 3)
                .widgetAccentable()
                .widgetLabel { Text(glucose + trend) }
        default:
            // Circular: stock's open gauge in the loop's colour, the reading inside, the trend below.
            ZStack {
                AccessoryWidgetBackground()
                Circle()
                    .strokeBorder(freshness.color, lineWidth: 3)
                    .widgetAccentable()
                VStack(spacing: -2) {
                    Text(glucose)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.5).lineLimit(1)
                    Text(trend).font(.system(size: 12, weight: .medium))
                }
                .padding(4)
            }
        }
    }
}

struct LoopStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LoopComplicationKind.loopStatus, provider: ComplicationProvider()) { entry in
            LoopStatusView(entry: entry)
        }
        // Plain Strings: an interpolated literal is formatted text, which WidgetKit rejects here.
        .configurationDisplayName(NSLocalizedString("Loop Status", comment: "Watch complication name: reading, trend and loop freshness"))
        .description(NSLocalizedString("Your glucose, its trend and how recently Loop ran.", comment: "Watch complication description: Loop Status"))
        .supportedFamilies([.accessoryInline, .accessoryCorner, .accessoryCircular])
    }
}

// MARK: - Glucose Graph

struct GlucoseGraphView: View {
    let entry: ComplicationEntry

    private var snapshot: ComplicationSnapshot { entry.snapshot ?? ComplicationSnapshot() }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(snapshot.glucose(at: entry.date) + snapshot.trend(at: entry.date))
                    .font(.headline)
                    .widgetAccentable()
                if let loopDate = snapshot.loopDate {
                    Text(loopDate, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(snapshot.freshness(at: entry.date).color)
                }
            }
            if let graph = snapshot.graph {
                GlucoseGraphCanvas(graph: graph, now: entry.date)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .complicationBackground()
    }
}

/// Stock's ClockKit chart (ComplicationChartManager), drawn at whatever size the slot leaves it.
struct GlucoseGraphCanvas: View {
    let graph: ComplicationGraph
    let now: Date

    /// The watch app's "glucose" asset.
    private static let glucoseColor = Color(red: 0.310, green: 0.678, blue: 0.973)

    var body: some View {
        Canvas { context, size in
            let start = now.addingTimeInterval(-ComplicationGraph.halfSpan)
            let end = now.addingTimeInterval(ComplicationGraph.halfSpan)
            let valueSpan = max(graph.glucoseMax - graph.glucoseMin, 1)

            func x(_ date: Date) -> CGFloat {
                CGFloat(date.timeIntervalSince(start) / end.timeIntervalSince(start)) * size.width
            }
            func y(_ value: Double) -> CGFloat {
                CGFloat((graph.glucoseMax - value) / valueSpan) * size.height
            }
            func fill(_ band: ComplicationGraph.Band, until bandEnd: Date, opacity: Double) {
                let left = x(max(start, band.start)), right = x(min(end, bandEnd))
                guard right > left else { return }
                let top = y(band.max)
                let rect = CGRect(x: left, y: top, width: right - left, height: max(y(band.min) - top, 2))
                context.fill(Path(rect), with: .color(Self.glucoseColor.opacity(opacity)))
            }

            for band in graph.targetRanges {
                fill(band, until: band.end, opacity: graph.override != nil ? 0.2 : 0.3)
            }
            if let override = graph.override {
                fill(override, until: override.end, opacity: 0.4)
                if end > override.end {
                    fill(override, until: end, opacity: 0.25)
                }
            }

            for point in graph.historical where point.date >= start && point.date <= end {
                let side: CGFloat = point.isManual ? 3 : 2
                context.fill(Path(CGRect(x: x(point.date), y: y(point.value), width: side, height: side)),
                             with: .color(point.isManual ? .red : Self.glucoseColor))
            }

            if graph.predicted.count > 2 {
                var path = Path()
                path.addLines(graph.predicted.map { CGPoint(x: x($0.date), y: y($0.value)) })
                context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 1, dash: [5, 3], dashPhase: 11))
            }

            let label = { (text: String) in Text(text).font(.system(size: 10)).foregroundColor(.white) }
            context.draw(label(graph.maxLabel), at: CGPoint(x: size.width - 2, y: 2), anchor: .topTrailing)
            context.draw(label(graph.minLabel), at: CGPoint(x: size.width - 2, y: size.height - 2), anchor: .bottomTrailing)
        }
    }
}

struct GlucoseGraphWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LoopComplicationKind.glucoseGraph, provider: ComplicationProvider()) { entry in
            GlucoseGraphView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("Glucose Graph", comment: "Watch complication name: glucose chart"))
        .description(NSLocalizedString("Your glucose over the last two hours and Loop's prediction.", comment: "Watch complication description: Glucose Graph"))
        .supportedFamilies([.accessoryRectangular])
    }
}

@main
struct LoopComplicationsBundle: WidgetBundle {
    var body: some Widget {
        LoopStatusWidget()
        GlucoseGraphWidget()
        LoopGlanceCornerWidget()
        LoopGlanceInlineWidget()
        LoopGlanceCircularWidget()
        LoopGlanceRectangularWidget()
    }
}
