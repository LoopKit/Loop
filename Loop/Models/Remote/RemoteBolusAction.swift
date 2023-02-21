//
//  RemoteBolusAction.swift
//  Loop
//
//  Created by Bill Gestrich on 2/21/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import LoopKit

extension RemoteBolusAction {
    public func toValidBolusAmount(maximumBolus: Double?) throws -> Double {
        
        guard amountInUnits > 0 else {
            throw RemoteBolusActionError.invalidBolus
        }
        
        guard let maxBolusAmount = maximumBolus else {
            throw RemoteBolusActionError.missingMaxBolus
        }
        
        guard amountInUnits <= maxBolusAmount else {
            throw RemoteBolusActionError.exceedsMaxBolus
        }
        
        return amountInUnits
    }
}

public enum RemoteBolusActionError: LocalizedError {
    
    case invalidBolus
    case missingMaxBolus
    case exceedsMaxBolus
    
    public var errorDescription: String? {
        switch self {
        case .invalidBolus:
            return NSLocalizedString("Invalid Bolus Amount", comment: "Remote command error description: invalid bolus amount.")
        case .missingMaxBolus:
            return NSLocalizedString("Missing maximum allowed bolus in settings", comment: "Remote command error description: missing maximum bolus in settings.")
        case .exceedsMaxBolus:
            return NSLocalizedString("Exceeds maximum allowed bolus in settings", comment: "Remote command error description: bolus exceeds maximum bolus in settings.")
        }
    }
}
