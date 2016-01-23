//
//  CarbStore.swift
//  CarbKit
//
//  Created by Nathan Racklyeft on 1/3/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit


public class CarbStore {

    public static let CarbEntriesDidUpdateNotification = "com.loudnate.CarbKit.CarbEntriesDidUpdateNotification"

    /// The `CarbEntriesDidUpdateNotification` user info key for an array of new CarbEntry items
    public static let CarbEntriesAddedUserInfoKey = "com.loudnate.CarbKit.CarbEntriesAddedKey"

    /// The `CarbEntriesDidUpdateNotification` user info key for an array of removed CarbEntry items
    public static let CarbEntriesRemovedUserInfoKey = "com.loudnate.CarbKit.CarbEntriesRemovedKey"

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

    /// A span of default carbohydrate absorption times. Defaults to 2, 3, and 4 hours.
    public let defaultAbsorptionTimes: [NSTimeInterval]

    /// The longest expected absorption time interval for carbohydrates. Defaults to 4 hours.
    private let maximumAbsorptionTimeInterval: NSTimeInterval

    /**
     Initializes a new instance of the store.
     
     `nil` is returned if HealthKit is not available on the current device.

     - returns: A new instance of the store
     */
    public init?(defaultAbsorptionTimes: [NSTimeInterval] = [NSTimeInterval(hours: 2), NSTimeInterval(hours: 3), NSTimeInterval(hours: 4)]) {
        self.defaultAbsorptionTimes = defaultAbsorptionTimes.sort()
        self.maximumAbsorptionTimeInterval = defaultAbsorptionTimes.last ?? NSTimeInterval(hours: 4)

        guard HKHealthStore.isHealthDataAvailable() && !sharingDenied && defaultAbsorptionTimes.count > 0 else {
            return nil
        }

        if !authorizationRequired {
            createQueries()
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
                        NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString("com.loudnate.CarbKit.sharingDeniedErrorRecoverySuggestion", tableName: "CarbKit", value: "Please re-enable sharing in Health", comment: "The error recovery suggestion when Health sharing was denied")
                    ]
                )
            }

            if success {
                self.createQueries()
            }

            parentHandler(success: success, error: authError)
        })
    }

    // MARK: - Query

    private var observerQueries: [HKObserverQuery] = []

    private var anchoredObjectQueries: [HKObserverQuery: HKAnchoredObjectQuery] = [:]

    private var queryAnchor: HKQueryAnchor?

    private func createQueries() {
        let predicate = recentSamplesPredicate()

        for type in readTypes {
            let observerQuery = HKObserverQuery(sampleType: type, predicate: predicate, updateHandler: { [unowned self] (query, completionHandler, error) -> Void in

                // TODO: Hand the error to the delegate

                if error == nil {
                    dispatch_async(self.dataAccessQueue) {
                        if self.anchoredObjectQueries[query] == nil {
                            let anchoredObjectQuery = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: self.queryAnchor, limit: Int(HKObjectQueryNoLimit), resultsHandler: self.processResultsFromAnchoredQuery)
                            anchoredObjectQuery.updateHandler = self.processResultsFromAnchoredQuery

                            self.anchoredObjectQueries[query] = anchoredObjectQuery
                            self.healthStore.executeQuery(anchoredObjectQuery)
                        }
                    }
                }

                completionHandler()
            })

            healthStore.executeQuery(observerQuery)
            observerQueries.append(observerQuery)
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

    private func processResultsFromAnchoredQuery(query: HKAnchoredObjectQuery, newSamples: [HKSample]?, deletedSamples: [HKDeletedObject]?, anchor: HKQueryAnchor?, error: NSError?) {
        // TODO: Hand the error to the delegate

        dispatch_async(self.dataAccessQueue) {
            // Prune the sample data based on the startDate and deletedSamples array
            var removedSamples: [HKQuantitySample] = []

            let cutoffDate = NSDate().dateByAddingTimeInterval(-self.maximumAbsorptionTimeInterval)

            // Filter samples to remove
            for sample in self.recentSamples {
                if sample.startDate < cutoffDate {
                    removedSamples.append(sample)
                } else if let deletedSamples = deletedSamples where deletedSamples.contains({ $0.UUID == sample.UUID }) {
                    removedSamples.append(sample)
                }
            }

            // Remove old samples
            removedSamples = removedSamples.flatMap({ self.recentSamples.remove($0) })

            // Append the new samples
            if let samples = newSamples as? [HKQuantitySample] {
                for sample in samples {
                    self.recentSamples.insert(sample)
                }
            }

            // Update the anchor
            self.queryAnchor = anchor

            // Clear the cached calculations
            self.carbsOnBoardCache = nil

            // Notify listeners
            NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.CarbEntriesDidUpdateNotification,
                object: self,
                userInfo: [
                    self.dynamicType.CarbEntriesAddedUserInfoKey: newSamples ?? [],
                    self.dynamicType.CarbEntriesRemovedUserInfoKey: removedSamples
                ]
            )
        }
    }

    private var recentSamples: Set<HKQuantitySample> = []

    private var dataAccessQueue: dispatch_queue_t = dispatch_queue_create("com.loudnate.CarbKit.dataAccessQueue", DISPATCH_QUEUE_SERIAL)

    private func recentSamplesPredicate() -> NSPredicate {
        return HKQuery.predicateForSamplesWithStartDate(NSDate(timeIntervalSinceNow: -maximumAbsorptionTimeInterval), endDate: NSDate.distantFuture(), options: [.StrictStartDate])
    }

    public func getRecentCarbEntries(resultsHandler: ([CarbEntry], NSError?) -> Void) {
        dispatch_async(dataAccessQueue) {
            let entries: [CarbEntry] = self.recentSamples.map({ (sample) in
                return StoredCarbEntry(sample: sample)
            })

            resultsHandler(entries, nil)
        }
    }

    public func addCarbEntry(entry: CarbEntry, resultHandler: (Bool, CarbEntry?, NSError?) -> Void) {
        let amount = HKQuantity(unit: HKUnit.gramUnit(), doubleValue: entry.value)
        var metadata = [String: AnyObject]()

        if let absorptionTime = entry.absorptionTime {
            metadata[MetadataKeyAbsorptionTimeMinutes] = absorptionTime
        }

        if let foodType = entry.foodType {
            metadata[HKMetadataKeyFoodType] = foodType
        }

        let carbs = HKQuantitySample(type: carbType, quantity: amount, startDate: entry.startDate, endDate: entry.startDate, device: nil, metadata: metadata)

        healthStore.saveObject(carbs) { (completed, error) -> Void in
            resultHandler(completed, StoredCarbEntry(sample: carbs), error)
        }
    }

    public func replaceCarbEntry(oldEntry: CarbEntry, withEntry newEntry: CarbEntry, resultHandler: (Bool, CarbEntry?, NSError?) -> Void) {
        deleteCarbEntry(oldEntry) { (completed, error) -> Void in
            if let error = error {
                resultHandler(false, nil, error)
            } else {
                self.addCarbEntry(newEntry, resultHandler: resultHandler)
            }
        }
    }

    public func deleteCarbEntry(entry: CarbEntry, resultHandler: (Bool, NSError?) -> Void) {
        if let entry = entry as? StoredCarbEntry {
            if entry.createdByCurrentApp {
                healthStore.deleteObject(entry.sample, withCompletion: resultHandler)
            } else {
                resultHandler(
                    false,
                    NSError(
                        domain: HKErrorDomain,
                        code: HKErrorCode.ErrorAuthorizationDenied.rawValue,
                        userInfo: [
                            NSLocalizedDescriptionKey: NSLocalizedString("com.loudnate.CarbKit.deleteCarbEntryUnownedErrorDescription", tableName: "CarbKit", value: "Authorization Denied", comment: "The description of an error returned when attempting to delete a sample not shared by the current app"),
                            NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString("com.loudnate.carbKit.sharingDeniedErrorRecoverySuggestion", tableName: "CarbKit", value: "This sample can be deleted from the Health app", comment: "The error recovery suggestion when attempting to delete a sample not shared by the current app")
                        ]
                    )
                )
            }
        } else {
            resultHandler(
                false,
                NSError(
                    domain: HKErrorDomain,
                    code: HKErrorCode.ErrorInvalidArgument.rawValue,
                    userInfo: [
                        NSLocalizedDescriptionKey: NSLocalizedString("com.loudnate.CarbKit.deleteCarbEntryInvalid", tableName: "CarbKit", value: "Invalid Entry", comment: "The description of an error returned when attempting to delete a non-HealthKit sample"),
                        NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString("com.loudnate.carbKit.sharingDeniedErrorRecoverySuggestion", tableName: "CarbKit", value: "This object is not saved in the Health database and therefore cannot be deleted", comment: "The error recovery suggestion when attempting to delete a non-HealthKit sample")
                    ]
                )
            )
        }
    }


    // MARK: - Math

    private var carbsOnBoardCache: [CarbValue]?

    public func carbsOnBoardAtDate(date: NSDate, resultHandler: (CarbValue?) -> Void) {
        dispatch_async(dataAccessQueue) { [unowned self] in
            if self.carbsOnBoardCache == nil {
                let entries: [CarbEntry] = self.recentSamples.map({ StoredCarbEntry(sample: $0) })

                self.carbsOnBoardCache = CarbMath.carbsOnBoardForCarbEntries(entries, defaultAbsorptionTime: self.defaultAbsorptionTimes[self.defaultAbsorptionTimes.count / 2])
            }

            var closestValue: CarbValue?

            if let values = self.carbsOnBoardCache {
                for value in values {
                    if value.startDate <= date {
                        closestValue = value
                    } else {
                        break
                    }
                }
            }

            resultHandler(closestValue)
        }
    }

    public func getTotalRecentCarbValue(resultHandler: (CarbValue?) -> Void) {
        dispatch_async(dataAccessQueue) { [unowned self] in
            let entries: [CarbEntry] = self.recentSamples.map({ StoredCarbEntry(sample: $0) })

            resultHandler(CarbMath.totalCarbsForCarbEntries(entries))
        }
    }
}
