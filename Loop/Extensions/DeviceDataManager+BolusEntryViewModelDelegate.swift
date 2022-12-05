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

extension DeviceDataManager: BolusEntryViewModelDelegate, ManualDoseViewModelDelegate {
    
    func addManuallyEnteredDose(startDate: Date, units: Double, insulinType: InsulinType?) {
        loopManager.addManuallyEnteredDose(startDate: startDate, units: units, insulinType: insulinType)
    }
    
    func withLoopState(do block: @escaping (LoopState) -> Void) {
        loopManager.getLoopState { block($1) }
    }

    func saveGlucose(sample: NewGlucoseSample) async -> StoredGlucoseSample? {
        return await withCheckedContinuation { continuation in
            loopManager.addGlucoseSamples([sample]) { result in
                switch result {
                case .success(let samples):
                    continuation.resume(returning: samples.first)
                case .failure:
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func addCarbEntry(_ carbEntry: NewCarbEntry, replacing replacingEntry: StoredCarbEntry?, completion: @escaping (Result<StoredCarbEntry>) -> Void) {
        loopManager.addCarbEntry(carbEntry, replacing: replacingEntry, completion: completion)
    }

    func storeManualBolusDosingDecision(_ bolusDosingDecision: BolusDosingDecision, withDate date: Date) {
        loopManager.storeManualBolusDosingDecision(bolusDosingDecision, withDate: date)
    }

    func getGlucoseSamples(start: Date?, end: Date?, completion: @escaping (Swift.Result<[StoredGlucoseSample], Error>) -> Void) {
        glucoseStore.getGlucoseSamples(start: start, end: end, completion: completion)
    }
    
    func insulinOnBoard(at date: Date, completion: @escaping (DoseStoreResult<InsulinValue>) -> Void) {
        doseStore.insulinOnBoard(at: date, completion: completion)
    }
    
    func carbsOnBoard(at date: Date, effectVelocities: [GlucoseEffectVelocity]?, completion: @escaping (CarbStoreResult<CarbValue>) -> Void) {
        carbStore.carbsOnBoard(at: date, effectVelocities: effectVelocities, completion: completion)
    }
    
    func ensureCurrentPumpData(completion: @escaping (Date?) -> Void) {
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
        return doseStore.insulinModelProvider.model(for: type).effectDuration
    }

    var settings: LoopSettings {
        return loopManager.settings
    }

    func updateRemoteRecommendation() {
        loopManager.updateRemoteRecommendation()
    }
}
