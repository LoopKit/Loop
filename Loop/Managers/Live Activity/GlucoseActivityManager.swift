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
    private let healthStore = HKHealthStore()
    
    private let glucoseStore: GlucoseStoreProtocol
    private let doseStore: DoseStoreProtocol
    private var loopSettings: LoopSettings
    
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
    
    init?(glucoseStore: GlucoseStoreProtocol, doseStore: DoseStoreProtocol, loopSettings: LoopSettings) {
        guard self.activityInfo.areActivitiesEnabled else {
            print("ERROR: Live Activities are not enabled...")
            return nil
        }
        
        self.glucoseStore = glucoseStore
        self.doseStore = doseStore
        self.loopSettings = loopSettings
        
        // Ensure settings exist
        if UserDefaults.standard.liveActivity == nil {
            self.settings = LiveActivitySettings()
        }
        
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(self.appMovedToForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(self.settingsChanged), name: .LiveActivitySettingsChanged, object: nil)
        guard self.settings.enabled else {
            return
        }
        
        initEmptyActivity(settings: self.settings)
        update()
        
        Task {
            await self.endUnknownActivities()
        }
    }
    
    public func update(loopSettings: LoopSettings) {
        self.loopSettings = loopSettings
        update()
    }
    
    private func update() {
        Task {
            if self.needsRecreation(), await UIApplication.shared.applicationState == .active {
                // activity is no longer visible or old. End it and try to push the update again
                print("INFO: Live Activities needs recreation")
                await endActivity()
                update()
                return
            }
            
            guard let unit = await self.healthStore.cachedPreferredUnits(for: .bloodGlucose) else {
                print("ERROR: No unit found...")
                return
            }
            
            await self.endUnknownActivities()

            let statusContext = UserDefaults.appGroup?.statusExtensionContext
            let glucoseFormatter = NumberFormatter.glucoseFormatter(for: unit)
            
            let glucoseSamples = self.getGlucoseSample(unit: unit)
            guard let currentGlucose = glucoseSamples.last else {
                print("ERROR: No glucose sample found...")
                return
            }
            
            let current = currentGlucose.quantity.doubleValue(for: unit)
            
            var delta: String = "+\(glucoseFormatter.string(from: Double(0)) ?? "")"
            if glucoseSamples.count > 1 {
                let prevSample = glucoseSamples[glucoseSamples.count - 2]
                let deltaValue = current - (prevSample.quantity.doubleValue(for: unit))
                delta = "\(deltaValue < 0 ? "-" : "+")\(glucoseFormatter.string(from: abs(deltaValue)) ?? "??")"
            }
            
            
            let bottomRow = self.getBottomRow(
                currentGlucose: current,
                delta: delta,
                statusContext: statusContext,
                glucoseFormatter: glucoseFormatter
            )
            
            var predicatedGlucose: [Double] = []
            if let samples = statusContext?.predictedGlucose?.values, settings.addPredictiveLine {
                predicatedGlucose = samples
            }
            
            var endDateChart: Date? = nil
            if predicatedGlucose.count == 0 {
                endDateChart = glucoseSamples.last?.startDate
            } else if let predictedGlucose = statusContext?.predictedGlucose {
                endDateChart = predictedGlucose.startDate.addingTimeInterval(.hours(4))
            }
            
            guard let endDateChart = endDateChart else {
                return
            }
            
            var presetContext: Preset? = nil
            if let override = self.loopSettings.preMealOverride ?? self.loopSettings.scheduleOverride, let start = glucoseSamples.first?.startDate {
                presetContext = Preset(
                    title: override.getTitle(),
                    startDate: max(override.startDate, start),
                    endDate: override.duration.isInfinite ? endDateChart : min(Date.now + override.duration.timeInterval, endDateChart),
                    minValue: override.settings.targetRange?.lowerBound.doubleValue(for: unit) ?? 0,
                    maxValue: override.settings.targetRange?.upperBound.doubleValue(for: unit) ?? 0
                )
            }
            
            var glucoseRanges: [GlucoseRangeValue] = []
            if let glucoseRangeSchedule = self.loopSettings.glucoseTargetRangeSchedule, let start = glucoseSamples.first?.startDate {
                for item in glucoseRangeSchedule.quantityBetween(start: start, end: endDateChart) {
                    let minValue = item.value.lowerBound.doubleValue(for: unit)
                    let maxValue = item.value.upperBound.doubleValue(for: unit)
                    let startDate = max(item.startDate, start)
                    let endDate = min(item.endDate, endDateChart)
                    
                    if let presetContext = presetContext {
                        if presetContext.startDate > startDate, presetContext.endDate < endDate {
                            // A preset is active during this schedule
                            glucoseRanges.append(GlucoseRangeValue(
                                id: UUID(),
                                minValue: minValue,
                                maxValue: maxValue,
                                startDate: startDate,
                                endDate: presetContext.startDate
                            ))
                            glucoseRanges.append(GlucoseRangeValue(
                                id: UUID(),
                                minValue: minValue,
                                maxValue: maxValue,
                                startDate: presetContext.endDate,
                                endDate: endDate
                            ))
                        } else if presetContext.endDate > startDate, presetContext.endDate < endDate {
                            // Cut off the start of the glucose target
                            glucoseRanges.append(GlucoseRangeValue(
                                id: UUID(),
                                minValue: minValue,
                                maxValue: maxValue,
                                startDate: presetContext.endDate,
                                endDate: endDate
                            ))
                        } else if presetContext.startDate < endDate, presetContext.startDate > startDate {
                            // Cut off the end of the glucose target
                            glucoseRanges.append(GlucoseRangeValue(
                                id: UUID(),
                                minValue: minValue,
                                maxValue: maxValue,
                                startDate: startDate,
                                endDate: presetContext.startDate
                            ))
                            if presetContext.endDate == endDateChart {
                                break
                            }
                        } else {
                            // No overlap with target and override
                            glucoseRanges.append(GlucoseRangeValue(
                                id: UUID(),
                                minValue: minValue,
                                maxValue: maxValue,
                                startDate: startDate,
                                endDate: endDate
                            ))
                        }
                    } else {
                        glucoseRanges.append(GlucoseRangeValue(
                            id: UUID(),
                            minValue: minValue,
                            maxValue: maxValue,
                            startDate: startDate,
                            endDate: endDate
                        ))
                    }
                }
            }

            let state = GlucoseActivityAttributes.ContentState(
                date: currentGlucose.startDate,
                ended: false,
                preset: presetContext,
                glucoseRanges: glucoseRanges,
                currentGlucose: current,
                trendType: statusContext?.glucoseDisplay?.trendType,
                delta: delta,
                isMmol: unit == HKUnit.millimolesPerLiter,
                isCloseLoop: statusContext?.isClosedLoop ?? false,
                lastCompleted: statusContext?.lastLoopCompleted,
                bottomRow: bottomRow,
                // In order to prevent maxSize errors, only allow the last 100 samples to be sent
                // Will most likely not be an issue, might be an issue for debugging/CGM simulator with 5sec interval
                glucoseSamples: glucoseSamples.suffix(100).map { item in
                    return GlucoseSampleAttributes(x: item.startDate, y: item.quantity.doubleValue(for: unit))
                },
                predicatedGlucose: predicatedGlucose,
                predicatedStartDate: statusContext?.predictedGlucose?.startDate,
                predicatedInterval: statusContext?.predictedGlucose?.interval
            )
            
            await self.activity?.update(ActivityContent(
                state: state,
                staleDate: Date.now.addingTimeInterval(.hours(1))
            ))
        }
    }
    
    @objc private func settingsChanged() {
        Task {
            let newSettings = UserDefaults.standard.liveActivity ?? LiveActivitySettings()
            
            // Update live activity if needed
            if !newSettings.enabled, let activity = self.activity {
                await activity.end(nil, dismissalPolicy: .immediate)
                self.activity = nil
                
                return
            } else if newSettings.enabled && self.activity == nil {
                initEmptyActivity(settings: newSettings)
                
            } else if
                newSettings.mode != self.settings.mode ||
                newSettings.addPredictiveLine != self.settings.addPredictiveLine ||
                newSettings.useLimits != self.settings.useLimits ||
                newSettings.lowerLimitChartMmol != self.settings.lowerLimitChartMmol ||
                newSettings.upperLimitChartMmol != self.settings.upperLimitChartMmol ||
                newSettings.lowerLimitChartMg != self.settings.lowerLimitChartMg ||
                newSettings.upperLimitChartMg != self.settings.upperLimitChartMg
            {
                await self.activity?.end(nil, dismissalPolicy: .immediate)
                self.activity = nil
                
                initEmptyActivity(settings: newSettings)
            }
            
            self.settings = newSettings
            update()
        }
    }
    
    @objc private func appMovedToForeground() {
        guard let activity = self.activity else {
            print("ERROR: appMovedToForeground: No Live activity found...")
            return
        }
        
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            await self.endUnknownActivities()
            self.activity = nil
            
            initEmptyActivity(settings: self.settings)
            update()
        }
    }
    
    private func endUnknownActivities() async {
        for unknownActivity in Activity<GlucoseActivityAttributes>.activities
            .filter({ self.activity?.id != $0.id })
        {
            await unknownActivity.end(nil, dismissalPolicy: .immediate)
        }
    }
    
    private func endActivity() async {
        let dynamicState = self.activity?.content.state
        
        await self.activity?.end(nil, dismissalPolicy: .immediate)
        for unknownActivity in Activity<GlucoseActivityAttributes>.activities {
            await unknownActivity.end(nil, dismissalPolicy: .immediate)
        }
        
        do {
            if let dynamicState = dynamicState {
                self.activity = try Activity.request(
                    attributes: GlucoseActivityAttributes(
                        mode: self.settings.mode,
                        addPredictiveLine: self.settings.addPredictiveLine,
                        useLimits: self.settings.useLimits,
                        upperLimitChartMmol: self.settings.upperLimitChartMmol,
                        lowerLimitChartMmol: self.settings.lowerLimitChartMmol,
                        upperLimitChartMg: self.settings.upperLimitChartMg,
                        lowerLimitChartMg: self.settings.lowerLimitChartMg
                    ),
                    content: .init(state: dynamicState, staleDate: nil),
                    pushType: .token
                )
            }
            self.startDate = Date.now
        } catch {
            print("ERROR: Error while ending live activity: \(error.localizedDescription)")
        }
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
    
    private func getGlucoseSample(unit: HKUnit) -> [StoredGlucoseSample] {
        let updateGroup = DispatchGroup()
        var samples: [StoredGlucoseSample] = []
        
        updateGroup.enter()
        
        // When in spacious mode, we want to show the predictive line
        // In compact mode, we only want to show the history
        let timeInterval: TimeInterval = self.settings.addPredictiveLine ? .hours(-2) : .hours(-6)
        self.glucoseStore.getGlucoseSamples(
            start: Date.now.addingTimeInterval(timeInterval),
            end: Date.now
        ) { result in
            switch (result) {
            case .failure:
                break
            case .success(let data):
                samples = data
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
                return BottomRowItem.generic(label: type.name(), value: getInsulinOnBoard(), unit: "U")
                
            case .cob:
                var cob: String = "0"
                if let cobValue = statusContext?.carbsOnBoard {
                    cob = self.cobFormatter.string(from: cobValue) ?? "??"
                }
                return BottomRowItem.generic(label: type.name(), value: cob, unit: "g")
                
            case .basal:
                guard let netBasalContext = statusContext?.netBasal else {
                    return BottomRowItem.basal(rate: 0, percentage: 0)
                }

                return BottomRowItem.basal(rate: netBasalContext.rate, percentage: netBasalContext.percentage)
                
            case .currentBg:
                return BottomRowItem.currentBg(label: type.name(), value: "\(glucoseFormatter.string(from: currentGlucose) ?? "??")", trend: statusContext?.glucoseDisplay?.trendType)
                
            case .eventualBg:
                guard let eventual = statusContext?.predictedGlucose?.values.last else {
                    return BottomRowItem.generic(label: type.name(), value: "??", unit: "")
                }
                
                return BottomRowItem.generic(label: type.name(), value: glucoseFormatter.string(from: eventual) ?? "??", unit: "")
                
            case .deltaBg:
                return BottomRowItem.generic(label: type.name(), value: delta, unit: "")
                
            case .loopCircle:
                return BottomRowItem.loopIcon()
                
            case .updatedAt:
                return BottomRowItem.generic(label: type.name(), value: timeFormatter.string(from: Date.now), unit: "")
            }
       }
    }
    
    private func initEmptyActivity(settings: LiveActivitySettings) {
        do {
            let dynamicState = GlucoseActivityAttributes.ContentState(
                date: Date.now,
                ended: true,
                preset: nil,
                glucoseRanges: [],
                currentGlucose: 0,
                trendType: nil,
                delta: "",
                isMmol: true,
                isCloseLoop: false,
                lastCompleted: nil,
                bottomRow: [],
                glucoseSamples: [],
                predicatedGlucose: [],
                predicatedStartDate: nil,
                predicatedInterval: nil
            )
            
            self.activity = try Activity.request(
                attributes: GlucoseActivityAttributes(
                    mode: settings.mode,
                    addPredictiveLine: settings.addPredictiveLine,
                    useLimits: settings.useLimits,
                    upperLimitChartMmol: settings.upperLimitChartMmol,
                    lowerLimitChartMmol: settings.lowerLimitChartMmol,
                    upperLimitChartMg: settings.upperLimitChartMg,
                    lowerLimitChartMg: settings.lowerLimitChartMg
                ),
                content: .init(state: dynamicState, staleDate: nil),
                pushType: .token
            )
        } catch {
            print("ERROR: Error while creating empty live activity: \(error.localizedDescription)")
        }
    }
}

extension TemporaryScheduleOverride {
    func getTitle() -> String {
        switch (self.context) {
        case .preset(let preset):
            return "\(preset.symbol) \(preset.name)"
        case .custom:
            return NSLocalizedString("Custom preset", comment: "The title of the cell indicating a generic custom preset is enabled")
        case .preMeal:
            return NSLocalizedString(" Pre-meal Preset", comment: "Status row title for premeal override enabled (leading space is to separate from symbol)")
        case .legacyWorkout:
            return ""
        }
    }
}
