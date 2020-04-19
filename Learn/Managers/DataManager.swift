//
//  DataManager.swift
//  Learn
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore


final class DataManager {
    let carbStore: CarbStore

    let doseStore: DoseStore

    let glucoseStore: GlucoseStore

    let settings: LoopSettings

    init(
        basalRateSchedule: BasalRateSchedule? = UserDefaults.appGroup?.basalRateSchedule,
        carbRatioSchedule: CarbRatioSchedule? = UserDefaults.appGroup?.carbRatioSchedule,
        insulinModelSettings: InsulinModelSettings? = UserDefaults.appGroup?.insulinModelSettings,
        insulinSensitivitySchedule: InsulinSensitivitySchedule? = UserDefaults.appGroup?.insulinSensitivitySchedule,
        settings: LoopSettings = UserDefaults.appGroup?.loopSettings ?? LoopSettings()
    ) {
        self.settings = settings

        let healthStore = HKHealthStore()
        let cacheStore = PersistenceController.controllerInAppGroupDirectory(isReadOnly: true)
        
        let overrideHistory = UserDefaults.appGroup?.overrideHistory ?? TemporaryScheduleOverrideHistory()

        carbStore = CarbStore(
            healthStore: healthStore,
            cacheStore: cacheStore,
            observationEnabled: false,
            carbRatioSchedule: carbRatioSchedule,
            insulinSensitivitySchedule: insulinSensitivitySchedule,
            overrideHistory: overrideHistory
        )

        doseStore = DoseStore(
            healthStore: healthStore,
            cacheStore: cacheStore,
            observationEnabled: false,
            insulinModel: insulinModelSettings?.model,
            basalProfile: basalRateSchedule,
            insulinSensitivitySchedule: insulinSensitivitySchedule,
            overrideHistory: overrideHistory
        )

        glucoseStore = GlucoseStore(
            healthStore: healthStore,
            cacheStore: cacheStore,
            observationEnabled: false
        )
    }
}


// MARK: - Thread-safe Preferences
extension DataManager {
    /// The daily schedule of basal insulin rates
    var basalRateSchedule: BasalRateSchedule? {
        return doseStore.basalProfile
    }

    /// The daily schedule of carbs-to-insulin ratios
    /// This is measured in grams/Unit
    var carbRatioSchedule: CarbRatioSchedule? {
        return carbStore.carbRatioSchedule
    }

    /// The length of time insulin has an effect on blood glucose
    var insulinModelSettings: InsulinModelSettings? {
        guard let model = doseStore.insulinModel else {
            return nil
        }

        return InsulinModelSettings(model: model)
    }

    /// The daily schedule of insulin sensitivity (also known as ISF)
    /// This is measured in <blood glucose>/Unit
    var insulinSensitivitySchedule: InsulinSensitivitySchedule? {
        return carbStore.insulinSensitivitySchedule
    }
}

protocol EffectsFetcher {
    func fetchEffects(for day: DateInterval, retrospectiveCorrection: RetrospectiveCorrection, momentumDataInterval: TimeInterval) -> Result<GlucoseEffects>
}

// MARK: - Effects Data

