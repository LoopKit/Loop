//
//  RemoteDataManager.swift
//  Learn
//
//  Created by Pete Schwamb on 4/19/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import NightscoutUploadKit
import LoopCore
import LoopKit
import HealthKit

class RemoteDataManager: EffectsFetcher {
    
    var forecastDuration: TimeInterval
    
    let nightscout = NightscoutUploader(siteURL: URL(string: "https://mysite.herokuapp.com/")!, APISecret: "asdf")
    
    init(forecastDuration: ) {
        
    }
    
    func fetchEffects(for day: DateInterval, retrospectiveCorrection: RetrospectiveCorrection, momentumDataInterval: TimeInterval) -> Result<GlucoseEffects> {

        let fetchGroup = DispatchGroup()
        
        var glucose: [StoredGlucoseSample]? = []
//        var insulinEffects: [GlucoseEffect]?
//        var counteractionEffects: [GlucoseEffectVelocity]?
//        var carbEffects: [GlucoseEffect]?
//        var retrospectiveGlucoseDiscrepanciesSummed: [GlucoseChange]?

        fetchGroup.enter()
        let neededGlucoseInterval = DateInterval(start: day.start.addingTimeInterval(-momentumDataInterval),
                                                 end: day.end.addingTimeInterval(forecastDuration))
        nightscout.fetchGlucose(dateInterval: neededGlucoseInterval, maxCount: 600) { (result) in
            switch result {
            case .failure(let error):
                print("Error fetching glucose: \(error)")
            case .success(let samples):
                print("Fetched \(samples.count) glucose samples")
                glucose = samples.compactMap { $0.asStoredGlucoseSample }
            }
            fetchGroup.leave()
        }
        
        fetchGroup.enter()
        nightscout.fetchTreatments(dateInterval: day, maxCount: 500) { (result) in
            switch result {
            case .failure(let error):
                print("Error fetching glucose: \(error)")
            case .success(let treatments):
                print("Fetched \(treatments.count) treatments")
            }
            fetchGroup.leave()
        }
        
        _ = fetchGroup.wait(timeout: .now() + .seconds(10))
        
        let glucoseEffects = GlucoseEffects(dateInterval: day, glucose: glucose!, insulinEffects: [], counteractionEffects: [], carbEffects: [], retrospectiveGlucoseDiscrepanciesSummed: [])
        
        return .success(glucoseEffects)
    }
}

extension GlucoseEntry {
    var asStoredGlucoseSample: StoredGlucoseSample? {
        
        guard let uuid = identifier.asUUID else {
            return nil
        }
        
        return StoredGlucoseSample(
            sampleUUID: uuid,
            syncIdentifier: identifier,
            syncVersion: 0,
            startDate: date,
            quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: sgv),
            isDisplayOnly: false,
            provenanceIdentifier: device)
    }
}

extension String {
    var asUUID: UUID? {
        guard let data = padding(toLength: 32, withPad: " ", startingAt: 0).data(using: .utf8) else {
            return nil
        }
        return data.withUnsafeBytes { $0.load(as: UUID.self) }
    }
}
