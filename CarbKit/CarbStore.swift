//
//  CarbStore.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/3/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit


public class CarbStore {

    private let foodType = HKCorrelationType.correlationTypeForIdentifier(HKCorrelationTypeIdentifierFood)!

    private let carbType = HKQuantityType.quantityTypeForIdentifier(HKQuantityTypeIdentifierDietaryCarbohydrates)!

    /// All the sample types we need permission to read.
    /// Eventually, we want to consider fat, protein, and other factors to estimate carb absorption.
    private var readTypes: Set<HKSampleType> {
        return Set(arrayLiteral: carbType)
    }

    private var shareTypes: Set<HKSampleType> {
        return Set(arrayLiteral: carbType)
    }

    /// The health store used for underlying queries
    public let healthStore = HKHealthStore()

    /// The longest expected absorption time interval for carbohydrates. Defaults to 6 hours.
    public let maximumAbsorptionTimeInterval: NSTimeInterval

    /**
     Initializes a new instance of the store.
     
     `nil` is returned if HealthKit is not available on the current device.

     - returns: A new instance of the store
     */
    public init?(maximumAbsorptionTimeInterval: NSTimeInterval = NSTimeInterval(hours: 6)) {
        self.maximumAbsorptionTimeInterval = maximumAbsorptionTimeInterval

        guard HKHealthStore.isHealthDataAvailable() && !sharingDenied else {
            return nil
        }

        if !authorizationRequired {
            createObserverQueries()
        }
    }

    private var sharingDenied: Bool {
        for type in shareTypes {
            if healthStore.authorizationStatusForType(type) == .SharingDenied {
                return true
            }
        }

        return false
    }

    /// True if the store requires authorization
    public var authorizationRequired: Bool {
        for type in readTypes.union(shareTypes) {
            if healthStore.authorizationStatusForType(type) == .NotDetermined {
                return true
            }
        }

        return false
    }

    /**
     Initializes the HealthKit authorization flow for all required sample types

     - parameter completion: A closure called after authorization is completed. This closure takes two arguments:
        - success: Whether the authorization to share was successful
        - error:   An error object explaining why the authorization was unsuccessful
     */
    public func authorize(completion: (success: Bool, error: NSError?) -> Void) {
        let parentHandler = completion

        healthStore.requestAuthorizationToShareTypes(shareTypes, readTypes: readTypes, completion: { (completed, error) -> Void in

            // Make sure we received authorization to write food and carb data
            let success = completed && !self.sharingDenied
            var authError = error

            if !success && authError == nil {
                authError = NSError(
                    domain: HKErrorDomain,
                    code: HKErrorCode.ErrorAuthorizationDenied.rawValue,
                    userInfo: [
                        NSLocalizedDescriptionKey: NSLocalizedString("com.loudnate.CarbKit.sharingDeniedErrorDescription", tableName: "CarbKit", value: "Authorization Denied", comment: "The error description describing when Health sharing was denied"),
                        NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString("com.loudnate.carbKit.sharingDeniedErrorRecoverySuggestion", tableName: "CarbKit", value: "Please re-enable sharing in Health", comment: "The error recovery suggestion when Health sharing was denied")
                    ]
                )
            }

            if success {
                self.createObserverQueries()
            }

            parentHandler(success: success, error: authError)
        })
    }

    private var observerQueries: [HKObserverQuery] = []

    private func createObserverQueries() {
        let predicate = recentSamplesPredicate()

        for type in readTypes {
            let query = HKObserverQuery(sampleType: type, predicate: predicate, updateHandler: { (query, completionHandler, error) -> Void in

                // Handle new data for `query.sampleType`

                completionHandler()
            })

            healthStore.executeQuery(query)
            observerQueries.append(query)
        }
    }

    deinit {
        for query in observerQueries {
            healthStore.stopQuery(query)
        }
    }

    // MARK: - Background management

    /// Whether background delivery of new data is enabled
    public private(set) var isBackgroundDeliveryEnabled = false

    /**
     Enables the background delivery of updates to carbohydrate data.
     
     This is necessary if carbohydrate data is used in a long-running task (like automated dosing) and new entries are expected from other apps or input sources.

     - parameter enabled:    Whether to enable or disable background delivery
     - parameter completion: A closure called after the background delivery preference is changed. The closure takes two arguments:
        - Whether the background delivery preference was successfully updated
        - An error object explaining why the preference failed to update
     */
    public func setBackgroundDeliveryEnabled(enabled: Bool, completion: (Bool, NSError?) -> Void) {
        dispatch_async(dispatch_get_main_queue()) { () -> Void in
            let oldValue = self.isBackgroundDeliveryEnabled
            self.isBackgroundDeliveryEnabled = enabled

            switch (oldValue, enabled) {
            case (false, true):
                let group = dispatch_group_create()
                var lastError: NSError?

                for type in self.readTypes {
                    dispatch_group_enter(group)
                    self.healthStore.enableBackgroundDeliveryForType(type, frequency: .Immediate, withCompletion: { [unowned self] (enabled, error) -> Void in
                        if !enabled {
                            self.isBackgroundDeliveryEnabled = oldValue

                            lastError = error
                        }

                        dispatch_group_leave(group)
                    })
                }

                dispatch_group_notify(group, dispatch_get_main_queue()) {
                    completion(enabled == self.isBackgroundDeliveryEnabled, lastError)
                }
            case (true, false):
                let group = dispatch_group_create()
                var lastError: NSError?

                for type in self.readTypes {
                    dispatch_group_enter(group)
                    self.healthStore.disableBackgroundDeliveryForType(type, withCompletion: { [unowned self] (disabled, error) -> Void in
                        if !disabled {
                            self.isBackgroundDeliveryEnabled = oldValue

                            lastError = error
                        }

                        dispatch_group_leave(group)
                    })
                }

                dispatch_group_notify(group, dispatch_get_main_queue()) {
                    completion(enabled == self.isBackgroundDeliveryEnabled, lastError)
                }
            default:
                completion(true, nil)
            }
        }
    }

    // MARK: - Data fetching

    private func recentSamplesPredicate() -> NSPredicate {
        return HKQuery.predicateForSamplesWithStartDate(NSDate(timeIntervalSinceNow: -maximumAbsorptionTimeInterval), endDate: NSDate.distantFuture(), options: [.StrictStartDate])
    }

    public func getRecentCarbEntries(resultsHandler: ([CarbEntry], NSError?) -> Void) {
        let startDateDesc = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let query = HKSampleQuery(sampleType: carbType, predicate: recentSamplesPredicate(), limit: Int(HKObjectQueryNoLimit), sortDescriptors: [startDateDesc]) { (query, samples, error) -> Void in
            var entries = [CarbEntry]()

            if let samples = samples as? [HKQuantitySample] {
                for sample in samples {
                    entries.append(CarbEntry(
                        amount: sample.quantity.doubleValueForUnit(HKUnit.gramUnit()),
                        startDate: sample.startDate,
                        description: sample.foodType,
                        absorptionTime: sample.absorptionTime,
                        sampleUUID: sample.UUID
                    ))
                }
            }

            resultsHandler(entries, error)
        }

        healthStore.executeQuery(query)
    }
}
