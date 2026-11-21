//
//  RemoteCommandGuardTests.swift
//  LoopTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit

@testable import Loop

class RemoteCommandGuardTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var sentAt: Date { now.addingTimeInterval(.minutes(-5)) }

    private func treatment(_ syncIdentifier: String?, minutesAgo: Double, amount: Double) -> RemoteCommandGuard.Treatment {
        RemoteCommandGuard.Treatment(syncIdentifier: syncIdentifier, date: now.addingTimeInterval(.minutes(-minutesAgo)), amount: amount)
    }

    /// `known` were seen by the sender; `uploaded` adds treatments uploaded after the marker, whose time is `markerDate` or the send time
    private func commandGuard(known: Set<String>?, uploaded: Set<String> = [], recordedSince: Date? = nil, sentAt: Date? = nil, markerDate: Date? = nil) -> RemoteCommandGuard {
        let sentAt = sentAt ?? self.sentAt
        let knownTreatments = known.map {
            RemoteCommandContext.KnownTreatments(
                syncIdentifiers: $0,
                uploadedSyncIdentifiers: $0.union(uploaded),
                recordedSince: recordedSince ?? now.addingTimeInterval(.hours(-24)),
                markerDate: markerDate ?? sentAt
            )
        }
        return RemoteCommandGuard(context: RemoteCommandContext(sentAt: sentAt, knownTreatments: knownTreatments), now: now)
    }

    // MARK: Bolus

    func testBolus_UnknownInsulinBelowFraction_Accepted() {
        let boluses = [
            treatment("known", minutesAgo: 30, amount: 3),
            treatment("unknown", minutesAgo: 20, amount: 0.3)
        ]
        XCTAssertNoThrow(try commandGuard(known: ["known"], uploaded: ["unknown"]).checkBolus(amountInUnits: 2, boluses: boluses))
    }

    func testBolus_UnknownInsulinAtFraction_Rejected() {
        let boluses = [treatment("unknown", minutesAgo: 20, amount: 0.4)]
        XCTAssertThrowsError(try commandGuard(known: [], uploaded: ["unknown"]).checkBolus(amountInUnits: 2, boluses: boluses)) { error in
            XCTAssertEqual(error as? RemoteCommandGuardError, .unknownInsulin(units: 0.4))
        }
    }

    func testBolus_ThresholdWithoutFloatingPointError_Rejected() {
        // 3 * 0.2 is 0.6000000000000001 in binary floating point
        let boluses = [treatment("unknown", minutesAgo: 20, amount: 0.6)]
        XCTAssertThrowsError(try commandGuard(known: [], uploaded: ["unknown"]).checkBolus(amountInUnits: 3, boluses: boluses))
    }

    func testBolus_UnknownInsulinSummedAboveFraction_Rejected() {
        let boluses = [
            treatment("smb1", minutesAgo: 15, amount: 0.2),
            treatment("smb2", minutesAgo: 10, amount: 0.25),
            treatment("known", minutesAgo: 60, amount: 4)
        ]
        XCTAssertThrowsError(try commandGuard(known: ["known"], uploaded: ["smb1", "smb2"]).checkBolus(amountInUnits: 2, boluses: boluses))
    }

    func testBolus_InProgressBolusCountsProgrammedUnits() {
        let inProgress = DoseEntry(type: .bolus, startDate: now.addingTimeInterval(.minutes(-1)), value: 2, unit: .units, deliveredUnits: nil, syncIdentifier: "in-progress", isMutable: true)
        let candidate = RemoteCommandGuard.Treatment(bolus: inProgress)
        XCTAssertEqual(candidate.amount, 2)
        XCTAssertThrowsError(try commandGuard(known: nil).checkBolus(amountInUnits: 2, boluses: [candidate]))
    }

    func testBolus_FinalizedBolusCountsDeliveredUnits() {
        let interrupted = DoseEntry(type: .bolus, startDate: now.addingTimeInterval(.minutes(-30)), value: 2, unit: .units, deliveredUnits: 0.5, syncIdentifier: "interrupted")
        XCTAssertEqual(RemoteCommandGuard.Treatment(bolus: interrupted).amount, 0.5)
    }

    func testBolusCandidates_IncludePumpBolusInProgressOnce() {
        let history = [DoseEntry(type: .bolus, startDate: now.addingTimeInterval(.minutes(-60)), value: 1, unit: .units, deliveredUnits: 1, syncIdentifier: "old")]
        let inProgress = DoseEntry(type: .bolus, startDate: now.addingTimeInterval(.minutes(-1)), value: 2, unit: .units, syncIdentifier: "pump", isMutable: true)

        XCTAssertEqual(RemoteCommandGuard.bolusCandidates(history: history, inProgress: inProgress).count, 2)
        XCTAssertEqual(RemoteCommandGuard.bolusCandidates(history: history + [inProgress], inProgress: inProgress).count, 2)
    }

    func testBolusCandidates_InProgressWithOtherIdentifierCountedOnce() {
        // MockPumpManager reports its bolus in progress without a syncIdentifier; the stored entry has one
        let startDate = now.addingTimeInterval(.minutes(-1))
        let stored = DoseEntry(type: .bolus, startDate: startDate, value: 2, unit: .units, syncIdentifier: "stored", isMutable: true)
        let unidentified = DoseEntry(type: .bolus, startDate: startDate.addingTimeInterval(1), value: 2, unit: .units, isMutable: true)
        let otherIdentifier = DoseEntry(type: .bolus, startDate: startDate, value: 2, unit: .units, syncIdentifier: "pump", isMutable: true)
        let otherBolus = DoseEntry(type: .bolus, startDate: startDate.addingTimeInterval(1), value: 1, unit: .units, isMutable: true)

        XCTAssertEqual(RemoteCommandGuard.bolusCandidates(history: [stored], inProgress: unidentified).count, 1)
        XCTAssertEqual(RemoteCommandGuard.bolusCandidates(history: [stored], inProgress: otherIdentifier).count, 1)
        XCTAssertEqual(RemoteCommandGuard.bolusCandidates(history: [stored], inProgress: otherBolus).count, 2)
    }

    func testIsSameBolus_ToleranceEdges() {
        let startDate = now.addingTimeInterval(.minutes(-1))
        func bolus(secondsLater: TimeInterval, units: Double, syncIdentifier: String? = nil) -> DoseEntry {
            DoseEntry(type: .bolus, startDate: startDate.addingTimeInterval(secondsLater), value: units, unit: .units, syncIdentifier: syncIdentifier, isMutable: true)
        }
        let reference = bolus(secondsLater: 0, units: 0.3)

        XCTAssertTrue(RemoteCommandGuard.isSameBolus(reference, bolus(secondsLater: 10, units: 0.3)))
        XCTAssertTrue(RemoteCommandGuard.isSameBolus(reference, bolus(secondsLater: -10, units: 0.3)))
        XCTAssertFalse(RemoteCommandGuard.isSameBolus(reference, bolus(secondsLater: 10.5, units: 0.3)))

        // 0.325 - 0.3 is slightly above 0.025 in binary floating point
        XCTAssertTrue(RemoteCommandGuard.isSameBolus(reference, bolus(secondsLater: 0, units: 0.325)))
        XCTAssertTrue(RemoteCommandGuard.isSameBolus(reference, bolus(secondsLater: 0, units: 0.275)))
        XCTAssertFalse(RemoteCommandGuard.isSameBolus(reference, bolus(secondsLater: 0, units: 0.35)))
        XCTAssertFalse(RemoteCommandGuard.isSameBolus(reference, bolus(secondsLater: 10.5, units: 0.325)))

        let identified = bolus(secondsLater: 0, units: 0.3, syncIdentifier: "same")
        XCTAssertTrue(RemoteCommandGuard.isSameBolus(identified, bolus(secondsLater: 60, units: 1, syncIdentifier: "same")))
        XCTAssertFalse(RemoteCommandGuard.isSameBolus(identified, bolus(secondsLater: 60, units: 1, syncIdentifier: "other")))
    }

    func testBolus_DatedAfterNow_Rejected() {
        // The pump clock is ahead of the phone
        let boluses = [treatment("pump-ahead", minutesAgo: -3, amount: 2)]
        XCTAssertThrowsError(try commandGuard(known: nil).checkBolus(amountInUnits: 2, boluses: boluses)) { error in
            XCTAssertEqual(error as? RemoteCommandGuardError, .unknownInsulin(units: 2))
        }
        XCTAssertThrowsError(try commandGuard(known: ["pump-ahead"]).checkBolus(amountInUnits: 2, boluses: boluses))

        let beforeSend = [treatment("before-send", minutesAgo: 10, amount: 2)]
        XCTAssertNoThrow(try commandGuard(known: nil).checkBolus(amountInUnits: 2, boluses: beforeSend))
    }

    func testBolus_BolusOlderThanLookback_Ignored() {
        let boluses = [treatment("old", minutesAgo: 6 * 60 + 1, amount: 5)]
        XCTAssertNoThrow(try commandGuard(known: []).checkBolus(amountInUnits: 1, boluses: boluses))
    }

    func testBolus_OnlyMissingNightscoutIds_NotUploadedMessage() {
        let boluses = [treatment("not-uploaded", minutesAgo: 20, amount: 1)]
        XCTAssertThrowsError(try commandGuard(known: []).checkBolus(amountInUnits: 2, boluses: boluses)) { error in
            XCTAssertEqual(error as? RemoteCommandGuardError, .insulinNotUploaded(units: 1))
        }
    }

    func testBolus_MixedReasons_UnknownInsulinMessage() {
        let boluses = [
            treatment("not-uploaded", minutesAgo: 20, amount: 0.5),
            treatment("after-marker", minutesAgo: 15, amount: 0.5)
        ]
        XCTAssertThrowsError(try commandGuard(known: [], uploaded: ["after-marker"]).checkBolus(amountInUnits: 2, boluses: boluses)) { error in
            XCTAssertEqual(error as? RemoteCommandGuardError, .unknownInsulin(units: 1))
        }
    }

    // MARK: Carbs

    func testCarbs_AllKnown_Accepted() {
        let entries = [treatment("a", minutesAgo: 90, amount: 40), treatment("b", minutesAgo: 30, amount: 10)]
        XCTAssertNoThrow(try commandGuard(known: ["a", "b"]).checkCarbs(carbEntries: entries))
    }

    func testCarbs_BackdatedEntryUploadedAfterMarker_Rejected() {
        // Dated before the send time, but its Nightscout _id is newer than the marker
        let entries = [treatment("backdated", minutesAgo: 60, amount: 20)]
        XCTAssertThrowsError(try commandGuard(known: [], uploaded: ["backdated"]).checkCarbs(carbEntries: entries)) { error in
            XCTAssertEqual(error as? RemoteCommandGuardError, .unknownCarbs(grams: [20]))
        }
    }

    func testCarbs_FutureDatedKnownEntry_Accepted() {
        let entries = [treatment("future", minutesAgo: -30, amount: 15)]
        XCTAssertNoThrow(try commandGuard(known: ["future"]).checkCarbs(carbEntries: entries))
    }

    func testCarbs_FutureDatedUnknownEntry_Rejected() {
        let entries = [treatment("future", minutesAgo: -30, amount: 15)]
        XCTAssertThrowsError(try commandGuard(known: [], uploaded: ["future"]).checkCarbs(carbEntries: entries))
    }

    func testCarbs_EntryWithoutNightscoutId_Rejected() {
        // Not uploaded, or uploaded without an _id ("NA"): not in the uploaded set
        let entries = [treatment("not-uploaded", minutesAgo: 30, amount: 10)]
        XCTAssertThrowsError(try commandGuard(known: ["other"]).checkCarbs(carbEntries: entries))
    }

    func testCarbs_EntryWithoutSyncIdentifier_RejectedWhenMarkerPresent() {
        let entries = [treatment(nil, minutesAgo: 30, amount: 10)]
        XCTAssertThrowsError(try commandGuard(known: []).checkCarbs(carbEntries: entries))
        XCTAssertNoThrow(try commandGuard(known: nil).checkCarbs(carbEntries: entries))
    }

    func testEditedCarbEntry_UpdatedAfterSend_Rejected() {
        // Dated and seen before the send time; the edit keeps its Nightscout _id
        var edited = treatment("edited", minutesAgo: 40, amount: 30)
        edited.updatedDate = now.addingTimeInterval(.minutes(-2))
        XCTAssertThrowsError(try commandGuard(known: ["edited"]).checkCarbs(carbEntries: [edited])) { error in
            XCTAssertEqual(error as? RemoteCommandGuardError, .unknownCarbs(grams: [30]))
        }
        XCTAssertThrowsError(try commandGuard(known: nil).checkCarbs(carbEntries: [edited]))

        edited.updatedDate = now.addingTimeInterval(.minutes(-10))
        XCTAssertNoThrow(try commandGuard(known: ["edited"]).checkCarbs(carbEntries: [edited]))
    }

    func testEditedCarbEntry_EditedAfterMarkerBeforeSend_Rejected() {
        let markerDate = now.addingTimeInterval(.minutes(-20))
        var edited = treatment("edited", minutesAgo: 40, amount: 30)
        edited.updatedDate = now.addingTimeInterval(.minutes(-10))
        XCTAssertThrowsError(try commandGuard(known: ["edited"], markerDate: markerDate).checkCarbs(carbEntries: [edited])) { error in
            XCTAssertEqual(error as? RemoteCommandGuardError, .unknownCarbs(grams: [30]))
        }
        // Without a marker only edits after the send time count
        XCTAssertNoThrow(try commandGuard(known: nil).checkCarbs(carbEntries: [edited]))

        edited.updatedDate = now.addingTimeInterval(.minutes(-25))
        XCTAssertNoThrow(try commandGuard(known: ["edited"], markerDate: markerDate).checkCarbs(carbEntries: [edited]))

        // A marker after the send time leaves the send time as the limit
        edited.updatedDate = now.addingTimeInterval(.minutes(-4))
        XCTAssertThrowsError(try commandGuard(known: ["edited"], markerDate: now.addingTimeInterval(.minutes(-1))).checkCarbs(carbEntries: [edited]))
    }

    func testMarkerRule_JudgesByCreationDate() {
        let recordedSince = now.addingTimeInterval(.minutes(-60))

        // Future-dated entry created before recording started, never uploaded with an _id
        var createdBefore = treatment("future", minutesAgo: -60, amount: 30)
        createdBefore.createdDate = now.addingTimeInterval(.minutes(-90))
        XCTAssertNoThrow(try commandGuard(known: [], recordedSince: recordedSince).checkCarbs(carbEntries: [createdBefore]))

        var createdAfter = createdBefore
        createdAfter.createdDate = now.addingTimeInterval(.minutes(-30))
        XCTAssertThrowsError(try commandGuard(known: [], recordedSince: recordedSince).checkCarbs(carbEntries: [createdAfter]))

        // Backdated entry created after recording started
        var backdated = treatment("backdated", minutesAgo: 90, amount: 20)
        backdated.createdDate = now.addingTimeInterval(.minutes(-30))
        XCTAssertThrowsError(try commandGuard(known: [], recordedSince: recordedSince).checkCarbs(carbEntries: [backdated]))
    }

    func testMarkerRule_SkippedForEntriesDatedBeforeRecordingStarted() {
        let entries = [treatment("before-recording", minutesAgo: 90, amount: 30)]
        let recordedSince = now.addingTimeInterval(.minutes(-60))
        XCTAssertNoThrow(try commandGuard(known: [], recordedSince: recordedSince).checkCarbs(carbEntries: entries))

        let laterEntries = [treatment("after-recording", minutesAgo: 30, amount: 30)]
        XCTAssertThrowsError(try commandGuard(known: [], recordedSince: recordedSince).checkCarbs(carbEntries: laterEntries))
    }

    // MARK: Without a marker

    func testNoMarker_SendTimeRuleOnly() {
        let carbs = [treatment("before", minutesAgo: 10, amount: 30)]
        XCTAssertNoThrow(try commandGuard(known: nil).checkCarbs(carbEntries: carbs))

        let laterCarbs = [treatment("after", minutesAgo: 2, amount: 30)]
        XCTAssertThrowsError(try commandGuard(known: nil).checkCarbs(carbEntries: laterCarbs))

        let futureCarbs = [treatment("future", minutesAgo: -30, amount: 30)]
        XCTAssertNoThrow(try commandGuard(known: nil).checkCarbs(carbEntries: futureCarbs))

        let laterBolus = [treatment("after", minutesAgo: 2, amount: 1)]
        XCTAssertThrowsError(try commandGuard(known: nil).checkBolus(amountInUnits: 2, boluses: laterBolus))
    }

    func testInvalidMarker_TreatedAsAbsent() {
        // NightscoutService passes no known treatments for an invalid marker
        let entries = [treatment("not-uploaded", minutesAgo: 30, amount: 10)]
        XCTAssertNoThrow(try commandGuard(known: nil).checkCarbs(carbEntries: entries))
    }

    func testMarkerOlderThanSendTime_EntryBetweenMarkerAndSendTime_Rejected() {
        // The sender's last fetch was before an entry that is still dated before the send time
        let entries = [
            treatment("seen", minutesAgo: 40, amount: 20),
            treatment("recorded-after-fetch", minutesAgo: 8, amount: 15)
        ]
        XCTAssertThrowsError(try commandGuard(known: ["seen"], uploaded: ["recorded-after-fetch"]).checkCarbs(carbEntries: entries)) { error in
            XCTAssertEqual(error as? RemoteCommandGuardError, .unknownCarbs(grams: [15]))
        }
    }

    func testTwoCaregivers_SecondCommandRejected() {
        // Caregiver A's 2 U bolus was delivered after caregiver B sent the same command
        let firstBolusDate = now.addingTimeInterval(.minutes(-1))
        let boluses = [RemoteCommandGuard.Treatment(syncIdentifier: "caregiver-a", date: firstBolusDate, amount: 2)]
        let guardB = commandGuard(known: ["older"], uploaded: ["caregiver-a"], sentAt: now.addingTimeInterval(.minutes(-3)))
        XCTAssertThrowsError(try guardB.checkBolus(amountInUnits: 2, boluses: boluses))

        // Caregiver B sends again after seeing the bolus in Nightscout
        let guardBAgain = commandGuard(known: ["older", "caregiver-a"], sentAt: now)
        XCTAssertNoThrow(try guardBAgain.checkBolus(amountInUnits: 2, boluses: boluses))
    }

    // MARK: Messages

    func testErrorMessages() {
        XCTAssertEqual(RemoteCommandGuardError.unknownInsulin(units: 0.4).replyText, "Command rejected: 0.4 U of insulin was delivered after the command was sent (or after the newest treatment you had seen).")
        XCTAssertEqual(RemoteCommandGuardError.unknownInsulin(units: 1.2345).replyText, "Command rejected: 1.23 U of insulin was delivered after the command was sent (or after the newest treatment you had seen).")
        XCTAssertEqual(RemoteCommandGuardError.unknownInsulin(units: 0.125).replyText, "Command rejected: 0.13 U of insulin was delivered after the command was sent (or after the newest treatment you had seen).")
        XCTAssertEqual(RemoteCommandGuardError.unknownCarbs(grams: [12.5]).replyText, "Command rejected: a carb entry of 13 g was recorded that you had not seen.")
        XCTAssertEqual(RemoteCommandGuardError.insulinNotUploaded(units: 1.5).replyText, "Command rejected: 1.5 U of insulin has not been uploaded to Nightscout yet.")
        XCTAssertEqual(RemoteCommandGuardError.unknownCarbs(grams: [20]).replyText, "Command rejected: a carb entry of 20 g was recorded that you had not seen.")
        XCTAssertEqual(RemoteCommandGuardError.unknownCarbs(grams: [20.4, 15]).replyText, "Command rejected: 2 carb entries totaling 35 g were recorded that you had not seen.")
        XCTAssertEqual(RemoteBolusDeliveryError.uncertainDelivery.replyText, "Bolus may have been delivered. Check the history before sending another bolus.")
    }

    func testFormat_RoundsHalfUpFromDecimalRepresentation() {
        XCTAssertEqual(RemoteCommandGuardError.format(1.005, scale: 2), "1.01")
        XCTAssertEqual(RemoteCommandGuardError.format(2.675, scale: 2), "2.68")
        XCTAssertEqual(RemoteCommandGuardError.format(0.1 + 0.2, scale: 2), "0.3")
        XCTAssertEqual(RemoteCommandGuardError.format(2, scale: 2), "2")
        XCTAssertEqual(RemoteCommandGuardError.format(0.004, scale: 2), "0")
        XCTAssertEqual(RemoteCommandGuardError.format(12.5, scale: 0), "13")
        XCTAssertEqual(RemoteCommandGuardError.format(1234.5, scale: 0), "1235")
        XCTAssertEqual(RemoteCommandGuardError.unknownInsulin(units: 1.005).replyText, "Command rejected: 1.01 U of insulin was delivered after the command was sent (or after the newest treatment you had seen).")
    }

    func testDescriptionMatchesReplyInDevelopmentLanguage() {
        let errors: [RemoteCommandRejection] = [
            RemoteCommandGuardError.unknownInsulin(units: 1.005),
            RemoteCommandGuardError.insulinNotUploaded(units: 1.5),
            RemoteCommandGuardError.unknownCarbs(grams: [20]),
            RemoteCommandGuardError.unknownCarbs(grams: [20.4, 15]),
            RemoteCommandGuardError.historyUnavailable,
            RemoteBolusDeliveryError.uncertainDelivery
        ]
        for error in errors {
            XCTAssertEqual(error.errorDescription, error.replyText)
        }
    }

    func testRepliesAreRejections() {
        XCTAssertTrue(RemoteCommandGuardError.unknownInsulin(units: 1) as Error is RemoteCommandRejection)
        XCTAssertTrue(RemoteBolusDeliveryError.uncertainDelivery as Error is RemoteCommandRejection)
    }
}

