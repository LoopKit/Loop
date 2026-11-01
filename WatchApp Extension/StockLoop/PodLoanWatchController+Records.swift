//
//  PodLoanWatchController+Records.swift
//  WatchApp Extension
//
//  Minting journal events (doses, carbs, overrides) and streaming them to the phone. The
//  journal is the protocol record; dosing reads the LoopKit stores.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import WatchKit
import os.log

extension PodLoanWatchController {

    /// Everything unacked. A `renewal` goes even when empty: it is the phone's sign the watch is there.
    func streamRecords(renewal: Bool = false) {
        guard phase == .active, let epoch = epoch else { return }
        let events = journal.unackedEvents()
        let tombstones = journal.pendingTombstones()
        let empty = events.isEmpty && tombstones.isEmpty
        guard renewal || !empty else { return }

        // The pod's last-known total rides along for a mid-loan checkpoint; no read is made for it.
        var odometer: LoanOdometerSnapshot?
        if let start = deliveredAtTakeover, let reading = pumpOdometer?.deliveredUnits {
            let latest = reading.units, asOf = reading.at
            odometer = LoanOdometerSnapshot(deliveredAtStart: start, deliveredLatest: latest,
                                            asOf: asOf, deliveredAtStartAt: persisted.deliveredAtTakeoverAt)
        }
        sendMessage(.doseRecordBatch(DoseRecordBatch(epoch: epoch, events: events, tombstones: tombstones,
                                                     odometer: odometer, sentAt: self.now(),
                                                     seizeToken: persisted.seizeToken)))
    }

    /// Once per completed cycle, including cycles that recorded nothing.
    func renewHold() {
        DispatchQueue.main.async { self.streamRecords(renewal: true) }
    }

    /// Once per pod-native raw; the running temp is re-reported and must not be re-minted.
    func journalPumpEvents(_ events: [NewPumpEvent]) {
        guard phase == .active else { return }
        let reported = events.compactMap { event in event.dose.flatMap { Self.loanRecord(for: $0, raw: event.raw) } }
        var minted = 0
        for record in Self.recordsToJournal(reported, journaled: journal.record(syncIdentifier:)) {
            guard (try? journal.mintEvent(record: record, provenance: .confirmed)) != nil else {
                SportLog.event("loan", "could not record a \(record.kind) dose for the phone")
                continue
            }
            minted += 1
            if record.kind == .tempBasal, record.endDate == record.startDate {
                SportLog.event("loan", "temp basal cancel recorded for the phone")
                continue
            }
            SportLog.event("loan", record.kind == .bolus ? String(format: "bolus %.2f U recorded for the phone", record.amount ?? 0)
                                                         : String(format: "temp basal %.2f U/hr recorded for the phone", record.unitsPerHour ?? 0))
        }
        if minted > 0 { streamRecords() }
    }

    /// What a pump report adds to the loan's records: each dose not yet journaled, and a cancel back to the
    /// schedule. The pump manager reports that cancel only by re-reporting the running temp, shortened, under
    /// its own identity; a temp change reports the same shortened temp beside the new one, which ends it anyway.
    /// So a journaled temp back with an earlier end, and no new temp in the report, is journaled as a
    /// zero-length rate record at the new end: the cancel the phone's books and audit already understand.
    static func recordsToJournal(_ reported: [LoanDoseRecord], journaled: (String) -> LoanDoseRecord?) -> [LoanDoseRecord] {
        let setsATemp = reported.contains { $0.kind == .tempBasal && $0.syncIdentifier.flatMap(journaled) == nil }
        return reported.compactMap { record in
            guard let identity = record.syncIdentifier else { return nil }
            guard let known = journaled(identity) else { return record }
            let cancelIdentity = identity + "-cancel"
            guard record.kind == .tempBasal, !setsATemp, let end = record.endDate, let knownEnd = known.endDate,
                  end < knownEnd, journaled(cancelIdentity) == nil else { return nil }
            return LoanDoseRecord(kind: .tempBasal, startDate: end, endDate: end, unitsPerHour: 0,
                                  syncIdentifier: cancelIdentity, insulinType: record.insulinType)
        }
    }

    /// Identity is the hex of the pod-native raw. Delivered units and insulin type travel
    /// explicitly: the pod floors to whole pulses, and a rapid analogue must keep its own curve.
    static func loanRecord(for dose: DoseEntry, raw: Data) -> LoanDoseRecord? {
        let identity = raw.map { String(format: "%02x", $0) }.joined()
        switch dose.type {
        case .bolus:
            return LoanDoseRecord(kind: .bolus, startDate: dose.startDate, endDate: dose.endDate,
                                  amount: dose.programmedUnits, syncIdentifier: identity,
                                  insulinType: dose.insulinType, deliveredUnits: dose.deliveredUnits,
                                  automatic: dose.automatic, decisionId: dose.decisionId)
        case .tempBasal:
            return LoanDoseRecord(kind: .tempBasal, startDate: dose.startDate, endDate: dose.endDate,
                                  unitsPerHour: dose.unitsPerHour, syncIdentifier: identity,
                                  insulinType: dose.insulinType, deliveredUnits: dose.deliveredUnits,
                                  decisionId: dose.decisionId)
        default:
            SportLog.event("loan", "pump reported a \(dose.type) dose, which is not recorded for the phone")
            return nil
        }
    }

