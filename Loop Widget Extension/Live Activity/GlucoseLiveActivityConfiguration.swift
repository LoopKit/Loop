//
//  LiveActivityConfiguration.swift
//  Loop Widget Extension
//
//  Created by Bastiaan Verhaar on 23/06/2024.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import ActivityKit
import LoopKit
import SwiftUI
import LoopCore
import WidgetKit
import Charts
import HealthKit

@available(iOS 16.2, *)
struct GlucoseLiveActivityConfiguration: Widget {
    var body: some WidgetConfiguration {
        if #available(iOS 18.0, *) {
            return ActivityConfiguration(for: GlucoseActivityAttributes.self) { context in
                lockScreenView(context: context)
            } dynamicIsland: { context in
                dynamicIslandView(context: context)
            }
            .supplementalActivityFamilies([.small])
        } else {
            return ActivityConfiguration(for: GlucoseActivityAttributes.self) { context in
                lockScreenView(context: context)
            } dynamicIsland: { context in
                dynamicIslandView(context: context)
            }
        }
    }

    // MARK: - Lock Screen View

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<GlucoseActivityAttributes>) -> some View {
        // Create the presentation that appears on the Lock Screen and as a
        // banner on the Home Screen of devices that don't support the Dynamic Island.
        if #available(iOS 18.0, *) {
            AdaptiveLockScreenView(context: context)
        } else {
            fullLockScreenView(context: context)
        }
    }

    @available(iOS 18.0, *)
    struct AdaptiveLockScreenView: View {
        let context: ActivityViewContext<GlucoseActivityAttributes>
        @Environment(\.activityFamily) private var activityFamily

        var body: some View {
            if activityFamily == .small {
                // CarPlay supplemental view - show only bottom row
                compactLockScreenView(context: context)
            } else {
                // Lock screen - show full view with chart
                fullLockScreenView(context: context)
            }
        }

        @ViewBuilder
        private func fullLockScreenView(context: ActivityViewContext<GlucoseActivityAttributes>) -> some View {
            GlucoseLiveActivityConfiguration().fullLockScreenView(context: context)
        }

        @ViewBuilder
        private func compactLockScreenView(context: ActivityViewContext<GlucoseActivityAttributes>) -> some View {
            GlucoseLiveActivityConfiguration().compactLockScreenView(context: context)
        }
    }

    @ViewBuilder
    private func fullLockScreenView(context: ActivityViewContext<GlucoseActivityAttributes>) -> some View {
        ZStack {
            VStack {
                if context.attributes.mode == .large {
                        HStack(spacing: 15) {
                            loopIcon(context)
                            if context.attributes.addPredictiveLine {
                                ChartView(
                                    glucoseSamples: context.state.glucoseSamples,
                                    predicatedGlucose: context.state.predicatedGlucose,
                                    predicatedStartDate: context.state.predicatedStartDate,
                                    predicatedInterval: context.state.predicatedInterval,
                                    useLimits: context.attributes.useLimits,
                                    lowerLimit: context.state.isMmol ? context.attributes.lowerLimitChartMmol : context.attributes.lowerLimitChartMg,
                                    upperLimit: context.state.isMmol ? context.attributes.upperLimitChartMmol : context.attributes.upperLimitChartMg,
                                    glucoseRanges: context.state.glucoseRanges,
                                    preset: context.state.preset,
                                    yAxisMarks: context.state.yAxisMarks
                                )
                                .frame(height: 85)
                            } else {
                                ChartView(
                                    glucoseSamples: context.state.glucoseSamples,
                                    useLimits: context.attributes.useLimits,
                                    lowerLimit: context.state.isMmol ? context.attributes.lowerLimitChartMmol : context.attributes.lowerLimitChartMg,
                                    upperLimit: context.state.isMmol ? context.attributes.upperLimitChartMmol : context.attributes.upperLimitChartMg,
                                    glucoseRanges: context.state.glucoseRanges,
                                    preset: context.state.preset,
                                    yAxisMarks: context.state.yAxisMarks
                                )
                                .frame(height: 85)
                            }
                        }
                    }
                    
                    HStack {
                        bottomSpacer(border: false)
                        
                        let endIndex = context.state.bottomRow.endIndex - 1
                        ForEach(Array(context.state.bottomRow.enumerated()), id: \.element) { (index, item) in
                            switch (item.type) {
                            case .generic:
                                bottomItemGeneric(
                                    title: item.label,
                                    value: item.value,
                                    unit: LocalizedString(item.unit, comment: "No comment")
                                )
                                
                            case .basal:
                                BasalViewActivity(percent: item.percentage, rate: item.rate)
                                
                            case .currentBg:
                                bottomItemCurrentBG(
                                    value: item.value,
                                    trend: item.trend,
                                    context: context
                                )
                                
                            case .loopCircle:
                                bottomItemLoopCircle(context: context)
                            }
                            
                            if index != endIndex {
                                bottomSpacer(border: true)
                            }
                        }
                        
                        bottomSpacer(border: false)
                    }
                }
                if context.state.ended {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(NSLocalizedString("Open the app to update the widget", comment: "No comment"))
                            Spacer()
                        }
                        Spacer()
                    }
                    .background(.ultraThinMaterial.opacity(0.8))
                    .padding(.all, -15)
                }
            }
                .privacySensitive()
                .padding(.all, 15)
                .background(BackgroundStyle.background.opacity(0.4))
                .activityBackgroundTint(Color.clear)
    }

    @ViewBuilder
    private func compactLockScreenView(context: ActivityViewContext<GlucoseActivityAttributes>) -> some View {
        /* Simple large display for CarPlay and Apple Watch - single row with Loop icon,
           current BG with trend, and eventual BG. Larger fonts for CarPlay readability,
           elements scale down on Watch to avoid truncation.
        */
        HStack(spacing: 0) {
            // Loop icon - color coded, least important (only color matters)
            // Scales down aggressively on narrow displays
            Circle()
                .trim(from: context.state.isCloseLoop ? 0 : 0.2, to: 1)
                .stroke(getLoopColor(context.state.lastCompleted), lineWidth: 6)
                .rotationEffect(Angle(degrees: -126))
                .frame(idealWidth: 36, idealHeight: 36)
                .frame(minWidth: 20, maxWidth: 36, minHeight:20, maxHeight: 36)
                .padding(.trailing, 8)
                .layoutPriority(0)  // Lowest priority - shrinks first before the text elements
            
            VStack(alignment: .leading, spacing: 0) {
                // Current BG with trend arrow + eventual BG - composed as single string so they scale together
                let glucoseFormatter = NumberFormatter.glucoseFormatter(for: context.state.isMmol ? HKUnit.millimolesPerLiter : HKUnit.milligramsPerDeciliter)
                let currentBG = (glucoseFormatter.string(from: context.state.currentGlucose) ?? "??") + getArrowImage(context.state.trendType)
                let eventualBG = context.state.bottomRow.first(where: { $0.label == NSLocalizedString("Event", comment: "") })?.value ?? ""
                let combinedText = currentBG + (eventualBG.isEmpty ? "" : "  " + eventualBG)

                Text(combinedText)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(!context.attributes.useLimits ? .primary : getGlucoseColor(context.state.currentGlucose, context: context))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                                  
                HStack() {
                    Text(context.state.delta)
                        .foregroundStyle(Color(white: 0.9))
                        .font(.system(size: 25))
                    Text(context.state.isMmol ? HKUnit.millimolesPerLiter.localizedShortUnitString : HKUnit.milligramsPerDeciliter.localizedShortUnitString)
                        .foregroundStyle(Color(white: 0.7))
                        .font(.subheadline)
                }
                .padding(.leading)
            }
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity)  // Allow HStack to use full available width
        .privacySensitive()
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Color.clear)
    }

    // MARK: - Dynamic Island View

    private func dynamicIslandView(context: ActivityViewContext<GlucoseActivityAttributes>) -> DynamicIsland {
        let glucoseFormatter = NumberFormatter.glucoseFormatter(for: context.state.isMmol ? HKUnit.millimolesPerLiter : HKUnit.milligramsPerDeciliter)

        return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(alignment: .center) {
                        loopIcon(context)
                            .frame(width: 40, height: 40, alignment: .trailing)
                        Spacer()
                        Text("\(glucoseFormatter.string(from: context.state.currentGlucose) ?? "??")\(getArrowImage(context.state.trendType))")
                            .foregroundStyle(getGlucoseColor(context.state.currentGlucose, context: context))
                            .font(.headline)
                            .fontWeight(.heavy)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack{
                        Text(context.state.delta)
                            .foregroundStyle(Color(white: 0.9))
                            .font(.headline)
                        Text(context.state.isMmol ? HKUnit.millimolesPerLiter.localizedShortUnitString : HKUnit.milligramsPerDeciliter.localizedShortUnitString)
                            .foregroundStyle(Color(white: 0.7))
                            .font(.subheadline)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.attributes.addPredictiveLine {
                        ChartView(
                            glucoseSamples: context.state.glucoseSamples,
                            predicatedGlucose: context.state.predicatedGlucose,
                            predicatedStartDate: context.state.predicatedStartDate,
                            predicatedInterval: context.state.predicatedInterval,
                            useLimits: context.attributes.useLimits,
                            lowerLimit: context.state.isMmol ? context.attributes.lowerLimitChartMmol : context.attributes.lowerLimitChartMg,
                            upperLimit: context.state.isMmol ? context.attributes.upperLimitChartMmol : context.attributes.upperLimitChartMg,
                            glucoseRanges: context.state.glucoseRanges,
                            preset: context.state.preset,
                            yAxisMarks: context.state.yAxisMarks
                        )
                            .frame(height: 75)
                    } else {
                        ChartView(
                            glucoseSamples: context.state.glucoseSamples,
                            useLimits: context.attributes.useLimits,
                            lowerLimit: context.state.isMmol ? context.attributes.lowerLimitChartMmol : context.attributes.lowerLimitChartMg,
                            upperLimit: context.state.isMmol ? context.attributes.upperLimitChartMmol : context.attributes.upperLimitChartMg,
                            glucoseRanges: context.state.glucoseRanges,
                            preset: context.state.preset,
                            yAxisMarks: context.state.yAxisMarks
                        )
                            .frame(height: 75)
                    }
                }
            } compactLeading: {
                Text("\(glucoseFormatter.string(from: context.state.currentGlucose) ?? "??")\(getArrowImage(context.state.trendType))")
                    .foregroundStyle(getGlucoseColor(context.state.currentGlucose, context: context))
                    .minimumScaleFactor(0.1)
            } compactTrailing: {
                Text(context.state.delta)
                    .foregroundStyle(Color(white: 0.9))
                    .minimumScaleFactor(0.1)
            } minimal: {
                Text(glucoseFormatter.string(from: context.state.currentGlucose) ?? "??")
                    .foregroundStyle(getGlucoseColor(context.state.currentGlucose, context: context))
                    .minimumScaleFactor(0.1)
            }
    }

    @ViewBuilder
    private func loopIcon(_ context: ActivityViewContext<GlucoseActivityAttributes>) -> some View {
        Circle()
            .trim(from: context.state.isCloseLoop ? 0 : 0.2, to: 1)
            .stroke(getLoopColor(context.state.lastCompleted), lineWidth: 8)
            .rotationEffect(Angle(degrees: -126))
            .frame(width: 36, height: 36)
    }
    
    @ViewBuilder
    private func bottomItemGeneric(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .center) {
            Text("\(value)\(unit)")
                .font(.headline)
                .foregroundStyle(.primary)
                .fontWeight(.heavy)
                .font(Font.body.leading(.tight))
            Text(title)
                .font(.subheadline)
        }
    }
    
    @ViewBuilder
    private func bottomItemCurrentBG(value: String, trend: GlucoseTrend?, context: ActivityViewContext<GlucoseActivityAttributes>) -> some View {
        VStack(alignment: .center) {
            HStack {
                Text(value + getArrowImage(trend))
                    .font(.title)
                    .foregroundStyle(!context.attributes.useLimits ? .primary : getGlucoseColor(context.state.currentGlucose, context: context))
                    .fontWeight(.heavy)
                    .font(Font.body.leading(.tight))
            }
        }
    }
    
    @ViewBuilder
    private func bottomItemLoopCircle(context: ActivityViewContext<GlucoseActivityAttributes>) -> some View {
        VStack(alignment: .center) {
            loopIcon(context)
        }
    }
    
    @ViewBuilder
    private func bottomSpacer(border: Bool) -> some View {
        Spacer()
        if (border) {
            Divider()
                .background(.secondary)
            Spacer()
        }
        
    }
    
    private func getArrowImage(_ trendType: GlucoseTrend?) -> String {
        switch trendType {
        case .upUpUp:
            return "\u{2191}\u{2191}" // ↑↑
        case .upUp:
            return "\u{2191}" // ↑
        case .up:
            return "\u{2197}" // ↗
        case .flat:
            return "\u{2192}" // →
        case .down:
            return "\u{2198}" // ↘
        case .downDown:
            return "\u{2193}" // ↓
        case .downDownDown:
            return "\u{2193}\u{2193}" // ↓↓
        case .none:
            return ""
        }
    }
    
    private func getLoopColor(_ age: Date?) -> Color {
        var freshness: LoopCompletionFreshness = .stale
        if let age = age {
            freshness = LoopCompletionFreshness(age: abs(min(0, age.timeIntervalSinceNow)))
        }
        
        switch freshness {
        case .fresh:
            return Color("fresh")
        case .aging:
            return Color("warning")
        case .stale:
            return .red
        }
    }
    
    private func getGlucoseColor(_ value: Double, context: ActivityViewContext<GlucoseActivityAttributes>) -> Color {
        guard context.attributes.useLimits else {
            return .primary
        }
        
        if
            context.state.isMmol && value < context.attributes.lowerLimitChartMmol ||
            !context.state.isMmol && value < context.attributes.lowerLimitChartMg
        {
            return .red
        }
        
        if
            context.state.isMmol && value > context.attributes.upperLimitChartMmol ||
            !context.state.isMmol && value > context.attributes.upperLimitChartMg
        {
            return .orange
        }
        
        return .green
    }

}
