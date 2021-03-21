//
//  CarbStore.swift
//  Loop
//
//  Created by Darin Krauss on 5/8/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit

extension CarbStore.CarbStoreError: Codable {
    public init(from decoder: Decoder) throws {
        if let string = try? decoder.singleValueContainer().decode(String.self) {
            switch string {
            case CodableKeys.notConfigured.rawValue:
                self = .notConfigured
            case CodableKeys.unauthorized.rawValue:
                self = .unauthorized
            case CodableKeys.noData.rawValue:
                self = .noData
            default:
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "invalid enumeration"))
            }
        } else {
            let container = try decoder.container(keyedBy: CodableKeys.self)
            if let healthStoreError = try container.decodeIfPresent(HealthStoreError.self, forKey: .healthStoreError) {
                self = .healthStoreError(healthStoreError.error)
            } else if let coreDataError = try container.decodeIfPresent(CoreDataError.self, forKey: .coreDataError) {
                self = .coreDataError(coreDataError.error)
            } else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "invalid enumeration"))
            }
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .notConfigured:
            var container = encoder.singleValueContainer()
            try container.encode(CodableKeys.notConfigured.rawValue)
        case .healthStoreError(let error):
            var container = encoder.container(keyedBy: CodableKeys.self)
            try container.encode(HealthStoreError(error: error), forKey: .healthStoreError)
        case .coreDataError(let error):
            var container = encoder.container(keyedBy: CodableKeys.self)
            try container.encode(CoreDataError(error: error), forKey: .coreDataError)
        case .unauthorized:
            var container = encoder.singleValueContainer()
            try container.encode(CodableKeys.unauthorized.rawValue)
        case .noData:
            var container = encoder.singleValueContainer()
            try container.encode(CodableKeys.noData.rawValue)
        }
    }
    
    private struct HealthStoreError: Codable {
        let error: CodableLocalizedError
        
        init(error: Error) {
            self.error = CodableLocalizedError(error)
        }
    }

    private struct CoreDataError: Codable {
        let error: CodableLocalizedError

        init(error: Error) {
            self.error = CodableLocalizedError(error)
        }
    }

    private enum CodableKeys: String, CodingKey {
        case notConfigured
        case healthStoreError
        case coreDataError
        case unauthorized
        case noData
    }
}
