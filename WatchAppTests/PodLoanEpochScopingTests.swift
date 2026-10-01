//
//  PodLoanEpochScopingTests.swift
//  WatchAppTests
//

import XCTest
import LoopKit
import OmnipodKit
import LoopCore
import LoopAlgorithm
@testable import WatchApp

// MARK: - The lean reacquisition path's one piece of persisted state

/// Discovery is name resolution: it turns a pod id we already know into a CoreBluetooth
/// handle THIS device can use. Handles are per-device, so the one in a grant is the phone's
/// and useless here — but ours is reusable for every later loan with the same pod.
///
/// These cover the decision logic only. Whether a cached handle is still VALID is a question
/// only the radio can answer, which is why the caller keeps a discovery fallback.
final class PodLoanBleIdentifierCacheTests: XCTestCase {

    private let podA: UInt32 = 0x177E6B7E
    private let podB: UInt32 = 0x1A2B3C4D

    override func setUp() {
        super.setUp()
        PodLoanBleIdentifierCache.removeAll()
    }

    override func tearDown() {
        PodLoanBleIdentifierCache.removeAll()
        super.tearDown()
    }

    func testAnUnknownPodHasNoHandleSoTheCallerMustDiscover() {
        XCTAssertNil(PodLoanBleIdentifierCache.identifier(forPodAddress: podA))
    }

    func testAHandleSurvivesForTheSamePod() {
        PodLoanBleIdentifierCache.store("UUID-A", forPodAddress: podA)
        XCTAssertEqual(PodLoanBleIdentifierCache.identifier(forPodAddress: podA), "UUID-A")
    }

    /// The key must be the POD, not "the last pod we saw". A pod change every three days
    /// would otherwise hand the new pod the old pod's handle — a bare connect() has no
    /// timeout, so that would hang rather than fail.
    func testHandlesAreKeyedPerPodAndDoNotBleed() {
        PodLoanBleIdentifierCache.store("UUID-A", forPodAddress: podA)
        PodLoanBleIdentifierCache.store("UUID-B", forPodAddress: podB)
        XCTAssertEqual(PodLoanBleIdentifierCache.identifier(forPodAddress: podA), "UUID-A")
        XCTAssertEqual(PodLoanBleIdentifierCache.identifier(forPodAddress: podB), "UUID-B")
    }

    /// Re-adopting the same pod on a different handle must REPLACE, not accumulate: the
    /// stale one can never be retrieved on this device and would pin the radio scanning.
    func testReAdoptingReplacesTheHandle() {
        PodLoanBleIdentifierCache.store("UUID-OLD", forPodAddress: podA)
        PodLoanBleIdentifierCache.store("UUID-NEW", forPodAddress: podA)
        XCTAssertEqual(PodLoanBleIdentifierCache.identifier(forPodAddress: podA), "UUID-NEW")
    }


    /// THE REGRESSION THIS SUITE MISSED (field 2026-08-20, epochs 150-152).
    ///
    /// `PodState` decodes the LTK and the BLE handle in a SINGLE `if let`, so removing
    /// `bleIdentifier` from a grant's raw state silently removes the pod's ENCRYPTION KEY with
    /// it. The takeover then connects normally and the pod hangs up ~100 ms after the first
    /// command — which looks nothing like "a key is missing", and cost three grants to spot.
    ///
    /// Every cache test below passed while that shipped, because the bug was never in the
    /// cache: it was in what the CALLER does on a cache MISS. This pins the coupling so nobody
    /// "tidies up" the foreign identifier again.
    func testLtkAndHandleAreCoupledInPodStateDecoding() throws {
        let podStatePath = #filePath
            .replacingOccurrences(of: "Loop/WatchAppTests/PodLoanEpochScopingTests.swift",
                                  with: "OmnipodKit/OmnipodKit/PumpManager/PodState.swift")
        let source = try String(contentsOfFile: podStatePath, encoding: .utf8)
        // The property that matters is whether ltk's `if let` is a STANDALONE condition or a
        // COMPOUND one. Textual proximity cannot tell those apart — the two branches sit next to
        // each other by design — so read the ltk line itself: a compound condition continues with
        // a comma, a standalone one opens its brace.
        guard let ltkLine = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first(where: { $0.contains("let ltkString = rawValue[\"ltk\"]") })
        else {
            return XCTFail("PodState no longer decodes ltk the way this test expects — re-check every site that edits a grant's raw podState")
        }
        let trimmed = ltkLine.trimmingCharacters(in: .whitespaces)
        XCTAssertTrue(trimmed.hasSuffix("{"),
                      "PodState's ltk decode is a COMPOUND condition again (line: \(trimmed)). Whatever it is bound with — bleIdentifier historically — becomes load-bearing for the pod's ENCRYPTION KEY, so dropping that disposable field silently drops the key and the pod hangs up ~108 ms after the first command. Decode ltk on its own.")
    }

