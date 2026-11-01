//
//  WatchLoopManager+Dosing.swift
//  WatchApp Extension
//
//  The insulin book (one writer, the pump manager, plus a per-loan seed; reset every loan)
//  and what the wrist does to the pod: automatic doses, manual boluses and carb entries.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import WatchConnectivity
import os.log

extension WatchLoopManager {

    /// `syncDoseEntries` ignores entries without a `syncIdentifier`, so the seed carries the phone's.
    func seedInsulinHistory(_ entries: [DoseEntry]) async throws {
        try await doseStore.syncDoseEntries(entries)
    }

    /// Call even with no events: it advances `lastAddedPumpData`, the recency gate's clock.
    func recordPumpEvents(_ events: [NewPumpEvent], lastReconciliation: Date?, replacePendingEvents: Bool) async throws {
        try await doseStore.addPumpEvents(events, lastReconciliation: lastReconciliation, replacePendingEvents: replacePendingEvents)
    }

    /// Clears both the pump events and the seeded delivery objects, and the reconciliation date,
    /// so nothing doses until the pod has reported once.
    func resetInsulinBook(reason: String) async {
        do {
            try await doseStore.resetPumpData()
        } catch {
            SportLog.event("book", "could not clear the insulin history at \(reason): \(String(describing: error))")
        }
        await doseStore.insulinDeliveryStore.purgeCachedInsulinDeliveryObjects()
    }

    /// On the lane; the contract is `manualBolusRecommendation`. Like stock's recommendation for the
    /// watch, it also keeps the watchBolus decision built with it.
    func recommendManualBolus(potentialCarbEntry: NewCarbEntry? = nil,
                              completion: @escaping (Swift.Result<ManualBolusRecommendation?, Error>) -> Void) {
        onLane {
            let result = await self.manualBolusRecommendation(potentialCarbEntry: potentialCarbEntry)
            self.noteContextDosingDecision(potentialCarbEntry: potentialCarbEntry, recommendation: (try? result.get()) ?? nil)
            completion(result)
        }
    }

    /// The cycle's manual bolus recommendation (stock `LoopDataManager.recommendManualBolus`), with the
    /// potential carb entry as a new entry. It stores nothing: no displayed value changes. Lane work.
    func manualBolusRecommendation(potentialCarbEntry: NewCarbEntry? = nil,
                                   truncatingActiveOverride: Bool = false) async -> Swift.Result<ManualBolusRecommendation?, Error> {
        do {
            return .success(try await cycle.recommendManualBolus(carbEntryChange: potentialCarbEntry.map { .add($0) },
                                                                 truncatingActiveOverride: truncatingActiveOverride))
        } catch {
            return .failure(error)
        }
    }

    /// The input of the recommendation, up to the run (separate so the suite can read it).
    func manualBolusInput(potentialCarbEntry: NewCarbEntry? = nil,
                          truncatingActiveOverride: Bool = false) async throws -> StoredDataAlgorithmInput {
        try await cycle.manualBolusInput(carbEntryChange: potentialCarbEntry.map { .add($0) },
                                         truncatingActiveOverride: truncatingActiveOverride)
    }

    /// Stock's `LoopDataManager.usePositiveMomentumAndRCForManualBoluses`. Stock's app never
    /// passes `FeatureFlags.usePositiveMomentumAndRCForManualBoluses` to it, so the init default
    /// (`true`) is what the phone runs; the watch matches that.
    var usePositiveMomentumAndRCForManualBoluses: Bool { true }

