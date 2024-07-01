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
                HStack {
                    glucoseView(context)
                    Spacer()
                    metaView(context)
                }
                
                Spacer()
                
                HStack {
                    bottomSpacer(border: false)
                    bottomItem(
                        value: context.state.iob,
                        unit: LocalizedString("U", comment: "No comment"),
                        title: LocalizedString("IOB", comment: "No comment")
                    )
                    bottomSpacer(border: true)
                    bottomItem(
                        value: context.state.cob,
                        unit: LocalizedString("g", comment: "No comment"),
                        title: LocalizedString("COB", comment: "No comment")
                    )
                    bottomSpacer(border: true)
                    basalView(context)
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
    private func glucoseView(_ context: ActivityViewContext<GlucoseActivityAttributes>) -> some View {
        HStack {
            Circle()
                .trim(from: context.state.isCloseLoop ? 0 : 0.2, to: 1)
                .stroke(getLoopColor(context.state.lastCompleted), lineWidth: 8)
                .rotationEffect(Angle(degrees: -126))
                .frame(width: 36, height: 36)
            
            Text("\(context.state.glucose)")
                .font(.title)
                .fontWeight(.heavy)
                .padding(.leading, 16)
            
            if let trendImageName = getArrowImage(context.state.trendType) {
                Image(systemName: trendImageName)
                    .font(.system(size: 24))
            }
        }
    }
    
    private func metaView(_ context: ActivityViewContext<GlucoseActivityAttributes>) -> some View {
        VStack(alignment: .trailing) {
            Text("\(timeFormatter.string(from: context.state.date))")
                .font(.subheadline)
            
            Text("\(context.state.delta)")
                .font(.subheadline)
        }
    }
    
    @ViewBuilder
    private func bottomItem(value: String, unit: String, title: String) -> some View {
        VStack(alignment: .center) {
            Text("\(value)\(unit)")
                .font(.headline)
                .fontWeight(.heavy)
            Text(title)
                .font(.subheadline)
        }
    }
    
    @ViewBuilder
    private func basalView(_ context: ActivityViewContext<GlucoseActivityAttributes>) -> some View {
        let netBasal = context.state.netBasal
        
        BasalViewActivity(percent: netBasal?.percentage ?? 0, rate: netBasal?.rate ?? 0)
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
             return Color.red
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
}
