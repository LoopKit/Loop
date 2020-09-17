//
//  LoopErrorTests.swift
//  LoopTests
//
//  Created by Darin Krauss on 5/11/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit

@testable import Loop

class LoopErrorCodableTests: XCTestCase {
    
    func testCodableConfigurationError() throws {
        try assertLoopErrorCodable(.configurationError(.pumpManager), encodesJSON: """
{
  "loopError" : {
    "configurationError" : {
      "configurationErrorDetail" : "pumpManager"
    }
  }
}
"""
        )
    }
    
    func testCodableConnectionError() throws {
        try assertLoopErrorCodable(.connectionError, encodesJSON: """
{
  "loopError" : "connectionError"
}
"""
        )
    }
    
    func testCodableMissingDataError() throws {
        try assertLoopErrorCodable(.missingDataError(.glucose), encodesJSON: """
{
  "loopError" : {
    "missingDataError" : {
      "missingDataErrorDetail" : "glucose"
    }
  }
}
"""
        )
    }
    
    func testCodableGlucoseTooOld() throws {
        try assertLoopErrorCodable(.glucoseTooOld(date: dateFormatter.date(from: "2020-05-14T22:38:16Z")!), encodesJSON: """
{
  "loopError" : {
    "glucoseTooOld" : {
      "date" : "2020-05-14T22:38:16Z"
    }
  }
}
"""
        )
    }
    
    func testCodablePumpDataTooOld() throws {
        try assertLoopErrorCodable(.pumpDataTooOld(date: dateFormatter.date(from: "2020-05-14T22:48:16Z")!), encodesJSON: """
{
  "loopError" : {
    "pumpDataTooOld" : {
      "date" : "2020-05-14T22:48:16Z"
    }
  }
}
"""
        )
    }
    
    func testCodableRecommendationExpired() throws {
        try assertLoopErrorCodable(.recommendationExpired(date: dateFormatter.date(from: "2020-05-14T22:58:16Z")!), encodesJSON: """
{
  "loopError" : {
    "recommendationExpired" : {
      "date" : "2020-05-14T22:58:16Z"
    }
  }
}
"""
        )
    }
    
    func testCodableInvalidDate() throws {
        try assertLoopErrorCodable(.invalidData(details: "LoopError.invalidData.details"), encodesJSON: """
{
  "loopError" : {
    "invalidData" : {
      "details" : "LoopError.invalidData.details"
    }
  }
}
"""
        )
    }
    
    private func assertLoopErrorCodable(_ original: LoopError, encodesJSON string: String) throws {
        let data = try encoder.encode(TestContainer(loopError: original))
        XCTAssertEqual(String(data: data, encoding: .utf8), string)
        let decoded = try decoder.decode(TestContainer.self, from: data)
        XCTAssertEqual(decoded.loopError, original)
    }

    private let dateFormatter = ISO8601DateFormatter()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private struct TestContainer: Codable, Equatable {
        let loopError: LoopError
    }
}

extension LoopError: Equatable {
    public static func == (lhs: LoopError, rhs: LoopError) -> Bool {
        switch (lhs, rhs) {
        case (.configurationError(let lhsConfigurationErrorDetail), .configurationError(let rhsConfigurationErrorDetail)):
            return lhsConfigurationErrorDetail == rhsConfigurationErrorDetail
        case (.connectionError, .connectionError):
            return true
        case (.missingDataError(let lhsMissingDataErrorDetail), .missingDataError(let rhsMissingDataErrorDetail)):
            return lhsMissingDataErrorDetail == rhsMissingDataErrorDetail
        case (.glucoseTooOld(let lhsDate), .glucoseTooOld(let rhsDate)),
             (.pumpDataTooOld(let lhsDate), .pumpDataTooOld(let rhsDate)),
             (.recommendationExpired(let lhsDate), .recommendationExpired(let rhsDate)):
            return lhsDate == rhsDate
        case (.invalidData(let lhsDetails), .invalidData(let rhsDetails)):
            return lhsDetails == rhsDetails
        default:
            return false
        }
    }
}