@MainActor
class RemoteCommandGateTests: XCTestCase {

    private final class MockTreatmentSource: RemoteCommandTreatmentSource {
        var boluses: [DoseEntry] = []
        var bolusInProgress: DoseEntry?
        var carbs: [StoredCarbEntry] = []
        var bolusIncrement: Double?

        func bolusHistory(since start: Date) async throws -> [DoseEntry] { boluses }
        func carbEntries(since start: Date) async throws -> [StoredCarbEntry] { carbs }
        func roundToSupportedBolusVolume(units: Double) -> Double {
            guard let bolusIncrement else { return units }
            return (units / bolusIncrement).rounded() * bolusIncrement
        }
    }

    private final class Counter {
        var count = 0
    }

    private var source: MockTreatmentSource!
    private var gate: RemoteCommandGate!

    override func setUp() async throws {
        source = MockTreatmentSource()
        gate = RemoteCommandGate()
        gate.treatmentSource = source
    }

    private func context(sentAt: Date) -> RemoteCommandContext {
        RemoteCommandContext(sentAt: sentAt)
    }

    func testConcurrentBoluses_SecondRejected() async throws {
        let sentAt = Date().addingTimeInterval(-60)
        let deliveries = Counter()
        let deliver: @MainActor () async throws -> Void = {
            try await Task.sleep(nanoseconds: 50_000_000)
            deliveries.count += 1
        }

        async let first: Void = gate.deliverBolus(amountInUnits: 2, context: context(sentAt: sentAt), deliver: deliver)
        async let second: Void = gate.deliverBolus(amountInUnits: 2, context: context(sentAt: sentAt), deliver: deliver)
        var errors: [Error] = []
        do { try await first } catch { errors.append(error) }
        do { try await second } catch { errors.append(error) }

        XCTAssertEqual(deliveries.count, 1)
        XCTAssertEqual(errors.compactMap { $0 as? RemoteCommandGuardError }, [.unknownInsulin(units: 2)])
    }

