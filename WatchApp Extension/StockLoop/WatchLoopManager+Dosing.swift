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
import LoopAlgorithm
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
            SportLog.event("book", "reset FAILED (pump events) — \(reason): \(String(describing: error))")
        }
        await doseStore.insulinDeliveryStore.purgeCachedInsulinDeliveryObjects()
        SportLog.event("book", "insulin book reset — \(reason)")
    }

    /// Queue hop; the contract is `manualBolusRecommendationOnQueue`. Like stock's recommendation
    /// for the watch, it also keeps the watchBolus decision built with it.
    func recommendManualBolus(potentialCarbEntry: NewCarbEntry? = nil,
                              completion: @escaping (Swift.Result<ManualBolusRecommendation, Error>) -> Void) {
        dataAccessQueue.async {
            let result = self.manualBolusRecommendationOnQueue(potentialCarbEntry: potentialCarbEntry)
            self.noteContextDosingDecision(potentialCarbEntry: potentialCarbEntry, recommendation: try? result.get())
            completion(result)
        }
    }

    /// Stock `LoopDataManager.recommendManualBolus`: `fetchData(for: now)` with the active preset
    /// presumed ending now when asked or when a pre-meal preset meets a carb entry, NO trim (a
    /// running temp is credited through its scheduled end, since the bolus goes on top of a temp
    /// that keeps running), the potential carb entry added, `.manualBolus`. It stores nothing:
    /// no displayed value changes. Differences from stock: no manual glucose sample or edited
    /// original entry (the wrist has no UI for either); a nil recommendation is an error rather
    /// than nil; the amount is rounded by the pump manager when one is held, as in stock.
    func manualBolusRecommendationOnQueue(potentialCarbEntry: NewCarbEntry? = nil,
                                          truncatingActiveOverride: Bool = false) -> Swift.Result<ManualBolusRecommendation, Error> {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))

        do {
            let input = try manualBolusInput(potentialCarbEntry: potentialCarbEntry,
                                             truncatingActiveOverride: truncatingActiveOverride)

            let output = LoopAlgorithm.run(input: input)

            switch output.recommendationResult {
            case .success(let prediction):
                guard var manualBolusRecommendation = prediction.manual else {
                    return .failure(WatchLoopError.missingDataError("no manual bolus recommendation"))
                }
                if let pump = self.pumpManager {
                    manualBolusRecommendation.amount = pump.roundToSupportedBolusVolume(units: manualBolusRecommendation.amount)
                }
                return .success(manualBolusRecommendation)
            case .failure(let error):
                return .failure(error)
            }
        } catch {
            return .failure(error)
        }
    }

    /// The input of stock's `recommendManualBolus`, up to the run (separate so the suite can read it).
    func manualBolusInput(potentialCarbEntry: NewCarbEntry? = nil,
                          truncatingActiveOverride: Bool = false) throws -> StoredDataAlgorithmInput {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))

        var endingPremealOverride = false

        // Watch: stock's `temporaryPresetsManager.activeOverride`.
        if potentialCarbEntry != nil,
           let activeOverride = scheduleOverride, activeOverride.isActive(at: now()),
           activeOverride.context == .preMeal
        {
            endingPremealOverride = true
        }

        var input = try runBlocking {
            try await self.fetchData(for: self.now(), presumePresetEndingNow: truncatingActiveOverride || endingPremealOverride)
        }
        .addingCarbEntry(carbEntry: potentialCarbEntry?.asStoredCarbEntry)

        input.includePositiveVelocityAndRC = usePositiveMomentumAndRCForManualBoluses
        input.recommendationType = .manualBolus
        return input
    }

    /// Stock's `LoopDataManager.usePositiveMomentumAndRCForManualBoluses`. Stock's app never
    /// passes `FeatureFlags.usePositiveMomentumAndRCForManualBoluses` to it, so the init default
    /// (`true`) is what the phone runs; the watch matches that.
    var usePositiveMomentumAndRCForManualBoluses: Bool { true }

    /// Straight to `pumpManager.enactBolus`, capped at the grant's `maximumBolus`. Skips stock's
    /// `DeviceDataManager.enact` wrapper and its uncertain-delivery and suspend checks. As stock's
    /// watch bolus, the watchBolus decision is stored first and its id goes with the command.
    func enactManualBolus(units: Double, activationType: BolusActivationType, carbEntry: NewCarbEntry? = nil,
                          completion: @escaping (Error?) -> Void) {
        dataAccessQueue.async {
            let decisionId = self.storeWatchBolusDosingDecision(carbEntry: carbEntry, requested: units)

            guard let pumpManager = self.pumpManager else {
                DispatchQueue.main.async { completion(WatchLoopError.pumpManagerUnconnected) }
                return
            }
            guard let maxBolus = self.settings.maximumBolus else {
                DispatchQueue.main.async { completion(WatchLoopError.configurationError("maximumBolus")) }
                return
            }
            // The slack is for the exact-maximum case: a picker offering precisely the limit
            // must not be refused by floating-point representation.
            guard units <= maxBolus + .ulpOfOne else {
                DispatchQueue.main.async { completion(WatchLoopError.configurationError("bolus exceeds therapy maximum")) }
                return
            }
            let rounded = pumpManager.roundToSupportedBolusVolume(units: units)

            let deliverBolus = {
                SportLog.event("loan", String(format: "MANUAL BOLUS %.2f U — enacting on the watch pump", rounded))
                self.enactBolusCommand(pumpManager, decisionId, rounded, activationType) { error in
                    if let error = error {
                        SportLog.event("loan", "MANUAL BOLUS FAILED — \(String(describing: error))")
                    } else {
                        SportLog.event("loan", String(format: "MANUAL BOLUS %.2f U ACCEPTED by pod", rounded))

                        // Re-run the moment the pod ACCEPTS, not when delivery finishes: the
                        // temp the loop is running was computed without this bolus in it.
                        self.loop()
                    }
                    self.setManualBolusInFlight(false)
                    DispatchQueue.main.async { completion(error) }
                }
            }
            self.setManualBolusInFlight(true, units: rounded)

            self.dataAccessQueue.async { deliverBolus() }
        }
    }

    /// The local half, under the identity the caller journals it with. Re-runs the loop because
    /// carb effects are only invalidated by new CGM data here.
    func addLoanCarbEntry(_ entry: NewCarbEntry, syncIdentifier: String) {
        carbStore.addCarbEntry(entry, syncIdentifier: syncIdentifier) { result in
            switch result {
            case .success(let stored):
                SportLog.event("loan", String(format: "carbs logged locally: %.0f g", stored.quantity.doubleValue(for: .gram)))

                // Judged against the last pump report, without a fresh pod read.
                self.loop()
            case .failure(let error):
                SportLog.event("loan", "carb store add FAILED — \(String(describing: error))")
            }
        }
    }

    /// Skips stock's authorship checks, which refuse phone-seeded entries. The caller must
    /// journal the delete, or the next takeover re-seeds it.
    func deleteLoanCarbEntry(_ entry: StoredCarbEntry, completion: @escaping (Bool) -> Void) {
        let grams = entry.quantity.doubleValue(for: .gram)

        SportLog.event("loan", String(format: "carb delete attempt %.0f g @ %@ · uuid=%@ sync=%@ ver=%@ prov=%@ mine=%@",
                                      grams, ISO8601DateFormatter().string(from: entry.startDate),
                                      entry.uuid == nil ? "nil" : "set",
                                      entry.syncIdentifier.map { String($0.prefix(8)) } ?? "nil",
                                      entry.syncVersion.map(String.init) ?? "nil",
                                      String(entry.provenanceIdentifier.prefix(12)),
                                      entry.createdByCurrentApp ? "y" : "n"))

        carbStore.deleteCarbEntrySkippingAuthorshipCheck(entry) { result, lookupDiag in
            switch result {
            case .success:
                SportLog.event("loan", String(format: "carb DELETED locally: %.0f g · lookup: %@", grams, lookupDiag))
                self.loop()

                let start = min(Calendar.current.startOfDay(for: self.now()),
                                Date(timeIntervalSinceNow: -CarbMath.maximumAbsorptionTimeInterval))
                self.carbStore.getCarbEntries(start: start) { readback in
                    if case .success(let remaining) = readback {
                        let total = remaining.reduce(0.0) { $0 + $1.quantity.doubleValue(for: .gram) }
                        SportLog.event("loan", String(format: "post-delete store: %d entr%@ remain, %.0f g total",
                                                      remaining.count, remaining.count == 1 ? "y" : "ies", total))
                    }
                }
                completion(true)
            case .failure(let error):
                SportLog.event("loan", "carb store delete FAILED — \(String(describing: error)) · lookup: \(lookupDiag)")
                completion(false)
            }
        }
    }

    /// Stock's `DeviceDataManager.enact` plus `loop()`'s gates before it, in stock's order:
    /// pump inoperable, suspended, manual temp basal running. One deliberate watch difference: a
    /// recommendation older than five minutes is refused. Failures must be enact refusals or
    /// `.enactFailed`, never `.missingDataError`.
    func enactRecommendedAutomaticDose(decisionId: UUID? = nil) -> WatchLoopError? {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))

        guard let recommendedDose = self.recommendedAutomaticDose else {
            return nil
        }

        // Not stock: a recommendation older than five minutes has been overtaken by its own
        // inputs. The wrist can be suspended between compute and enact, which the phone cannot.
        guard abs(recommendedDose.date.timeIntervalSince(now())) < TimeInterval(minutes: 5) else {
            return .recommendationExpired(date: recommendedDose.date)
        }

        guard let pumpManager = pumpManager else {
            return .pumpManagerUnconnected
        }

        // Stock `DeviceDataManager.isPumpInoperable`: a nil delivery state counts.
        guard let basalDeliveryState = pumpManager.status.basalDeliveryState,
              basalDeliveryState != .pumpInoperable else {
            return .pumpInoperable
        }

        // Stock `isSuspended`. A suspended pod is a deliberate user state, not a fault.
        if basalDeliveryState.isSuspended {
            return .pumpSuspended
        }

        // Stock `isManualTempBasalRunning`: the user's temp is left alone.
        if case .tempBasal(let dose) = basalDeliveryState, dose.automatic == false, dose.endDate > now() {
            return .manualTempBasalRunning
        }

        // Unacknowledged last command: OmnipodKit resolves it next session; don't guess.
        guard !pumpManager.status.deliveryIsUncertain else {
            SportLog.event("dose", "enact refused — the pod's last command is unacknowledged (delivery uncertain); the pump manager resolves it on its next session")
            return .enactFailed("delivery uncertain")
        }
        var enactError: WatchLoopError?

        let recommendation = recommendedDose.recommendation

        // Logged BEFORE the send, so a command that never comes back still leaves a record of
        // what was asked for.
        let temp: TempBasalRecommendation? = recommendedDose.enactTempBasal ? recommendation.basalAdjustment : nil
        if let temp {
            SportLog.event("dose", String(format: "enacting temp %.2f U/hr × %.0f min", temp.unitsPerHour, temp.duration / 60))
        }
        let bolus: Double? = recommendation.bolusUnits.map { pumpManager.roundToSupportedBolusVolume(units: $0) }.flatMap { $0 > 0 ? $0 : nil }
        if let bolus {
            SportLog.event("dose", String(format: "enacting automatic bolus %.2f U", bolus))
        }
        do {
            try runBlocking {
                try await self.doseEnactor.enact(decisionId: decisionId, bolus: bolus, tempBasal: temp, with: pumpManager)
            }
            if let temp {
                SportLog.event("dose", String(format: "temp %.2f U/hr ACCEPTED by pod", temp.unitsPerHour))
            }
            if let bolus {
                SportLog.event("dose", String(format: "automatic bolus %.2f U ACCEPTED by pod", bolus))
            }
        } catch {
            SportLog.event("dose", "enact FAILED — \(String(describing: error))")
            enactError = .enactFailed(String(describing: error))
        }

        // Cleared only on success. A failed recommendation stays visible to the display, and the
        // expiry guard above is what stops it being enacted later by some other path.
        if enactError == nil {
            self.recommendedAutomaticDose = nil
        }

        return enactError
    }
}

/// Labelled copies of stock's helpers (`Loop/Managers/LoopDataManager.swift`, phone-only).
extension NewCarbEntry {
    var asStoredCarbEntry: StoredCarbEntry {
        StoredCarbEntry(
            startDate: startDate,
            quantity: quantity,
            foodType: foodType,
            absorptionTime: absorptionTime,
            userCreatedDate: date
        )
    }
}

extension StoredDataAlgorithmInput {
    func addingCarbEntry(carbEntry: CarbType?) -> StoredDataAlgorithmInput {
        var rval = self
        if let carbEntry {
            rval.carbEntries = carbEntries + [carbEntry]
        }
        return rval
    }
}
