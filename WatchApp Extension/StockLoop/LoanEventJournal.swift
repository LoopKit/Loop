//
//  LoanEventJournal.swift
//  WatchApp Extension
//
//  The watch-side protocol ledger for loan v2 (docs/DESIGN_LOAN_PROTOCOL_V2.md §1.2/§1.3,
//  §10). This is the PROTOCOL record, not a dose world: dosing math reads only the
//  LoopKit DoseStore; the journal exists so every journal-worthy occurrence can travel
//  to the phone with a stable identity (minted at INTENT time, before pod transmission),
//  a monotonic per-loan seq for cursor acks, and a provenance tag (R6 layer 2).
//
//  Durability: every mutation persists to disk BEFORE returning (journal-loss-proof,
//  P4 / the crude build's 0.85 U loss lesson). Relaunch loads the persisted state so
//  the recovered hand-back can drain it (spec §3.2 RELAUNCH).
//

import Foundation
import LoopCore
import os.log

final class LoanEventJournal {
    /// One loan's ledger. `nextSeq` is per-loan and monotonic, and `ackedCursor` is how far the
    /// phone has told us it committed — everything above it is still owed.
    private struct State: Codable {
        var epoch: Int
        var nextSeq: Int
        var events: [LoanEvent]

        /// Retractions the phone must be told about. Nothing on the watch mints one today — a
        /// wrist delete travels as a `.carbDeleted` RECORD, which keeps its own seq — but they
        /// are carried in every batch and cleared with the acks so the wire stays honest.
        var tombstones: [UUID]

        var ackedCursor: Int

        static func empty(epoch: Int) -> State {
            State(epoch: epoch, nextSeq: 1, events: [], tombstones: [], ackedCursor: 0)
        }
    }

    private let log = OSLog(subsystem: "com.loopkit.Loop", category: "LoanEventJournal")
    private let lock = NSLock()
    private var state: State?
    private let fileURL: URL