    func testAcceptedBolus_DroppedOnceInHistory() async throws {
        try await gate.deliverBolus(amountInUnits: 2, context: context(sentAt: Date().addingTimeInterval(-60))) {}
        XCTAssertNotNil(gate.acceptedRemoteBolus)

        source.boluses = [DoseEntry(type: .bolus, startDate: Date(), value: 2, unit: .units, deliveredUnits: 2, syncIdentifier: "remote")]
        try await gate.deliverBolus(amountInUnits: 1, context: context(sentAt: Date().addingTimeInterval(1))) {}
        XCTAssertEqual(gate.acceptedRemoteBolus?.programmedUnits, 1)
    }

    func testPumpBolusInProgress_Rejects() async throws {
        source.bolusInProgress = DoseEntry(type: .bolus, startDate: Date().addingTimeInterval(-10), value: 3, unit: .units, syncIdentifier: "pump", isMutable: true)
        var delivered = false
        do {
            try await gate.deliverBolus(amountInUnits: 2, context: context(sentAt: Date().addingTimeInterval(-60))) { delivered = true }
            XCTFail("Expected rejection")
        } catch {
            XCTAssertEqual(error as? RemoteCommandGuardError, .unknownInsulin(units: 3))
        }
        XCTAssertFalse(delivered)
    }

