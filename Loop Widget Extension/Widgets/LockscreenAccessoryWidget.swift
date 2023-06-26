//
//  LockscreenAccessoryWidget.swift
//  Loop Widget Extension
//
//  Created by Cameron Ingham on 6/26/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import LoopUI
import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 16.0, *)
struct LockscreenAccessoryWidgetEntryView : View {
    
    @Environment(\.widgetFamily) private var widgetFamily
    
    var entry: StatusWidgetTimelineProvider.Entry

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if widgetFamily == .accessoryRectangular {
                LoopCircleView(entry: entry)
                    .scaleEffect(0.75)
            }

            GlucoseView(entry: entry)
        }
        .widgetBackground()
    }
}

@available(iOSApplicationExtension 16.0, *)
struct LockscreenAccessoryWidget: Widget {
    let kind: String = "LockscreenAccessoryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatusWidgetTimelineProvider()) { entry in
            LockscreenAccessoryWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Loop Accessory Widget")
        .description("See your current blood glucose.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}
