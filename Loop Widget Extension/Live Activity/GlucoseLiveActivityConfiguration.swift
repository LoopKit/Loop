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
                switch (context.attributes.mode) {
                case .spacious:
                    topRowSpaciousView(context)
                case .compact:
                    topRowCompactView(context)
                }
                
                Spacer()
                
                HStack {
                    bottomSpacer(border: false)
                    
                    let endIndex = context.state.bottomRow.endIndex - 1
                    ForEach(Array(context.state.bottomRow.enumerated()), id: \.element) { (index, item) in
                        switch (item.type) {
                        case .generic:
                            bottomItemGeneric(
                                title: LocalizedString(item.label, comment: "No comment"),
                                value: item.value,
                                unit: LocalizedString(item.unit, comment: "No comment")
                            )
                            
                        case .basal:
                            BasalViewActivity(percent: item.percentage, rate: item.rate)
                            
                        case .currentBg:
                            bottomItemCurrentBG(
                                title: LocalizedString(item.label, comment: "No comment"),
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
        } dynamicIsland: { _ in
            DynamicIsland {
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
                // Create the compact leading presentation.
                HStack{}
            } compactTrailing: {
                // Create the compact trailing presentation.
                HStack{}
            } minimal: {
                // Create the minimal presentation.
                HStack{}
            }
        }
    }
    
    @ViewBuilder
    private func topRowSpaciousView(_ context: ActivityViewContext<GlucoseActivityAttributes>) -> some View {
        HStack {
            HStack {
                loopIcon(context)
                
                Text("\(context.state.glucose)")
                    .font(.title)
                    .fontWeight(.heavy)
                    .padding(.leading, 16)
                
                if let trendImageName = getArrowImage(context.state.trendType) {
                    Image(systemName: trendImageName)
                        .font(.system(size: 24))
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Text("\(timeFormatter.string(from: context.state.date))")
                    .font(.subheadline)
                
                Text("\(context.state.delta)")
                    .font(.subheadline)
            }
        }
    }
    
    @ViewBuilder
    private func topRowCompactView(_ context: ActivityViewContext<GlucoseActivityAttributes>) -> some View {
        HStack(spacing: 20) {
            loopIcon(context)
            ChartView(glucoseSamples: context.state.glucoseSamples)
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
    private func bottomItemCurrentBG(title: String, value: String, trend: GlucoseTrend?) -> some View {
        VStack(alignment: .center) {
            HStack {
                Text(value)
                    .font(.title)
                    .fontWeight(.heavy)
                
                if let trend = trend, let trendImageName = getArrowImage(trend) {
                    Image(systemName: trendImageName)
                        .font(.system(size: 24))
                }
            }
        }
    }
    
    @ViewBuilder
    private func bottomSpacer(border: Bool) -> some View {
        Spacer()
        if (border) {
            Divider()
                .background(.secondary)
                .padding(.vertical, 10)
            Spacer()
        }
        
    }
    
    private func getArrowImage(_ trendType: GlucoseTrend?) -> String? {
        switch trendType {
        case .upUpUp:
//            return "arrow.double.up" -> This one isn't available anymore
            return "arrow.up"
        case .upUp:
            return "arrow.up"
        case .up:
            return "arrow.up.right"
        case .flat:
            return "arrow.right"
        case .down:
            return "arrow.down.right"
        case .downDown:
            return "arrow.down"
        case .downDownDown:
//            return "arrow.double.down.circle" -> This one isn't available anymore
            return "arrow.down"
        case .none:
            return nil
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
}
