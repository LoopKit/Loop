//
//  WatchLoopManager+Dosing.swift
//  WatchApp Extension
//
//  What the wrist does to the pod, and the book it reasons from.
//
//  THE INSULIN BOOK. The watch keeps its own DoseStore, and during a loan it has exactly ONE
//  writer — the watch's pump manager reporting pod events — plus a single per-loan seed of the
//  phone's history at grant. It is RESET at the start of every loan, because the two writers
//  name the same physical dose differently: a seeded row carries the phone's sync identifier and
//  a pod-reported row carries one derived from the pod's own bytes, so nothing dedupes them and
//  a dose left over from the previous loan would be counted twice.
//
//  Two ways insulin leaves: the automatic temp basal, which is the only thing the closed loop
//  ever commands, and a manual bolus, which a human has confirmed on the wrist. Carb entry lives
//  here too — a carb has to reach THIS cycle's prediction, not the next one's.
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore
import G7SensorKit
import WatchConnectivity
import os.log

extension WatchLoopManager {

    /// Write the phone's doses for this loan into the book. `syncDoseEntries` matches on
    /// `syncIdentifier` and silently ignores an entry without one, so the seed carries the
    /// phone's identities and only ever lands in the insulin-delivery half of the store — which
    /// is why `resetInsulinBook` has to clear that half too.
    func seedInsulinHistory(_ entries: [DoseEntry]) async throws {
        try await doseStore.syncDoseEntries(entries)
    }

    /// The book's only live writer: pod events, straight from the pump manager.
    ///
    /// Call it even when `events` is EMPTY. `lastReconciliation` advances `lastAddedPumpData`
    /// before the empty-list early return, and that is the clock the dosing recency gate reads —
    /// a status read that found nothing new is exactly the evidence that the book is current.
    func recordPumpEvents(_ events: [NewPumpEvent], lastReconciliation: Date?, replacePendingEvents: Bool) async throws {
        try await doseStore.addPumpEvents(events, lastReconciliation: lastReconciliation, replacePendingEvents: replacePendingEvents)
    }

    /// Empty the book, at the start of a loan and at teardown. BOTH halves are needed: the pump
    /// events and reservoir on one side, the cached insulin-delivery objects the grant seed lands
    /// in on the other. Clear only the first and the previous loan's seeded rows survive.
    ///
    /// It also nils the store's reconciliation date, so `lastAddedPumpData` falls back to the
    /// distant past and the recency gate refuses to dose until the pod has reported once. That is
    /// the intended order: seed, then a pod read, then a cycle.
    func resetInsulinBook(reason: String) async {
        do {
            try await doseStore.resetPumpData()
        } catch {
            SportLog.event("book", "reset FAILED (pump events) — \(reason): \(String(describing: error))")
        }
        await doseStore.insulinDeliveryStore.purgeCachedInsulinDeliveryObjects()
        SportLog.event("book", "insulin book reset — \(reason)")
    }

    /// IOB read straight from the book, independent of whether a cycle has run — which is what
    /// makes a number available at takeover, before the first prediction exists.
    ///
    /// Basal-relative, annotated against the OVERRIDE-APPLIED schedule: IOB is delivery above or
    /// below the schedule, and under an override the schedule itself has moved. nil means the
    /// question cannot be answered (no basal schedule yet); an empty book is 0, not nil.
    ///
    /// The timeline is on a 5-minute grid, so `date` rarely falls on a point. Taking the larger
    /// of the neighbours either side errs toward MORE insulin on board, which is the direction
    /// that asks for less.
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

    /// Mirrors stock `LoopDataManager.recommendManualBolus`, with four differences that matter.
    ///
    /// 1. IT IS NOT PURE. It republishes `predictedGlucose`, `activeInsulin`, `activeCarbs` and
    ///    `lastAlgorithmEffects` from a `.manualBolus` run. `publishHUDContext` calls it every
    ///    time it publishes, so the numbers on the wrist come from this run and not from the
    ///    temp-basal run that actually dosed. Stock's function only returns a value.
    /// 2. The amount is rounded to a volume the pod can deliver BEFORE anyone sees it. The stock
    ///    dial renders three fraction digits, so an unrounded value reads as "REC: 2.191 U" — a
    ///    dose no pod can give, and one the delivery path would round differently anyway.
    /// 3. A potential carb entry is appended to the input by hand rather than through stock's
    ///    `addingCarbEntry`, and there is no manual glucose sample, no original carb entry and no
    ///    pre-meal/override truncation: none of those surfaces exist on the wrist.
    /// 4. `includePositiveVelocityAndRC` is fixed true where stock reads a user setting, and the
    ///    pump-data recency gate and the dose trim inside `fetchAlgorithmInput` apply here too —
    ///    stock's manual path does neither.
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

