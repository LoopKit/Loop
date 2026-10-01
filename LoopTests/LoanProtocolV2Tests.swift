//
//  LoanProtocolV2Tests.swift
//  LoopTests
//
//  Loan protocol v2 unit coverage (DESIGN_LOAN_PROTOCOL_V2.md §10): wire-format
//  round-trip + version skew (never-silently-discard), and the fingerprints-only
//  allocation properties (never reduce confirmed, exact-match preference with
//  latest-on-tie, skipped-reduction window fit, ambiguity touches nothing, one-way
//  valve). Controller-level flows (epoch race D22, resend/ack ordering) are exercised
//  as bench drills Part E; the state machines' UserDefaults/UNNotification coupling
//  keeps them out of unit scope deliberately.
//
//  NOTE: run via Xcode (Cmd-U). CLI test execution fails signing in this environment;
//  the CLI gate is compile-only.
//

import XCTest
import HealthKit
import LoopKit
import LoopCore
import LoopAlgorithm
@testable import Loop

final class LoanProtocolV2Tests: XCTestCase {

    // MARK: - Wire format

    private func roundTrip(_ message: LoanMessage) throws -> LoanMessage? {
        let dict = try message.transportDictionary()
        return try LoanMessage.decode(fromTransport: dict)
    }

    func testEveryMessageKindRoundTrips() throws {
        // Dates on the wire's millisecond grid: the protocol encodes Int64 ms, so
        // sub-millisecond fractions deliberately do not survive (determinism > ULPs).
        let now = Date(timeIntervalSince1970: 1_784_338_000.125)
        let status = LoanPodStatus(timestamp: now, deliveredUnits: 12.3, reservoirLevel: nil, isSuspended: false, faultCode: nil)
        let event = LoanEvent(id: UUID(), seq: 3, provenance: .confirmed,
                              record: LoanDoseRecord(kind: .bolus, startDate: now, amount: 1.0), loggedAt: now)
        let messages: [LoanMessage] = [
            .request(LoanRequest(watchBuild: "77")),
            .grant(LoanGrant(epoch: 5, expiresAt: now.addingTimeInterval(300),
                             pumpManagerRawState: Data([1, 2, 3]), podAddress: 0x1F0A2B3C,
                             therapySettingsRaw: Data([4, 5]), settingsTimeZoneID: "America/New_York",
                             doseHistory: [LoanDoseRecord(kind: .tempBasal, startDate: now, endDate: now.addingTimeInterval(1800), unitsPerHour: 0.8)])),
            .takeoverComplete(TakeoverComplete(epoch: 5, firstPodStatus: status)),
            .takeoverFailed(TakeoverFailed(epoch: 5, reason: "test")),
            .doseRecordBatch(DoseRecordBatch(epoch: 5, events: [event], tombstones: [UUID()])),
            .handbackOffer(HandbackOffer(epoch: 5, handedBackAt: now, finalStatus: status,
                                         odometer: LoanOdometerSnapshot(deliveredAtStart: 10, deliveredLatest: 12, freshenSucceeded: true),
                                         events: [event], tombstones: [], recovered: false)),
            .handbackAck(HandbackAck(epoch: 5, committedCursor: 3)),
            .revoke(Revoke(epoch: 5)),
            .statusQuery(StatusQuery(epoch: 5)),
            .statusReport(StatusReport(epoch: 5, mode: .closedDirect, lastDirectGlucoseAge: 120, lastEventSeq: 3, podFault: nil, holdsPod: true)),
            .nack(ProtocolNack(seenVersion: 1)),
            .denied(LoanDenied(reason: "settings incomplete")),
            .diag(LoanDiag(epoch: 5, text: "offer RX ev=3")),
        ]
        for message in messages {
            XCTAssertEqual(try roundTrip(message), message)
        }
    }

