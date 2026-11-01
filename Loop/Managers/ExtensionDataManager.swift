//
//  ExtensionDataManager.swift
//  Loop
//
//  Created by Bharat Mediratta on 11/25/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import LoopKit
import LoopCore

@MainActor
final class ExtensionDataManager {
    unowned let deviceManager: DeviceDataManager
    unowned let loopDataManager: LoopDataManager
    unowned let settingsManager: SettingsManager
    unowned let temporaryPresetsManager: TemporaryPresetsManager

    private var dataUpdatedObserver: NSObjectProtocol?
    private var pumpManagerChangedObserver: NSObjectProtocol?
    
    init(deviceDataManager: DeviceDataManager,
         loopDataManager: LoopDataManager,
         settingsManager: SettingsManager,
         temporaryPresetsManager: TemporaryPresetsManager
    ) {
        self.deviceManager = deviceDataManager
        self.loopDataManager = loopDataManager
        self.settingsManager = settingsManager
        self.temporaryPresetsManager = temporaryPresetsManager

        dataUpdatedObserver = NotificationCenter.default.addObserver(forName: .LoopDataUpdated, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.update()
            }
        }
        
        pumpManagerChangedObserver = NotificationCenter.default.addObserver(forName: .PumpManagerChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.update()
            }
        }
        
        // Wait until LoopDataManager has had a chance to initialize itself
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.update()
        }
    }
    
    deinit {
        if let obs = dataUpdatedObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = pumpManagerChangedObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    nonisolated fileprivate static var defaults: UserDefaults? {
        return UserDefaults.appGroup
    }

    nonisolated static var context: StatusExtensionContext? {
        get {
            return defaults?.statusExtensionContext
        }
        set {
            defaults?.statusExtensionContext = newValue
        }
    }

    static var intentExtensionInfo: IntentExtensionInfo? {
        get {
            return defaults?.intentExtensionInfo
        }
        set {
            defaults?.intentExtensionInfo = newValue
        }
    }

    static var lastLoopCompleted: Date? {
        context?.lastLoopCompleted
    }
    
    private func update() {
        Task { @MainActor in
            if let context = await createStatusContext(glucoseUnit:  deviceManager.displayGlucosePreference.unit) {
                ExtensionDataManager.context = context
            }

            if let info = createIntentsContext(), ExtensionDataManager.intentExtensionInfo?.overridePresetNames != info.overridePresetNames {
                ExtensionDataManager.intentExtensionInfo = info
            }
        }
    }
    
    private func createIntentsContext() -> IntentExtensionInfo? {
        let presets = settingsManager.settings.overridePresets
        let info = IntentExtensionInfo(overridePresetNames: presets.map { $0.name })
        return info
    }

    private func createStatusContext(glucoseUnit: LoopUnit) async -> StatusExtensionContext? {

        let basalDeliveryState = deviceManager.pumpManager?.status.basalDeliveryState

        let state = loopDataManager.algorithmState

        let dataManager = self.deviceManager
        var context = StatusExtensionContext()

        context.createdAt = Date()

        #if IOS_SIMULATOR
            // If we're in the simulator, there's a higher likelihood that we don't have
            // a fully configured app. Inject some baseline debug data to let us test the
            // experience. This data will be overwritten by actual data below, if available.
            context.batteryPercentage = 0.25
            context.netBasal = NetBasalContext(
                rate: 2.1,
                percentage: 0.6,
                start:
                Date(timeIntervalSinceNow: -250),
                end: Date(timeIntervalSinceNow: .minutes(30))
            )
            context.predictedGlucose = PredictedGlucoseContext(
                values: (1...36).map { 89.123 + Double($0 * 5) }, // 3 hours of linear data
                unit: LoopUnit.milligramsPerDeciliter,
                startDate: Date(),
                interval: TimeInterval(minutes: 5))
        #endif

        context.lastLoopCompleted = loopDataManager.lastLoopCompleted
        context.mostRecentGlucoseDataDate = loopDataManager.mostRecentGlucoseDataDate
        context.mostRecentPumpDataDate = loopDataManager.mostRecentPumpDataDate

        context.isClosedLoop = self.settingsManager.dosingEnabled

        context.preMealPresetAllowed = self.settingsManager.dosingEnabled && self.settingsManager.settings.preMealTargetRange != nil
        context.preMealPresetActive = self.temporaryPresetsManager.isPreMealTargetActive()
        context.customPresetActive = self.temporaryPresetsManager.isNonPreMealOverrideActive()

        // Drop the first element in predictedGlucose because it is the currentGlucose
        // and will have a different interval to the next element
        if let predictedGlucose = state.output?.predictedGlucose.dropFirst(),
            predictedGlucose.count > 1 {
            let first = predictedGlucose[predictedGlucose.startIndex]
            let second = predictedGlucose[predictedGlucose.startIndex.advanced(by: 1)]
            context.predictedGlucose = PredictedGlucoseContext(
                values: predictedGlucose.map { $0.loopKit.quantity.doubleValue(for: glucoseUnit) },
                unit: glucoseUnit,
                startDate: first.startDate,
                interval: second.startDate.timeIntervalSince(first.startDate))
        }

        if let basalDeliveryState = basalDeliveryState,
            let basalSchedule = self.temporaryPresetsManager.basalRateScheduleApplyingOverrideHistory,
           let netBasal = basalDeliveryState.getNetBasal(basalSchedule: basalSchedule, maximumBasalRatePerHour: self.settingsManager.settings.maximumBasalRatePerHour)
        {
            context.netBasal = NetBasalContext(rate: netBasal.rate, percentage: netBasal.percent, start: netBasal.start, end: netBasal.end)
        }

        context.batteryPercentage = dataManager.pumpManager?.status.pumpBatteryChargeRemaining
        context.reservoirCapacity = dataManager.pumpManager?.pumpReservoirCapacity

        if let glucoseDisplay = dataManager.glucoseDisplay(for: loopDataManager.latestGlucose) {
            context.glucoseDisplay = GlucoseDisplayableContext(
                isStateValid: glucoseDisplay.isStateValid,
                stateDescription: glucoseDisplay.stateDescription,
                trendType: glucoseDisplay.trendType,
                trendRate: glucoseDisplay.trendRate,
                isLocal: glucoseDisplay.isLocal,
                glucoseRangeCategory: glucoseDisplay.glucoseRangeCategory
            )
        }

        if let pumpManagerHUDProvider = dataManager.pumpManagerHUDProvider {
            context.pumpManagerHUDViewContext = PumpManagerHUDViewContext(pumpManagerHUDViewRawValue: PumpManagerHUDViewRawValueFromHUDProvider(pumpManagerHUDProvider))
        }

        context.pumpStatusHighlightContext = DeviceStatusHighlightContext(from: dataManager.pumpStatusHighlight)
        context.pumpLifecycleProgressContext = DeviceLifecycleProgressContext(from: dataManager.pumpLifecycleProgress)

        context.cgmStatusHighlightContext = DeviceStatusHighlightContext(from: dataManager.cgmStatusHighlight)
        context.cgmLifecycleProgressContext = DeviceLifecycleProgressContext(from: dataManager.cgmLifecycleProgress)

        context.carbsOnBoard = state.activeCarbs?.value

        return context
    }
}


extension ExtensionDataManager: CustomDebugStringConvertible {
    nonisolated var debugDescription: String {
        return [
            "## StatusExtensionDataManager",
            "appGroupName: \(Bundle.main.appGroupSuiteName)",
            "statusExtensionContext: \(String(reflecting: ExtensionDataManager.context))",
            ""
        ].joined(separator: "\n")
    }
}
