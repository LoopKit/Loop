//
//  SystemStatusWidget.swift
//  Loop
//
//  Created by Noah Brauner on 8/15/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopKitUI
import LoopUI
import SwiftUI
import WidgetKit

struct SystemStatusWidgetEntryView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    
    var entry: StatusWidgetTimelimeEntry
    
    var freshness: LoopCompletionFreshness {
        var age: TimeInterval
        
        if entry.closeLoop {
            let lastLoopCompleted = entry.lastLoopCompleted ?? Date().addingTimeInterval(.minutes(16))
            age = abs(min(0, lastLoopCompleted.timeIntervalSinceNow))
        } else {
            let mostRecentGlucoseDataDate = entry.mostRecentGlucoseDataDate ?? Date().addingTimeInterval(.minutes(16))
            let mostRecentPumpDataDate = entry.mostRecentPumpDataDate ?? Date().addingTimeInterval(.minutes(16))
            age = abs(max(min(0, mostRecentGlucoseDataDate.timeIntervalSinceNow), min(0, mostRecentPumpDataDate.timeIntervalSinceNow)))
        }
        
        return LoopCompletionFreshness(age: age)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            VStack(alignment: .center, spacing: 5) {
                HStack(alignment: .center, spacing: 0) {
                    LoopCircleView(closedLoop: entry.closeLoop, freshness: freshness)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .environment(\.loopStatusColorPalette, .loopStatus)
                        .disabled(entry.contextIsStale)
                    
                    GlucoseView(entry: entry)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(5)
                .containerRelativeBackground()
                
                HStack(alignment: .center, spacing: 0) {
                    PumpView(entry: entry)
                        .frame(maxWidth: .infinity, alignment: .center)

                    EventualGlucoseView(entry: entry)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .padding(.vertical, 5)
                .containerRelativeBackground()
            }
            
            if widgetFamily != .systemSmall {
                VStack(alignment: .center, spacing: 5) {
                    HStack(alignment: .center, spacing: 5) {
                        DeeplinkView(destination: .carbEntry)
                        
                        DeeplinkView(destination: .bolus)
                    }
                    
                    HStack(alignment: .center, spacing: 5) {
                        if entry.preMealPresetAllowed {
                            DeeplinkView(destination: .preMeal, isActive: entry.preMealPresetActive)
                        }
                        
                        DeeplinkView(destination: .customPresets, isActive: entry.customPresetActive)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .foregroundColor(entry.contextIsStale ? .staleGray : nil)
        .padding(5)
        .widgetBackground()
    }
}

struct SystemStatusWidget: Widget {
    let kind: String = "SystemStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatusWidgetTimelineProvider()) { entry in
            SystemStatusWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Loop Status Widget")
        .description("See your current blood glucose and insulin delivery.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabledIfAvailable()
    }
}
