//
//  LoanEventJournal.swift
//  WatchApp Extension
//
//  The watch's loan ledger: each event with a stable identity and a per-loan seq, persisted
//  before returning so a relaunch can drain it. Dosing never reads it.
//

import Foundation
import LoopCore
import os.log

final class LoanEventJournal {
    /// `ackedCursor`: how far the phone has committed.
    private struct State: Codable {
        var epoch: Int
        var nextSeq: Int
        var events: [LoanEvent]

        /// Carried and cleared with acks; nothing mints one today.
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

    /// In Application Support, outside the versioned store, so it survives a store reset.
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

    /// Outlives the controller's epoch, so a parked drain recognises its acks.
    var activeEpoch: Int? {
        lock.lock(); defer { lock.unlock() }
        return state?.epoch
    }

    /// A launch reads this to choose between idle and a parked drain.
    var hasUndrainedEvents: Bool {
        lock.lock(); defer { lock.unlock() }
        guard let s = state else { return false }
        return s.events.contains { $0.seq > s.ackedCursor } || !s.tombstones.isEmpty
    }

    /// Refuses to clobber undrained events; `adoptEpoch` is the way past.
    func begin(epoch: Int) throws {
        lock.lock(); defer { lock.unlock() }
        if let s = state, s.events.contains(where: { $0.seq > s.ackedCursor }) {
            throw LoanJournalError.undrainedPriorLoan(epoch: s.epoch)
        }
        state = .empty(epoch: epoch)
        persistLocked()
    }

    /// Only after the phone has everything, or the drain has given up.
    func end() {
        lock.lock(); defer { lock.unlock() }
        state = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Re-tags undrained events into a new epoch without re-minting; returns how many.
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

    /// Persists before returning. A failed persist logs but does not throw.
    func mintEvent(record: LoanDoseRecord, provenance: EventProvenance, at date: Date = Date(), id: UUID = UUID()) throws -> LoanEvent {
        lock.lock(); defer { lock.unlock() }
        guard var s = state else { throw LoanJournalError.noActiveLoan }
        let event = LoanEvent(id: id, seq: s.nextSeq, provenance: provenance, record: record, loggedAt: date)
        s.nextSeq += 1
        s.events.append(event)
        state = s
        persistLocked()
        return event
    }

    /// Stops the re-reported running temp from being minted twice.
    func contains(syncIdentifier: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return state?.events.contains { $0.record.syncIdentifier == syncIdentifier } ?? false
    }

    /// Above the cursor, in seq order.
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

    /// Highest seq minted, not the cursor.
    var lastEventSeq: Int {
        lock.lock(); defer { lock.unlock() }
        guard let s = state else { return 0 }
        return s.nextSeq - 1
    }

    /// Monotonic, so a replayed ack never moves the cursor back.
    func applyAck(committedCursor: Int) {
        mutate { s in
            let cursor = committedCursor
            s.ackedCursor = max(s.ackedCursor, cursor)
            s.tombstones.removeAll()
        }
    }

    /// The only mutation path: lock, apply, persist.
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
