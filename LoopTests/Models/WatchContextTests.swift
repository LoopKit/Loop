import XCTest
import LoopKit
import LoopCore

final class WatchContextTests: XCTestCase {
    func testReservoirMessagesRemainCompatibleAcrossPhoneAndWatchVersions() throws {
        // Decode the numeric reservoir field found in previously cached watch contexts.
        let legacy: WatchContext.RawValue = ["v": 5, "cd": Date(), "r": 12.345]
        let receivedLegacy = try XCTUnwrap(WatchContext(rawValue: legacy))
        XCTAssertEqual(receivedLegacy.reservoirLevel, .measured(units: 12.345))

        // Retain the legacy numeric field for receivers that read only that field.
        let measured = WatchContext(reservoirLevel: .measured(units: 12.345))
        XCTAssertEqual(measured.rawValue["r"] as? Double, 12.345)

        // A measurement limit cannot be encoded as a measured amount in the numeric-only field.
        let bound = WatchContext(reservoirLevel: .aboveThreshold(units: 50))
        XCTAssertNil(bound.rawValue["r"])

        // The typed field preserves the measurement limit through property-list serialization.
        let data = try PropertyListSerialization.data(fromPropertyList: bound.rawValue, format: .binary, options: 0)
        let transported = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? WatchContext.RawValue)
        let receivedBound = try XCTUnwrap(WatchContext(rawValue: transported))
        XCTAssertEqual(receivedBound.reservoirLevel, .aboveThreshold(units: 50))
    }
}