    /// Deliver a human-confirmed bolus on the watch's pump. During a loan the phone cannot do
    /// it — it released the pod link at the grant, and it may be switched off entirely.
    ///
    /// Capped at the GRANT's `maximumBolus`, the same value the picker offers. The cap is checked
    /// here as well as at the picker because the phone's relayed limit can be stale and cannot be
    /// refreshed with the phone off.
    ///
    /// This goes STRAIGHT to `pumpManager.enactBolus`, not through stock's
    /// `DeviceDataManager.enact` wrapper — so it does not cancel a running automatic bolus first
    /// (the watch never issues one; it is temp-basal-only) and it does not raise stock's failure
    /// notification, which the bolus flow re-implements. It also does not re-check
    /// `deliveryIsUncertain` or suspension the way the automatic path does.
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
                        // An ESTIMATE for the progress bar, from the pod's fixed delivery rate
                        // of 1.5 U/min (one 0.05 U pulse every two seconds). Same contract as
                        // stock's PodDoseProgressEstimator: the pod is never asked, the estimate
                        // expires on its own clock, and nothing here ever renders "delivered" —
                        // a clock cannot claim to have watched insulin arrive.
                        let acceptedAt = self.now()
                        let deliveryEndsAt = acceptedAt.addingTimeInterval(rounded / 1.5 * 60)
                        SportLog.event("loan", String(format: "MANUAL BOLUS delivering %.2f U — estimated done in %.0fs",
                                                      rounded, deliveryEndsAt.timeIntervalSince(acceptedAt)))

                        self.setManualBolusDelivering(units: rounded, from: acceptedAt, to: deliveryEndsAt)

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

    /// The LOCAL half of a wrist carb entry. The durable half is the caller's: the same entry
    /// must be journaled, or the phone never learns about it.
    ///
    /// The immediate re-run is load-bearing. Carb effects are invalidated only by new CGM data —
    /// stock's carb-store observer is not wired up here — so without it the entry sits outside
    /// the prediction until the next reading, up to five minutes of dosing that cannot see the
    /// meal. Note this runs a full ENACTING cycle where stock's observer only refreshes the
    /// display.
    func addLoanCarbEntry(_ entry: NewCarbEntry) {
        carbStore.addCarbEntry(entry) { result in
            switch result {
            case .success(let stored):
                SportLog.event("loan", String(format: "carbs logged locally: %.0f g", stored.quantity.doubleValue(for: .gram)))

                // `loop()` directly, not `checkPumpDataAndLoop()`: the pod is not read first, so
                // this cycle is judged against the last pump report. If that report is already
                // older than the recency gate allows, the cycle refuses rather than the carb
                // entry provoking a pod read of its own.
                self.loop()
            case .failure(let error):
                SportLog.event("loan", "carb store add FAILED — \(String(describing: error))")
            }
        }
    }

    /// Delete through the authorship-check-skipping door, and re-run the loop for the same
    /// reason `addLoanCarbEntry` does.
    ///
    /// Entries seeded from the phone at takeover are honestly marked `createdByCurrentApp: false`
    /// with `uuid: nil`, and BOTH of stock's gates — the method guard and the object lookup —
    /// refuse them. On a store that is an authoritative mirror of another device's, authorship is
    /// an artifact of the seeding path, not an ownership boundary.
    ///
    /// The local delete is again only half of it: the caller must journal the deletion. A wipe at
    /// the next takeover re-seeds the phone's view, so a delete the phone never heard about
    /// RESURRECTS — the user deletes a carb, watches it vanish, and it returns still dosing.
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

    /// Send the automatic recommendation to the pod. Stands in for stock's
    /// `DeviceDataManager.enact` plus the gates stock keeps in `loop()`.
    ///
    /// EVERY failure out of here must be `.enactFailed` (or one of the specific refusals), never
    /// `.missingDataError`. The verdict line classifies `missingDataError` as a COMPUTE failure
    /// and prints it as a missing prediction, so a mistyped pod refusal is reported as a bad
    /// forecast and the refusal itself disappears from the log entirely.
    ///
    /// Stock's `pumpInoperable` and `manualTempBasalRunning` gates are NOT reproduced here.
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

        // The pod's last command was never acknowledged, so we do not know what it is running.
        // OmnipodKit resolves it on its next session and the book then gets the resolved truth;
        // guessing here would write a dose that may not exist.
        guard !pumpManager.status.deliveryIsUncertain else {
            SportLog.event("dose", "enact refused — the pod's last command is unacknowledged (delivery uncertain); the pump manager resolves it on its next session")
            return .enactFailed("delivery uncertain")
        }
        var enactError: WatchLoopError?

        let recommendation = recommendedDose.recommendation

        // Logged BEFORE the send, so a command that never comes back still leaves a record of
        // what was asked for.
        let temp = recommendation.basalAdjustment
        SportLog.event("dose", String(format: "enacting temp %.2f U/hr × %.0f min", temp.unitsPerHour, temp.duration / 60))
        if let bolus = recommendation.bolusUnits, bolus > 0 {
            SportLog.event("dose", String(format: "enacting bolus %.2f U", bolus))
        }
        do {
            try runBlocking {
                try await self.doseEnactor.enact(decisionId: nil, bolus: recommendation.bolusUnits,
                                                 tempBasal: recommendation.basalAdjustment, with: pumpManager)
            }
            SportLog.event("dose", String(format: "temp %.2f U/hr ACCEPTED by pod", temp.unitsPerHour))
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
