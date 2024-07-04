//
//  LiveActivityManaer.swift
//  Loop
//
//  Created by Bastiaan Verhaar on 24/06/2024.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import LoopKitUI
import LoopKit
import LoopCore
import Foundation
import HealthKit
import ActivityKit

extension Notification.Name {
    static let LiveActivitySettingsChanged = Notification.Name(rawValue:  "com.loopKit.notification.LiveActivitySettingsChanged")
}

@available(iOS 16.2, *)
class GlucoseActivityManager {
    private let activityInfo = ActivityAuthorizationInfo()
    private var activity: Activity<GlucoseActivityAttributes>?
    private var activityChart: Activity<GlucoseChartActivityAttributes>?
    private let healthStore = HKHealthStore()
    
    private let glucoseStore: GlucoseStoreProtocol
    private let doseStore: DoseStoreProtocol
    
    private var lastGlucoseSample: GlucoseSampleValue?
    private var prevGlucoseSample: GlucoseSampleValue?
    
    private var startDate: Date = Date.now
    private var settings: LiveActivitySettings = UserDefaults.standard.liveActivity ?? LiveActivitySettings()
    
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
    private let timeFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .none
        dateFormatter.timeStyle = .short
        
        return dateFormatter
    }()
    
    init?(glucoseStore: GlucoseStoreProtocol, doseStore: DoseStoreProtocol) {
        guard self.activityInfo.areActivitiesEnabled else {
            print("ERROR: Activities are not enabled... :(")
            return nil
        }
        
        self.glucoseStore = glucoseStore
        self.doseStore = doseStore
        
        // Ensure settings exist
        if UserDefaults.standard.liveActivity == nil {
            self.settings = LiveActivitySettings()
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.settingsChanged), name: .LiveActivitySettingsChanged, object: nil)
        guard self.settings.enabled else {
            return
        }
        
        initEmptyActivity()
        initEmptyChartActivity()
        
        Task {
            await self.endUnknownActivities()
        }
    }
    
    public func update() {
        self.update(glucose: self.lastGlucoseSample)
    }
    
    public func update(glucose: GlucoseSampleValue?) {
        Task {
            if self.needsRecreation() {
                // activity is no longer visible or old. End it and try to push the update again
                await endActivity()
                update(glucose: glucose)
                return
            }
            
            guard let glucose = glucose, let unit = await self.healthStore.cachedPreferredUnits(for: .bloodGlucose) else {
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
            
            let glucoseSamples = self.getGlucoseSample(unit: unit)
            let bottomRow = self.getBottomRow(
                currentGlucose: current,
                delta: delta,
                statusContext: statusContext,
                glucoseFormatter: glucoseFormatter
            )

            let state = GlucoseActivityAttributes.ContentState(
                date: glucose.startDate,
                glucose: glucoseFormatter.string(from: current) ?? "??",
                trendType: statusContext?.glucoseDisplay?.trendType,
                delta: delta,
                isCloseLoop: statusContext?.isClosedLoop ?? false,
                lastCompleted: statusContext?.lastLoopCompleted,
                bottomRow: bottomRow,
                glucoseSamples: glucoseSamples
            )
            
            await self.activity?.update(ActivityContent(
                state: state,
                staleDate: min(state.date, Date.now).addingTimeInterval(.minutes(12))
            ))
            
            if let activityChart = self.activityChart {
                var predicatedGlucose: [Double] = []
                if let samples = statusContext?.predictedGlucose?.values {
                    predicatedGlucose = samples
                }
                
                let stateChart = GlucoseChartActivityAttributes.ContentState(
                    predicatedGlucose: predicatedGlucose,
                    predicatedStartDate: statusContext?.predictedGlucose?.startDate,
                    predicatedInterval: statusContext?.predictedGlucose?.interval,
                    glucoseSamples: glucoseSamples
                )
                
                await activityChart.update(ActivityContent(
                    state: stateChart,
                    staleDate: min(state.date, Date.now).addingTimeInterval(.minutes(12))
                ))
            }
            
            self.prevGlucoseSample = glucose
        }
    }
    
    @objc private func settingsChanged() {
        let newSettings = UserDefaults.standard.liveActivity ?? LiveActivitySettings()
        
        // Update live activity if needed
        if !newSettings.enabled, let activity = self.activity {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
                self.activity = nil
            }
        } else if newSettings.enabled && self.activity == nil {
            initEmptyActivity()
        }
        
        if !newSettings.enabled, let activityChart = self.activityChart {
            Task {
                await activityChart.end(nil, dismissalPolicy: .immediate)
                self.activityChart = nil
            }
        } else if newSettings.enabled && self.activityChart == nil {
            initEmptyChartActivity()
        }
        
        update()
        self.settings = newSettings
    }
    
    private func endUnknownActivities() async {
        for unknownActivity in Activity<GlucoseActivityAttributes>.activities
            .filter({ self.activity?.id != $0.id && self.activityChart?.id != $0.id })
        {
            await unknownActivity.end(nil, dismissalPolicy: .immediate)
        }
    }
    
    private func endActivity() async {
        let dynamicState = self.activity?.content.state
        let dynamicChartState = self.activityChart?.content.state
        
        await self.activity?.end(nil, dismissalPolicy: .immediate)
        await self.activityChart?.end(nil, dismissalPolicy: .immediate)
        for unknownActivity in Activity<GlucoseActivityAttributes>.activities {
            await unknownActivity.end(nil, dismissalPolicy: .immediate)
        }
        
        do {
            if let dynamicState = dynamicState {
                self.activity = try Activity.request(
                    attributes: GlucoseActivityAttributes(mode: self.settings.mode),
                    content: .init(state: dynamicState, staleDate: nil),
                    pushType: .token
                )
            }
            
            
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
        if !self.settings.enabled {
            return false
        }
        
        switch activity?.activityState {
        case .dismissed,
             .ended,
             .stale:
            return true
        case .active:
            return -startDate.timeIntervalSinceNow > .hours(1)
        default:
            return true
        }
    }
    
    private func getInsulinOnBoard() -> String {
        let updateGroup = DispatchGroup()
        var iob = "??"
        
        updateGroup.enter()
        self.doseStore.insulinOnBoard(at: Date.now) { result in
            switch (result) {
            case .failure:
                break
            case .success(let iobValue):
                iob = self.iobFormatter.string(from: iobValue.value) ?? "??"
                break
            }
            
            updateGroup.leave()
        }
        
        _ = updateGroup.wait(timeout: .distantFuture)
        return iob
    }
    
    private func getGlucoseSample(unit: HKUnit) -> [GlucoseSampleAttributes] {
        let updateGroup = DispatchGroup()
        var samples: [GlucoseSampleAttributes] = []
        
        updateGroup.enter()
        self.glucoseStore.getGlucoseSamples(start: Date.now.addingTimeInterval(.hours(-1)), end: Date.now) { result in
            switch (result) {
            case .failure:
                break
            case .success(let data):
                samples = data.suffix(30).map { item in
                    return GlucoseSampleAttributes(x: item.startDate, y: item.quantity.doubleValue(for: unit))
                }
                break
            }
            
            updateGroup.leave()
        }
        
        _ = updateGroup.wait(timeout: .distantFuture)
        return samples
    }
    
    private func getBottomRow(currentGlucose: Double, delta: String, statusContext: StatusExtensionContext?, glucoseFormatter: NumberFormatter) -> [BottomRowItem] {
        return self.settings.bottomRowConfiguration.map { type in
            switch(type) {
            case .iob:
                return BottomRowItem(label: "IOB", value: getInsulinOnBoard(), unit: "U")
                
            case .cob:
                var cob: String = "0"
                if let cobValue = statusContext?.carbsOnBoard {
                    cob = self.cobFormatter.string(from: cobValue) ?? "??"
                }
                return BottomRowItem(label: "COB", value: cob, unit: "g")
                
            case .basal:
                guard let netBasalContext = statusContext?.netBasal else {
                    return BottomRowItem(rate: 0, percentage: 0)
                }

                return BottomRowItem(rate: netBasalContext.rate, percentage: netBasalContext.percentage)
                
            case .currentBg:
                return BottomRowItem(label: "Current", value: "\(glucoseFormatter.string(from: currentGlucose) ?? "??")", trend: statusContext?.glucoseDisplay?.trendType)
                
            case .eventualBg:
                guard let eventual = statusContext?.predictedGlucose?.values.last else {
                    return BottomRowItem(label: "Event.", value: "??", unit: "")
                }
                
                return BottomRowItem(label: "Event.", value: glucoseFormatter.string(from: eventual) ?? "??", unit: "")
                
            case .deltaBg:
                return BottomRowItem(label: "Delta", value: delta, unit: "")
                
            case .updatedAt:
                return BottomRowItem(label: "Updated", value: timeFormatter.string(from: Date.now), unit: "")
            }
       }
    }
    
    private func initEmptyActivity() {
        do {
            let dynamicState = GlucoseActivityAttributes.ContentState(
                date: Date.now,
                glucose: "--",
                trendType: nil,
                delta: "",
                isCloseLoop: false,
                lastCompleted: nil,
                bottomRow: [],
                glucoseSamples: []
            )
            
            self.activity = try Activity.request(
                attributes: GlucoseActivityAttributes(mode: self.settings.mode),
                content: .init(state: dynamicState, staleDate: nil),
                pushType: .token
            )
        } catch {}
    }
    
    private func initEmptyChartActivity() {
        do {
            if self.settings.mode == .spacious {
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
            }
        } catch {}
    }
}
