//
//  SleepStore.swift
//  Loop
//
//  Created by Anna Quinlan on 12/28/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit

enum SleepStoreResult<T> {
    case success(T)
    case failure(Error)
}

enum SleepStoreError: Error {
    case noMatchingBedtime
    case unknownReturnConfiguration
    case noSleepDataAvailable
}

extension SleepStoreError: LocalizedError {
    public var localizedDescription: String {
        switch self {
        case .noMatchingBedtime:
            return NSLocalizedString("Could not find a matching bedtime", comment: "")
        case .unknownReturnConfiguration:
            return NSLocalizedString("Unknown return configuration from query", comment: "")
        case .noSleepDataAvailable:
            return NSLocalizedString("No sleep data available", comment: "")
        }
    }
}

class SleepStore {
    var healthStore: HKHealthStore
    var sampleLimit: Int
    
    public init(
        healthStore: HKHealthStore,
        sampleLimit: Int = 30
    ) {
        self.healthStore = healthStore
        self.sampleLimit = sampleLimit
    }
    
    func getAverageSleepStartTime(_ completion: @escaping (_ result: SleepStoreResult<Date>) -> Void) {
        let inBedPredicate = HKQuery.predicateForCategorySamples(
            with: .equalTo,
            value: HKCategoryValueSleepAnalysis.inBed.rawValue
        )
        
        let asleepPredicate = HKQuery.predicateForCategorySamples(
            with: .equalTo,
            value: HKCategoryValueSleepAnalysis.asleep.rawValue
        )
        
        getAverageSleepStartTime(matching: inBedPredicate, sampleLimit: sampleLimit) {
            (result) in
            switch result {
            case .success(_):
                completion(result)
            case .failure(let error):
                switch error {
                case SleepStoreError.noSleepDataAvailable:
                    // if there were no .inBed samples, check if there are any .asleep samples that could be used to estimate bedtime
                    self.getAverageSleepStartTime(matching: asleepPredicate, sampleLimit: self.sampleLimit, completion)
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
                completion(.failure(error))
            } else if let samples = samples as? [HKCategorySample] {
                guard !samples.isEmpty else {
                    completion(.failure(SleepStoreError.noSleepDataAvailable))
                    return
                }
                
                // find the average hour and minute components from the sleep start times
                let average = samples.reduce(0, {$0 + $1.startDate.timeOfDayInSeconds()}) / samples.count
                let averageHour = average / 3600
                let averageMinute = average % 3600 / 60
                
                // find the next time that the user will go to bed, based on the averages we've computed
                if let bedtime = Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: averageHour, minute: averageMinute), matchingPolicy: .nextTime), bedtime.timeIntervalSinceNow <= .hours(24) {
                    completion(.success(bedtime))
                } else {
                    completion(.failure(SleepStoreError.noMatchingBedtime))
                }
            } else {
                completion(.failure(SleepStoreError.unknownReturnConfiguration))
            }
        }
        healthStore.execute(query)
    }
}

extension Date {
    fileprivate func timeOfDayInSeconds() -> Int {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.hour, .minute, .second], from: self)
        let dateSeconds = dateComponents.hour! * 3600 + dateComponents.minute! * 60 + dateComponents.second!

        return dateSeconds
    }
}
