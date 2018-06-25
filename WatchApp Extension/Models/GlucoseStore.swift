//
//  GlucoseManager.swift
//  WatchApp Extension
//
//  Created by Bharat Mediratta on 6/22/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit

class GlucoseStore: NSObject {
    let healthStore = HKHealthStore()
    @objc var samples: [HKQuantitySample] = []

    var latestDate: Date {
        return samples.last?.startDate ?? healthStore.earliestPermittedSampleDate()
    }

    var isStale: Bool {
        return latestDate.timeIntervalSinceNow < -TimeInterval(minutes: 4.5)
    }

    override init() {
        super.init()

        let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!
        let query = HKObserverQuery(sampleType: glucoseType, predicate: nil) { (query, completionHandler, error) in
            if error == nil {
                let startDate = max(Date().addingTimeInterval(TimeInterval(hours: -2)), self.latestDate)
                let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
                let query = HKSampleQuery(sampleType: glucoseType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: []) {
                    (_, samples, error) -> Void in
                    if error == nil, let samples = samples as? [HKQuantitySample] {
                        self.add(samples: samples)
                    }
                }
                self.healthStore.execute(query)
            }
        }
        healthStore.execute(query)
    }

    func backfill(samples: [WatchGlucoseContext]) {
        let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!
        add(samples: samples.map {
            HKQuantitySample(type: glucoseType, quantity: $0.quantity, start: $0.startDate, end: $0.startDate)
        })
    }

    private func add(samples new: [HKQuantitySample]) {
        let cutoff = Date().addingTimeInterval(TimeInterval(hours: -2))
        samples = (samples + new).sorted {
            $0.startDate < $1.startDate
            }.filter {
                $0.startDate >= cutoff
        }
        NotificationCenter.default.post(name: .GlucoseUpdated, object: nil)
    }
}
