//
//  GlucoseCondition.swift
//  WatchApp Extension
//
//  Created by Pete Schwamb on 6/13/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

extension GlucoseCondition {
    var localizedDescription: String {
        switch self {
        case .aboveRange:
            return NSLocalizedString("HIGH", comment: "String displayed instead of a glucose value above the CGM range")
        case .belowRange:
            return NSLocalizedString("LOW", comment: "String displayed instead of a glucose value below the CGM range")
        }
    }
}