extension DataManager: EffectsFetcher {
    func fetchEffects(for day: DateInterval, retrospectiveCorrection: RetrospectiveCorrection, momentumDataInterval: TimeInterval) -> Result<GlucoseEffects> {
        let updateGroup = DispatchGroup()

        let retrospectiveStart = day.start.addingTimeInterval(-retrospectiveCorrection.retrospectionInterval)

        var insulinEffects: [GlucoseEffect]?
        var insulinFetchError: Error?
        
        updateGroup.enter()
        doseStore.getGlucoseEffects(start: day.start, basalDosingEnd: day.end) { (result) -> Void in
            switch result {
            case .failure(let error):
                insulinFetchError = error
            case .success(let effects):
                insulinEffects = effects
            }

            updateGroup.leave()
        }

        _ = updateGroup.wait(timeout: .distantFuture)
        
        guard insulinFetchError == nil else {
            return .failure(insulinFetchError!)
        }
        
        var counteractionEffects: [GlucoseEffectVelocity]?
        var glucose: [StoredGlucoseSample]?
        
        updateGroup.enter()
        // Get enough glucose readings for momentum at the beginning of the day
        let glucoseStart = day.start.addingTimeInterval(-momentumDataInterval)
        glucoseStore.getCachedGlucoseSamples(start: glucoseStart, end: day.end) { (samples) in
            glucose = samples
            counteractionEffects = samples.counteractionEffects(to: insulinEffects!)
            
            updateGroup.leave()
        }
        
        _ = updateGroup.wait(timeout: .distantFuture)
        
        var carbEffects: [GlucoseEffect]?
        var carbFetchError: Error?
        
        updateGroup.enter()
        carbStore.getGlucoseEffects(
            start: retrospectiveStart,
            effectVelocities: settings.dynamicCarbAbsorptionEnabled ? counteractionEffects! : nil
        ) { (result) -> Void in
            switch result {
            case .failure(let error):
                carbFetchError = error
            case .success(let (_, effects)):
                carbEffects = effects
            }

            updateGroup.leave()
        }

        _ = updateGroup.wait(timeout: .distantFuture)
        
        guard carbFetchError == nil else {
            return .failure(carbFetchError!)
        }

        // Get timeline of glucose discrepancies
        let retrospectiveGlucoseDiscrepancies: [GlucoseEffect] = counteractionEffects!.subtracting(carbEffects!, withUniformInterval: carbStore.delta)
        
        let retrospectiveCorrectionGroupingIntervalMultiplier = 1.01
        
        let retrospectiveGlucoseDiscrepanciesSummed: [GlucoseChange] = retrospectiveGlucoseDiscrepancies.combinedSums(of: settings.retrospectiveCorrectionGroupingInterval * retrospectiveCorrectionGroupingIntervalMultiplier)

        return .success(GlucoseEffects(
            dateInterval: day,
            glucose: glucose!,
            insulinEffects: insulinEffects!,
            counteractionEffects: counteractionEffects!,
            carbEffects: carbEffects!,
            retrospectiveGlucoseDiscrepanciesSummed: retrospectiveGlucoseDiscrepanciesSummed
        ))
    }

}



// MARK: - HealthKit Setup
extension DataManager {
    var healthStore: HKHealthStore {
        return carbStore.healthStore
    }

    /// All the HealthKit types to be read and shared by stores
    private var sampleTypes: Set<HKSampleType> {
        return Set([
            glucoseStore.sampleType,
            carbStore.sampleType,
            doseStore.sampleType,
        ].compactMap { $0 })
    }

    /// True if any stores require HealthKit authorization
    var authorizationRequired: Bool {
        return glucoseStore.authorizationRequired ||
               carbStore.authorizationRequired ||
               doseStore.authorizationRequired
    }

    /// True if the user has explicitly denied access to any stores' HealthKit types
    private var sharingDenied: Bool {
        return glucoseStore.sharingDenied ||
               carbStore.sharingDenied ||
               doseStore.sharingDenied
    }

    func authorize(_ completion: @escaping () -> Void) {
        // Authorize all types at once for simplicity
        carbStore.healthStore.requestAuthorization(toShare: [], read: sampleTypes) { (success, error) in
            if success {
                // Call the individual authorization methods to trigger query creation
                self.carbStore.authorize(toShare: false, { _ in })
                self.doseStore.insulinDeliveryStore.authorize(toShare: false, { _ in })
                self.glucoseStore.authorize(toShare: false, { _ in })
            }

            completion()
        }
    }
}


struct GlucoseEffects {
    var dateInterval: DateInterval
    
    var glucose: [StoredGlucoseSample]
    var insulinEffects: [GlucoseEffect]
    var counteractionEffects: [GlucoseEffectVelocity]
    var carbEffects: [GlucoseEffect]
    var retrospectiveGlucoseDiscrepanciesSummed: [GlucoseChange]
}
