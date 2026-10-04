//
//  LoopAlgorithmSupport.swift
//  Loop
//
//  Moved unchanged from LoopDataManager.swift so the watch app compiles the same definitions.
//  LastReservoirValue and Settings were private there; the watch and
//  LoopDataManager+PodLoan.swift use them.
//

import Foundation
import LoopKit
import LoopAlgorithm

struct AlgorithmDisplayState {
    var input: StoredDataAlgorithmInput?
    var output: AlgorithmOutput<StoredCarbEntry>?

    var activeInsulin: InsulinValue? {
        guard let input, let value = output?.activeInsulin else {
            return nil
        }
        return InsulinValue(startDate: input.predictionStart, value: value)
    }

    var activeCarbs: CarbValue? {
        guard let input, let value = output?.activeCarbs else {
            return nil
        }
        return CarbValue(startDate: input.predictionStart, value: value)
    }

    var asTuple: (algoInput: StoredDataAlgorithmInput?, algoOutput: AlgorithmOutput<StoredCarbEntry>?) {
        return (algoInput: input, algoOutput: output)
    }
}

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
            carbAbsorptionModel: self.carbAbsorptionModel.model
        )
        return prediction.glucose
    }
}

extension Notification.Name {
    static let LoopDataUpdated = Notification.Name(rawValue: "com.loopkit.Loop.LoopDataUpdated")
    static let LoopRunning = Notification.Name(rawValue: "com.loopkit.Loop.LoopRunning")
    static let LoopCycleCompleted = Notification.Name(rawValue: "com.loopkit.Loop.LoopCycleCompleted")
}

extension StoredDosingDecision.LastReservoirValue {
    init?(_ reservoirValue: ReservoirValue?) {
        guard let reservoirValue = reservoirValue else {
            return nil
        }
        self.init(startDate: reservoirValue.startDate, unitVolume: reservoirValue.unitVolume)
    }
}

extension StoredDosingDecision.Settings {
    init?(_ settings: StoredSettings?) {
        guard let settings = settings else {
            return nil
        }
        self.init(syncIdentifier: settings.syncIdentifier)
    }
}

extension AutomaticDosingStrategy {
    var recommendationType: DoseRecommendationType {
        switch self {
        case .tempBasalOnly:
            return .tempBasal
        case .automaticBolus:
            return .automaticBolus
        }
    }
}

extension StoredDosingDecision {
    mutating func updateFrom(input: StoredDataAlgorithmInput, output: AlgorithmOutput<StoredCarbEntry>) {
        self.historicalGlucose = input.glucoseHistory.map { HistoricalGlucoseValue(startDate: $0.startDate, quantity: $0.quantity) }
        switch output.recommendationResult {
        case .success(let recommendation):
            self.automaticDoseRecommendation = recommendation.automatic
        case .failure(let error):
            self.appendError(error as? LoopError ?? .unknownError(error))
        }
        if let activeInsulin = output.activeInsulin {
            self.insulinOnBoard = InsulinValue(startDate: input.predictionStart, value: activeInsulin)
        }
        if let activeCarbs = output.activeCarbs {
            self.carbsOnBoard = CarbValue(startDate: input.predictionStart, value: activeCarbs)
        }
        self.predictedGlucose = output.predictedGlucose
    }
}
