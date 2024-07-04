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
    
    static let defaults: [BottomRowConfiguration] =  [.iob, .cob, .basal, .eventualBg] //[.currentBg, .iob, .cob, .updatedAt]
}

public enum GlucoseActivityMode: Codable, Hashable {
    case compact
    case spacious
}

public struct LiveActivitySettings: Codable {
    public var enabled: Bool
    
    public var mode: GlucoseActivityMode
    public var bottomRowConfiguration: [BottomRowConfiguration]
    
    private enum CodingKeys: String, CodingKey {
        case enabled
        case mode
        case bottomRowConfiguration
    }
    
    public init(from decoder:Decoder) throws {
//        let values = try decoder.container(keyedBy: CodingKeys.self)
//        enabled = try values.decode(Bool.self, forKey: .enabled)
//        mode = try values.decode(GlucoseActivityMode.self, forKey: .mode)
//        bottomRowConfiguration = try values.decode([BottomRowConfiguration].self, forKey: .bottomRowConfiguration)
        self.enabled = true
        self.mode = .spacious
        self.bottomRowConfiguration = BottomRowConfiguration.defaults
    }
    
    public init() {
        self.enabled = true
        self.mode = .spacious
        self.bottomRowConfiguration = BottomRowConfiguration.defaults
    }
}
