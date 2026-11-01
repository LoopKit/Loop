//
//  WatchLoopManager+Diagnostics.swift
//  WatchApp Extension
//
//  The prediction breakdown the debug screen renders, and the inputs behind a dose for its log
//  line; no dosing path reads them.
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore
import WatchConnectivity
import os.log

extension WatchLoopManager {

    /// Each effect's forward difference from the latest glucose, for the debug screen. Describes the
    /// automatic loop's run (`loopRunState`), never the display run. Lane work.
    func updatePredictionBreakdown() {
        let predictedGlucose = loopRunState.output?.predictedGlucose

        /// An effect's change from now to the end of its forecast; nil with none ahead.
        func delta(_ effects: [LoopAlgorithm.GlucoseEffect]?) -> Double? {
            let forward = (effects ?? []).filter { $0.startDate >= now() }
            guard let first = forward.first, let last = forward.last else { return nil }
            return last.mgdl - first.mgdl
        }

        let mgdlU = LoopUnit.milligramsPerDeciliter
        let e = loopRunState.output?.effects

        lastPredictionBreakdown = {
            guard let start = glucoseStore.latestGlucose?.quantity.doubleValue(for: mgdlU),
                  let eventualValue = predictedGlucose?.last?.mgdl else { return nil }
            return PredictionBreakdown(
                startMgdl: start,
                eventualMgdl: eventualValue,
                insulinMgdl: delta(e?.insulin) ?? 0,
                carbMgdl: delta(e?.carbs) ?? 0,
                momentumMgdl: delta(e?.momentum) ?? 0,
                retrospectiveMgdl: delta(e?.retrospectiveCorrection) ?? 0)
        }()
    }

    /// The inputs behind a dose, for its line.
    func algorithmSummary(input: StoredDataAlgorithmInput, output: AlgorithmOutput<StoredCarbEntry>) -> String {
        let target = input.targetMgdl.closestPrior(to: input.predictionStart)?.value
        return String(
            format: "eventual %@ mg/dL against target %@, IOB %.2f U, COB %.0f g",
            output.predictedGlucose.last.map { String(format: "%.0f", $0.mgdl) } ?? "—",
            target.map { String(format: "%.0f-%.0f", $0.lowerBound, $0.upperBound) } ?? "—",
            output.activeInsulin ?? 0,
            output.activeCarbs ?? 0)
    }
}
