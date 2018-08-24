//
//  DoseMath.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/8/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit


private enum InsulinCorrection {
    case inRange
    case aboveRange(min: GlucoseValue, correcting: GlucoseValue, minTarget: HKQuantity, units: Double)
    case entirelyBelowRange(correcting: GlucoseValue, minTarget: HKQuantity, units: Double)
    case suspend(min: GlucoseValue)
}


extension InsulinCorrection {
    /// The delivery units for the correction
    private var units: Double {
        switch self {
        case .aboveRange(min: _, correcting: _, minTarget: _, units: let units):
            return units
        case .entirelyBelowRange(correcting: _, minTarget: _, units: let units):
            return units
        case .inRange, .suspend:
            return 0
        }
    }

    /// Determines the temp basal over `duration` needed to perform the correction.
    ///
    /// - Parameters:
    ///   - scheduledBasalRate: The scheduled basal rate at the time the correction is delivered
    ///   - maxBasalRate: The maximum allowed basal rate
    ///   - duration: The duration of the temporary basal
    ///   - minimumProgrammableIncrementPerUnit: The smallest fraction of a unit supported in basal delivery
    /// - Returns: A temp basal recommendation
    fileprivate func asTempBasal(
        scheduledBasalRate: Double,
        maxBasalRate: Double,
        duration: TimeInterval,
        minimumProgrammableIncrementPerUnit: Double
    ) -> TempBasalRecommendation {
        var rate = units / (duration / TimeInterval(hours: 1))  // units/hour
        switch self {
        case .aboveRange, .inRange, .entirelyBelowRange:
            rate += scheduledBasalRate
        case .suspend:
            break
        }

        rate = Swift.min(maxBasalRate, Swift.max(0, rate))
        rate = round(rate * minimumProgrammableIncrementPerUnit) / minimumProgrammableIncrementPerUnit

        return TempBasalRecommendation(
            unitsPerHour: rate,
            duration: duration
        )
    }

    private var bolusRecommendationNotice: BolusRecommendationNotice? {
        switch self {
        case .suspend(min: let minimum):
            return .glucoseBelowSuspendThreshold(minGlucose: minimum)
        case .inRange, .entirelyBelowRange:
            return nil
        case .aboveRange(min: let min, correcting: _, minTarget: let target, units: let units):
            if units > 0 && min.quantity < target {
                return .predictedGlucoseBelowTarget(minGlucose: min)
            } else {
                return nil
            }
        }
    }

    /// Determins the bolus needed to perform the correction
    ///
    /// - Parameters:
    ///   - pendingInsulin: The number of units expected to be delivered, but not yet reflected in the correction
    ///   - maxBolus: The maximum allowable bolus value in units
    ///   - minimumProgrammableIncrementPerUnit: The smallest fraction of a unit supported in bolus delivery
    /// - Returns: A bolus recommendation
    fileprivate func asBolus(
        pendingInsulin: Double,
        maxBolus: Double,
        minimumProgrammableIncrementPerUnit: Double
    ) -> BolusRecommendation {
        var units = self.units - pendingInsulin
        units = Swift.min(maxBolus, Swift.max(0, units))
        units = round(units * minimumProgrammableIncrementPerUnit) / minimumProgrammableIncrementPerUnit

        return BolusRecommendation(
            amount: units,
            pendingInsulin: pendingInsulin,
            notice: bolusRecommendationNotice
        )
    }
}


struct TempBasalRecommendation: Equatable {
    let unitsPerHour: Double
    let duration: TimeInterval

    /// A special command which cancels any existing temp basals
    static var cancel: TempBasalRecommendation {
        return self.init(unitsPerHour: 0, duration: 0)
    }
}


extension TempBasalRecommendation {
    /// Equates the recommended rate with another rate
    ///
    /// - Parameter unitsPerHour: The rate to compare
    /// - Returns: Whether the rates are equal within Double precision
    private func matchesRate(_ unitsPerHour: Double) -> Bool {
        return abs(self.unitsPerHour - unitsPerHour) < .ulpOfOne
    }

