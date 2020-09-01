//
//  PumpManagerError.swift
//  Loop
//
//  Created by Darin Krauss on 5/8/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit

extension PumpManagerError: Codable {
    public init(from decoder: Decoder) throws {
        if let string = try? decoder.singleValueContainer().decode(String.self) {
            switch string {
            case CodableKeys.uncertainDelivery.rawValue:
                self = .uncertainDelivery
            default:
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "invalid enumeration"))
            }
        } else {
            let container = try decoder.container(keyedBy: CodableKeys.self)
            if let associated = try container.decodeIfPresent(Associated.self, forKey: .configuration) {
                self = .configuration(associated.localizedError)
            } else if let associated = try container.decodeIfPresent(Associated.self, forKey: .connection) {
                self = .connection(associated.localizedError)
            } else if let associated = try container.decodeIfPresent(Associated.self, forKey: .communication) {
                self = .communication(associated.localizedError)
            } else if let associated = try container.decodeIfPresent(Associated.self, forKey: .deviceState) {
                self = .deviceState(associated.localizedError)
            } else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "invalid enumeration"))
            }
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .configuration(let localizedError):
            var container = encoder.container(keyedBy: CodableKeys.self)
            try container.encode(Associated(localizedError: localizedError), forKey: .configuration)
        case .connection(let localizedError):
            var container = encoder.container(keyedBy: CodableKeys.self)
            try container.encode(Associated(localizedError: localizedError), forKey: .connection)
        case .communication(let localizedError):
            var container = encoder.container(keyedBy: CodableKeys.self)
            try container.encode(Associated(localizedError: localizedError), forKey: .communication)
        case .deviceState(let localizedError):
            var container = encoder.container(keyedBy: CodableKeys.self)
            try container.encode(Associated(localizedError: localizedError), forKey: .deviceState)
        case .uncertainDelivery:
            var container = encoder.singleValueContainer()
            try container.encode(CodableKeys.uncertainDelivery.rawValue)
        }
    }
    
    private struct Associated: Codable {
        let localizedError: CodableLocalizedError?
        
        init(localizedError: LocalizedError?) {
            self.localizedError = CodableLocalizedError(localizedError)
        }
    }
    
    private enum CodableKeys: String, CodingKey {
        case configuration
        case connection
        case communication
        case deviceState
        case uncertainDelivery
    }
}
