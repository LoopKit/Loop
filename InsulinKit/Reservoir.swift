//
//  Reservoir.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/29/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import CoreData


class Reservoir: NSManagedObject {

    var volume: Double! {
        get {
            willAccessValueForKey("volume")
            defer { didAccessValueForKey("volume") }
            return primitiveVolume?.doubleValue
        }
        set {
            willChangeValueForKey("volume")
            defer { didChangeValueForKey("volume") }
            primitiveVolume = volume != nil ? NSNumber(double: volume) : nil
        }
    }

    override func awakeFromInsert() {
        super.awakeFromInsert()

        createdAt = NSDate()
    }
}


extension Reservoir: Fetchable { }


extension Reservoir: ReservoirValue {
    var startDate: NSDate {
        return date
    }

    var unitVolume: Double {
        return volume
    }
}