    /// Determines whether the recommendation is necessary given the current state of the pump
    ///
    /// - Parameters:
    ///   - date: The date the recommendation would be delivered
    ///   - scheduledBasalRate: The scheduled basal rate at `date`
    ///   - lastTempBasal: The previously set temp basal
    ///   - continuationInterval: The duration of time before an ongoing temp basal should be continued with a new command
    /// - Returns: A temp basal recommendation
    func ifNecessary(
        at date: Date,
        scheduledBasalRate: Double,
        lastTempBasal: DoseEntry?,
        continuationInterval: TimeInterval
    ) -> TempBasalRecommendation? {
        // Adjust behavior for the currently active temp basal
        if let lastTempBasal = lastTempBasal,
            lastTempBasal.type == .tempBasal,
            lastTempBasal.endDate > date
        {
            /// If the last temp basal has the same rate, and has more than `continuationInterval` of time remaining, don't set a new temp
            if matchesRate(lastTempBasal.unitsPerHour),
                lastTempBasal.endDate.timeIntervalSince(date) > continuationInterval {
                return nil
            } else if matchesRate(scheduledBasalRate) {
                // If our new temp matches the scheduled rate, cancel the current temp
                return .cancel
            }
        } else if matchesRate(scheduledBasalRate) {
            // If we recommend the in-progress scheduled basal rate, do nothing
            return nil
        }

        return self
    }
}


/// Computes a total insulin amount necessary to correct a glucose differential at a given sensitivity
///
/// - Parameters:
///   - fromValue: The starting glucose value
///   - toValue: The desired glucose value
///   - effectedSensitivity: The sensitivity, in glucose-per-insulin-unit
/// - Returns: The insulin correction in units
private func insulinCorrectionUnits(fromValue: Double, toValue: Double, effectedSensitivity: Double) -> Double? {
    guard effectedSensitivity > 0 else {
        return nil
    }

    let glucoseCorrection = fromValue - toValue

    return glucoseCorrection / effectedSensitivity
}

/// Computes a target glucose value for a correction, at a given time during the insulin effect duration
///
/// - Parameters:
///   - percentEffectDuration: The percent of time elapsed of the insulin effect duration
///   - minValue: The minimum (starting) target value
///   - maxValue: The maximum (eventual) target value
/// - Returns: A target value somewhere between the minimum and maximum
private func targetGlucoseValue(percentEffectDuration: Double, minValue: Double, maxValue: Double) -> Double {
    // The inflection point in time: before it we use minValue, after it we linearly blend from minValue to maxValue
    let useMinValueUntilPercent = 0.5

    guard percentEffectDuration > useMinValueUntilPercent else {
        return minValue
    }

    guard percentEffectDuration < 1 else {
        return maxValue
    }

    let slope = (maxValue - minValue) / (1 - useMinValueUntilPercent)
    return minValue + slope * (percentEffectDuration - useMinValueUntilPercent)
}


extension Collection where Iterator.Element == GlucoseValue {

