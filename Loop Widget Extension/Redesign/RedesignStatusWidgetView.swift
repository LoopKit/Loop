//
//  RedesignStatusWidgetView.swift
//  Loop Widget Extension
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopCore
import LoopKit
import LoopAlgorithm
import SwiftUI
import WidgetKit

/// The home screen widget in the redesign's style: the Now screen's hero on the left, and in the medium
/// size the Now screen's actions on the right.
struct RedesignStatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    let entry: StatusWidgetTimelimeEntry

    private typealias P = LoopDesign.Palette

    var body: some View {
        HStack(spacing: LoopDesign.Space.s3) {
            status
            if family != .systemSmall {
                actions
            }
        }
        .padding(LoopDesign.Space.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .redesignWidgetBackground(renderingMode == .accented ? .clear : P.surfaceRaised)
    }

    // MARK: - Status

    private var status: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetStatusLine(status: WidgetDesign.LoopStatus(closedLoop: entry.closeLoop, lastCompleted: entry.lastLoopCompleted, now: entry.date))
                .opacity(entry.contextIsStale ? 0.6 : 1)
            Spacer(minLength: LoopDesign.Space.s1)
            reading
            Spacer(minLength: LoopDesign.Space.s2)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var reading: some View {
        if let glucose = entry.currentGlucose, let unit = entry.unit, !entry.glucoseIsStale {
            let value = glucose.quantity.doubleValue(for: unit)
            VStack(alignment: .leading, spacing: 0) {
                WidgetGlucoseValue(
                    value: NumberFormatter.glucoseFormatter(for: unit).string(from: value) ?? "–",
                    trend: entry.sensor?.trendType,
                    size: 40
                )
                if let range = WidgetDesign.Range(mgdl: glucose.quantity.doubleValue(for: .milligramsPerDeciliter)) {
                    HStack(spacing: LoopDesign.Space.s1) {
                        Circle().fill(range.color).frame(width: 7, height: 7)
                        Text(range.text)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(P.ink)
                } else {
                    Text(WidgetDesign.readingDetail(unit: unit.localizedShortUnitString, delta: delta(in: unit)))
                        .font(.caption)
                        .foregroundStyle(P.inkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .opacity(entry.glucoseStatusIsStale ? 0.6 : 1)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("No reading", comment: "Shown on the Now screen in place of the glucose value when there is no recent CGM reading"))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(P.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let date = entry.currentGlucose?.startDate {
                    Text(String(format: NSLocalizedString("Last reading %1$@ ago", comment: "Shown on the Now screen under No reading when the latest CGM reading is too old. (1: duration, e.g. 25m)"), WidgetDesign.duration(entry.date.timeIntervalSince(date))))
                        .font(.caption)
                        .foregroundStyle(P.inkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }

    private func delta(in unit: LoopUnit) -> String? {
        guard let delta = entry.delta else { return nil }
        return WidgetDesign.signed(delta.doubleValue(for: unit), decimals: unit == .millimolesPerLiter ? 1 : 0)
    }

    /// A device problem replaces the tiles, as notices lead the Now screen.
    @ViewBuilder
    private var footer: some View {
        if let notice = WidgetNotice.mostSerious([entry.pumpHighlight, entry.cgmHighlight]) {
            notice
        } else {
            HStack(spacing: 6) {
                WidgetTile(label: NSLocalizedString("COB", comment: "Abbreviation for carbs on board; label of a tile on the Now screen")) {
                    Text(entry.carbsOnBoard.map { String(format: NSLocalizedString("%1$@ g", comment: "Amount of carbohydrate in grams. (1: number)"), Self.number($0, decimals: 0)) } ?? "–")
                        .foregroundStyle(P.carbsInk)
                }
                WidgetTile(label: NSLocalizedString("Eventually", comment: "Short label above the glucose Loop predicts at the end of its prediction, in a small tile on the widget and Live Activity. Keep it to one short word, such as 'Forecast'.")) {
                    Text(eventual ?? "–")
                        .foregroundStyle(P.ink)
                }
            }
            .opacity(entry.contextIsStale ? 0.6 : 1)
        }
    }

    private var eventual: String? {
        guard let eventual = entry.eventualGlucose else { return nil }
        return NumberFormatter.glucoseFormatter(for: eventual.unit).string(from: eventual.quantity.doubleValue(for: eventual.unit))
    }

    static func number(_ value: Double, decimals: Int) -> String {
        value.formatted(.number.precision(.fractionLength(decimals)))
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                action(.carbEntry(nil), NSLocalizedString("Add carbs", comment: "Button on the Now screen that opens carb entry"), "fork.knife", fill: P.carbs, ink: P.onFill)
                action(.bolus, NSLocalizedString("Bolus", comment: "Button on the Now screen that opens the bolus screen"), "syringe.fill", fill: P.insulin, ink: P.onFill)
            }
            HStack(spacing: 6) {
                if entry.preMealPresetAllowed {
                    action(.preMeal,
                           entry.preMealPresetActive
                               ? NSLocalizedString("Pre-meal on", comment: "Presets button title on the Now screen while the pre-meal target is on")
                               : NSLocalizedString("Pre-meal", comment: "Menu item under Presets on the Now screen that turns on the pre-meal target"),
                           "fork.knife.circle",
                           fill: entry.preMealPresetActive ? P.accent.opacity(0.18) : WidgetDesign.sunken, ink: P.ink)
                }
                action(.customPresets, NSLocalizedString("Presets", comment: "Button on the Now screen that opens override presets (and pre-meal); also its VoiceOver label and menu item"), "slider.horizontal.3",
                       fill: entry.customPresetActive ? P.accent.opacity(0.18) : WidgetDesign.sunken, ink: P.ink)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func action(_ destination: Deeplink, _ title: String, _ symbol: String, fill: Color, ink: Color) -> some View {
        Link(destination: URL(string: "loop://\(destination.host.rawValue)")!) {
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 0)
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(renderingMode == .accented ? P.ink : ink)
            .padding(LoopDesign.Space.s2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                renderingMode == .accented ? AnyShapeStyle(.white.opacity(0.12)) : AnyShapeStyle(fill),
                in: RoundedRectangle(cornerRadius: LoopDesign.Radius.md, style: .continuous)
            )
        }
    }
}
