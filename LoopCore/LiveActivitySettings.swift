//
//  LiveActivitySettings.swift
//  LoopCore
//
//  Created by Bastiaan Verhaar on 04/07/2024.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation

public enum BottomRowConfiguration: Codable {
    case iob
    case cob
    case basal
    case currentBg
    case eventualBg
    case deltaBg
    case updatedAt
    
    static let defaults: [BottomRowConfiguration] =  [.currentBg, .iob, .cob, .updatedAt]
    public static let all: [BottomRowConfiguration] = [.iob, .cob, .basal, .currentBg, .eventualBg, .deltaBg, .updatedAt]
    
    public func name() -> String {
        switch self {
        case .iob:
            return NSLocalizedString("IOB", comment: "Label used for the Insulin On Board value in the Live Activity view")
        case .cob:
            return NSLocalizedString("COB", comment: "Label used for the Carbohydrates On Board value in the Live Activity view")
        case .basal:
            return NSLocalizedString("Basal", comment: "Label used for the Basal Rate plot in the Live Activity view")
        case .currentBg:
            return NSLocalizedString("Current BG", comment: "Label not shown in the Live Activity view")
        case .eventualBg:
            return NSLocalizedString("Eventual BG", comment: "Label used for the Forecasted Glucose in the Live Activity view")
        case .deltaBg:
            return NSLocalizedString("Delta", comment: "Label used for the Delta Glucose in the Live Activity view")
        case .updatedAt:
            return NSLocalizedString("at", comment: "Label used for the Updated time value in the Live Activity view")
        }
    }
    
    public func description() -> String {
        switch self {
        case .iob:
            return NSLocalizedString("Active Insulin (IOB)", comment: "Description for the Insulin On Board selection for the Live Activity configuration")
        case .cob:
            return NSLocalizedString("Active Carbohydrates (COB)", comment: "Description for the Carbohydrates On Board selection for the Live Activity configuration")
        case .basal:
            return NSLocalizedString("Relative Basal Rate (Basal)", comment: "Description for the Basal Rate plot selection for the Live Activity configuration")
        case .currentBg:
            return NSLocalizedString("Current Glucose (Value and Arrow)", comment: "Description for the Current Glucose selection for the Live Activity configuration")
        case .eventualBg:
            return NSLocalizedString("Forecasted Glucose (Eventual BG)", comment: "Description for the Forecasted Glucose selection for the Live Activity configuration")
        case .deltaBg:
            return NSLocalizedString("Delta Glucose (Delta)", comment: "Description for the Delta Glucose selection for the Live Activity configuration")
        case .updatedAt:
            return NSLocalizedString("Updated (at)", comment: "Description for the Updated time selection for the Live Activity configuration")
        }
    }
}

public enum LiveActivityMode: Codable, CustomStringConvertible {
    case large
    case small
    
    public static let all: [LiveActivityMode] = [.large, .small]
    public var description: String {
        NSLocalizedString("In which mode do you want to render the Live Activity", comment: "")
    }
    
    public func name() -> String {
        switch self {
        case .large:
            return NSLocalizedString("Plot and Row", comment: "Short name to choose the Lock Screen display including the the plot")
        case .small:
            return NSLocalizedString("Row Only", comment: "Short name to choose the Lock Screen display without the plot")
        }
    }
}

public struct LiveActivitySettings: Codable, Equatable {
    public var enabled: Bool
    public var mode: LiveActivityMode
    public var addPredictiveLine: Bool
    public var useLimits: Bool
    public var upperLimitChartMmol: Double
    public var lowerLimitChartMmol: Double
    public var upperLimitChartMg: Double
    public var lowerLimitChartMg: Double
    public var bottomRowConfiguration: [BottomRowConfiguration]
    
    private enum CodingKeys: String, CodingKey {
        case enabled
        case mode
        case addPredictiveLine
        case bottomRowConfiguration
        case useLimits
        case upperLimitChartMmol
        case lowerLimitChartMmol
        case upperLimitChartMg
        case lowerLimitChartMg
    }
    
    private static let defaultUpperLimitMmol = Double(10)
    private static let defaultLowerLimitMmol = Double(4)
    private static let defaultUpperLimitMg = Double(180)
    private static let defaultLowerLimitMg = Double(72)
    
    public init(from decoder:Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        self.enabled = try values.decode(Bool.self, forKey: .enabled)
        self.mode = try values.decodeIfPresent(LiveActivityMode.self, forKey: .mode) ?? .large
        self.addPredictiveLine = try values.decode(Bool.self, forKey: .addPredictiveLine)
        self.useLimits = try values.decode(Bool.self, forKey: .useLimits)
        self.upperLimitChartMmol = try values.decode(Double?.self, forKey: .upperLimitChartMmol) ?? LiveActivitySettings.defaultUpperLimitMmol
        self.lowerLimitChartMmol = try values.decode(Double?.self, forKey: .lowerLimitChartMmol) ?? LiveActivitySettings.defaultLowerLimitMmol
        self.upperLimitChartMg = try values.decode(Double?.self, forKey: .upperLimitChartMg) ?? LiveActivitySettings.defaultUpperLimitMg
        self.lowerLimitChartMg = try values.decode(Double?.self, forKey: .lowerLimitChartMg) ?? LiveActivitySettings.defaultLowerLimitMg
        self.bottomRowConfiguration = try values.decode([BottomRowConfiguration].self, forKey: .bottomRowConfiguration)
    }
    
    public init() {
        self.enabled = true
        self.mode = .large
        self.addPredictiveLine = true
        self.useLimits = true
        self.upperLimitChartMmol = LiveActivitySettings.defaultUpperLimitMmol
        self.lowerLimitChartMmol = LiveActivitySettings.defaultLowerLimitMmol
        self.upperLimitChartMg = LiveActivitySettings.defaultUpperLimitMg
        self.lowerLimitChartMg = LiveActivitySettings.defaultLowerLimitMg
        self.bottomRowConfiguration = BottomRowConfiguration.defaults
    }
    
    public static func == (lhs: LiveActivitySettings, rhs: LiveActivitySettings) -> Bool {
        return lhs.addPredictiveLine == rhs.addPredictiveLine &&
            lhs.mode == rhs.mode &&
            lhs.useLimits == rhs.useLimits &&
            lhs.lowerLimitChartMmol == rhs.lowerLimitChartMmol &&
            lhs.upperLimitChartMmol == rhs.upperLimitChartMmol &&
            lhs.lowerLimitChartMg == rhs.lowerLimitChartMg &&
            lhs.upperLimitChartMg == rhs.upperLimitChartMg
    }
    
    public static func != (lhs: LiveActivitySettings, rhs: LiveActivitySettings) -> Bool {
        return lhs.addPredictiveLine != rhs.addPredictiveLine ||
            lhs.mode != rhs.mode ||
            lhs.useLimits != rhs.useLimits ||
            lhs.lowerLimitChartMmol != rhs.lowerLimitChartMmol ||
            lhs.upperLimitChartMmol != rhs.upperLimitChartMmol ||
            lhs.lowerLimitChartMg != rhs.lowerLimitChartMg ||
            lhs.upperLimitChartMg != rhs.upperLimitChartMg
    }
}