    /// For a collection of glucose prediction, determine the least amount of insulin delivered at
    /// `date` to correct the predicted glucose to the middle of `correctionRange` at the time of prediction.
    ///
    /// - Parameters:
    ///   - correctionRange: The schedule of glucose values used for correction
    ///   - date: The date the insulin correction is delivered
    ///   - suspendThreshold: The glucose value below which only suspension is returned
    ///   - sensitivity: The insulin sensitivity at the time of delivery
    ///   - model: The insulin effect model
    /// - Returns: A correction value in units, if one could be calculated
    private func insulinCorrection(
        to correctionRange: GlucoseRangeSchedule,
        at date: Date,
        suspendThreshold: HKQuantity,
        sensitivity: HKQuantity,
        model: InsulinModel
    ) -> InsulinCorrection? {
        var minGlucose: GlucoseValue?
        var eventualGlucose: GlucoseValue?
        var correctingGlucose: GlucoseValue?
        var minCorrectionUnits: Double?

        // Only consider predictions within the model's effect duration
        let validDateRange = DateInterval(start: date, duration: model.effectDuration)

        let unit = correctionRange.unit
        let sensitivityValue = sensitivity.doubleValue(for: unit)
        let suspendThresholdValue = suspendThreshold.doubleValue(for: unit)

        // For each prediction above target, determine the amount of insulin necessary to correct glucose based on the modeled effectiveness of the insulin at that time
        for prediction in self {
            guard validDateRange.contains(prediction.startDate) else {
                continue
            }

            // If any predicted value is below the suspend threshold, return immediately
            guard prediction.quantity >= suspendThreshold else {
                return .suspend(min: prediction)
            }

            // Update range statistics
            if minGlucose == nil || prediction.quantity < minGlucose!.quantity {
                minGlucose = prediction
            }
            eventualGlucose = prediction

            let predictedGlucoseValue = prediction.quantity.doubleValue(for: unit)
            let time = prediction.startDate.timeIntervalSince(date)

            // Compute the target value as a function of time since the dose started
            let targetValue = targetGlucoseValue(
                percentEffectDuration: time / model.effectDuration,
                minValue: suspendThresholdValue, 
                maxValue: correctionRange.value(at: prediction.startDate).averageValue
            )

            // Compute the dose required to bring this prediction to target:
            // dose = (Glucose Δ) / (% effect × sensitivity)

            let percentEffected = 1 - model.percentEffectRemaining(at: time)
            let effectedSensitivity = percentEffected * sensitivityValue
            guard let correctionUnits = insulinCorrectionUnits(
                fromValue: predictedGlucoseValue,
                toValue: targetValue,
                effectedSensitivity: effectedSensitivity
            ), correctionUnits > 0 else {
                continue
            }

            // Update the correction only if we've found a new minimum
            guard minCorrectionUnits == nil || correctionUnits < minCorrectionUnits! else {
                continue
            }

            correctingGlucose = prediction
            minCorrectionUnits = correctionUnits
        }

        guard let eventual = eventualGlucose, let min = minGlucose else {
            return nil
        }

        // Choose either the minimum glucose or eventual glocse as the correction delta
        let minGlucoseTargets = correctionRange.value(at: min.startDate)
        let eventualGlucoseTargets = correctionRange.value(at: eventual.startDate)

        let minGlucoseValue = min.quantity.doubleValue(for: unit)
        let eventualGlucoseValue = eventual.quantity.doubleValue(for: unit)

        // Treat the mininum glucose when both are below range
        if minGlucoseValue < minGlucoseTargets.minValue &&
            eventual.quantity.doubleValue(for: unit) < eventualGlucoseTargets.minValue
        {
            let time = min.startDate.timeIntervalSince(date)
            // For time = 0, assume a small amount effected. This will result in large (negative) unit recommendation rather than no recommendation at all.
            let percentEffected = Swift.max(.ulpOfOne, 1 - model.percentEffectRemaining(at: time))

            guard let units = insulinCorrectionUnits(
                fromValue: minGlucoseValue,
                toValue: minGlucoseTargets.averageValue,
                effectedSensitivity: sensitivityValue * percentEffected
            ) else {
                return nil
            }

            return .entirelyBelowRange(
                correcting: min,
                minTarget: HKQuantity(unit: unit, doubleValue: minGlucoseTargets.minValue),
                units: units
            )
        } else if eventualGlucoseValue > eventualGlucoseTargets.maxValue,
            let minCorrectionUnits = minCorrectionUnits, let correctingGlucose = correctingGlucose
        {
            return .aboveRange(
                min: min,
                correcting: correctingGlucose,
                minTarget: HKQuantity(unit: unit, doubleValue: eventualGlucoseTargets.minValue),
                units: minCorrectionUnits
            )
        } else {
            return .inRange
        }
    }