    /// `forget` is the escape hatch for a handle proven wrong, so the next loan pays for
    /// discovery once instead of pending forever on a dead UUID.
    func testForgettingSendsUsBackToDiscoveryForThatPodOnly() {
        PodLoanBleIdentifierCache.store("UUID-A", forPodAddress: podA)
        PodLoanBleIdentifierCache.store("UUID-B", forPodAddress: podB)
        PodLoanBleIdentifierCache.forget(podAddress: podA)
        XCTAssertNil(PodLoanBleIdentifierCache.identifier(forPodAddress: podA))
        XCTAssertEqual(PodLoanBleIdentifierCache.identifier(forPodAddress: podB), "UUID-B",
                       "forgetting one pod must not disturb another")
    }
}

// MARK: - Stranded sensor identity (#104's blind spot)

/// #104 keeps a persisted sensor identity when stock reports nil, which is right on a watch —
/// that signal fires after nearly every loan. What it swallows is a REAL sensor change, and the
/// manager cannot rescue itself: it learns a new sensor's ID only by talking to it, and it is
/// busy failing authentication against the old one.
///
/// These cover the DECISION, not the radio: the age predicate that both the persist filter and
/// the launch restore now share, since the escape living only on the write path is what let a
/// dead identity be restored 19 hours past its own expiry (pure/SportMode field case, three days
/// of auth failures, zero direct readings).
final class StrandedSensorIdentityTests: XCTestCase {

    private let tenDaysTwelveHours: TimeInterval = .hours(10 * 24 + 12)

    func testAFreshSensorIsNotPastLife() {
        let activated = Date().addingTimeInterval(-.hours(24))
        XCTAssertFalse(WatchLoopManager.persistedSensorIsPastLife(activated))
    }

    /// The boundary matters: a sensor at 10d11h is still nominally alive and forgetting it would
    /// re-open the false-forget #104 exists to prevent.
    func testJustInsideTheGraceWindowIsKept() {
        let now = Date()
        let activated = now.addingTimeInterval(-(tenDaysTwelveHours - .minutes(30)))
        XCTAssertFalse(WatchLoopManager.persistedSensorIsPastLife(activated, now: now))
    }

    func testPastTenDaysTwelveHoursIsDiscardable() {
        let now = Date()
        let activated = now.addingTimeInterval(-(tenDaysTwelveHours + .minutes(1)))
        XCTAssertTrue(WatchLoopManager.persistedSensorIsPastLife(activated, now: now))
    }

    /// Never discard on a guess. A blob with no activation date tells us nothing about age, and
    /// throwing away a possibly-live identity costs direct readings for the rest of its life.
    func testUnknownAgeIsNeverDiscarded() {
        XCTAssertFalse(WatchLoopManager.persistedSensorIsPastLife(nil))
    }

    /// The field case that motivated the read-path fix: an identity restored PAST its own expiry.
    /// Before the fix this predicate was never consulted at launch, so this returned true and
    /// nothing asked.
    func testTheFieldCaseNineteenHoursPastExpiryIsDiscardable() {
        let now = Date()
        let activated = now.addingTimeInterval(-(tenDaysTwelveHours + .hours(19)))
        XCTAssertTrue(WatchLoopManager.persistedSensorIsPastLife(activated, now: now),
                      "a sensor 19h past its grace window must not be restored at launch — the manager will auto-connect to it and fail auth forever")
    }
}

// MARK: - Sport Mode start gate

/// The gate refuses a loan that would run on relayed BG alone. The argument: the phone reads the
/// sensor over BLE and the sensor is on the body, so a phone close enough to relay is close enough
/// to drive the pod itself — a relay-only loan is redundant or degraded, never useful.
///
/// This branch's departure from pure's: the range argument holds only for a REAL BLE sensor, not
/// for a CGM Simulator or cloud source. So the gate keys on whether THIS WATCH has an enrolled,
/// still-living sensor that has gone quiet — no protocol field, and bench setups stay unblocked.
final class SportModeStartGateTests: XCTestCase {

    private func verdict(_ sensorName: String?, _ activatedAt: Date?, _ lastDirect: Date?, _ now: Date) -> WatchLoopManager.StartGateVerdict {
        WatchLoopManager.startGateVerdict(sensorName: sensorName, sensorActivatedAt: activatedAt,
                                          lastDirectG7At: lastDirect, now: now)
    }

