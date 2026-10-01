//
//  WatchContext.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 11/25/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation
import LoopKit
import LoopAlgorithm

public enum InsulinDeliveryWatchState: Int, Equatable {
    case neutralNoOverride
    case neutralOverride
    case increasedInsulin
    case decreasedInsulin
    case minimumDelivery
    case suspended
    case noDelivery
}

@Observable
public final class WatchContext: RawRepresentable {
    public typealias RawValue = [String: Any]

    private let version = 5

    public var creationDate = Date()

    public var displayGlucoseUnit: LoopUnit?

    public var glucose: LoopQuantity?
    public var glucoseCondition: GlucoseCondition?
    public var glucoseTrend: GlucoseTrend?
    public var glucoseTrendRate: LoopQuantity?
    public var glucoseDate: Date?
    public var glucoseIsDisplayOnly: Bool?
    public var glucoseWasUserEntered: Bool?
    public var glucoseSyncIdentifier: String?

    public var predictedGlucose: WatchPredictedGlucose?

    /// True only for a context the WATCH built for itself during a loan. Deliberately NOT
    /// encoded into rawValue — a context decoded from the phone always reads false, which is
    /// exactly the discrimination needed to stop a relayed copy of the wrist's own reading
    /// from outranking the original.
    public var isWatchAuthored: Bool = false
    public var eventualGlucose: LoopQuantity? {
        return predictedGlucose?.values.last?.quantity
    }

    public var loopLastRunDate: Date?
    public var lastNetTempBasalDose: Double?
    public var lastNetTempBasalDate: Date?
    public var recommendedBolusDose: Double?
    public var insulinDeliveryState: InsulinDeliveryWatchState?
    public var lastManualBolus: LastManualBolus?

    public var potentialCarbEntry: NewCarbEntry?

    public var cob: Double?
    public var iob: Double?
    public var reservoir: Double?
    public var reservoirPercentage: Double?
    public var batteryPercentage: Double?

    public var cgmManagerState: CGMManager.RawStateValue?

    public var isClosedLoop: Bool?
    public var deviceIssue: Bool?
    public var isOnboardingCompleted: Bool?

    public init(
        creationDate: Date = Date(),
        glucose: LoopQuantity? = nil,
        displayGlucoseUnit: LoopUnit? = nil,
        glucoseCondition: GlucoseCondition? = nil,
        glucoseTrend: GlucoseTrend? = nil,
        glucoseTrendRate: LoopQuantity? = nil,
        glucoseDate: Date? = nil,
        glucoseIsDisplayOnly: Bool? = nil,
        glucoseWasUserEntered: Bool? = nil,
        glucoseSyncIdentifier: String? = nil,
        predictedGlucose: WatchPredictedGlucose? = nil,
        loopLastRunDate: Date? = nil,
        lastNetTempBasalDose: Double? = nil,
        lastNetTempBasalDate: Date? = nil,
        recommendedBolusDose: Double? = nil,
        potentialCarbEntry: NewCarbEntry? = nil,
        cob: Double? = nil,
        iob: Double? = nil,
        reservoir: Double? = nil,
        reservoirPercentage: Double? = nil,
        batteryPercentage: Double? = nil,
        cgmManagerState: CGMManager.RawStateValue? = nil,
        insulinDeliveryState: InsulinDeliveryWatchState? = nil,
        lastManualBolus: LastManualBolus? = nil,
        isClosedLoop: Bool? = nil,
        deviceIssue: Bool? = nil,
        isOnboardingCompleted: Bool? = nil
    ) {
        self.creationDate = creationDate
        self.displayGlucoseUnit = displayGlucoseUnit
        self.glucose = glucose
        self.glucoseCondition = glucoseCondition
        self.glucoseTrend = glucoseTrend
        self.glucoseTrendRate = glucoseTrendRate
        self.glucoseDate = glucoseDate
        self.glucoseIsDisplayOnly = glucoseIsDisplayOnly
        self.glucoseWasUserEntered = glucoseWasUserEntered
        self.glucoseSyncIdentifier = glucoseSyncIdentifier
        self.predictedGlucose = predictedGlucose
        self.loopLastRunDate = loopLastRunDate
        self.lastNetTempBasalDose = lastNetTempBasalDose
        self.lastNetTempBasalDate = lastNetTempBasalDate
        self.recommendedBolusDose = recommendedBolusDose
        self.potentialCarbEntry = potentialCarbEntry
        self.cob = cob
        self.iob = iob
        self.reservoir = reservoir
        self.reservoirPercentage = reservoirPercentage
        self.batteryPercentage = batteryPercentage
        self.cgmManagerState = cgmManagerState
        self.insulinDeliveryState = insulinDeliveryState
        self.lastManualBolus = lastManualBolus
        self.isClosedLoop = isClosedLoop
        self.deviceIssue = deviceIssue
        self.isOnboardingCompleted = isOnboardingCompleted
    }

