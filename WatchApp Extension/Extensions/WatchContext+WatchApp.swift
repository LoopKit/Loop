//
//  WatchContext.swift
//  Loop
//
//  Created by Bharat Mediratta on 12/16/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

extension WatchContext {
    var glucoseTrend: GlucoseTrendType? {
        get {
            if let glucoseTrendRawValue = glucoseTrendRawValue {
                return GlucoseTrendType(rawValue: glucoseTrendRawValue)
            } else {
                return nil
            }
        }
    }
}
