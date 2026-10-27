//
//  WidgetDesign.swift
//  Loop Widget Extension
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopCore
import LoopKit
import SwiftUI

/// The redesign's rules for the widget and Live Activity, so they read like the Now screen: the glucose
/// number is never tinted, low and high are said in words, and Loop's state is a dot with words.
enum WidgetDesign {
    /// The tile fill. The app's sunken grey disappears against a dark home screen widget, so the
    /// widget uses a translucent ink that reads on both light and dark.
    static let sunken = LoopDesign.Palette.ink.opacity(0.08)

    /// Matches the app's interface setting, which the app mirrors into the app group.
    static var useRedesign: Bool { UserDefaults.appGroup?.redesignEnabled ?? true }

    static func trendSymbol(_ trend: GlucoseTrend) -> String {
        switch trend {
        case .upUpUp: return "arrow.up.to.line"
        case .upUp: return "chevron.up.2"
        case .up: return "arrow.up"
        case .flat: return "arrow.right"
        case .down: return "arrow.down"
        case .downDown: return "chevron.down.2"
        case .downDownDown: return "arrow.down.to.line"
        }
    }

    enum Range {
        case urgentLow, low, high

        /// The Now screen's thresholds: below 54 and 70 mg/dL, above 250 mg/dL.
        init?(mgdl: Double) {
            switch mgdl {
            case ..<54: self = .urgentLow
            case ..<70: self = .low
            case 250.0.nextUp...: self = .high
            default: return nil
            }
        }

        init?(_ value: Double, isMmol: Bool) {
            let unit: HKUnit = isMmol ? .millimolesPerLiter : .milligramsPerDeciliter
            self.init(mgdl: HKQuantity(unit: unit, doubleValue: value).doubleValue(for: .milligramsPerDeciliter))
        }

        var text: String {
            switch self {
            case .urgentLow: return NSLocalizedString("Urgent low", comment: "Pill under the glucose value on the Now screen when glucose is below 54 mg/dL (3.0 mmol/L)")
            case .low: return NSLocalizedString("Low", comment: "Pill under the glucose value on the Now screen when glucose is below 70 mg/dL (3.9 mmol/L)")
            case .high: return NSLocalizedString("High", comment: "Pill under the glucose value on the Now screen when glucose is above 250 mg/dL (13.9 mmol/L)")
            }
        }

        var color: Color {
            self == .high ? LoopDesign.Palette.statusWarning : LoopDesign.Palette.statusCritical
        }
    }

    /// Loop's state as on the Now pill. The time of the last run stands in for the Now screen's age,
    /// because a widget isn't redrawn every minute and an age would go stale on screen.
    struct LoopStatus {
        let text: String
        let color: Color

        init(closedLoop: Bool, lastCompleted: Date?, now: Date = Date()) {
            typealias P = LoopDesign.Palette
            guard let lastCompleted else {
                text = closedLoop
                    ? NSLocalizedString("Closed loop · not run yet", comment: "Status pill on the Now screen when closed loop is on but Loop hasn't completed a run yet")
                    : NSLocalizedString("Open loop · not run yet", comment: "Status pill on the Now screen when closed loop is off and Loop hasn't completed a run yet")
                color = P.inkMuted
                return
            }
            let age = max(0, now.timeIntervalSince(lastCompleted))
            if LoopCompletionFreshness(age: age) == .stale {
                text = String(format: NSLocalizedString("Loop hasn't run for %1$@", comment: "Notice title on the Now screen when Loop hasn't completed a run recently. (1: duration, e.g. 25m)"), WidgetDesign.duration(age))
                color = P.statusWarning
                return
            }
            let time = lastCompleted.formatted(date: .omitted, time: .shortened)
            if closedLoop {
                text = String(format: NSLocalizedString("Closed loop · %1$@", comment: "Status pill on the Now screen: closed loop is on. (1: how long ago Loop last ran, e.g. 2m)"), time)
                color = LoopCompletionFreshness(age: age) == .fresh ? P.statusAutomated : P.statusWarning
            } else {
                text = String(format: NSLocalizedString("Open loop · %1$@", comment: "Status pill on the Now screen: closed loop is off. (1: how long ago Loop last ran, e.g. 2m)"), time)
                color = P.inkMuted
            }
        }
    }

