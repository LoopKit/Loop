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
    private var activityChart: Activity<GlucoseChartActivityAttributes>?
    private let healthStore = HKHealthStore()
    
    private let glucoseStore: GlucoseStoreProtocol
    private let doseStore: DoseStoreProtocol
    
    private var lastGlucoseSample: GlucoseSampleValue?
    private var prevGlucoseSample: GlucoseSampleValue?
    
    private var startDate: Date = Date.now
    
    private let cobFormatter: NumberFormatter =  {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .none
        return numberFormatter
    }()
    private let iobFormatter: NumberFormatter =  {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .none
        numberFormatter.maximumFractionDigits = 1
        numberFormatter.minimumFractionDigits = 1
        return numberFormatter
    }()
    
    init?(glucoseStore: GlucoseStoreProtocol, doseStore: DoseStoreProtocol) {
        guard self.activityInfo.areActivitiesEnabled else {
            print("ERROR: Activities are not enabled... :(")
            return nil
        }
        
        self.glucoseStore = glucoseStore
        self.doseStore = doseStore
        
        do {
            let lastCompleted: Date? = nil
            let pumpHighlight: PumpHighlightAttributes? = nil
            let netBasal: NetBasalAttributes? = nil
            
            let dynamicState = GlucoseActivityAttributes.ContentState(
                date: Date.now,
                glucose: "--",
                trendType: nil,
                delta: "",
                cob: "0",
                iob: "0",
                isCloseLoop: false,
                lastCompleted: lastCompleted,
                pumpHighlight: pumpHighlight,
                netBasal: netBasal,
                eventualGlucose: ""
            )
            
            self.activity = try Activity.request(
                attributes: GlucoseActivityAttributes(),
                content: .init(state: dynamicState, staleDate: nil),
                pushType: .token
            )
            
            let dynamicChartState = GlucoseChartActivityAttributes.ContentState(
                predicatedGlucose: [],
                predicatedStartDate: nil,
                predicatedInterval: nil,
                glucoseSamples: []
            )
            
            self.activityChart = try Activity.request(
                attributes: GlucoseChartActivityAttributes(),
                content: .init(state: dynamicChartState, staleDate: nil),
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
    
    public func update() {
        self.update(glucose: self.lastGlucoseSample)
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
            self.lastGlucoseSample = glucose
            
            var delta: String = "+\(glucoseFormatter.string(from: Double(0)) ?? "")"
            if let prevSample = self.prevGlucoseSample {
                let deltaValue = current - (prevSample.quantity.doubleValue(for: unit))
                delta = "\(deltaValue < 0 ? "-" : "+")\(glucoseFormatter.string(from: abs(deltaValue)) ?? "??")"
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
                    percentage: netBasalContext.percentage
                )
            }
            
            var predicatedGlucose: [Double] = []
            if let samples = statusContext?.predictedGlucose?.values {
                predicatedGlucose = samples
            }
            
            var cob: String = "0"
            if let cobValue = statusContext?.carbsOnBoard {
                cob = self.cobFormatter.string(from: cobValue) ?? "??"
            }
            
            let glucoseSamples = await self.getGlucoseSample(unit: unit)
            let iob = await self.getInsulinOnBoard()

            let state = GlucoseActivityAttributes.ContentState(
                date: glucose.startDate,
                glucose: glucoseFormatter.string(from: current) ?? "??",
                trendType: statusContext?.glucoseDisplay?.trendType,
                delta: delta,
                cob: cob,
                iob: iob,
                isCloseLoop: statusContext?.isClosedLoop ?? false,
                lastCompleted: statusContext?.lastLoopCompleted,
                pumpHighlight: pumpHighlight,
                netBasal: netBasal,
                eventualGlucose: glucoseFormatter.string(from: statusContext?.predictedGlucose?.values.last ?? 0) ?? "??"
            )
            
            await self.activity.update(ActivityContent(
                state: state,
                staleDate: min(state.date, Date.now).addingTimeInterval(TimeInterval(6 * 60))
            ))
            
            if let activityChart = self.activityChart {
                let stateChart = GlucoseChartActivityAttributes.ContentState(
                    predicatedGlucose: predicatedGlucose,
                    predicatedStartDate: statusContext?.predictedGlucose?.startDate,
                    predicatedInterval: statusContext?.predictedGlucose?.interval,
                    glucoseSamples: glucoseSamples
                )
                
                await activityChart.update(ActivityContent(
                    state: stateChart,
                    staleDate: min(state.date, Date.now).addingTimeInterval(TimeInterval(6 * 60))
                ))
            }
            
            self.prevGlucoseSample = glucose
        }
    }
    
    private func endUnknownActivities() async {
        for unknownActivity in Activity<GlucoseActivityAttributes>.activities
            .filter({ self.activity.id != $0.id && self.activityChart?.id != $0.id })
        {
            await unknownActivity.end(nil, dismissalPolicy: .immediate)
        }
    }
    
    private func endActivity() async {
        let dynamicState = self.activity.content.state
        let dynamicChartState = self.activityChart?.content.state
        
        await self.activity.end(nil, dismissalPolicy: .immediate)
        await self.activityChart?.end(nil, dismissalPolicy: .immediate)
        for unknownActivity in Activity<GlucoseActivityAttributes>.activities {
            await unknownActivity.end(nil, dismissalPolicy: .immediate)
        }
        
        do {
            self.activity = try Activity.request(
                attributes: GlucoseActivityAttributes(),
                content: .init(state: dynamicState, staleDate: nil),
                pushType: .token
            )
            
            
            if let dynamicChartState = dynamicChartState {
                self.activityChart = try Activity.request(
                    attributes: GlucoseChartActivityAttributes(),
                    content: .init(state: dynamicChartState, staleDate: nil),
                    pushType: .token
                )
            }
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
    
    private func getInsulinOnBoard() async -> String {
        return await withCheckedContinuation { continuation in
            self.doseStore.insulinOnBoard(at: Date.now) { result in
                switch (result) {
                case .failure:
                    continuation.resume(returning: "??")
                    break
                case .success(let iob):
                    continuation.resume(returning: self.iobFormatter.string(from: iob.value) ?? "??")
                    break
                }
            }
        }
    }
    
    private func getGlucoseSample(unit: HKUnit) async -> [GlucoseSampleAttributes] {
        return await withCheckedContinuation { continuation in
            self.glucoseStore.getGlucoseSamples(start: Date.now.addingTimeInterval(.hours(-1)), end: Date.now) { result in
                switch (result) {
                case .failure:
                    continuation.resume(returning: [])
                    break
                case .success(let data):
                    continuation.resume(returning: data.map { item in
                        return GlucoseSampleAttributes(x: item.startDate, y: item.quantity.doubleValue(for: unit))
                    })
                    return
                }
            }
        }
    }
}