    /// Recommends a temporary basal rate to conform a glucose prediction timeline to a correction range
    ///
    /// Returns nil if the normal scheduled basal, or active temporary basal, is sufficient.
    ///
    /// - Parameters:
    ///   - correctionRange: The schedule of correction ranges
    ///   - date: The date at which the temp basal would be scheduled, defaults to now
    ///   - suspendThreshold: A glucose value causing a recommendation of no insulin if any prediction falls below
    ///   - sensitivity: The schedule of insulin sensitivities
    ///   - model: The insulin absorption model
    ///   - basalRates: The schedule of basal rates
    ///   - maxBasalRate: The maximum allowed basal rate
    ///   - lastTempBasal: The previously set temp basal
    ///   - duration: The duration of the temporary basal
    ///   - minimumProgrammableIncrementPerUnit: The smallest fraction of a unit supported in basal delivery
    ///   - continuationInterval: The duration of time before an ongoing temp basal should be continued with a new command
    /// - Returns: The recommended temporary basal rate and duration
    func recommendedTempBasal(
        to correctionRange: GlucoseRangeSchedule,
        at date: Date = Date(),
        suspendThreshold: HKQuantity?,
        sensitivity: InsulinSensitivitySchedule,
        model: InsulinModel,
        basalRates: BasalRateSchedule,
        maxBasalRate: Double,
        lastTempBasal: DoseEntry?,
        duration: TimeInterval = .minutes(30),
        minimumProgrammableIncrementPerUnit: Double = 40,
        continuationInterval: TimeInterval = .minutes(11)
    ) -> TempBasalRecommendation? {
        let correction = self.insulinCorrection(
            to: correctionRange,
            at: date,
            suspendThreshold: suspendThreshold ?? correctionRange.minQuantity(at: date),
            sensitivity: sensitivity.quantity(at: date),
            model: model
        )

        let scheduledBasalRate = basalRates.value(at: date)
        var maxBasalRate = maxBasalRate

        // TODO: Allow `highBasalThreshold` to be a configurable setting
        if case .aboveRange(min: let min, correcting: _, minTarget: let highBasalThreshold, units: _)? = correction,
            min.quantity < highBasalThreshold
        {
            maxBasalRate = scheduledBasalRate
        }

        let temp = correction?.asTempBasal(
            scheduledBasalRate: scheduledBasalRate,
            maxBasalRate: maxBasalRate,
            duration: duration,
            minimumProgrammableIncrementPerUnit: minimumProgrammableIncrementPerUnit
        )

        return temp?.ifNecessary(
            at: date,
            scheduledBasalRate: scheduledBasalRate,
            lastTempBasal: lastTempBasal,
            continuationInterval: continuationInterval
        )
    }

    /// Recommends a bolus to conform a glucose prediction timeline to a correction range
    ///
    /// - Parameters:
    ///   - correctionRange: The schedule of correction ranges
    ///   - date: The date at which the bolus would apply, defaults to now
    ///   - suspendThreshold: A glucose value causing a recommendation of no insulin if any prediction falls below
    ///   - sensitivity: The schedule of insulin sensitivities
    ///   - model: The insulin absorption model
    ///   - pendingInsulin: The number of units expected to be delivered, but not yet reflected in the correction
    ///   - maxBolus: The maximum bolus to return
    ///   - minimumProgrammableIncrementPerUnit: The smallest fraction of a unit supported in bolus delivery
    /// - Returns: A bolus recommendation
    func recommendedBolus(
        to correctionRange: GlucoseRangeSchedule,
        at date: Date = Date(),
        suspendThreshold: HKQuantity?,
        sensitivity: InsulinSensitivitySchedule,
        model: InsulinModel,
        pendingInsulin: Double,
        maxBolus: Double,
        minimumProgrammableIncrementPerUnit: Double = 40
    ) -> BolusRecommendation {
        guard let correction = self.insulinCorrection(
            to: correctionRange,
            at: date,
            suspendThreshold: suspendThreshold ?? correctionRange.minQuantity(at: date),
            sensitivity: sensitivity.quantity(at: date),
            model: model
        ) else {
            return BolusRecommendation(amount: 0, pendingInsulin: pendingInsulin)
        }

        var bolus = correction.asBolus(
            pendingInsulin: pendingInsulin,
            maxBolus: maxBolus,
            minimumProgrammableIncrementPerUnit: minimumProgrammableIncrementPerUnit
        )

        // Handle the "current BG below target" notice here
        // TODO: Don't assume in the future that the first item in the array is current BG
        if case .predictedGlucoseBelowTarget? = bolus.notice,
            let first = first, first.quantity < correctionRange.minQuantity(at: first.startDate)
        {
            bolus.notice = .currentGlucoseBelowTarget(glucose: first)
        }

        return bolus
    }
}
