//
//  HKUnit.swift
//  Loop
//
//  Created by Bharat Mediratta on 12/2/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import HealthKit

// Code in this extension is duplicated from:
//   https://github.com/LoopKit/LoopKit/blob/master/LoopKit/HKUnit.swift
// to avoid pulling in the LoopKit extension since it's not extension-API safe.
extension HKUnit {
    // A formatting helper for determining the preferred decimal style for a given unit
    var preferredFractionDigits: Int {
        if self.unitString == "mg/dL" {
            return 0
        } else {
            return 1
        }
    }

    static func milligramsPerDeciliter() -> HKUnit {
        return HKUnit.gramUnit(with: .milli).unitDivided(by: HKUnit.literUnit(with: .deci))
    }
    
    static func millimolesPerLiter() -> HKUnit {
        return HKUnit.moleUnit(with: .milli, molarMass: HKUnitMolarMassBloodGlucose).unitDivided(by: HKUnit.liter())
    }
    
    // A glucose-centric presentation helper for the localized unit string
    var glucoseUnitDisplayString: String {
        if self == HKUnit.millimolesPerLiter() {
            return NSLocalizedString("mmol/L", comment: "The unit display string for millimoles of glucose per liter")
        } else {
            return String(describing: self)
        }
    }

}