    func testAcceptedBolusAndInProgressBolus_CountedOnce() async throws {
        let sentAt = Date().addingTimeInterval(-60)
        try await gate.deliverBolus(amountInUnits: 1, context: context(sentAt: sentAt)) {}
        let acceptedAt = try XCTUnwrap(gate.acceptedRemoteBolus?.startDate)

        // The pump dates the bolus slightly before acceptance, stores it, and reports it in progress without a syncIdentifier
        source.boluses = [DoseEntry(type: .bolus, startDate: acceptedAt.addingTimeInterval(-2), value: 1, unit: .units, syncIdentifier: "stored", isMutable: true)]
        source.bolusInProgress = DoseEntry(type: .bolus, startDate: acceptedAt.addingTimeInterval(-2), value: 1, unit: .units, isMutable: true)

        // 1 U counted once is below 20 % of 6 U; counted twice or three times it would reject
        try await gate.deliverBolus(amountInUnits: 6, context: context(sentAt: sentAt)) {}
    }

    func testNoTreatmentSource_Rejects() async throws {
        gate.treatmentSource = nil
        var delivered = false
        do {
            try await gate.deliverCarbs(context: context(sentAt: Date())) { delivered = true }
            XCTFail("Expected rejection")
        } catch {
            XCTAssertEqual(error as? RemoteCommandGuardError, .historyUnavailable)
        }
        do {
            try await gate.deliverBolus(amountInUnits: 1, context: context(sentAt: Date())) { delivered = true }
            XCTFail("Expected rejection")
        } catch {
            XCTAssertEqual(error as? RemoteCommandGuardError, .historyUnavailable)
        }
        XCTAssertFalse(delivered)
    }

