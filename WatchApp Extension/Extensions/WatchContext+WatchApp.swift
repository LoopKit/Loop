//
//  WatchContext.swift
//  Loop
//
//  Created by Bharat Mediratta on 12/16/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

extension WatchContext {
    var glucoseTrend: GlucoseTrend? {
        get {
            if let glucoseTrendRawValue = glucoseTrendRawValue {
                return GlucoseTrend(rawValue: glucoseTrendRawValue)
            } else {
                return nil
            }
        }
    }
}
