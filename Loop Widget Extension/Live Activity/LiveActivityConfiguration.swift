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

@available(iOS 16.2, *)
struct LiveActivityConfiguration: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GlucoseActivityAttributes.self) { context in
            // Create the presentation that appears on the Lock Screen and as a
            // banner on the Home Screen of devices that don't support the Dynamic Island.
            HStack {
                glucoseView(context)
                Spacer()
                pumpView(context)
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
                .stroke(getLoopColor(context.state.lastCompleted), lineWidth: 4)
                .rotationEffect(Angle(degrees: -126))
                .frame(width: 18, height: 18)
            
            Text("\(context.state.glucose) \(context.state.unit)")
                .font(.body)
            Text(context.state.delta)
                .font(.body)
                .foregroundStyle(Color(UIColor.secondaryLabel))
        }
    }
    
    @ViewBuilder
    private func pumpView(_ context: ActivityViewContext<GlucoseActivityAttributes>) -> some View {
        HStack(spacing: 10) {
            if let pumpHighlight = context.state.pumpHighlight {
                HStack {
                    Image(systemName: pumpHighlight.imageName)
                        .foregroundColor(pumpHighlight.state == .critical ? .critical : .warning)
                    Text(pumpHighlight.localizedMessage)
                        .fontWeight(.heavy)
                }
            }
            else if let netBasal = context.state.netBasal {
                BasalView(netBasal:
                    NetBasalContext(
                        rate: netBasal.rate,
                        percentage: netBasal.percentage,
                        start: netBasal.start,
                        end: netBasal.end
                    ),
                  isOld: false
                )
                
                VStack {
                    Text(LocalizedString("Eventual", comment: "No comment"))
                        .font(.footnote)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                    
                    Text("\(context.state.eventualGlucose) \(context.state.unit)")
                        .font(.subheadline)
                        .fontWeight(.heavy)
                }
            }

        }
    }
    
     func getLoopColor(_ age: Date?) -> Color {
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
}
