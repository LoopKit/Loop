//
//  LoopDataManager+CarbAbsorption.swift
//  Loop
//
//  Created by Pete Schwamb on 11/6/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import HealthKit
import LoopAlgorithm

struct CarbAbsorptionReview {
    var carbEntries: [StoredCarbEntry]
    var carbStatuses: [CarbStatus<StoredCarbEntry>]
    var effectsVelocities: [GlucoseEffectVelocity]
    var carbEffects: [GlucoseEffect]
}

extension LoopDataManager {

    func dynamicCarbsOnBoard(from start: Date? = nil, to end: Date? = nil) async -> [CarbValue] {
        if let effects = displayState.output?.effects {
            return effects.carbStatus.dynamicCarbsOnBoard(from: start, to: end, absorptionModel: carbAbsorptionModel.model)
        } else {
            return []
        }
    }

    func fetchCarbAbsorptionReview(start: Date, end: Date) async throws -> CarbAbsorptionReview {
        // Need to get insulin data from any active doses that might affect this time range
        var dosesStart = start.addingTimeInterval(-InsulinMath.defaultInsulinActivityDuration)
        let doses = try await doseStore.getNormalizedDoseEntries(
            start: dosesStart,
            end: end
        ).map { $0.simpleDose(with: insulinModel(for: $0.insulinType)) }

        dosesStart = doses.map { $0.startDate }.min() ?? dosesStart

        let basal = try await settingsProvider.getBasalHistory(startDate: dosesStart, endDate: end)

        let carbEntries = try await carbStore.getCarbEntries(start: start, end: end)

        let carbRatio = try await settingsProvider.getCarbRatioHistory(startDate: start, endDate: end)

        let glucose = try await glucoseStore.getGlucoseSamples(start: start, end: end)

        let sensitivityStart = min(start, dosesStart)

        let sensitivity = try await settingsProvider.getInsulinSensitivityHistory(startDate: sensitivityStart, endDate: end)

        let overrides = temporaryPresetsManager.overrideHistory.getOverrideHistory(startDate: sensitivityStart, endDate: end)

        guard !sensitivity.isEmpty else {
            throw LoopError.configurationError(.insulinSensitivitySchedule)
        }

        let sensitivityWithOverrides = overrides.applySensitivity(over: sensitivity)

        guard !basal.isEmpty else {
            throw LoopError.configurationError(.basalRateSchedule)
        }
        let basalWithOverrides = overrides.applyBasal(over: basal)

        guard !carbRatio.isEmpty else {
            throw LoopError.configurationError(.carbRatioSchedule)
        }
        let carbRatioWithOverrides = overrides.applyCarbRatio(over: carbRatio)

        let carbModel: CarbAbsorptionModel = FeatureFlags.nonlinearCarbModelEnabled ? .piecewiseLinear : .linear

        // Overlay basal history on basal doses, splitting doses to get amount delivered relative to basal
        let annotatedDoses = doses.annotated(with: basalWithOverrides)

        let insulinEffects = annotatedDoses.glucoseEffects(
            insulinSensitivityHistory: sensitivityWithOverrides,
            from: start.addingTimeInterval(-CarbMath.maximumAbsorptionTimeInterval).dateFlooredToTimeInterval(GlucoseMath.defaultDelta),
            to: nil)

        // ICE
        let insulinCounteractionEffects = glucose.counteractionEffects(to: insulinEffects)

        // Carb Effects
        let carbStatus = carbEntries.map(
            to: insulinCounteractionEffects,
            carbRatio: carbRatioWithOverrides,
            insulinSensitivity: sensitivityWithOverrides
        )

        let carbEffects = carbStatus.dynamicGlucoseEffects(
            from: end,
            to: end.addingTimeInterval(InsulinMath.defaultInsulinActivityDuration),
            carbRatios: carbRatioWithOverrides,
            insulinSensitivities: sensitivityWithOverrides,
            absorptionModel: carbModel.model
        )

        return CarbAbsorptionReview(
            carbEntries: carbEntries,
            carbStatuses: carbStatus,
            effectsVelocities: insulinCounteractionEffects,
            carbEffects: carbEffects
        )
    }
}
