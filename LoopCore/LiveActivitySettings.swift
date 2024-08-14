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
    case loopCircle
    case updatedAt
    
    static let defaults: [BottomRowConfiguration] =  [.currentBg, .iob, .cob, .updatedAt]
    public static let all: [BottomRowConfiguration] = [.iob, .cob, .basal, .currentBg, .eventualBg, .deltaBg, .loopCircle, .updatedAt]
    
    public func name() -> String {
        switch self {
        case .iob:
            return NSLocalizedString("IOB", comment: "")
        case .cob:
            return NSLocalizedString("COB", comment: "")
        case .basal:
            return NSLocalizedString("Basal", comment: "")
        case .currentBg:
            return NSLocalizedString("Current BG", comment: "")
        case .eventualBg:
            return NSLocalizedString("Event", comment: "")
        case .deltaBg:
            return NSLocalizedString("Delta", comment: "")
        case .loopCircle:
            return NSLocalizedString("Loop", comment: "")
        case .updatedAt:
            return NSLocalizedString("Updated", comment: "")
        }
    }
    
    public func description() -> String {
        switch self {
        case .iob:
            return NSLocalizedString("Active Insulin", comment: "")
        case .cob:
            return NSLocalizedString("Active Carbohydrates", comment: "")
        case .basal:
            return NSLocalizedString("Basal", comment: "")
        case .currentBg:
            return NSLocalizedString("Current Glucose", comment: "")
        case .eventualBg:
            return NSLocalizedString("Eventually", comment: "")
        case .deltaBg:
            return NSLocalizedString("Delta", comment: "")
        case .loopCircle:
            return NSLocalizedString("Loop circle", comment: "")
        case .updatedAt:
            return NSLocalizedString("Updated at", comment: "")
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
            return NSLocalizedString("Large", comment: "")
        case .small:
            return NSLocalizedString("Small", comment: "")
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
        self.useLimits = try values.decodeIfPresent(Bool.self, forKey: .useLimits) ?? true
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