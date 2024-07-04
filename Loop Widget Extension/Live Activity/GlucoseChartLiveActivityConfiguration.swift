//
//  ChartView.swift
//  Loop Widget Extension
//
//  Created by Bastiaan Verhaar on 27/06/2024.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import SwiftUI
import Charts
import WidgetKit

struct GlucoseChartLiveActivityConfiguration: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GlucoseChartActivityAttributes.self) { context in
            // Create the presentation that appears on the Lock Screen and as a
            // banner on the Home Screen of devices that don't support the Dynamic Island.
            HStack {
                ChartView(
                    glucoseSamples: context.state.glucoseSamples,
                    predicatedGlucose: context.state.predicatedGlucose,
                    predicatedStartDate: context.state.predicatedStartDate,
                    predicatedInterval: context.state.predicatedInterval
                )
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
}
