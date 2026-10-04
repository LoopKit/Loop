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
import LoopAlgorithm
import LoopCore
import WatchKit
import os.log

extension PodLoanWatchController {

    /// Everything unacked. A `renewal` goes even when empty (the phone's liveness signal), and an
    /// empty one is urgent-only.
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
                                            freshenSucceeded: false, asOf: asOf)
        }
        if !empty {
            SportLog.event("handback", String(format: "stream: %d event(s), %d tombstone(s)%@", events.count, tombstones.count,
                                              odometer.map { String(format: " · odo %.2f U @ %@ [checkpoint]", $0.deliveredLatest, DateFormatter.localizedString(from: $0.asOf ?? .distantPast, dateStyle: .none, timeStyle: .medium)) } ?? ""))
        }

        sendMessage(.doseRecordBatch(DoseRecordBatch(epoch: epoch, events: events, tombstones: tombstones,
                                                     odometer: odometer, sentAt: self.now())),
                    urgentOnly: empty)
    }

    /// Once per completed cycle, including cycles that recorded nothing.
    func renewHold() {
        queue.async { self.streamRecords(renewal: true) }
    }

    /// Once per pod-native raw; the running temp is re-reported and must not be re-minted.
    func journalPumpEvents(_ events: [NewPumpEvent]) {
        guard phase == .active else { return }
        var minted = 0
        for event in events {
            guard let dose = event.dose, let record = Self.loanRecord(for: dose, raw: event.raw),
                  let identity = record.syncIdentifier, !journal.contains(syncIdentifier: identity) else { continue }
            guard let journaled = try? journal.mintEvent(record: record, provenance: .confirmed) else {
                SportLog.event("loan", "** JOURNAL MINT FAILED for \(record.kind) — the dose is in the book but will NOT follow the pod home **")
                continue
            }
            minted += 1
            let amount = record.kind == .bolus ? String(format: "%.2f U", record.amount ?? 0)
                                               : String(format: "%.2f U/hr", record.unitsPerHour ?? 0)
            SportLog.event("loan", "\(record.kind) JOURNALED from the pump manager's report — \(amount)\(dose.isMutable ? " (running)" : ""), seq \(journaled.seq)")
        }
        if minted > 0 { streamRecords() }
    }

    /// Identity is the hex of the pod-native raw. Delivered units and insulin type travel
    /// explicitly: the pod floors to whole pulses, and a rapid analogue must keep its own curve.
    private static func loanRecord(for dose: DoseEntry, raw: Data) -> LoanDoseRecord? {
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
            SportLog.event("loan", "pump report carried a \(dose.type) dose — not a wrist command; not journaled")
            return nil
        }
    }

    /// Also in the local store, so the next cycle's COB sees it. Both under the event ID, the
    /// identity the phone stores it under, so a later wrist delete matches there. `completion`
    /// gets the local store's answer.
    func loanDidRecordCarbs(_ entry: NewCarbEntry, completion: ((Swift.Result<StoredCarbEntry, Error>) -> Void)? = nil) {
        let grams = entry.quantity.doubleValue(for: .gram)
        let eventID = UUID()
        loopManager.addLoanCarbEntry(entry, syncIdentifier: eventID.uuidString, completion: completion)
        // async, never sync: ordering with the pump's reports, and main must not wait.
        queue.async {
            guard self.phase == .active else {
                SportLog.event("loan", String(format: "carb entry ignored (%.0f g) — no active loan to journal it against", grams))
                return
            }
            let record = LoanDoseRecord(kind: .carb,
                                        startDate: entry.startDate,
                                        amount: grams,
                                        absorptionTime: entry.absorptionTime)
            guard let event = try? self.journal.mintEvent(record: record, provenance: .confirmed, id: eventID) else {
                SportLog.event("loan", String(format: "** CARB JOURNAL MINT FAILED (%.0f g) — the carb is LIVE on the watch but will NOT follow the pod home **", grams))
                return
            }
            SportLog.event("loan", String(format: "carb JOURNALED %.0f g (absorption %.1f h) — seq %d, event %@",
                                          grams, (entry.absorptionTime ?? 0) / 3600, event.seq,
                                          String(event.id.uuidString.prefix(8))))
            self.streamRecords()
        }
    }

    /// Journaled, or the next grant would resurrect the carb. A wrist carb's identity is its
    /// event ID; an add and delete in one drain cancel on the phone.
    func loanDidDeleteCarb(syncIdentifier: String?, startDate: Date, grams: Double) {
        queue.async {
            guard self.phase == .active else {
                SportLog.event("loan", String(format: "carb delete ignored (%.0f g) — no active loan to journal it against", grams))
                return
            }
            let record = LoanDoseRecord(kind: .carbDeleted,
                                        startDate: startDate,
                                        amount: grams,
                                        syncIdentifier: syncIdentifier)
            guard let event = try? self.journal.mintEvent(record: record, provenance: .confirmed) else {
                SportLog.event("loan", String(format: "** CARB DELETE JOURNAL MINT FAILED (%.0f g) — gone on the watch but the phone still has it; the next grant will RESURRECT it **", grams))
                return
            }
            SportLog.event("loan", String(format: "carb DELETE journaled %.0f g @ %@ — sync %@, seq %d, event %@",
                                          grams, ISO8601DateFormatter().string(from: startDate),
                                          syncIdentifier ?? "none", event.seq,
                                          String(event.id.uuidString.prefix(8))))
            self.streamRecords()
        }
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
        queue.async {
            guard self.phase == .active else {
                SportLog.event("override", "NOT JOURNALED (\(name)) — no active loan (phase \(self.phase.rawValue)); the stock phone path owns it")
                return
            }
            guard self.phoneSupportsOverrideRecords else {
                SportLog.event("override", "NOT JOURNALED (\(name)) — this phone build predates override records; the override is LIVE on the watch but will NOT follow the pod home. Update the phone app to sync overrides.")
                return
            }
            let record = LoanDoseRecord.overrideChange(override, at: self.now(), note: name)
            guard let event = try? self.journal.mintEvent(record: record, provenance: .confirmed) else {
                SportLog.event("override", "** JOURNAL MINT FAILED for \(name) — the override is LIVE on the watch but will NOT follow the pod home **")
                return
            }
            SportLog.event("override", "JOURNALED \(name) — seq \(event.seq), event \(event.id.uuidString.prefix(8)), sync \(record.syncIdentifier ?? "—") (rides the drain to the phone)")
            self.streamRecords()
        }
    }
}
