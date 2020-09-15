//
//  DoseStore.swift
//  Loop
//
//  Created by Darin Krauss on 5/8/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit

extension DoseStore.DoseStoreError: Codable {
    public init(from decoder: Decoder) throws {
        if let string = try? decoder.singleValueContainer().decode(String.self) {
            switch string {
            case CodableKeys.configurationError.rawValue:
                self = .configurationError
            default:
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "invalid enumeration"))
            }
        } else {
            let container = try decoder.container(keyedBy: CodableKeys.self)
            if let associated = try container.decodeIfPresent(Associated.self, forKey: .initializationError) {
                self = .initializationError(description: associated.description, recoverySuggestion: associated.recoverySuggestion)
            } else if let associated = try container.decodeIfPresent(Associated.self, forKey: .persistenceError) {
                self = .persistenceError(description: associated.description, recoverySuggestion: associated.recoverySuggestion)
            } else if let associated = try container.decodeIfPresent(Associated.self, forKey: .fetchError) {
                self = .fetchError(description: associated.description, recoverySuggestion: associated.recoverySuggestion)
            } else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "invalid enumeration"))
            }
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .configurationError:
            var container = encoder.singleValueContainer()
            try container.encode(CodableKeys.configurationError.rawValue)
        case .initializationError(let description, let recoverySuggestion):
            var container = encoder.container(keyedBy: CodableKeys.self)
            try container.encode(Associated(description: description, recoverySuggestion: recoverySuggestion), forKey: .initializationError)
        case .persistenceError(let description, let recoverySuggestion):
            var container = encoder.container(keyedBy: CodableKeys.self)
            try container.encode(Associated(description: description, recoverySuggestion: recoverySuggestion), forKey: .persistenceError)
        case .fetchError(let description, let recoverySuggestion):
            var container = encoder.container(keyedBy: CodableKeys.self)
            try container.encode(Associated(description: description, recoverySuggestion: recoverySuggestion), forKey: .fetchError)
        }
    }
    
    private struct Associated: Codable {
        let description: String
        let recoverySuggestion: String?
    }
    
    private enum CodableKeys: String, CodingKey {
        case configurationError
        case initializationError
        case persistenceError
        case fetchError
    }
}