    /// No enrolled sensor WARNS rather than blocks. A bench rig and a brand-new user are
    /// indistinguishable from the watch, and refusing would cost the no-sensor bench workflow —
    /// so the verdict is its own case, and the caller proceeds after saying so.
    func testNoEnrolledSensorWarnsButDoesNotBlock() {
        let now = Date()
        XCTAssertEqual(verdict(nil, nil, nil, now), .noSensorEverEnrolled)
    }

    /// An identity past its life is a corpse the launch path discards; it must not block Start on
    /// its way out, or a dead sensor would lock the wearer out of Sport Mode entirely.
    func testExpiredSensorAllowsStart() {
        let now = Date()
        XCTAssertEqual(verdict("DXCMqL", now.addingTimeInterval(-.hours(10 * 24 + 13)), nil, now), .allowed)
    }

    /// Enrolled, alive, delivering: the healthy case must not be refused.
    func testFreshDirectReadingAllowsStart() {
        let now = Date()
        XCTAssertEqual(verdict("DXCMqL", now.addingTimeInterval(-.hours(24)), now.addingTimeInterval(-.minutes(4)), now), .allowed)
    }

    /// Not a fault: a fresh enrollment legitimately takes minutes, so it gets the calmer wording
    /// rather than a "check Dexcom" prompt that reads as an error on a healthy new sensor.
    func testEnrolledButNeverDeliveredIsWaiting() {
        let now = Date()
        XCTAssertEqual(verdict("DXCMu0", now.addingTimeInterval(-.minutes(3)), nil, now), .waitingForFirstReading(sensorName: "DXCMu0"))
    }

    /// The field case: enrolled, alive, and silent past the bound. A loan here would run on relay
    /// alone and stop looping the moment the phone leaves.
    func testEnrolledAndSilentBlocksStart() {
        let now = Date()
        XCTAssertEqual(verdict("DXCMqL", now.addingTimeInterval(-.hours(24)), now.addingTimeInterval(-.minutes(31)), now), .noDirectConnection(sensorName: "DXCMqL", silentMinutes: 31))
    }

    /// The bound is 15 minutes, not the 7-minute display window: deciding whether the LINK works
    /// needs three missed cadence periods, or one jittered reading refuses a healthy setup.
    func testJustInsideTheBoundStillAllowsStart() {
        let now = Date()
        XCTAssertEqual(verdict("DXCMqL", now.addingTimeInterval(-.hours(24)), now.addingTimeInterval(-(WatchLoopManager.startGateSilenceLimit - .minutes(1))), now), .allowed)
    }
}


// MARK: - The BLE-wedge signature (PodLoanConnectClock.isWedge)

/// A takeover failure carries the WEDGE signature when a CBError#11 landed during the attempt,
/// or when no connect EVER landed against a pod the phone released seconds earlier. The verdict
/// changes the user-facing remedy — a wedge means "toggle watch Bluetooth", because retrying
/// feeds it (system-level pending connects survive force-quit and accumulate) — so both false
/// positives and false negatives put the WRONG instruction on the wrist.
final class BleWedgeSignatureTests: XCTestCase {

    private let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func testCode11DuringTheAttemptIsAWedge() {
        XCTAssertTrue(PodLoanConnectClock.isWedge(lastCode11At: start.addingTimeInterval(5),
                                                  lastConnectAt: start.addingTimeInterval(2),
                                                  since: start),
                      "a slot refusal during the attempt is the wedge even if some connect landed")
    }

    /// Stale evidence must not indict a fresh attempt: the clock is reset at takeover start, but
    /// reclaim ladders share it across a loan, so the time test is what scopes the verdict.
    func testCode11FromBeforeTheAttemptIsNot() {
        XCTAssertFalse(PodLoanConnectClock.isWedge(lastCode11At: start.addingTimeInterval(-60),
                                                   lastConnectAt: start.addingTimeInterval(3),
                                                   since: start))
    }

    /// At takeover the pod is known-present — the phone was talking to it seconds ago and
    /// released it for us — so a whole attempt with zero didConnect is our radio, not the pod.
    func testNoConnectEverIsAWedge() {
        XCTAssertTrue(PodLoanConnectClock.isWedge(lastCode11At: nil, lastConnectAt: nil, since: start))
    }

    func testConnectLandedAndNoCode11IsNotAWedge() {
        XCTAssertFalse(PodLoanConnectClock.isWedge(lastCode11At: nil,
                                                   lastConnectAt: start.addingTimeInterval(1.3),
                                                   since: start))
    }

    /// A connect from BEFORE the attempt is somebody else's evidence — a prior ladder's success
    /// must not make this attempt read as healthy.
    func testConnectFromBeforeTheAttemptDoesNotCount() {
        XCTAssertTrue(PodLoanConnectClock.isWedge(lastCode11At: nil,
                                                  lastConnectAt: start.addingTimeInterval(-300),
                                                  since: start))
    }
}
