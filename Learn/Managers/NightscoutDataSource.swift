//
//  NightscoutDataSource.swift
//  Learn
//
//  Created by Pete Schwamb on 4/19/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import NightscoutUploadKit
import LoopKit
import LoopUI
import LoopCore

class NightscoutDataSource: LearnDataSource {

    typealias RawStateValue = [String: Any]
    
    var category: String {
        return "Nightscout"
    }

    var title: String
    
    var identifier: String
    
    var therapySettings: LearnTherapySettings
    
    var api: NightscoutUploader

    init?(rawState: RawStateValue) {
        guard
            let title = rawState["title"] as? String,
            let identifier = rawState["identifier"] as? String,
            let settingsRaw = rawState["settings"] as? LearnTherapySettings.RawValue,
            let settings = LearnTherapySettings(rawValue: settingsRaw)
        else {
            return nil
        }
        
        self.title = title
        self.identifier = identifier
        self.therapySettings = settings
        
        let keychain = KeychainManager()
        
        if let (siteURL, APISecret) = keychain.getNightscoutCredentials(identifier: identifier) {
            self.api = NightscoutUploader(siteURL: siteURL, APISecret: APISecret)
        } else {
            return nil
        }
    }

    var rawState: RawStateValue {
        return [
            "title": title,
            "identifier": identifier,
            "settings": therapySettings.rawValue
        ]
    }
    
    init(title: String, identifier: String, api: NightscoutUploader, therapySettings: LearnTherapySettings) {
        self.title = title
        self.identifier = identifier
        self.therapySettings = therapySettings
        self.api = api
    }
    
