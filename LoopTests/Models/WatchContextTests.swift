import XCTest
import LoopKit
import LoopCore

final class WatchContextTests: XCTestCase {
    func testReservoirTransportKeepsMeasurementLimitsDistinctFromLegacyExactReadings() throws {
        // An older phone's numeric value becomes the same typed state used by the current UI.
        let legacy: WatchContext.RawValue = ["v": 5, "cd": Date(), "r": 12.345]
        let receivedLegacy = try XCTUnwrap(WatchContext(rawValue: legacy))
        XCTAssertEqual(receivedLegacy.reservoirLevel, .measured(units: 12.345))
        XCTAssertEqual(receivedLegacy.rawValue["r"] as? Double, 12.345)

        // A lower bound must never be sent to an older watch as an exact reservoir amount.
        let bound = WatchContext(reservoirLevel: .aboveThreshold(units: 50))
        XCTAssertNil(bound.rawValue["r"])

        // The typed state takes precedence even if a sender includes an obsolete numeric value.
        var mixed = bound.rawValue
        mixed["r"] = 2.0
        let data = try PropertyListSerialization.data(fromPropertyList: mixed, format: .binary, options: 0)
        let transported = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? WatchContext.RawValue)
        let receivedBound = try XCTUnwrap(WatchContext(rawValue: transported))
        XCTAssertEqual(receivedBound.reservoirLevel, .aboveThreshold(units: 50))
        XCTAssertNil(receivedBound.rawValue["r"])
    }
}
