import XCTest
import LoopKit
import LoopCore

final class WatchContextTests: XCTestCase {
    func testReservoirMessagesRemainCompatibleAcrossPhoneAndWatchVersions() throws {
        // An older phone's numeric value becomes the same typed state used by the current UI.
        let legacy: WatchContext.RawValue = ["v": 5, "cd": Date(), "r": 12.345]
        let receivedLegacy = try XCTUnwrap(WatchContext(rawValue: legacy))
        XCTAssertEqual(receivedLegacy.reservoirLevel, .measured(units: 12.345))

        // A current phone still supplies a measured amount in the older watch's numeric field.
        let measured = WatchContext(reservoirLevel: .measured(units: 12.345))
        XCTAssertEqual(measured.rawValue["r"] as? Double, 12.345)

        // A lower bound must never be sent to an older watch as an exact reservoir amount.
        let bound = WatchContext(reservoirLevel: .aboveThreshold(units: 50))
        XCTAssertNil(bound.rawValue["r"])

        // Current phone and watch versions preserve the bound through the actual transport format.
        let data = try PropertyListSerialization.data(fromPropertyList: bound.rawValue, format: .binary, options: 0)
        let transported = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? WatchContext.RawValue)
        let receivedBound = try XCTUnwrap(WatchContext(rawValue: transported))
        XCTAssertEqual(receivedBound.reservoirLevel, .aboveThreshold(units: 50))
    }
}
