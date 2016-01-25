//
//  GlucoseStore.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/24/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit


public class GlucoseStore: HealthKitSampleStore {

    private let glucoseType = HKQuantityType.quantityTypeForIdentifier(HKQuantityTypeIdentifierBloodGlucose)!

    public override var readTypes: Set<HKSampleType> {
        return Set(arrayLiteral: glucoseType)
    }

    public override var shareTypes: Set<HKSampleType> {
        return Set(arrayLiteral: glucoseType)
    }

    public override init?() {
        super.init()

        if !authorizationRequired {

        }
    }

 /// The interval before which glucose values should be parsed from HealthKit.
    private var purgeAfterInterval: NSTimeInterval? = NSTimeInterval(hours: 3)

    public func addGlucose(quantity: HKQuantity, date: NSDate, device: HKDevice?, resultHandler: (Bool, HKQuantitySample?, NSError?) -> Void) {

        let glucose = HKQuantitySample(type: glucoseType, quantity: quantity, startDate: date, endDate: date, device: device, metadata: nil)

        healthStore.saveObject(glucose) { (completed, error) -> Void in
            resultHandler(completed, glucose, error)
        }

//        let device = HKDevice(name: "xDripG5", manufacturer: "Dexcom", model: "G5 Mobile", hardwareVersion: nil, firmwareVersion: nil, softwareVersion: String(xDripG5VersionNumber), localIdentifier: nil, UDIDeviceIdentifier: "00386270000224")
    }
}