    func testFailedDelivery_NotHeldAsAccepted() async throws {
        struct DeliveryError: Error {}
        do {
            try await gate.deliverBolus(amountInUnits: 2, context: context(sentAt: Date())) { throw DeliveryError() }
        } catch {}
        XCTAssertNil(gate.acceptedRemoteBolus)
    }

    func testUncertainDelivery_HeldAsAcceptedAndReported() async throws {
        do {
            try await gate.deliverBolus(amountInUnits: 2, context: context(sentAt: Date())) { throw PumpManagerError.uncertainDelivery }
            XCTFail("Expected the delivery error")
        } catch RemoteBolusDeliveryError.uncertainDelivery {
        }
        XCTAssertEqual(gate.acceptedRemoteBolus?.programmedUnits, 2)
    }

    private final class Clock {
        var now = Date()
    }

    func testAcceptedBolus_CountedUntilRetentionExpires() async throws {
        let clock = Clock()
        gate = RemoteCommandGate(now: { clock.now })
        gate.treatmentSource = source
        let acceptedAt = clock.now
        let sentAt = acceptedAt.addingTimeInterval(-60)
        try await gate.deliverBolus(amountInUnits: 2, context: context(sentAt: sentAt)) {}

        clock.now = acceptedAt.addingTimeInterval(RemoteCommandGate.acceptedBolusRetention)
        do {
            try await gate.deliverBolus(amountInUnits: 2, context: context(sentAt: sentAt)) {}
            XCTFail("Expected rejection")
        } catch {
            XCTAssertEqual(error as? RemoteCommandGuardError, .unknownInsulin(units: 2))
        }
        XCTAssertNotNil(gate.acceptedRemoteBolus)

        clock.now = acceptedAt.addingTimeInterval(RemoteCommandGate.acceptedBolusRetention + 1)
        try await gate.deliverBolus(amountInUnits: 1, context: context(sentAt: clock.now)) {}
        XCTAssertEqual(gate.acceptedRemoteBolus?.programmedUnits, 1)
        XCTAssertEqual(gate.acceptedRemoteBolus?.startDate, clock.now)
    }

