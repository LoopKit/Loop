//
//  LiveActivityManaer.swift
//  Loop
//
//  Created by Bastiaan Verhaar on 24/06/2024.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import LoopKitUI
import LoopKit
import Foundation
import HealthKit
import ActivityKit
import UIKit

@available(iOS 16.2, *)
class GlucoseActivityManager {
    private let activityInfo = ActivityAuthorizationInfo()
    private var activity: Activity<GlucoseActivityAttributes>
    private let healthStore = HKHealthStore()
    
    private var prevGlucoseSample: GlucoseSampleValue?
    private var startDate: Date = Date.now
    
    init?() {
        guard self.activityInfo.areActivitiesEnabled else {
            print("ERROR: Activities are not enabled... :(")
            return nil
        }
        
        do {
            let lastCompleted: Date? = nil
            let pumpHighlight: PumpHighlightAttributes? = nil
            let netBasal: NetBasalAttributes? = nil
            
            let state = GlucoseActivityAttributes()
            let dynamicState = GlucoseActivityAttributes.ContentState(
                date: Date.now,
                glucose: "--",
                delta: "",
                unit: "",
                isCloseLoop: false,
                lastCompleted: lastCompleted,
                pumpHighlight: pumpHighlight,
                netBasal: netBasal,
                eventualGlucose: "",
                predicatedGlucose: [],
                predicatedStartDate: nil,
                predicatedInterval: nil
            )
            
            self.activity = try Activity.request(
                attributes: state,
                content: .init(state: dynamicState, staleDate: nil),
                pushType: .token
            )
            
            Task {
                await self.endUnknownActivities()
            }
        } catch {
            print("ERROR: \(error.localizedDescription) :(")
            return nil
        }
    }
    
    public func update(glucose: GlucoseSampleValue?) {
        Task {
            if self.needsRecreation(), await UIApplication.shared.applicationState == .active {
                // activity is no longer visible or old. End it and try to push the update again
                await endActivity()
                update(glucose: glucose)
                return
            }
            
            guard let glucose = glucose, let unit = await healthStore.cachedPreferredUnits(for: .bloodGlucose) else {
                return
            }
            
            await self.endUnknownActivities()

            let statusContext = UserDefaults.appGroup?.statusExtensionContext
            let glucoseFormatter = NumberFormatter.glucoseFormatter(for: unit)
            
            let current = glucose.quantity.doubleValue(for: unit)
            var delta: String = "+ \(glucoseFormatter.string(from: Double(0)) ?? "")"
            if let prevSample = self.prevGlucoseSample {
                let deltaValue = current - (prevSample.quantity.doubleValue(for: unit))
                delta = "\(deltaValue < 0 ? "-" : "+") \(glucoseFormatter.string(from: abs(deltaValue)) ?? "")"
            }
            
            var pumpHighlight: PumpHighlightAttributes? = nil
            if let pumpStatusHightlight = statusContext?.pumpStatusHighlightContext {
                pumpHighlight = PumpHighlightAttributes(
                    localizedMessage: pumpStatusHightlight.localizedMessage,
                    imageName: pumpStatusHightlight.imageName,
                    state: pumpStatusHightlight.state)
            }
            
            var netBasal: NetBasalAttributes? = nil
            if let netBasalContext = statusContext?.netBasal {
                netBasal = NetBasalAttributes(
                    rate: netBasalContext.rate,
                    percentage: netBasalContext.percentage,
                    start: netBasalContext.start,
                    end: netBasalContext.end
                )
            }
            
            let state = GlucoseActivityAttributes.ContentState(
                date: glucose.startDate,
                glucose: glucoseFormatter.string(from: current) ?? "??",
                delta: delta,
                unit: unit.localizedShortUnitString,
                isCloseLoop: statusContext?.isClosedLoop ?? false,
                lastCompleted: statusContext?.lastLoopCompleted,
                pumpHighlight: pumpHighlight,
                netBasal: netBasal,
                eventualGlucose: glucoseFormatter.string(from: statusContext?.predictedGlucose?.values.last ?? 0) ?? "??",
                predicatedGlucose: statusContext?.predictedGlucose?.values ?? [],
                predicatedStartDate: statusContext?.predictedGlucose?.startDate,
                predicatedInterval: statusContext?.predictedGlucose?.interval
            )
            
            await self.activity.update(ActivityContent(
                state: state,
                staleDate: min(state.date, Date.now).addingTimeInterval(TimeInterval(6 * 60))
            ))
            
            self.prevGlucoseSample = glucose
        }
    }
    
    private func endUnknownActivities() async {
        for unknownActivity in Activity<GlucoseActivityAttributes>.activities
            .filter({ self.activity.id != $0.id })
        {
            await unknownActivity.end(nil, dismissalPolicy: .immediate)
        }
    }
    
    private func endActivity() async {
        let dynamicState = self.activity.content.state
        
        await self.activity.end(nil, dismissalPolicy: .immediate)
        for unknownActivity in Activity<GlucoseActivityAttributes>.activities {
            await unknownActivity.end(nil, dismissalPolicy: .immediate)
        }
        
        do {
            self.activity = try Activity.request(
                attributes: GlucoseActivityAttributes(),
                content: .init(state: dynamicState, staleDate: nil),
                pushType: .token
            )
            self.startDate = Date.now
        } catch {}

    }
    
    private func needsRecreation() -> Bool {
        switch activity.activityState {
        case .dismissed,
             .ended,
             .stale:
            return true
        case .active:
            return -startDate.timeIntervalSinceNow >
                TimeInterval(60 * 60)
        default:
            return true
        }
    }
}
