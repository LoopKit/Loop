//
//  PumpManagerErrorTests.swift
//  LoopTests
//
//  Created by Darin Krauss on 5/11/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit

class PumpManagerErrorCodableTests: XCTestCase {
    func testCodableConfigurationWithLocalizedError() throws {
        let localizedError = TestLocalizedError(errorDescription: "PumpManagerError.configuration.localizedError.errorDescription",
                                                failureReason: "PumpManagerError.configuration.localizedError.failureReason",
                                                helpAnchor: "PumpManagerError.configuration.localizedError.helpAnchor",
                                                recoverySuggestion: "PumpManagerError.configuration.localizedError.recoverySuggestion")
        try assertPumpManagerErrorCodable(.configuration(localizedError), encodesJSON: """
{
  "pumpManagerError" : {
    "configuration" : {
      "localizedError" : {
        "errorDescription" : "PumpManagerError.configuration.localizedError.errorDescription",
        "failureReason" : "PumpManagerError.configuration.localizedError.failureReason",
        "helpAnchor" : "PumpManagerError.configuration.localizedError.helpAnchor",
        "recoverySuggestion" : "PumpManagerError.configuration.localizedError.recoverySuggestion"
      }
    }
  }
}
"""
        )
    }
    
    func testCodableConfigurationWithoutLocalizedError() throws {
        try assertPumpManagerErrorCodable(.configuration(nil), encodesJSON: """
{
  "pumpManagerError" : {
    "configuration" : {

    }
  }
}
"""
        )
    }
    
    func testCodableConnectionWithLocalizedError() throws {
        let localizedError = TestLocalizedError(errorDescription: "PumpManagerError.connection.localizedError.errorDescription",
                                                failureReason: "PumpManagerError.connection.localizedError.failureReason",
                                                helpAnchor: "PumpManagerError.connection.localizedError.helpAnchor",
                                                recoverySuggestion: "PumpManagerError.connection.localizedError.recoverySuggestion")
        try assertPumpManagerErrorCodable(.connection(localizedError), encodesJSON: """
{
  "pumpManagerError" : {
    "connection" : {
      "localizedError" : {
        "errorDescription" : "PumpManagerError.connection.localizedError.errorDescription",
        "failureReason" : "PumpManagerError.connection.localizedError.failureReason",
        "helpAnchor" : "PumpManagerError.connection.localizedError.helpAnchor",
        "recoverySuggestion" : "PumpManagerError.connection.localizedError.recoverySuggestion"
      }
    }
  }
}
"""
        )
    }
    
    func testCodableConnectionWithoutLocalizedError() throws {
        try assertPumpManagerErrorCodable(.connection(nil), encodesJSON: """
{
  "pumpManagerError" : {
    "connection" : {

    }
  }
}
"""
        )
    }
    
    func testCodableCommunicationWithLocalizedError() throws {
        let localizedError = TestLocalizedError(errorDescription: "PumpManagerError.communication.localizedError.errorDescription",
                                                failureReason: "PumpManagerError.communication.localizedError.failureReason",
                                                helpAnchor: "PumpManagerError.communication.localizedError.helpAnchor",
                                                recoverySuggestion: "PumpManagerError.communication.localizedError.recoverySuggestion")
        try assertPumpManagerErrorCodable(.communication(localizedError), encodesJSON: """
{
  "pumpManagerError" : {
    "communication" : {
      "localizedError" : {
        "errorDescription" : "PumpManagerError.communication.localizedError.errorDescription",
        "failureReason" : "PumpManagerError.communication.localizedError.failureReason",
        "helpAnchor" : "PumpManagerError.communication.localizedError.helpAnchor",
        "recoverySuggestion" : "PumpManagerError.communication.localizedError.recoverySuggestion"
      }
    }
  }
}
"""
        )
    }
    
    func testCodableCommunicationWithoutLocalizedError() throws {
        try assertPumpManagerErrorCodable(.communication(nil), encodesJSON: """
{
  "pumpManagerError" : {
    "communication" : {

    }
  }
}
"""
        )
    }
    
    func testCodableDeviceStateWithLocalizedError() throws {
        let localizedError = TestLocalizedError(errorDescription: "PumpManagerError.deviceState.localizedError.errorDescription",
                                                failureReason: "PumpManagerError.deviceState.localizedError.failureReason",
                                                helpAnchor: "PumpManagerError.deviceState.localizedError.helpAnchor",
                                                recoverySuggestion: "PumpManagerError.deviceState.localizedError.recoverySuggestion")
        try assertPumpManagerErrorCodable(.deviceState(localizedError), encodesJSON: """
{
  "pumpManagerError" : {
    "deviceState" : {
      "localizedError" : {
        "errorDescription" : "PumpManagerError.deviceState.localizedError.errorDescription",
        "failureReason" : "PumpManagerError.deviceState.localizedError.failureReason",
        "helpAnchor" : "PumpManagerError.deviceState.localizedError.helpAnchor",
        "recoverySuggestion" : "PumpManagerError.deviceState.localizedError.recoverySuggestion"
      }
    }
  }
}
"""
        )
    }
    
    func testCodableDeviceStateWithoutLocalizedError() throws {
        try assertPumpManagerErrorCodable(.deviceState(nil), encodesJSON: """
{
  "pumpManagerError" : {
    "deviceState" : {

    }
  }
}
"""
        )
    }
    
    func testCodableUncertainDeliveryError() throws {
        try assertPumpManagerErrorCodable(.uncertainDelivery, encodesJSON: """
{
  "pumpManagerError" : "uncertainDelivery"
}
"""
        )
    }

    
    private func assertPumpManagerErrorCodable(_ original: PumpManagerError, encodesJSON string: String) throws {
        let data = try encoder.encode(TestContainer(pumpManagerError: original))
        XCTAssertEqual(String(data: data, encoding: .utf8), string)
        let decoded = try decoder.decode(TestContainer.self, from: data)
        XCTAssertEqual(decoded.pumpManagerError, original)
    }

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private let decoder = JSONDecoder()

    private struct TestContainer: Codable, Equatable {
        let pumpManagerError: PumpManagerError
    }
}

extension PumpManagerError: Equatable {
    public static func == (lhs: PumpManagerError, rhs: PumpManagerError) -> Bool {
        switch (lhs, rhs) {
        case (.configuration(let lhsLocalizedError), .configuration(let rhsLocalizedError)),
             (.connection(let lhsLocalizedError), .connection(let rhsLocalizedError)),
             (.communication(let lhsLocalizedError), .communication(let rhsLocalizedError)),
             (.deviceState(let lhsLocalizedError), .deviceState(let rhsLocalizedError)):
            return lhsLocalizedError?.localizedDescription == rhsLocalizedError?.localizedDescription &&
                lhsLocalizedError?.errorDescription == rhsLocalizedError?.errorDescription &&
                lhsLocalizedError?.failureReason == rhsLocalizedError?.failureReason &&
                lhsLocalizedError?.helpAnchor == rhsLocalizedError?.helpAnchor &&
                lhsLocalizedError?.recoverySuggestion == rhsLocalizedError?.recoverySuggestion
        case (.uncertainDelivery, .uncertainDelivery):
            return true
        default:
            return false
        }
    }
}
