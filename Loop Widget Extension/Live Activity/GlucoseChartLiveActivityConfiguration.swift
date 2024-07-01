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
                chartView(context)
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
    private func chartView(_ context: ActivityViewContext<GlucoseChartActivityAttributes>) -> some View {
        let glucoseSampleData = ChartValues.convert(data: context.state.glucoseSamples)
        let predicatedData = ChartValues.convert(
            data: context.state.predicatedGlucose,
            startDate: context.state.predicatedStartDate ?? Date.now,
            interval: context.state.predicatedInterval ?? .minutes(5)
        )
        
        let lowerBound = min(4, glucoseSampleData.min { $0.y < $1.y }?.y ?? 0, predicatedData.min { $0.y < $1.y }?.y ?? 0)
        let upperBound = max(10, glucoseSampleData.max { $0.y < $1.y }?.y ?? 0, predicatedData.max { $0.y < $1.y }?.y ?? 0)

        Chart {
            ForEach(glucoseSampleData) { item in
                PointMark (x: .value("Date", item.x),
                          y: .value("Glucose level", item.y)
                )
                .symbolSize(20)
            }
            
            ForEach(predicatedData) { item in
                LineMark (x: .value("Date", item.x),
                          y: .value("Glucose level", item.y)
                )
                .lineStyle(StrokeStyle(lineWidth: 3, dash: [2, 3]))
            }
        }
            .chartYScale(domain: [lowerBound, upperBound])
    }
}
