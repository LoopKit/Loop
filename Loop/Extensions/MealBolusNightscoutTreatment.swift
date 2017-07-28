//
//  NightscoutTreatment.swift
//  Loop
//
//  Created by Pete Schwamb on 10/7/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation
import NightscoutUploadKit
import CarbKit
import HealthKit

extension MealBolusNightscoutTreatment {
    public convenience init(carbEntry: CarbEntry) {
        let carbGrams = carbEntry.quantity.doubleValue(for: HKUnit.gram())
        self.init(timestamp: carbEntry.startDate, enteredBy: "loop://\(UIDevice.current.name)", id: carbEntry.externalID, carbs: lround(carbGrams), absorptionTime: carbEntry.absorptionTime, foodType: carbEntry.foodType)
    }
}
