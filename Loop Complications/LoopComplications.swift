//
//  LoopComplications.swift
//  Loop Complications (watchOS widget extension)
//
//  Loop's watch complications on WidgetKit, replacing the ClockKit ones (ClockKit is deprecated and
//  current watchOS no longer takes new ClockKit complications). The same two as before:
//  "Loop Status" — the reading, its trend and the loop's freshness — and "Glucose Graph" — the
//  reading over the chart of recent and predicted glucose. The watch app publishes a
//  ComplicationSnapshot (and the graph image) to the shared app group and asks WidgetKit to reload;
//  this extension only reads and lays it out.
//

import SwiftUI
import WidgetKit

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: ComplicationSnapshot?
    /// The face editor's preview, which shows sample content.
    var isPreview = false
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: Date(), snapshot: .sample, isPreview: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(context.isPreview
                   ? ComplicationEntry(date: Date(), snapshot: .sample, isPreview: true)
                   : ComplicationEntry(date: Date(), snapshot: ComplicationSnapshot.load()))
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
        // Stock's layout: the reading and its trend, the chart under it across the slot.
        VStack(alignment: .leading, spacing: 1) {
            Text(snapshot.glucose(at: entry.date) + snapshot.trend(at: entry.date))
                .font(.headline)
                .widgetAccentable()
            GeometryReader { space in
                chart(in: space.size)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .complicationBackground()
    }

    /// The app draws the chart at the size this slot reports, so it fills the width on every watch.
    @ViewBuilder private func chart(in size: CGSize) -> some View {
        if entry.isPreview {
            SampleGraph()
        } else {
            let _ = ComplicationSnapshot.saveGraphSize(size)
            if snapshot.graphRenderedAt != nil, let url = ComplicationSnapshot.graphURL,
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height, alignment: .leading)
            }
        }
    }
}

/// The face editor's preview of the chart, in the real one's style: the target band, the recent
/// readings dotted, the prediction dashed. The real chart exists only once the watch app has drawn one.
private struct SampleGraph: View {
    var body: some View {
        GeometryReader { space in
            let w = space.size.width, h = space.size.height
            let target = h * 0.7
            // A rise and fall back to the target: readings to 60 % of the width, the prediction after.
            let point = { (x: CGFloat) -> CGPoint in
                CGPoint(x: x * w, y: x < 0.75 ? target - h * 0.55 * sin(.pi * x / 0.75) : target)
            }
            let curve = { (from: CGFloat, to: CGFloat) -> Path in
                Path { path in
                    path.move(to: point(from))
                    stride(from: from, through: to, by: 0.02).forEach { path.addLine(to: point($0)) }
                }
            }
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.blue.opacity(0.4))
                    .frame(width: w, height: h * 0.12)
                    .offset(y: target - h * 0.06)
                curve(0, 0.6).stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.5, 3]))
                curve(0.6, 1).stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
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
