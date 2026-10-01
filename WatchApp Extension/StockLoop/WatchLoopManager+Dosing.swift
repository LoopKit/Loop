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

    /// IOB from the book, against the override-applied schedule; takes the larger grid neighbour.
    /// nil only when there is no basal schedule.
    func insulinOnBoardFromStore(at date: Date) -> Double? {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))
        guard let basal = basalRateScheduleApplyingOverrideHistory else { return nil }
        let longest = doseStore.longestEffectDuration
        guard let doses = try? runBlocking({
            try await self.doseStore.getNormalizedDoseEntries(start: date.addingTimeInterval(-longest), end: nil)
        }) else { return nil }
        if doses.isEmpty { return 0 }
        let window = (start: doses.map(\.startDate).min() ?? date,
                      end: (doses.map(\.endDate).max() ?? date).addingTimeInterval(longest))
        let basalTimeline = BasalRateSchedule.generateTimeline(
            schedules: [(date: .distantPast, schedule: basal)],
            startDate: window.start,
            endDate: window.end)
        let timeline = doses
            .map { $0.simpleDose(with: insulinModel(for: $0.insulinType)) }
            .annotated(with: basalTimeline)
            .insulinOnBoardTimeline(longestEffectDuration: longest,
                                    from: date.addingTimeInterval(-.minutes(5)),
                                    to: date.addingTimeInterval(.minutes(5)))
        let before = timeline.last(where: { $0.startDate <= date })?.value
        let after = timeline.first(where: { $0.startDate >= date })?.value
        return max(before ?? 0, after ?? 0)
    }

    /// Publish an IOB from the book before any cycle has run, so the glance shows the loan's
    /// inherited insulin from the moment of takeover rather than a dash.
    func primeIOBFromStore(at date: Date, _ completion: @escaping (Double?) -> Void) {
        dataAccessQueue.async {
            let iob = self.insulinOnBoardFromStore(at: date)
            if let iob { self.activeInsulin = iob }
            completion(iob)
        }
    }

    /// Queue hop only; the contract is `manualBolusRecommendationOnQueue`, including the fact
    /// that running it REPUBLISHES the displayed prediction, IOB and COB.
    func recommendManualBolus(potentialCarbEntry: NewCarbEntry? = nil,
                              completion: @escaping (Swift.Result<ManualBolusRecommendation, Error>) -> Void) {
        dataAccessQueue.async {
            completion(self.manualBolusRecommendationOnQueue(potentialCarbEntry: potentialCarbEntry))
        }
    }

    /// Stock `recommendManualBolus`, except: it republishes the display values, rounds to a
    /// deliverable volume, appends the carb entry by hand, and applies the recency gate and trim.
    func manualBolusRecommendationOnQueue(potentialCarbEntry: NewCarbEntry? = nil) -> Swift.Result<ManualBolusRecommendation, Error> {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))
        var result: Swift.Result<ManualBolusRecommendation, Error>!
        let completion: (Swift.Result<ManualBolusRecommendation, Error>) -> Void = { result = $0 }
        do {
                var input = try self.runBlocking {
                    try await self.fetchAlgorithmInput(at: self.now(), recommendationType: .manualBolus)
                }

                if let potentialCarbEntry {
                    input.carbEntries += [StoredCarbEntry(
                        startDate: potentialCarbEntry.startDate,
                        quantity: potentialCarbEntry.quantity,
                        foodType: potentialCarbEntry.foodType,
                        absorptionTime: potentialCarbEntry.absorptionTime)]
                }

                let output = LoopAlgorithm.run(input: input)

                self.predictedGlucose = output.predictedGlucose
                self.activeInsulin = output.activeInsulin
                self.activeCarbs = output.activeCarbs
                self.lastAlgorithmEffects = output.effects

                switch output.recommendationResult {
                case .failure(let error):
                    throw error
                case .success(let recommendation):
                    guard var manual = recommendation.manual else {
                        throw WatchLoopError.missingDataError("no manual bolus recommendation")
                    }

                    if let pump = self.pumpManager {
                        manual.amount = pump.roundToSupportedBolusVolume(units: manual.amount)
                    }
                    completion(.success(manual))
                }
        } catch {
            completion(.failure(error))
        }
        return result
    }

    /// Straight to `pumpManager.enactBolus`, capped at the grant's `maximumBolus`. Skips stock's
    /// `DeviceDataManager.enact` wrapper and its uncertain-delivery and suspend checks.
    func enactManualBolus(units: Double, activationType: BolusActivationType, completion: @escaping (Error?) -> Void) {
        dataAccessQueue.async {
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
                pumpManager.enactBolus(decisionId: nil, units: rounded, activationType: activationType) { error in
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

    /// Stock's `DeviceDataManager.enact` plus `loop()`'s gates, minus `pumpInoperable` and
    /// `manualTempBasalRunning`. Failures must be `.enactFailed`, never `.missingDataError`.
    func enactRecommendedAutomaticDose() -> WatchLoopError? {
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

        // A suspended pod is a deliberate user state, not a fault: refuse quietly and let the
        // cycle report it, rather than sending a temp that would resume delivery.
        if case .suspended = pumpManager.status.basalDeliveryState {
            return .pumpSuspended
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
                try await self.doseEnactor.enact(decisionId: nil, bolus: bolus, tempBasal: temp, with: pumpManager)
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