    /// Also in the local store, so the next cycle's COB sees it. The entry's identity is the journal
    /// event's ID, the identity the phone stores it under, so a later delete on the watch matches there.
    /// `completion` gets the local store's answer.
    func loanDidRecordCarbs(_ entry: NewCarbEntry, completion: ((Swift.Result<StoredCarbEntry, Error>) -> Void)? = nil) {
        let grams = entry.quantity.doubleValue(for: .gram)
        let eventID = UUID(uuidString: entry.syncIdentifier) ?? UUID()
        let entry = entry.syncIdentifier == eventID.uuidString ? entry : entry.withSyncIdentifier(eventID.uuidString)
        loopManager.addLoanCarbEntry(entry) { result in
            // As stock `LoopDataManager.addCarbEntry`: saved carbs end a pre-meal preset.
            if case .success = result { self.endPreMealOverride(reason: "carbs saved on the watch") }
            completion?(result)
        }
        // async, never sync: ordering with the pump's reports, and main must not wait.
        DispatchQueue.main.async {
            guard self.phase == .active else {
                SportLog.event("loan", String(format: "carb entry of %.0f g not recorded for the phone: no loan is active", grams))
                return
            }
            let record = LoanDoseRecord(kind: .carb,
                                        startDate: entry.startDate,
                                        amount: grams,
                                        absorptionTime: entry.absorptionTime,
                                        note: entry.foodType,
                                        userCreatedDate: entry.date)
            guard (try? self.journal.mintEvent(record: record, provenance: .confirmed, id: eventID)) != nil else {
                SportLog.event("loan", String(format: "could not record the %.0f g carb entry for the phone", grams))
                return
            }
            SportLog.event("loan", String(format: "carb entry of %.0f g, absorption %.1f h, recorded for the phone",
                                          grams, (entry.absorptionTime ?? 0) / 3600))
            self.streamRecords()
        }
    }

    /// Journaled, or the next grant would resurrect the carb. A wrist carb's identity is its
    /// event ID; an add and delete in one drain cancel on the phone.
    func loanDidDeleteCarb(syncIdentifier: String?, startDate: Date, grams: Double) {
        DispatchQueue.main.async {
            guard self.phase == .active else {
                SportLog.event("loan", String(format: "carb deletion of %.0f g not recorded for the phone: no loan is active", grams))
                return
            }
            let record = LoanDoseRecord(kind: .carbDeleted,
                                        startDate: startDate,
                                        amount: grams,
                                        syncIdentifier: syncIdentifier)
            guard (try? self.journal.mintEvent(record: record, provenance: .confirmed)) != nil else {
                SportLog.event("loan", String(format: "could not record the deletion of %.0f g for the phone; the next grant would bring it back", grams))
                return
            }
            SportLog.event("loan", String(format: "carb deletion of %.0f g recorded for the phone", grams))
            self.streamRecords()
        }
    }

    /// Stock `TemporaryPresetsManager.endPreMealOverride`, where stock calls it: after a carb entry
    /// is saved and when the loop is opened. Through the wrist's override path, so the journal
    /// carries it to the phone; the screens show the loop's override, so they follow.
    func endPreMealOverride(reason: String) {
        guard let active = loopManager.scheduleOverride, active.isActive(at: now()), active.context == .preMeal else { return }
        SportLog.event("override", "ending the pre-meal override: \(reason)")
        applyWristOverride(nil)
    }

    /// A wrist override: the loan's dosing first, then the journal, which carries it to the phone.
    func applyWristOverride(_ override: TemporaryScheduleOverride?) {
        loopManager.applyWristOverride(override)
        loanDidRecordOverride(override)
    }

    /// Journaled only when the phone understands override records; otherwise it stays local and
    /// the log says so.
    func loanDidRecordOverride(_ override: TemporaryScheduleOverride?) {
        let name = override.map { $0.context.presetNameForLog } ?? "cleared"
        DispatchQueue.main.async {
            guard self.phase == .active else {
                SportLog.event("override", "override change not recorded for the phone, as no loan is active: \(name)")
                return
            }
            let record = LoanDoseRecord.overrideChange(override, at: self.now(), note: name)
            guard (try? self.journal.mintEvent(record: record, provenance: .confirmed)) != nil else {
                SportLog.event("override", "could not record the override change for the phone: \(name)")
                return
            }
            SportLog.event("override", "override change recorded for the phone: \(name)")
            self.streamRecords()
        }
    }
}