    func testAcceptedBolus_KeptWhenHistoryShowsOnlyAnUnrelatedLaterBolus() async throws {
        let clock = Clock()
        gate = RemoteCommandGate(now: { clock.now })
        gate.treatmentSource = source
        let acceptedAt = clock.now
        let sentAt = acceptedAt.addingTimeInterval(-60)
        do {
            try await gate.deliverBolus(amountInUnits: 2, context: context(sentAt: sentAt)) { throw PumpManagerError.uncertainDelivery }
        } catch RemoteBolusDeliveryError.uncertainDelivery {
        }
        XCTAssertNotNil(gate.acceptedRemoteBolus)

        // An automatic bolus after the accepted one, with a different amount
        source.boluses = [DoseEntry(type: .bolus, startDate: acceptedAt.addingTimeInterval(.minutes(3)), value: 0.3, unit: .units, deliveredUnits: 0.3, syncIdentifier: "smb", automatic: true)]
        clock.now = acceptedAt.addingTimeInterval(.minutes(5))

        do {
            try await gate.deliverBolus(amountInUnits: 2, context: context(sentAt: sentAt)) {}
            XCTFail("Expected rejection")
        } catch {
            XCTAssertEqual(error as? RemoteCommandGuardError, .unknownInsulin(units: 2.3))
        }
        XCTAssertEqual(gate.acceptedRemoteBolus?.programmedUnits, 2)
    }

