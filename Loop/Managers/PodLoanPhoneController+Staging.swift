//
//  PodLoanPhoneController+Staging.swift
//  Loop
//
//  Part of PodLoanPhoneController (see PodLoanPhoneController.swift). Split by concern; stored
//  properties live in the core class.
//
//  The holding area for records the watch has streamed but the phone's stores have not
//  committed yet. Everything staged is written to disk on every batch, so a phone that
//  relaunches mid-loan resumes with the records it already had rather than an empty set.
//
//  The file carries the epoch that wrote it. Records belong to exactly one loan, so a file
//  from a different epoch is ignored rather than folded into the current one.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import UserNotifications
import os.log

extension PodLoanPhoneController {
    var stagedFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("PodLoanStagedRecordsV2.json")
    }

    /// The on-disk shape. `epoch` is what makes a resumed file admissible.
    struct StagedState: Codable {
        let epoch: Int
        let events: [LoanEvent]
        let tombstones: [UUID]
    }

    /// Called on every batch, not only at hand-back: a phone that dies between receiving a
    /// batch and committing it must come back holding that batch.
    func persistStaged() {
        let snapshot = StagedState(epoch: epoch, events: Array(staged.values), tombstones: Array(stagedTombstones))
        if let data = try? LoanProtocol.encoder.encode(snapshot) {
            try? data.write(to: stagedFileURL, options: .atomic)
        }
    }

    /// Merges the persisted set back in, but only when the file was written under the epoch
    /// this phone is on now. A mismatch means the file describes a loan that has closed.
    func loadStaged() {
        guard let data = try? Data(contentsOf: stagedFileURL),
              let snapshot = try? LoanProtocol.decoder.decode(StagedState.self, from: data),
              snapshot.epoch == epoch else { return }
        for event in snapshot.events { staged[event.id] = event }
        stagedTombstones.formUnion(snapshot.tombstones)
    }

    /// `committedIDs` is the exactly-once record for the whole feature — dedup is by event ID,
    /// never by cursor position — so it has to survive a relaunch or a resend re-commits doses
    /// that are already in the store.
    func persistCommittedIDs() {
        UserDefaults.standard.set(committedIDs.map(\.uuidString), forKey: Keys.committedIDs)
    }
}
