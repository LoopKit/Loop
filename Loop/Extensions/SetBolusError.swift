//
//  SetBolusError.swift
//  Loop
//
//  Created by Darin Krauss on 5/8/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit

extension SetBolusError: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodableKeys.self)
        if let associated = try container.decodeIfPresent(Associated.self, forKey: .certain) {
            self = .certain(associated.localizedError)
        } else if let associated = try container.decodeIfPresent(Associated.self, forKey: .uncertain) {
            self = .uncertain(associated.localizedError)
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "invalid enumeration"))
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodableKeys.self)
        switch self {
        case .certain(let localizedError):
            try container.encode(Associated(localizedError: localizedError), forKey: .certain)
        case .uncertain(let localizedError):
            try container.encode(Associated(localizedError: localizedError), forKey: .uncertain)
        }
    }
    
    private struct Associated: Codable {
        let localizedError: CodableLocalizedError
        
        init(localizedError: LocalizedError) {
            self.localizedError = CodableLocalizedError(localizedError)
        }
    }
    
    private enum CodableKeys: String, CodingKey {
        case certain
        case uncertain
    }
}
