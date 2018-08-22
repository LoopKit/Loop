//
//  BasalProfile.swift
//  Loop
//
//  Created by Kenneth Stack on 2/14/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//
import Foundation
import UIKit

enum BasalProfile: Int, CustomStringConvertible {
    case notSet = 0
    case standard
    case patternA
    case patternB
    
    var description: String {
        switch self {
        case .notSet:
            return NSLocalizedString("Not Set", comment: "Describing the not set condition")
        case .standard:
            return NSLocalizedString("Standard", comment: "Describing the standard basal pattern")
        case .patternA:
            return NSLocalizedString("Pattern A", comment: "Describing basal pattern A")
        case .patternB:
            return NSLocalizedString("Pattern B", comment: "Describing basal pattern B")
            //      case .notSet:
            //         return NSLocalizedString("Pattern Not Set", comment: "Describing basal pattern not set")
        }
    }
}
