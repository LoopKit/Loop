//
//  LiveActivityAttributes.swift
//  LoopUI
//
//  Created by Bastiaan Verhaar on 23/06/2024.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import ActivityKit
import Foundation
import LoopKit

public struct GlucoseActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Meta data
        public let date: Date
        
        // Glucose view
        public let glucose: String
        public let delta: String
        public let unit: String
        public let isCloseLoop: Bool
        public let lastCompleted: Date?
        
        // Pump view
        public let pumpHighlight: PumpHighlightAttributes?
        public let netBasal: NetBasalAttributes?
        public let eventualGlucose: String
        
        // Graph view
        public let predicatedGlucose: [Double]
        public let predicatedStartDate: Date?
        public let predicatedInterval: TimeInterval?
    }
}

public struct PumpHighlightAttributes: Codable, Hashable {
    public let localizedMessage: String
    public let imageName: String
    public let state: DeviceStatusHighlightState
}

public struct NetBasalAttributes: Codable, Hashable {
    public let rate: Double
    public let percentage: Double
    public let start: Date
    public let end: Date?
}