    /// Stock `DeviceDataManager.enactBolus`, straight to the pump manager; as stock, the picker
    /// caps the amount. As stock's watch bolus, the watchBolus decision is stored first, with the
    /// carb entry as stored, and its id goes with the command.
    func enactManualBolus(units: Double, activationType: BolusActivationType, carbEntry: NewCarbEntry? = nil,
                          storedCarbEntry: StoredCarbEntry? = nil, completion: @escaping (Error?) -> Void) {
        onLane {
            let decisionId = await self.storeWatchBolusDosingDecision(carbEntry: carbEntry, storedCarbEntry: storedCarbEntry, requested: units)

            guard let pumpManager = self.pumpManager else {
                completion(LoopError.configurationError(.pumpManager))
                return
            }
            let rounded = pumpManager.roundToSupportedBolusVolume(units: units)

            self.setManualBolusInFlight(true, units: rounded)

            // A labelled copy of stock `DeviceDataManager.enactBolus`: a manual bolus first
            // cancels an automatic bolus in progress.
            var automaticBolusOngoing = false
            if case .inProgress(let dose) = pumpManager.status.bolusState, dose.automatic == true {
                automaticBolusOngoing = true
            }

            if automaticBolusOngoing && activationType != .automatic {
                SportLog.event("loan", "cancelling the automatic bolus in progress before the manual bolus")
                await self.cancelBolusCommand(pumpManager)
            }

            SportLog.event("loan", String(format: "enacting manual bolus %.2f U", rounded))
            // The driver answers on its own queue.
            self.enactBolusCommand(pumpManager, decisionId, rounded, activationType) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        SportLog.event("loan", String(format: "manual bolus %.2f U failed: %@", rounded, String(describing: error)))
                    } else {
                        // As stock, no cycle follows: the dose store's change refreshes the display.
                        SportLog.event("loan", String(format: "manual bolus %.2f U accepted by the pod", rounded))
                    }
                    self.setManualBolusInFlight(false)
                    completion(error)
                }
            }
        }
    }

    /// The local half, under the entry's own identity, which the caller journals it with. As stock, no
    /// cycle follows: the next reading runs one, and the carb store's change refreshes the display.
    func addLoanCarbEntry(_ entry: NewCarbEntry, completion: ((Swift.Result<StoredCarbEntry, Error>) -> Void)? = nil) {
        Task {
            let result: Swift.Result<StoredCarbEntry, Error>
            do {
                let stored = try await carbStore.addCarbEntry(entry)
                result = .success(stored)
            } catch {
                SportLog.event("loan", "could not save the carb entry: \(String(describing: error))")
                result = .failure(error)
            }
            completion?(result)
        }
    }

    /// Stock's delete: Loop's own entries only, as on the phone. The caller must journal the
    /// delete, or the next takeover re-seeds it.
    func deleteLoanCarbEntry(_ entry: StoredCarbEntry, completion: @escaping (Bool) -> Void) {
        // The store answers on its own queue.
        carbStore.deleteCarbEntry(entry) { result in DispatchQueue.main.async {
            switch result {
            case .success:
                completion(true)
            case .failure(let error):
                SportLog.event("loan", "could not delete the carb entry: \(String(describing: error))")
                completion(false)
            }
        } }
    }

    /// The cycle's temp cancel (stock `LoopDataManager.cancelActiveTempBasal(for:)`), then the display
    /// run forced, as stock. Lane work.
    func cancelActiveTempBasal(reason: CancelActiveTempBasalReason) async {
        do {
            guard try await cycle.cancelActiveTempBasal(for: reason) else { return }
            SportLog.event("loop", "temp basal cancelled: \(reason.rawValue)")
        } catch {
            SportLog.event("loop", "temp basal cancel failed: \(String(describing: error))")
            return
        }
        await updateDisplayStateOnLane(forceStoreRemoteRecommendation: true)
    }
}

extension NewCarbEntry {
    /// The same entry under another identity.
    func withSyncIdentifier(_ syncIdentifier: String) -> NewCarbEntry {
        NewCarbEntry(date: date, syncIdentifier: syncIdentifier, quantity: quantity, startDate: startDate,
                     foodType: foodType, absorptionTime: absorptionTime, favoriteFoodID: favoriteFoodID)
    }
}

/// The lent pod, to the loop cycle: the delivery members shared with the phone's `DeviceDataManager`
/// (`PumpManagerDeliveryDelegate`), over the pump the watch holds. The cycle runs stock's checks
/// (inoperable, suspended, manual temp) before `enact`.
extension WatchLoopManager: PumpManagerDeliveryDelegate {
    /// The watch has no pump UI layer.
    var pumpStatusHighlight: DeviceStatusHighlight? {
        nil
    }

    /// Logged before the send, so a command that never comes back still leaves a record of what was
    /// asked for.
    func send(bolus: Double?, tempBasal: TempBasalRecommendation?, decisionId: UUID?, to pumpManager: PumpManager) async throws {
        if let tempBasal {
            SportLog.event("dose", String(format: "enacting temp %.2f U/hr for %.0f min", tempBasal.unitsPerHour, tempBasal.duration / 60))
        }
        if let bolus, bolus > 0 {
            SportLog.event("dose", String(format: "enacting automatic bolus %.2f U", bolus))
        }
        do {
            try await doseEnactor.enact(decisionId: decisionId, bolus: bolus, tempBasal: tempBasal, with: pumpManager)
        } catch {
            SportLog.event("dose", "enact failed: \(String(describing: error))")
            throw error
        }
        if let tempBasal {
            SportLog.event("dose", String(format: "temp %.2f U/hr accepted by the pod", tempBasal.unitsPerHour))
        }
        if let bolus, bolus > 0 {
            SportLog.event("dose", String(format: "automatic bolus %.2f U accepted by the pod", bolus))
        }
    }

    /// Stock's `DeviceDataManager.enactBolus`, for the cycle's protocol; the watch's own bolus flow
    /// is `enactManualBolus`.
    func enactBolus(units: Double, decisionId: UUID?, activationType: BolusActivationType) async throws {
        guard let pumpManager else {
            throw LoopError.configurationError(.pumpManager)
        }
        try await pumpManager.enactBolus(decisionId: decisionId, units: units, activationType: activationType)
    }
}

