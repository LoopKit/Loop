//
//  NightscoutDataManager.swift
//  Loop
//
//  Created by Nate Racklyeft on 8/8/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import NightscoutUploadKit
import HealthKit
import LoopKit
import os.log


final class NightscoutDataManager {

    unowned let deviceManager: DeviceDataManager

    private let log = OSLog(category: "NightscoutDataManager")

    // Last time we uploaded device status
    var lastDeviceStatusUpload: Date?

    // Last time we uploaded settings
    var lastSettingsUpload: Date = .distantPast

    // Last time settings were updated
    var lastSettingsUpdate: Date = .distantPast
    
    // Override history query anchor
    var overrideHistoryQueryAnchor: TemporaryScheduleOverrideHistory.QueryAnchor?

    init(deviceDataManager: DeviceDataManager) {
        self.deviceManager = deviceDataManager

        NotificationCenter.default.addObserver(self, selector: #selector(loopCompleted(_:)), name: .LoopCompleted, object: deviceDataManager.loopManager)
        NotificationCenter.default.addObserver(self, selector: #selector(loopDataUpdated(_:)), name: .LoopDataUpdated, object: deviceDataManager.loopManager)
    }


    @objc func loopDataUpdated(_ note: Notification) {
        guard
            let rawContext = note.userInfo?[LoopDataManager.LoopUpdateContextKey] as? LoopDataManager.LoopUpdateContext.RawValue,
            let context = LoopDataManager.LoopUpdateContext(rawValue: rawContext),
            case .preferences = context
            else {
                return
        }

        lastSettingsUpdate = Date()
        uploadSettings()
        uploadOverridesUpdates()
    }
    
    private func uploadOverridesUpdates() {
        guard let uploader = deviceManager.remoteDataManager.nightscoutService.uploader else {
            return
        }
        
        let (overrides, deletedOverrides, newAnchor) = deviceManager.loopManager.overrideHistory.queryByAnchor(overrideHistoryQueryAnchor)
        
        let updates = overrides.map { OverrideTreatment(override: $0) }
        
        let deletions = deletedOverrides.map { $0.syncIdentifier.uuidString }
        uploader.deleteTreatmentsByClientId(deletions, completionHandler: { (error) in
            if let error = error {
                self.log.error("Overrides deletions failed to delete %{public}@: %{public}@", String(describing: deletions), String(describing: error))
            } else {
                if deletions.count > 0 {
                    self.log.debug("Deleted ids: %@", deletions)
                }
                uploader.upload(updates) { (result) in
                    switch result {
                    case .failure(let error):
                        self.log.error("Failed to upload overrides %{public}@: %{public}@", String(describing: updates.map {$0.dictionaryRepresentation}), String(describing: error))
                    case .success:
                        self.log.debug("Uploaded overrides %@", String(describing: updates.map {$0.dictionaryRepresentation}))
                        self.overrideHistoryQueryAnchor = newAnchor
                    }
                }
            }
        })
    }

    private func uploadSettings() {
        let settings = deviceManager.loopManager.settings
        
        guard
            let uploader = deviceManager.remoteDataManager.nightscoutService.uploader,
            let basalRateSchedule = UserDefaults.appGroup?.basalRateSchedule,
            let insulinModelSettings = UserDefaults.appGroup?.insulinModelSettings,
            let carbRatioSchedule = UserDefaults.appGroup?.carbRatioSchedule,
            let insulinSensitivitySchedule = UserDefaults.appGroup?.insulinSensitivitySchedule,
            let preferredUnit = settings.glucoseUnit,
            let correctionSchedule = settings.glucoseTargetRangeSchedule else
        {
            log.default("Not uploading due to incomplete configuration")
            return
        }
        
        let targetLowItems = correctionSchedule.items.map { (item) -> ProfileSet.ScheduleItem in
            return ProfileSet.ScheduleItem(offset: item.startTime, value: item.value.minValue)
        }

        let targetHighItems = correctionSchedule.items.map { (item) -> ProfileSet.ScheduleItem in
            return ProfileSet.ScheduleItem(offset: item.startTime, value: item.value.maxValue)
        }

        let nsScheduledOverride = settings.scheduleOverride?.nsScheduleOverride(for: preferredUnit)

        let nsPreMealTargetRange: ClosedRange<Double>?
        if let preMealTargetRange = settings.preMealTargetRange {
            nsPreMealTargetRange = ClosedRange(uncheckedBounds: (
                lower: preMealTargetRange.minValue,
                upper: preMealTargetRange.maxValue))
        } else {
            nsPreMealTargetRange = nil
        }

        let nsLoopSettings = NightscoutUploadKit.LoopSettings(
            dosingEnabled: settings.dosingEnabled,
            overridePresets: settings.overridePresets.map { $0.nsScheduleOverride(for: preferredUnit) },
            scheduleOverride: nsScheduledOverride,
            minimumBGGuard: settings.suspendThreshold?.quantity.doubleValue(for: preferredUnit),
            preMealTargetRange: nsPreMealTargetRange,
            maximumBasalRatePerHour: settings.maximumBasalRatePerHour,
            maximumBolus: settings.maximumBolus,
            deviceToken: settings.deviceToken,
            bundleIdentifier: Bundle.main.bundleIdentifier)

        let profile = ProfileSet.Profile(
            timezone: basalRateSchedule.timeZone,
            dia: insulinModelSettings.model.effectDuration,
            sensitivity: insulinSensitivitySchedule.items.scheduleItems(),
            carbratio: carbRatioSchedule.items.scheduleItems(),
            basal: basalRateSchedule.items.scheduleItems(),
            targetLow: targetLowItems,
            targetHigh: targetHighItems,
            units: correctionSchedule.unit.shortLocalizedUnitString())

        let store: [String: ProfileSet.Profile] = [
            "Default": profile
        ]

        let profileSet = ProfileSet(
            startDate: Date(),
            units: preferredUnit.shortLocalizedUnitString(),
            enteredBy: "Loop",
            defaultProfile: "Default",
            store: store,
            settings: nsLoopSettings)

        log.default("Uploading profile")

        uploader.uploadProfile(profileSet: profileSet) { (result) in
            switch(result) {
            case .failure(let error):
                self.log.error("Settings upload failed: %{public}@", String(describing: error))
            case .success:
                DispatchQueue.main.async {
                    self.lastSettingsUpload = Date()
                }
            }
        }
    }

    @objc func loopCompleted(_ note: Notification) {
        guard deviceManager.remoteDataManager.nightscoutService.uploader != nil else {
            return
        }

        deviceManager.loopManager.getLoopState { (manager, state) in
            var loopError = state.error
            let recommendedBolus: Double?
            

            recommendedBolus = state.recommendedBolus?.recommendation.amount

            let carbsOnBoard = state.carbsOnBoard
            let predictedGlucose = state.predictedGlucoseIncludingPendingInsulin
            let recommendedTempBasal = state.recommendedAutomaticDose

            manager.doseStore.insulinOnBoard(at: Date()) { (result) in
                let insulinOnBoard: InsulinValue?

                switch result {
                case .success(let value):
                    insulinOnBoard = value
                case .failure(let error):
                    insulinOnBoard = nil

                    if loopError == nil {
                        loopError = error
                    }
                }

                self.uploadLoopStatus(
                    insulinOnBoard: insulinOnBoard,
                    carbsOnBoard: carbsOnBoard,
                    predictedGlucose: predictedGlucose,
                    recommendedAutomaticDose: recommendedTempBasal,
                    recommendedManualBolus: recommendedBolus,
                    loopError: loopError
                )

                if self.lastSettingsUpdate > self.lastSettingsUpload {
                    self.uploadSettings()
                }
                
                self.uploadOverridesUpdates()
            }
        }
    }
    
    private var lastTempBasalUploaded: DoseEntry?

    func uploadLoopStatus(
        insulinOnBoard: InsulinValue? = nil,
        carbsOnBoard: CarbValue? = nil,
        predictedGlucose: [GlucoseValue]? = nil,
        recommendedAutomaticDose: (recommendation: AutomaticDoseRecommendation, date: Date)? = nil,
        recommendedManualBolus: Double? = nil,
        loopError: Error? = nil)
    {

        guard deviceManager.remoteDataManager.nightscoutService.uploader != nil else {
            return
        }
        
        let statusTime = Date()
        
        let iob: IOBStatus?
        
        if let insulinOnBoard = insulinOnBoard {
            iob = IOBStatus(timestamp: insulinOnBoard.startDate, iob: insulinOnBoard.value)
        } else {
            iob = nil
        }

        let cob: COBStatus?

        if let carbsOnBoard = carbsOnBoard {
            cob = COBStatus(cob: carbsOnBoard.quantity.doubleValue(for: HKUnit.gram()), timestamp: carbsOnBoard.startDate)
        } else {
            cob = nil
        }
        
        let predicted: PredictedBG?
        if let predictedGlucose = predictedGlucose, let startDate = predictedGlucose.first?.startDate {
            let values = predictedGlucose.map { $0.quantity }
            predicted = PredictedBG(startDate: startDate, values: values)
        } else {
            predicted = nil
        }

        let recommended: RecommendedTempBasal?
        
        if let (recommendation: recommendation, date: date) = recommendedAutomaticDose, let basalAdjustment = recommendation.basalAdjustment {
            recommended = RecommendedTempBasal(timestamp: date, rate: basalAdjustment.unitsPerHour, duration: basalAdjustment.duration)
        } else {
            recommended = nil
        }

        let loopEnacted: LoopEnacted?
        if case .some(.tempBasal(let tempBasal)) = deviceManager.pumpManagerStatus?.basalDeliveryState, lastTempBasalUploaded?.startDate != tempBasal.startDate {
            let duration = tempBasal.endDate.timeIntervalSince(tempBasal.startDate)
            loopEnacted = LoopEnacted(rate: tempBasal.unitsPerHour, duration: duration, timestamp: tempBasal.startDate, received:
                true)
            lastTempBasalUploaded = tempBasal
        } else {
            loopEnacted = nil
        }
        
        let loopName = Bundle.main.bundleDisplayName
        let loopVersion = Bundle.main.shortVersionString

        //this is the only pill that has the option to modify the text
        //to do that pass a different name value instead of loopName
        let loopStatus = LoopStatus(name: loopName, version: loopVersion, timestamp: statusTime, iob: iob, cob: cob, predicted: predicted, recommendedTempBasal: recommended, recommendedBolus: recommendedManualBolus, enacted: loopEnacted, failureReason: loopError)

        let pumpStatus: NightscoutUploadKit.PumpStatus?
        
        if let pumpManagerStatus = deviceManager.pumpManagerStatus
        {
            
            let battery: BatteryStatus?
            
            if let chargeRemaining = pumpManagerStatus.pumpBatteryChargeRemaining {
                battery = BatteryStatus(percent: Int(round(chargeRemaining * 100)), voltage: nil, status: nil)
            } else {
                battery = nil
            }
            
            let bolusing: Bool
            if case .inProgress = pumpManagerStatus.bolusState {
                bolusing = true
            } else {
                bolusing = false
            }
            
            let currentReservoirUnits: Double?
            if let lastReservoirValue = deviceManager.loopManager.doseStore.lastReservoirValue, lastReservoirValue.startDate > Date().addingTimeInterval(.minutes(-15)) {
                currentReservoirUnits = lastReservoirValue.unitVolume
            } else {
                currentReservoirUnits = nil
            }

            pumpStatus = NightscoutUploadKit.PumpStatus(
                clock: Date(),
                pumpID: pumpManagerStatus.device.localIdentifier ?? "Unknown",
                manufacturer: pumpManagerStatus.device.manufacturer,
                model: pumpManagerStatus.device.model,
                iob: nil,
                battery: battery,
                suspended: pumpManagerStatus.basalDeliveryState.isSuspended,
                bolusing: bolusing,
                reservoir: currentReservoirUnits,
                secondsFromGMT: pumpManagerStatus.timeZone.secondsFromGMT())
        } else {
            pumpStatus = nil
        }
        
        //add overrideStatus
        let overrideStatus: NightscoutUploadKit.OverrideStatus?
        let settings = deviceManager.loopManager.settings
        let unit: HKUnit = settings.glucoseTargetRangeSchedule?.unit ?? HKUnit.milligramsPerDeciliter
        if let override = settings.scheduleOverride, override.isActive(),
            let range = settings.glucoseTargetRangeScheduleApplyingOverrideIfActive?.value(at: Date()) {
            let lowerTarget : HKQuantity = HKQuantity(unit : unit, doubleValue: range.minValue)
            let upperTarget : HKQuantity = HKQuantity(unit : unit, doubleValue: range.maxValue)
            let correctionRange = CorrectionRange(minValue: lowerTarget, maxValue: upperTarget)
            let endDate = override.endDate
            let duration : TimeInterval?
            if override.duration == .indefinite {
                duration = nil
            }
            else
            {
                duration = round(endDate.timeIntervalSince(Date()))
                
            }
            let name : String?
            
            switch override.context {
            case .preMeal:
                name = "preMeal"
            case .custom:
                name = "Custom"
            case .preset(let preset):
                name = preset.name
            case .legacyWorkout:
                name = "Workout"
            }
            
            
            overrideStatus = NightscoutUploadKit.OverrideStatus(name: name, timestamp: Date(), active: true, currentCorrectionRange: correctionRange, duration: duration, multiplier: override.settings.insulinNeedsScaleFactor)
            
        }
        
        else
        
        {
            overrideStatus = NightscoutUploadKit.OverrideStatus(timestamp: Date(), active: false)
        }
        log.default("Uploading loop status")
        upload(pumpStatus: pumpStatus, loopStatus: loopStatus, deviceName: nil, firmwareVersion: nil, uploaderStatus: getUploaderStatus(), overrideStatus: overrideStatus)
    }
    
    private func getUploaderStatus() -> UploaderStatus {
        // Gather UploaderStatus
        let uploaderDevice = UIDevice.current

        let battery: Int?
        if uploaderDevice.isBatteryMonitoringEnabled {
            battery = Int(uploaderDevice.batteryLevel * 100)
        } else {
            battery = nil
        }
        return UploaderStatus(name: uploaderDevice.name, timestamp: Date(), battery: battery)
    }

    func upload(pumpStatus: NightscoutUploadKit.PumpStatus?, deviceName: String?, firmwareVersion: String?) {
        upload(pumpStatus: pumpStatus, loopStatus: nil, deviceName: deviceName, firmwareVersion: firmwareVersion, uploaderStatus: nil, overrideStatus: nil)
    }

    private func upload(pumpStatus: NightscoutUploadKit.PumpStatus?, loopStatus: LoopStatus?, deviceName: String?, firmwareVersion: String?, uploaderStatus: UploaderStatus?, overrideStatus: OverrideStatus?) {

        guard let uploader = deviceManager.remoteDataManager.nightscoutService.uploader else {
            return
        }
        
        if pumpStatus == nil && loopStatus == nil && uploaderStatus != nil {
            // If we're just uploading phone status, limit it to once every 5 minutes
            if self.lastDeviceStatusUpload != nil && self.lastDeviceStatusUpload!.timeIntervalSinceNow > -(TimeInterval(minutes: 5)) {
                return
            }
        }

        let uploaderDevice = UIDevice.current

        // Build DeviceStatus
        let deviceStatus = DeviceStatus(device: "loop://\(uploaderDevice.name)", timestamp: Date(), pumpStatus: pumpStatus, uploaderStatus: uploaderStatus, loopStatus: loopStatus, radioAdapter: nil, overrideStatus: overrideStatus)

        self.lastDeviceStatusUpload = Date()
        uploader.uploadDeviceStatus(deviceStatus)
    }

    func uploadGlucose(_ values: [GlucoseValue], sensorState: SensorDisplayable?, fromDevice device: HKDevice?) {
        guard let uploader = deviceManager.remoteDataManager.nightscoutService.uploader else {
            return
        }
        
        var deviceStr: String
        if let device = device {
            deviceStr = [device.name, device.manufacturer, device.model, device.firmwareVersion, device.softwareVersion].compactMap { $0 }.joined(separator: " ")
        } else {
            deviceStr = "loop://unknowndevice"
        }

        let direction: String? = {
            switch sensorState?.trendType {
            case .up?:
                return "FortyFiveUp"
            case .upUp?:
                return "SingleUp"
            case .upUpUp?:
                return "DoubleUp"
            case .down?:
                return "FortyFiveDown"
            case .downDown?:
                return "SingleDown"
            case .downDownDown?:
                return "DoubleDown"
            case .flat?:
                return "Flat"
            case .none:
                return nil
            }
        }()

        for value in values {
            uploader.uploadSGV(
                glucoseMGDL: Int(value.quantity.doubleValue(for: .milligramsPerDeciliter)),
                at: value.startDate,
                direction: direction,
                device: deviceStr
            )
        }
        uploader.flushAll();
    }
}

private extension Array where Element == RepeatingScheduleValue<Double> {
    func scheduleItems() -> [ProfileSet.ScheduleItem] {
        return map { (item) -> ProfileSet.ScheduleItem in
            return ProfileSet.ScheduleItem(offset: item.startTime, value: item.value)
        }
    }
}

// Likely this will be deprecated, in favor of override history uploading to NS treatments
private extension LoopKit.TemporaryScheduleOverride {
    func nsScheduleOverride(for unit: HKUnit) -> NightscoutUploadKit.TemporaryScheduleOverride {
        let nsCorrectionRange: ClosedRange<Double>?
        if let targetRange = settings.targetRange {
            nsCorrectionRange = ClosedRange(uncheckedBounds: (
                lower: targetRange.lowerBound.doubleValue(for: unit),
                upper: targetRange.upperBound.doubleValue(for: unit)))
        } else {
            nsCorrectionRange = nil
        }

        let nsDuration: TimeInterval
        switch duration {
        case .finite(let interval):
            nsDuration = interval
        case .indefinite:
            nsDuration = 0
        }

        let name: String?
        let symbol: String?

        switch context {
        case .custom:
            name = nil
            symbol = nil
        case .legacyWorkout:
            name = "Workout"
            symbol = nil
        case .preMeal:
            name = "PreMeal"
            symbol = nil
        case .preset(let preset):
            name = preset.name
            symbol = preset.symbol
        }

        return NightscoutUploadKit.TemporaryScheduleOverride(
            duration: nsDuration,
            targetRange: nsCorrectionRange,
            insulinNeedsScaleFactor: settings.insulinNeedsScaleFactor,
            symbol: symbol,
            name: name)
    }
}

private extension LoopKit.TemporaryScheduleOverridePreset {
    func nsScheduleOverride(for unit: HKUnit) -> NightscoutUploadKit.TemporaryScheduleOverride {
        let nsCorrectionRange: ClosedRange<Double>?
        if let targetRange = settings.targetRange {
            nsCorrectionRange = ClosedRange(uncheckedBounds: (
                lower: targetRange.lowerBound.doubleValue(for: unit),
                upper: targetRange.upperBound.doubleValue(for: unit)))
        } else {
            nsCorrectionRange = nil
        }

        let nsDuration: TimeInterval
        switch duration {
        case .finite(let interval):
            nsDuration = interval
        case .indefinite:
            nsDuration = 0
        }

        return NightscoutUploadKit.TemporaryScheduleOverride(
            duration: nsDuration,
            targetRange: nsCorrectionRange,
            insulinNeedsScaleFactor: settings.insulinNeedsScaleFactor,
            symbol: self.symbol,
            name: self.name)
    }
}

private extension OverrideTreatment {
    convenience init(override: LoopKit.TemporaryScheduleOverride) {
        
        // NS Treatments should be in mg/dL
        let unit: HKUnit = .milligramsPerDeciliter
        
        let nsTargetRange: ClosedRange<Double>?
        if let targetRange = override.settings.targetRange {
            nsTargetRange = ClosedRange(uncheckedBounds: (
                lower: targetRange.lowerBound.doubleValue(for: unit),
                upper: targetRange.upperBound.doubleValue(for: unit)))
        } else {
            nsTargetRange = nil
        }
        
        let reason: String
        switch override.context {
        case .custom:
            reason = NSLocalizedString("Custom Override", comment: "Name of custom override")
        case .legacyWorkout:
            reason = NSLocalizedString("Workout", comment: "Name of legacy workout override")
        case .preMeal:
            reason = NSLocalizedString("Pre-Meal", comment: "Name of pre-meal workout override")
        case .preset(let preset):
            reason = preset.symbol + " " + preset.name
        }
        
        let remoteAddress: String?
        let enteredBy: String
        if case .remote(let address) = override.enactTrigger {
            remoteAddress = address
            enteredBy = "Loop (via remote command)"
        } else {
            remoteAddress = nil
            enteredBy = "Loop"
        }
        
        let duration: OverrideTreatment.Duration
        switch override.duration {
        case .finite(let time):
            duration = .finite(time)
        case .indefinite:
            duration = .indefinite
        }
        
        self.init(startDate: override.startDate, enteredBy: enteredBy, reason: reason, duration: duration, correctionRange: nsTargetRange, insulinNeedsScaleFactor: override.settings.insulinNeedsScaleFactor, remoteAddress:remoteAddress, id: override.syncIdentifier.uuidString)
    }
}
