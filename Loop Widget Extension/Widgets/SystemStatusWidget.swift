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

struct SystemStatusWidgetEntryView : View {
    
    @Environment(\.widgetFamily) private var widgetFamily
    
    var entry: StatusWidgetTimelineProvider.Entry
    
    var freshness: LoopCompletionFreshness {
        let lastLoopCompleted = entry.lastLoopCompleted ?? Date().addingTimeInterval(.minutes(16))
        let age = abs(min(0, lastLoopCompleted.timeIntervalSinceNow))
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
                .background(
                    ContainerRelativeShape()
                        .fill(Color("WidgetSecondaryBackground"))
                )
                
                HStack(alignment: .center, spacing: 0) {
                    PumpView(entry: entry)
                        .frame(maxWidth: .infinity, alignment: .center)

                    EventualGlucoseView(entry: entry)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .padding(.vertical, 5)
                .background(
                    ContainerRelativeShape()
                        .fill(Color("WidgetSecondaryBackground"))
                )
            }
            
            if widgetFamily != .systemSmall {
                VStack(alignment: .center, spacing: 5) {
                    HStack(alignment: .center, spacing: 5) {
                        SystemActionLink(to: .carbEntry)
                        
                        SystemActionLink(to: .bolus)
                    }
                    
                    HStack(alignment: .center, spacing: 5) {
                        if entry.preMealPresetAllowed {
                            SystemActionLink(to: .preMeal, active: entry.preMealPresetActive)
                        }
                        
                        SystemActionLink(to: .customPreset, active: entry.customPresetActive)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .foregroundColor(entry.contextIsStale ? Color(UIColor.systemGray3) : nil)
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
