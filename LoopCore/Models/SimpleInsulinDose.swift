//
//  SimpleInsulinDose.swift
//  Loop
//
//  Created by Pete Schwamb on 2/23/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopAlgorithm

// Implements the bare minimum of InsulinDose, including a slot for InsulinModel
// We could use DoseEntry, but we need to dynamically lookup user's preferred
// fast acting insulin model in settings. So until that is removed, we need this.
public struct SimpleInsulinDose: InsulinDose {
    public var deliveryType: InsulinDeliveryType
    public var automatic: Bool
    public var startDate: Date
    public var endDate: Date
    public var volume: Double
    public var insulinModel: InsulinModel

    public init(deliveryType: InsulinDeliveryType, automatic: Bool, startDate: Date, endDate: Date, volume: Double, insulinModel: InsulinModel) {
        self.deliveryType = deliveryType
        self.automatic = automatic
        self.startDate = startDate
        self.endDate = endDate
        self.volume = volume
        self.insulinModel = insulinModel
    }
}

extension DoseEntry {
    public var deliveryType: InsulinDeliveryType {
        switch self.type {
        case .bolus:
            return .bolus
        default:
            return .basal
        }
    }

    public var volume: Double {
        return deliveredUnits ?? programmedUnits
    }

    public func simpleDose(with model: InsulinModel) -> SimpleInsulinDose {
        SimpleInsulinDose(
            deliveryType: deliveryType,
            automatic: automatic ?? false,
            startDate: startDate,
            endDate: endDate,
            volume: volume,
            insulinModel: model
        )
    }
}

public extension Array where Element == SimpleInsulinDose {
    func trimmed(to end: Date? = nil) -> [SimpleInsulinDose] {
        return self.compactMap { (dose) -> SimpleInsulinDose? in
            if let end, dose.startDate > end {
                return nil
            }
            if dose.deliveryType == .bolus {
                return dose
            }
            return dose.trimmed(to: end)
        }
    }
}

extension SimpleInsulinDose {
    public func trimmed(from start: Date? = nil, to end: Date? = nil, syncIdentifier: String? = nil) -> SimpleInsulinDose {

        let originalDuration = endDate.timeIntervalSince(startDate)

        let startDate = max(start ?? .distantPast, self.startDate)
        let endDate = max(startDate, min(end ?? .distantFuture, self.endDate))

        var trimmedVolume: Double = volume

        if originalDuration > .ulpOfOne && (startDate > self.startDate || endDate < self.endDate) {
            trimmedVolume = volume * (endDate.timeIntervalSince(startDate) / originalDuration)
        }

        return SimpleInsulinDose(
            deliveryType: self.deliveryType,
            automatic: automatic,
            startDate: startDate,
            endDate: endDate,
            volume: trimmedVolume,
            insulinModel: insulinModel
        )
    }
}

