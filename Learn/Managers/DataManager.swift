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

        carbStore = CarbStore(
            healthStore: healthStore,
            cacheStore: cacheStore,
            observationEnabled: false,
            carbRatioSchedule: carbRatioSchedule,
            insulinSensitivitySchedule: insulinSensitivitySchedule
        )

        doseStore = DoseStore(
            healthStore: healthStore,
            cacheStore: cacheStore,
            observationEnabled: false,
            insulinModel: insulinModelSettings?.model,
            basalProfile: basalRateSchedule,
            insulinSensitivitySchedule: insulinSensitivitySchedule
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
