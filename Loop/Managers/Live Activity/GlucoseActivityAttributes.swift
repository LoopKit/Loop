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
        public let ended: Bool
        public let preset: Preset?
        public let glucoseRanges: [GlucoseRangeValue]
        
        // Dynamic island data
        public let currentGlucose: Double
        public let trendType: GlucoseTrend?
        public let delta: String
        public let isMmol: Bool
        
        // Loop circle
        public let isCloseLoop: Bool
        public let lastCompleted: Date?
        
        // Bottom row
        public let bottomRow: [BottomRowItem]
        
        // Chart view
        public let glucoseSamples: [GlucoseSampleAttributes]
        public let predicatedGlucose: [Double]
        public let predicatedStartDate: Date?
        public let predicatedInterval: TimeInterval?
    }
    
    public let mode: LiveActivityMode
    public let addPredictiveLine: Bool
    public let useLimits: Bool
    public let upperLimitChartMmol: Double
    public let lowerLimitChartMmol: Double
    public let upperLimitChartMg: Double
    public let lowerLimitChartMg: Double
}

public struct Preset: Codable, Hashable {
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let minValue: Double
    public let maxValue: Double
}

public struct GlucoseRangeValue: Identifiable, Codable, Hashable {
    public let id: UUID
    public let minValue: Double
    public let maxValue: Double
    public let startDate: Date
    public let endDate: Date
}

public struct BottomRowItem: Codable, Hashable {
    public enum BottomRowType: Codable, Hashable {
        case generic
        case basal
        case currentBg
        case loopCircle
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
    
    private init(type: BottomRowType, label: String?, value: String?, unit: String?, trend: GlucoseTrend?, rate: Double?, percentage: Double?) {
        self.type = type
        self.label = label ?? ""
        self.value = value ?? ""
        self.trend = trend
        self.unit = unit ?? ""
        self.rate = rate ?? 0
        self.percentage = percentage ?? 0
    }
    
    static func generic(label: String, value: String, unit: String) -> BottomRowItem  {
        return BottomRowItem(
            type: .generic,
            label: label,
            value: value,
            unit: unit,
            trend: nil,
            rate: nil,
            percentage: nil
        )
    }
    
    static func basal(rate: Double, percentage: Double) -> BottomRowItem {
        return BottomRowItem(
            type: .basal,
            label: nil,
            value: nil,
            unit: nil,
            trend: nil,
            rate: rate,
            percentage: percentage
        )
    }
    
    static func currentBg(label: String, value: String, trend: GlucoseTrend?) -> BottomRowItem {
        return BottomRowItem(
            type: .currentBg,
            label: label,
            value: value,
            unit: nil,
            trend: trend,
            rate: nil,
            percentage: nil
        )
    }
    
    static func loopIcon() -> BottomRowItem {
        return BottomRowItem(
            type: .loopCircle,
            label: nil,
            value: nil,
            unit: nil,
            trend: nil,
            rate: nil,
            percentage: nil
        )
    }
}

public struct GlucoseSampleAttributes: Codable, Hashable {
    public let x: Date
    public let y: Double
}
