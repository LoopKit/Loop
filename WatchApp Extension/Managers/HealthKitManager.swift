//
//  HealthKitManager.swift
//  WatchApp Extension
//
//  Created by Bharat Mediratta on 6/21/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit


class HealthKitManager {
    let healthStore = HKHealthStore()

    func getCachedGlucoseSamples(completion: @escaping ([HKQuantitySample]) -> ()) {
        let startDate = max(Date().addingTimeInterval(TimeInterval(hours: -2)), healthStore.earliestPermittedSampleDate())
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let sortDescriptors = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!

        let query = HKSampleQuery(sampleType: glucoseType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: sortDescriptors) { (_, samples, error) -> Void in
            if error == nil, let samples = samples as? [HKQuantitySample] {
                completion(samples)
            }
        }
        healthStore.execute(query)
    }
}
