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
        case .updatedAt:
            return NSLocalizedString("Updated at", comment: "")
        }
    }
}

public struct LiveActivitySettings: Codable {
    public var enabled: Bool
    public var addPredictiveLine: Bool
    public var bottomRowConfiguration: [BottomRowConfiguration]
    
    private enum CodingKeys: String, CodingKey {
        case enabled
        case addPredictiveLine
        case bottomRowConfiguration
    }
    
    public init(from decoder:Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decode(Bool.self, forKey: .enabled)
        addPredictiveLine = try values.decode(Bool.self, forKey: .addPredictiveLine)
        bottomRowConfiguration = try values.decode([BottomRowConfiguration].self, forKey: .bottomRowConfiguration)
    }
    
    public init() {
        self.enabled = true
        self.addPredictiveLine = true
        self.bottomRowConfiguration = BottomRowConfiguration.defaults
    }
}
