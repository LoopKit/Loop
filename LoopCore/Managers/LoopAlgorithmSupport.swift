//
//  LoopAlgorithmSupport.swift
//  Loop
//
//  Code from LoopDataManager.swift that the watch app also runs, so both compile one definition.
//  The declarations moved unchanged; `fetch` is `fetchData`'s body and `checkRecency` is `loop()`'s
//  input checks, with LoopDataManager's own properties as parameters. LastReservoirValue and
//  Settings were private there; the watch and LoopDataManager+PodLoan.swift use them.
//

import Foundation
import LoopKit
import LoopAlgorithm

public extension NewCarbEntry {
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

public extension NewGlucoseSample {
    var asStoredGlucoseSample: StoredGlucoseSample {
        StoredGlucoseSample(
            syncIdentifier: syncIdentifier,
            syncVersion: syncVersion,
            startDate: date,
            quantity: quantity,
            condition: condition,
            trend: trend,
            trendRate: trendRate,
            isDisplayOnly: isDisplayOnly,
            wasUserEntered: wasUserEntered,
            device: device
        )
    }
}

public extension CarbEntryUpdate {
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

public extension StoredDataAlgorithmInput {

    func addingDose(dose: InsulinDoseType?) -> StoredDataAlgorithmInput {
        var rval = self
        if let dose {
            rval.doses = doses + [dose]
        }
        return rval
    }

    func addingGlucoseSample(sample: GlucoseType?) -> StoredDataAlgorithmInput {
        var rval = self
        if let sample {
            rval.glucoseHistory.append(sample)
        }
        return rval
    }

    func addingCarbEntry(carbEntry: CarbType?) -> StoredDataAlgorithmInput {
        var rval = self
        if let carbEntry {
            rval.carbEntries = carbEntries + [carbEntry]
        }
        return rval
    }

    func removingCarbEntry(carbEntry: CarbType?) -> StoredDataAlgorithmInput {
        guard let carbEntry else {
            return self
        }
        var rval = self
        var currentEntries = self.carbEntries
        if let index = currentEntries.firstIndex(of: carbEntry) {
            currentEntries.remove(at: index)
        }
        rval.carbEntries = currentEntries
        return rval
    }

    func predictGlucose(effectsOptions: AlgorithmEffectsOptions = .all) throws -> [PredictedGlucoseValue] {
        let prediction = LoopAlgorithm.generatePrediction(
            start: predictionStart,
            glucoseHistory: glucoseHistory,
            doses: doses,
            carbEntries: carbEntries,
            basal: basal,
            sensitivity: sensitivity,
            carbRatio: carbRatio,
            algorithmEffectsOptions: effectsOptions,
            useIntegralRetrospectiveCorrection: self.useIntegralRetrospectiveCorrection,
            useMidAbsorptionISF: true,
            carbAbsorptionModel: self.carbAbsorptionModel.model,
            experiments: experiments
        )
        return prediction.glucose
    }
}

public extension Notification.Name {
    static let LoopDataUpdated = Notification.Name(rawValue: "com.loopkit.Loop.LoopDataUpdated")
    static let LoopRunning = Notification.Name(rawValue: "com.loopkit.Loop.LoopRunning")
    static let LoopCycleCompleted = Notification.Name(rawValue: "com.loopkit.Loop.LoopCycleCompleted")
}
