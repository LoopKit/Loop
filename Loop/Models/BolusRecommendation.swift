//
//  BolusRecommendation.swift
//  Loop
//
//  Created by Pete Schwamb on 1/2/17.
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import HealthKit

enum BolusRecommendationNotice: CustomStringConvertible, Equatable {
    case glucoseBelowMinimumGuard
    case currentGlucoseBelowTarget
    case predictedGlucoseBelowTarget(minGlucose: GlucoseValue, unit: HKUnit)

    public var description: String {
        switch self {
        case .glucoseBelowMinimumGuard:
            return NSLocalizedString("Predicted glucose is below your minimum BG Guard setting.", comment: "Notice message when recommending bolus when BG is below minimum BG guard.")
        case .currentGlucoseBelowTarget:
            return NSLocalizedString("Glucose is below target range.", comment: "Message when offering bolus prediction even though bg is below range.")
        case .predictedGlucoseBelowTarget(let minGlucose, let unit):
            let timeFormatter = DateFormatter()
            timeFormatter.dateStyle = .none
            timeFormatter.timeStyle = .short
            let time = timeFormatter.string(from: minGlucose.startDate)

            let numberFormatter = NumberFormatter.glucoseFormatter(for: unit)

            let minBGStr = numberFormatter.describingGlucose(minGlucose.quantity, for: unit)!

            return String(format: NSLocalizedString("Predicted glucose at %1$@ is %2$@.", comment: "Message when offering bolus prediction even though bg is below range and minBG is in future. (1: glucose time)(2: glucose number)"), time, minBGStr)

        }
    }

    static func ==(lhs: BolusRecommendationNotice, rhs: BolusRecommendationNotice) -> Bool {
        switch (lhs, rhs) {
        case (.glucoseBelowMinimumGuard, .glucoseBelowMinimumGuard):
            return true

        case (.currentGlucoseBelowTarget, .currentGlucoseBelowTarget):
            return true

        case (let .predictedGlucoseBelowTarget(minGlucose1, unit1), let .predictedGlucoseBelowTarget(minGlucose2, unit2)):
            // GlucoseValue is not equatable
            return
                minGlucose1.startDate == minGlucose2.startDate &&
                minGlucose1.endDate == minGlucose2.endDate &&
                minGlucose1.quantity == minGlucose2.quantity &&
                unit1 == unit2

        default:
            return false
        }
    }
}


struct BolusRecommendation {
    let amount: Double
    let pendingInsulin: Double
    let notice: BolusRecommendationNotice?

    init(amount: Double, pendingInsulin: Double, notice: BolusRecommendationNotice? = nil) {
        self.amount = amount
        self.pendingInsulin = pendingInsulin
        self.notice = notice
    }
}
