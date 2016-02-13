//
//  HealthKitSampleStore.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/24/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit


public class HealthKitSampleStore {

    /// All the sample types we need permission to read
    public var readTypes: Set<HKSampleType> {
        return Set()
    }

    /// All the sample types we need permission to share
    public var shareTypes: Set<HKSampleType> {
        return Set()
    }

    /// The health store used for underlying queries
    public let healthStore = HKHealthStore()

    public init?() {
        guard HKHealthStore.isHealthDataAvailable() && !sharingDenied else {
            return nil
        }
    }

    /// True if the user has explicitly denied access to any required share types
    public var sharingDenied: Bool {
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

            let success = completed && !self.sharingDenied
            var authError = error

            if !success && authError == nil {
                authError = NSError(
                    domain: HKErrorDomain,
                    code: HKErrorCode.ErrorAuthorizationDenied.rawValue,
                    userInfo: [
                        NSLocalizedDescriptionKey: NSLocalizedString("com.loudnate.LoopKit.sharingDeniedErrorDescription", tableName: "LoopKit", value: "Authorization Denied", comment: "The error description describing when Health sharing was denied"),
                        NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString("com.loudnate.LoopKit.sharingDeniedErrorRecoverySuggestion", tableName: "LoopKit", value: "Please re-enable sharing in Health", comment: "The error recovery suggestion when Health sharing was denied")
                    ]
                )
            }

            parentHandler(success: success, error: authError)
        })
    }

    /**
     Queries the preferred unit for the authorized share types. If more than one unit is retrieved,
     then the completion contains just one of them.

     - parameter completion: A closure called after the query is completed. This closure takes two arguments:
        - unit:  The retrieved unit
        - error: An error object explaining why the retrieval was unsuccessful
     */
    public func preferredUnit(completion: (unit: HKUnit?, error: NSError?) -> Void) {
        let postAuthHandler = {
            let quantityTypes = self.shareTypes.flatMap { (sampleType) -> HKQuantityType? in
                return sampleType as? HKQuantityType
            }

            self.healthStore.preferredUnitsForQuantityTypes(Set(quantityTypes)) { (quantityToUnit, error) -> Void in
                completion(unit: quantityToUnit.values.first, error: error)
            }
        }

        if authorizationRequired || sharingDenied {
            authorize({ (success, error) -> Void in
                if error != nil {
                    completion(unit: nil, error: error)
                } else {
                    postAuthHandler()
                }
            })
        } else {
            postAuthHandler()
        }
    }

}