    func testGrantCarbHistoryRoundTrips() throws {
        let now = Date(timeIntervalSince1970: 1_784_338_000.125)
        let carb = LoanCarbRecord(syncIdentifier: "carb-abc", provenanceIdentifier: "com.loopkit.Loop",
                                  syncVersion: 1, startDate: now, grams: 25, absorptionTime: .hours(3),
                                  foodType: "🍕", userCreatedDate: now, userUpdatedDate: nil)
        let grant = LoanGrant(epoch: 7, expiresAt: now.addingTimeInterval(300),
                              pumpManagerRawState: Data([1]), podAddress: 0,
                              therapySettingsRaw: Data([2]), settingsTimeZoneID: "UTC",
                              doseHistory: [], carbHistory: [carb])
        guard case .grant(let g) = try roundTrip(.grant(grant)) else { return XCTFail("not a grant") }
        XCTAssertEqual(g.carbHistory, [carb], "carb history must survive the wire")

        // Backward compat: an older phone sends no carbHistory; it must decode as nil, not [].
        let old = LoanGrant(epoch: 7, expiresAt: now.addingTimeInterval(300),
                            pumpManagerRawState: Data([1]), podAddress: 0,
                            therapySettingsRaw: Data([2]), settingsTimeZoneID: "UTC",
                            doseHistory: [])
        guard case .grant(let g2) = try roundTrip(.grant(old)) else { return XCTFail("not a grant") }
        XCTAssertNil(g2.carbHistory)
    }

    func testGrantGlucoseHistoryRoundTrips() throws {
        let now = Date(timeIntervalSince1970: 1_784_338_000.125)
        let sample = LoanGlucoseRecord(syncIdentifier: "g-1", startDate: now, valueMgdl: 120,
                                       trendRateMgdlPerMin: 1.5, isDisplayOnly: false, wasUserEntered: false)
        let grant = LoanGrant(epoch: 8, expiresAt: now.addingTimeInterval(300),
                              pumpManagerRawState: Data([1]), podAddress: 0,
                              therapySettingsRaw: Data([2]), settingsTimeZoneID: "UTC",
                              doseHistory: [], glucoseHistory: [sample])
        guard case .grant(let g) = try roundTrip(.grant(grant)) else { return XCTFail("not a grant") }
        XCTAssertEqual(g.glucoseHistory, [sample], "glucose history must survive the wire")

        // Backward compat: an older phone sends no glucoseHistory; it must decode as nil, not [].
        let old = LoanGrant(epoch: 8, expiresAt: now.addingTimeInterval(300),
                            pumpManagerRawState: Data([1]), podAddress: 0,
                            therapySettingsRaw: Data([2]), settingsTimeZoneID: "UTC",
                            doseHistory: [])
        guard case .grant(let g2) = try roundTrip(.grant(old)) else { return XCTFail("not a grant") }
        XCTAssertNil(g2.glucoseHistory)
    }

    func testGrantPredictionSnapshotRoundTrips() throws {
        let now = Date(timeIntervalSince1970: 1_784_338_000.125)
        let snap = LoanPredictionSnapshot(
            snapshotAt: now, startGlucoseMgdl: 180, startGlucoseDate: now.addingTimeInterval(-300),
            eventualMgdl: 105, eventualIncludingPendingMgdl: 103,
            impactMomentumMgdl: 39, impactInsulinMgdl: -105, impactCarbMgdl: 0, impactRCMgdl: 6,
            iobUnits: 1.5, iobDate: now.addingTimeInterval(-60), cobGrams: 0,
            momentumPointCount: 5, rcDiscrepancyCount: 7, enabledEffectsRaw: 15)
        let grant = LoanGrant(epoch: 9, expiresAt: now.addingTimeInterval(300),
                              pumpManagerRawState: Data([1]), podAddress: 0,
                              therapySettingsRaw: Data([2]), settingsTimeZoneID: "UTC",
                              doseHistory: [], predictionSnapshot: snap)
        guard case .grant(let g) = try roundTrip(.grant(grant)) else { return XCTFail("not a grant") }
        XCTAssertEqual(g.predictionSnapshot, snap, "prediction snapshot must survive the wire (incl. sub-second dates)")

        // Backward compat: an older phone sends no snapshot; it must decode as nil, not a default.
        let old = LoanGrant(epoch: 9, expiresAt: now.addingTimeInterval(300),
                            pumpManagerRawState: Data([1]), podAddress: 0,
                            therapySettingsRaw: Data([2]), settingsTimeZoneID: "UTC",
                            doseHistory: [])
        guard case .grant(let g2) = try roundTrip(.grant(old)) else { return XCTFail("not a grant") }
        XCTAssertNil(g2.predictionSnapshot)
    }

    func testForeignPayloadIsNotOurs() throws {
        XCTAssertNil(try LoanMessage.decode(fromTransport: ["somethingElse": Data([1])]))
    }

