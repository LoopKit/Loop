//
//  G7SilenceHintTests.swift
//  WatchAppTests
//
//  The glance's wedge hint has three gates (two missed bursts, the phone not relaying, and the
//  ruled wording that names the WATCH's Bluetooth); the tests exist so a later edit cannot
//  quietly move them.
//

import XCTest
import LoopAlgorithm
@testable import WatchApp

final class G7SilenceHintTests: XCTestCase {
    func testTwoMissesWithThePhoneAwayNameTheWatchBluetooth() {
        let hint = G7SilenceHint.text(directAge: 11 * 60, relayAge: nil)
        XCTAssertNotNil(hint)
        XCTAssertTrue(hint!.contains("watch Bluetooth"), "ruled wording: it must name the WATCH")
        XCTAssertTrue(hint!.contains("11 min"))
    }

    func testOneMissIsNotAWedge() {
        XCTAssertNil(G7SilenceHint.text(directAge: 7 * 60, relayAge: nil))
    }

    func testAPhoneThatIsRelayingIsNotAWedge() {
        XCTAssertNil(G7SilenceHint.text(directAge: 15 * 60, relayAge: 3 * 60),
                     "the phone is collecting — a missed direct read with a relay is not the parked stack")
    }

    func testAFreshNumberNeverCarriesTheHint() {
        XCTAssertNil(G7SilenceHint.text(directAge: 60, relayAge: nil))
        XCTAssertNil(G7SilenceHint.text(directAge: nil, relayAge: nil))
    }
}

// MARK: - The sensor change that used to trigger it

extension G7SilenceHintTests {

    /// The defect this rule exists for. A sensor change leaves the last direct reading with the
    /// EXPIRING sensor, then hours of warm-up silence — the exact picture of a parked radio. The
    /// hint told the user to toggle Bluetooth at a sensor they had just put on, for the whole
    /// warm-up, and the minutes it quoted were counted across the change.
    func testANewSensorsWarmUpIsNotAParkedRadio() {
        XCTAssertNil(G7SilenceHint.text(directAge: .hours(1), relayAge: nil, sensorAge: .minutes(20)),
                     "a sensor twenty minutes old is quiet because it is warming up")
        XCTAssertNil(G7SilenceHint.text(directAge: .hours(2), relayAge: nil, sensorAge: .hours(2)),
                     "and still warming up at two hours")
    }

    /// Past the allowance the hint comes back: a sensor that has had time to start and still
    /// delivers nothing is the failure this line is for.
    func testASettledSensorGoingQuietStillEarnsTheHint() {
        XCTAssertNotNil(G7SilenceHint.text(directAge: .minutes(12), relayAge: nil, sensorAge: .hours(6)),
                        "a settled sensor with two missed bursts is the real thing")
    }

    /// An unknown activation date must not suppress it. nil means "not known", and a watch that
    /// has never learned the sensor's start is exactly the one most likely to be parked.
    func testAnUnknownSensorAgeDoesNotSuppressTheHint() {
        XCTAssertNotNil(G7SilenceHint.text(directAge: .minutes(12), relayAge: nil, sensorAge: nil))
    }

    /// The other two conditions still rule. Warm-up is an extra reason to stay quiet, never a
    /// reason to speak.
    func testWarmUpDoesNotOverrideTheOtherConditions() {
        XCTAssertNil(G7SilenceHint.text(directAge: .minutes(3), relayAge: nil, sensorAge: .days(3)),
                     "one missed window is not enough, whatever the sensor's age")
        XCTAssertNil(G7SilenceHint.text(directAge: .minutes(12), relayAge: .minutes(2), sensorAge: .days(3)),
                     "a phone still relaying means glucose is arriving")
    }
}