    static func duration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = interval >= 3600 ? [.hour, .minute] : [.minute]
        formatter.maximumUnitCount = 2
        return formatter.string(from: interval) ?? ""
    }

    /// "mmol/L · +0.2 in 5 min", as under the number on the Now screen.
    static func readingDetail(unit: String, delta: String?) -> String {
        guard let delta, !delta.isEmpty else { return unit }
        return String(format: NSLocalizedString("%1$@ · %2$@ in 5 min", comment: "Under the glucose value on the Now screen: the glucose unit and how much glucose changed over 5 minutes. (1: glucose unit, e.g. mmol/L; 2: signed change, e.g. +0.3)"), unit, delta)
    }

    static func signed(_ value: Double, decimals: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        formatter.positivePrefix = formatter.plusSign
        return formatter.string(from: NSNumber(value: value)) ?? ""
    }
}

/// The status dot with words, as on the Now screen's first pill.
struct WidgetStatusLine: View {
    let status: WidgetDesign.LoopStatus
    var font: Font = LoopDesign.Typeface.footnote.weight(.medium)

    var body: some View {
        HStack(spacing: LoopDesign.Space.s1) {
            Circle().fill(status.color).frame(width: 7, height: 7)
            Text(status.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(font)
        .foregroundStyle(LoopDesign.Palette.ink)
    }
}

/// The glucose number with its trend arrow, in the Now hero's type.
struct WidgetGlucoseValue: View {
    let value: String
    let trend: GlucoseTrend?
    var size: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: size * 0.12) {
            Text(value)
                .font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(LoopDesign.Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
            if let trend {
                Image(systemName: WidgetDesign.trendSymbol(trend))
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(LoopDesign.Palette.glucose)
                    .accessibilityLabel(trend.localizedDescription)
            }
        }
    }
}

/// A sunken tile with a label over a value, the widget-sized `ValueTile`.
struct WidgetTile<Value: View>: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let label: String
    /// Label and value on one line, where height is short (the Live Activity has 160 points).
    var inline = false
    @ViewBuilder var value: Value

    var body: some View {
        let layout = inline
            ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: LoopDesign.Space.s1))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 1))
        layout {
            Text(label)
                .font(.caption2)
                .foregroundStyle(LoopDesign.Palette.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            value
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, LoopDesign.Space.s2)
        .padding(.vertical, inline ? 5 : 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            renderingMode == .accented ? AnyShapeStyle(.white.opacity(0.12)) : AnyShapeStyle(WidgetDesign.sunken),
            in: RoundedRectangle(cornerRadius: LoopDesign.Radius.md, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

/// A device problem said in words, as in the Now screen's notices.
struct WidgetNotice: View {
    let message: String
    let symbol: String
    let state: DeviceStatusHighlightState

    /// Critical first, then warnings, then information such as a sensor warming up.
    static func mostSerious(_ highlights: [DeviceStatusHighlightContext?]) -> WidgetNotice? {
        let rank: (DeviceStatusHighlightState) -> Int = { $0 == .critical ? 0 : $0 == .warning ? 1 : 2 }
        guard let highlight = highlights.compactMap({ $0 }).min(by: { rank($0.state) < rank($1.state) }) else { return nil }
        return WidgetNotice(message: highlight.localizedMessage, symbol: highlight.imageName, state: highlight.state)
    }

    private var tint: Color {
        switch state {
        case .critical: return LoopDesign.Palette.statusCritical
        case .warning: return LoopDesign.Palette.statusWarning
        default: return LoopDesign.Palette.glucose
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            Text(message.replacingOccurrences(of: "\n", with: " "))
                .font(.caption.weight(.semibold))
                .foregroundStyle(LoopDesign.Palette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, LoopDesign.Space.s2)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            tint.opacity(0.18),
            in: RoundedRectangle(cornerRadius: LoopDesign.Radius.md, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// The widget's container background, in the colour of a Now screen card.
    @ViewBuilder
    func redesignWidgetBackground(_ color: Color) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) { color }
        } else {
            background { color }
        }
    }
}
