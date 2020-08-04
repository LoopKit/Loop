//
//  SetBolusErrorTests.swift
//  LoopTests
//
//  Created by Darin Krauss on 5/11/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit

class SetBolusErrorCodableTests: XCTestCase {
    func testCodableCertain() throws {
        let localizedError = TestLocalizedError(errorDescription: "SetBolusError.certain.localizedError.errorDescription",
                                                failureReason: "SetBolusError.certain.localizedError.failureReason",
                                                helpAnchor: "SetBolusError.certain.localizedError.helpAnchor",
                                                recoverySuggestion: "SetBolusError.certain.localizedError.recoverySuggestion")
        try assertSetBolusErrorCodable(.certain(localizedError), encodesJSON: """
{
  "setBolusError" : {
    "certain" : {
      "localizedError" : {
        "errorDescription" : "SetBolusError.certain.localizedError.errorDescription",
        "failureReason" : "SetBolusError.certain.localizedError.failureReason",
        "helpAnchor" : "SetBolusError.certain.localizedError.helpAnchor",
        "recoverySuggestion" : "SetBolusError.certain.localizedError.recoverySuggestion"
      }
    }
  }
}
"""
        )
    }
    
    func testCodableUncertain() throws {
        let localizedError = TestLocalizedError(errorDescription: "SetBolusError.uncertain.localizedError.errorDescription",
                                                failureReason: "SetBolusError.uncertain.localizedError.failureReason",
                                                helpAnchor: "SetBolusError.uncertain.localizedError.helpAnchor",
                                                recoverySuggestion: "SetBolusError.uncertain.localizedError.recoverySuggestion")
        try assertSetBolusErrorCodable(.uncertain(localizedError), encodesJSON: """
{
  "setBolusError" : {
    "uncertain" : {
      "localizedError" : {
        "errorDescription" : "SetBolusError.uncertain.localizedError.errorDescription",
        "failureReason" : "SetBolusError.uncertain.localizedError.failureReason",
        "helpAnchor" : "SetBolusError.uncertain.localizedError.helpAnchor",
        "recoverySuggestion" : "SetBolusError.uncertain.localizedError.recoverySuggestion"
      }
    }
  }
}
"""
        )
    }

    private func assertSetBolusErrorCodable(_ original: SetBolusError, encodesJSON string: String) throws {
        let data = try encoder.encode(TestContainer(setBolusError: original))
        XCTAssertEqual(String(data: data, encoding: .utf8), string)
        let decoded = try decoder.decode(TestContainer.self, from: data)
        XCTAssertEqual(decoded.setBolusError, original)
    }

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private let decoder = JSONDecoder()

    private struct TestContainer: Codable, Equatable {
        let setBolusError: SetBolusError
    }
}

extension SetBolusError: Equatable {
    public static func == (lhs: SetBolusError, rhs: SetBolusError) -> Bool {
        switch (lhs, rhs) {
        case (.certain(let lhsLocalizedError), .certain(let rhsLocalizedError)),
             (.uncertain(let lhsLocalizedError), .uncertain(let rhsLocalizedError)):
            return lhsLocalizedError.errorDescription == rhsLocalizedError.errorDescription &&
                lhsLocalizedError.failureReason == rhsLocalizedError.failureReason &&
                lhsLocalizedError.helpAnchor == rhsLocalizedError.helpAnchor &&
                lhsLocalizedError.recoverySuggestion == rhsLocalizedError.recoverySuggestion
        default:
            return false
        }
    }
}

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
