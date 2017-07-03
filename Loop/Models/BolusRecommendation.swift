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
    case glucoseBelowMinimumGuard(minGlucose: GlucoseValue, unit: HKUnit)
    case currentGlucoseBelowTarget(glucose: GlucoseValue, unit: HKUnit)
    case predictedGlucoseBelowTarget(minGlucose: GlucoseValue, unit: HKUnit)

    public var description: String {

        switch self {
        case .glucoseBelowMinimumGuard(let minGlucose, let unit):
            let glucoseFormatter = NumberFormatter.glucoseFormatter(for: unit)
            let bgStr = glucoseFormatter.describingGlucose(minGlucose.quantity, for: unit)!
            return String(format: NSLocalizedString("Predicted glucose of %1$@ is below your minimum BG Guard setting.", comment: "Notice message when recommending bolus when BG is below minimum BG guard. (1: glucose value)"), bgStr)
        case .currentGlucoseBelowTarget(let glucose, let unit):
            let glucoseFormatter = NumberFormatter.glucoseFormatter(for: unit)
            let bgStr = glucoseFormatter.describingGlucose(glucose.quantity, for: unit)!
            return String(format: NSLocalizedString("Current glucose of %1$@ is below target range.", comment: "Message when offering bolus recommendation even though bg is below range. (1: glucose value)"), bgStr)
        case .predictedGlucoseBelowTarget(let minGlucose, let unit):
            let timeFormatter = DateFormatter()
            timeFormatter.dateStyle = .none
            timeFormatter.timeStyle = .short
            let time = timeFormatter.string(from: minGlucose.startDate)

            let glucoseFormatter = NumberFormatter.glucoseFormatter(for: unit)
            let minBGStr = glucoseFormatter.describingGlucose(minGlucose.quantity, for: unit)!
            return String(format: NSLocalizedString("Predicted glucose at %1$@ is %2$@.", comment: "Message when offering bolus recommendation even though bg is below range and minBG is in future. (1: glucose time)(2: glucose number)"), time, minBGStr)

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


extension BolusRecommendation: Comparable {
    static func ==(lhs: BolusRecommendation, rhs: BolusRecommendation) -> Bool {
        return lhs.amount == rhs.amount
    }

    static func <(lhs: BolusRecommendation, rhs: BolusRecommendation) -> Bool {
        return lhs.amount < rhs.amount
    }
}

