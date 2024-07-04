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
import LoopCore

public struct GlucoseActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Meta data
        public let date: Date
        
        // Glucose view
        public let glucose: String
        public let trendType: GlucoseTrend?
        public let delta: String
        public let isCloseLoop: Bool
        public let lastCompleted: Date?
        
        public let bottomRow: [BottomRowItem]
        public let glucoseSamples: [GlucoseSampleAttributes]
    }
    
    public let mode: GlucoseActivityMode
}

public struct GlucoseChartActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public let predicatedGlucose: [Double]
        public let predicatedStartDate: Date?
        public let predicatedInterval: TimeInterval?
        public let glucoseSamples: [GlucoseSampleAttributes]
    }
}

public struct BottomRowItem: Codable, Hashable {
    public enum BottomRowType: Codable, Hashable {
        case generic
        case basal
        case currentBg
    }
    
    public let type: BottomRowType
    
    // Generic properties
    public let label: String
    public let value: String
    public let unit: String
    
    public let trend: GlucoseTrend?

    // Basal properties
    public let rate: Double
    public let percentage: Double
    
    init(label: String, value: String, unit: String) {
        self.type = .generic
        self.label = label
        self.value = value
        self.unit = unit
        
        self.trend = nil
        self.rate = 0
        self.percentage = 0
    }
    
    init(label: String, value: String, trend: GlucoseTrend?) {
        self.type = .currentBg
        self.label = label
        self.value = value
        self.trend = trend
        
        self.unit = ""
        self.rate = 0
        self.percentage = 0
    }
    
    init(rate: Double, percentage: Double) {
        self.type = .basal
        self.rate = rate
        self.percentage = percentage
        
        self.label = ""
        self.value = ""
        self.unit = ""
        self.trend = nil
    }
}

public struct GlucoseSampleAttributes: Codable, Hashable {
    public let x: Date
    public let y: Double
}