    /// Loads whatever a previous run left behind. The file lives in Application Support,
    /// deliberately outside the versioned Core Data store directory: it is the one piece of loan
    /// state that must survive a store reset.
    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.fileURL = base.appendingPathComponent("PodLoanJournalV2.json")
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? LoanProtocol.decoder.decode(State.self, from: data) {
            self.state = loaded
            os_log("Loaded persisted loan journal: epoch %d, %d events, cursor %d",
                   log: log, type: .default, loaded.epoch, loaded.events.count, loaded.ackedCursor)
        }
    }

    /// The epoch this ledger belongs to, which outlives the controller's own `epoch` — a parked
    /// drain has cleared that but still needs to recognise its acks.
    var activeEpoch: Int? {
        lock.lock(); defer { lock.unlock() }
        return state?.epoch
    }

    /// Whether anything is still owed to the phone. This is what a launch reads to choose
    /// between a clean idle and a parked drain.
    var hasUndrainedEvents: Bool {
        lock.lock(); defer { lock.unlock() }
        guard let s = state else { return false }
        return s.events.contains { $0.seq > s.ackedCursor } || !s.tombstones.isEmpty
    }

    /// Start a loan's ledger. Refuses to clobber a prior loan that still has undrained events —
    /// those are doses and carbs the phone has never seen. `adoptEpoch` is the only sanctioned
    /// way past this.
    func begin(epoch: Int) throws {
        lock.lock(); defer { lock.unlock() }
        if let s = state, s.events.contains(where: { $0.seq > s.ackedCursor }) {
            throw LoanJournalError.undrainedPriorLoan(epoch: s.epoch)
        }
        state = .empty(epoch: epoch)
        persistLocked()
    }

    /// Close the ledger and delete the file. Only ever reached once the phone has acked
    /// everything, or once the drain has given up and the phone demonstrably owns the records.
    func end() {
        lock.lock(); defer { lock.unlock() }
        state = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Re-tag this ledger into a new epoch, carrying its undrained events and its cursor, and
    /// return how many events were carried.
    ///
    /// A fold RE-TAGS; it never re-mints. Identity is what makes every layer downstream
    /// idempotent, so a stale queued offer for the old epoch books the same ids and the phone's
    /// store dedupes them. Keeping the seq run unbroken is what keeps the phone's contiguous
    /// cursor arithmetic working.
    @discardableResult
    func adoptEpoch(_ newEpoch: Int) -> Int {
        lock.lock(); defer { lock.unlock() }
        guard var s = state else {
            state = .empty(epoch: newEpoch)
            persistLocked()
            return 0
        }
        let carried = s.events.filter { $0.seq > s.ackedCursor }.count + s.tombstones.count
        s.epoch = newEpoch
        state = s
        persistLocked()
        os_log("Journal FOLDED into epoch %d — %d undrained event(s) carried, cursor %d kept",
               log: log, type: .default, newEpoch, carried, s.ackedCursor)
        return carried
    }

    /// Mint an event and persist it BEFORE returning. Minting throws only when there is no
    /// active loan; a failed persist is loud but does not throw — refusing to dose because the
    /// ledger could not be written would be the worse failure, and only the crash-recovery
    /// guarantee degrades.
    func mintEvent(record: LoanDoseRecord, provenance: EventProvenance, at date: Date = Date()) throws -> LoanEvent {
        lock.lock(); defer { lock.unlock() }
        guard var s = state else { throw LoanJournalError.noActiveLoan }
        let event = LoanEvent(id: UUID(), seq: s.nextSeq, provenance: provenance, record: record, loggedAt: date)
        s.nextSeq += 1
        s.events.append(event)
        state = s
        persistLocked()
        return event
    }

    /// Whether this identity has already been journalled in this loan. The running temp is
    /// re-reported under the same pod-native raw on every pod session, and this is what stops a
    /// second event being minted for it.
    func contains(syncIdentifier: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return state?.events.contains { $0.record.syncIdentifier == syncIdentifier } ?? false
    }

    /// Everything above the committed cursor, in seq order — the payload of every batch and
    /// every hand-back offer.
    func unackedEvents() -> [LoanEvent] {
        lock.lock(); defer { lock.unlock() }
        guard let s = state else { return [] }
        return s.events.filter { $0.seq > s.ackedCursor }.sorted { $0.seq < $1.seq }
    }

    /// Retractions owed to the phone. Cleared wholesale by the next ack, never individually.
    func pendingTombstones() -> [UUID] {
        lock.lock(); defer { lock.unlock() }
        return state?.tombstones ?? []
    }

    /// The highest seq minted, for status reports. Not the cursor: this says what exists, the
    /// cursor says what the phone has.
    var lastEventSeq: Int {
        lock.lock(); defer { lock.unlock() }
        guard let s = state else { return 0 }
        return s.nextSeq - 1
    }

    /// Monotonic by construction: a stale or replayed ack can never move the cursor backwards,
    /// so a redelivery cannot un-commit records the phone already holds.
    func applyAck(committedCursor: Int) {
        mutate { s in
            let cursor = committedCursor
            s.ackedCursor = max(s.ackedCursor, cursor)
            s.tombstones.removeAll()
        }
    }

    /// The one mutation path: take the lock, apply, persist. Nothing may write `state` without
    /// persisting in the same breath, or a crash could leave the file describing a past ledger.
    private func mutate(_ body: (inout State) -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard var s = state else { return }
        body(&s)
        state = s
        persistLocked()
    }

    /// Atomic write on every mutation, so a crash mid-write cannot leave a corrupt ledger.
    private func persistLocked() {
        guard let s = state else { return }
        do {
            let data = try LoanProtocol.encoder.encode(s)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            os_log("Loan journal persist FAILED: %{public}@", log: log, type: .fault, String(describing: error))
        }
    }
}

enum LoanJournalError: Error {
    case noActiveLoan
    case undrainedPriorLoan(epoch: Int)
}
