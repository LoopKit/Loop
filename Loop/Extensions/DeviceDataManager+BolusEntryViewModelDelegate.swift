//
//  DeviceDataManager+BolusEntryViewModelDelegate.swift
//  Loop
//
//  Created by Rick Pasetto on 9/29/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopCore
import LoopKit

extension DeviceDataManager: BolusEntryViewModelDelegate, LoggedDoseViewModelDelegate {
    
    func logOutsideInsulinDose(startDate: Date, units: Double, insulinType: InsulinType?) {
        loopManager.logOutsideInsulinDose(startDate: startDate, units: units, insulinType: insulinType)
    }
    
    func withLoopState(do block: @escaping (LoopState) -> Void) {
        loopManager.getLoopState { block($1) }
    }
    
    func addGlucoseSamples(_ samples: [NewGlucoseSample], completion: ((Swift.Result<[StoredGlucoseSample], Error>) -> Void)?) {
        loopManager.addGlucoseSamples(samples, completion: completion)
    }
    
    func addCarbEntry(_ carbEntry: NewCarbEntry, replacing replacingEntry: StoredCarbEntry?, completion: @escaping (Result<StoredCarbEntry>) -> Void) {
        loopManager.addCarbEntry(carbEntry, replacing: replacingEntry, completion: completion)
    }

    func storeBolusDosingDecision(_ bolusDosingDecision: BolusDosingDecision, withDate date: Date) {
        loopManager.storeBolusDosingDecision(bolusDosingDecision, withDate: date)
    }

    /// func enactBolus(units: Double, at startDate: Date, completion: @escaping (_ error: Error?) -> Void)
    /// is already implemented in DeviceDataManager
    
    func getGlucoseSamples(start: Date?, end: Date?, completion: @escaping (Swift.Result<[StoredGlucoseSample], Error>) -> Void) {
        glucoseStore.getGlucoseSamples(start: start, end: end, completion: completion)
    }
    
    func insulinOnBoard(at date: Date, completion: @escaping (DoseStoreResult<InsulinValue>) -> Void) {
        doseStore.insulinOnBoard(at: date, completion: completion)
    }
    
    func carbsOnBoard(at date: Date, effectVelocities: [GlucoseEffectVelocity]?, completion: @escaping (CarbStoreResult<CarbValue>) -> Void) {
        carbStore.carbsOnBoard(at: date, effectVelocities: effectVelocities, completion: completion)
    }
    
    func ensureCurrentPumpData(completion: @escaping () -> Void) {
        pumpManager?.ensureCurrentPumpData(completion: completion)
    }
    
    var mostRecentGlucoseDataDate: Date? {
        return glucoseStore.latestGlucose?.startDate
    }
    
    var mostRecentPumpDataDate: Date? {
        return doseStore.lastAddedPumpData
    }

    var isPumpConfigured: Bool {
        return pumpManager != nil
    }
    
    var preferredGlucoseUnit: HKUnit {
        return glucoseStore.preferredUnit ?? .milligramsPerDeciliter
    }
    
    var pumpInsulinType: InsulinType? {
        return pumpManager?.status.insulinType
    }
        
    func insulinActivityDuration(for type: InsulinType?) -> TimeInterval {
        if let insulinModelSettings = doseStore.insulinModelSettings {
            return insulinModelSettings.model(for: type).effectDuration
        } else {
            return ExponentialInsulinModelPreset.rapidActingAdult.effectDuration
        }
    }

    var settings: LoopSettings {
        return loopManager.settings
    }

}
