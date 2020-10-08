//
//  DoseStoreTests.swift
//  LoopTests
//
//  Created by Darin Krauss on 5/11/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit

class DoseStoreDoseStoreErrorCodableTests: XCTestCase {
    func testCodableConfigurationError() throws {
        try assertDoseStoreDoseStoreErrorCodable(.configurationError, encodesJSON: """
{
  "doseStoreError" : "configurationError"
}
""")
    }
    
    func testCodableInitializationErrorWithRecoverySuggestion() throws {
        try assertDoseStoreDoseStoreErrorCodable(.initializationError(description: "DoseStoreError.initializationError.description",
                                                                      recoverySuggestion: "DoseStoreError.initializationError.recoverySuggestion"),
                                                 encodesJSON: """
{
  "doseStoreError" : {
    "initializationError" : {
      "description" : "DoseStoreError.initializationError.description",
      "recoverySuggestion" : "DoseStoreError.initializationError.recoverySuggestion"
    }
  }
}
"""
        )
    }

    func testCodableInitializationErrorWithoutRecoverySuggestion() throws {
        try assertDoseStoreDoseStoreErrorCodable(.initializationError(description: "DoseStoreError.initializationError.description",
                                                                      recoverySuggestion: nil),
                                                 encodesJSON: """
{
  "doseStoreError" : {
    "initializationError" : {
      "description" : "DoseStoreError.initializationError.description"
    }
  }
}
"""
        )
    }

    func testCodablePersistenceErrorWithRecoverySuggestion() throws {
        try assertDoseStoreDoseStoreErrorCodable(.persistenceError(description: "DoseStoreError.persistenceError.description",
                                                                   recoverySuggestion: "DoseStoreError.persistenceError.recoverySuggestion"),
                                                 encodesJSON: """
{
  "doseStoreError" : {
    "persistenceError" : {
      "description" : "DoseStoreError.persistenceError.description",
      "recoverySuggestion" : "DoseStoreError.persistenceError.recoverySuggestion"
    }
  }
}
"""
        )
    }

    func testCodablePersistenceErrorWithoutRecoverySuggestion() throws {
        try assertDoseStoreDoseStoreErrorCodable(.persistenceError(description: "DoseStoreError.persistenceError.description",
                                                                   recoverySuggestion: nil),
                                                 encodesJSON: """
{
  "doseStoreError" : {
    "persistenceError" : {
      "description" : "DoseStoreError.persistenceError.description"
    }
  }
}
"""
        )
    }

    func testCodableFetchErrorWithRecoverySuggestion() throws {
        try assertDoseStoreDoseStoreErrorCodable(.fetchError(description: "DoseStoreError.fetchError.description",
                                                             recoverySuggestion: "DoseStoreError.fetchError.recoverySuggestion"),
                                                 encodesJSON: """
{
  "doseStoreError" : {
    "fetchError" : {
      "description" : "DoseStoreError.fetchError.description",
      "recoverySuggestion" : "DoseStoreError.fetchError.recoverySuggestion"
    }
  }
}
"""
        )
    }

    func testCodableFetchErrorWithoutRecoverySuggestion() throws {
        try assertDoseStoreDoseStoreErrorCodable(.fetchError(description: "DoseStoreError.fetchError.description",
                                                             recoverySuggestion: nil),
                                                 encodesJSON: """
{
  "doseStoreError" : {
    "fetchError" : {
      "description" : "DoseStoreError.fetchError.description"
    }
  }
}
"""
        )
    }
    
    private func assertDoseStoreDoseStoreErrorCodable(_ original: DoseStore.DoseStoreError, encodesJSON string: String) throws {
        let data = try encoder.encode(TestContainer(doseStoreError: original))
        XCTAssertEqual(String(data: data, encoding: .utf8), string)
        let decoded = try decoder.decode(TestContainer.self, from: data)
        XCTAssertEqual(decoded.doseStoreError, original)
    }

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private let decoder = JSONDecoder()

    private struct TestContainer: Codable, Equatable {
        let doseStoreError: DoseStore.DoseStoreError
    }
}

extension DoseStore.DoseStoreError: Equatable {
    public static func == (lhs: DoseStore.DoseStoreError, rhs: DoseStore.DoseStoreError) -> Bool {
        switch (lhs, rhs) {
        case (.configurationError, .configurationError):
            return true
        case (.initializationError(let lhsDescription, let lhsRecoverySuggestion), .initializationError(let rhsDescription, let rhsRecoverySuggestion)),
             (.persistenceError(let lhsDescription, let lhsRecoverySuggestion), .persistenceError(let rhsDescription, let rhsRecoverySuggestion)),
             (.fetchError(let lhsDescription, let lhsRecoverySuggestion), .fetchError(let rhsDescription, let rhsRecoverySuggestion)):
            return lhsDescription == rhsDescription && lhsRecoverySuggestion == rhsRecoverySuggestion
        default:
            return false
        }
    }
}
