//
//  CarbStoreTests.swift
//  LoopTests
//
//  Created by Darin Krauss on 5/11/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit

struct TestLocalizedError: LocalizedError {
    public let errorDescription: String?
    public let failureReason: String?
    public let helpAnchor: String?
    public let recoverySuggestion: String?

    init(errorDescription: String? = nil, failureReason: String? = nil, helpAnchor: String? = nil, recoverySuggestion: String? = nil) {
        self.errorDescription = errorDescription
        self.failureReason = failureReason
        self.helpAnchor = helpAnchor
        self.recoverySuggestion = recoverySuggestion
    }
}

class CarbStoreCarbStoreErrorCodableTests: XCTestCase {
    func testCodableConfigurationError() throws {
        try assertCarbStoreErrorCodable(.notConfigured, encodesJSON: """
{
  "carbStoreError" : "notConfigured"
}
"""
        )
    }

    func testCodableInitializationError() throws {
        let localizedError = TestLocalizedError(errorDescription: "CarbStoreError.healthStoreError.error.errorDescription",
                                                failureReason: "CarbStoreError.healthStoreError.error.failureReason",
                                                helpAnchor: "CarbStoreError.healthStoreError.error.helpAnchor",
                                                recoverySuggestion: "CarbStoreError.healthStoreError.error.recoverySuggestion")
        try assertCarbStoreErrorCodable(.healthStoreError(localizedError), encodesJSON: """
{
  "carbStoreError" : {
    "healthStoreError" : {
      "error" : {
        "errorDescription" : "CarbStoreError.healthStoreError.error.errorDescription",
        "failureReason" : "CarbStoreError.healthStoreError.error.failureReason",
        "helpAnchor" : "CarbStoreError.healthStoreError.error.helpAnchor",
        "recoverySuggestion" : "CarbStoreError.healthStoreError.error.recoverySuggestion"
      }
    }
  }
}
"""
        )
    }

    func testCodableCoreDataError() throws {
        let localizedError = TestLocalizedError(errorDescription: "CarbStoreError.coreDataError.error.errorDescription",
                                                failureReason: "CarbStoreError.coreDataError.error.failureReason",
                                                helpAnchor: "CarbStoreError.coreDataError.error.helpAnchor",
                                                recoverySuggestion: "CarbStoreError.coreDataError.error.recoverySuggestion")
        try assertCarbStoreErrorCodable(.coreDataError(localizedError), encodesJSON: """
{
  "carbStoreError" : {
    "coreDataError" : {
      "error" : {
        "errorDescription" : "CarbStoreError.coreDataError.error.errorDescription",
        "failureReason" : "CarbStoreError.coreDataError.error.failureReason",
        "helpAnchor" : "CarbStoreError.coreDataError.error.helpAnchor",
        "recoverySuggestion" : "CarbStoreError.coreDataError.error.recoverySuggestion"
      }
    }
  }
}
"""
        )
    }

    func testCodablePersistenceError() throws {
        try assertCarbStoreErrorCodable(.unauthorized, encodesJSON: """
{
  "carbStoreError" : "unauthorized"
}
"""
        )
    }

    func testCodableFetchError() throws {
        try assertCarbStoreErrorCodable(.noData, encodesJSON: """
{
  "carbStoreError" : "noData"
}
"""
        )
    }

    private func assertCarbStoreErrorCodable(_ original: CarbStore.CarbStoreError, encodesJSON string: String) throws {
        let data = try encoder.encode(TestContainer(carbStoreError: original))
        XCTAssertEqual(String(data: data, encoding: .utf8), string)
        let decoded = try decoder.decode(TestContainer.self, from: data)
        XCTAssertEqual(decoded.carbStoreError, original)
    }

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private let decoder = JSONDecoder()

    private struct TestContainer: Codable, Equatable {
        let carbStoreError: CarbStore.CarbStoreError
    }
}

extension CarbStore.CarbStoreError: Equatable {
    public static func == (lhs: CarbStore.CarbStoreError, rhs: CarbStore.CarbStoreError) -> Bool {
        switch (lhs, rhs) {
        case (.notConfigured, .notConfigured):
            return true
        case (.healthStoreError(let lhsError), .healthStoreError(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        case (.coreDataError(let lhsError), .coreDataError(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        case (.unauthorized, .unauthorized),
             (.noData, .noData):
            return true
        default:
            return false
        }
    }
}
