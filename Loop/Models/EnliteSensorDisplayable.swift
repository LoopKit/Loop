//
//  EnliteSensorDisplayable.swift
//  Loop
//
//  Created by Timothy Mecklem on 12/28/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopUI
import MinimedKit


struct EnliteSensorDisplayable: SensorDisplayable {
    public let isStateValid: Bool
    public let trendType: LoopUI.GlucoseTrend?
    public let isLocal: Bool

    public init?(_ event: RelativeTimestampedGlucoseEvent) {
        isStateValid = event.isStateValid
        trendType = event.trendType
        isLocal = event.isLocal
    }
}

extension RelativeTimestampedGlucoseEvent {
    var isStateValid: Bool {
        return self is SensorValueGlucoseEvent
    }

    var trendType: LoopUI.GlucoseTrend? {
        return nil
    }

    var isLocal: Bool {
        return true
    }
}
