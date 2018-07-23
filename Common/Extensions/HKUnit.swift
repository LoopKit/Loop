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

    static let milligramsPerDeciliter: HKUnit = {
        return HKUnit.gramUnit(with: .milli).unitDivided(by: HKUnit.literUnit(with: .deci))
    }()
    
    static let millimolesPerLiter: HKUnit = {
        return HKUnit.moleUnit(with: .milli, molarMass: HKUnitMolarMassBloodGlucose).unitDivided(by: HKUnit.liter())
    }()

    var localizedShortUnitString: String {
        if self == HKUnit.millimolesPerLiter {
            return NSLocalizedString("mmol/L", comment: "The short unit display string for millimoles of glucose per liter")
        } else if self == .milligramsPerDeciliter {
            return NSLocalizedString("mg/dL", comment: "The short unit display string for milligrams of glucose per decilter")
        } else if self == .internationalUnit() {
            return NSLocalizedString("U", comment: "The short unit display string for international units of insulin")
        } else if self == .gram() {
            return NSLocalizedString("g", comment: "The short unit display string for grams")
        } else {
            return String(describing: self)
        }
    }

    /// An example value for the "ideal" target
    var glucoseExampleTargetValue: Double {
        if unitString == "mg/dL" {
            return 100
        } else {
            return 5.5
        }
    }

    /// The smallest value expected to be visible on a chart
    var chartableIncrement: Double {
        if unitString == "mg/dL" {
            return 1
        } else {
            return 1 / 25
        }
    }
}
