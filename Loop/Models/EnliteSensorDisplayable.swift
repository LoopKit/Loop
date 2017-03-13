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
    public let trendType: LoopUI.GlucoseTrend? = nil
    public let isLocal = true

    public init?(_ e: RelativeTimestampedGlucoseEvent) {
        isStateValid = e is SensorValueGlucoseEvent
    }
}
