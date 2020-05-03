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
import HealthKit

class NightscoutDataSource: LearnDataSource {

    typealias RawStateValue = [String: Any]
    
    var category: String {
        return "Nightscout"
    }

    var title: String
    
    var identifier: String
    
    var api: NightscoutUploader

    init?(rawState: RawStateValue) {
        guard
            let title = rawState["title"] as? String,
            let identifier = rawState["identifier"] as? String
        else {
            return nil
        }
        
        self.title = title
        self.identifier = identifier
        
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
        ]
    }
    
    init(title: String, identifier: String, api: NightscoutUploader) {
        self.title = title
        self.identifier = identifier
        self.api = api
    }
    
    func getGlucoseSamples(start: Date, end: Date?, completion: @escaping (Result<[StoredGlucoseSample]>) -> Void) {
        // 2 weeks of 5m glucose is 4032 samples
        api.fetchGlucose(dateInterval: DateInterval(start: start, end: end ?? Date()), maxCount: 6000) { (result) in
            switch result {
            case .failure(let error):
                print("Error fetching glucose: \(error)")
                completion(.failure(error))
            case .success(let samples):
                print("Fetched \(samples.count) glucose samples")
                let glucose = samples.compactMap { $0.asStoredGlucoseSample }.sorted { $0.startDate <= $1.startDate }
                completion(.success(glucose))
            }
        }
    }
    
    func fetchTherapySettings() -> LearnTherapySettings? {
        let fetchGroup = DispatchGroup()
        var settings: LearnTherapySettings?
        
        fetchGroup.enter()
        api.fetchCurrentProfile { (profileFetchResult) in
            switch profileFetchResult {
            case .success(let profileSet):
                if let profile = profileSet.store[profileSet.defaultProfile] {
                    settings = NightscoutTherapySettings(profile: profile)
                }
            default:
                break
            }
            fetchGroup.leave()
        }
        
        _ = fetchGroup.wait(timeout: .distantFuture)
        
        return settings
    }

    func fetchEffects(for day: DateInterval, using therapySettings: LearnTherapySettings) -> Result<GlucoseEffects> {

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
        var neededTreatmentsInterval = DateInterval(start: day.start.addingTimeInterval(-therapySettings.insulinModel.model.effectDuration),
                                                 end: day.end.addingTimeInterval(forecastDuration))

        fetchGroup.enter()
        
        // Issue report generated 2020-05-03 02:55:01 +0000
        let cutoffDate = DateFormatter.descriptionFormatter.date(from: "2020-05-03 02:55:01 +0000")!
        if neededTreatmentsInterval.end > cutoffDate {
            neededTreatmentsInterval.end = cutoffDate
        }
        
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
        let normalizedDoses = doses.reversed().reconciled().annotated(with: therapySettings.basalSchedule)
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
            delta: therapySettings.delta
        )

        // Get timeline of glucose discrepancies
        let retrospectiveGlucoseDiscrepancies: [GlucoseEffect] = counteractionEffects.subtracting(carbEffects, withUniformInterval: therapySettings.delta)

        let retrospectiveCorrectionGroupingIntervalMultiplier = 1.01
        
        let retrospectiveGlucoseDiscrepanciesSummed: [GlucoseChange] = retrospectiveGlucoseDiscrepancies.combinedSums(of: therapySettings.retrospectiveCorrectionGroupingInterval * retrospectiveCorrectionGroupingIntervalMultiplier)
        
        let glucoseEffects = GlucoseEffects(dateInterval: day, glucose: glucose, insulinEffects: insulinEffects, counteractionEffects: counteractionEffects, carbEffects: carbEffects, retrospectiveGlucoseDiscrepanciesSummed: retrospectiveGlucoseDiscrepanciesSummed)
        
        return .success(glucoseEffects)
    }
}

struct NightscoutTherapySettings: LearnTherapySettings {
    var momentumDataInterval: TimeInterval
    
    var insulinModel: InsulinModelSettings
    
    var basalSchedule: BasalRateSchedule
    
    var sensitivity: InsulinSensitivitySchedule
    
    var carbRatios: CarbRatioSchedule
    
    var absorptionTimeOverrun: Double
    
    var defaultAbsorptionTime: TimeInterval
    
    var carbAbsortionModel: CarbAbsorptionModel
    
    var carbEffectDelay: TimeInterval
    
    var retrospectiveCorrectionGroupingInterval: TimeInterval

    var retrospectiveCorrection: RetrospectiveCorrection
    
    var delta: TimeInterval
    
    var inputDataRecencyInterval: TimeInterval
    
    init?(profile: ProfileSet.Profile) {
        momentumDataInterval = TimeInterval(minutes: 15)
        // TODO: Not currently provided in NS
        insulinModel = InsulinModelSettings.exponentialPreset(.humalogNovologAdult)
        
        guard
            let basalSchedule = BasalRateSchedule(dailyItems: profile.basal.compactMap { RepeatingScheduleValue<Double>(startTime: $0.offset, value: $0.value) }, timeZone: profile.timeZone),
            let sensitivitySchedule = InsulinSensitivitySchedule(unit: HKUnit.milligramsPerDeciliter, dailyItems: profile.sensitivity.compactMap { RepeatingScheduleValue<Double>(startTime: $0.offset, value: $0.value) }, timeZone: profile.timeZone),
            let carbRatioSchedule = CarbRatioSchedule(unit: HKUnit.gram(), dailyItems: profile.carbratio.compactMap { RepeatingScheduleValue<Double>(startTime: $0.offset, value: $0.value) }, timeZone: profile.timeZone)
        else {
            return nil
        }
        
        self.basalSchedule = basalSchedule
        self.sensitivity = sensitivitySchedule
        self.carbRatios = carbRatioSchedule
        
        // TODO: Not currently provided in NS; using Loop default
        self.absorptionTimeOverrun = 1.5
        // TODO: Not currently provided in NS; using Loop default
        self.defaultAbsorptionTime = TimeInterval(hours: 3)
        // TODO: Not currently provided in NS; using Loop default
        self.carbAbsortionModel = CarbAbsorptionModel.nonlinear
        // TODO: Not currently provided in NS; using Loop default
        self.carbEffectDelay = TimeInterval(minutes: 10)
        // TODO: Not currently provided in NS; using Loop default
        self.retrospectiveCorrectionGroupingInterval = TimeInterval(minutes: 30)
        let retrospectiveCorrectionEffectDuration = TimeInterval(hours: 1)
        self.retrospectiveCorrection = StandardRetrospectiveCorrection(effectDuration: retrospectiveCorrectionEffectDuration)
        
        self.delta = TimeInterval(minutes: 5)
        // TODO: Not currently provided in NS; using Loop default
        self.inputDataRecencyInterval = TimeInterval(minutes: 15)
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


extension DateFormatter {
    static var descriptionFormatter: DateFormatter {
        let formatter = self.init()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ssZZZZZ"

        return formatter
    }
}