    func testShows_LaterBolusWithSameUnits() {
        let acceptedAt = Date()
        let accepted = DoseEntry(type: .bolus, startDate: acceptedAt, value: 2, unit: .units, isMutable: true)
        func bolus(secondsLater: TimeInterval, units: Double) -> DoseEntry {
            DoseEntry(type: .bolus, startDate: acceptedAt.addingTimeInterval(secondsLater), value: units, unit: .units, deliveredUnits: units, syncIdentifier: "stored")
        }

        XCTAssertTrue(RemoteCommandGate.shows(bolus(secondsLater: 30, units: 2), accepted: accepted))
        XCTAssertTrue(RemoteCommandGate.shows(bolus(secondsLater: 30, units: 2.025), accepted: accepted))
        XCTAssertTrue(RemoteCommandGate.shows(bolus(secondsLater: 30, units: 1.975), accepted: accepted))
        XCTAssertFalse(RemoteCommandGate.shows(bolus(secondsLater: 30, units: 2.03), accepted: accepted))
        XCTAssertTrue(RemoteCommandGate.shows(bolus(secondsLater: -5, units: 2), accepted: accepted))
        XCTAssertTrue(RemoteCommandGate.shows(bolus(secondsLater: -10, units: 2), accepted: accepted))
        XCTAssertFalse(RemoteCommandGate.shows(bolus(secondsLater: -11, units: 2), accepted: accepted))
        XCTAssertFalse(RemoteCommandGate.shows(bolus(secondsLater: 30, units: 0.3), accepted: accepted))
        XCTAssertFalse(RemoteCommandGate.shows(bolus(secondsLater: -60, units: 2), accepted: accepted))
    }