    func fetchEffects(for day: DateInterval, retrospectiveCorrection: RetrospectiveCorrection, delta: TimeInterval) -> Result<GlucoseEffects> {

        let fetchGroup = DispatchGroup()
        
        var glucose: [StoredGlucoseSample] = []
        
        let forecastDuration = therapySettings.insulinModel.model.effectDuration

        let neededGlucoseInterval = DateInterval(start: day.start.addingTimeInterval(-therapySettings.momentumDataInterval),
                                                 end: day.end.addingTimeInterval(forecastDuration))

        fetchGroup.enter()
        print("Fetching glucose for: \(neededGlucoseInterval)")
        api.fetchGlucose(dateInterval: neededGlucoseInterval, maxCount: 600) { (result) in
            switch result {
            case .failure(let error):
                print("Error fetching glucose: \(error)")
            case .success(let samples):
                print("Fetched \(samples.count) glucose samples")
                glucose = samples.compactMap { $0.asStoredGlucoseSample }.sorted { $0.startDate <= $1.startDate }
            }
            fetchGroup.leave()
        }

        _ = fetchGroup.wait(timeout: .distantFuture)

        var treatments: [NightscoutTreatment] = []
        let neededTreatmentsInterval = DateInterval(start: day.start.addingTimeInterval(-therapySettings.insulinModel.model.effectDuration),
                                                 end: day.end.addingTimeInterval(forecastDuration))

        fetchGroup.enter()
        print("Fetching treatments for: \(neededTreatmentsInterval)")
        api.fetchTreatments(dateInterval: neededTreatmentsInterval, maxCount: 500) { (result) in
            switch result {
            case .failure(let error):
                print("Error fetching treatments: \(error)")
            case .success(let fetchedTreatments):
                print("Fetched \(fetchedTreatments.count) treatments")
                treatments = fetchedTreatments
            }
            fetchGroup.leave()
        }
        
        _ = fetchGroup.wait(timeout: .distantFuture)
        
        let doses = treatments.compactMap { $0.dose }
        print("Found \(doses.count) doses")
        let normalizedDoses = doses.reconciled().annotated(with: therapySettings.basalSchedule)
        print("Normalized to \(normalizedDoses.count) doses")
        let insulinEffects = normalizedDoses.glucoseEffects(insulinModel: therapySettings.insulinModel.model, insulinSensitivity: therapySettings.sensitivity)
        
        let carbEntries = treatments.compactMap { $0.carbEntry }
        print("Found \(carbEntries.count) carb entries")
        
        let counteractionEffects = glucose.counteractionEffects(to: insulinEffects)

        let carbModelSettings = therapySettings.carbModelSettings
        
        let carbEffects = carbEntries.map(
            to: counteractionEffects,
            carbRatio: therapySettings.carbRatios,
            insulinSensitivity: therapySettings.sensitivity,
            absorptionTimeOverrun: therapySettings.absorptionTimeOverrun,
            defaultAbsorptionTime: therapySettings.defaultAbsorptionTime,
            delay: therapySettings.carbEffectDelay,
            initialAbsorptionTimeOverrun: carbModelSettings.initialAbsorptionTimeOverrun,
            absorptionModel: carbModelSettings.absorptionModel,
            adaptiveAbsorptionRateEnabled: carbModelSettings.adaptiveAbsorptionRateEnabled,
            adaptiveRateStandbyIntervalFraction: carbModelSettings.adaptiveRateStandbyIntervalFraction
        ).dynamicGlucoseEffects(
            from: neededTreatmentsInterval.start,
            to: neededTreatmentsInterval.end,
            carbRatios: therapySettings.carbRatios,
            insulinSensitivities: therapySettings.sensitivity,
            defaultAbsorptionTime: therapySettings.defaultAbsorptionTime,
            absorptionModel: carbModelSettings.absorptionModel,
            delay: therapySettings.carbEffectDelay,
            delta: delta
        )

        // Get timeline of glucose discrepancies
        let retrospectiveGlucoseDiscrepancies: [GlucoseEffect] = counteractionEffects.subtracting(carbEffects, withUniformInterval: delta)

        let retrospectiveCorrectionGroupingIntervalMultiplier = 1.01
        
        let retrospectiveGlucoseDiscrepanciesSummed: [GlucoseChange] = retrospectiveGlucoseDiscrepancies.combinedSums(of: therapySettings.retrospectiveCorrectionGroupingInterval * retrospectiveCorrectionGroupingIntervalMultiplier)
        
        let glucoseEffects = GlucoseEffects(dateInterval: day, glucose: glucose, insulinEffects: insulinEffects, counteractionEffects: counteractionEffects, carbEffects: carbEffects, retrospectiveGlucoseDiscrepanciesSummed: retrospectiveGlucoseDiscrepanciesSummed)
        
        return .success(glucoseEffects)
    }
}

extension NightscoutTreatment {
    var dose: DoseEntry? {
        switch self {
        case let bolus as BolusNightscoutTreatment:
            let endDate = bolus.timestamp.addingTimeInterval(bolus.duration)
            return DoseEntry(type: .bolus, startDate: bolus.timestamp, endDate: endDate, value: bolus.amount, unit: .units, deliveredUnits: bolus.amount, description: "Bolus", syncIdentifier: bolus.id, scheduledBasalRate: nil)
        case let tempBasal as TempBasalNightscoutTreatment:
            let endDate = tempBasal.timestamp.addingTimeInterval(tempBasal.duration)
            return DoseEntry(type: .tempBasal, startDate: tempBasal.timestamp, endDate: endDate, value: tempBasal.rate, unit: .unitsPerHour, deliveredUnits: tempBasal.amount, description: "TempBasal", syncIdentifier: tempBasal.id, scheduledBasalRate: nil)
        default:
            return nil
        }
    }

    var carbEntry: StoredCarbEntry? {
        switch self {
        case let meal as MealBolusNightscoutTreatment:
            guard let identifier = meal.id, let uuid = identifier.asUUID else {
                return nil
            }
            return StoredCarbEntry(sampleUUID: uuid, syncIdentifier: identifier, syncVersion: 0, startDate: meal.timestamp, unitString: "g", value: meal.carbs, foodType: meal.foodType, absorptionTime: meal.absorptionTime, createdByCurrentApp: false, externalID: identifier, isUploaded: true)
        default:
            return nil
        }
    }

}
