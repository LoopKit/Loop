//
//  GlucoseRangeCategory.swift
//  LoopUI
//
//  Created by Nathaniel Hamming on 2020-07-28.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit

extension GlucoseRangeCategory {
    public var glucoseColor: UIColor {
        switch self {
        case .normal, .high, .low:
            return .label
        case .urgentLow, .belowRange:
            return .critical
        case .aboveRange:
            return .warning
        }
    }
    
    public var trendColor: UIColor {
        switch self {
        case .normal:
            return .glucose
        case .urgentLow, .belowRange:
            return .critical
        case .low, .high, .aboveRange:
            return .warning
        }
    }
}
