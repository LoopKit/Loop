//
//  GlucoseDisplay.swift
//  Loop
//
//  Created by Nathaniel Hamming on 2020-09-22.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit

struct GlucoseDisplay: GlucoseDisplayable {
    let isStateValid: Bool
    let trendType: GlucoseTrend?
    let trendRate: HKQuantity?
    let isLocal: Bool
    var glucoseRangeCategory: GlucoseRangeCategory?
        
    init(isStateValid: Bool,
         trendType: GlucoseTrend?,
         trendRate: HKQuantity?,
         isLocal: Bool,
         glucoseRangeCategory: GlucoseRangeCategory?)
    {
        self.isStateValid = isStateValid
        self.trendType = trendType
        self.trendRate = trendRate
        self.isLocal = isLocal
        self.glucoseRangeCategory = glucoseRangeCategory
    }
    
    init?(_ glucoseDisplayable: GlucoseDisplayable?) {
        guard let glucoseDisplayable = glucoseDisplayable else {
            return nil
        }
        self.isStateValid = glucoseDisplayable.isStateValid
        self.trendType = glucoseDisplayable.trendType
        self.trendRate = glucoseDisplayable.trendRate
        self.isLocal = glucoseDisplayable.isLocal
        self.glucoseRangeCategory = glucoseDisplayable.glucoseRangeCategory
    }
}

struct ManualGlucoseDisplay: GlucoseDisplayable {
    let isStateValid: Bool
    let trendType: GlucoseTrend?
    let trendRate: HKQuantity?
    let isLocal: Bool
    let glucoseRangeCategory: GlucoseRangeCategory?
    
    init(glucoseRangeCategory: GlucoseRangeCategory?) {
        isStateValid = true
        trendType = nil
        trendRate = nil
        isLocal = true
        self.glucoseRangeCategory = glucoseRangeCategory
    }
}
