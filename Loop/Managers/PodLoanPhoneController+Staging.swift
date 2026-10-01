//
//  PodLoanPhoneController+Staging.swift
//  Loop
//
//  Records the watch has streamed but the phone has not committed, kept on disk under the
//  epoch that wrote them.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import UserNotifications
import os.log

extension PodLoanPhoneController {
    var stagedFileURL: URL {
        let base = deps.stateDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("PodLoanStagedRecordsV2.json")
    }

    /// The on-disk shape. `epoch` is what makes a resumed file admissible.
    struct StagedState: Codable {
        let epoch: Int
        let events: [LoanEvent]
        let tombstones: [UUID]
    }

    /// Every batch, so a relaunch mid-loan keeps what it had received.
    func persistStaged() {
        let snapshot = StagedState(epoch: epoch, events: Array(staged.values), tombstones: Array(stagedTombstones))
        if let data = try? LoanProtocol.encoder.encode(snapshot) {
            try? data.write(to: stagedFileURL, options: .atomic)
        }
    }

    /// Restores the staged set only if it was written under the current epoch.
    func loadStaged() {
        guard let data = try? Data(contentsOf: stagedFileURL),
              let snapshot = try? LoanProtocol.decoder.decode(StagedState.self, from: data),
              snapshot.epoch == epoch else { return }
        for event in snapshot.events { staged[event.id] = event }
        stagedTombstones.formUnion(snapshot.tombstones)
    }
}