    public required init?(rawValue: RawValue) {
        guard rawValue["v"] as? Int == version, let creationDate = rawValue["cd"] as? Date else {
            return nil
        }

        self.creationDate = creationDate
        isClosedLoop = rawValue["cl"] as? Bool
        deviceIssue = rawValue["di"] as? Bool
        isOnboardingCompleted = rawValue["oc"] as? Bool

        if let unitString = rawValue["gu"] as? String {
            displayGlucoseUnit = LoopUnit(from: unitString)
        }
        let unit = displayGlucoseUnit ?? .milligramsPerDeciliter
        if let glucoseValue = rawValue["gv"] as? Double {
            glucose = LoopQuantity(unit: unit, doubleValue: glucoseValue)
        }

        if let rawGlucoseCondition = rawValue["gc"] as? GlucoseCondition.RawValue {
            glucoseCondition = GlucoseCondition(rawValue: rawGlucoseCondition)
        }
        if let rawGlucoseTrend = rawValue["gt"] as? GlucoseTrend.RawValue {
            glucoseTrend = GlucoseTrend(rawValue: rawGlucoseTrend)
        }
        if let glucoseTrendRateValue = rawValue["gtrv"] as? Double {
            glucoseTrendRate = LoopQuantity(unit: .milligramsPerDeciliterPerMinute, doubleValue: glucoseTrendRateValue)
        }
        glucoseDate = rawValue["gd"] as? Date
        glucoseIsDisplayOnly = rawValue["gdo"] as? Bool
        glucoseWasUserEntered = rawValue["gue"] as? Bool
        glucoseSyncIdentifier = rawValue["gs"] as? String
        iob = rawValue["iob"] as? Double
        reservoir = rawValue["r"] as? Double
        reservoirPercentage = rawValue["rp"] as? Double
        batteryPercentage = rawValue["bp"] as? Double

        loopLastRunDate = rawValue["ld"] as? Date
        lastNetTempBasalDose = rawValue["ba"] as? Double
        lastNetTempBasalDate = rawValue["bad"] as? Date

        if let rawInsulinDeliveryState = rawValue["ids"] as? InsulinDeliveryWatchState.RawValue {
            insulinDeliveryState = InsulinDeliveryWatchState(rawValue: rawInsulinDeliveryState)
        }

        if let rawLastManualBolus = rawValue["lmb"] as? LastManualBolus.RawValue {
            lastManualBolus = LastManualBolus(rawValue: rawLastManualBolus)
        }

        recommendedBolusDose = rawValue["rbo"] as? Double
        if let rawPotentialCarbEntry = rawValue["pce"] as? NewCarbEntry.RawValue {
            potentialCarbEntry = NewCarbEntry(rawValue: rawPotentialCarbEntry)
        }
        cob = rawValue["cob"] as? Double

        cgmManagerState = rawValue["cgmManagerState"] as? CGMManager.RawStateValue

        if let rawValue = rawValue["pg"] as? WatchPredictedGlucose.RawValue {
            predictedGlucose = WatchPredictedGlucose(rawValue: rawValue)
        }
    }

    public var rawValue: RawValue {
        var raw: [String: Any] = [
            "v": version,
            "cd": creationDate
        ]

        raw["ba"] = lastNetTempBasalDose
        raw["bad"] = lastNetTempBasalDate
        raw["bp"] = batteryPercentage
        raw["cl"] = isClosedLoop
        raw["di"] = deviceIssue
        raw["oc"] = isOnboardingCompleted

        raw["cgmManagerState"] = cgmManagerState

        raw["cob"] = cob

        let unit = displayGlucoseUnit ?? .milligramsPerDeciliter
        raw["gu"] = displayGlucoseUnit?.unitString
        raw["gv"] = glucose?.doubleValue(for: unit)

        raw["gc"] = glucoseCondition?.rawValue
        raw["gt"] = glucoseTrend?.rawValue
        if let glucoseTrendRate = glucoseTrendRate {
            let unitPerMinute = unit.unitDivided(by: .minute)
            raw["gtru"] = unitPerMinute.unitString
            raw["gtrv"] = glucoseTrendRate.doubleValue(for: unitPerMinute)
        }
        raw["gd"] = glucoseDate
        raw["gdo"] = glucoseIsDisplayOnly
        raw["gue"] = glucoseWasUserEntered
        raw["gs"] = glucoseSyncIdentifier
        raw["iob"] = iob
        raw["ld"] = loopLastRunDate
        raw["r"] = reservoir

        raw["ids"] = insulinDeliveryState?.rawValue
        raw["lmb"] = lastManualBolus?.rawValue

        raw["rbo"] = recommendedBolusDose
        raw["pce"] = potentialCarbEntry?.rawValue
        raw["rp"] = reservoirPercentage

        raw["pg"] = predictedGlucose?.rawValue

        return raw
    }
}


extension WatchContext {
    public func shouldReplace(_ other: WatchContext) -> Bool {
        if let date = self.glucoseDate, let otherDate = other.glucoseDate {
            return date >= otherDate
        } else {
            return true
        }
    }
}

extension WatchContext {
    public var newGlucoseSample: NewGlucoseSample? {
        if let quantity = glucose, let date = glucoseDate, let syncIdentifier = glucoseSyncIdentifier {
            return NewGlucoseSample(date: date,
                                    quantity: quantity,
                                    condition: glucoseCondition,
                                    trend: glucoseTrend,
                                    trendRate: glucoseTrendRate,
                                    isDisplayOnly: glucoseIsDisplayOnly ?? false,
                                    wasUserEntered: glucoseWasUserEntered ?? false,
                                    syncIdentifier: syncIdentifier, syncVersion: 0)
        }
        return nil
    }
}
