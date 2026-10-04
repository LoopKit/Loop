//
//  WatchLoopManager+Diagnostics.swift
//  WatchApp Extension
//
//  Log surfaces only; no dosing path reads them. `lastPredictionBreakdown` is also rendered
//  by the debug screen.
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore
import WatchConnectivity
import os.log

extension WatchLoopManager {

    /// The per-cycle prediction line: each effect's forward difference from the latest glucose.
    /// Describes the automatic loop's run (`loopRunState`), never the display run.
    func logPredictionBreakdown(decided: AutomaticDoseRecommendation? = nil) {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))

        let predictedGlucose = loopRunState.output?.predictedGlucose
        let activeInsulin = loopRunState.output?.activeInsulin
        let activeCarbs = loopRunState.output?.activeCarbs

        // `net` and `delta` are the same difference; keep them in step.
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

        if let r = decided {
            let basal = String(format: "%.2f U/h", r.basalAdjustment.unitsPerHour)
            let bolus = r.bolusUnits.map { String(format: " + auto-bolus %.2f U", $0) } ?? ""
            rec = basal + bolus
        } else {
            rec = "none"
        }

        // The forecast minimum beside the suspend threshold: it drives the correction.
        let minPredicted: String = {
            guard let fwd = predictedGlucose?.filter({ $0.startDate >= now() }), !fwd.isEmpty,
                  let m = fwd.min(by: { $0.quantity.doubleValue(for: mgdlU) < $1.quantity.doubleValue(for: mgdlU) })
            else { return "—" }
            return String(format: "%.0f@%dm", m.quantity.doubleValue(for: mgdlU), Int(m.startDate.timeIntervalSince(now()) / 60))
        }()
        // The run's own threshold: a very-high-insulin-needs override raises it.
        let suspendThr = loopRunState.input?.suspendThreshold.map { String(format: "%.0f", $0.doubleValue(for: mgdlU)) } ?? "—"

        let e = loopRunState.output?.effects

        lastPredictionBreakdown = {
            func delta(_ effects: [GlucoseEffect]?) -> Double {
                guard let effects else { return 0 }
                let forward = effects.filter { $0.startDate >= now() }
                guard let first = forward.first, let last = forward.last else { return 0 }
                return last.quantity.doubleValue(for: mgdlU) - first.quantity.doubleValue(for: mgdlU)
            }
            guard let start = glucoseStore.latestGlucose?.quantity.doubleValue(for: mgdlU),
                  let eventualValue = predictedGlucose?.last?.quantity.doubleValue(for: mgdlU) else { return nil }
            return PredictionBreakdown(
                startMgdl: start,
                eventualMgdl: eventualValue,
                insulinMgdl: delta(e?.insulin),
                carbMgdl: delta(e?.carbs),
                momentumMgdl: delta(e?.momentum),
                retrospectiveMgdl: delta(e?.retrospectiveCorrection))
        }()
        SportLog.event("predict", "eventual \(eventual) · min \(minPredicted) · suspendThr \(suspendThr) · net effects: carbs \(net(e?.carbs)), insulin \(net(e?.insulin)), momentum \(net(e?.momentum)), RC \(net(e?.retrospectiveCorrection)) · IOB \(activeInsulin.map { String(format: "%.2f", $0) } ?? "—") · COB \(activeCarbs.map { String(format: "%.0f", $0) } ?? "—") · momPts \(e?.momentum.count ?? 0) · rcDisc \(e?.retrospectiveGlucoseDiscrepancies.count ?? 0) · rec \(rec)")
        SportLog.event("curve", curveSummary(predictedGlucose))
    }

    /// The insulin book dose by dose at one instant, for seed-in and hand-back. Rows with zero
    /// net basal are omitted.
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

    /// Forecast minimum, then the curve every 30 minutes to two hours.
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

    /// Every input behind a temp, on the same line.
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