    func testVersionSkewThrowsNeverDiscards() throws {
        var dict = try LoanMessage.revoke(Revoke(epoch: 1)).transportDictionary()
        var json = try JSONSerialization.jsonObject(with: dict[LoanProtocol.userInfoKey] as! Data) as! [String: Any]
        json["protocolVersion"] = 99
        dict[LoanProtocol.userInfoKey] = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try LoanMessage.decode(fromTransport: dict)) { error in
            guard case LoanProtocolError.undecodable(let seen) = error else { return XCTFail() }
            XCTAssertEqual(seen, 99)
        }
    }

    func testUnknownKindThrows() throws {
        var dict = try LoanMessage.revoke(Revoke(epoch: 1)).transportDictionary()
        var json = try JSONSerialization.jsonObject(with: dict[LoanProtocol.userInfoKey] as! Data) as! [String: Any]
        json["kind"] = "futureMessage"
        dict[LoanProtocol.userInfoKey] = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try LoanMessage.decode(fromTransport: dict))
    }

    /// KNOWN_RESIDUALS §16 (test debt): released-flag decode with the key ABSENT.
    ///
    /// A legacy watch only ever offered after it had stopped dosing and released the pod,
    /// so its payload carries no `released` key at all. Passing `released: nil` in Swift is
    /// NOT the same wire shape — the encoder can still emit an explicit null — so this test
    /// strips the key from the encoded JSON to produce the genuine legacy payload. `nil`
    /// must mean FINAL; reading it as "interim" would leave such a watch's loan stranded in
    /// .loaned forever, since a legacy sender never sends anything more definitive.
    func testLegacyOfferWithoutReleasedKeyDecodesAsNil() throws {
        let offer = HandbackOffer(epoch: 7, handedBackAt: Date(), finalStatus: nil, odometer: nil,
                                  events: [], tombstones: [], recovered: false, released: true)
        var dict = try LoanMessage.handbackOffer(offer).transportDictionary()
        var json = try JSONSerialization.jsonObject(with: dict[LoanProtocol.userInfoKey] as! Data) as! [String: Any]
        XCTAssertTrue(Self.stripKey("released", from: &json), "fixture must actually contain a released key to strip")
        dict[LoanProtocol.userInfoKey] = try JSONSerialization.data(withJSONObject: json)

        guard case .handbackOffer(let decoded) = try LoanMessage.decode(fromTransport: dict) else {
            return XCTFail("expected a handbackOffer")
        }
        XCTAssertNil(decoded.released, "an absent key decodes as nil, not as false")
        XCTAssertEqual(decoded.epoch, 7, "the rest of the payload still decodes")
    }

    // MARK: - Pulse model

    /// The pod delivers whole 0.05 U pulses spaced 3600×0.05/rate apart, and restarts that clock
    /// on every new command — so a temp truncated before its next pulse loses it. `expectedInsulin`
    /// must model that, or it systematically over-predicts.
    ///
    /// 2.15 U/hr → a pulse every 83.7 s. Over 302 s the pod fires at 83.7/167.4/251.2 s = 3 pulses
    /// = 0.150 U, while rate×time says 0.180 U. The 0.030 U difference is the partial pulse that
    /// never happened, and it recurs on EVERY replacement — which is what put the first field
    /// residual 6.8 pulses adrift (epoch 5: delivered 2.250 vs expected 2.592).
    func testExpectedInsulinModelsPodPulsesNotRateTimesTime() {
        let start = loanStart
        let temp = LoanEvent(id: UUID(), seq: 1, provenance: .confirmed,
                             record: LoanDoseRecord(kind: .tempBasal, startDate: start,
                                                    endDate: start.addingTimeInterval(302),
                                                    unitsPerHour: 2.15),
                             loggedAt: start)

        let expected = LoanReconciler.expectedInsulin(events: [temp], schedule: nil,
                                                      from: start, to: start.addingTimeInterval(302))

        XCTAssertEqual(expected, 0.150, accuracy: 0.0001,
                       "3 whole pulses — the 4th was still 51 s away when the temp was replaced")
        XCTAssertLessThan(expected, 2.15 * 302 / 3600,
                          "must be strictly less than rate×time: the partial pulse is never delivered")
    }

    /// A bolus is commanded as a pulse count, so it has no partial-pulse tail and must stay exact —
    /// otherwise the fix for basal quantization would introduce a NEW bias on boluses.
    func testExpectedInsulinLeavesBolusesExact() {
        let start = loanStart
        let bolus = LoanEvent(id: UUID(), seq: 1, provenance: .confirmed,
                              record: LoanDoseRecord(kind: .bolus, startDate: start, amount: 1.60),
                              loggedAt: start)

        let expected = LoanReconciler.expectedInsulin(events: [bolus], schedule: nil,
                                                      from: start, to: start.addingTimeInterval(60))
        XCTAssertEqual(expected, 1.60, accuracy: 0.0001)
    }

    /// The bias is per-REPLACEMENT, which is why it grows with loan length: ten identical
    /// five-minute segments lose ten partial pulses, where one fifty-minute segment loses one.
    func testQuantizationLossScalesWithTheNumberOfReplacements() {
        let start = loanStart
        let rate = 1.15   // a pulse every 156.5 s — 300 s gives 1 whole pulse, 0.92 lost
        var chopped: [LoanEvent] = []
        for i in 0..<10 {
            let segStart = start.addingTimeInterval(Double(i) * 300)
            chopped.append(LoanEvent(id: UUID(), seq: i + 1, provenance: .confirmed,
                                     record: LoanDoseRecord(kind: .tempBasal, startDate: segStart,
                                                            endDate: segStart.addingTimeInterval(300),
                                                            unitsPerHour: rate),
                                     loggedAt: segStart))
        }
        let whole = [LoanEvent(id: UUID(), seq: 1, provenance: .confirmed,
                               record: LoanDoseRecord(kind: .tempBasal, startDate: start,
                                                      endDate: start.addingTimeInterval(3000),
                                                      unitsPerHour: rate),
                               loggedAt: start)]

        let end = start.addingTimeInterval(3000)
        let choppedTotal = LoanReconciler.expectedInsulin(events: chopped, schedule: nil, from: start, to: end)
        let wholeTotal = LoanReconciler.expectedInsulin(events: whole, schedule: nil, from: start, to: end)

        // 1.15 U/hr → a pulse every 156.5 s. Ten 300 s segments each fire once (10 × 0.05 = 0.50 U);
        // one continuous 3000 s segment fires floor(3000/156.5) = 19 times (0.95 U). The chopping
        // costs 9 pulses — and that is the whole point: the loss is per-replacement, so it grows
        // with loan length rather than staying within any fixed tolerance.
        XCTAssertLessThan(choppedTotal, wholeTotal,
                          "replacing the temp every 5 min delivers strictly less than leaving it alone")
        XCTAssertEqual(wholeTotal - choppedTotal, 0.45, accuracy: 0.0001,
                       "10 replacements lose 9 more pulses than 1 continuous segment does")
    }

    /// Recursively remove `key` wherever it appears; returns whether anything was removed.
    /// The offer's nesting inside the envelope is an encoding detail this test should not pin.
    private static func stripKey(_ key: String, from json: inout [String: Any]) -> Bool {
        var removed = false
        if json.removeValue(forKey: key) != nil { removed = true }
        for (k, v) in json {
            if var child = v as? [String: Any] {
                if stripKey(key, from: &child) { json[k] = child; removed = true }
            }
        }
        return removed
    }

    // MARK: - Allocation fixtures

    private let loanStart = Date(timeIntervalSinceReferenceDate: 700_000_000)
    private var loanEnd: Date { loanStart.addingTimeInterval(7200) }  // 2 h loan

    private var flatSchedule: BasalRateSchedule {
        BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)], timeZone: TimeZone(identifier: "GMT")!)!
    }

    private func bolusEvent(seq: Int, units: Double, provenance: EventProvenance, at offset: TimeInterval) -> LoanEvent {
        LoanEvent(id: UUID(), seq: seq, provenance: provenance,
                  record: LoanDoseRecord(kind: .bolus, startDate: loanStart.addingTimeInterval(offset), amount: units),
                  loggedAt: loanStart.addingTimeInterval(offset))
    }

    private func reconcile(events: [LoanEvent]) -> LoanReconciler.Outcome {
        LoanReconciler.reconcile(LoanReconciler.Input(
            events: events,
            schedule: flatSchedule, loanStart: loanStart, loanEnd: loanEnd))
    }

    // MARK: - Allocation properties

    /// A confirmed event can NEVER be reduced — same arithmetic, confirmed tag.
    func testConfirmedEventsAreNeverAnnulled() {
        let confirmed = bolusEvent(seq: 1, units: 1.0, provenance: .confirmed, at: 600)
        let outcome = reconcile(events: [confirmed])
        // The record is entered IN FULL (max-exposure: never truncate downward).
        XCTAssertEqual(outcome.doses.count, 1)
        XCTAssertEqual(outcome.doses[0].programmedUnits, 1.0)
    }

    // MARK: - Expected-insulin math (journal supersedes schedule, schedule fills gaps)

    func testExpectedInsulinJournalOverridesSchedule() {
        // 2 h window, flat 1.0 U/hr schedule, journaled 2.0 U/hr temp for the 1st hour:
        // expected = 2.0 (temp hour) + 1.0 (schedule hour) = 3.0.
        let temp = LoanEvent(id: UUID(), seq: 1, provenance: .confirmed,
                             record: LoanDoseRecord(kind: .tempBasal, startDate: loanStart,
                                                    endDate: loanStart.addingTimeInterval(3600), unitsPerHour: 2.0),
                             loggedAt: loanStart)
        let expected = LoanReconciler.expectedInsulin(events: [temp], schedule: flatSchedule, from: loanStart, to: loanEnd)
        XCTAssertEqual(expected, 3.0, accuracy: 0.01)
    }

    func testExpectedInsulinSuspendCountsAsZero() {
        // Suspend = rate-0 temp for hour 1: expected = 0 + 1.0 = 1.0.
        let suspend = LoanEvent(id: UUID(), seq: 1, provenance: .confirmed,
                                record: LoanDoseRecord(kind: .suspend, startDate: loanStart,
                                                       endDate: loanStart.addingTimeInterval(3600), unitsPerHour: 0),
                                loggedAt: loanStart)
        let expected = LoanReconciler.expectedInsulin(events: [suspend], schedule: flatSchedule, from: loanStart, to: loanEnd)
        XCTAssertEqual(expected, 1.0, accuracy: 0.01)
    }

    // MARK: - Pump-event reroute
    // The reconciler no longer truncates overlaps — routing through DoseStore.addPumpEvents
    // runs stock InsulinMath.reconciled() at the store, which collapses them. The reconciler
    // now only finalizes/clamps for a final hand-back and WITHHOLDS the interim open temp
    // (written on the final drain). See docs/DESIGN_LOAN_ADDPUMPEVENTS.md.

    private func temps(count: Int, spacingSeconds: Double = 300, windowSeconds: Double = 1800,
                       rate: Double = 2.0) -> [LoanEvent] {
        (0..<count).map { i in
            let start = loanStart.addingTimeInterval(Double(i) * spacingSeconds)
            return LoanEvent(id: UUID(), seq: i + 1, provenance: .confirmed,
                             record: LoanDoseRecord(kind: .tempBasal, startDate: start,
                                                    endDate: start.addingTimeInterval(windowSeconds), unitsPerHour: rate),
                             loggedAt: start)
        }
    }

    /// Final hand-back: every dose is finalized — immutable and clamped to loanEnd, so a
    /// full-window trailing temp isn't deferred by addPumpEvents' save filter. Overlap
    /// truncation is intentionally NOT done here (stock reconciled() collapses them at the
    /// store), so the doses may still overlap.
    func testFinalHandbackFinalizesAndClampsToLoanEnd() {
        let events = temps(count: 3)  // 30-min windows, 5 min apart
        let loanEnd = loanStart.addingTimeInterval(1500)  // 25 min: every window overruns it
        let outcome = LoanReconciler.reconcile(LoanReconciler.Input(
            events: events, schedule: flatSchedule,
            loanStart: loanStart, loanEnd: loanEnd))

        XCTAssertNil(outcome.openEventID, "nothing is open on a final hand-back")
        XCTAssertEqual(outcome.doses.count, 3)
        for dose in outcome.doses {
            XCTAssertFalse(dose.isMutable, "final-hand-back doses are finalized")
            XCTAssertEqual(dose.endDate, loanEnd, "each 30-min window overruns loanEnd, so all clamp to it (not deferred)")
        }
    }

    /// Interim drain: the still-open trailing temp is reported via openEventID and
    /// WITHHELD from the write (it re-drains and is written on the final drain). The
    /// controller still acks its seq so the watch can finalize; keeping it out of the write
    /// and committedIDs is what lets it re-drain. The superseded temps are written immutable
    /// for stock reconciled() to collapse.
    func testInterimDrainWithholdsOpenTempFromWrite() {
        let events = temps(count: 3)
        // Drain 12 min in — all three 30-min windows still extend past it; temp[2] is open.
        let outcome = LoanReconciler.reconcile(LoanReconciler.Input(
            events: events, schedule: flatSchedule,
            loanStart: loanStart, loanEnd: loanStart.addingTimeInterval(720),
            isFinalHandback: false))

        XCTAssertEqual(outcome.openEventID, events[2].id, "the latest-starting still-running temp is open")
        // The open temp is NOT written; the two superseded temps are, immutable & uncapped.
        XCTAssertEqual(outcome.doses.count, 2)
        XCTAssertFalse(outcome.doses.contains { $0.isMutable }, "no mutable loan doses")
        let openSyncID = LoanReconciler.syncIdentifier(for: events[2])
        XCTAssertFalse(outcome.doses.contains { $0.syncIdentifier == openSyncID }, "open temp withheld from write")
        XCTAssertTrue(outcome.doses.contains { $0.syncIdentifier == LoanReconciler.syncIdentifier(for: events[0]) })
    }

    /// A single completed temp on a final hand-back keeps its (sub-loanEnd) window intact.
    func testSingleCompletedTempKeepsWindow() {
        let event = temps(count: 1)[0]  // [0, 1800]
        let outcome = LoanReconciler.reconcile(LoanReconciler.Input(
            events: [event], schedule: flatSchedule,
            loanStart: loanStart, loanEnd: loanStart.addingTimeInterval(3600)))  // loanEnd well past the window
        XCTAssertEqual(outcome.doses.count, 1)
        XCTAssertFalse(outcome.doses[0].isMutable)
        XCTAssertEqual(outcome.doses[0].programmedUnits, 1.0, accuracy: 0.01)  // 2.0 × 0.5h, unclamped
    }

    // MARK: - LoanSeedIdentity (double-hex fix)

    /// The seed's raw must round-trip the phone's hex syncIdentifier back to the ORIGINAL bytes,
    /// so the watch row's derived syncIdentifier (hex of raw) equals the phone's — one identity
    /// end-to-end, and the pod's deterministic re-reports collide instead of duplicating.
    func testLoanSeedIdentityRawRoundTripAndFallbacks() {
        let podRaw = Data("tempBasal 2.35 2026-07-28T21:38:02Z".utf8)   // OmniBLE uniqueKey shape
        let phoneSyncId = podRaw.map { String(format: "%02hhx", $0) }.joined()

        XCTAssertEqual(LoanSeedIdentity.raw(forSyncIdentifier: phoneSyncId), podRaw, "hex decodes to original bytes")
        XCTAssertEqual(LoanSeedIdentity.raw(forSyncIdentifier: phoneSyncId.uppercased()), podRaw, "case-insensitive")

        // Identity stability: hex(decoded) == the phone's syncId → the watch stores the SAME syncIdentifier.
        let watchSyncId = LoanSeedIdentity.raw(forSyncIdentifier: phoneSyncId).map { String(format: "%02hhx", $0) }.joined()
        XCTAssertEqual(watchSyncId, phoneSyncId)

        // Non-hex identifiers keep the utf8 encoding (old-phone epoch-keyed fallback, UUID-style ids).
        let epochKeyed = "loanv2-grant-47-0"
        XCTAssertEqual(LoanSeedIdentity.raw(forSyncIdentifier: epochKeyed), Data(epochKeyed.utf8))
        XCTAssertEqual(LoanSeedIdentity.raw(forSyncIdentifier: "abc"), Data("abc".utf8), "odd length is not hex")
        XCTAssertEqual(LoanSeedIdentity.raw(forSyncIdentifier: ""), Data(), "empty stays empty via fallback")
    }

    // MARK: - The seed carries finished history only; live doses belong to the pod

    func testSeedDoseEntriesSplitsLiveFromFinished() {
        let now = Date()
        let finishedBolus = LoanDoseRecord(kind: .bolus, startDate: now.addingTimeInterval(-1800),
                                           endDate: now.addingTimeInterval(-1754), amount: 2.0)
        let finishedTemp = LoanDoseRecord(kind: .tempBasal, startDate: now.addingTimeInterval(-3600),
                                          endDate: now.addingTimeInterval(-1800), unitsPerHour: 2.0)
        let runningTemp = LoanDoseRecord(kind: .tempBasal, startDate: now.addingTimeInterval(-600),
                                         endDate: now.addingTimeInterval(1200), unitsPerHour: 2.0)
        let grant = LoanGrant(epoch: 9, expiresAt: now.addingTimeInterval(60), pumpManagerRawState: Data(),
                              podAddress: 0x1F0F, therapySettingsRaw: Data(), settingsTimeZoneID: "UTC",
                              doseHistory: [finishedBolus, finishedTemp, runningTemp])

        let (seed, live) = grant.seedDoseEntries(finishedBy: now)
        XCTAssertEqual(seed.count, 2, "finished bolus + finished temp are seedable history")
        XCTAssertEqual(live.count, 1, "the running temp is live — pod state owns it, never seeded")
        XCTAssertEqual(live.first?.unitsPerHour, 2.0)
        XCTAssertTrue(live.first!.endDate > now)
        XCTAssertFalse(seed.contains { $0.endDate > now }, "nothing still-delivering may enter the seed")
        // The split is a partition of the unfiltered seed set.
        XCTAssertEqual(seed.count + live.count, grant.seedDoseEntries().count)
    }

    // MARK: - Channel classification

    /// `.takeoverComplete` MUST ride the immediate channel. It moved there on 2026-08-12 because
    /// the pump tile now shows "Taking over…" until it arrives — on `transferUserInfo` that label
    /// outlives the takeover by tens of seconds to minutes and reads as a hang. Measured on build
    /// 268 epoch 10: pod taken at +10.2 s, phone still in `.grantOffered` at +20 s.
    ///
    /// This test exists so that a future "tidy up the switch" cannot quietly revert the UI.
    func testTakeoverCompleteRidesTheImmediateChannel() {
        let status = LoanPodStatus(timestamp: Date(), deliveredUnits: 1, reservoirLevel: nil, isSuspended: false, faultCode: nil)
        XCTAssertTrue(LoanMessage.takeoverComplete(TakeoverComplete(epoch: 1, firstPodStatus: status)).isInteractiveHandshake,
                      "the tile's 'Taking over…' state depends on this arriving promptly")
    }

    /// The other side of the rule, so the fix cannot be over-applied: background bookkeeping stays
    /// on the guaranteed, relaunch-surviving queue that the cursor/ID machinery is built around.
    func testBackgroundBookkeepingStaysOnTheQueuedChannel() {
        XCTAssertFalse(LoanMessage.doseRecordBatch(DoseRecordBatch(epoch: 1, events: [], tombstones: [])).isInteractiveHandshake)
        XCTAssertFalse(LoanMessage.statusQuery(StatusQuery(epoch: 1)).isInteractiveHandshake)
        XCTAssertFalse(LoanMessage.diag(LoanDiag(epoch: 1, text: "x")).isInteractiveHandshake)
    }

    // MARK: - Transport kind peek

    /// The watch's queued-offer supersede cancels ONLY hand-back offers, identified by this
    /// peek. A false positive cancels a one-shot message (a record stream is not resent until
    /// the next cycle); a false negative just leaves a duplicate in the queue to be
    /// coalesced. So: exact kind for an offer, nil for everything not ours.
    func testPeekKindIdentifiesOffersAndRejectsForeignPayloads() throws {
        let offer = HandbackOffer(epoch: 3, handedBackAt: Date(), finalStatus: nil, odometer: nil,
                                  events: [], tombstones: [], recovered: false, released: false)
        let dict = try LoanMessage.handbackOffer(offer).transportDictionary()
        XCTAssertEqual(LoanMessage.peekKind(transport: dict), "handbackOffer")

        let batch = try LoanMessage.doseRecordBatch(DoseRecordBatch(epoch: 3, events: [], tombstones: [])).transportDictionary()
        XCTAssertEqual(LoanMessage.peekKind(transport: batch), "doseRecordBatch", "streams must NOT peek as offers")

        XCTAssertNil(LoanMessage.peekKind(transport: ["name": "WatchContext"]), "foreign payloads peek as nil")
        XCTAssertNil(LoanMessage.peekKind(transport: [:]))
    }
}
