//
//  WatchLoopManager+Diagnostics.swift
//  WatchApp Extension
//
//  Log surfaces. NOTHING HERE DOSES, and no dosing path reads any of these numbers back: they
//  exist so a log recovered from the wrist can be read without the watch in front of you.
//
//  The one product that outlives its log line is `lastPredictionBreakdown`, which the debug
//  screen renders; `logPredictionBreakdown` is its only writer.
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

    /// Write the per-cycle prediction line and refresh `lastPredictionBreakdown`.
    ///
    /// Every component is the FORWARD DIFFERENCE of one effect array — its last value minus its
    /// first value at or after `now()` — and the start is the latest stored glucose. That is an
    /// arithmetic that reads well, not `LoopMath.predictGlucose`'s own accounting: the arrays are
    /// differenced independently, the momentum blend's taper is not applied, and nothing is
    /// anchored to the starting sample's date. So `residualMgdl` is whatever the four named
    /// effects fail to explain and is NOT zero by construction — a big one is a thing to look at,
    /// not a bug in this function.
    func logPredictionBreakdown(decided: AutomaticDoseRecommendation? = nil) {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))

        // `net` (formatted, for the log line) and `delta` (numeric, for the struct) are the SAME
        // forward difference. Change one and the log and the debug screen stop agreeing.
        func net(_ effects: [GlucoseEffect]?) -> String {
            guard let effects, !effects.isEmpty else { return "—" }
            let forward = effects.filter { $0.startDate >= now() }
            guard let first = forward.first, let last = forward.last else { return "—" }
            let mgdl = LoopUnit.milligramsPerDeciliter
            return String(format: "%+.0f", last.quantity.doubleValue(for: mgdl) - first.quantity.doubleValue(for: mgdl))
        }

        let mgdlU = LoopUnit.milligramsPerDeciliter
        let eventual = predictedGlucose?.last.map { String(format: "%.0f", $0.quantity.doubleValue(for: mgdlU)) } ?? "—"

        let rec: String

        // `decided` is passed in because a SUCCESSFUL enact clears `recommendedAutomaticDose`.
        // Without it this line would print "none" for exactly the cycles that dosed.
        if let r = decided ?? recommendedAutomaticDose?.recommendation {
            let basal = String(format: "%.2f U/h", r.basalAdjustment.unitsPerHour)
            let bolus = r.bolusUnits.map { String(format: " + auto-bolus %.2f U", $0) } ?? ""
            rec = basal + bolus
        } else {
            rec = "none"
        }

        // The forecast MINIMUM, printed beside the suspend threshold on purpose: the correction
        // is driven by the lowest forward point, and any point below the threshold turns the whole
        // cycle into a suspend. A small temp under a high eventual is read off this pair.
        let minPredicted: String = {
            guard let fwd = predictedGlucose?.filter({ $0.startDate >= now() }), !fwd.isEmpty,
                  let m = fwd.min(by: { $0.quantity.doubleValue(for: mgdlU) < $1.quantity.doubleValue(for: mgdlU) })
            else { return "—" }
            return String(format: "%.0f@%dm", m.quantity.doubleValue(for: mgdlU), Int(m.startDate.timeIntervalSince(now()) / 60))
        }()
        let suspendThr = settings.suspendThreshold.map { String(format: "%.0f", $0.quantity.doubleValue(for: mgdlU)) } ?? "—"

        let e = lastAlgorithmEffects

        lastPredictionBreakdown = {
            func delta(_ effects: [GlucoseEffect]?) -> Double {
                guard let effects else { return 0 }
                let forward = effects.filter { $0.startDate >= now() }
                guard let first = forward.first, let last = forward.last else { return 0 }
                return last.quantity.doubleValue(for: mgdlU) - first.quantity.doubleValue(for: mgdlU)
            }
            guard let start = glucoseStore.latestGlucose?.quantity.doubleValue(for: mgdlU),
                  let eventualValue = predictedGlucose?.last?.quantity.doubleValue(for: mgdlU) else { return nil }
            let insulin = delta(e?.insulin)
            let carb = delta(e?.carbs)
            let momentum = delta(e?.momentum)
            let retro = delta(e?.retrospectiveCorrection)

            let rawTail: Double? = {
                guard let tail = e?.insulin, let last = tail.last else { return nil }
                let base = tail.last(where: { $0.startDate <= now() }) ?? tail.first
                guard let base else { return nil }
                return last.quantity.doubleValue(for: mgdlU) - base.quantity.doubleValue(for: mgdlU)
            }()
            return PredictionBreakdown(
                startMgdl: start,
                eventualMgdl: eventualValue,
                insulinMgdl: insulin,
                carbMgdl: carb,
                momentumMgdl: momentum,
                retrospectiveMgdl: retro,
                residualMgdl: eventualValue - (start + insulin + carb + momentum + retro),
                insulinRawTailMgdl: rawTail,
                insulinExpectedMgdl: nil,
                isfMgdlPerU: nil,
                iobUnits: activeInsulin,
                momentumPointCount: e?.momentum.count ?? 0,
                computedAt: now())
        }()
        SportLog.event("predict", "eventual \(eventual) · min \(minPredicted) · suspendThr \(suspendThr) · net effects: carbs \(net(e?.carbs)), insulin \(net(e?.insulin)), momentum \(net(e?.momentum)), RC \(net(e?.retrospectiveCorrection)) · IOB \(activeInsulin.map { String(format: "%.2f", $0) } ?? "—") · COB \(activeCarbs.map { String(format: "%.0f", $0) } ?? "—") · momPts \(e?.momentum.count ?? 0) · rcDisc \(e?.retrospectiveGlucoseDiscrepancies.count ?? 0) · rec \(rec)")
        SportLog.event("curve", curveSummary(predictedGlucose))
        logPredictionDiffAgainstPhone(effects: e)
    }

    /// Watch-vs-phone column diff against the prediction the phone stamped into the grant — the
    /// one moment the two devices ran on the same inputs, so a divergence here is the wrist's
    /// own, not the clock's.
    ///
    /// Stops after 20 minutes: past that the snapshot describes glucose, carbs and doses the
    /// watch has moved on from, and the columns would be comparing two different questions.
    func logPredictionDiffAgainstPhone(effects e: LoopAlgorithmEffects<StoredCarbEntry>?) {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))
        guard let snap = phonePredictionSnapshotAtGrant else { return }
        let age = now().timeIntervalSince(snap.snapshotAt)
        guard age <= .minutes(20) else { return }

        let mgdl = LoopUnit.milligramsPerDeciliter

        func fwd(_ effects: [GlucoseEffect]?) -> Double? {
            guard let effects else { return nil }
            let forward = effects.filter { $0.startDate >= now() }
            guard let first = forward.first, let last = forward.last else { return nil }
            return last.quantity.doubleValue(for: mgdl) - first.quantity.doubleValue(for: mgdl)
        }
        func col(_ label: String, _ watch: Double?, _ phone: Double) -> String {
            guard let w = watch else { return "\(label) —/\(String(format: "%+.0f", phone))" }
            return String(format: "%@ %+.0f vs %+.0f (Δ%+.0f)", label, w, phone, w - phone)
        }

        let wEventual = predictedGlucose?.last?.quantity.doubleValue(for: mgdl)
        let eventualCol = wEventual.map { String(format: "eventual %.0f vs %.0f (Δ%+.0f)", $0, snap.eventualMgdl, $0 - snap.eventualMgdl) }
            ?? String(format: "eventual —/%.0f", snap.eventualMgdl)
        let iobCol = activeInsulin.map { String(format: "IOB %.2f vs %.2f (Δ%+.2f)", $0, snap.iobUnits, $0 - snap.iobUnits) }
            ?? String(format: "IOB —/%.2f", snap.iobUnits)
        let cobCol = activeCarbs.map { String(format: "COB %.0f vs %.0f", $0, snap.cobGrams) }
            ?? String(format: "COB —/%.0f", snap.cobGrams)

        SportLog.event("predict-diff", String(
            format: "@+%.0fs (watch vs phone@grant) — %@ | %@ · %@ · %@ · %@ | %@ · %@ | momPts %d vs %d · rcDisc %d vs %d",
            age,
            eventualCol,
            col("mom", fwd(e?.momentum), snap.impactMomentumMgdl),
            col("ins", fwd(e?.insulin), snap.impactInsulinMgdl),
            col("carb", fwd(e?.carbs), snap.impactCarbMgdl),
            col("RC", fwd(e?.retrospectiveCorrection), snap.impactRCMgdl),
            iobCol, cobCol,
            e?.momentum.count ?? 0, snap.momentumPointCount,
            e?.retrospectiveGlucoseDiscrepancies.count ?? 0, snap.rcDiscrepancyCount))
    }

    /// Dose-by-dose decomposition of the insulin book at one instant, labelled by the moment
    /// that asked for it. Called at both ends of a loan (seed-in and hand-back) so the two dumps
    /// can be read side by side when an IOB figure is disputed.
    ///
    /// Net basal is the number that matters — delivery ABOVE or BELOW the schedule, which is what
    /// IOB is built from — so rows whose net rounds to zero are omitted, boluses always kept. The
    /// annotated dose type carries no sync identity, hence the placeholder id column; rows are
    /// matched across dumps by time.
    func dumpIOBDecomp(_ label: String, at t: Date) {
        dataAccessQueue.async {
            guard let basal = self.basalRateScheduleApplyingOverrideHistory else {
                SportLog.event("iob-decomp", "@\(label) — no schedule yet")
                return
            }
            let longest = self.doseStore.longestEffectDuration
            let bookDoses = (try? self.runBlocking {
                try await self.doseStore.getNormalizedDoseEntries(start: t.addingTimeInterval(-longest), end: nil)
            }) ?? []
            do {
                let window = (start: bookDoses.map(\.startDate).min() ?? t,
                              end: (bookDoses.map(\.endDate).max() ?? t).addingTimeInterval(InsulinMath.defaultInsulinActivityDuration))
                let basalTimeline = BasalRateSchedule.generateTimeline(
                    schedules: [(date: .distantPast, schedule: basal)],
                    startDate: window.start,
                    endDate: window.end)
                let doses = bookDoses
                    .map { $0.simpleDose(with: self.insulinModel(for: $0.insulinType)) }
                    .annotated(with: basalTimeline)
                let uhr = LoopUnit.internationalUnit.unitDivided(by: .hour)
                let tf = DateFormatter()
                tf.dateFormat = "HH:mm:ss"
                var netSum = 0.0
                var rows: [String] = []
                for d in doses where abs(d.netBasalUnits) > 0.0001 || d.type == .bolus {
                    netSum += d.netBasalUnits
                    let sched = String(format: "%.2f", d.volume / max(d.duration / 3600, .ulpOfOne))
                    let id = "—"

                    let del = String(format: "%.3f", d.volume)
                    rows.append(String(format: "%@ %@..%@ net=%+.3f sched=%@ vol=%@ id=%@",
                                       "\(d.type)", tf.string(from: d.startDate), tf.string(from: d.endDate),
                                       d.netBasalUnits, sched, del, id))
                }
                SportLog.event("iob-decomp", "@\(label) Σnet=\(String(format: "%.3f", netSum))U n=\(rows.count) · " + rows.joined(separator: " | "))
            }
        }
    }

    /// The forecast in one line: its lowest forward point, then the curve sampled every 30
    /// minutes out to two hours. When no point is still in the future — a prediction that has
    /// aged out — the minimum falls back to the whole array, so the summary can be describing a
    /// curve that has already been overtaken. The sample marks are always taken from `now()`.
    func curveSummary(_ predicted: [PredictedGlucoseValue]?) -> String {
        guard let predicted, !predicted.isEmpty else { return "—" }
        let mgdl = LoopUnit.milligramsPerDeciliter
        let t0 = now()
        let fwd = predicted.filter { $0.startDate >= t0 }
        guard let minPoint = (fwd.isEmpty ? predicted : fwd)
            .min(by: { $0.quantity.doubleValue(for: mgdl) < $1.quantity.doubleValue(for: mgdl) }) else { return "—" }
        let minV = Int(minPoint.quantity.doubleValue(for: mgdl).rounded())
        let minOff = Int((minPoint.startDate.timeIntervalSince(t0) / 60).rounded())
        let samples = [0, 30, 60, 90, 120].map { m -> String in
            let mark = t0.addingTimeInterval(.minutes(Double(m)))
            guard let p = predicted.last(where: { $0.startDate <= mark }) ?? predicted.first else { return "—" }
            return "\(Int(p.quantity.doubleValue(for: mgdl).rounded()))"
        }.joined(separator: "→")
        return "min \(minV)@\(minOff)m · t0–120: \(samples)"
    }

    /// Every input that produced a temp, on the same line as the temp. Built at the moment of
    /// the decision and from that cycle's own input, so reading the log never requires re-running
    /// the algorithm against settings that may since have changed.
    func algorithmSummary(input: StoredDataAlgorithmInput,
                                  output: AlgorithmOutput<StoredCarbEntry>,
                                  enacting: TempBasalRecommendation) -> String {
        let mgdl = LoopUnit.milligramsPerDeciliter
        let target = input.target.closestPrior(to: input.predictionStart)?.value
        return String(
            format: "eventual %@ vs target %@ · running %@ · scheduled %.2f · maxBasal %.2f · IOB %.2f · COB %.0f · suspendThr %@ => temp %.2f U/hr x %.0f min",
            output.predictedGlucose.last.map { String(format: "%.0f", $0.quantity.doubleValue(for: mgdl)) } ?? "—",
            target.map { String(format: "%.0f-%.0f", $0.lowerBound.doubleValue(for: mgdl), $0.upperBound.doubleValue(for: mgdl)) } ?? "—",
            runningTempBasal().map { String(format: "%.2f U/hr", $0.unitsPerHour) } ?? "none(scheduled)",
            input.basal.closestPrior(to: input.predictionStart)?.value ?? 0,
            input.maxBasalRate,
            output.activeInsulin ?? 0,
            output.activeCarbs ?? 0,
            input.suspendThreshold?.doubleValue(for: mgdl).description ?? "none",
            enacting.unitsPerHour,
            enacting.duration / 60)
    }
}
