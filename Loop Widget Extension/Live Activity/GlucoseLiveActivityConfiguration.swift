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
    private let timeFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .none
        dateFormatter.timeStyle = .short
        
        return dateFormatter
    }()
    
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GlucoseActivityAttributes.self) { context in
            // Create the presentation that appears on the Lock Screen and as a
            // banner on the Home Screen of devices that don't support the Dynamic Island.
            VStack {
                HStack(spacing: 15) {
                    loopIcon(context)
                    if context.attributes.addPredictiveLine {
                        ChartView(
                            glucoseSamples: context.state.glucoseSamples,
                            predicatedGlucose: context.state.predicatedGlucose,
                            predicatedStartDate: context.state.predicatedStartDate,
                            predicatedInterval: context.state.predicatedInterval,
                            lowerLimit: context.state.isMmol ? context.attributes.lowerLimitChartMmol : context.attributes.lowerLimitChartMg,
                            upperLimit: context.state.isMmol ? context.attributes.upperLimitChartMmol : context.attributes.upperLimitChartMg
                        )
                            .frame(height: 85)
                    } else {
                        ChartView(
                            glucoseSamples: context.state.glucoseSamples,
                            lowerLimit: context.state.isMmol ? context.attributes.lowerLimitChartMmol : context.attributes.lowerLimitChartMg,
                            upperLimit: context.state.isMmol ? context.attributes.upperLimitChartMmol : context.attributes.upperLimitChartMg
                        )
                            .frame(height: 85)
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
                                trend: item.trend
                            )
                        }
                        
                        if index != endIndex {
                            bottomSpacer(border: true)
                        }
                    }
                    
                    bottomSpacer(border: false)
                }
            }
                .privacySensitive()
                .padding(.all, 15)
                .background(BackgroundStyle.background.opacity(0.4))
                .activityBackgroundTint(Color.clear)
        } dynamicIsland: { context in
            let glucoseFormatter = NumberFormatter.glucoseFormatter(for: context.state.isMmol ? HKUnit.millimolesPerLiter : HKUnit.milligramsPerDeciliter)
            
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack{}
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack{}
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack{}
                }
            } compactLeading: {
                Text("\(glucoseFormatter.string(from: context.state.currentGlucose) ?? "??")\(getArrowImage(context.state.trendType))")
                    .foregroundStyle(getGlucoseColor(context.state.currentGlucose))
                    .minimumScaleFactor(0.1)
            } compactTrailing: {
                Text(context.state.delta)
                    .foregroundStyle(Color(white: 0.9))
                    .minimumScaleFactor(0.1)
            } minimal: {
                Text(glucoseFormatter.string(from: context.state.currentGlucose) ?? "??")
                    .foregroundStyle(getGlucoseColor(context.state.currentGlucose))
                    .minimumScaleFactor(0.1)
            }
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
                .fontWeight(.heavy)
            Text(title)
                .font(.subheadline)
        }
    }
    
    @ViewBuilder
    private func bottomItemCurrentBG(value: String, trend: GlucoseTrend?) -> some View {
        VStack(alignment: .center) {
            HStack {
                Text(value + getArrowImage(trend))
                    .font(.title)
                    .fontWeight(.heavy)
            }
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
    
    private func getGlucoseColor(_ value: Double) -> Color {
        if value < 4 {
            return .red
        }
        
        if value > 10 {
            return .orange
        }
        
        return .green
    }
}
