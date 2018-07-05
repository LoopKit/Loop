//
//  CGMManager.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit


extension CGM {
    func createManager() -> CGMManager? {
        switch self {
        case .usePump:
            return nil
        case .g4:
            return G4CGMManager()
        case .g5(let transmitterID):
            return G5CGMManager(transmitterID: transmitterID)
        }
    }
}
