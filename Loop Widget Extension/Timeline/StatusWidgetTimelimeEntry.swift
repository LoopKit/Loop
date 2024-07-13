//
//  StatusWidgetTimelimeEntry.swift
//  Loop Widget Extension
//
//  Created by Cameron Ingham on 6/26/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopCore
import LoopKit
import WidgetKit

struct StatusWidgetTimelimeEntry: TimelineEntry {
    var date: Date
    
    let contextUpdatedAt: Date
    
    let lastLoopCompleted: Date?
    let closeLoop: Bool
    
    let currentGlucose: GlucoseValue?
    let glucoseFetchedAt: Date?
    let delta: HKQuantity?
    let unit: HKUnit?
    let sensor: GlucoseDisplayableContext?

    let pumpHighlight: DeviceStatusHighlightContext?
    let netBasal: NetBasalContext?
    
    let eventualGlucose: GlucoseContext?
    
    let preMealPresetAllowed: Bool
    let preMealPresetActive: Bool
    let customPresetActive: Bool
    
    // Whether context data is old
    var contextIsStale: Bool {
        return (date - contextUpdatedAt) >= StatusWidgetTimelineProvider.stalenessAge
    }

    var glucoseStatusIsStale: Bool {
        guard let glucoseFetchedAt = glucoseFetchedAt else {
            return true
        }
        let glucoseStatusAge = date - glucoseFetchedAt
        return glucoseStatusAge >= StatusWidgetTimelineProvider.stalenessAge
    }

    var glucoseIsStale: Bool {
        guard let glucoseDate = currentGlucose?.startDate else {
            return true
        }
        let glucoseAge = date - glucoseDate

        return glucoseAge >= LoopCoreConstants.inputDataRecencyInterval
    }
}
