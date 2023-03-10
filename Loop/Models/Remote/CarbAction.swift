//
//  CarbAction.swift
//  Loop
//
//  Created by Bill Gestrich on 2/21/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import LoopKit
import HealthKit

extension CarbAction {
    
    func toValidCarbEntry(defaultAbsorptionTime: TimeInterval,
                                 minAbsorptionTime: TimeInterval,
                                 maxAbsorptionTime: TimeInterval,
                                 maxCarbEntryQuantity: Double,
                                 maxCarbEntryPastTime: TimeInterval,
                                 maxCarbEntryFutureTime: TimeInterval,
                                 nowDate: Date = Date()) throws -> NewCarbEntry {
        
        let absorptionTime = absorptionTime ?? defaultAbsorptionTime
        if absorptionTime < minAbsorptionTime || absorptionTime > maxAbsorptionTime {
            throw CarbActionError.invalidAbsorptionTime(absorptionTime)
        }
        
        guard amountInGrams > 0.0 else {
            throw CarbActionError.invalidCarbs
        }

        guard amountInGrams <= maxCarbEntryQuantity else {
            throw CarbActionError.exceedsMaxCarbs
        }
        
        if let startDate = startDate {
            let maxStartDate = nowDate.addingTimeInterval(maxCarbEntryFutureTime)
            let minStartDate = nowDate.addingTimeInterval(maxCarbEntryPastTime)
            guard startDate <= maxStartDate  && startDate >= minStartDate else {
                throw CarbActionError.invalidStartDate(startDate)
            }
        }
        
        let quantity = HKQuantity(unit: .gram(), doubleValue: amountInGrams)
        return NewCarbEntry(quantity: quantity, startDate: startDate ?? nowDate, foodType: foodType, absorptionTime: absorptionTime)
    }
}

enum CarbActionError: LocalizedError {
    
    case invalidAbsorptionTime(TimeInterval)
    case invalidStartDate(Date)
    case exceedsMaxCarbs
    case invalidCarbs
    
    var errorDescription: String? {
             switch  self {
             case .exceedsMaxCarbs:
                 return NSLocalizedString("Exceeds maximum allowed carbs", comment: "Remote command error description: carbs exceed maximum amount.")
             case .invalidCarbs:
                 return NSLocalizedString("Invalid carb amount", comment: "Remote command error description: invalid carb amount.")
             case .invalidAbsorptionTime(let absorptionTime):
                 return String(format: NSLocalizedString("Invalid absorption time: %d hours", comment: "Remote command error description: invalid absorption time."), absorptionTime.hours)
             case .invalidStartDate(let startDate):
                 return String(format: NSLocalizedString("Start time is out of range: %@", comment: "Remote command error description: invalid start time is out of range."), Self.dateFormatter.string(from: startDate))
             }
    }
    
    static var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }()
}
