//
//  SleepStore.swift
//  Loop
//
//  Created by Anna Quinlan on 12/28/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import os.log

enum SleepStoreResult<T> {
    case success(T)
    case failure(SleepStoreError)
}

enum SleepStoreError: Error {
    case noMatchingBedtime
    case unknownReturnConfiguration
    case noSleepDataAvailable
    case queryError(String) // String is description of error
}

class SleepStore {
    var healthStore: HKHealthStore
    
    private let log = OSLog(category: "SleepStore")
    
    public init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
    }
    
    func getAverageSleepStartTime(sampleLimit: Int = 30, _ completion: @escaping (_ result: SleepStoreResult<Date>) -> Void) {
        let inBedPredicate = HKQuery.predicateForCategorySamples(
            with: .equalTo,
            value: HKCategoryValueSleepAnalysis.inBed.rawValue
        )
                
        getAverageSleepStartTime(matching: inBedPredicate, sampleLimit: sampleLimit) { (result) in
            switch result {
            case .success(_):
                completion(result)
            case .failure(let error):
                switch error {
                case SleepStoreError.noSleepDataAvailable:
                    // if there were no .inBed samples, check if there are any .asleep samples that could be used to estimate bedtime
                    let asleepPredicate = HKQuery.predicateForCategorySamples(
                        with: .equalTo,
                        value: HKCategoryValueSleepAnalysis.asleep.rawValue
                    )
                    self.getAverageSleepStartTime(matching: asleepPredicate, sampleLimit: sampleLimit, completion)
                default:
                    // otherwise, call completion
                    completion(result)
                }
            }
            
        }
    }

    fileprivate func getAverageSleepStartTime(matching predicate: NSPredicate, sampleLimit: Int, _ completion: @escaping (_ result: SleepStoreResult<Date>) -> Void) {
        let sleepType = HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier.sleepAnalysis)!
        
        // get more-recent values first
        let sortByDate = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: sampleLimit, sortDescriptors: [sortByDate]) { (query, samples, error) in

            if let error = error {
                self.log.error("Error fetching sleep data: %{public}@", String(describing: error))
                completion(.failure(SleepStoreError.queryError(error.localizedDescription)))
            } else if let samples = samples as? [HKCategorySample] {
                guard !samples.isEmpty else {
                    completion(.failure(SleepStoreError.noSleepDataAvailable))
                    return
                }
                
                // find the average hour and minute components from the sleep start times
                let average = samples.reduce(0, { (base, sample) in
                    if let metadata = sample.metadata, let timezoneStr = metadata[HKMetadataKeyTimeZone] as? String, let timezone = NSTimeZone(name: timezoneStr) {
                        return base + sample.startDate.timeOfDayInSeconds(sampleTimeZone: timezone as TimeZone)
                    } else {
                        // default to the current timezone if the sample does not contain one in its metadata
                        return base + sample.startDate.timeOfDayInSeconds(sampleTimeZone: Calendar.current.timeZone)
                    }
                }) / samples.count
                
                let averageHour = average / 3600
                let averageMinute = average % 3600 / 60
                
                // find the next time that the user will go to bed, based on the averages we've computed
                guard let bedtime = Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: averageHour, minute: averageMinute), matchingPolicy: .nextTime), bedtime.timeIntervalSinceNow <= .hours(24) else {
                    completion(.failure(SleepStoreError.noMatchingBedtime))
                    return
                }
                completion(.success(bedtime))
            } else {
                completion(.failure(SleepStoreError.unknownReturnConfiguration))
            }
        }
        healthStore.execute(query)
    }
}

extension Date {
    fileprivate func timeOfDayInSeconds(sampleTimeZone: TimeZone) -> Int {
        var calendar = Calendar.current
        calendar.timeZone = sampleTimeZone
        
        let dateComponents = calendar.dateComponents([.hour, .minute, .second], from: self)
        let dateSeconds = dateComponents.hour! * 3600 + dateComponents.minute! * 60 + dateComponents.second!

        return dateSeconds
    }
}
