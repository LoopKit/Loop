//
//  PodLoanWatchController+Records.swift
//  WatchApp Extension
//
//  Minting the loan's journal events and streaming them to the phone.
//
//  Everything the wrist does that the phone must eventually know about — doses the pod reported,
//  carbs added or deleted, override changes — becomes one journal event with a stable identity
//  and a per-loan sequence number, then rides the next batch home. The journal is the PROTOCOL
//  record; dosing math reads the LoopKit stores and never this.
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore
import OmnipodKit
import WatchKit
import os.log

extension PodLoanWatchController {

    /// Send everything the phone has not acked yet.
    ///
    /// A `renewal` batch goes even when there is nothing to say: an empty batch is what tells the
    /// phone this watch completed a cycle, and the absence of those SEND stamps is what its
    /// silence warning counts. An empty one is sent urgent-only — it carries no records, so
    /// nothing is lost if it cannot go now, and queuing it would only delay the batches that do
    /// carry something.
    func streamRecords(renewal: Bool = false) {
        guard phase == .active, let epoch = epoch else { return }
        let events = journal.unackedEvents()
        let tombstones = journal.pendingTombstones()
        let empty = events.isEmpty && tombstones.isEmpty
        guard renewal || !empty else { return }

        // Ride the pod's delivery total along when we have one: it lets the phone checkpoint the
        // loan's insulin mid-flight instead of waiting for the hand-back. Nothing is dialled for
        // it — this is whatever the last pod session left — so it claims no freshening.
        var odometer: LoanOdometerSnapshot?
        if let start = deliveredAtTakeover, let latest = pumpManager?.podLoanInsulinDelivered,
           let asOf = pumpManager?.podLoanInsulinDeliveredAt {
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

    /// Called once per completed cycle. The phone judges the watch's silence from the send stamp
    /// on these batches, so this must keep going on cycles that recorded nothing at all.
    func renewHold() {
        queue.async { self.streamRecords(renewal: true) }
    }

    /// Journal each dose the pump manager reports, ONCE, keyed on the pod-native raw. The running
    /// temp is re-reported under the same raw on every pod session and must not be re-minted; the
    /// phone finalizes it from the pod state that comes home with the hand-back.
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

    /// The wire form of a dose. Identity is the hex of the pod-native raw bytes, because LoopKit
    /// DISCARDS an incoming `syncIdentifier` and derives identity from `raw` itself — anything
    /// else gives one physical dose two identities and defeats every dedup layer downstream.
    ///
    /// `deliveredUnits` and `insulinType` travel explicitly rather than being re-derived on the
    /// phone: the pod delivers whole pulses and a superseded temp is floored, so a phone working
    /// from programmed units over-states IOB; and fiasp or lyumjev would silently decay on the
    /// adult curve.
    private static func loanRecord(for dose: DoseEntry, raw: Data) -> LoanDoseRecord? {
        let identity = raw.map { String(format: "%02x", $0) }.joined()
        switch dose.type {
        case .bolus:
            return LoanDoseRecord(kind: .bolus, startDate: dose.startDate, endDate: dose.endDate,
                                  amount: dose.programmedUnits, syncIdentifier: identity,
                                  insulinType: dose.insulinType, deliveredUnits: dose.deliveredUnits)
        case .tempBasal:
            return LoanDoseRecord(kind: .tempBasal, startDate: dose.startDate, endDate: dose.endDate,
                                  unitsPerHour: dose.unitsPerHour, syncIdentifier: identity,
                                  insulinType: dose.insulinType, deliveredUnits: dose.deliveredUnits)
        default:
            SportLog.event("loan", "pump report carried a \(dose.type) dose — not a wrist command; not journaled")
            return nil
        }
    }

    /// Wrist-entered carbs ride the journal home. The local carb store already has this entry, so
    /// this cycle's COB sees it; the journal is the durable copy the phone commits.
    func loanDidRecordCarbs(_ entry: NewCarbEntry) {
        let grams = entry.quantity.doubleValue(for: .gram)
        // The UI-originated journal writers hop with `async`, never `sync`: ordering against the
        // pump manager's own reports on this queue is what keeps sequence numbers meaningful, and
        // a sync from the main thread is the stall this queue must never cause.
        queue.async {
            guard self.phase == .active else {
                SportLog.event("loan", String(format: "carb entry ignored (%.0f g) — no active loan to journal it against", grams))
                return
            }
            let record = LoanDoseRecord(kind: .carb,
                                        startDate: entry.startDate,
                                        amount: grams,
                                        absorptionTime: entry.absorptionTime)
            guard let event = try? self.journal.mintEvent(record: record, provenance: .confirmed) else {
                SportLog.event("loan", String(format: "** CARB JOURNAL MINT FAILED (%.0f g) — the carb is LIVE on the watch but will NOT follow the pod home **", grams))
                return
            }
            SportLog.event("loan", String(format: "carb JOURNALED %.0f g (absorption %.1f h) — seq %d, event %@",
                                          grams, (entry.absorptionTime ?? 0) / 3600, event.seq,
                                          String(event.id.uuidString.prefix(8))))
            self.streamRecords()
        }
    }

    /// A delete on the wrist must ride the journal too, never be applied locally only: every
    /// grant replaces the watch's carb store wholesale from the phone, so a delete the phone never
    /// heard about is RESURRECTED at the next takeover, still driving dosing.
    ///
    /// A carb entered on the wrist has no phone-side identity yet, so `syncIdentifier` is nil
    /// here. The phone cancels an add-and-delete pair inside one drain by their sequence order
    /// instead of matching an identity it never minted.
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
                                          syncIdentifier ?? "none(watch-entered)", event.seq,
                                          String(event.id.uuidString.prefix(8))))
            self.streamRecords()
        }
    }

    /// Override changes ride the journal for the same reason carb deletes do — the next grant
    /// would otherwise undo them — but only when the phone advertised that it understands the
    /// record. Without that capability the override stays LIVE on the wrist and the log says so:
    /// a record the phone's decoder cannot read would throw and strand the loan, which mid-
    /// exercise is worse than an override that does not follow the pod home.
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