    func testShows_IgnoresAutomaticBolus() {
        let acceptedAt = Date()
        let accepted = DoseEntry(type: .bolus, startDate: acceptedAt, value: 0.5, unit: .units, isMutable: true)
        let automatic = DoseEntry(type: .bolus, startDate: acceptedAt.addingTimeInterval(60), value: 0.5, unit: .units, deliveredUnits: 0.5, syncIdentifier: "smb", automatic: true)
        let manual = DoseEntry(type: .bolus, startDate: acceptedAt.addingTimeInterval(60), value: 0.5, unit: .units, deliveredUnits: 0.5, syncIdentifier: "manual", automatic: false)
        XCTAssertFalse(RemoteCommandGate.shows(automatic, accepted: accepted))
        XCTAssertTrue(RemoteCommandGate.shows(manual, accepted: accepted))
    }

    func testAcceptedBolus_KeptWhenOnlyAnAutomaticBolusMatches() async throws {
        let clock = Clock()
        gate = RemoteCommandGate(now: { clock.now })
        gate.treatmentSource = source
        let acceptedAt = clock.now
        let sentAt = acceptedAt.addingTimeInterval(-60)
        try await gate.deliverBolus(amountInUnits: 0.5, context: context(sentAt: sentAt)) {}

        source.boluses = [DoseEntry(type: .bolus, startDate: acceptedAt.addingTimeInterval(.minutes(3)), value: 0.5, unit: .units, deliveredUnits: 0.5, syncIdentifier: "smb", automatic: true)]
        clock.now = acceptedAt.addingTimeInterval(.minutes(5))

        // 0.5 U automatic alone is below 20 % of 4 U; with the accepted 0.5 U it is not
        do {
            try await gate.deliverBolus(amountInUnits: 4, context: context(sentAt: sentAt)) {}
            XCTFail("Expected rejection")
        } catch {
            XCTAssertEqual(error as? RemoteCommandGuardError, .unknownInsulin(units: 1))
        }
        XCTAssertEqual(gate.acceptedRemoteBolus?.programmedUnits, 0.5)
    }

    func testAcceptedBolus_DroppedWhenPumpShowsItInProgress() async throws {
        let clock = Clock()
        gate = RemoteCommandGate(now: { clock.now })
        gate.treatmentSource = source
        let acceptedAt = clock.now
        let sentAt = acceptedAt.addingTimeInterval(-60)
        try await gate.deliverBolus(amountInUnits: 2, context: context(sentAt: sentAt)) {}

        source.bolusInProgress = DoseEntry(type: .bolus, startDate: acceptedAt.addingTimeInterval(-3), value: 2.02, unit: .units, isMutable: true)
        clock.now = acceptedAt.addingTimeInterval(30)

        // 2.02 U in progress alone is below 20 % of 15 U; with the accepted 2 U it is not
        try await gate.deliverBolus(amountInUnits: 15, context: context(sentAt: sentAt)) {}
        XCTAssertEqual(gate.acceptedRemoteBolus?.programmedUnits, 15)
    }

    func testAcceptedBolus_HeldAtPumpRoundedAmount() async throws {
        source.bolusIncrement = 0.05
        try await gate.deliverBolus(amountInUnits: 1.03, context: context(sentAt: Date().addingTimeInterval(-60))) {}
        XCTAssertEqual(try XCTUnwrap(gate.acceptedRemoteBolus?.programmedUnits), 1.05, accuracy: 1e-9)

        // The pump records the rounded amount, which shows the accepted bolus
        let acceptedAt = try XCTUnwrap(gate.acceptedRemoteBolus?.startDate)
        source.boluses = [DoseEntry(type: .bolus, startDate: acceptedAt, value: 1.05, unit: .units, deliveredUnits: 1.05, syncIdentifier: "stored")]
        XCTAssertTrue(RemoteCommandGate.shows(source.boluses[0], accepted: try XCTUnwrap(gate.acceptedRemoteBolus)))
    }
}
